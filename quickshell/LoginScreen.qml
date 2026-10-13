pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell

// What the lock screen and the greeter show: the wallpaper on every monitor, and on the primary one (workspace 1,
// `MYWM_PRIMARY_OUTPUT`) a large clock and a glass card that asks for the password. Both look alike by sharing this;
// the greeter adds the user name, sessions and power.
Item {
    id: screen

    required property var theme
    required property url background
    // The text in the fields, shared by every monitor's copy so typing works wherever the pointer is.
    property string password: ""
    property string userName: ""
    property bool askUser: false
    property bool busy: false
    property string message: ""
    property bool messageIsError: false
    // Greeter only: [{ name, command }], and the index picked.
    property var sessions: []
    property int session: 0
    property bool showPower: false
    // Only the primary monitor shows the card; elsewhere typing still reaches the shared password.
    property bool primary: true
    signal passwordEdited(string text)
    signal userEdited(string text)
    signal submitted()
    signal sessionPicked(int index)
    signal powerRequested(string action)

    // A lock surface learns its screen only after it was made: whichever field shows now takes the keys.
    onPrimaryChanged: focusField()

    function focusField(): void {
        if (!primary) hiddenField.forceActiveFocus();
        else if (askUser && userName === "") userField.forceActiveFocus();
        else passwordField.forceActiveFocus();
    }

    Rectangle { anchors.fill: parent; color: screen.theme.backgroundColor }
    Image {
        anchors.fill: parent
        source: screen.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
    // Calm the picture so text and glass stay readable on any wallpaper.
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }

    // Keys that reach another monitor (the pointer is there) type into the shared password.
    TextInput {
        id: hiddenField
        visible: !screen.primary
        opacity: 0
        echoMode: TextInput.Password
        text: screen.password
        enabled: !screen.busy
        onTextEdited: screen.passwordEdited(text)
        Keys.onReturnPressed: screen.submitted()
        Keys.onEnterPressed: screen.submitted()
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }
    Column {
        visible: screen.primary
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.date.toLocaleTimeString(Qt.locale("de_DE"), "HH:mm")
            color: screen.theme.textColor
            font.family: screen.theme.fontFamily; font.pixelSize: 112; font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.date.toLocaleDateString(Qt.locale("de_DE"), "dddd, d. MMMM")
            color: screen.theme.textColor
            opacity: 0.8
            font.family: screen.theme.fontFamily; font.pixelSize: 22
        }
    }

    Rectangle {
        id: card
        visible: screen.primary
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.52
        width: Math.min(400, parent.width - 48)
        height: cardColumn.implicitHeight + 2 * 28
        radius: 28
        color: screen.theme.glassColor
        border.width: 1
        border.color: screen.theme.glassBorderColor

        Column {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 16

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72; height: 72; radius: 36
                color: screen.theme.accentColor
                Text {
                    anchors.centerIn: parent
                    text: screen.userName ? screen.userName.charAt(0).toLocaleUpperCase() : "󰀄"
                    color: screen.theme.backgroundColor
                    font.family: screen.userName ? screen.theme.fontFamily : screen.theme.iconFontFamily
                    font.pixelSize: 32; font.bold: true
                }
            }
            Text {
                visible: !screen.askUser
                anchors.horizontalCenter: parent.horizontalCenter
                text: screen.userName
                color: screen.theme.textColor
                font.family: screen.theme.fontFamily; font.pixelSize: 20
            }
            TextField {
                id: userField
                visible: screen.askUser
                width: parent.width; height: 48
                leftPadding: 20; rightPadding: 20
                text: screen.userName
                onTextEdited: screen.userEdited(text)
                placeholderText: "Benutzername"
                enabled: !screen.busy
                color: screen.theme.textColor
                placeholderTextColor: screen.theme.mutedColor
                selectionColor: screen.theme.accentColor
                selectedTextColor: screen.theme.backgroundColor
                font.family: screen.theme.fontFamily; font.pixelSize: 16
                background: Rectangle {
                    radius: height / 2
                    color: screen.theme.glassSurfaceColor
                    border.width: userField.activeFocus ? 2 : 1
                    border.color: userField.activeFocus ? screen.theme.accentColor : screen.theme.borderColor
                }
                Keys.onReturnPressed: passwordField.forceActiveFocus()
                Keys.onEnterPressed: passwordField.forceActiveFocus()
            }
            TextField {
                id: passwordField
                width: parent.width; height: 48
                leftPadding: 20; rightPadding: 56
                text: screen.password
                onTextEdited: screen.passwordEdited(text)
                echoMode: TextInput.Password
                passwordCharacter: "●"
                placeholderText: "Passwort"
                enabled: !screen.busy
                focus: true
                color: screen.theme.textColor
                placeholderTextColor: screen.theme.mutedColor
                selectionColor: screen.theme.accentColor
                selectedTextColor: screen.theme.backgroundColor
                font.family: screen.theme.fontFamily; font.pixelSize: 16
                background: Rectangle {
                    radius: height / 2
                    color: screen.theme.glassSurfaceColor
                    border.width: passwordField.activeFocus ? 2 : 1
                    border.color: screen.messageIsError ? screen.theme.alertColor
                                  : passwordField.activeFocus ? screen.theme.accentColor : screen.theme.borderColor
                }
                Keys.onReturnPressed: screen.submitted()
                Keys.onEnterPressed: screen.submitted()
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: 18
                    color: submitMouse.containsMouse ? screen.theme.accentColor : screen.theme.surfaceColor
                    Text {
                        anchors.centerIn: parent
                        text: screen.busy ? "󰔟" : "󰁔"
                        color: submitMouse.containsMouse ? screen.theme.backgroundColor : screen.theme.accentColor
                        font.family: screen.theme.iconFontFamily; font.pixelSize: 18
                    }
                    MouseArea { id: submitMouse; anchors.fill: parent; hoverEnabled: true; onClicked: screen.submitted() }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: text !== ""
                text: screen.message
                color: screen.messageIsError ? screen.theme.alertColor : screen.theme.mutedColor
                font.family: screen.theme.fontFamily; font.pixelSize: 14
            }
        }
    }

    // Greeter: which session to start (only when there is a choice) and the power buttons.
    Rectangle {
        visible: screen.primary && screen.sessions.length > 1
        anchors { left: parent.left; bottom: parent.bottom; margins: 24 }
        width: sessionRow.implicitWidth + 8; height: screen.theme.islandHeight
        radius: height / 2
        color: screen.theme.glassColor
        border.width: 1; border.color: screen.theme.glassBorderColor
        Row {
            id: sessionRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: screen.sessions
                BarButton {
                    required property var modelData
                    required property int index
                    theme: screen.theme
                    text: modelData.name
                    selected: index === screen.session
                    onClicked: screen.sessionPicked(index)
                }
            }
        }
    }
    Rectangle {
        visible: screen.primary && screen.showPower
        anchors { right: parent.right; bottom: parent.bottom; margins: 24 }
        width: powerRow.implicitWidth + 8; height: screen.theme.islandHeight
        radius: height / 2
        color: screen.theme.glassColor
        border.width: 1; border.color: screen.theme.glassBorderColor
        Row {
            id: powerRow
            anchors.centerIn: parent
            spacing: 2
            BarButton {
                theme: screen.theme
                fontFamily: screen.theme.iconFontFamily
                text: "󰜉"
                onClicked: screen.powerRequested("reboot")
            }
            BarButton {
                theme: screen.theme
                fontFamily: screen.theme.iconFontFamily
                text: "⏻"
                onClicked: screen.powerRequested("poweroff")
            }
        }
    }
}
