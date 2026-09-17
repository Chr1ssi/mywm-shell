#!/usr/bin/env python3
"""Exercise picker, persistence and spanning wallpaper on isolated River outputs."""
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import tempfile
import time
import zlib

from bar_smoke import ROOT, SHELL_ROOT, wait_for


def gradient_png(path):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + bytes(v for x in range(256) for v in (x, y * 3, 100)) for y in range(72))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 72, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def main():
    with tempfile.TemporaryDirectory(prefix='mywm-wallpaper-') as directory:
        base = Path(directory)
        runtime = base / 'runtime'
        runtime.mkdir(mode=0o700)
        images = base / 'images # test'
        images.mkdir()
        gradient_png(images / 'a gradient # 100%.png')
        gradient_png(images / 'b second.PNG')
        (images / 'ignored.txt').write_text('not an image')
        config = base / 'config.toml'
        config.write_text('wallpaper_directory = ' + json.dumps(str(images)) + '\n')
        env = dict(os.environ, MYWM_SHELL_DIR=str(SHELL_ROOT / "quickshell"), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base/'config'),
                   XDG_STATE_HOME=str(base/'state'), MYWM_CONFIG=str(config), MYWM_SOCKET=str(runtime/'control.sock'),
                   WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='2', WLR_RENDERER='pixman',
                   QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', QT_QUICK_CONTROLS_STYLE='Basic', GDK_BACKEND='wayland')
        for key in ['WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'DISPLAY']:
            env.pop(key, None)
        shell = kanshi = None
        with (base/'river.log').open('w+') as river_log, (base/'shell.log').open('w+') as shell_log:
            river = subprocess.Popen(['river', '-no-xwayland', '-c', str(ROOT/'target/debug/mywm')], env=env,
                                     stdout=river_log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                wait_for(lambda: Path(env['MYWM_SOCKET']).exists())
                env['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*') if p.is_socket())
                def start():
                    return subprocess.Popen([str(ROOT/'target/debug/mywm'), '--wallpaper'], env=env, stdout=shell_log, stderr=subprocess.STDOUT)
                shell = start()
                def ipc(method, *args):
                    if shell.poll() is not None:
                        raise AssertionError('Wallpaper process exited')
                    return subprocess.run(['qs', 'ipc', '--pid', str(shell.pid), 'call', 'wallpaper', method, *map(str, args)], env=env, capture_output=True, text=True, timeout=2)
                wait_for(lambda: ipc('count').stdout.strip() == '2')
                result = subprocess.run(['qs', 'ipc', '--path', str(SHELL_ROOT/'quickshell/wallpaper.qml'), 'call', 'wallpaper', 'openPicker', '-100', '100'], env=env, capture_output=True, text=True, timeout=2)
                assert result.returncode == 0, (result.stdout, result.stderr)
                wait_for(lambda: ipc('isOpen').stdout.strip() == 'true')
                ipc('search', 'GRADIENT')
                assert ipc('count').stdout.strip() == '1'
                if os.environ.get('MYWM_PICKER_SCREENSHOT'):
                    time.sleep(0.2)
                    subprocess.run(['grim', os.environ['MYWM_PICKER_SCREENSHOT']], env=env, check=True)
                ipc('choose', 0)
                saved = base/'state/mywm/wallpaper.json'
                wait_for(saved.exists)
                wallpaper = json.loads(saved.read_text())['wallpaper']
                assert '%23' in wallpaper and '%25' in wallpaper, wallpaper
                wait_for(lambda: ipc('isOpen').stdout.strip() == 'false')

                def check_span():
                    geometry = json.loads(ipc('geometry').stdout)
                    desk = geometry['desktop']
                    ppm = base/'screen.ppm'
                    time.sleep(0.2)
                    subprocess.run(['grim', '-t', 'ppm', str(ppm)], env=env, check=True)
                    with ppm.open('rb') as f:
                        assert f.readline() == b'P6\n'
                        width, height = map(int, f.readline().split())
                        assert f.readline() == b'255\n'
                        data = f.read()
                    assert (width, height) == (desk['width'], desk['height'])
                    scale = max(width / 256, height / 72)
                    for screen in geometry['screens']:
                        x = screen['x'] - desk['x'] + screen['width'] // 2
                        y = screen['y'] - desk['y'] + screen['height'] // 2
                        actual = data[(y*width+x)*3:(y*width+x)*3+3]
                        source_x = (x + (256*scale-width)/2) / scale
                        source_y = (y + (72*scale-height)/2) / scale
                        assert abs(actual[0]-source_x) < 5 and abs(actual[1]-source_y*3) < 5, (screen, list(actual), source_x, source_y)
                    return geometry
                geometry = check_span()
                # Non-rectangular layout with a portrait output and a vertical offset.
                profile = base/'kanshi.conf'
                first, second = [s['name'] for s in geometry['screens']]
                profile.write_text(f'profile test {{\n output {first} position 0,720\n output {second} position 1280,0 transform 90\n}}\n')
                kanshi = subprocess.Popen(['kanshi', '-c', str(profile)], env=env, stdout=shell_log, stderr=subprocess.STDOUT)
                wait_for(lambda: json.loads(ipc('geometry').stdout)['desktop']['height'] == 1440)
                check_span()
                if os.environ.get('MYWM_WALLPAPER_SCREENSHOT'):
                    subprocess.run(['grim', os.environ['MYWM_WALLPAPER_SCREENSHOT']], env=env, check=True)
                shell.terminate(); shell.wait(timeout=3)
                shell = start()
                wait_for(lambda: ipc('current').stdout.strip() == wallpaper)
                ipc('openPicker', 1300, 100)
                ipc('search', 'no matches')
                assert ipc('count').stdout.strip() == '0'
                ipc('choose', 0)
                assert ipc('isOpen').stdout.strip() == 'true'
                ipc('close')
                assert json.loads(saved.read_text())['wallpaper'] == wallpaper
                if os.environ.get('MYWM_COLLECTION_PREVIEW'):
                    shell.terminate(); shell.wait(timeout=3)
                    config.write_text('wallpaper_directory = "/home/chris/Bilder/Wallpaper"\n')
                    shell = start()
                    wait_for(lambda: ipc('count').stdout.strip() == '20')
                    ipc('openPicker', 100, 800)
                    time.sleep(4)
                    subprocess.run(['grim', os.environ['MYWM_COLLECTION_PREVIEW']], env=env, check=True)
                print('Wallpaper smoke passed: search, encoded filenames, persistence, cancel, no results, continuous span across offset/portrait outputs')
            finally:
                for child in [shell, kanshi]:
                    if child is not None and child.poll() is None:
                        child.terminate(); child.wait(timeout=3)
                if river.poll() is None:
                    os.killpg(river.pid, signal.SIGTERM); river.wait(timeout=3)
                shell_log.seek(0)
                log = shell_log.read()
                print(log)
                assert not any(e in log for e in ['ERROR', 'ReferenceError', 'TypeError', 'Unable to assign']), 'QML error'

if __name__ == '__main__':
    main()
