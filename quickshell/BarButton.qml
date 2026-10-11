import QtQuick

Rectangle {
    id: button
    required property var theme
    property string text: ""
    property bool selected: false
    property bool marked: false
    property string fontFamily: theme.fontFamily
    signal clicked()
    signal secondaryClicked()
    signal scrolled(real delta)
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    implicitWidth: label.implicitWidth + 16
    implicitHeight: 26
    radius: height / 2
    color: selected || mouse.containsMouse || activeFocus ? theme.surfaceColor : "transparent"
    opacity: enabled ? 1 : 0.45
    Text {
        id: label
        // Center the line inside the full height: centerIn would round the 19 px text box
        // to a whole-pixel offset and leave icons visibly high.
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 12
        height: parent.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: button.text
        color: button.selected ? button.theme.accentColor : button.theme.textColor
        font.family: button.fontFamily; font.pixelSize: 14
        font.bold: button.marked || button.selected
    }
    Rectangle {
        visible: button.marked && !button.selected
        anchors.bottom: parent.bottom; anchors.bottomMargin: 2
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
