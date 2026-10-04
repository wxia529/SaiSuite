"""Build a per-user installer from the complete portable bundle; no system setup."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
INNO_VERSION = '6.5.3'
INNO_SHA256 = '9345ee029faa0b7aed0818c3d5b227699ef9a496cce79e20c19eb9d6ef2e2c2d'
INNO_URL = f'https://github.com/jrsoftware/issrc/releases/download/is-6_5_3/innosetup-{INNO_VERSION}.exe'


def compiler():
    cache = ROOT / '.buildlog'
    cache.mkdir(exist_ok=True)
    archive = cache / f'innosetup-{INNO_VERSION}.exe'
    if not archive.exists():
        urllib.request.urlretrieve(INNO_URL, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != INNO_SHA256:
        raise ValueError('Inno Setup download checksum mismatch')
    directory = cache / 'inno-compiler'
    executable = directory / 'ISCC.exe'
    if not executable.exists():
        subprocess.run([str(archive), '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
                        '/CURRENTUSER', '/PORTABLE=1', f'/DIR={directory}'], check=True,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    return executable


def build(output):
    output = output.resolve()
    if not output.is_relative_to(ROOT):
        raise ValueError('Installer output must stay inside the workspace')
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)',
                      (ROOT / 'pubspec.yaml').read_text(), re.M)
    name, number = match.groups()
    bundle = output / f'SaiSuite-{name}-windows-x64'
    if not (bundle / 'saisuite.exe').is_file() or not (bundle / 'FILES-SHA256.json').is_file():
        raise ValueError('Build the complete Windows portable bundle first')
    subprocess.run([str(compiler()), f'/DBundleDir={bundle}', f'/DOutputDir={output}',
                    f'/DAppVersion={name}', f'/DBuildNumber={number}',
                    str(ROOT / 'windows/installer/SaiSuite.iss')], check=True)
    setup = output / f'SaiSuite-{name}-windows-x64-setup.exe'
    checksum = hashlib.sha256(setup.read_bytes()).hexdigest()
    setup.with_suffix('.exe.sha256').write_text(f'{checksum}  {setup.name}\n', encoding='ascii')
    print(f'{setup}: {setup.stat().st_size} bytes; SHA256 {checksum}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='dist/development/windows')
    build(ROOT / parser.parse_args().output)
