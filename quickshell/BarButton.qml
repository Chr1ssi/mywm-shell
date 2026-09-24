import QtQuick

Rectangle {
    id: button
    required property var theme
    property string text: ""
    property bool selected: false
    property bool marked: false
    signal clicked()
    signal secondaryClicked()
    signal scrolled(real delta)
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    implicitWidth: label.implicitWidth + 16
    implicitHeight: 24
    radius: 0
    color: selected || mouse.containsMouse || activeFocus ? theme.surfaceColor : "transparent"
    opacity: enabled ? 1 : 0.45
    Text {
        id: label
        anchors.centerIn: parent
        width: parent.width - 12
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: button.text
        color: button.selected ? button.theme.accentColor : button.theme.textColor
        font.family: button.theme.fontFamily; font.pixelSize: 12
        font.bold: button.marked || button.selected
    }
    Rectangle {
        visible: button.marked && !button.selected
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: 4; height: 3; radius: 1
        color: button.theme.accentColor
    }
    MouseArea {
        id: mouse; anchors.fill: parent; hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => { if (event.button === Qt.RightButton) button.secondaryClicked(); else button.clicked(); }
        onWheel: event => button.scrolled(event.angleDelta.y / 120)
    }
}
