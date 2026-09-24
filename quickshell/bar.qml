import QtQuick
import QtQuick.Controls
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
    property int workspaceCount: 9
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
        if (socket.connected) { socket.write("v1 " + command + "\n"); socket.flush(); }
    }
    function outputFor(screen): var {
        return outputs.find(o => o.x === screen.x && o.y === screen.y) || null;
    }
    function removeNotification(notification): void {
        toastNotifications = toastNotifications.filter(item => item !== notification);
        notifications = notifications.filter(item => item !== notification);
    }
    function markNotificationClosed(notification): void {
        if (!closedNotificationIds.includes(notification.id))
            closedNotificationIds = closedNotificationIds.concat([notification.id]);
    }
    function dismissNotification(notification): void {
        const alreadyClosed = closedNotificationIds.includes(notification.id);
        removeNotification(notification);
        if (!alreadyClosed) notification.dismiss();
    }
    function clearNotifications(): void {
        const current = notifications.slice();
        notifications = [];
        toastNotifications = [];
        for (const notification of current) {
            if (!closedNotificationIds.includes(notification.id)) notification.dismiss();
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
            notification.closed.connect(() => root.markNotificationClosed(notification));
            root.notifications = [notification].concat(root.notifications.filter(item => item.id !== notification.id));
            root.toastNotifications = [notification].concat(root.toastNotifications.filter(item => item.id !== notification.id)).slice(0, 4);
        }
    }
    Socket {
        id: socket
        path: Quickshell.env("MYWM_SOCKET") || ""
        connected: path !== ""
        onConnectedChanged: if (!connected) root.outputs = []
        parser: SplitParser {
            onRead: data => {
                const parts = data.trim().split(" ");
                if (parts[0] !== "v1" || parts[1] !== "state") return;
                root.workspaceCount = Number(parts[2]);
                root.outputs = (parts[3] || "").split(";").filter(s => s.length).map(s => {
                    const v = s.split(",").map(Number);
                    return { id: v[0], x: v[1], y: v[2], width: v[3], height: v[4], active: v[5], occupied: v[6], workspaces: Array.from({length: root.workspaceCount}, (_, i) => i + 1).filter(n => (v.length < 8 || (v[7] & (1 << (n - 1))) !== 0)) };
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
        function clearNotifications(): void { root.clearNotifications(); }
        function volume(value: real): void { root.setVolume(value); }
        function mute(): void { root.toggleMute(); }
        function workspace(output: string, number: int): void { root.send("workspace " + output + " " + number); }
        function panel(index: int, name: string): void {
            if (index >= 0 && index < bars.instances.length && ["", "audio", "media", "notifications"].includes(name)) bars.instances[index].activePanel = name;
        }
        function menu(index: int): void { bars.instances[index].menuOpen = true; }
        function choosePower(index: int, action: string): void { bars.instances[index].choosePower(action); }
        function confirmPower(index: int): void { bars.instances[index].confirmPower(); }
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
            onMenuOpenChanged: if (menuOpen) { activePanel = ""; trayMenu = null; }
            onActivePanelChanged: if (activePanel) { menuOpen = false; trayMenu = null; }
            property string pending: ""
            property string errorText: ""
            function choosePower(action: string): void {
                if (["logout", "reboot", "poweroff"].includes(action)) { pending = action; menuOpen = true; }
            }
            function confirmPower(): void {
                if (powerProcess.running || !menuOpen) return;
                if (pending === "logout") { root.send("logout"); menuOpen = false; }
                else if (["reboot", "poweroff"].includes(pending)) {
                    powerProcess.command = ["systemctl", pending]; powerProcess.running = true;
                }
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
            color: root.theme.backgroundColor
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "mywm-bar"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Row {
                anchors.left: parent.left; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater {
                    model: bar.output ? bar.output.workspaces : []
                    BarButton {
                        required property int modelData
                        theme: root.theme
                        width: 24
                        text: String(modelData)
                        enabled: bar.output !== null
                        selected: bar.output !== null && bar.output.active === modelData
                        marked: bar.output !== null && (bar.output.occupied & (1 << (modelData - 1))) !== 0
                        onClicked: root.send("workspace " + bar.output.id + " " + modelData)
                    }
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: 8

                BarButton {
                    visible: bar.activePlayer !== null
                    width: visible ? Math.min(260, bar.width * 0.24) : 0
                    theme: root.theme
                    text: bar.activePlayer ? "󰎆 " + (bar.activePlayer.trackTitle || bar.activePlayer.identity) : ""
                    selected: bar.activePanel === "media"
                    onClicked: bar.activePanel = selected ? "" : "media"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.clockText
                    color: root.theme.textColor
                    font.family: root.theme.fontFamily; font.pixelSize: 12
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Repeater {
                    model: SystemTray.items
                    Rectangle {
                        id: trayIcon
                        required property var modelData
                        width: visible ? 24 : 0; height: 24; radius: 6
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
                    onClicked: { bar.pending = ""; bar.errorText = ""; bar.menuOpen = !bar.menuOpen; }
                }
            }

            Process {
                id: powerProcess
                onExited: (exitCode, exitStatus) => {
                    if (exitCode !== 0) bar.errorText = "Aktion fehlgeschlagen (" + exitCode + ")";
                    else bar.menuOpen = false;
                }
            }
            PanelWindow {
                visible: bar.trayMenu !== null
                screen: bar.screen
                anchors { top: true; right: true }
                margins { top: root.theme.barHeight + 8; right: 8 }
                implicitWidth: Math.min(320, bar.screen.width - 16)
                implicitHeight: Math.min(500, trayMenuView.implicitHeight + 24)
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.namespace: "mywm-tray-menu"

                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: root.theme.backgroundColor
                    border.color: root.theme.borderColor
                    focus: true
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
                visible: bar.activePanel !== ""
                screen: bar.screen
                anchors {
                    top: true
                    right: bar.activePanel === "audio" || bar.activePanel === "notifications"
                }
                margins { top: root.theme.barHeight + 12; right: bar.activePanel === "audio" || bar.activePanel === "notifications" ? 12 : 0 }
                implicitWidth: Math.min(400, bar.screen.width - 24)
                implicitHeight: Math.min(Math.max(150, panelLoader.implicitHeight + 82), bar.screen.height - root.theme.barHeight - 24)
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                Rectangle {
                    anchors.fill: parent; radius: 18; color: root.theme.backgroundColor; border.color: root.theme.borderColor
                    focus: true
                    Keys.onEscapePressed: bar.activePanel = ""
                    Column {
                        anchors.fill: parent; anchors.margins: 20; spacing: 14
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - 40
                                text: bar.activePanel === "audio" ? "Audio" : bar.activePanel === "media" ? "Medien" : "Benachrichtigungen"
                                color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 18
                            }
                            BarButton { theme: root.theme; text: "×"; onClicked: bar.activePanel = "" }
                        }
                        Flickable {
                            width: parent.width; height: parent.height - 42
                            contentHeight: panelLoader.height; clip: true
                            ScrollBar.vertical: ScrollBar {}
                            Loader {
                                id: panelLoader
                                width: parent.width
                                sourceComponent: bar.activePanel === "audio" ? audioPanel : bar.activePanel === "media" ? mediaPanel : notificationPanel
                            }
                        }
                    }
                }
                Component { id: audioPanel; AudioPanel { theme: root.theme } }
                Component { id: mediaPanel; MediaPanel { theme: root.theme } }
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
                implicitWidth: Math.min(620, bar.screen.width - 32)
                implicitHeight: 260
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "mywm-power"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                color: "transparent"
                Rectangle {
                    anchors.fill: parent; color: root.theme.backgroundColor; radius: 24
                    border.color: root.theme.borderColor
                    focus: true
                    Keys.onEscapePressed: { bar.menuOpen = false; bar.pending = ""; }
                    Column {
                        anchors.fill: parent; anchors.margins: 24; spacing: 22
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: bar.pending ? ({logout: "Abmelden?", reboot: "Neu starten?", poweroff: "Ausschalten?"})[bar.pending] : "Sitzung und System"
                            color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 20
                        }
                        Row {
                            visible: bar.pending === ""
                            width: parent.width; spacing: 12
                            Repeater {
                                model: [{label: "Sperren", icon: "󰌾", action: "lock"}, {label: "Abmelden", icon: "󰍃", action: "logout"}, {label: "Neustart", icon: "󰜉", action: "reboot"}, {label: "Ausschalten", icon: "⏻", action: "poweroff"}]
                                Rectangle {
                                    id: powerTile
                                    required property var modelData
                                    width: (parent.width - 36) / 4; height: 112; radius: 18
                                    color: powerMouse.containsMouse || activeFocus ? root.theme.accentColor : root.theme.surfaceColor
                                    activeFocusOnTab: true
                                    enabled: !["lock", "logout"].includes(modelData.action) || socket.connected
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
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: powerTile.modelData.label; font.family: root.theme.fontFamily; font.pixelSize: 11; color: powerMouse.containsMouse || powerTile.activeFocus ? root.theme.backgroundColor : root.theme.textColor }
                                    }
                                    MouseArea { id: powerMouse; anchors.fill: parent; hoverEnabled: true; onClicked: powerTile.activate() }
                                }
                            }
                        }
                        Row {
                            visible: bar.pending !== ""; anchors.horizontalCenter: parent.horizontalCenter; spacing: 20
                            BarButton { theme: root.theme; text: "Abbrechen"; height: 44; onClicked: { bar.pending = ""; bar.errorText = ""; } }
                            BarButton { theme: root.theme; text: "Bestätigen"; height: 44; selected: true; enabled: !powerProcess.running && (bar.pending !== "logout" || socket.connected); onClicked: bar.confirmPower() }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: bar.errorText || "Esc zum Schließen"; color: root.theme.mutedColor; font.family: root.theme.fontFamily; font.pixelSize: 12 }
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
            visible: root.toastNotifications.length > 0
            anchors { top: true; right: true }
            margins { top: root.theme.barHeight + 12; right: 12 }
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
                        onCloseRequested: root.dismissNotification(modelData)
                        Timer {
                            readonly property int requested: toast.modelData.expireTimeout
                            interval: requested > 0 ? requested : toast.modelData.urgency === NotificationUrgency.Low ? 4000 : 7000
                            running: requested !== 0 && !toastMouse.containsMouse
                            onTriggered: {
                                toast.modelData.expire();
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
