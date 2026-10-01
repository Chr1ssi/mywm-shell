import QtQuick

// A translucent, fully rounded group of bar items.
Rectangle {
    id: island
    required property var theme
    default property alias content: row.data
    implicitWidth: row.implicitWidth + 8
    implicitHeight: theme.islandHeight
    radius: height / 2
    color: theme.glassColor
    border.width: 1
    border.color: theme.glassBorderColor
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
    }
}
