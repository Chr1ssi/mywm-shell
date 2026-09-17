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
        Qt.callLater(() => { search.forceActiveFocus(); grid.positionViewAtIndex(selected, GridView.Contain); });
    }
    function move(delta: int): void {
        if (!results.length) return;
        selected = Math.max(0, Math.min(results.length - 1, selected + delta));
        grid.positionViewAtIndex(selected, GridView.Contain);
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
        implicitWidth: Math.min(960, (screen ? screen.width : 992) - 32)
        implicitHeight: Math.min(700, (screen ? screen.height : 732) - 64)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "mywm-wallpaper-picker"
        color: "transparent"
        Rectangle {
            anchors.fill: parent; radius: 14
            color: root.theme.backgroundColor
            border.width: 2; border.color: root.theme.accentColor
            Column {
                anchors.fill: parent; anchors.margins: 20; spacing: 12
                Text { text: "Wallpaper · über alle Monitore"; color: root.theme.textColor; font.pixelSize: 22; font.bold: true }
                TextField {
                    id: search
                    width: parent.width; height: 44
                    text: root.query; onTextChanged: root.query = text
                    placeholderText: "Nach Dateiname suchen …"
                    color: root.theme.textColor; placeholderTextColor: root.theme.mutedColor
                    selectionColor: root.theme.accentColor; selectedTextColor: root.theme.backgroundColor
                    background: Rectangle { color: root.theme.surfaceColor; radius: 7 }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) root.pickerOpen = false;
                        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.move(1);
                        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) root.move(-1);
                        else if (event.key === Qt.Key_Down) root.move(grid.columns);
                        else if (event.key === Qt.Key_Up) root.move(-grid.columns);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.choose(root.selected);
                        else return;
                        event.accepted = true;
                    }
                }
                GridView {
                    id: grid
                    readonly property int columns: Math.max(1, Math.floor(width / 210))
                    width: parent.width; height: Math.max(80, picker.height - 188)
                    cellWidth: width / columns; cellHeight: 155
                    clip: true
                    model: root.results
                    currentIndex: root.selected
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        width: grid.cellWidth - 8; height: grid.cellHeight - 8; radius: 7
                        color: root.theme.surfaceColor
                        border.width: index === root.selected ? 2 : 0; border.color: root.theme.accentColor
                        Image {
                            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 6 }
                            height: 110
                            source: tile.modelData.url
                            sourceSize.width: 240; sourceSize.height: 160
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                        }
                        Text {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 8 }
                            text: tile.modelData.name; elide: Text.ElideMiddle
                            color: root.theme.textColor; font.pixelSize: 12
                        }
                        MouseArea { anchors.fill: parent; enabled: !root.saving; onClicked: root.choose(tile.index) }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.results.length
                        text: scan.running ? "Bilder werden geladen …" : "Keine passenden Bilder gefunden"
                        color: root.theme.mutedColor
                    }
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: root.errorText || (root.results.length + " Bilder · Pfeiltasten auswählen · Enter/Klick anwenden · Esc schließen")
                    color: root.theme.mutedColor; font.pixelSize: 12
                }
            }
        }
    }
}
