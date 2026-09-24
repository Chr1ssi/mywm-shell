pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Column {
    id: center

    required property var theme
    required property var notifications
    signal dismiss(var notification)
    signal clearAll()

    spacing: 12

    Row {
        id: heading
        width: parent.width
        spacing: 8
        Text {
            width: parent.width - clearButton.width - 8
            text: center.notifications.length + (center.notifications.length === 1 ? " Benachrichtigung" : " Benachrichtigungen")
            color: center.theme.textColor
            font.family: center.theme.fontFamily; font.pixelSize: 13
        }
        BarButton {
            id: clearButton
            theme: center.theme; text: "Alle löschen"
            enabled: center.notifications.length > 0
            onClicked: center.clearAll()
        }
    }

    ListView {
        id: list
        width: parent.width
        height: Math.min(470, Math.max(80, contentHeight))
        spacing: 8
        clip: true
        model: center.notifications
        ScrollBar.vertical: ScrollBar {}
        delegate: NotificationCard {
            required property var modelData
            width: list.width - (list.ScrollBar.vertical.visible ? 10 : 0)
            notification: modelData
            theme: center.theme
            onCloseRequested: center.dismiss(modelData)
        }
        Text {
            anchors.centerIn: parent
            visible: center.notifications.length === 0
            text: "Keine Benachrichtigungen"
            color: center.theme.mutedColor
            font.family: center.theme.fontFamily; font.pixelSize: 12
        }
    }
}
