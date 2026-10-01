import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Column {
    id: panel
    required property Theme theme
    property date shownMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date selectedDate: new Date()
    property var events: []
    property var calendars: []
    property string errorText: ""
    property bool createOpen: false
    spacing: 14

    function isoDate(date: date): string {
        return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
            + "-" + String(date.getDate()).padStart(2, "0");
    }
    function reload(): void {
        if (eventsProcess.running) return;
        const start = new Date(shownMonth.getFullYear(), shownMonth.getMonth(), 1);
        const end = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + 1, 8);
        eventsProcess.command = ["mywm-calendar", "events", isoDate(start), isoDate(end)];
        errorText = "";
        eventsProcess.running = true;
    }
    function shiftMonth(offset: int): void {
        shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + offset, 1);
        selectedDate = new Date(shownMonth.getFullYear(), shownMonth.getMonth(), 1);
        reload();
    }
    function dayNumber(index: int): int {
        return index - (shownMonth.getDay() + 6) % 7 + 1;
    }
    function validDay(day: int): bool {
        return day > 0 && day <= new Date(shownMonth.getFullYear(), shownMonth.getMonth() + 1, 0).getDate();
    }
    function dateForDay(day: int): date { return new Date(shownMonth.getFullYear(), shownMonth.getMonth(), day); }
    function isToday(day: int): bool { return validDay(day) && isoDate(dateForDay(day)) === isoDate(new Date()); }
    function isSelected(day: int): bool { return validDay(day) && isoDate(dateForDay(day)) === isoDate(selectedDate); }
    function eventsForDay(day: int): var {
        if (!validDay(day)) return [];
        const target = isoDate(dateForDay(day));
        return events.filter(event => event.startDate <= target && event.endDate >= target);
    }
    function selectedEvents(): var {
        const target = isoDate(selectedDate);
        return events.filter(event => event.startDate <= target && event.endDate >= target);
    }
    function upcomingEvents(): var {
        const today = isoDate(new Date());
        return events.filter(event => event.endDate >= today).slice(0, 8);
    }
    function submitEvent(): void {
        const title = titleField.text.trim();
        const start = startField.text.trim();
        const end = endField.text.trim();
        if (!title || !/^\d\d:\d\d$/.test(start) || !/^\d\d:\d\d$/.test(end)
                || end <= start || calendarBox.currentText === "") {
            errorText = "Bitte Titel sowie gültige Start- und Endzeit eingeben.";
            return;
        }
        createProcess.command = ["mywm-calendar", "create", calendarBox.currentText,
            isoDate(selectedDate), start, end, title, locationField.text.trim()];
        errorText = "";
        createProcess.running = true;
    }

    Component.onCompleted: { calendarsProcess.running = true; reload(); }

    Process {
        id: eventsProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try { panel.events = JSON.parse(text || "[]"); panel.errorText = ""; }
                catch (_) { panel.events = []; panel.errorText = "Termine konnten nicht gelesen werden."; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) panel.errorText = "Kalender ist noch nicht eingerichtet.";
        }
    }
    Process {
        id: calendarsProcess
        command: ["mywm-calendar", "calendars"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { panel.calendars = JSON.parse(text || "[]"); }
                catch (_) { panel.calendars = []; }
            }
        }
    }
    Process {
        id: createProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                titleField.text = ""; locationField.text = ""; panel.createOpen = false; panel.reload();
            } else panel.errorText = "Der Termin konnte nicht erstellt werden.";
        }
    }

    Row {
        width: parent.width; spacing: 8
        BarButton { theme: panel.theme; text: "‹"; onClicked: panel.shiftMonth(-1) }
        Text {
            width: parent.width - 96; anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: panel.shownMonth.toLocaleString(Qt.locale("de_DE"), "MMMM yyyy")
            color: panel.theme.textColor; font.family: panel.theme.fontFamily; font.pixelSize: 18
        }
        BarButton { theme: panel.theme; text: "›"; onClicked: panel.shiftMonth(1) }
    }

    Grid {
        width: parent.width; columns: 7; rowSpacing: 3; columnSpacing: 3
        Repeater {
            model: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
            Text {
                required property string modelData
                width: (panel.width - 18) / 7; height: 22
                text: modelData; horizontalAlignment: Text.AlignHCenter
                color: panel.theme.mutedColor; font.family: panel.theme.fontFamily; font.pixelSize: 13
            }
        }
        Repeater {
            model: 42
            Rectangle {
                id: dayCell
                required property int index
                readonly property int day: panel.dayNumber(index)
                readonly property bool valid: panel.validDay(day)
                readonly property var dayEvents: panel.eventsForDay(day)
                width: (panel.width - 18) / 7; height: 34; radius: 8
                color: panel.isSelected(day) ? panel.theme.accentColor
                    : panel.isToday(day) ? panel.theme.surfaceColor : "transparent"
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 3
                    text: dayCell.valid ? dayCell.day : ""
                    color: panel.isSelected(dayCell.day) ? panel.theme.backgroundColor : panel.theme.textColor
                    font.family: panel.theme.fontFamily; font.pixelSize: 14
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                    spacing: 2
                    Repeater {
                        model: dayCell.dayEvents.slice(0, 3)
                        Rectangle {
                            required property var modelData
                            width: 4; height: 4; radius: 2
                            color: modelData.color || panel.theme.accentColor
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent; enabled: dayCell.valid
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: panel.selectedDate = panel.dateForDay(dayCell.day)
                }
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: panel.theme.borderColor }
    Row {
        width: parent.width; spacing: 8
        Text {
            width: parent.width - 104
            text: "Termine am " + panel.selectedDate.toLocaleString(Qt.locale("de_DE"), "dd. MMMM")
            color: panel.theme.textColor; font.family: panel.theme.fontFamily; font.pixelSize: 16
        }
        BarButton { theme: panel.theme; text: "+"; selected: panel.createOpen; onClicked: panel.createOpen = !panel.createOpen }
        BarButton { theme: panel.theme; text: "󰑐"; onClicked: panel.reload() }
    }

    Column {
        visible: panel.createOpen; width: parent.width; spacing: 8
        TextField { id: titleField; width: parent.width; placeholderText: "Titel" }
        Row {
            width: parent.width; spacing: 8
            TextField { id: startField; width: (parent.width - 8) / 2; text: "09:00"; placeholderText: "Start (HH:MM)" }
            TextField { id: endField; width: (parent.width - 8) / 2; text: "10:00"; placeholderText: "Ende (HH:MM)" }
        }
        TextField { id: locationField; width: parent.width; placeholderText: "Ort (optional)" }
        ComboBox { id: calendarBox; width: parent.width; model: panel.calendars; textRole: "name"; valueRole: "name" }
        BarButton {
            width: parent.width; theme: panel.theme
            text: createProcess.running ? "Wird gespeichert …" : "Termin erstellen"
            enabled: !createProcess.running; onClicked: panel.submitEvent()
        }
    }

    Text {
        visible: panel.errorText !== ""; width: parent.width
        text: panel.errorText; wrapMode: Text.WordWrap
        color: panel.theme.mutedColor; font.family: panel.theme.fontFamily; font.pixelSize: 14
    }
    Repeater {
        model: panel.selectedEvents()
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
                    id: eventColumn; width: parent.width - 13; spacing: 2
                    Text {
                        width: parent.width; text: modelData.title || "(Ohne Titel)"; elide: Text.ElideRight
                        color: panel.theme.textColor; font.family: panel.theme.fontFamily; font.pixelSize: 15
                    }
                    Text {
                        width: parent.width
                        text: (modelData.allDay ? "Ganztägig" : modelData.startTime + "–" + modelData.endTime)
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
        visible: panel.errorText === "" && panel.selectedEvents().length === 0; width: parent.width
        text: "Keine Termine an diesem Tag."; color: panel.theme.mutedColor
        font.family: panel.theme.fontFamily; font.pixelSize: 14
    }
    Rectangle { width: parent.width; height: 1; color: panel.theme.borderColor }
    Text {
        width: parent.width; text: "Nächste Termine"
        color: panel.theme.textColor
        font.family: panel.theme.fontFamily; font.pixelSize: 16
    }
    Repeater {
        model: panel.upcomingEvents()
        Rectangle {
            required property var modelData
            width: panel.width; height: upcomingColumn.implicitHeight + 14; radius: 12
            color: panel.theme.glassSurfaceColor
            Row {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 9
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4; height: upcomingColumn.height; radius: 2
                    color: modelData.color || panel.theme.accentColor
                }
                Column {
                    id: upcomingColumn; width: parent.width - 13; spacing: 2
                    Text {
                        width: parent.width; text: modelData.title || "(Ohne Titel)"; elide: Text.ElideRight
                        color: panel.theme.textColor; font.family: panel.theme.fontFamily; font.pixelSize: 15
                    }
                    Text {
                        width: parent.width
                        text: modelData.startDate.split("-").reverse().slice(0, 2).join(".") + ".  ·  "
                            + (modelData.allDay ? "Ganztägig" : modelData.startTime + "–" + modelData.endTime)
                            + "  ·  " + modelData.calendar
                        elide: Text.ElideRight; color: panel.theme.mutedColor
                        font.family: panel.theme.fontFamily; font.pixelSize: 13
                    }
                }
            }
        }
    }
    Text {
        visible: panel.errorText === "" && panel.upcomingEvents().length === 0; width: parent.width
        text: "Keine anstehenden Termine im geladenen Zeitraum."; color: panel.theme.mutedColor
        font.family: panel.theme.fontFamily; font.pixelSize: 14
    }
    BarButton {
        width: panel.width; theme: panel.theme; text: "Kalender-App öffnen"
        onClicked: Quickshell.execDetached(["kitty", "--class", "mywm-calendar", "--title", "Kalender", "mywm-calendar", "app"])
    }
}
