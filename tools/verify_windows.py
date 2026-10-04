"""Verify and relocate the finished portable ZIP, then test its bundled worker."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import time
import zipfile
import release

ROOT = Path(__file__).resolve().parents[1]
archive = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / f'dist/development/windows/SaiSuite-{release.version()[0]}-windows-x64.zip'
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
assert archive.with_suffix('.zip.sha256').read_text('ascii') == f'{checksum}  {archive.name}\n'
destination = ROOT / '.buildlog' / f'windows-relocated-{int(time.time())}' / '便携版 测试'
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name in z.namelist():
        assert not Path(name).is_absolute() and '..' not in Path(name).parts
    z.extractall(destination)
bundle = next(destination.iterdir())
manifest = json.loads((bundle / 'FILES-SHA256.json').read_text('utf-8'))
for filename, expected in manifest.items():
    assert hashlib.sha256((bundle / filename).read_bytes()).hexdigest() == expected, filename
for name in ('saisuite.exe', 'flutter_windows.dll', 'video_player_win_plugin.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'backend/python.exe', 'backend/ffmpeg/ffmpeg.exe'):
    data = (bundle / name).read_bytes()
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[offset:offset+4] == b'PE\x00\x00' and struct.unpack_from('<H', data, offset+4)[0] == 0x8664, name
subprocess.run([str(bundle / 'backend/python.exe'), '-X', 'utf8', str(ROOT / 'tools/test_windows_backend.py'), str(bundle / 'backend')], check=True)
report = {'archive': str(archive), 'bytes': archive.stat().st_size, 'sha256': checksum, 'files': len(manifest), 'bundle': str(bundle), 'architecture': 'x64', 'worker_tests': 5}
(ROOT / '.buildlog/windows-portable-verification.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(report, indent=2, ensure_ascii=False))
