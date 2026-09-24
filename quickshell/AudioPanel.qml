pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

Column {
    id: panel
    required property var theme
    spacing: 12
    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio)
    PwObjectTracker { objects: panel.nodes }
    Repeater {
        model: ["Ausgabe", "Mikrofon", "Anwendungen"]
        Column {
            id: section
            required property string modelData
            required property int index
            width: panel.width
            spacing: 8
            readonly property var devices: panel.nodes.filter(n => index === 2 ? n.isStream : !n.isStream && n.isSink === (index === 0))
            Text { text: section.modelData; color: panel.theme.accentColor; font.family: panel.theme.fontFamily; font.pixelSize: 13 }
            Text { visible: section.devices.length === 0; text: "Keine aktiven Geräte / Streams"; color: panel.theme.mutedColor; font.family: panel.theme.fontFamily; font.pixelSize: 12 }
            Repeater {
                model: section.devices
                Column {
                    id: device
                    required property var modelData
                    width: section.width
                    spacing: 4
                    Row {
                        spacing: 6
                        BarButton {
                            theme: panel.theme
                            width: device.width - 84
                            text: (selected ? "✓ " : "") + (device.modelData.description || device.modelData.name)
                            selected: section.index !== 2 && device.modelData === (section.index === 0 ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource)
                            enabled: section.index !== 2
                            onClicked: {
                                if (section.index === 0) Pipewire.preferredDefaultAudioSink = device.modelData;
                                else Pipewire.preferredDefaultAudioSource = device.modelData;
                            }
                        }
                        BarButton {
                            theme: panel.theme; width: 78
                            text: device.modelData.audio.muted ? "Stumm" : Math.round(device.modelData.audio.volume * 100) + " %"
                            onClicked: device.modelData.audio.muted = !device.modelData.audio.muted
                        }
                    }
                    VolumeSlider {
                        theme: panel.theme
                        width: parent.width; from: 0; to: 1
                        value: device.modelData.audio.volume
                        onMoved: { device.modelData.audio.volume = value; device.modelData.audio.muted = false; }
                    }
                }
            }
        }
    }
}
