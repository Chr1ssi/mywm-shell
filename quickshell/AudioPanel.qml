pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

Column {
    id: panel

    required property var theme
    property bool outputsExpanded: false
    property bool inputsExpanded: false

    readonly property var nodes: Pipewire.nodes.values
    readonly property var outputs: nodes.filter(node => mediaClass(node) === "Audio/Sink")
    readonly property var inputs: nodes.filter(node => mediaClass(node).startsWith("Audio/Source"))
    readonly property var outputStreams: nodes.filter(node => mediaClass(node) === "Stream/Output/Audio")
    readonly property var applications: outputStreams.filter(node =>
        String(node.properties["application.name"] || "") !== "")
    readonly property var currentOutput: Pipewire.defaultAudioSink || null
    readonly property var currentInput: Pipewire.defaultAudioSource || null

    spacing: 14

    function applicationLabel(node): string {
        return String(node.properties["application.name"] || node.description || node.name);
    }

    function mediaClass(node): string {
        return String(node.properties["media.class"] || "");
    }

    function selectDefault(node): void {
        defaultDeviceProcess.command = ["wpctl", "set-default", String(node.id)];
        defaultDeviceProcess.running = true;
    }

    PwObjectTracker { objects: panel.nodes }
    Process { id: defaultDeviceProcess }

    Column {
        width: parent.width
        spacing: 8

        Text {
            text: "Ausgabe"
            color: panel.theme.accentColor
            font.family: panel.theme.fontFamily; font.pixelSize: 13
        }
        Text {
            visible: panel.currentOutput === null
            text: "Kein Ausgabegerät"
            color: panel.theme.mutedColor
            font.family: panel.theme.fontFamily; font.pixelSize: 12
        }
        Loader {
            active: panel.currentOutput !== null
            visible: active
            width: parent.width
            sourceComponent: AudioDeviceControl {
                theme: panel.theme
                node: panel.currentOutput
                selected: true
            }
        }
        BarButton {
            visible: panel.outputs.filter(node => node !== panel.currentOutput).length > 0
            theme: panel.theme
            width: parent.width
            text: panel.outputsExpanded ? "▴ Andere Ausgänge ausblenden" : "▾ Anderen Ausgang wählen"
            onClicked: panel.outputsExpanded = !panel.outputsExpanded
        }
        Column {
            visible: panel.outputsExpanded
            width: parent.width
            spacing: 8
            Repeater {
                model: panel.outputs.filter(node => node !== panel.currentOutput)
                AudioDeviceControl {
                    required property var modelData
                    theme: panel.theme
                    node: modelData
                    selectable: true
                    onSelectRequested: {
                        panel.selectDefault(modelData);
                        panel.outputsExpanded = false;
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            text: "Mikrofon"
            color: panel.theme.accentColor
            font.family: panel.theme.fontFamily; font.pixelSize: 13
        }
        Text {
            visible: panel.currentInput === null
            text: "Kein Eingabegerät"
            color: panel.theme.mutedColor
            font.family: panel.theme.fontFamily; font.pixelSize: 12
        }
        Loader {
            active: panel.currentInput !== null
            visible: active
            width: parent.width
            sourceComponent: AudioDeviceControl {
                theme: panel.theme
                node: panel.currentInput
                selected: true
            }
        }
        BarButton {
            visible: panel.inputs.filter(node => node !== panel.currentInput).length > 0
            theme: panel.theme
            width: parent.width
            text: panel.inputsExpanded ? "▴ Andere Eingänge ausblenden" : "▾ Anderes Mikrofon wählen"
            onClicked: panel.inputsExpanded = !panel.inputsExpanded
        }
        Column {
            visible: panel.inputsExpanded
            width: parent.width
            spacing: 8
            Repeater {
                model: panel.inputs.filter(node => node !== panel.currentInput)
                AudioDeviceControl {
                    required property var modelData
                    theme: panel.theme
                    node: modelData
                    selectable: true
                    onSelectRequested: {
                        panel.selectDefault(modelData);
                        panel.inputsExpanded = false;
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            text: "Anwendungen"
            color: panel.theme.accentColor
            font.family: panel.theme.fontFamily; font.pixelSize: 13
        }
        Text {
            visible: panel.applications.length === 0
            text: "Keine aktiven Anwendungen"
            color: panel.theme.mutedColor
            font.family: panel.theme.fontFamily; font.pixelSize: 12
        }
        Repeater {
            model: panel.applications
            AudioDeviceControl {
                required property var modelData
                theme: panel.theme
                node: modelData
                label: panel.applicationLabel(modelData)
            }
        }
    }
}
