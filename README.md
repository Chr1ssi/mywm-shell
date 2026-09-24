# mywm-shell

Eigene Quickshell-Oberfläche für mywm: Bar, Launcher, Audio, Medien, Systemtray
und ein durchgehendes Wallpaper mit Picker. Benachrichtigungen sind noch geplant.

## Entwicklung

Die Repositories liegen standardmäßig nebeneinander:

```text
Projects/
├── mywm/
└── mywm-shell/
    ├── quickshell/
    └── tests/
```

Benötigt werden Quickshell (getestet mit 0.3.1), River und das gebaute mywm.
Der Sitzungsstart in mywm verwaltet Bar und Wallpaper. `mywm --bar` und
`mywm --wallpaper` übergeben Theme und Hilfsprogramme; Super+Space öffnet den Launcher.
`MYWM_SHELL_DIR` kann auf einen anderen absoluten QML-Ordner zeigen.

Die gemeinsame Palette bleibt in mywms TOML unter `[appearance]`.
IPC, Umgebungsvariablen und Hilfsbefehle sind im
[Integrationsvertrag](../mywm/docs/quickshell.md) beschrieben.
Die Shell benötigt derzeit weiterhin mywm für Wallpaper-Dateiliste und Sitzungssperre.

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

Das Repository wurde aus bisher unversionierten Shell-Dateien ausgegliedert;
es gab dafür keine Git-Historie zu übertragen. Es ist noch kein Remote eingerichtet.

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
  Ausschalten. Die letzten drei Aktionen verlangen weiterhin Bestätigung.
  Escape schließt das Menü; Tab und Enter erlauben Tastaturbedienung.

Audio- und Medienpanels schließen über × oder Escape. Sie und das Powermenü
öffnen auf dem Monitor der angeklickten Bar.

Gestaltungsreferenzen: [Omarchy Image Picker](https://github.com/basecamp/omarchy/blob/quattro/shell/plugins/image-picker/ImagePicker.qml)
und [Noctalia](https://github.com/noctalia-dev/noctalia).
