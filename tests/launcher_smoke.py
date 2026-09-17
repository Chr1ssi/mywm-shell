#!/usr/bin/env python3
"""Run real Quickshell on an isolated headless River, using harmless test apps."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

SHELL_ROOT = Path(__file__).resolve().parents[1]
ROOT = Path(os.environ.get("MYWM_SOURCE_DIR", str(SHELL_ROOT.parent / "mywm"))).resolve()


def wait_until(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for test process")


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-launcher-") as directory:
        base = Path(directory)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        data = base / "data"
        apps = data / "applications"
        apps.mkdir(parents=True)
        marker = base / "launched.json"
        terminal_marker = base / "terminal.json"
        probe = base / "probe"
        probe.write_text("#!/usr/bin/python3\nimport json,os,sys\nfrom pathlib import Path\n"
                         + f"Path({str(marker)!r}).write_text(json.dumps([sys.argv[1:], os.getcwd()]))\n")
        probe.chmod(0o755)
        terminal = base / "terminal"
        terminal.write_text("#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n"
                            + f"Path({str(terminal_marker)!r}).write_text(json.dumps(sys.argv[1:]))\n")
        terminal.chmod(0o755)
        apps.joinpath("probe-browser.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName=Probe Browser\nGenericName=Web Browser\n"
            f"Comment=Browse test pages\nKeywords=internet;web;\nExec={probe} \"two words\" %U\nPath={base}\n")
        apps.joinpath("probe-terminal.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName=Probe Terminal\nExec={probe}\nTerminal=true\n")
        apps.joinpath("hidden.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName=Hidden Probe\nExec={probe}\nNoDisplay=true\n")
        env = dict(os.environ, MYWM_SHELL_DIR=str(SHELL_ROOT / "quickshell"), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   XDG_DATA_HOME=str(data), XDG_DATA_DIRS=str(base / "empty"),
                   WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1", WLR_RENDERER="pixman",
                   QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software", QT_QUICK_CONTROLS_STYLE="Basic",
                   MYWM_CONFIG=str(ROOT / "config/mywm.toml"), MYWM_SOCKET=str(runtime / "control.sock"),
                   MYWM_TERMINAL_COUNT="2", MYWM_TERMINAL_0=str(terminal), MYWM_TERMINAL_1="--test-arg",
                   MYWM_COLOR_BACKGROUND="#1e1e2e", MYWM_COLOR_SURFACE="#313244",
                   MYWM_COLOR_TEXT="#cdd6f4", MYWM_COLOR_MUTED="#a6adc8",
                   MYWM_COLOR_ACCENT="#89b4fa", MYWM_COLOR_BORDER="#45475a")
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("WAYLAND_SOCKET", None)
        env.pop("DISPLAY", None)
        processes = []
        with (base / "river.log").open("w+") as river_log, (base / "launcher.log").open("w+") as launcher_log:
            river = subprocess.Popen(["river", "-no-xwayland", "-c", str(ROOT / "target/debug/mywm")],
                                     env=env, stdout=river_log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                wait_until(lambda: any(p.is_socket() for p in runtime.glob("wayland-*")))
                env["WAYLAND_DISPLAY"] = next(p.name for p in runtime.glob("wayland-*") if p.is_socket())
                def keymap_ready():
                    river_log.seek(0)
                    return "Keyboard layout: de" in river_log.read()
                wait_until(keymap_ready)

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
                print("Launcher smoke test passed: real River/Quickshell, search, no matches, hidden entries, selection, GUI/terminal launch, cwd, reopen and close")
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=3)
                if river.poll() is None:
                    os.killpg(river.pid, signal.SIGTERM)
                river.wait(timeout=3)
                launcher_log.seek(0)
                log = launcher_log.read()
                print(log)
                if "ERROR" in log or "ReferenceError" in log or "TypeError" in log:
                    raise AssertionError("Quickshell reported errors")


if __name__ == "__main__":
    main()
