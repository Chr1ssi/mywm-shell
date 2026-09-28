# mywm-shell

Quickshell-Oberfläche für mywm: Bar, Launcher, Audio, Medien, Systemtray,
Benachrichtigungen und ein durchgehendes Wallpaper mit Picker.

## Entwicklung

Die Repositories liegen standardmäßig nebeneinander:

```text
Projects/
├── mywm/
└── mywm-shell/
    ├── quickshell/
    └── tests/
```

Der Flake stellt ein eigenständiges `mywm-shell`-Paket bereit.
Der Sitzungsstart in mywm verwaltet Bar und Wallpaper. `mywm --bar` und
`mywm --wallpaper` übergeben Theme und Hilfsprogramme; Super+Space öffnet den Launcher.
`MYWM_SHELL_DIR` kann auf einen anderen absoluten QML-Ordner zeigen.

Die gemeinsame Palette bleibt in mywms TOML unter `[appearance]`.
Das eigenständige `mywm-shell`-Programm startet Bar, Launcher, Wallpaper, Picker, Idle-Verhalten und Sitzungssperre. Die Bar kommuniziert über `MYWM_SOCKET` mit mywm.

## Eigenständiges Paket

```sh
nix run . -- bar
nix run . -- launcher
nix run . -- wallpaper
nix run . -- lock
```

Wallpaper-Verzeichnis, Farben, Terminal und Idle-Zeiten lassen sich über die in `scripts/mywm-shell` dokumentierten `MYWM_SHELL_*`- beziehungsweise Laufzeitvariablen konfigurieren.

## Tests

Zuerst in mywm `cargo build` ausführen. Danach hier:

```sh
python3 tests/launcher_smoke.py
python3 tests/bar_smoke.py
python3 tests/wallpaper_smoke.py
```

Die Tests verwenden isolierte Headless-River-Sitzungen. Benötigt werden außerdem
Kanshi, Grim und für den Bar-Test PipeWire samt Kommandozeilenwerkzeugen.
`MYWM_SOURCE_DIR` erlaubt einen anderen Pfad zum mywm-Repository.


## Gestaltung und Bedienung

Die zentrale TOML-Palette von mywm färbt alle Komponenten ein. Die Bar bleibt
30 Pixel hoch und verwendet JetBrainsMono Nerd Font, auch für die Symbole.

- **Wallpaper:** Omarchy-inspiriertes Karussell mit großer Auswahl, schrägen
  Nachbarvorschauen und abgedunkeltem Hintergrund. Pfeiltasten oder Mausrad
  wechseln die Vorschau. Klick auf ein Nachbarbild wählt es aus; Klick auf die
  Auswahl oder Enter übernimmt es für alle Monitore. Tippen filtert Dateinamen,
  Escape oder Klick auf den Hintergrund schließt den Picker.
- **Audio:** Klick auf die Lautstärke öffnet Ausgabe, Mikrofone und App-Streams.
  Gerätenamen wählen das Standardgerät; Regler und Prozentknopf steuern
  Lautstärke und Stummschaltung. Rechtsklick auf das Audio-Symbol schaltet stumm,
  Mausrad ändert die Lautstärke in 5-Prozent-Schritten. Gerätewechsel benötigen
  einen PipeWire-Sessionmanager wie WirePlumber.
- **Kalender:** Klick auf Datum und Uhrzeit öffnet eine Monatsübersicht. Farbige
  Punkte markieren Tage mit Terminen; ein Klick auf einen Tag zeigt dessen
  Agenda. Über `+` lassen sich Termin, Uhrzeit, Ort und Zielkalender direkt im
  Panel erfassen. Der Knopf am Panelende startet die vollständige Kalender-App.
- **Medien:** Ein laufender MPRIS-Player erscheint mittig direkt neben Datum
  und Uhrzeit. Wenn nichts wiedergegeben wird, bleibt der Medienbereich komplett
  ausgeblendet. Ein Klick öffnet mittig das Panel mit Cover, Titel, Interpret
  und Wiedergabesteuerung. Nicht unterstützte Aktionen sind deaktiviert.
- **Tray:** StatusNotifierItem-Icons mit Tooltip, Linksklick zum Aktivieren,
  Rechtsklick für das App-Menü, Mittelklick und Scroll-Unterstützung.
  Passive Einträge sind ausgeblendet, Aufmerksamkeit wird markiert.
- **Benachrichtigungen:** Die Shell stellt selbst den Freedesktop-Notification-
  Dienst bereit; Dunst wird daher nicht benötigt und darf nicht parallel laufen.
  Toasts erscheinen rechts oben, unterstützen Bilder und Aktionen und landen im
  Verlauf hinter dem Glockensymbol. Kritische Meldungen bleiben stehen, normale
  und niedrige Dringlichkeiten verschwinden nach ihrer jeweiligen Ablaufzeit.
- **Power:** Mittige, schwebende Icon-Auswahl für Sperren, Abmelden, Neustart und
  Ausschalten. Für die letzten drei Aktionen erscheint ein icon-zentrierter
  Fünf-Sekunden-Countdown; danach wird die Aktion automatisch ausgeführt.
  Escape, ein Klick außerhalb oder „Abbrechen“ stoppen den Countdown. Tab und
  Enter erlauben Tastaturbedienung.

Kalender-, Audio- und Medienpanels schließen über × oder Escape. Sie und das Powermenü
öffnen auf dem Monitor der angeklickten Bar.

Gestaltungsreferenzen: [Omarchy Image Picker](https://github.com/basecamp/omarchy/blob/quattro/shell/plugins/image-picker/ImagePicker.qml)
und [Noctalia](https://github.com/noctalia-dev/noctalia).
