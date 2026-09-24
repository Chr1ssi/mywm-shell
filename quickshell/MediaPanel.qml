pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris

Column {
    id: panel
    required property var theme
    spacing: 14
    Text { visible: Mpris.players.values.length === 0; text: "Keine aktive Wiedergabe"; color: panel.theme.mutedColor; font.family: panel.theme.fontFamily }
    Repeater {
        model: Mpris.players
        Column {
            id: player
            required property var modelData
            width: panel.width
            spacing: 8
            Image {
                width: parent.width; height: 150
                visible: source.toString() !== "" && status !== Image.Error
                source: player.modelData.trackArtUrl
                fillMode: Image.PreserveAspectCrop; asynchronous: true
                sourceSize.width: 400; sourceSize.height: 200
            }
            Text { width: parent.width; text: player.modelData.trackTitle || player.modelData.identity; elide: Text.ElideRight; color: panel.theme.textColor; font.family: panel.theme.fontFamily; font.pixelSize: 15 }
            Text { width: parent.width; text: player.modelData.trackArtist || player.modelData.identity; elide: Text.ElideRight; color: panel.theme.mutedColor; font.family: panel.theme.fontFamily; font.pixelSize: 12 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                BarButton { theme: panel.theme; text: "󰒮"; enabled: player.modelData.canGoPrevious; onClicked: player.modelData.previous() }
                BarButton { theme: panel.theme; text: player.modelData.isPlaying ? "󰏤" : "󰐊"; enabled: player.modelData.canTogglePlaying; onClicked: player.modelData.togglePlaying() }
                BarButton { theme: panel.theme; text: "󰒭"; enabled: player.modelData.canGoNext; onClicked: player.modelData.next() }
            }
        }
    }
}
