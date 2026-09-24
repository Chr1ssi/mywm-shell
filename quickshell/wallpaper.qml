import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property Theme theme: Theme {}
    readonly property var desktop: {
        const screens = Quickshell.screens;
        if (!screens.length) return {x: 0, y: 0, width: 1, height: 1, scale: 1};
        const left = Math.min(...screens.map(s => s.x));
        const top = Math.min(...screens.map(s => s.y));
        const right = Math.max(...screens.map(s => s.x + s.width));
        const bottom = Math.max(...screens.map(s => s.y + s.height));
        return {x: left, y: top, width: right - left, height: bottom - top,
                scale: Math.max(...screens.map(s => s.devicePixelRatio))};
    }
    readonly property string directory: Quickshell.env("MYWM_WALLPAPER_DIRECTORY") || ""
    property string wallpaper: ""
    property bool stateReady: false
    property bool saving: false
    property string errorText: ""
    property bool pickerOpen: false
    property var pickerScreen: null
    property string query: ""
    property int selected: 0
    property var entries: []
    readonly property var results: entries.filter(e => e.name.toLocaleLowerCase().includes(query.toLocaleLowerCase().trim()))
    readonly property string displayedWallpaper: wallpaper || (entries.length ? entries[0].url : "")
    function openPicker(x: int, y: int): void {
        if (!scan.running) scan.running = true;
        pickerScreen = Quickshell.screens.find(s => x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) || Quickshell.screens[0];
        query = "";
        selected = Math.max(0, results.findIndex(e => e.url === displayedWallpaper));
        pickerOpen = true;
        Qt.callLater(() => search.forceActiveFocus());
    }
    function move(delta: int): void {
        if (!results.length) return;
        selected = Math.max(0, Math.min(results.length - 1, selected + delta));

    }
    function choose(index: int): void {
        if (saving || !stateReady || index < 0 || index >= results.length) return;
        selected = index;
        errorText = "";
        validation.source = results[index].url;
        if (validation.status === Image.Ready) commit();
    }
    function commit(): void {
        if (saving) return;
        saving = true;
        stateFile.setText(JSON.stringify({version: 1, wallpaper: String(validation.source)}) + "\n");
    }
    onQueryChanged: selected = 0
    onResultsChanged: selected = Math.max(0, Math.min(selected, results.length - 1))
    Process {
        id: scan
        command: [Quickshell.env("MYWM_WALLPAPER_HELPER"), "--wallpaper-list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.entries = text.split("\n").filter(line => line.startsWith("file:///")).map(url => ({url: url, name: decodeURIComponent(url.split("/").pop())}))
        }
        onExited: (code, status) => { if (code !== 0) root.errorText = "Bildordner konnte nicht gelesen werden: " + root.directory; }
    }
    FileView {
        id: stateFile
        path: Quickshell.env("MYWM_WALLPAPER_STATE") || ""
        printErrors: false
        atomicWrites: true
        onLoaded: {
            if (root.stateReady) return;
            try {
                const saved = JSON.parse(text());
                if (saved.version !== 1 || typeof saved.wallpaper !== "string" || !saved.wallpaper.startsWith("file:///")) throw new Error("Ungültiges Format");
                root.wallpaper = saved.wallpaper;
            } catch (error) { root.errorText = "Gespeicherte Auswahl konnte nicht gelesen werden."; }
            root.stateReady = true;
        }
        onLoadFailed: root.stateReady = true
        onSaved: {
            root.wallpaper = String(validation.source);
            root.saving = false;
            root.pickerOpen = false;
        }
        onSaveFailed: { root.saving = false; root.errorText = "Auswahl konnte nicht gespeichert werden."; }
    }
    Image {
        id: validation
        visible: false
        asynchronous: true
        sourceSize.width: 32; sourceSize.height: 32
        onStatusChanged: {
            if (status === Image.Ready) root.commit();
            else if (status === Image.Error) root.errorText = "Dieses Bild kann nicht geladen werden.";
        }
    }
    IpcHandler {
        target: "wallpaper"
        function openPicker(x: int, y: int): void {
        if (!scan.running) scan.running = true; root.openPicker(x, y); }
        function close(): void { root.pickerOpen = false; }
        function search(text: string): void { root.query = text; }
        function count(): int { return root.results.length; }
        function choose(index: int): void { root.choose(index); }
        function current(): string { return root.wallpaper; }
        function geometry(): string { return JSON.stringify({desktop: root.desktop, screens: Quickshell.screens.map(s => ({name: s.name, x: s.x, y: s.y, width: s.width, height: s.height}))}); }
        function isOpen(): bool { return root.pickerOpen; }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: background
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "mywm-wallpaper"
            color: root.theme.backgroundColor
            Item {
                anchors.fill: parent
                clip: true
                Image {
                    x: root.desktop.x - background.screen.x
                    y: root.desktop.y - background.screen.y
                    width: root.desktop.width
                    height: root.desktop.height
                    source: root.displayedWallpaper
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.ceil(root.desktop.width * root.desktop.scale)
                    sourceSize.height: Math.ceil(root.desktop.height * root.desktop.scale)
                    onStatusChanged: if (status === Image.Error) root.errorText = "Das gespeicherte Bild fehlt oder kann nicht geladen werden. Bitte neu auswählen.";
                }
            }
        }
    }
    PanelWindow {
        id: picker
        visible: root.pickerOpen
        screen: root.pickerScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "mywm-wallpaper-picker"
        color: "#b3000000"
        MouseArea { anchors.fill: parent; onClicked: root.pickerOpen = false }
        Column {
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 22
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "WALLPAPER"
                color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 14; font.bold: true
            }
            Item {
                id: carousel
                width: parent.width
                height: Math.min(475, picker.height * 0.58)
                readonly property real expandedWidth: Math.min(768, width * 0.64)
                readonly property real step: Math.min(78, width * 0.07)
                clip: true
                Repeater {
                    model: root.results
                    Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property int distance: index - root.selected
                        readonly property bool selected: distance === 0
                        visible: Math.abs(distance) <= 6
                        z: selected ? 10 : 6 - Math.abs(distance)
                        x: (carousel.width - carousel.expandedWidth) / 2 + (distance < 0 ? distance * carousel.step : distance > 0 ? carousel.expandedWidth + (distance - 1) * carousel.step : 0)
                        y: selected ? 0 : 20
                        width: selected ? carousel.expandedWidth : carousel.step + 24
                        height: carousel.height - (selected ? 0 : 40)
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.06, 0, 14, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; color: root.theme.surfaceColor
                            clip: true
                            Image {
                                anchors.fill: parent; anchors.margins: tile.selected ? 3 : 1
                                source: tile.visible ? tile.modelData.url : ""
                                sourceSize.width: 1000; sourceSize.height: 600
                                fillMode: Image.PreserveAspectCrop; asynchronous: true
                            }
                            Rectangle { anchors.fill: parent; color: "#66000000"; visible: !tile.selected }
                            Rectangle { anchors.fill: parent; color: "transparent"; border.width: tile.selected ? 3 : 1; border.color: tile.selected ? root.theme.accentColor : root.theme.borderColor }
                        }
                        MouseArea {
                            anchors.fill: parent; enabled: !root.saving; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (tile.selected) root.choose(tile.index); else root.selected = tile.index; }
                            onWheel: event => root.move(event.angleDelta.y < 0 ? 1 : -1)
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent; visible: !root.results.length
                    text: scan.running ? "Bilder werden geladen …" : "Keine passenden Bilder gefunden"
                    color: root.theme.textColor; font.family: root.theme.fontFamily
                }
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
                text: root.results.length ? root.results[root.selected].name : ""
                color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 20
            }
            TextField {
                id: search
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(420, parent.width); height: 40
                font.family: root.theme.fontFamily; font.pixelSize: 13
                text: root.query; onTextChanged: root.query = text
                placeholderText: "Bilder filtern …"
                color: root.theme.textColor; placeholderTextColor: root.theme.mutedColor
                selectionColor: root.theme.accentColor; selectedTextColor: root.theme.backgroundColor
                background: Rectangle { color: root.theme.backgroundColor; border.color: root.theme.borderColor }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) root.pickerOpen = false;
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) root.move(1);
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) root.move(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.choose(root.selected);
                    else return;
                    event.accepted = true;
                }
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                text: root.errorText || (root.saving ? "Wird gespeichert …" : (root.results.length ? root.selected + 1 : 0) + " / " + root.results.length + "  ·  ← → Auswahl  ·  ↵ Anwenden  ·  Esc")
                color: root.theme.textColor; font.family: root.theme.fontFamily; font.pixelSize: 12
            }
        }
    }
}
