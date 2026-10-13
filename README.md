# mywm-shell

Quickshell-Oberfläche für mywm: Bar, Launcher, Commandcenter, Audio, Medien, Systemtray,
Benachrichtigungen, Sperrbildschirm, Anmeldebildschirm (greetd) und den Wallpaper-Picker (das Bild selbst zeichnet MyWM-Smithay).

## Entwicklung

Die Repositories liegen standardmäßig nebeneinander:

```text
Projects/
├── MyWM-Smithay/
└── mywm-shell/
    ├── quickshell/
    └── tests/
```

Der Flake stellt ein eigenständiges `mywm-shell`-Paket bereit.
Der Sitzungsstart von MyWM-Smithay verwaltet Bar und Wallpaper-Picker. `mywm-compositor --bar` und
`mywm-compositor --wallpaper` übergeben Theme und Hilfsprogramme; Super+Space öffnet den Launcher.
`MYWM_SHELL_DIR` kann auf einen anderen absoluten QML-Ordner zeigen.

Die gemeinsame Palette bleibt in mywms TOML unter `[appearance]`.
Das eigenständige `mywm-shell`-Programm startet Bar, Launcher, Wallpaper-Picker, Idle-Verhalten und Sitzungssperre. Die Bar kommuniziert über `MYWM_SOCKET` mit mywm.

## Eigenständiges Paket

```sh
nix run . -- bar
nix run . -- launcher
nix run . -- wallpaper
nix run . -- lock
```

Wallpaper-Verzeichnis, Farben, Terminal und Idle-Zeiten lassen sich über die in `scripts/mywm-shell` dokumentierten `MYWM_SHELL_*`- beziehungsweise Laufzeitvariablen konfigurieren.

## Tests

```sh
nix develop -c tests/run-smoke              # alle Tests
nix develop -c tests/run-smoke bar launcher # einzelne
```

Die Tests starten echtes Quickshell aus diesem Repository in abgeschotteten,
nested MyWM-Smithay-Sitzungen: ein eigenes Xvfb, ein eigener D-Bus ohne
Dienst-Aktivierung, eigene Laufzeit-, Konfigurations- und Statusverzeichnisse.
Die laufende Sitzung bleibt unberührt. Der Compositor ist das Nix-Paket des
MyWM-Smithay-Checkouts daneben (`MYWM_SOURCE_DIR` für einen anderen Pfad,
`MYWM_TEST_BINARY` für ein anderes Binary). Gedrehte Ausgänge prüft der
Wallpaper-Test nicht, weil der nested Compositor sie ungedreht aufnimmt.
Der Commandcenter-Test bekommt einen nachgebauten BlueZ-Dienst (`tests/fake_bluez.py`)
auf einem eigenen Systembus sowie Platzhalter für `gammastep`, `ip` und `wl-copy`.
Der Sperrbildschirm-Test prüft Passwörter über ein eigenes PAM-Verzeichnis (`pam_exec` mit einem
Testpasswort, nie ein echtes Konto), der Anmeldebildschirm-Test spricht mit einem nachgebauten
greetd (`tests/fake_greetd.py`).


## Gestaltung und Bedienung

Die zentrale TOML-Palette von mywm färbt alle Komponenten ein. Die Bar bleibt
30 Pixel hoch und verwendet JetBrainsMono Nerd Font, auch für die Symbole.

- **Wallpaper:** Omarchy-inspiriertes Karussell mit großer Auswahl, schrägen
  Nachbarvorschauen und abgedunkeltem Hintergrund. Pfeiltasten oder Mausrad
  wechseln die Vorschau. Klick auf ein Nachbarbild wählt es aus; Klick auf die
  Auswahl oder Enter übernimmt es für alle Monitore. Tippen filtert Dateinamen,
  Escape oder Klick auf den Hintergrund schließt den Picker.
- **Commandcenter:** Das Symbol links neben der Glocke zeigt den Zustand (Bluetooth an
  oder verbunden, Nachtlicht an, sonst ein Zahnrad) und öffnet das Panel. Die Kacheln
  schalten Bluetooth und das Nachtlicht. Darunter stehen die lokalen IPv4-Adressen,
  ein Klick kopiert eine. Die Geräteliste zeigt gekoppelte Geräte mit Akkustand zum
  Verbinden und Trennen; „Suchen“ findet neue, „Koppeln“ koppelt sie und vertraut ihnen,
  damit sie sich später selbst verbinden. Bluetooth braucht BlueZ
  (`hardware.bluetooth.enable`). Das Nachtlicht hält `gammastep -O 4000` am Laufen,
  solange es an ist (über das Gamma-Protokoll des Compositors, also nur auf echter
  Hardware); die Wahl liegt in `$XDG_STATE_HOME/mywm/night-light` und gilt auch nach
  der nächsten Anmeldung.
