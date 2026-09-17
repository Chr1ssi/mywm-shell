# mywm-shell

Eigene Quickshell-Oberfläche für mywm: Bar, Launcher und ein durchgehendes
Wallpaper mit Picker. Benachrichtigungen sind noch geplant.

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
