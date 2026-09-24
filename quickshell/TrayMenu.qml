pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Column {
    id: menuView

    required property var theme
    required property var menu
    required property string title
    property var currentMenu: menu
    property var menuStack: []
    signal closeRequested()

    spacing: 4

    function iconSource(icon): string {
        const value = String(icon || "");
        if (!value) return "";
        if (value.startsWith("image://") || value.startsWith("file:") || value.startsWith("qrc:") || value.startsWith("/") || value.includes("://"))
            return value;
        return Quickshell.iconPath(value, true);
    }

    function symbolicGlyph(icon, label): string {
        const value = (String(icon || "") + " " + String(label || "")).toLocaleLowerCase();
        if (value.includes("exit") || value.includes("quit") || value.includes("beenden")) return "󰍃";
        if (value.includes("setting") || value.includes("preference") || value.includes("einstellung")) return "󰒓";
        if (value.includes("window") || value.includes("show") || value.includes("open") || value.includes("anzeigen")) return "󰖯";
        if (value.includes("about") || value.includes("help") || value.includes("info")) return "󰋼";
        if (value.includes("bypass") || value.includes("enable") || value.includes("aktiv")) return "󰈈";
        return "•";
    }

    onMenuChanged: {
        currentMenu = menu;
        menuStack = [];
    }

    QsMenuOpener {
        id: opener
        menu: menuView.currentMenu
    }

    Row {
        id: header
        width: parent.width
        spacing: 6

        BarButton {
            visible: menuView.menuStack.length > 0
            width: visible ? implicitWidth : 0
            theme: menuView.theme
            text: "←"
            onClicked: {
                const stack = menuView.menuStack.slice();
                menuView.currentMenu = stack.pop();
                menuView.menuStack = stack;
            }
        }
        Text {
            width: parent.width - closeButton.width - (menuView.menuStack.length > 0 ? 38 : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: menuView.title
            color: menuView.theme.textColor
            font.family: menuView.theme.fontFamily; font.pixelSize: 13; font.bold: true
            elide: Text.ElideRight
        }
        BarButton {
            id: closeButton
            theme: menuView.theme; text: "×"; width: 24
            onClicked: menuView.closeRequested()
        }
    }

    ListView {
        id: entries
        width: parent.width
        height: Math.min(440, contentHeight)
        model: opener.children
        spacing: 2
        clip: true

        delegate: Item {
            id: entry
            required property var modelData
            width: entries.width
            height: modelData.isSeparator ? 9 : 34

            Rectangle {
                visible: entry.modelData.isSeparator
                anchors.centerIn: parent
                width: parent.width; height: 1
                color: menuView.theme.borderColor
            }

            Rectangle {
                visible: !entry.modelData.isSeparator
                anchors.fill: parent
                radius: 8
                color: entryMouse.containsMouse ? menuView.theme.surfaceColor : "transparent"
                opacity: entry.modelData.enabled ? 1 : 0.45

                Row {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    spacing: 8

                    Text {
                        width: 18
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: entry.modelData.buttonType === QsMenuButtonType.None ? "" : entry.modelData.checkState === Qt.Checked ? "✓" : "○"
                        color: menuView.theme.accentColor
                        font.family: menuView.theme.fontFamily; font.pixelSize: 12
                    }
                    Item {
                        id: entryIcon
                        readonly property bool symbolic: String(entry.modelData.icon || "").includes("symbolic")
                        readonly property string glyph: symbolic ? menuView.symbolicGlyph(entry.modelData.icon, entry.modelData.text) : ""
                        width: visible ? 18 : 0; height: 18
                        anchors.verticalCenter: parent.verticalCenter
                        visible: glyph !== "" || iconImage.status === Image.Ready

                        Image {
                            id: iconImage
                            anchors.fill: parent
                            visible: !entryIcon.symbolic && status === Image.Ready
                            source: entryIcon.symbolic ? "" : menuView.iconSource(entry.modelData.icon)
                            sourceSize.width: 18; sourceSize.height: 18
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: entryIcon.glyph !== ""
                            text: entryIcon.glyph
                            color: menuView.theme.textColor
                            font.family: menuView.theme.fontFamily; font.pixelSize: 13
                        }
                    }
                    Text {
                        width: parent.width - 52 - (entryIcon.visible ? 26 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text
                        color: menuView.theme.textColor
                        font.family: menuView.theme.fontFamily; font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        width: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.hasChildren ? "›" : ""
                        color: menuView.theme.mutedColor
                        font.family: menuView.theme.fontFamily; font.pixelSize: 16
                    }
                }

                MouseArea {
                    id: entryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: entry.modelData.enabled
                    onClicked: {
                        if (entry.modelData.hasChildren) {
                            menuView.menuStack = menuView.menuStack.concat([menuView.currentMenu]);
                            menuView.currentMenu = entry.modelData;
                        } else {
                            entry.modelData.triggered();
                            menuView.closeRequested();
                        }
                    }
                }
            }
        }
    }
}
