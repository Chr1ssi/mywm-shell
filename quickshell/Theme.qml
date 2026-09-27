import QtQuick
import Quickshell
import Quickshell.Io

// mywm supplies the central TOML palette. Direct QML runs use the system palette.
SystemPalette {
    id: root
    property var generated: ({})
    function color(name, fallback) {
        const token = generated.colors && generated.colors[name];
        return token && token.default && token.default.hex ? token.default.hex : fallback;
    }
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int panelPadding: 16
    readonly property int barHeight: 30
    readonly property color backgroundColor: color("surface", Quickshell.env("MYWM_COLOR_BACKGROUND") || window)
    readonly property color surfaceColor: color("surface_container", Quickshell.env("MYWM_COLOR_SURFACE") || base)
    readonly property color textColor: color("on_surface", Quickshell.env("MYWM_COLOR_TEXT") || text)
    readonly property color mutedColor: color("on_surface_variant", Quickshell.env("MYWM_COLOR_MUTED") || placeholderText)
    readonly property color accentColor: color("primary", Quickshell.env("MYWM_COLOR_ACCENT") || highlight)
    readonly property color borderColor: color("outline_variant", Quickshell.env("MYWM_COLOR_BORDER") || mid)

    property FileView themeFile: FileView {
        id: themeFile
        path: Quickshell.env("MYWM_THEME_STATE") || ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed.version === 1 && parsed.colors) root.generated = parsed;
            } catch (error) {
                console.warn("Could not parse mywm theme:", error);
            }
        }
    }
}
