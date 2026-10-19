pragma Singleton
import QtQuick
import Quickshell

// The shell's texts in the system language. The German text in the QML is the key; every other
// language takes its table here, English stands in for languages without one. The language is the
// first of the system's UI languages (LANGUAGE, LC_ALL, LC_MESSAGES, LANG) that the shell knows;
// dates and times follow Qt.locale() (LC_TIME) instead.
Singleton {
    readonly property var tables: ({ en: english })
    readonly property string language: {
        for (const name of Qt.locale().uiLanguages) {
            const language = name.split("-")[0];
            if (language === "de" || language in tables) return language;
        }
        return "en";
    }

    // tr("Automatisch in %1 Sekunden", 5): the text in the shell's language, %1, %2, … by the arguments.
    function tr(text: string, ...args): string {
        const table = tables[language];
        let result = table && table[text] !== undefined ? table[text] : text;
        args.forEach((value, index) => result = result.split("%" + (index + 1)).join(String(value)));
        return result;
    }

    readonly property var english: ({
        "(Ohne Titel)": "(Untitled)",
        "%1 / %2  ·  ← → Auswahl  ·  ↵ Anwenden  ·  Esc": "%1 / %2  ·  ← → select  ·  ↵ apply  ·  Esc",
        "%1 Apps  ·  ↑↓ Auswahl  ·  ↵ Start  ·  Esc": "%1 apps  ·  ↑↓ select  ·  ↵ launch  ·  Esc",
        "%1 Benachrichtigungen": "%1 notifications",
        "%1 verbunden": "%1 connected",
        "1 Benachrichtigung": "1 notification",
        "Abbrechen": "Cancel",
        "Abmelden": "Log out",
        "Aktion fehlgeschlagen (%1)": "Action failed (%1)",
        "Alle löschen": "Clear all",
        "An": "On",
        "Andere Ausgänge ausblenden": "Hide other outputs",
        "Andere Eingänge ausblenden": "Hide other inputs",
        "Anderen Ausgang wählen": "Choose another output",
        "Anderes Mikrofon wählen": "Choose another microphone",
        "Anmeldung nicht möglich (%1)": "Cannot sign in (%1)",
        "Anmeldung nicht möglich: %1": "Cannot sign in: %1",
        "ANWENDUNGEN": "APPLICATIONS",
        "Anwendung": "Application",
        "Anwendungen": "Applications",
        "App suchen …": "Search apps …",
        "Aufnahme": "Recording",
        "Aus": "Off",
        "Ausgabe": "Output",
        "Ausschalten": "Shut down",
        "Auswahl konnte nicht gespeichert werden.": "The selection could not be saved.",
        "Automatisch in %1 Sekunden": "Automatically in %1 seconds",
        "Benachrichtigung": "Notification",
        "Benachrichtigungen": "Notifications",
        "Benutzername": "User name",
        "Bilder filtern …": "Filter images …",
        "Bilder werden geladen …": "Loading images …",
        "Bildordner konnte nicht gelesen werden: %1": "The image folder could not be read: %1",
        "Bis zur Korrektur gilt die zuletzt geladene Konfiguration, beim Start die Standardwerte.": "Until it is fixed, the last loaded configuration applies, or the defaults at startup.",
        "Bitte Titel sowie gültige Start- und Endzeit eingeben.": "Please enter a title and a valid start and end time.",
        "Bluetooth ist aus": "Bluetooth is off",
        "Commandcenter": "Command center",
        "Der Termin konnte nicht erstellt werden.": "The event could not be created.",
        "Dieses Bild kann nicht geladen werden.": "This image cannot be loaded.",
        "Ende (HH:MM)": "End (HH:MM)",
        "Esc zum Schließen": "Esc to close",
        "Falsches Passwort": "Wrong password",
        "Farbpipette": "Color picker",
        "Farbschema konnte nicht erzeugt werden.": "The color scheme could not be generated.",
        "Fenster anklicken · Kachel daneben oder Enter: ganzer Monitor · D: dynamisch, mit den Cast-Tasten umschaltbar · Esc: abbrechen": "Click a window · tile beside it or Enter: whole monitor · D: dynamic, switchable with the cast keys · Esc: cancel",
        "Ganztägig": "All day",
        "Gekoppelt": "Paired",
        "Geräte": "Devices",
        "Gespeicherte Auswahl konnte nicht gelesen werden.": "The saved selection could not be read.",
        "Kalender": "Calendar",
        "Kalender ist noch nicht eingerichtet.": "The calendar is not set up yet.",
        "Kalender-App öffnen": "Open calendar app",
        "Kein Adapter": "No adapter",
        "Kein Ausgabegerät": "No output device",
        "Kein Eingabegerät": "No input device",
        "Keine aktive Wiedergabe": "Nothing is playing",
        "Keine aktiven Anwendungen": "No active applications",
        "Keine anstehenden Termine im geladenen Zeitraum.": "No upcoming events in the loaded period.",
        "Keine Benachrichtigungen": "No notifications",
        "Keine gekoppelten Geräte": "No paired devices",
        "Keine passenden Anwendungen": "No matching applications",
        "Keine passenden Bilder gefunden": "No matching images found",
        "Keine Termine an diesem Tag.": "No events on this day.",
        "Keine Termine in den nächsten 31 Tagen.": "No events in the next 31 days.",
        "Keine Verbindung": "No connection",
        "Klick kopiert die Farbe · Esc: abbrechen": "Click copies the color · Esc: cancel",
        "Konfiguration fehlerhaft": "Configuration error",
        "Kopiert": "Copied",
        "Koppeln": "Pair",
        "Koppeln …": "Pairing …",
        "Medien": "Media",
        "Mikrofon": "Microphone",
        "Nachtlicht": "Night light",
        "Nächste Termine": "Upcoming events",
        "Netzwerk": "Network",
        "Neu": "New",
        "Neu starten": "Restart",
        "Neustart": "Restart",
        "Ort (optional)": "Location (optional)",
        "Passwort": "Password",
        "Sitzung startet …": "Starting session …",
        "Sitzung und System": "Session and system",
        "Sperren": "Lock",
        "Stumm": "Muted",
        "Suche beenden": "Stop searching",
        "Suche läuft …": "Searching …",
        "Suchen": "Search",
        "Termin erstellen": "Create event",
        "Termine am %1": "Events on %1",
        "Termine konnten nicht gelesen werden.": "The events could not be read.",
        "Titel": "Title",
        "Trennen": "Disconnect",
        "Trennen …": "Disconnecting …",
        "Verbinden": "Connect",
        "Verbinden …": "Connecting …",
        "Verbunden": "Connected",
        "Verbunden · %1 %": "Connected · %1 %",
        "Was soll geteilt werden?": "What should be shared?",
        "Wird gespeichert …": "Saving …",
        "Zu viele Versuche": "Too many attempts"
    })
}
