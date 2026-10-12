#!/usr/bin/env python3
"""The bar shows a recording indicator while the compositor reports a capture.

Like the gaming test, the bar talks to a stand-in for the compositor's bar socket.
"""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

from session import MYWM_BINARY, Session, wait_for

STATE = "v1 state 1,0,0,1280,800,1,0,0,1:0\nv1 scratchpad 0 0\nv1 locked 0\nv1 gaming 0\n"


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-capture-") as directory:
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

                def ipc(method):
                    if bar.poll() is not None:
                        raise AssertionError("Bar exited")
                    result = subprocess.run(["qs", "ipc", "--pid", str(bar.pid), "call", "bar", method],
                                            env=env, capture_output=True, text=True, timeout=2)
                    return result.stdout.strip()

                client.sendall((STATE + "v1 capture 0\nv1 config ok\n").encode())
                wait_for(lambda: ipc("status") not in ("", "[]"))
                assert ipc("capturing") == "false", "an indicator without a capture"
                client.sendall(b"v1 capture 1\n")
                wait_for(lambda: ipc("capturing") == "true")
                if os.environ.get("MYWM_CAPTURE_SCREENSHOT"):
                    time.sleep(0.3)
                    subprocess.run(["grim", os.environ["MYWM_CAPTURE_SCREENSHOT"]], env=env, check=True)
                client.sendall(b"v1 capture 0\n")
                wait_for(lambda: ipc("capturing") == "false")
                print("Capture smoke passed: the indicator follows the compositor's capture flag")
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
