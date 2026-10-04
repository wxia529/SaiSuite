"""Check the icon pixels embedded in the app and installer, not just source ICO.

Usage: python tools/verify_windows_icon.py path/to/saisuite.exe path/to/setup.exe
"""
import ctypes
from ctypes import wintypes
from io import BytesIO
from pathlib import Path
import struct
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
kernel.LoadLibraryExW.restype = wintypes.HMODULE
kernel.FreeLibrary.argtypes = [wintypes.HMODULE]
kernel.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
kernel.FindResourceW.restype = wintypes.HANDLE
kernel.SizeofResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
kernel.SizeofResource.restype = wintypes.DWORD
kernel.LoadResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
kernel.LoadResource.restype = wintypes.HANDLE
kernel.LockResource.argtypes = [wintypes.HANDLE]
kernel.LockResource.restype = ctypes.c_void_p
Callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ssize_t)
kernel.EnumResourceNamesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, Callback, ctypes.c_ssize_t]
kernel.EnumResourceNamesW.restype = wintypes.BOOL


def resource(module, name, kind):
    if isinstance(name, str):
        text = ctypes.create_unicode_buffer(name)
        pointer = ctypes.cast(text, ctypes.c_void_p)
    else:
        pointer = ctypes.c_void_p(name)
    handle = kernel.FindResourceW(module, pointer, ctypes.c_void_p(kind))
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    size = kernel.SizeofResource(module, handle)
    data = kernel.LoadResource(module, handle)
    return ctypes.string_at(kernel.LockResource(data), size)


def verify(path, expected):
    # LOAD_LIBRARY_AS_DATAFILE: examine PE resources without running executable code.
    module = kernel.LoadLibraryExW(str(path.resolve()), None, 2)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())
    names = []

    @Callback
    def collect(_module, _kind, name, _param):
        names.append(ctypes.wstring_at(name) if name > 65535 else name)
        return True

    try:
        if not kernel.EnumResourceNamesW(module, ctypes.c_void_p(14), collect, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        matches = []
        for name in names:
            group = resource(module, name, 14)
            reserved, kind, count = struct.unpack_from('<HHH', group)
            assert reserved == 0 and kind == 1
            entries = []
            offset = 6 + count * 16
            header = struct.pack('<HHH', 0, 1, count)
            for i in range(count):
                w, h, colors, zero, planes, bits, size, icon_id = struct.unpack_from('<BBBBHHIH', group, 6 + i * 14)
                data = resource(module, icon_id, 3)
                assert len(data) == size
                header += struct.pack('<BBBBHHII', w, h, colors, zero, planes, bits, size, offset)
                entries.append(data)
                offset += size
            icon = Image.open(BytesIO(header + b''.join(entries)))
            actual = {size: icon.ico.getimage(size).convert('RGBA').tobytes() for size in icon.ico.sizes()}
            if all(actual.get(size) == pixels for size, pixels in expected.items()):
                matches.append(str(name))
        assert matches, f'{path}: no resource group matches all nine SaiSuite icon sizes'
        print(f'{path}: 9 icon sizes match source; resource group {", ".join(matches)}')
    finally:
        kernel.FreeLibrary(module)


if __name__ == '__main__':
    icon = Image.open(ROOT / 'windows/runner/resources/app_icon.ico')
    sizes = {(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 128, 256)}
    assert icon.ico.sizes() == sizes
    expected = {size: icon.ico.getimage(size).convert('RGBA').tobytes() for size in sizes}
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for filename in sys.argv[1:]:
        verify(Path(filename), expected)
