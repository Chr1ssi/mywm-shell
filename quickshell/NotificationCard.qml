pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Rectangle {
    id: card

    required property var notification
    required property var theme
    property bool compact: false
    signal closeRequested()

    implicitHeight: content.implicitHeight + 24
    radius: 16
    color: theme.backgroundColor
    border.width: notification.urgency === NotificationUrgency.Critical ? 2 : 1
    border.color: notification.urgency === NotificationUrgency.Critical ? theme.accentColor : theme.borderColor

    Row {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 12

        Image {
            width: 42; height: 42
            visible: source.toString() !== "" && status !== Image.Error
            source: card.notification.image || Quickshell.iconPath(card.notification.appIcon || "dialog-information", true)
            sourceSize.width: 64; sourceSize.height: 64
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Column {
            width: parent.width - (parent.children[0].visible ? 54 : 0) - 32
            spacing: 4

            Row {
                width: parent.width
                spacing: 8
                Text {
                    width: parent.width - closeButton.width - 8
                    text: card.notification.summary || card.notification.appName || "Benachrichtigung"
                    color: card.theme.textColor
                    font.family: card.theme.fontFamily; font.pixelSize: 13; font.bold: true
                    elide: Text.ElideRight
                }
                BarButton {
                    id: closeButton
                    theme: card.theme; text: "×"; width: 24
                    onClicked: card.closeRequested()
                }
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: card.notification.body || ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.compact ? 3 : 8
                elide: Text.ElideRight
                color: card.theme.textColor
                font.family: card.theme.fontFamily; font.pixelSize: 12
            }
            Text {
                visible: text !== ""
                text: card.notification.appName || ""
                color: card.theme.mutedColor
                font.family: card.theme.fontFamily; font.pixelSize: 10
            }
            Flow {
                width: parent.width
                spacing: 6
                visible: card.notification.actions.length > 0
                Repeater {
                    model: card.notification.actions
                    BarButton {
                        required property var modelData
                        theme: card.theme
                        text: modelData.text
                        selected: modelData.identifier === "default"
                        onClicked: modelData.invoke()
                    }
                }
            }
        }
    }
}
