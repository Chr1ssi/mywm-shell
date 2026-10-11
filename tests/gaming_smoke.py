#!/usr/bin/env python3
"""While the compositor reports a fullscreen game, only critical notifications pop up.

The bar runs in a nested MyWM-Smithay session but talks to a stand-in for the compositor's bar socket,
which sends `v1 gaming` as the test needs it (the compositor's own smoke test covers when it does).
"""
from pathlib import Path
import socket
import subprocess
import tempfile

from session import MYWM_BINARY, Session, wait_for

STATE = "v1 state 1,0,0,1280,800,1,0,0,1:0\nv1 scratchpad 0 0\nv1 locked 0\n"


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-gaming-") as directory:
        base = Path(directory)
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(base / "bar.sock"))
        server.listen(1)
        server.settimeout(15)
        bar = None
        with Session(base, outputs=1) as session, (base / "bar.log").open("w+") as bar_log:
            try:
                env = dict(session.env, MYWM_SOCKET=str(base / "bar.sock"))
                bar = subprocess.Popen([str(MYWM_BINARY), "--bar"], env=env, stdout=bar_log, stderr=subprocess.STDOUT)
                client, _ = server.accept()
                client.sendall((STATE + "v1 gaming 0\n").encode())

                def ipc(method):
                    if bar.poll() is not None:
                        raise AssertionError("Bar exited")
                    result = subprocess.run(["qs", "ipc", "--pid", str(bar.pid), "call", "bar", method],
                                            env=env, capture_output=True, text=True, timeout=2)
                    return result.stdout.strip()

                def notify(summary, *flags):
                    subprocess.run(["notify-send", *flags, summary, "Test", "--expire-time=30000"], env=env, check=True)

                wait_for(lambda: ipc("status") not in ("", "[]"))
                notify("vor dem Spiel")
                wait_for(lambda: ipc("toastCount") == "1")
                client.sendall(b"v1 gaming 1\n")
                # The open popup goes away, its notification stays in the list.
                wait_for(lambda: ipc("toastCount") == "0")
                notify("im Spiel")
                wait_for(lambda: ipc("notificationCount") == "2")
                assert ipc("toastCount") == "0", "a normal notification popped up over the game"
                notify("kritisch", "--urgency=critical")
                wait_for(lambda: ipc("toastCount") == "1")
                client.sendall(b"v1 gaming 0\n")
                notify("nach dem Spiel")
                wait_for(lambda: ipc("toastCount") == "2")
                print("Gaming smoke passed: popups held back over a game, critical ones shown, normal again afterwards")
            finally:
                if bar is not None and bar.poll() is None:
                    bar.terminate()
                    bar.wait(timeout=3)
                server.close()
                bar_log.seek(0)
                log = bar_log.read()
                print(log)
                # No PipeWire runs here, so the bar's audio service cannot connect; that is not under test.
                errors = [line for line in log.splitlines()
                          if any(e in line for e in ["ERROR", "ReferenceError", "TypeError"]) and "service.pipewire" not in line]
                assert not errors, "Bar QML error"


if __name__ == "__main__":
    main()
