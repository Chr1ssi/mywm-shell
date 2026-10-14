pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io

// Quick settings: Bluetooth, night light and the local addresses.
Column {
    id: panel

    required property var theme
    required property bool nightLight
    signal nightLightToggled()

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: adapter !== null && adapter.enabled
    // Known devices first, then what a search found; connected ones on top.
    readonly property var devices: adapter === null ? [] : adapter.devices.values
        .filter(device => device.paired || adapter.discovering)
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
    readonly property int connectedCount: devices.filter(device => device.connected).length
    property var addresses: []
    property string copied: ""

    spacing: 14

    function deviceStatus(device): string {
        if (device.pairing) return "Koppeln …";
        if (device.state === BluetoothDeviceState.Connecting) return "Verbinden …";
        if (device.state === BluetoothDeviceState.Disconnecting) return "Trennen …";
        if (device.connected) return device.batteryAvailable ? "Verbunden · " + Math.round(device.battery * 100) + " %" : "Verbunden";
        return device.paired ? "Gekoppelt" : "Neu";
    }

    function useDevice(device): void {
        if (device.connected) device.disconnect();
        else if (device.paired) device.connect();
        else {
            // A device paired from here should reconnect on its own later.
            device.trusted = true;
            device.pair();
        }
    }

    // `ip -4 -o addr show scope global`: "2: eno1    inet 192.168.178.56/24 brd … scope global …"
    function parseAddresses(text: string): void {
        const parsed = text.split("\n").map(line => line.trim().split(/\s+/)).filter(f => f.length > 3 && f[2] === "inet")
            .map(f => ({ device: f[1], address: f[3].split("/")[0] }));
        // Polled every few seconds: unchanged addresses keep their rows.
        if (JSON.stringify(parsed) !== JSON.stringify(addresses)) addresses = parsed;
    }

    Process {
        id: addressQuery
        command: ["ip", "-4", "-o", "addr", "show", "scope", "global"]
        running: true
        stdout: StdioCollector { onStreamFinished: panel.parseAddresses(text) }
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: addressQuery.running = true }
    Process { id: copyProcess }
    Timer { id: copiedReset; interval: 1500; onTriggered: panel.copied = "" }

    Row {
        width: parent.width
        spacing: 10
        Repeater {
            model: [
                { key: "bluetooth", icon: panel.bluetoothOn ? (panel.connectedCount > 0 ? "󰂱" : "󰂯") : "󰂲", label: "Bluetooth",
                  detail: panel.adapter === null ? "Kein Adapter" : !panel.bluetoothOn ? "Aus"
                          : panel.connectedCount > 0 ? panel.connectedCount + " verbunden" : "An",
                  active: panel.bluetoothOn, available: panel.adapter !== null },
                { key: "night", icon: "󰖔", label: "Nachtlicht", detail: panel.nightLight ? "An" : "Aus",
                  active: panel.nightLight, available: true }
            ]
            Rectangle {
                id: tile
                required property var modelData
                width: (parent.width - 10) / 2; height: 72; radius: 22
                color: modelData.active ? panel.theme.accentColor : tileMouse.containsMouse || activeFocus ? panel.theme.surfaceColor : panel.theme.glassSurfaceColor
                enabled: modelData.available
                opacity: enabled ? 1 : 0.45
                activeFocusOnTab: true
                function toggle(): void {
                    if (modelData.key === "night") panel.nightLightToggled();
                    else if (panel.adapter) panel.adapter.enabled = !panel.adapter.enabled;
                }
                Keys.onReturnPressed: toggle()
                Keys.onSpacePressed: toggle()
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 16; spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.modelData.icon
                        color: tile.modelData.active ? panel.theme.backgroundColor : panel.theme.accentColor
                        font.family: panel.theme.iconFontFamily; font.pixelSize: 24
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: tile.modelData.label
                            color: tile.modelData.active ? panel.theme.backgroundColor : panel.theme.textColor
                            font.family: panel.theme.fontFamily; font.pixelSize: 15; font.bold: true
                        }
                        Text {
                            text: tile.modelData.detail
                            color: tile.modelData.active ? panel.theme.backgroundColor : panel.theme.mutedColor
                            font.family: panel.theme.fontFamily; font.pixelSize: 13
                        }
                    }
                }
                MouseArea { id: tileMouse; anchors.fill: parent; hoverEnabled: true; onClicked: tile.toggle() }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 8
        Text {
            text: "Netzwerk"
            color: panel.theme.accentColor
            font.family: panel.theme.fontFamily; font.pixelSize: 15
        }
        Text {
            visible: panel.addresses.length === 0
            text: "Keine Verbindung"
            color: panel.theme.mutedColor
            font.family: panel.theme.fontFamily; font.pixelSize: 14
        }
        Repeater {
            model: panel.addresses
            Rectangle {
                id: addressRow
                required property var modelData
                width: parent.width; height: 40; radius: 14
                color: addressMouse.containsMouse ? panel.theme.surfaceColor : "transparent"
                Text {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    text: addressRow.modelData.device
                    color: panel.theme.mutedColor
                    font.family: panel.theme.fontFamily; font.pixelSize: 14
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: panel.copied === addressRow.modelData.address ? "Kopiert" : addressRow.modelData.address
                    color: panel.theme.textColor
                    font.family: panel.theme.fontFamily; font.pixelSize: 14
                }
                MouseArea {
                    id: addressMouse
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        copyProcess.command = ["wl-copy", addressRow.modelData.address];
                        copyProcess.running = true;
                        panel.copied = addressRow.modelData.address;
                        copiedReset.restart();
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 8
        visible: panel.adapter !== null
        Item {
            width: parent.width; height: searchButton.height
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Geräte"
                color: panel.theme.accentColor
                font.family: panel.theme.fontFamily; font.pixelSize: 15
            }
            BarButton {
                id: searchButton
                anchors.right: parent.right
                visible: panel.bluetoothOn
                theme: panel.theme
                text: panel.adapter && panel.adapter.discovering ? "󰓛 Suche beenden" : "󰍉 Suchen"
                onClicked: panel.adapter.discovering = !panel.adapter.discovering
            }
        }
        Text {
            visible: !panel.bluetoothOn
            text: "Bluetooth ist aus"
            color: panel.theme.mutedColor
            font.family: panel.theme.fontFamily; font.pixelSize: 14
        }
        Text {
            visible: panel.bluetoothOn && panel.devices.length === 0
            text: panel.adapter && panel.adapter.discovering ? "Suche läuft …" : "Keine gekoppelten Geräte"
            color: panel.theme.mutedColor
            font.family: panel.theme.fontFamily; font.pixelSize: 14
        }
        Repeater {
            model: panel.bluetoothOn ? panel.devices : []
            Rectangle {
                id: deviceRow
                required property var modelData
                width: parent.width; height: 52; radius: 16
                color: deviceRow.modelData.connected ? panel.theme.surfaceColor : deviceMouse.containsMouse ? panel.theme.glassSurfaceColor : "transparent"
                Column {
                    x: 12; width: parent.width - actionButton.width - 36
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: deviceRow.modelData.name || deviceRow.modelData.address
                        color: panel.theme.textColor
                        font.family: panel.theme.fontFamily; font.pixelSize: 14; font.bold: deviceRow.modelData.connected
                    }
                    Text {
                        text: panel.deviceStatus(deviceRow.modelData)
                        color: panel.theme.mutedColor
                        font.family: panel.theme.fontFamily; font.pixelSize: 12
                    }
                }
                MouseArea { id: deviceMouse; anchors.fill: parent; hoverEnabled: true }
                BarButton {
                    id: actionButton
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    theme: panel.theme
                    enabled: !deviceRow.modelData.pairing
                    text: deviceRow.modelData.connected ? "Trennen" : deviceRow.modelData.paired ? "Verbinden" : "Koppeln"
                    onClicked: panel.useDevice(deviceRow.modelData)
                }
            }
        }
    }
}
