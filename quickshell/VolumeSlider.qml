import QtQuick
import QtQuick.Controls

Slider {
    id: control
    required property var theme
    from: 0; to: 1
    implicitHeight: 26
    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth; height: 6; radius: 3
        color: control.theme.surfaceColor
        Rectangle { width: control.visualPosition * parent.width; height: parent.height; radius: 3; color: control.theme.accentColor }
    }
    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: 14; height: 14; radius: 7
        color: control.theme.accentColor
        border.width: control.activeFocus ? 2 : 0; border.color: control.theme.textColor
    }
}
