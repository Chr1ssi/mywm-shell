#!/usr/bin/env python3
"""Exercise picker, persistence and the compositor's spanning wallpaper in a nested MyWM-Smithay session."""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import zlib

from session import MYWM_BINARY, SHELL_ROOT, Session, wait_for


def gradient_png(path):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + bytes(v for x in range(256) for v in (x, y * 3, 100)) for y in range(72))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 72, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def main():
    with tempfile.TemporaryDirectory(prefix='mywm-wallpaper-') as directory:
        base = Path(directory)
        images = base / 'images # test'
        images.mkdir()
        gradient_png(images / 'a gradient # 100%.png')
        gradient_png(images / 'b second.PNG')
        (images / 'ignored.txt').write_text('not an image')
        session = Session(base, outputs=2, config='wallpaper_directory = ' + json.dumps(str(images)) + '\n')
        config, env = session.config, session.env
        shell = kanshi = None
        with session, (base/'shell.log').open('w+') as shell_log:
            try:
                def start():
                    return subprocess.Popen([str(MYWM_BINARY), '--wallpaper'], env=env, stdout=shell_log, stderr=subprocess.STDOUT)
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

                def span_error():
                    """Why the screen does not show the image filling the desktop (None: it does)."""
                    geometry = json.loads(ipc('geometry').stdout)
                    desk = geometry['desktop']
                    ppm = base/'screen.ppm'
                    subprocess.run(['grim', '-t', 'ppm', str(ppm)], env=env, check=True)
                    with ppm.open('rb') as f:
                        assert f.readline() == b'P6\n'
                        width, height = map(int, f.readline().split())
                        assert f.readline() == b'255\n'
                        data = f.read()
                    if (width, height) != (desk['width'], desk['height']):
                        return ('size', width, height, desk)
                    scale = max(width / 256, height / 72)
                    for screen in geometry['screens']:
                        x = screen['x'] - desk['x'] + screen['width'] // 2
                        y = screen['y'] - desk['y'] + screen['height'] // 2
                        actual = data[(y*width+x)*3:(y*width+x)*3+3]
                        source_x = (x + (256*scale-width)/2) / scale
                        source_y = (y + (72*scale-height)/2) / scale
                        if not (abs(actual[0]-source_x) < 5 and abs(actual[1]-source_y*3) < 5):
                            return (screen, list(actual), source_x, source_y)
                    return None

                def check_span():
                    # The compositor decodes the image in the background.
                    try:
                        wait_for(lambda: span_error() is None, 15)
                    except AssertionError:
                        raise AssertionError(span_error())
                    return json.loads(ipc('geometry').stdout)
                geometry = check_span()
                # Non-rectangular layout with a vertical offset. (No portrait output: nested, the compositor
                # captures rotated outputs unrotated, so grim cannot check them.)
                profile = base/'kanshi.conf'
                first, second = [s['name'] for s in geometry['screens']]
                profile.write_text(f'profile test {{\n output {first} position 0,720\n output {second} position 1280,0\n}}\n')
                kanshi = subprocess.Popen(['kanshi', '-c', str(profile)], env=env, stdout=shell_log, stderr=subprocess.STDOUT)
                wait_for(lambda: json.loads(ipc('geometry').stdout)['desktop']['height'] == 720 + 800)
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
                print('Wallpaper smoke passed: search, encoded filenames, persistence, cancel, no results, continuous span across offset outputs drawn by the compositor')
            finally:
                for child in [shell, kanshi]:
                    if child is not None and child.poll() is None:
                        child.terminate(); child.wait(timeout=3)
                shell_log.seek(0)
                log = shell_log.read()
                print(log)
                assert not any(e in log for e in ['ERROR', 'ReferenceError', 'TypeError', 'Unable to assign']), 'QML error'

if __name__ == '__main__':
    main()
