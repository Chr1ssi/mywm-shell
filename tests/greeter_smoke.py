#!/usr/bin/env python3
"""The login screen (greeter.qml) on `mywm-compositor --greeter` against a stand-in for greetd: a wrong password is
refused, the right one starts the picked session, and then the greeter and the compositor end, as greetd needs."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

from session import SHELL_ROOT, Session, wait_for

TESTS = Path(__file__).resolve().parent
USER, PASSWORD = "tester", "geheim"


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-greeter-") as directory:
        base = Path(directory)
        sessions = base / "sessions"
        sessions.mkdir()
        (sessions / "mywm.desktop").write_text("[Desktop Entry]\nName=mywm\nExec=/run/mywm-launch\nType=Application\n")
        (sessions / "other.desktop").write_text("[Desktop Entry]\nName=Andere\nExec=/run/other-launch --flag %U\n")
        greetd_log = base / "greetd"
        greetd_log.touch()
        greetd = subprocess.Popen(["python3", str(TESTS / "fake_greetd.py"), str(base / "greetd.sock"), USER, PASSWORD,
                                   str(greetd_log)])
        wait_for(lambda: "ready" in greetd_log.read_text())
        greeter = f"qs --path {SHELL_ROOT / 'quickshell' / 'greeter.qml'}"
        env = {"GREETD_SOCK": str(base / "greetd.sock"), "MYWM_GREETER_USER": USER,
               "MYWM_GREETER_SESSIONS": str(sessions)}
        try:
            # Two monitors: the login screen is on both, and typing works wherever the keyboard goes.
            with Session(base, outputs=2, env=env, args=["--greeter", greeter]) as session:
                env = session.env
                window = subprocess.check_output(["xdotool", "search", "--onlyvisible", "--name", "Smithay"],
                                                 env=env).split()[0].decode()

                # Quickshell itself: the compositor's command line names greeter.qml too.
                def greeter_pid():
                    result = subprocess.run(["pgrep", "-f", "greeter.qml"], capture_output=True, text=True)
                    for pid in result.stdout.split():
                        try:
                            if "quickshell" in Path(f"/proc/{pid}/comm").read_text():
                                return int(pid)
                        except OSError:
                            pass
                    return None

                def ipc(method, *args):
                    return subprocess.run(["qs", "ipc", "--pid", str(greeter_pid()), "call", "greeter", method, *args],
                                          env=env, capture_output=True, text=True, timeout=2).stdout.strip()

                def type_password(text):
                    subprocess.run(["xdotool", "windowfocus", window], env=env, check=True)
                    subprocess.run(["xdotool", "type", "--delay", "40", text], env=env, check=True)
                    subprocess.run(["xdotool", "key", "Return"], env=env, check=True)

                def screenshot(name):
                    if os.environ.get("MYWM_GREETER_SCREENSHOTS"):
                        subprocess.run(["grim", f"{os.environ['MYWM_GREETER_SCREENSHOTS']}/{name}.png"], env=env, check=True)

                def requests():
                    return greetd_log.read_text().splitlines()

                wait_for(lambda: greeter_pid() and ipc("sessions").startswith("[{"), 15)
                assert '"name":"Andere"' in ipc("sessions"), ipc("sessions")
                time.sleep(1)
                screenshot("greeter")

                type_password("falsch")
                wait_for(lambda: ipc("message") == "Falsches Passwort")
                # Quickshell ends the failed session itself (cancel_session).
                assert requests()[1:3] == [f"create_session {USER}", "response wrong"], requests()
                print("wrong password OK")

                # The second session (sorted by file name: other.desktop), its field codes left out.
                ipc("pickSession", "1")
                type_password(PASSWORD)
                wait_for(lambda: "start_session /run/other-launch --flag" in requests())
                # greetd starts the session once the greeter is gone; the compositor ends with it.
                wait_for(lambda: session.process.poll() is not None, 10)
                assert session.process.returncode == 0, session.process.returncode
                print("login OK")
                print("OK")
        finally:
            greetd.terminate()


if __name__ == "__main__":
    main()
