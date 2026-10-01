import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray

ShellRoot {
    id: root
    property Theme theme: Theme {}
    property var outputs: []
    readonly property bool backendAvailable: socket.connected
    property bool scratchpadVisible: false
    property bool scratchpadOccupied: false
    property var notifications: []
    property var toastNotifications: []
    property var closedNotificationIds: []
    property string clockText: clock.date.toLocaleString(Qt.locale("de_DE"), "ddd dd. MMM  HH:mm")
    SystemClock { id: clock; precision: SystemClock.Minutes }
    property var sink: Pipewire.defaultAudioSink
    property var audio: sink ? sink.audio : null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    function setVolume(value: real): void {
        if (audio) { audio.volume = Math.max(0, Math.min(1, value)); audio.muted = false; }
    }
    function toggleMute(): void { if (audio) audio.muted = !audio.muted; }
    function send(command: string): void {
        if (socket.connected) {
            socket.write("v1 " + command + "\n");
            socket.flush();
            return;
        }
    }
    function outputFor(screen): var {
        return outputs.find(o => o.id === screen.name || (o.x === screen.x && o.y === screen.y)) || null;
    }
    // Quickshell destroys a notification object once it is closed, which leaves
    // null entries in the JS arrays; drop those along with the requested one.
    function removeNotification(notification): void {
        const keep = item => item && (!notification || item.id !== notification.id);
        toastNotifications = toastNotifications.filter(keep);
        notifications = notifications.filter(keep);
    }
    function markNotificationClosed(notification): void {
        if (!closedNotificationIds.includes(notification.id))
            closedNotificationIds = closedNotificationIds.concat([notification.id]);
    }
    function dismissNotification(notification): void {
        if (!notification) { removeNotification(null); return; }
        const alreadyClosed = closedNotificationIds.includes(notification.id);
        removeNotification(notification);
        if (!alreadyClosed) notification.dismiss();
    }
    function clearNotifications(): void {
        const current = notifications.slice();
        notifications = [];
        toastNotifications = [];
        for (const notification of current) {
            if (notification && !closedNotificationIds.includes(notification.id)) notification.dismiss();
        }
        closedNotificationIds = [];
    }

    NotificationServer {
        id: notificationServer
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: notification => {
            notification.tracked = true;
            root.closedNotificationIds = root.closedNotificationIds.filter(id => id !== notification.id);
            notification.closed.connect(() => {
                root.markNotificationClosed(notification);
                root.removeNotification(notification);
            });
            root.notifications = [notification].concat(root.notifications.filter(item => item && item.id !== notification.id));
            root.toastNotifications = [notification].concat(root.toastNotifications.filter(item => item && item.id !== notification.id)).slice(0, 4);
        }
    }
    Socket {
        id: socket
        path: Quickshell.env("MYWM_SOCKET") || ""
        connected: path !== ""
        onConnectedChanged: if (!connected) {
            root.outputs = [];
            root.scratchpadVisible = false;
            root.scratchpadOccupied = false;
        }
        parser: SplitParser {
            onRead: data => {
                const parts = data.trim().split(" ");
                if (parts[0] === "v1" && parts[1] === "scratchpad") {
                    root.scratchpadVisible = parts[2] === "1";
                    root.scratchpadOccupied = parts[3] === "1";
                    return;
                }
                if (parts[0] !== "v1" || parts[1] !== "state") return;
                // Per output: id,x,y,width,height,active,left,right,"number:occupied|..." (number 0 is gaming).
                root.outputs = (parts[2] || "").split(";").filter(s => s.length).map(s => {
                    const v = s.split(",");
                    const workspaces = (v[8] || "").split("|").filter(w => w.length).map(w => {
                        const [number, occupied] = w.split(":");
                        return { number: Number(number), occupied: occupied === "1" };
                    });
                    return { id: Number(v[0]), x: Number(v[1]), y: Number(v[2]), width: Number(v[3]), height: Number(v[4]), active: Number(v[5]), canScrollLeft: v[6] === "1", canScrollRight: v[7] === "1", workspaces: workspaces };
                });
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: !socket.connected && socket.path !== ""; onTriggered: socket.connected = true }

    IpcHandler {
        target: "bar"
        function status(): string { return JSON.stringify(root.outputs); }
        function audioStatus(): string { return JSON.stringify(root.audio ? {volume: root.audio.volume, muted: root.audio.muted} : null); }
        function notificationCount(): int { return root.notifications.length; }
        function dismissNotification(index: int): void {
            if (index >= 0 && index < root.notifications.length)
                root.dismissNotification(root.notifications[index]);
        }
        function clearNotifications(): void { root.clearNotifications(); }
        function volume(value: real): void { root.setVolume(value); }
        function mute(): void { root.toggleMute(); }
        function workspace(output: string, number: int): void { root.send("workspace " + output + " " + number); }
        function panel(index: int, name: string): void {
            if (index >= 0 && index < bars.instances.length && ["", "audio", "calendar", "media", "notifications"].includes(name)) bars.instances[index].activePanel = name;
        }
        function menu(index: int): void { bars.instances[index].menuOpen = true; }
        function choosePower(index: int, action: string): void { bars.instances[index].choosePower(action); }
    }
    Variants {
        id: bars
        model: Quickshell.screens
        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            property var output: root.outputFor(modelData)
            readonly property var activePlayer: Mpris.players.values.find(player => player.isPlaying) || null
            property bool menuOpen: false
            property string activePanel: ""
            property var trayMenu: null
            property string trayMenuTitle: ""
            onMenuOpenChanged: {
                if (menuOpen) {
                    activePanel = "";
                    trayMenu = null;
                } else {
                    powerCountdown.stop();
                    powerCountdownAnimation.stop();
                    pending = "";
                    countdownProgress = 1;
                }
            }
            onActivePanelChanged: if (activePanel) { menuOpen = false; trayMenu = null; }
            property string pending: ""
            property string errorText: ""
            property real countdownProgress: 1
            readonly property var powerActions: ({
                logout: { title: "Abmelden", icon: "󰍃" },
                reboot: { title: "Neu starten", icon: "󰜉" },
                poweroff: { title: "Ausschalten", icon: "⏻" }
            })
            function choosePower(action: string): void {
                if (!["logout", "reboot", "poweroff"].includes(action)) return;
                pending = action;
                errorText = "";
                countdownProgress = 1;
                menuOpen = true;
                powerCountdown.restart();
                powerCountdownAnimation.restart();
            }
            function cancelPower(): void {
                powerCountdown.stop();
                powerCountdownAnimation.stop();
                pending = "";
                errorText = "";
                menuOpen = false;
                countdownProgress = 1;
            }
            function executePower(): void {
                if (powerProcess.running || !menuOpen || !pending) return;
                powerCountdown.stop();
                powerCountdownAnimation.stop();
                countdownProgress = 0;
                if (pending === "logout") {
                    root.send("logout");
                    menuOpen = false;
                } else if (["reboot", "poweroff"].includes(pending)) {
                    powerProcess.command = ["systemctl", pending];
                    powerProcess.running = true;
                }
            }
            Timer {
                id: powerCountdown
                interval: 5000
                onTriggered: bar.executePower()
            }
            NumberAnimation {
                id: powerCountdownAnimation
                target: bar
                property: "countdownProgress"
                from: 1
                to: 0
                duration: 5000
                easing.type: Easing.Linear
            }
            function openTrayMenu(item): void {
                if (!item.hasMenu || !item.menu) return;
                activePanel = "";
                menuOpen = false;
                trayMenuTitle = item.title || item.id || "Anwendung";
                trayMenu = item.menu;
            }
            anchors { top: true; left: true; right: true }
            implicitHeight: root.theme.barHeight
            exclusiveZone: root.theme.barHeight
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "mywm-bar"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            readonly property bool hasTrayItems: SystemTray.items.values.some(item => item.status !== Status.Passive)

            PanelWindow {
                visible: bar.output !== null && bar.output.canScrollLeft
                screen: bar.screen
                anchors { top: true; bottom: true; left: true }
                implicitWidth: 5
                exclusiveZone: 5
                color: root.theme.accentColor
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "mywm-window-marker-left"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            }
            PanelWindow {
                visible: bar.output !== null && bar.output.canScrollRight
                screen: bar.screen
                anchors { top: true; bottom: true; right: true }
                implicitWidth: 5
                exclusiveZone: 5
                color: root.theme.accentColor
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "mywm-window-marker-right"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            }

            BarIsland {
                theme: root.theme
                x: 8; y: root.theme.barMargin
                Repeater {
                    model: bar.output ? bar.output.workspaces : []
                    BarButton {
                        required property var modelData
                        theme: root.theme
                        width: 26
                        text: modelData.number === 0 ? "G" : String(modelData.number)
                        enabled: bar.output !== null
                        selected: bar.output !== null && bar.output.active === modelData.number
                        marked: modelData.occupied
                        onClicked: root.send("workspace " + bar.output.id + " " + modelData.number)
                    }
                }
                BarButton {
                    width: 26
                    theme: root.theme
                    text: "+"
                    enabled: bar.output !== null
                    onClicked: root.send("new-workspace " + bar.output.id)
                }
                BarButton {
                    width: 26
                    theme: root.theme
                    text: "S"
                    visible: root.scratchpadOccupied
                    selected: root.scratchpadVisible
                    marked: root.scratchpadOccupied
                    onClicked: root.send("scratchpad")
                }
            }
            BarIsland {
                theme: root.theme
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.theme.barMargin
                BarButton {
                    visible: bar.activePlayer !== null
                    width: visible ? Math.min(260, bar.width * 0.24) : 0
                    theme: root.theme
                    text: bar.activePlayer ? "󰎆 " + (bar.activePlayer.trackTitle || bar.activePlayer.identity) : ""
                    selected: bar.activePanel === "media"
                    onClicked: bar.activePanel = selected ? "" : "media"
                }
                BarButton {
                    theme: root.theme
                    text: root.clockText
                    selected: bar.activePanel === "calendar"
                    onClicked: bar.activePanel = selected ? "" : "calendar"
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8
                y: root.theme.barMargin
                spacing: 8
                // Tray icons belong to other applications; the shell's own status sits apart.
                BarIsland {
                    theme: root.theme
                    visible: bar.hasTrayItems
                    Repeater {
                        model: SystemTray.items
                        Rectangle {
                            id: trayIcon
                            required property var modelData
                            width: visible ? 26 : 0; height: 26; radius: 13
                            visible: modelData.status !== Status.Passive
                            color: trayMouse.containsMouse ? root.theme.surfaceColor : "transparent"
                            border.width: modelData.status === Status.NeedsAttention ? 1 : 0
                            border.color: root.theme.accentColor
                            Image { anchors.centerIn: parent; width: 18; height: 18; source: trayIcon.modelData.icon }
                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent; hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: event => {
                                    if (event.button === Qt.MiddleButton) trayIcon.modelData.secondaryActivate();
                                    else if (event.button === Qt.RightButton || trayIcon.modelData.onlyMenu) {
                                        bar.openTrayMenu(trayIcon.modelData);
                                    } else trayIcon.modelData.activate();
                                }
                                onWheel: event => trayIcon.modelData.scroll(event.angleDelta.y || event.angleDelta.x, event.angleDelta.y === 0)
                            }
                        }
                    }
                }
                BarIsland {
                    theme: root.theme
                    BarButton {
                        theme: root.theme
                        text: root.notifications.length ? "󰂚 " + root.notifications.length : "󰂜"
                        selected: bar.activePanel === "notifications"
                        onClicked: bar.activePanel = selected ? "" : "notifications"
                    }
                    BarButton {
                        theme: root.theme
                        text: !root.audio ? "󰕾 —" : root.audio.muted ? "󰖁 Stumm" : "󰕾 " + Math.round(root.audio.volume * 100) + " %"
                        selected: bar.activePanel === "audio"
                        onClicked: bar.activePanel = selected ? "" : "audio"
                        onSecondaryClicked: root.toggleMute()
                        onScrolled: delta => { if (root.audio) root.setVolume(root.audio.volume + delta * 0.05); }
                    }
                    BarButton {
                        theme: root.theme
                        text: "⏻"
                        selected: bar.menuOpen
                        onClicked: {
                            if (bar.menuOpen) bar.cancelPower();
                            else bar.menuOpen = true;
                        }
                    }
                }
            }

            Process {
                id: powerProcess
                onExited: (exitCode, exitStatus) => {
                    if (exitCode !== 0) {
                        bar.pending = "";
                        bar.errorText = "Aktion fehlgeschlagen (" + exitCode + ")";
                    }
                    else bar.menuOpen = false;
                }
            }
            PanelWindow {
                id: trayMenuWindow
                visible: bar.trayMenu !== null
                screen: bar.screen
                anchors { top: true; right: true }
                margins { top: root.theme.barHeight + 6; right: 8 }
                implicitWidth: Math.min(320, bar.screen.width - 16)
                implicitHeight: Math.min(500, trayMenuView.implicitHeight + 24)
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                WlrLayershell.namespace: "mywm-tray-menu"
                property bool gainedFocus: false
                onVisibleChanged: if (!visible) gainedFocus = false

                Rectangle {
                    id: trayMenuRoot
                    anchors.fill: parent
                    radius: root.theme.panelRadius
                    color: root.theme.glassColor
                    border.color: root.theme.glassBorderColor
                    focus: true
                    property bool windowActive: Window.active
                    onWindowActiveChanged: {
                        if (windowActive) trayMenuWindow.gainedFocus = true;
                        else if (trayMenuWindow.visible && trayMenuWindow.gainedFocus) bar.trayMenu = null;
                    }
                    Keys.onEscapePressed: bar.trayMenu = null

                    TrayMenu {
                        id: trayMenuView
                        anchors { fill: parent; margins: 12 }
                        theme: root.theme
                        menu: bar.trayMenu
                        title: bar.trayMenuTitle
                        onCloseRequested: bar.trayMenu = null
                    }
                }
            }
            PanelWindow {
                id: detailsPanel
                visible: bar.activePanel !== ""
                screen: bar.screen
                anchors {
                    top: true
                    right: bar.activePanel === "audio" || bar.activePanel === "notifications"
                }
                margins { top: root.theme.barHeight + 6; right: bar.activePanel === "audio" || bar.activePanel === "notifications" ? 8 : 0 }
                implicitWidth: Math.min(400, bar.screen.width - 24)
                implicitHeight: Math.min(Math.max(150, panelLoader.implicitHeight + 82), bar.screen.height - root.theme.barHeight - 18)
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                property bool gainedFocus: false
                onVisibleChanged: if (!visible) gainedFocus = false
                Rectangle {
                    id: detailsPanelRoot
                    anchors.fill: parent; radius: root.theme.panelRadius; color: root.theme.glassColor; border.color: root.theme.glassBorderColor
                    focus: true
                    property bool windowActive: Window.active
                    onWindowActiveChanged: {
                        if (windowActive) detailsPanel.gainedFocus = true;
                        else if (detailsPanel.visible && detailsPanel.gainedFocus) bar.activePanel = "";
                    }
                    Keys.onEscapePressed: bar.activePanel = ""
                    Column {
                        anchors.fill: parent; anchors.margins: 20; spacing: 14
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width
                                text: bar.activePanel === "audio" ? "Audio" : bar.activePanel === "media" ? "Medien" : bar.activePanel === "calendar" ? "Kalender" : "Benachrichtigungen"
                                color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 20
                            }
                        }
                        Flickable {
                            width: parent.width; height: parent.height - 42
                            contentHeight: panelLoader.height; clip: true
                            ScrollBar.vertical: ScrollBar {}
                            Loader {
                                id: panelLoader
                                width: parent.width
                                sourceComponent: bar.activePanel === "audio" ? audioPanel : bar.activePanel === "media" ? mediaPanel : bar.activePanel === "calendar" ? calendarPanel : notificationPanel
                            }
                        }
                    }
                }
                Component { id: audioPanel; AudioPanel { theme: root.theme } }
                Component { id: mediaPanel; MediaPanel { theme: root.theme } }
                Component { id: calendarPanel; CalendarPanelInteractive { theme: root.theme } }
                Component {
                    id: notificationPanel
                    NotificationCenter {
                        theme: root.theme
                        notifications: root.notifications
                        onDismiss: notification => root.dismissNotification(notification)
                        onClearAll: root.clearNotifications()
                    }
                }
            }
            PanelWindow {
                id: menu
                screen: bar.screen
                visible: bar.menuOpen
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "mywm-power"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                color: "transparent"
                property bool gainedFocus: false
                onVisibleChanged: if (!visible) gainedFocus = false
                Rectangle {
                    anchors.fill: parent
                    color: "#66000000"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: bar.cancelPower()
                }
                Rectangle {
                    id: menuRoot
                    anchors.centerIn: parent
                    width: bar.pending ? 380 : Math.min(620, menu.width - 32)
                    height: bar.pending ? 330 : 260
                    color: root.theme.glassColor; radius: 28
                    border.color: root.theme.glassBorderColor
                    focus: true
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => mouse.accepted = true
                    }
                    property bool windowActive: Window.active
                    onWindowActiveChanged: {
                        if (windowActive) menu.gainedFocus = true;
                        else if (menu.visible && menu.gainedFocus) {
                            bar.cancelPower();
                        }
                    }
                    Keys.onEscapePressed: bar.cancelPower()
                    Column {
                        anchors.fill: parent; anchors.margins: 24; spacing: 22
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: bar.pending === ""
                            text: "Sitzung und System"
                            color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 22
                        }
                        Row {
                            visible: bar.pending === ""
                            width: parent.width; spacing: 12
                            Repeater {
                                model: [{label: "Sperren", icon: "󰌾", action: "lock"}, {label: "Abmelden", icon: "󰍃", action: "logout"}, {label: "Neustart", icon: "󰜉", action: "reboot"}, {label: "Ausschalten", icon: "⏻", action: "poweroff"}]
                                Rectangle {
                                    id: powerTile
                                    required property var modelData
                                    width: (parent.width - 36) / 4; height: 112; radius: 22
                                    color: powerMouse.containsMouse || activeFocus ? root.theme.accentColor : root.theme.glassSurfaceColor
                                    activeFocusOnTab: true
                                    enabled: !["lock", "logout"].includes(modelData.action) || root.backendAvailable
                                    opacity: enabled ? 1 : 0.4
                                    function activate(): void {
                                        if (modelData.action === "lock") { root.send("lock"); bar.menuOpen = false; }
                                        else bar.choosePower(modelData.action);
                                    }
                                    Keys.onReturnPressed: activate()
                                    Keys.onSpacePressed: activate()
                                    Column {
                                        anchors.centerIn: parent; spacing: 10
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: powerTile.modelData.icon; font.family: root.theme.fontFamily; font.pixelSize: 34; color: powerMouse.containsMouse || powerTile.activeFocus ? root.theme.backgroundColor : root.theme.accentColor }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: powerTile.modelData.label; font.family: root.theme.fontFamily; font.pixelSize: 13; color: powerMouse.containsMouse || powerTile.activeFocus ? root.theme.backgroundColor : root.theme.textColor }
                                    }
                                    MouseArea { id: powerMouse; anchors.fill: parent; hoverEnabled: true; onClicked: powerTile.activate() }
                                }
                            }
                        }
                        Column {
                            visible: bar.pending !== ""
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 14
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 112; height: 112
                                Canvas {
                                    anchors.fill: parent
                                    property real progress: bar.countdownProgress
                                    onProgressChanged: requestPaint()
                                    onPaint: {
                                        const context = getContext("2d");
                                        context.reset();
                                        context.lineWidth = 5;
                                        context.lineCap = "round";
                                        context.strokeStyle = root.theme.borderColor;
                                        context.beginPath();
                                        context.arc(width / 2, height / 2, 50, 0, Math.PI * 2);
                                        context.stroke();
                                        context.strokeStyle = root.theme.accentColor;
                                        context.beginPath();
                                        context.arc(width / 2, height / 2, 50, -Math.PI / 2,
                                            -Math.PI / 2 + Math.PI * 2 * progress);
                                        context.stroke();
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 88; height: 88; radius: 44
                                    color: root.theme.surfaceColor
                                    Text {
                                        anchors.centerIn: parent
                                        text: bar.pending ? bar.powerActions[bar.pending].icon : ""
                                        color: root.theme.accentColor
                                        font.family: root.theme.fontFamily; font.pixelSize: 42
                                    }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: bar.pending ? bar.powerActions[bar.pending].title : ""
                                color: root.theme.textColor
                                font.family: root.theme.fontFamily; font.pixelSize: 22; font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Automatisch in " + Math.max(1, Math.ceil(bar.countdownProgress * 5)) + " Sekunden"
                                color: root.theme.mutedColor
                                font.family: root.theme.fontFamily; font.pixelSize: 14
                            }
                            BarButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                theme: root.theme; text: "Abbrechen"; height: 40
                                onClicked: bar.cancelPower()
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: bar.pending === "" || bar.errorText !== ""
                            text: bar.errorText || "Esc zum Schließen"
                            color: root.theme.mutedColor; font.family: root.theme.fontFamily; font.pixelSize: 14
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens.length ? [Quickshell.screens[0]] : []
        PanelWindow {
            id: toastWindow
            required property var modelData
            screen: modelData
            // Translucent panels on the right would show the toasts through them; the
            // notification center lists them anyway.
            readonly property var screenBar: bars.instances.find(b => b.screen === modelData) || null
            readonly property bool rightPanelOpen: screenBar !== null && (screenBar.activePanel === "notifications" || screenBar.activePanel === "audio" || screenBar.trayMenu !== null)
            visible: root.toastNotifications.length > 0 && !rightPanelOpen
            anchors { top: true; right: true }
            margins { top: root.theme.barHeight + 6; right: 8 }
            implicitWidth: Math.min(390, screen.width - 24)
            implicitHeight: toastColumn.implicitHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "mywm-notifications"

            Column {
                id: toastColumn
                width: parent.width
                spacing: 8
                Repeater {
                    model: root.toastNotifications
                    NotificationCard {
                        id: toast
                        required property var modelData
                        width: toastColumn.width
                        notification: modelData
                        theme: root.theme
                        compact: true
                        onCloseRequested: root.dismissNotification(notification)
                        Timer {
                            readonly property int requested: toast.modelData.expireTimeout
                            interval: requested > 0 ? requested : toast.modelData.urgency === NotificationUrgency.Low ? 4000 : 7000
                            running: requested !== 0 && !toastMouse.containsMouse
                            onTriggered: {
                                // Only hide the popup; expire() would destroy the
                                // notification and break its entry in the list.
                                root.toastNotifications = root.toastNotifications.filter(item => item !== toast.modelData);
                            }
                        }
                        MouseArea {
                            id: toastMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }
            }
        }
    }
}
