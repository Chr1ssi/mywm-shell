#!/usr/bin/env python3
"""The shell's language: every text in I18n.tr() has its English entry, and real Quickshell picks the language
from the system's locale variables (no compositor needed)."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from session import SHELL_ROOT

QML = SHELL_ROOT / "quickshell"
PROBE = """import QtQuick
import Quickshell
ShellRoot {
    // Quickshell ignores Qt.quit() before its event loop runs (in Component.onCompleted).
    Timer {
        running: true; interval: 1
        onTriggered: {
            console.log("PROBE " + JSON.stringify([I18n.language, I18n.tr("Falsches Passwort"),
                                                   I18n.tr("Automatisch in %1 Sekunden", 5)]));
            Qt.quit();
        }
    }
}
"""


def main():
    table = (QML / "I18n.qml").read_text()
    english = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)": "', table, re.M))
    used = {text for path in QML.glob("*.qml") for text in re.findall(r'I18n\.tr\("((?:[^"\\]|\\.)*)"', path.read_text())}
    assert not used - english, f"without English text: {sorted(used - english)}"
    assert not english - used, f"English text nobody uses: {sorted(english - used)}"

    cases = [
        ({"LANG": "de_DE.UTF-8"}, ["de", "Falsches Passwort", "Automatisch in 5 Sekunden"]),
        # Dates in German do not make the texts German: LC_TIME is not the language.
        ({"LANG": "en_US.UTF-8", "LC_TIME": "de_DE.UTF-8"}, ["en", "Wrong password", "Automatically in 5 seconds"]),
        ({"LANG": "en_US.UTF-8", "LC_MESSAGES": "de_DE.UTF-8"}, ["de", "Falsches Passwort", "Automatisch in 5 Sekunden"]),
        ({"LANG": "en_US.UTF-8", "LC_ALL": "de_AT.UTF-8"}, ["de", "Falsches Passwort", "Automatisch in 5 Sekunden"]),
        # LANGUAGE lists the preferences; the first one the shell knows wins.
        ({"LANG": "en_US.UTF-8", "LANGUAGE": "fr:de:en"}, ["de", "Falsches Passwort", "Automatisch in 5 Sekunden"]),
        ({"LANG": "fr_FR.UTF-8"}, ["en", "Wrong password", "Automatically in 5 seconds"]),
        ({"LANG": "C"}, ["en", "Wrong password", "Automatically in 5 seconds"]),
    ]
    with tempfile.TemporaryDirectory(prefix="mywm-i18n-") as directory:
        base = Path(directory)
        shutil.copy(QML / "I18n.qml", base)
        (base / "shell.qml").write_text(PROBE)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        clean = {key: value for key, value in os.environ.items()
                 if not key.startswith("LC_") and key not in ("LANG", "LANGUAGE", "WAYLAND_DISPLAY")}
        clean.update(QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(base / "state"),
                     XDG_CACHE_HOME=str(base / "cache"))
        for variables, expected in cases:
            result = subprocess.run(["qs", "-p", str(base / "shell.qml")], env=clean | variables,
                                    capture_output=True, text=True, timeout=20)
            probe = re.search(r"PROBE (\[.*\])", result.stdout + result.stderr)
            assert probe, f"{variables}: no answer from Quickshell\n{result.stdout}{result.stderr}"
            assert json.loads(probe.group(1)) == expected, f"{variables}: {probe.group(1)}, expected {expected}"
    print(f"I18n smoke passed: {len(used)} texts with English, language from {len(cases)} locale setups")


if __name__ == "__main__":
    main()
