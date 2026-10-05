"""An isolated, nested MyWM-Smithay session for the smoke tests.

Needs an X server ($DISPLAY), the compositor binary in `MYWM_TEST_BINARY` and the libraries it opens
nested in `MYWM_TEST_LIBRARY_PATH`; `tests/run-smoke` provides all of them.
"""
import os
from pathlib import Path
import signal
import subprocess
import time

SHELL_ROOT = Path(__file__).resolve().parents[1]
MYWM_BINARY = Path(os.environ.get("MYWM_TEST_BINARY", "mywm-compositor"))


def wait_for(fn, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for the shell or the compositor")


class Session:
    """The compositor with `outputs` outputs side by side (1280x800 each), its own runtime,
    config and state directories, and no environment of a running session."""

    def __init__(self, base, outputs=1, config="", env=None):
        if not os.environ.get("DISPLAY"):
            raise AssertionError("DISPLAY is not set; run the tests through tests/run-smoke")
        self.base = Path(base)
        runtime = self.base / "runtime"
        runtime.mkdir(mode=0o700)
        self.config = self.base / "mywm.toml"
        # Top-level keys must precede the first table.
        self.config.write_text("xwayland = false\n" + config)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("MYWM_") and key not in ("WAYLAND_DISPLAY", "WAYLAND_SOCKET")}
        self.env.update(MYWM_SHELL_DIR=str(SHELL_ROOT / "quickshell"), MYWM_CONFIG=str(self.config),
                        MYWM_SOCKET=str(runtime / "control.sock"), MYWM_LOG_FILE="off",
                        MYWM_VIRTUAL_OUTPUTS=str(outputs - 1), RUST_LOG="info",
                        XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(self.base / "config"),
                        XDG_STATE_HOME=str(self.base / "state"), GDK_BACKEND="wayland",
                        QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software", QT_QUICK_CONTROLS_STYLE="Basic")
        self.env.update(env or {})
        self.log = (self.base / "compositor.log").open("w+")
        compositor_env = dict(self.env)
        if os.environ.get("MYWM_TEST_LIBRARY_PATH"):
            compositor_env["LD_LIBRARY_PATH"] = os.environ["MYWM_TEST_LIBRARY_PATH"]
        self.process = subprocess.Popen([str(MYWM_BINARY)], env=compositor_env, stdout=self.log,
                                        stderr=subprocess.STDOUT, start_new_session=True)
        wait_for(lambda: Path(self.env["MYWM_SOCKET"]).exists() or self.process.poll() is not None, 15)
        if self.process.poll() is not None:
            raise AssertionError("The compositor exited:\n" + self.compositor_log())
        self.env["WAYLAND_DISPLAY"] = next(p.name for p in runtime.glob("wayland-*") if p.is_socket())

    def compositor_log(self):
        self.log.seek(0)
        return self.log.read()

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            self.process.wait(timeout=5)
        self.log.close()

    def __enter__(self):
        return self

    def __exit__(self, kind, error, trace):
        if error is not None:
            print(self.compositor_log()[-3000:])
        self.close()
