#!/usr/bin/env python3
"""Run the real Quickshell launcher in an isolated nested MyWM-Smithay session, using harmless test apps."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from session import SHELL_ROOT, Session, wait_for as wait_until


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-launcher-") as directory:
        base = Path(directory)
        data = base / "data"
        apps = data / "applications"
        apps.mkdir(parents=True)
        marker = base / "launched.json"
        terminal_marker = base / "terminal.json"
        probe = base / "probe"
        probe.write_text("#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\n"
                         + f"Path({str(marker)!r}).write_text(json.dumps([sys.argv[1:], os.getcwd()]))\n")
        probe.chmod(0o755)
        terminal = base / "terminal"
        terminal.write_text("#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\n"
                            + f"Path({str(terminal_marker)!r}).write_text(json.dumps(sys.argv[1:]))\n")
        terminal.chmod(0o755)
        apps.joinpath("probe-browser.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName=Probe Browser\nGenericName=Web Browser\n"
            f"Comment=Browse test pages\nKeywords=internet;web;\nExec={probe} \"two words\" %U\nPath={base}\n")
        apps.joinpath("probe-terminal.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName=Probe Terminal\nExec={probe}\nTerminal=true\n")
        apps.joinpath("hidden.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName=Hidden Probe\nExec={probe}\nNoDisplay=true\n")
        session = Session(base, env=dict(
            XDG_DATA_HOME=str(data), XDG_DATA_DIRS=str(base / "empty"),
            MYWM_TERMINAL_COUNT="2", MYWM_TERMINAL_0=str(terminal), MYWM_TERMINAL_1="--test-arg",
            MYWM_COLOR_BACKGROUND="#1e1e2e", MYWM_COLOR_SURFACE="#313244",
            MYWM_COLOR_TEXT="#cdd6f4", MYWM_COLOR_MUTED="#a6adc8",
            MYWM_COLOR_ACCENT="#89b4fa", MYWM_COLOR_BORDER="#45475a"))
        env = session.env
        processes = []
        with session, (base / "launcher.log").open("w+") as launcher_log:
            try:
                def start():
                    process = subprocess.Popen(["qs", "-p", str(SHELL_ROOT / "quickshell/shell.qml"), "--no-duplicate"],
                                               env=env, stdout=launcher_log, stderr=subprocess.STDOUT)
                    processes.append(process)
                    def ready():
                        if process.poll() is not None:
                            raise AssertionError("Quickshell exited during startup")
                        result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "show"], env=env,
                                                capture_output=True, text=True, timeout=2)
                        return result.returncode == 0 and "launcher" in result.stdout
                    wait_until(ready)
                    return process

                def ipc(process, method, *args):
                    result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "launcher", method, *args],
                                            env=env, capture_output=True, text=True, timeout=3, check=True)
                    return result.stdout.strip()

                launcher = start()
                wait_until(lambda: ipc(launcher, "count") == "2")
                ipc(launcher, "search", "INTERNET web")
                assert ipc(launcher, "count") == "1"
                assert ipc(launcher, "current") == "probe-browser"
                ipc(launcher, "search", "no-such-application")
                assert ipc(launcher, "count") == "0"
                ipc(launcher, "launch")  # Empty results must not close the launcher.
                assert launcher.poll() is None
                ipc(launcher, "search", "")
                ipc(launcher, "move", "1")
                assert ipc(launcher, "current") == "probe-terminal"
                ipc(launcher, "search", "web")
                time.sleep(0.2)
                if os.environ.get("MYWM_LAUNCHER_SCREENSHOT"):
                    subprocess.run(["grim", os.environ["MYWM_LAUNCHER_SCREENSHOT"]], env=env, check=True, timeout=3)
                ipc(launcher, "launch")
                wait_until(marker.exists)
                assert json.loads(marker.read_text()) == [["two words"], str(base)]
                assert launcher.wait(timeout=3) == 0
                launcher = start()
                ipc(launcher, "search", "terminal")
                ipc(launcher, "launch")
                wait_until(terminal_marker.exists)
                assert json.loads(terminal_marker.read_text()) == ["--test-arg", "-e", str(probe)]
                assert launcher.wait(timeout=3) == 0
                launcher = start()
                ipc(launcher, "close")
                assert launcher.wait(timeout=3) == 0
                print("Launcher smoke test passed: real MyWM-Smithay/Quickshell, search, no matches, hidden entries, selection, GUI/terminal launch, cwd, reopen and close")
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=3)
                launcher_log.seek(0)
                log = launcher_log.read()
                print(log)
                if "ERROR" in log or "ReferenceError" in log or "TypeError" in log:
                    raise AssertionError("Quickshell reported errors")


if __name__ == "__main__":
    main()
