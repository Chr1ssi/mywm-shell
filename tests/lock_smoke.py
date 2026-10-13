#!/usr/bin/env python3
"""The lock screen (lock.qml), started by the compositor: a wrong password keeps the session locked, the right one
unlocks, and a locker that dies is replaced by one that takes over the lock. PAM checks a test password through
its own service directory (pam_exec), never a real account."""
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time

from session import MYWM_BINARY, Session, wait_for

PASSWORD = "geheim"


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-lock-") as directory:
        base = Path(directory)
        modules = os.environ["MYWM_TEST_PAM_MODULES"]
        check = base / "check-password"
        # pam_exec hands the password over on stdin, ended by a NUL.
        check.write_text(f"#!/usr/bin/env bash\nIFS= read -r -d '' password\n[ \"$password\" = {PASSWORD} ]\n")
        check.chmod(0o755)
        pam = base / "pam.d"
        pam.mkdir()
        (pam / "mywm-lock").write_text(f"auth required {modules}/pam_exec.so expose_authtok quiet {check}\n"
                                       f"account required {modules}/pam_permit.so\n")

        with Session(base, env={"MYWM_PAM_DIR": str(pam)}) as session:
            env = session.env
            window = subprocess.check_output(["xdotool", "search", "--onlyvisible", "--name", "Smithay"],
                                             env=env).split()[0].decode()
            bar = socket.socket(socket.AF_UNIX)
            bar.connect(env["MYWM_SOCKET"])
            bar.settimeout(0.1)
            lines = []

            def locked():
                try:
                    lines.extend(bar.recv(65536).decode().splitlines())
                except socket.timeout:
                    pass
                states = [line for line in lines if line.startswith("v1 locked ")]
                return bool(states) and states[-1] == "v1 locked 1"

            def lockers():
                result = subprocess.run(["pgrep", "-f", "lock.qml"], capture_output=True, text=True)
                return [int(pid) for pid in result.stdout.split()]

            def message():
                pids = lockers()
                if not pids:
                    return ""
                return subprocess.run(["qs", "ipc", "--pid", str(pids[0]), "call", "lock", "message"], env=env,
                                      capture_output=True, text=True, timeout=2).stdout.strip()

            def type_password(text):
                subprocess.run(["xdotool", "windowfocus", window], env=env, check=True)
                subprocess.run(["xdotool", "type", "--delay", "40", text], env=env, check=True)
                subprocess.run(["xdotool", "key", "Return"], env=env, check=True)

            def screenshot(name):
                if os.environ.get("MYWM_LOCK_SCREENSHOTS"):
                    subprocess.run(["grim", f"{os.environ['MYWM_LOCK_SCREENSHOTS']}/{name}.png"], env=env, check=True)

            def lock():
                result = subprocess.run([str(MYWM_BINARY), "--lock"], env=env, timeout=20)
                assert result.returncode == 0, "--lock got no confirmation"
                wait_for(locked)
                time.sleep(1)

            try:
                lock()
                screenshot("locked")
                type_password("falsch")
                wait_for(lambda: message() == "Falsches Passwort")
                screenshot("wrong")
                assert locked(), "a wrong password unlocked"
                type_password(PASSWORD)
                wait_for(lambda: not locked() and not lockers(), 10)
                print("password OK")

                # A locker that dies leaves the session locked; the compositor starts another, which takes over.
                lock()
                [first] = lockers()
                os.kill(first, signal.SIGKILL)
                wait_for(lambda: lockers() and lockers() != [first], 10)
                time.sleep(2)
                assert locked(), "the session got unlocked when the locker died"
                screenshot("replaced")
                type_password(PASSWORD)
                wait_for(lambda: not locked() and not lockers(), 10)
                print("replaced locker OK")
                print("OK")
            except BaseException:
                print("lockers:", lockers(), "bar:", lines[-5:])
                raise


if __name__ == "__main__":
    main()
