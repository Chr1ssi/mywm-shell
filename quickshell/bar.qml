import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray

ShellRoot {
    id: root
    property Theme theme: Theme {}
    property var outputs: []
    // The last `v1 state` payload `outputs` was built from.
    property string layoutLine: ""
    readonly property bool backendAvailable: socket.connected
    property bool scratchpadVisible: false
    property bool scratchpadOccupied: false
    // A game is shown fullscreen: only critical notifications pop up over it; the rest wait in the list.
    property bool gaming: false
    // Something records or streams the screen or a window.
    property bool capturing: false
    // An app asked what to share; the compositor's overview is picking.
    property bool choosing: false
    // The color picker is on; the color under the pointer ("" until the compositor sampled one).
    property bool picking: false
    property string pickedColor: ""
    // Why the compositor could not load its configuration file; shown until fixed or dismissed.
    property string configError: ""
    // A warm screen (gammastep through the compositor's gamma control); kept across logins.
    property bool nightLight: false
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property string controlIcon: {
        const icons = [];
        if (bluetoothAdapter && bluetoothAdapter.enabled)
            icons.push(bluetoothAdapter.devices.values.some(device => device.connected) ? "󰂱" : "󰂯");
        if (nightLight) icons.push("󰖔");
        return icons.length ? icons.join(" ") : "󰒓";
    }
    function setNightLight(on: bool): void {
        nightLight = on;
        nightLightFile.setText(on ? "1\n" : "0\n");
    }
    property string dismissedConfigError: ""
    readonly property bool showConfigError: configError !== "" && configError !== dismissedConfigError
    onGamingChanged: if (gaming) toastNotifications = toastNotifications.filter(n => n && n.urgency === NotificationUrgency.Critical)
    property var notifications: []
    property var toastNotifications: []
    property var closedNotificationIds: []
    property string clockText: clock.date.toLocaleString(Qt.locale(), "ddd dd. MMM  HH:mm")
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
            if (!root.gaming || notification.urgency === NotificationUrgency.Critical)
                root.toastNotifications = [notification].concat(root.toastNotifications.filter(item => item && item.id !== notification.id)).slice(0, 4);
        }
    }
    FileView {
        id: nightLightFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/mywm/night-light"
        printErrors: false
        onLoaded: root.nightLight = text().trim() === "1"
    }
    Process {
        id: nightLightProcess
        // One-shot mode keeps running on Wayland: the warm ramp lasts as long as the process.
        command: ["gammastep", "-m", "wayland", "-O", "4000"]
        running: root.nightLight
        onExited: (exitCode, exitStatus) => {
            if (!root.nightLight) return;
            // Not switched off: it failed (no gamma control). The saved choice stays for the next login.
            console.warn("night light: gammastep exited with " + exitCode);
            root.nightLight = false;
        }
    }
    Socket {
        id: socket
        path: Quickshell.env("MYWM_SOCKET") || ""
        connected: path !== ""
        onConnectedChanged: if (connected) {
            // From now on the exit binding asks here instead of ending the session at once.
            root.send("handle-logout");
        } else {
            root.outputs = [];
            root.scratchpadVisible = false;
            root.scratchpadOccupied = false;
            root.gaming = false;
            root.capturing = false;
            root.choosing = false;
            root.picking = false;
            root.configError = "";
        }
        parser: SplitParser {
            onRead: data => {
                const parts = data.trim().split(" ");
                if (parts[0] === "v1" && parts[1] === "scratchpad") {
                    root.scratchpadVisible = parts[2] === "1";
                    root.scratchpadOccupied = parts[3] === "1";
                    return;
                }
                if (parts[0] === "v1" && parts[1] === "config") {
                    root.configError = parts[2] === "error" ? parts.slice(3).join(" ") : "";
                    return;
                }
                if (parts[0] === "v1" && parts[1] === "picking") {
                    root.picking = parts[2] === "1";
                    root.pickedColor = root.picking ? (parts[3] || "") : "";
                    return;
                }
                if (parts[0] === "v1" && parts[1] === "choosing") {
                    root.choosing = parts[2] === "1";
                    return;
                }
                if (parts[0] === "v1" && parts[1] === "capture") {
                    root.capturing = parts[2] === "1";
                    return;
                }
                if (parts[0] === "v1" && parts[1] === "gaming") {
                    root.gaming = parts[2] === "1";
                    return;
                }
                if (parts[0] === "v1" && parts[1] === "confirm-logout") {
                    const index = bars.instances.findIndex(b => b.output && b.output.id === Number(parts[2]));
                    if (bars.instances.length) bars.instances[Math.max(0, index)].choosePower("logout");
                    return;
                }
                if (parts[0] !== "v1" || parts[1] !== "state") return;
                // The compositor resends its whole snapshot when any line of it changes; an unchanged
                // layout must not rebuild the workspace buttons of every bar.
                const layout = parts[2] || "";
                if (layout === root.layoutLine && root.outputs.length) return;
                root.layoutLine = layout;
                // Per output: id,x,y,width,height,active,left,right,"number:occupied|..." (number 0 is gaming).
                root.outputs = layout.split(";").filter(s => s.length).map(s => {
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
        function audioInputs(index: int): string {
            const panel = index >= 0 && index < bars.instances.length ? bars.instances[index].panelItem : null;
            return JSON.stringify(panel && panel.inputs ? panel.inputs.map(node => node.name).sort() : null);
        }
        function notificationCount(): int { return root.notifications.length; }
        function toastCount(): int { return root.toastNotifications.length; }
        function configError(): string { return root.showConfigError ? root.configError : ""; }
        function capturing(): bool { return root.capturing; }
        function choosing(): bool { return root.choosing; }
        function pickedColor(): string { return root.picking ? root.pickedColor || "…" : ""; }
        function nightLight(): bool { return root.nightLight; }
        function setNightLight(on: bool): void { root.setNightLight(on); }
        function dismissNotification(index: int): void {
            if (index >= 0 && index < root.notifications.length)
                root.dismissNotification(root.notifications[index]);
        }
        function clearNotifications(): void { root.clearNotifications(); }
        function volume(value: real): void { root.setVolume(value); }
        function mute(): void { root.toggleMute(); }
        function workspace(output: string, number: int): void { root.send("workspace " + output + " " + number); }
        function panel(index: int, name: string): void {
            if (index >= 0 && index < bars.instances.length && ["", "audio", "calendar", "control", "media", "notifications"].includes(name)) bars.instances[index].activePanel = name;
        }
        function menu(index: int): void { bars.instances[index].menuOpen = true; }
        function choosePower(index: int, action: string): void { bars.instances[index].choosePower(action); }
        function powerPending(): string { return bars.instances.map(b => b.pending).find(p => p) || ""; }
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
            readonly property var panelItem: panelLoader.item
            // Panels of the right-hand buttons open under them; the others in the middle.
            readonly property bool panelOnRight: ["audio", "control", "notifications"].includes(activePanel)
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
                logout: { title: I18n.tr("Abmelden"), icon: "󰍃" },
                reboot: { title: I18n.tr("Neu starten"), icon: "󰜉" },
                poweroff: { title: I18n.tr("Ausschalten"), icon: "⏻" }
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
                trayMenuTitle = item.title || item.id || I18n.tr("Anwendung");
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
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.theme.barMargin
                spacing: 8
                BarIsland {
                    theme: root.theme
                    visible: bar.activePlayer !== null
                    BarButton {
                        width: Math.min(260, bar.width * 0.24)
                        theme: root.theme
                        text: bar.activePlayer ? "󰎆 " + (bar.activePlayer.trackTitle || bar.activePlayer.identity) : ""
                        selected: bar.activePanel === "media"
                        onClicked: bar.activePanel = selected ? "" : "media"
                    }
                }
                BarIsland {
                    theme: root.theme
                    BarButton {
                        theme: root.theme
                        text: root.clockText
                        selected: bar.activePanel === "calendar"
                        onClicked: bar.activePanel = selected ? "" : "calendar"
                    }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8
                y: root.theme.barMargin
                spacing: 8
                BarIsland {
                    theme: root.theme
                    visible: root.capturing
                    Text {
                        height: 26
                        leftPadding: 8; rightPadding: 8
                        verticalAlignment: Text.AlignVCenter
                        text: "󰑊 " + I18n.tr("Aufnahme")
                        color: root.theme.alertColor
                        font.family: root.theme.fontFamily; font.pixelSize: 14; font.bold: true
                    }
                }
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
                            Image { anchors.centerIn: parent; width: 18; height: 18; sourceSize.width: 18; sourceSize.height: 18; source: trayIcon.modelData.icon }
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
                        text: root.controlIcon
                        fontFamily: root.theme.iconFontFamily
                        selected: bar.activePanel === "control"
                        onClicked: bar.activePanel = selected ? "" : "control"
                    }
                    BarButton {
                        theme: root.theme
                        text: root.notifications.length ? "󰂚 " + root.notifications.length : "󰂜"
                        selected: bar.activePanel === "notifications"
                        onClicked: bar.activePanel = selected ? "" : "notifications"
                    }
                    BarButton {
                        theme: root.theme
                        text: !root.audio ? "󰕾 —" : root.audio.muted ? "󰖁 " + I18n.tr("Stumm") : "󰕾 " + Math.round(root.audio.volume * 100) + " %"
                        selected: bar.activePanel === "audio"
                        onClicked: bar.activePanel = selected ? "" : "audio"
                        onSecondaryClicked: root.toggleMute()
                        onScrolled: delta => { if (root.audio) root.setVolume(root.audio.volume + delta * 0.05); }
                    }
                }
                BarIsland {
                    theme: root.theme
                    BarButton {
                        theme: root.theme
                        text: "⏻"
                        fontFamily: root.theme.iconFontFamily
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
                        bar.errorText = I18n.tr("Aktion fehlgeschlagen (%1)", exitCode);
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
                    right: bar.panelOnRight
                }
                margins { top: root.theme.barHeight + 6; right: bar.panelOnRight ? 8 : 0 }
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
                                text: bar.activePanel === "audio" ? "Audio" : bar.activePanel === "control" ? I18n.tr("Commandcenter") : bar.activePanel === "media" ? I18n.tr("Medien") : bar.activePanel === "calendar" ? I18n.tr("Kalender") : I18n.tr("Benachrichtigungen")
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
                                // Closed, no panel stays loaded (the notification list would follow every notification on every monitor).
                                active: bar.activePanel !== ""
                                sourceComponent: bar.activePanel === "audio" ? audioPanel : bar.activePanel === "control" ? controlPanel : bar.activePanel === "media" ? mediaPanel : bar.activePanel === "calendar" ? calendarPanel : notificationPanel
                            }
                        }
                    }
                }
                Component { id: audioPanel; AudioPanel { theme: root.theme } }
                Component {
                    id: controlPanel
                    CommandCenter {
                        theme: root.theme
                        nightLight: root.nightLight
                        onNightLightToggled: root.setNightLight(!root.nightLight)
                    }
                }
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
                // Opened by the exit binding it must take the keyboard at once, or Esc could not stop the countdown.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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
                    Keys.onReturnPressed: if (bar.pending) bar.executePower()
                    Keys.onEnterPressed: if (bar.pending) bar.executePower()
                    Column {
                        anchors.fill: parent; anchors.margins: 24; spacing: 22
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: bar.pending === ""
                            text: I18n.tr("Sitzung und System")
                            color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 22
                        }
                        Row {
                            visible: bar.pending === ""
                            width: parent.width; spacing: 12
                            Repeater {
                                model: [{label: I18n.tr("Sperren"), icon: "󰌾", action: "lock"}, {label: I18n.tr("Abmelden"), icon: "󰍃", action: "logout"}, {label: I18n.tr("Neustart"), icon: "󰜉", action: "reboot"}, {label: I18n.tr("Ausschalten"), icon: "⏻", action: "poweroff"}]
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
                                text: I18n.tr("Automatisch in %1 Sekunden", Math.max(1, Math.ceil(bar.countdownProgress * 5)))
                                color: root.theme.mutedColor
                                font.family: root.theme.fontFamily; font.pixelSize: 14
                            }
                            BarButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                theme: root.theme; text: I18n.tr("Abbrechen"); height: 40
                                onClicked: bar.cancelPower()
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: bar.pending === "" || bar.errorText !== ""
                            text: bar.errorText || I18n.tr("Esc zum Schließen")
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
            visible: (root.toastNotifications.length > 0 || root.showConfigError || root.choosing || root.picking) && !rightPanelOpen
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
                Rectangle {
                    visible: root.choosing
                    width: toastColumn.width
                    implicitHeight: chooseText.implicitHeight + 24
                    radius: 18
                    color: root.theme.glassColor
                    border.width: 2
                    border.color: root.theme.alertColor
                    Column {
                        id: chooseText
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 4
                        Text {
                            text: "󰑊 " + I18n.tr("Was soll geteilt werden?")
                            color: root.theme.textColor
                            font.family: root.theme.fontFamily; font.pixelSize: 15; font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr("Fenster anklicken · Kachel daneben oder Enter: ganzer Monitor · D: dynamisch, mit den Cast-Tasten umschaltbar · Esc: abbrechen")
                            wrapMode: Text.Wrap
                            color: root.theme.textColor
                            font.family: root.theme.fontFamily; font.pixelSize: 13
                        }
                    }
                }
                Rectangle {
                    visible: root.picking
                    width: toastColumn.width
                    implicitHeight: 72
                    radius: 18
                    color: root.theme.glassColor
                    border.width: 1
                    border.color: root.theme.glassBorderColor
                    Rectangle {
                        id: pickedSwatch
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 48; height: 48; radius: 12
                        color: root.pickedColor || "transparent"
                        border.width: 1
                        border.color: root.theme.borderColor
                    }
                    Column {
                        anchors { left: pickedSwatch.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Text {
                            text: "󰈊 " + (root.pickedColor || I18n.tr("Farbpipette"))
                            color: root.theme.textColor
                            font.family: root.theme.fontFamily; font.pixelSize: 15; font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr("Klick kopiert die Farbe · Esc: abbrechen")
                            wrapMode: Text.Wrap
                            color: root.theme.mutedColor
                            font.family: root.theme.fontFamily; font.pixelSize: 13
                        }
                    }
                }
                Rectangle {
                    visible: root.showConfigError
                    width: toastColumn.width
                    implicitHeight: configText.implicitHeight + 24
                    radius: 18
                    color: root.theme.glassColor
                    border.width: 2
                    border.color: root.theme.accentColor
                    Column {
                        id: configText
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 4
                        Row {
                            width: parent.width
                            spacing: 8
                            Text {
                                width: parent.width - configClose.width - 8
                                text: I18n.tr("Konfiguration fehlerhaft")
                                color: root.theme.textColor
                                font.family: root.theme.fontFamily; font.pixelSize: 15; font.bold: true
                            }
                            BarButton {
                                id: configClose
                                theme: root.theme; text: "×"; width: 24
                                onClicked: root.dismissedConfigError = root.configError
                            }
                        }
                        Text {
                            width: parent.width
                            text: root.configError
                            wrapMode: Text.Wrap
                            color: root.theme.textColor
                            font.family: root.theme.fontFamily; font.pixelSize: 14
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr("Bis zur Korrektur gilt die zuletzt geladene Konfiguration, beim Start die Standardwerte.")
                            wrapMode: Text.Wrap
                            color: root.theme.mutedColor
                            font.family: root.theme.fontFamily; font.pixelSize: 12
                        }
                    }
                }
                Repeater {
                    // Keeps the cards (and their timers) of toasts that stay when another one comes or goes.
                    model: ScriptModel { values: root.toastNotifications }
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
