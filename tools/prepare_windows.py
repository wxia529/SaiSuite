"""Prepare the private, relocatable Windows file-processing runtime (build time only)."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEST = ROOT / '.buildlog/windows-runtime'
DOWNLOADS = ROOT / '.buildlog/windows-downloads'

def download(url, name):
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    path = DOWNLOADS / name
    if not path.exists():
        print('Downloading', name, flush=True)
        urllib.request.urlretrieve(url, path)
    return path

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    python_zip = download('https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip', 'python-3.13.7.zip')
    if hashlib.sha256(python_zip.read_bytes()).hexdigest() != 'f6cca216a359be84797cabb54149ce5e062afb16cc7567eb7fc51cacb2d86b65':
        raise ValueError('Python archive checksum mismatch')
    if not (DEST / 'python.exe').exists():
        with zipfile.ZipFile(python_zip) as z:
            z.extractall(DEST)
    (DEST / 'python313._pth').write_text('python313.zip\n.\nLib/site-packages\nimport site\n')
    requirements = ROOT / 'windows/backend/requirements.txt'
    stamp = DEST / 'requirements.lock'
    if not stamp.exists() or stamp.read_bytes() != requirements.read_bytes():
        packages = (DEST / 'Lib/site-packages').resolve()
        if not packages.is_relative_to(DEST.resolve()):
            raise ValueError('Runtime libraries must stay inside the build cache')
        if packages.exists():
            shutil.rmtree(packages)
        subprocess.run([sys.executable, '-m', 'pip', 'install', '--only-binary=:all:', '--python-version', '3.13', '--platform', 'win_amd64', '--implementation', 'cp', '--abi', 'cp313', '--target', str(packages), '-r', str(requirements)], check=True)
        shutil.copy2(requirements, stamp)
    # LGPL shared build: h264_mf uses the encoder supplied by Windows (no x264).
    url = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-10-03-18-14/ffmpeg-n8.1.3-14-g330caae0c1-win64-lgpl-shared-8.1.zip'
    ffmpeg_zip = download(url, 'ffmpeg-8.1-lgpl-shared.zip')
    if hashlib.sha256(ffmpeg_zip.read_bytes()).hexdigest() != '11a4b44bc69721274909619a779d82544c8b83a6557c5b1be92dce9a41a968be':
        raise ValueError('FFmpeg archive checksum mismatch')
    with zipfile.ZipFile(ffmpeg_zip) as z:
        for entry in z.infolist():
            p = pathlib.PurePosixPath(entry.filename)
            if 'bin' in p.parts and p.suffix.lower() in ('.exe', '.dll') and p.name != 'ffplay.exe':
                target = DEST / 'ffmpeg' / p.name
                target.parent.mkdir(exist_ok=True)
                target.write_bytes(z.read(entry))
            elif p.name in ('LICENSE.txt', 'COPYING.LGPLv2.1', 'COPYING.LGPLv3'):
                (DEST / ('FFmpeg-' + p.name)).write_bytes(z.read(entry))
    # LGPLv3 incorporates GPLv3 by reference; include both license texts.
    gpl = download('https://raw.githubusercontent.com/FFmpeg/FFmpeg/330caae0c1/COPYING.GPLv3', 'FFmpeg-COPYING.GPLv3')
    shutil.copy2(gpl, DEST / 'FFmpeg-COPYING.GPLv3')
    shutil.copy2(ROOT / 'windows/backend/worker.py', DEST / 'worker.py')
    shutil.copy2(ROOT / 'windows/backend/ocr.ps1', DEST / 'ocr.ps1')
    (DEST / 'runtime-manifest.json').write_text(json.dumps({'python': {'url': 'https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip', 'sha256': hashlib.sha256(python_zip.read_bytes()).hexdigest()}, 'ffmpeg': {'url': url, 'sha256': hashlib.sha256(ffmpeg_zip.read_bytes()).hexdigest()}}, indent=2))
    print('Runtime ready:', DEST, flush=True)

if __name__ == '__main__':
    main()
