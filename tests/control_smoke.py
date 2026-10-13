#!/usr/bin/env python3
"""The command center against a stand-in for BlueZ (tests/fake_bluez.py on a private system bus) and stand-ins for
gammastep, ip and wl-copy: everything is clicked like a user would, and the stand-ins record what the shell did."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

from session import SHELL_ROOT, Session, wait_for

TESTS = Path(__file__).resolve().parent
SYSTEM_BUS = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:path={path}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
"""


def stub(directory, name, script):
    path = directory / name
    path.write_text("#!/usr/bin/env bash\n" + script)
    path.chmod(0o755)


def main():
    with tempfile.TemporaryDirectory(prefix="mywm-control-") as directory:
        base = Path(directory)
        stubs = base / "bin"
        stubs.mkdir()
        record = base / "record"
        # gammastep keeps running while the night light is on; ip reports one address; wl-copy takes it.
        stub(stubs, "gammastep", f'echo "gammastep $*" >> {record}\ntrap \'echo "gammastep stopped" >> {record}; exit 0\' TERM\nwhile true; do sleep 0.1; done\n')
        stub(stubs, "ip", 'echo "2: eno1    inet 192.168.1.23/24 brd 192.168.1.255 scope global eno1"\n')
        stub(stubs, "wl-copy", f'echo "copy $*" >> {record}\n')
        record.touch()

        bus_config = base / "system-bus.conf"
        bus_config.write_text(SYSTEM_BUS.format(path=base / "system_bus"))
        system_bus = subprocess.Popen(["dbus-daemon", "--nofork", f"--config-file={bus_config}"])
        wait_for(lambda: (base / "system_bus").exists())
        bus_env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=f"unix:path={base / 'system_bus'}")
        bluez_log = base / "bluez"
        bluez_log.touch()
        bluez = subprocess.Popen(["python3", str(TESTS / "fake_bluez.py"), str(bluez_log)], env=bus_env)
        wait_for(lambda: "ready" in bluez_log.read_text())

        state = base / "state" / "mywm"
        state.mkdir(parents=True)
        session = Session(base, env={"DBUS_SYSTEM_BUS_ADDRESS": bus_env["DBUS_SYSTEM_BUS_ADDRESS"],
                                     "PATH": f"{stubs}:{os.environ['PATH']}"})
        env = session.env
        bar = None
        with session, (base / "bar.log").open("w+") as bar_log:
            try:
                # Straight through qs: `mywm-compositor --bar` puts its own tools (wl-copy) in front of the stand-ins.
                def start_bar():
                    return subprocess.Popen(["qs", "--path", str(SHELL_ROOT / "quickshell" / "bar.qml")], env=env,
                                            stdout=bar_log, stderr=subprocess.STDOUT)

                def ipc(method, *args):
                    if bar.poll() is not None:
                        raise AssertionError("Bar exited")
                    return subprocess.run(["qs", "ipc", "--pid", str(bar.pid), "call", "bar", method, *map(str, args)],
                                          env=env, capture_output=True, text=True, timeout=2)

                window = subprocess.check_output(["xdotool", "search", "--onlyvisible", "--name", "Smithay"],
                                                 env=env).split()[0].decode()

                def click(x, y):
                    subprocess.run(["xdotool", "mousemove", "--window", window, str(x), str(y), "click", "1"], env=env, check=True)
                    time.sleep(0.4)

                def calls():
                    return bluez_log.read_text().splitlines()

                def recorded():
                    return record.read_text().splitlines()

                def screenshot(name):
                    if os.environ.get("MYWM_CONTROL_SCREENSHOTS"):
                        subprocess.run(["grim", f"{os.environ['MYWM_CONTROL_SCREENSHOTS']}/{name}.png"], env=env, check=True)

                bar = start_bar()
                wait_for(lambda: ipc("status").returncode == 0 and ipc("status").stdout.strip() not in ("", "[]"))
                assert ipc("panel", "0", "control").returncode == 0
                time.sleep(1)
                screenshot("off")

                # Bluetooth is off: the tile switches it on, and the paired headset shows up.
                click(*BLUETOOTH_TILE)
                wait_for(lambda: "set hci0 Powered True" in calls())
                time.sleep(0.5)
                screenshot("on")
                click(*FIRST_DEVICE_BUTTON)
                wait_for(lambda: "call dev_11_11_11_11_11_11 Connect" in calls())
                # A search finds the speaker; pairing trusts it too.
                click(*SEARCH_BUTTON)
                wait_for(lambda: "call hci0 StartDiscovery" in calls())
                time.sleep(0.5)
                screenshot("search")
                click(*SECOND_DEVICE_BUTTON)
                wait_for(lambda: "call dev_22_22_22_22_22_22 Pair" in calls())
                assert "set dev_22_22_22_22_22_22 Trusted True" in calls(), calls()
                print("bluetooth OK")

                # The address row copies the address.
                click(*ADDRESS_ROW)
                wait_for(lambda: "copy 192.168.1.23" in recorded())
                print("address OK")

                # The night light tile runs gammastep while on and remembers the choice.
                click(*NIGHT_TILE)
                wait_for(lambda: "gammastep -m wayland -O 4000" in recorded())
                wait_for(lambda: ipc("nightLight").stdout.strip() == "true")
                assert (state / "night-light").read_text().strip() == "1"
                click(*NIGHT_TILE)
                wait_for(lambda: "gammastep stopped" in recorded())
                assert (state / "night-light").read_text().strip() == "0"
                # Saved as on, a new bar starts it at once.
                (state / "night-light").write_text("1\n")
                bar.terminate()
                bar.wait(5)
                record.write_text("")
                bar = start_bar()
                wait_for(lambda: "gammastep -m wayland -O 4000" in recorded())
                print("night light OK")
                print("OK")
            except BaseException:
                bar_log.seek(0)
                print(bar_log.read()[-4000:])
                print("bluez:", calls())
                print("recorded:", recorded())
                raise
            finally:
                if bar and bar.poll() is None:
                    bar.terminate()
                    bar.wait(5)
                bluez.terminate()
                system_bus.terminate()


# Where to click on 1280x800 with the panel open under the right of the bar (see screenshots with
# MYWM_CONTROL_SCREENSHOTS=<directory>).
BLUETOOTH_TILE = (986, 143)
NIGHT_TILE = (1171, 143)
ADDRESS_ROW = (1072, 241)
SEARCH_BUTTON = (1210, 290)
FIRST_DEVICE_BUTTON = (1200, 340)
SECOND_DEVICE_BUTTON = (1200, 400)

if __name__ == "__main__":
    main()