- **Audio:** Klick auf die Lautstärke öffnet Ausgabe, Mikrofone und App-Streams.
  Gerätenamen wählen das Standardgerät; Regler und Prozentknopf steuern
  Lautstärke und Stummschaltung. Rechtsklick auf das Audio-Symbol schaltet stumm,
  Mausrad ändert die Lautstärke in 5-Prozent-Schritten. Gerätewechsel benötigen
  einen PipeWire-Sessionmanager wie WirePlumber.
- **Kalender:** Klick auf Datum und Uhrzeit öffnet eine Monatsübersicht. Farbige
  Punkte markieren Tage mit Terminen; ein Klick auf einen Tag zeigt dessen
  Agenda. Über `+` lassen sich Termin, Uhrzeit, Ort und Zielkalender direkt im
  Panel erfassen. Der Knopf am Panelende startet die vollständige Kalender-App.
- **Medien:** Ein laufender MPRIS-Player erscheint als eigene Pill mittig links
  neben Datum und Uhrzeit. Wenn nichts wiedergegeben wird, bleibt die Pill
  komplett ausgeblendet. Ein Klick öffnet mittig das Panel mit Cover, Titel, Interpret
  und Wiedergabesteuerung. Nicht unterstützte Aktionen sind deaktiviert.
- **Tray:** StatusNotifierItem-Icons mit Tooltip, Linksklick zum Aktivieren,
  Rechtsklick für das App-Menü, Mittelklick und Scroll-Unterstützung.
  Passive Einträge sind ausgeblendet, Aufmerksamkeit wird markiert.
- **Benachrichtigungen:** Die Shell stellt selbst den Freedesktop-Notification-
  Dienst bereit; Dunst wird daher nicht benötigt und darf nicht parallel laufen.
  Toasts erscheinen rechts oben, unterstützen Bilder und Aktionen und landen im
  Verlauf hinter dem Glockensymbol. Kritische Meldungen bleiben stehen, normale
  und niedrige Dringlichkeiten verschwinden nach ihrer jeweiligen Ablaufzeit.
- **Power:** Eigene Pill ganz rechts, getrennt von Mitteilungen und Audio. Sie
  öffnet eine mittige, schwebende Icon-Auswahl für Sperren, Abmelden, Neustart und
  Ausschalten. Für die letzten drei Aktionen erscheint ein icon-zentrierter
  Fünf-Sekunden-Countdown; danach wird die Aktion automatisch ausgeführt.
  Escape, ein Klick außerhalb oder „Abbrechen“ stoppen den Countdown. Tab und
  Enter erlauben Tastaturbedienung.

- **Sperrbildschirm** (`lock.qml`): startet der Compositor (`Super+Escape`, Idle). Wallpaper auf
  jedem Monitor, große Uhr und eine Glas-Karte mit Passwortfeld nur auf dem Hauptmonitor (der mit
  Workspace 1, `MYWM_PRIMARY_OUTPUT`); getippt werden kann auf jedem. Das Passwort prüft PAM
  (Dienst `mywm-lock`, `MYWM_PAM_DIR` für ein anderes Verzeichnis). Nur eine erfolgreiche
  Prüfung entsperrt. Stirbt der Sperrbildschirm, bleibt die Sitzung gesperrt und der
  Compositor startet einen neuen, der die Sperre übernimmt.
- **Anmeldebildschirm** (`greeter.qml`): für greetd, gestartet von `mywm-compositor --greeter`
  (NixOS: `programs.mywm.greeter`). Gleiche Karte wie beim Sperrbildschirm, dazu Benutzername,
  Sitzungswahl (bei mehr als einer Sitzung) sowie Neustart und Ausschalten. Wallpaper und
  Farben spiegelt mywm in das Greeter-Verzeichnis. Umgebung: `MYWM_GREETER_BACKGROUND`,
  `MYWM_GREETER_USER`, `MYWM_GREETER_SESSIONS` (Verzeichnis der `wayland-sessions`),
  `MYWM_THEME_STATE`.

Commandcenter-, Kalender-, Audio- und Medienpanels schließen über × oder Escape. Sie und das Powermenü
öffnen auf dem Monitor der angeklickten Bar.

Gestaltungsreferenzen: [Omarchy Image Picker](https://github.com/basecamp/omarchy/blob/quattro/shell/plugins/image-picker/ImagePicker.qml)
und [Noctalia](https://github.com/noctalia-dev/noctalia).
