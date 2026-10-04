"""Exercise the real installer, reinstall, running-app guard and uninstaller.

Refuses to touch an existing SaiSuite installation or desktop shortcut. Installs
only into a unique directory inside .buildlog and removes its own installation.
"""
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
import winreg
import release

ROOT = Path(__file__).resolve().parents[1]
VERSION_NAME, BUILD_NUMBER = release.version()
KEY = r'Software\Microsoft\Windows\CurrentVersion\Uninstall\io.github.wxia529.SaiSuite.Windows_is1'
FLAGS = winreg.KEY_READ | winreg.KEY_WOW64_64KEY


def registration():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY, 0, FLAGS) as key:
            return {name: winreg.QueryValueEx(key, name)[0]
                    for name in ('DisplayName', 'DisplayVersion', 'InstallLocation', 'UninstallString')}
    except FileNotFoundError:
        return None


def shell_folder(number):
    buffer = ctypes.create_unicode_buffer(260)
    assert ctypes.windll.shell32.SHGetFolderPathW(None, number, None, 0, buffer) == 0
    return Path(buffer.value)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def preferences():
    directory = Path(os.environ['APPDATA']) / 'io.github.wxia529'
    return {str(p): digest(p) for p in directory.rglob('*') if p.is_file()}


def verify(setup):
    setup = setup.resolve()
    assert setup.with_suffix('.exe.sha256').read_text('ascii') == f'{digest(setup)}  {setup.name}\n'
    assert registration() is None, 'Existing installation must not be modified by verification'
    desktop = shell_folder(0x10) / '赛赛工具箱.lnk'
    assert not desktop.exists(), 'Existing desktop shortcut must not be overwritten'
    group_name = 'SaiSuite Installer Test ' + uuid.uuid4().hex[:8]
    group = shell_folder(0x2) / group_name
    test_root = (ROOT / '.buildlog' / ('windows-installer-test-' + uuid.uuid4().hex[:8])).resolve()
    assert test_root.is_relative_to(ROOT / '.buildlog')
    install = test_root / '安装目录 中文 空格'
    test_root.mkdir()
    args = [str(setup), '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
            f'/DIR={install}', f'/GROUP={group_name}', '/TASKS=desktopicon']
    sentinel = install / '用户保留文件.txt'
    export = test_root / '用户导出的结果.txt'
    export.write_text('keep exported result', encoding='utf-8')
    process = None
    result = {}
    try:
        subprocess.run(args + [f'/LOG={test_root / "install.log"}'], check=True, timeout=120)
        registered = registration()
        assert registered and registered['DisplayVersion'] == f'{VERSION_NAME}+{BUILD_NUMBER}', registered
        assert Path(registered['InstallLocation']).resolve() == install.resolve()
        assert desktop.is_file() and (group / '赛赛工具箱.lnk').is_file()
        assert (group / '卸载赛赛工具箱.lnk').is_file()
        manifest = json.loads((install / 'FILES-SHA256.json').read_text('utf-8'))
        for filename, expected in manifest.items():
            assert digest(install / filename) == expected, filename
        sentinel.write_text('preserve user file on reinstall and uninstall', encoding='utf-8')
        subprocess.run(args + [f'/LOG={test_root / "reinstall.log"}'], check=True, timeout=120)
        assert sentinel.read_text('utf-8') == 'preserve user file on reinstall and uninstall'
        # Test from the installed location, using its embedded interpreter only.
        subprocess.run([str(install / 'backend/python.exe'), '-X', 'utf8',
                        str(ROOT / 'tools/test_windows_backend.py'), str(install / 'backend')],
                       check=True, timeout=120)
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        process = subprocess.Popen([str(install / 'saisuite.exe')], cwd=ROOT,
                                   startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
        time.sleep(8)
        assert process.poll() is None, 'Installed application failed to start'
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenMutexW.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.LPCWSTR]
        kernel.OpenMutexW.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.OpenMutexW(0x00100000, False, 'SaiSuite.Desktop')
        assert handle, 'Installed app did not hold installer guard mutex'
        kernel.CloseHandle(handle)
        blocked = subprocess.run(args + [f'/LOG={test_root / "running-app.log"}'], timeout=30)
        assert blocked.returncode == 1, f'Running application guard returned {blocked.returncode}'
        assert '当前正在运行' in (test_root / 'running-app.log').read_text('utf-8-sig')
        assert process.poll() is None, 'Installer closed the running app'
        blocked_uninstall = subprocess.run([str(install / 'unins000.exe'), '/VERYSILENT',
                                           '/SUPPRESSMSGBOXES', '/NORESTART',
                                           f'/LOG={test_root / "running-uninstall.log"}'], timeout=30)
        assert blocked_uninstall.returncode != 0
        assert (install / 'saisuite.exe').is_file() and process.poll() is None
        process.terminate()  # Only the process started by this verification, with no edits.
        process.wait(timeout=15)
        process = None
        before = preferences()
        assert before, 'No actual preference file found to validate retention'
        uninstaller = install / 'unins000.exe'
        assert uninstaller.resolve().is_relative_to(test_root)
        subprocess.run([str(uninstaller), '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
                        f'/LOG={test_root / "uninstall.log"}'], check=True, timeout=120)
        assert registration() is None
        assert not (install / 'saisuite.exe').exists()
        assert not desktop.exists() and not group.exists()
        assert sentinel.is_file() and export.read_text('utf-8') == 'keep exported result'
        assert preferences() == before, 'Uninstall changed user preferences'
        result = {'installer': str(setup), 'bytes': setup.stat().st_size, 'sha256': digest(setup),
                  'installed_files_verified': len(manifest), 'version': registered['DisplayVersion'],
                  'install_reinstall_uninstall': 'passed', 'running_app_guard': 'passed',
                  'user_files_and_preferences': 'preserved', 'worker_test_groups': 5,
                  'preference_files_retained': len(before), 'shortcuts': 'passed',
                  'logs': str(test_root)}
        (ROOT / '.buildlog/windows-installer-verification.json').write_text(
            json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
        print(json.dumps(result, indent=2, ensure_ascii=False))
    finally:
        if process and process.poll() is None:
            process.terminate()
            process.wait(timeout=15)
        # Clean up only our test install even after a failed assertion. User files remain.
        if registration() and Path(registration()['InstallLocation']).resolve() == install.resolve():
            subprocess.run([str(install / 'unins000.exe'), '/VERYSILENT', '/SUPPRESSMSGBOXES',
                            '/NORESTART'], check=True, timeout=120)


if __name__ == '__main__':
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else
           ROOT / f'dist/development/windows/SaiSuite-{VERSION_NAME}-windows-x64-setup.exe')
