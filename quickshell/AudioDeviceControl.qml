pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Column {
    id: control

    required property var theme
    required property var node
    readonly property var audio: node.audio || null
    readonly property bool hasNativeAudio: audio !== null
    property real fallbackVolume: 0
    property bool fallbackMuted: false
    property bool fallbackLoaded: false
    property bool selectable: false
    property bool selected: false
    property string label: node.description || node.name
    signal selectRequested()

    width: parent ? parent.width : 0
    spacing: 4

    function updateFallback(text: string): void {
        const match = text.match(/Volume:\s+([0-9.]+)(.*)/);
        if (!match) return;
        fallbackVolume = Number(match[1]);
        fallbackMuted = match[2].includes("MUTED");
        fallbackLoaded = true;
    }

    function setVolume(value: real): void {
        if (hasNativeAudio) {
            audio.volume = value;
            audio.muted = false;
        } else {
            fallbackVolume = value;
            fallbackMuted = false;
            volumeProcess.command = ["wpctl", "set-volume", String(node.id), String(value)];
            volumeProcess.running = true;
        }
    }

    function toggleMute(): void {
        if (hasNativeAudio) {
            audio.muted = !audio.muted;
        } else {
            fallbackMuted = !fallbackMuted;
            muteProcess.running = true;
        }
    }

    Process {
        id: volumeQuery
        command: ["wpctl", "get-volume", String(control.node.id)]
        running: !control.hasNativeAudio
        stdout: StdioCollector { onStreamFinished: control.updateFallback(text) }
    }
    Process { id: volumeProcess }
    Process {
        id: muteProcess
        command: ["wpctl", "set-mute", String(control.node.id), "toggle"]
    }
    Timer {
        interval: 1500
        repeat: true
        running: !control.hasNativeAudio
        onTriggered: if (!volumeQuery.running) volumeQuery.running = true
    }

    Row {
        width: parent.width
        spacing: 6

        BarButton {
            theme: control.theme
            width: parent.width - 84
            text: (control.selected ? "✓ " : "") + control.label
            selected: control.selected
            enabled: control.selectable
            onClicked: control.selectRequested()
        }
        BarButton {
            theme: control.theme; width: 78
            text: control.hasNativeAudio
                ? (control.audio.muted ? "Stumm" : Math.round(control.audio.volume * 100) + " %")
                : !control.fallbackLoaded ? "…" : control.fallbackMuted ? "Stumm" : Math.round(control.fallbackVolume * 100) + " %"
            enabled: control.hasNativeAudio || control.fallbackLoaded
            onClicked: control.toggleMute()
        }
    }

    Loader {
        active: control.hasNativeAudio || control.fallbackLoaded
        visible: active
        width: parent.width
        sourceComponent: VolumeSlider {
            theme: control.theme
            from: 0; to: 1
            value: control.hasNativeAudio ? control.audio.volume : control.fallbackVolume
            onMoved: if (pressed) control.setVolume(value)
        }
    }
}
