import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

ShellRoot {
    id: root
    property Theme theme: Theme {}
    property var outputs: []
    property int workspaceCount: 9
    property string clockText: clock.date.toLocaleString(Qt.locale("de_DE"), "ddd, dd.MM.yyyy  ·  HH:mm")
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
        function volume(value: real): void { root.setVolume(value); }
        function mute(): void { root.toggleMute(); }
        function workspace(output: string, number: int): void { root.send("workspace " + output + " " + number); }
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
            property bool menuOpen: false
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
            anchors { top: true; left: true; right: true }
            implicitHeight: 36
            exclusiveZone: 36
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
                        width: 28
                        text: String(modelData)
                        enabled: bar.output !== null
                        selected: bar.output !== null && bar.output.active === modelData
                        marked: bar.output !== null && (bar.output.occupied & (1 << (modelData - 1))) !== 0
                        onClicked: root.send("workspace " + bar.output.id + " " + modelData)
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: root.clockText
                color: root.theme.textColor
                font.pixelSize: 14
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                BarButton {
                    theme: root.theme
                    text: !root.audio ? "Audio —" : root.audio.muted ? "Stumm" : Math.round(root.audio.volume * 100) + " %"
                    enabled: root.audio !== null
                    onClicked: root.toggleMute()
                }
                Slider {
                    id: volume
                    width: 110; height: 28
                    from: 0; to: 1
                    enabled: root.audio !== null
                    value: root.audio ? root.audio.volume : 0
                    onMoved: root.setVolume(value)
                    background: Rectangle {
                        x: volume.leftPadding; y: volume.topPadding + volume.availableHeight / 2 - height / 2
                        width: volume.availableWidth; height: 4; radius: 2
                        color: root.theme.surfaceColor
                        Rectangle { width: volume.visualPosition * parent.width; height: parent.height; radius: 2; color: root.theme.accentColor }
                    }
                    handle: Rectangle {
                        x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                        y: volume.topPadding + volume.availableHeight / 2 - height / 2
                        width: 12; height: 12; radius: 6; color: root.theme.accentColor
                    }
                }
                BarButton {
                    theme: root.theme
                    text: "Power"
                    selected: bar.menuOpen
                    onClicked: { bar.pending = ""; bar.errorText = ""; bar.menuOpen = !bar.menuOpen; }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.theme.borderColor }

            Process {
                id: powerProcess
                onExited: (exitCode, exitStatus) => {
                    if (exitCode !== 0) bar.errorText = "Aktion fehlgeschlagen (" + exitCode + ")";
                    else bar.menuOpen = false;
                }
            }
            PanelWindow {
                id: menu
                screen: bar.screen
                visible: bar.menuOpen
                anchors { top: true; right: true }
                margins { top: 42; right: 8 }
                implicitWidth: 280; implicitHeight: 230
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "mywm-power"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                color: "transparent"
                Rectangle {
                    anchors.fill: parent; color: root.theme.backgroundColor; radius: 10
                    border.color: root.theme.accentColor
                    focus: true
                    Keys.onEscapePressed: bar.menuOpen = false
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 8
                        Text {
                            text: bar.pending ? ({logout: "Abmelden?", reboot: "Neu starten?", poweroff: "Ausschalten?"})[bar.pending] : "Sitzung und System"
                            color: root.theme.textColor; font.pixelSize: 16
                        }
                        BarButton {
                            theme: root.theme; width: 252; text: "Sperren"
                            visible: bar.pending === ""
                            enabled: socket.connected
                            onClicked: { root.send("lock"); bar.menuOpen = false; }
                        }
                        Repeater {
                            model: bar.pending ? [] : [{label: "Logout", action: "logout"}, {label: "Reboot", action: "reboot"}, {label: "Shutdown", action: "poweroff"}]
                            BarButton {
                                required property var modelData
                                theme: root.theme; width: 252; text: modelData.label
                                onClicked: bar.choosePower(modelData.action)
                            }
                        }
                        BarButton {
                            visible: bar.pending !== ""
                            theme: root.theme; text: "Bestätigen"; width: 252
                            enabled: !powerProcess.running && (bar.pending !== "logout" || socket.connected)
                            onClicked: bar.confirmPower()
                        }
                        BarButton {
                            theme: root.theme; text: "Abbrechen"; width: 252
                            visible: bar.pending !== ""
                            onClicked: { bar.pending = ""; bar.errorText = ""; bar.menuOpen = false; }
                        }
                        Text { text: bar.errorText; color: root.theme.textColor; font.pixelSize: 12 }
                    }
                }
            }
        }
    }
}
