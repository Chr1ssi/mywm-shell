import QtQuick
import Quickshell

// mywm supplies the central TOML palette. Direct QML runs use the system palette.
SystemPalette {
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int panelPadding: 16
    readonly property int barHeight: 30
    readonly property color backgroundColor: Quickshell.env("MYWM_COLOR_BACKGROUND") || window
    readonly property color surfaceColor: Quickshell.env("MYWM_COLOR_SURFACE") || base
    readonly property color textColor: Quickshell.env("MYWM_COLOR_TEXT") || text
    readonly property color mutedColor: Quickshell.env("MYWM_COLOR_MUTED") || placeholderText
    readonly property color accentColor: Quickshell.env("MYWM_COLOR_ACCENT") || highlight
    readonly property color borderColor: Quickshell.env("MYWM_COLOR_BORDER") || mid
}
