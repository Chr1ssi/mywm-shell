import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Column {
    id: panel
    required property Theme theme
    property date shownMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property var events: []
    property string errorText: ""
    spacing: 14

    function reload(): void {
        if (eventsProcess.running) return;
        errorText = "";
        eventsProcess.running = true;
    }
    function shiftMonth(offset: int): void {
        shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + offset, 1);
    }
    function dayNumber(index: int): int {
        const firstWeekday = (shownMonth.getDay() + 6) % 7;
        return index - firstWeekday + 1;
    }
    function validDay(day: int): bool {
        return day > 0 && day <= new Date(shownMonth.getFullYear(), shownMonth.getMonth() + 1, 0).getDate();
    }
    function isToday(day: int): bool {
        const today = new Date();
        return validDay(day) && day === today.getDate()
            && shownMonth.getMonth() === today.getMonth()
            && shownMonth.getFullYear() === today.getFullYear();
    }
    function eventTime(value: string): string {
        const match = value.match(/(?:^|\s)(\d\d:\d\d)(?::\d\d)?$/);
        return match ? match[1] : "Ganztägig";
    }

    Component.onCompleted: reload()

    Process {
        id: eventsProcess
        command: ["mywm-calendar", "events", "31d"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    panel.events = JSON.parse(text || "[]");
                    panel.errorText = "";
                } catch (_) {
                    panel.events = [];
                    panel.errorText = "Termine konnten nicht gelesen werden.";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) panel.errorText = "Kalender ist noch nicht eingerichtet.";
        }
    }

    Row {
        width: parent.width
        spacing: 8
        BarButton { theme: panel.theme; text: "‹"; onClicked: panel.shiftMonth(-1) }
        Text {
            width: parent.width - 96
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: panel.shownMonth.toLocaleString(Qt.locale("de_DE"), "MMMM yyyy")
            color: panel.theme.textColor
            font.family: panel.theme.fontFamily; font.pixelSize: 18
        }
        BarButton { theme: panel.theme; text: "›"; onClicked: panel.shiftMonth(1) }
    }

    Grid {
        width: parent.width
        columns: 7
        rowSpacing: 3
        columnSpacing: 3
        Repeater {
            model: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
            Text {
                required property string modelData
                width: (panel.width - 18) / 7; height: 22
                text: modelData; horizontalAlignment: Text.AlignHCenter
                color: panel.theme.mutedColor
                font.family: panel.theme.fontFamily; font.pixelSize: 13
            }
        }
        Repeater {
            model: 42
            Rectangle {
                required property int index
                readonly property int day: panel.dayNumber(index)
                width: (panel.width - 18) / 7; height: 28; radius: 8
                color: panel.isToday(day) ? panel.theme.accentColor : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: parent.day > 0 && panel.validDay(parent.day) ? parent.day : ""
                    color: panel.isToday(parent.day) ? panel.theme.backgroundColor : panel.theme.textColor
                    font.family: panel.theme.fontFamily; font.pixelSize: 14
                }
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: panel.theme.borderColor }
    Row {
        width: parent.width
        Text {
            width: parent.width - 48; text: "Nächste Termine"
            color: panel.theme.textColor
            font.family: panel.theme.fontFamily; font.pixelSize: 16
        }
        BarButton { theme: panel.theme; text: "󰑐"; onClicked: panel.reload() }
    }
    Text {
        visible: panel.errorText !== ""; width: parent.width
        text: panel.errorText; wrapMode: Text.WordWrap
        color: panel.theme.mutedColor
        font.family: panel.theme.fontFamily; font.pixelSize: 14
    }
    Repeater {
        model: panel.events.slice(0, 8)
        Rectangle {
            required property var modelData
            width: panel.width; height: eventColumn.implicitHeight + 14; radius: 12
            color: panel.theme.glassSurfaceColor
            Row {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 9
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4; height: eventColumn.height; radius: 2
                    color: modelData.color || panel.theme.accentColor
                }
                Column {
                    id: eventColumn
                    width: parent.width - 13
                    spacing: 2
                    Text {
                        width: parent.width; text: modelData.title || "(Ohne Titel)"; elide: Text.ElideRight
                        color: panel.theme.textColor
                        font.family: panel.theme.fontFamily; font.pixelSize: 15
                    }
                    Text {
                        width: parent.width
                        text: panel.eventTime(modelData.start)
                            + "  ·  " + modelData.calendar
                            + (modelData.location ? "  ·  " + modelData.location : "")
                        elide: Text.ElideRight; color: panel.theme.mutedColor
                        font.family: panel.theme.fontFamily; font.pixelSize: 13
                    }
                }
            }
        }
    }
    Text {
        visible: panel.errorText === "" && panel.events.length === 0; width: parent.width
        text: "Keine Termine in den nächsten 31 Tagen."; color: panel.theme.mutedColor
        font.family: panel.theme.fontFamily; font.pixelSize: 14
    }
    BarButton {
        width: panel.width; theme: panel.theme; text: "Kalender-App öffnen"
        onClicked: Quickshell.execDetached(["foot", "--app-id", "mywm-calendar", "--title", "Kalender", "mywm-calendar", "app"])
    }
}
