import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property Theme theme: Theme {}
    property string query: ""
    property int selected: 0
    property bool launching: false
    readonly property var results: {
        const terms = query.trim().toLocaleLowerCase().split(/\s+/).filter(t => t.length > 0);
        return DesktopEntries.applications.values.filter(entry => {
            if (entry.noDisplay || entry.command.length === 0) return false;
            const haystack = [entry.name, entry.genericName, entry.comment, entry.id,
                              ...entry.keywords].join(" ").toLocaleLowerCase();
            return terms.every(term => haystack.includes(term));
        }).sort((a, b) => {
            const prefix = query.trim().toLocaleLowerCase();
            const aFirst = a.name.toLocaleLowerCase().startsWith(prefix);
            const bFirst = b.name.toLocaleLowerCase().startsWith(prefix);
            return aFirst !== bFirst ? (aFirst ? -1 : 1) : a.name.localeCompare(b.name);
        });
    }
    onQueryChanged: selected = 0
    onResultsChanged: selected = Math.max(0, Math.min(selected, results.length - 1))

    function iconName(entry): string {
        const id = String(entry.id || "").toLocaleLowerCase();
        const command = Array.from(entry.command || []).join(" ").toLocaleLowerCase();
        if (id.includes("nemo") || command.includes("nemo")) return "nemo";
        if (id.includes("nm-connection-editor") || command.includes("nm-connection-editor"))
            return "nm-device-wired";
        return entry.icon || "application-x-executable";
    }

    function move(delta: int): void {
        if (results.length === 0) return;
        selected = (selected + delta + results.length) % results.length;
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function launch(index: int): void {
        if (launching || index < 0 || index >= results.length) return;
        const entry = results[index];
        let command = Array.from(entry.command);
        if (entry.runInTerminal) {
            let terminal = [];
            const count = Number(Quickshell.env("MYWM_TERMINAL_COUNT") || "0");
            for (let i = 0; i < count; i++) terminal.push(String(Quickshell.env("MYWM_TERMINAL_" + i)));
            if (terminal.length === 0) terminal = ["kitty"];
            command = terminal.concat(["-e"], command);
        }
        launching = true;
        Quickshell.execDetached({ command: command, workingDirectory: entry.workingDirectory });
        Qt.quit();
    }

    function targetScreen(): var {
        const screens = Quickshell.screens;
        const xValue = Quickshell.env("MYWM_LAUNCHER_X");
        const yValue = Quickshell.env("MYWM_LAUNCHER_Y");
        if (xValue !== undefined && xValue !== "" && yValue !== undefined && yValue !== "") {
            const x = Number(xValue), y = Number(yValue);
            for (const screen of screens) {
                if (x >= screen.x && x < screen.x + screen.width && y >= screen.y && y < screen.y + screen.height)
                    return screen;
            }
        }
        return screens.length ? screens[0] : null;
    }

    IpcHandler {
        target: "launcher"
        function search(text: string): void { root.query = text; }
        function count(): int { return root.results.length; }
        function current(): string { return root.results.length ? root.results[root.selected].id : ""; }
        function move(delta: int): void { root.move(delta); }
        function launch(): void { root.launch(root.selected); }
        function close(): void { Qt.quit(); }
    }

    PanelWindow {
        id: panel
        screen: root.targetScreen()
        visible: true
        implicitWidth: Math.min(640, (screen ? screen.width : 672) - 32)
        implicitHeight: Math.min(560, (screen ? screen.height : 592) - 32)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "mywm-launcher"

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: root.theme.backgroundColor
            border.width: 2
            border.color: root.theme.accentColor

            Column {
                anchors.fill: parent
                anchors.margins: root.theme.panelPadding
                spacing: 12

                Text {
                    text: "ANWENDUNGEN"
                    color: root.theme.textColor
                    font.family: root.theme.fontFamily; font.pixelSize: 12
                    font.bold: true
                }

                TextField {
                    id: search
                    width: parent.width
                    height: 48
                    text: root.query
                    onTextChanged: root.query = text
                    placeholderText: "App suchen …"
                    color: root.theme.textColor
                    placeholderTextColor: root.theme.mutedColor
                    selectionColor: root.theme.accentColor
                    selectedTextColor: root.theme.backgroundColor
                    font.family: root.theme.fontFamily; font.pixelSize: 16
                    focus: true
                    background: Rectangle {
                        color: root.theme.surfaceColor
                        radius: 0
                        border.color: root.theme.borderColor
                    }
                    Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) Qt.quit();
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) root.move(1);
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) root.move(-1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.launch(root.selected);
                        else return;
                        event.accepted = true;
                    }
                }

                ListView {
                    id: list
                    width: parent.width
                    height: Math.max(40, panel.height - 148)
                    clip: true
                    spacing: 2
                    model: root.results
                    currentIndex: root.selected
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 52
                        radius: 0
                        color: index === root.selected || rowMouse.containsMouse ? root.theme.surfaceColor : "transparent"
                        border.width: 0
                        border.color: root.theme.accentColor
                        Image {
                            id: icon
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            source: Quickshell.iconPath(root.iconName(row.modelData), true)
                            sourceSize.width: 32
                            sourceSize.height: 32
                        }
                        Column {
                            x: 56
                            width: parent.width - 70
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                width: parent.width
                                text: row.modelData.name
                                elide: Text.ElideRight
                                color: root.theme.textColor
                                font.family: root.theme.fontFamily; font.pixelSize: 14
                            }
                            Text {
                                width: parent.width
                                text: row.modelData.genericName || row.modelData.comment || row.modelData.id
                                elide: Text.ElideRight
                                color: root.theme.mutedColor
                                font.family: root.theme.fontFamily; font.pixelSize: 12
                            }
                        }
                        MouseArea {
                            id: rowMouse
                            hoverEnabled: true
                            anchors.fill: parent
                            onClicked: root.launch(row.index)
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.results.length === 0
                        text: "Keine passenden Anwendungen"
                        color: root.theme.mutedColor
                        font.family: root.theme.fontFamily; font.pixelSize: 16
                    }
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.results.length + " Apps  ·  ↑↓ Auswahl  ·  ↵ Start  ·  Esc"
                    color: root.theme.mutedColor
                    font.family: root.theme.fontFamily; font.pixelSize: 12
                }
            }
        }
    }
}
