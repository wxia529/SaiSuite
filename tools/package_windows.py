"""Collect a complete Windows x64 portable distribution, including CRT and notices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def package(output):
    version = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)', (ROOT / 'pubspec.yaml').read_text(), re.M)
    name, build = version.groups()
    output.mkdir(parents=True, exist_ok=True)
    bundle = output / f'SaiSuite-{name}-windows-x64'
    require_abs = bundle.resolve()
    if not require_abs.is_relative_to(ROOT.resolve()):
        raise ValueError('Distribution must stay inside the project workspace')
    # Rebuild only this verified, explicitly named generated bundle, retaining APKs.
    if bundle.exists():
        shutil.rmtree(require_abs)
    shutil.copytree(ROOT / 'build/windows/x64/runner/Release', bundle, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('backend', '__pycache__', '*.pdb', '*.ilk', '*.exp', '*.lib'))
    shutil.copytree(ROOT / '.buildlog/windows-runtime', bundle / 'backend',
                    ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy2(ROOT / 'windows/backend/worker.py', bundle / 'backend/worker.py')
    shutil.copy2(ROOT / 'windows/backend/ocr.ps1', bundle / 'backend/ocr.ps1')
    vswhere = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    install = subprocess.check_output([str(vswhere), '-latest', '-property', 'installationPath'], text=True).strip()
    crt = sorted(Path(install).glob('VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT'))[-1]
    for dll in crt.glob('*.dll'):
        shutil.copy2(dll, bundle / dll.name)
    (bundle / '使用说明.txt').write_text(
        f'赛赛工具箱 Windows x64 {name}+{build}\n\n'
        '安装版：运行 -setup.exe，按中文向导选择目录和快捷方式；可从 Windows 设置中卸载。\n'
        '便携版：解压整个文件夹，双击 saisuite.exe。不要单独移动 EXE。\n'
        '支持 Windows 10/11 64 位；无需安装 Python、Java 或 FFmpeg。\n'
        '支持 PDF、图片创作与 OCR、视频与音频、日常计算、计时、日期、科研与电化学。\n'
        '指南针、水平仪及手机传感器工具仅在 Android 提供。屏幕标尺须用实体尺校准。\n'
        '番茄钟支持最小化提醒；关闭应用或电脑休眠时不保证提醒。\n'
        '计算和配方不会自动保存实验记录，处理结果请主动另存。\n'
        '更新时先关闭应用。安装版运行新版安装程序；便携版解压到新文件夹。\n'
        '偏好设置位于用户目录，与程序目录分开；卸载不会删除偏好或主动导出的文件。\n'
        '代码签名：本包没有 Windows Authenticode 签名；Android 签名密钥不会用于 Windows。\n', encoding='utf-8')
    notices = bundle / 'THIRD-PARTY-NOTICES.txt'
    notices.write_text(
        'SaiSuite desktop dependencies\n\n'
        'Python 3.13.7: PSF License. See backend/LICENSE.txt. https://www.python.org/ftp/python/3.13.7/\n'
        'pypdf: BSD-3-Clause; reportlab: BSD; Pillow: HPND; PyCryptodome: BSD/public domain.\n'
        'pypdfium2: Apache-2.0 / BSD-3-Clause; PDFium: BSD-3-Clause and third-party licenses.\n'
        'Exact licenses are included under backend/Lib/site-packages/*dist-info and pypdfium2_raw.\n'
        'FFmpeg 8.1 LGPL shared build (no GPL/nonfree): see backend/FFmpeg-LICENSE.txt, backend/ffmpeg/*.dll.\n'
        'Corresponding source and build scripts: https://github.com/BtbN/FFmpeg-Builds/tree/autobuild-2026-10-03-18-14\n'
        'FFmpeg source revision: https://github.com/FFmpeg/FFmpeg/tree/330caae0c1\n'
        'Full source can be downloaded at https://github.com/FFmpeg/FFmpeg/archive/330caae0c1.tar.gz\n'
        'FFmpeg runs as a separate process and shared libraries can be replaced. No codec package is installed.\n'
        'video_player_win: BSD-3-Clause, Windows Media Foundation. Flutter licenses: Settings > open-source licenses.\n'
        'OCR: Windows.Media.Ocr, supplied by Windows; Chinese OCR language resources must be installed.\n'
        'Visual C++ CRT redistributable files are distributed under the Microsoft Visual Studio license.\n'
        'Installer: Inno Setup 6.5.3, Jordan Russell and Martijn Laan. https://jrsoftware.org/\n'
        'Runtime archive hashes: backend/runtime-manifest.json\n', encoding='utf-8')
    files = [p for p in bundle.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    manifest = {p.relative_to(bundle).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (bundle / 'FILES-SHA256.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
    archive = output / f'SaiSuite-{name}-windows-x64.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in bundle.rglob('*'):
            if p.is_file() and '__pycache__' not in p.parts:
                z.write(p, p.relative_to(output).as_posix())
    checksum = f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n'
    archive.with_suffix('.zip.sha256').write_text(checksum, encoding='ascii')
    print(f'{archive}: {archive.stat().st_size} bytes; {len(manifest)} files')
    print(checksum)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='dist/development/windows')
    args = parser.parse_args()
    package((ROOT / args.output).resolve())
