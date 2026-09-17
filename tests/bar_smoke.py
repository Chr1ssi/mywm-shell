#!/usr/bin/env python3
"""Real isolated River/Quickshell bar test; never executes host power actions."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time

SHELL_ROOT = Path(__file__).resolve().parents[1]
ROOT = Path(os.environ.get("MYWM_SOURCE_DIR", str(SHELL_ROOT.parent / "mywm"))).resolve()


def wait_for(fn):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for bar/WM")


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-bar-") as directory:
        base = Path(directory)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, MYWM_SHELL_DIR=str(SHELL_ROOT / "quickshell"), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"), GDK_BACKEND="wayland",
                   WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="3", WLR_RENDERER="pixman",
                   QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software", QT_QUICK_CONTROLS_STYLE="Basic",
                   MYWM_CONFIG=str(ROOT / "config/mywm.toml"), MYWM_SOCKET=str(runtime / "control.sock"))
        for key in ["WAYLAND_DISPLAY", "WAYLAND_SOCKET", "DISPLAY"]:
            env.pop(key, None)
        config = base / "mywm.toml"
        config.write_text((ROOT / "config/mywm.toml").read_text().replace("DP-1", "HEADLESS-3").replace("DP-3", "HEADLESS-1").replace("HDMI-A-1", "HEADLESS-2"))
        env["MYWM_CONFIG"] = str(config)
        mock_bin = base / "bin"
        mock_bin.mkdir()
        power_log = base / "power.log"
        mock = mock_bin / "systemctl"
        mock.write_text("#!/usr/bin/python3\nimport sys\nfrom pathlib import Path\n" +
                        f"with Path({str(power_log)!r}).open('a') as f: f.write(sys.argv[1] + '\\n')\n")
        mock.chmod(0o755)
        env["PATH"] = str(mock_bin) + ":" + env["PATH"]
        pipewire_config = base / "pipewire.conf"
        config_text = Path("/usr/share/pipewire/pipewire.conf").read_text()
        config_text = config_text.replace("context.objects = [", """context.objects = [
            { factory = adapter args = { factory.name = support.null-audio-sink node.name = test-sink media.class = Audio/Sink audio.position = [ FL FR ] } }
            { factory = metadata args = { metadata.name = default metadata.values = [ { key = default.audio.sink value = { name = test-sink } } ] } }
        """, 1)
        pipewire_config.write_text(config_text)
        pipewire = subprocess.Popen(["pipewire", "-c", str(pipewire_config)], env=env,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        bar = None
        with (base / "river.log").open("w+") as river_log, (base / "bar.log").open("w+") as bar_log:
            river = subprocess.Popen(["river", "-no-xwayland", "-c", str(ROOT / "target/debug/mywm")], env=env,
                                     stdout=river_log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                wait_for(lambda: Path(env["MYWM_SOCKET"]).exists())
                env["WAYLAND_DISPLAY"] = next(p.name for p in runtime.glob("wayland-*") if p.is_socket())
                bar = subprocess.Popen([str(ROOT / "target/debug/mywm"), "--bar"], env=env,
                                       stdout=bar_log, stderr=subprocess.STDOUT)

                def ipc(method, *args):
                    if bar.poll() is not None:
                        raise AssertionError("Bar exited")
                    return subprocess.run(["qs", "ipc", "--pid", str(bar.pid), "call", "bar", method, *map(str, args)],
                                          env=env, capture_output=True, text=True, timeout=2)

                def status():
                    result = ipc("status")
                    return json.loads(result.stdout) if result.returncode == 0 else []
                def mapped_status():
                    outputs = status()
                    return outputs if len(outputs) == 3 and all(len(o["workspaces"]) == 3 for o in outputs) else None
                outputs = wait_for(mapped_status)
                assert sorted(n for o in outputs for n in o["workspaces"]) == list(range(1, 10))
                before_active = {o["id"]: o["active"] for o in outputs}
                subprocess.run(["pw-metadata", "-n", "default", "0", "default.audio.sink", '{"name":"test-sink"}', "Spa:String:JSON"], env=env, check=True, capture_output=True)
                wait_for(lambda: json.loads(ipc("audioStatus").stdout))
                assert ipc("volume", "0.37").returncode == 0
                wait_for(lambda: abs(json.loads(ipc("audioStatus").stdout)["volume"] - 0.37) < 0.01)
                assert ipc("mute").returncode == 0
                wait_for(lambda: json.loads(ipc("audioStatus").stdout)["muted"])
                # Observe the actual isolated PipeWire node, not only QML's local value.
                graph = json.loads(subprocess.check_output(["pw-dump"], env=env, text=True))
                sink = next(n for n in graph if n.get("info", {}).get("props", {}).get("node.name") == "test-sink")
                props = sink["info"]["params"]["Props"][0]
                assert props["mute"] is True
                assert ipc("volume", "0.5").returncode == 0
                target = outputs[0]["id"]
                selected = outputs[0]["workspaces"][1]
                assert ipc("workspace", target, selected).returncode == 0
                wait_for(lambda: next(o for o in status() if o["id"] == target)["active"] == selected)
                assert all(o["active"] == before_active[o["id"]] for o in status() if o["id"] != target)
                with socket.socket(socket.AF_UNIX) as client:
                    client.settimeout(3)
                    client.connect(env["MYWM_SOCKET"])
                    initial = client.recv(4096)
                    assert b"v1 state" in initial
                    client.sendall(b"v2 logout\nv1 workspace 0 99\n")
                    assert b"v1 error" in client.recv(4096)
                if os.environ.get("MYWM_BAR_SCREENSHOT"):
                    subprocess.run(["grim", os.environ["MYWM_BAR_SCREENSHOT"]], env=env, check=True)
                assert ipc("menu", 0).returncode == 0
                time.sleep(0.2)
                if os.environ.get("MYWM_POWER_SCREENSHOT"):
                    subprocess.run(["grim", os.environ["MYWM_POWER_SCREENSHOT"]], env=env, check=True)
                for action in ["reboot", "poweroff"]:
                    before = power_log.read_text() if power_log.exists() else ""
                    assert ipc("choosePower", 0, action).returncode == 0
                    time.sleep(0.1)
                    assert (power_log.read_text() if power_log.exists() else "") == before
                    assert ipc("confirmPower", 0).returncode == 0
                    wait_for(lambda: power_log.exists() and power_log.read_text() != before)
                assert power_log.read_text().splitlines() == ["reboot", "poweroff"]
                # Restart only the bar; initial state must restore the active workspace.
                bar.terminate()
                bar.wait(timeout=3)
                bar = subprocess.Popen([str(ROOT / "target/debug/mywm"), "--bar"], env=env,
                                       stdout=bar_log, stderr=subprocess.STDOUT)
                wait_for(lambda: status() and status()[0]["active"] == selected)
                # Logout terminates this isolated compositor, not the host session.
                with socket.socket(socket.AF_UNIX) as client:
                    client.connect(env["MYWM_SOCKET"])
                    client.sendall(b"v1 logout\n")
                    river.wait(timeout=5)
                print("Bar smoke passed: three outputs with distinct workspace groups, workspace switch, independent workspaces, invalid commands, bar restart, PipeWire volume/mute, confirmed power commands, logout")
            finally:
                if bar is not None and bar.poll() is None:
                    bar.terminate()
                    bar.wait(timeout=3)
                if river.poll() is None:
                    os.killpg(river.pid, signal.SIGTERM)
                    river.wait(timeout=3)
                pipewire.terminate()
                pipewire.wait(timeout=3)
                bar_log.seek(0)
                log = bar_log.read()
                print(log)
                river_log.seek(0)
                print(river_log.read())
                checked = log
                assert not any(error in checked for error in ["ERROR", "ReferenceError", "TypeError"]), "Bar QML error"


if __name__ == "__main__":
    main()
