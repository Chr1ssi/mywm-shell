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


def lock_ipc(env, method):
    """Call the running lock screen (if any) over Quickshell's IPC."""
    pids = subprocess.run(["pgrep", "-f", "lock.qml"], capture_output=True, text=True).stdout.split()
    if not pids:
        return ""
    return subprocess.run(["qs", "ipc", "--pid", pids[0], "call", "lock", method], env=env,
                          capture_output=True, text=True, timeout=2).stdout.strip()


def pam_directory(base):
    """A PAM service `mywm-lock` that accepts PASSWORD only."""
    modules = os.environ["MYWM_TEST_PAM_MODULES"]
    check = base / "check-password"
    # pam_exec hands the password over on stdin, ended by a NUL.
    check.write_text(f"#!/usr/bin/env bash\nIFS= read -r -d '' password\n[ \"$password\" = {PASSWORD} ]\n")
    check.chmod(0o755)
    pam = base / "pam.d"
    pam.mkdir()
    (pam / "mywm-lock").write_text(f"auth required {modules}/pam_exec.so expose_authtok quiet {check}\n"
                                   f"account required {modules}/pam_permit.so\n")
    return pam


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-lock-") as directory:
        base = Path(directory)
        pam = pam_directory(base)

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
                return lock_ipc(env, "message")

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
                wait_for(lambda: lock_ipc(env, "ready") == "true")

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
                wait_for(lambda: lock_ipc(env, "ready") == "true", 10)
                assert locked(), "the session got unlocked when the locker died"
                screenshot("replaced")
                type_password(PASSWORD)
                wait_for(lambda: not locked() and not lockers(), 10)
                print("replaced locker OK")
                print("OK")
            except BaseException:
                print("lockers:", lockers(), "bar:", lines[-5:])
                raise


def second_monitor():
    """With the pointer on the monitor without the card, the password still reaches the lock screen."""
    with tempfile.TemporaryDirectory(prefix="mywm-lock2-") as directory:
        base = Path(directory)
        pam = pam_directory(base)
        config = '[bindings]\nfocus_output_right = ["Super+Ctrl+period"]\n'
        with Session(base, outputs=2, config=config, env={"MYWM_PAM_DIR": str(pam)}) as session:
            env = session.env
            window = subprocess.check_output(["xdotool", "search", "--onlyvisible", "--name", "Smithay"],
                                             env=env).split()[0].decode()
            subprocess.run(["xdotool", "windowfocus", window], env=env, check=True)
            subprocess.run(["xdotool", "key", "--delay", "80", "alt+ctrl+period"], env=env, check=True)
            time.sleep(0.5)
            result = subprocess.run([str(MYWM_BINARY), "--lock"], env=env, timeout=20)
            assert result.returncode == 0, "--lock got no confirmation"
            wait_for(lambda: lock_ipc(env, "ready") == "true")
            subprocess.run(["xdotool", "type", "--delay", "40", PASSWORD], env=env, check=True)
            subprocess.run(["xdotool", "key", "Return"], env=env, check=True)
            wait_for(lambda: not subprocess.run(["pgrep", "-f", "lock.qml"], capture_output=True).stdout, 10)
            print("password typed on the second monitor OK")


if __name__ == "__main__":
    main()
    second_monitor()
