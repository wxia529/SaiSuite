"""Generate Android vectors/launchers and Windows ICO from one vector mark.

Requires Pillow. Tiles occupy top-left, bottom-left, bottom-right;
the lightning bolt occupies top-right. No fonts or downloads.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND, TILE, BOLT = '#147D73', '#F3F7E8', '#BEE2AF'
SIZES = [(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 128, 256)]
OUTLINE = [('M', 24, 4), ('L', 84, 4), ('Q', 104, 4, 104, 24),
           ('L', 104, 84), ('Q', 104, 104, 84, 104), ('L', 24, 104),
           ('Q', 4, 104, 4, 84), ('L', 4, 24), ('Q', 4, 4, 24, 4), ('Z',)]


def tile(x, y):
    return [('M', x+3, y), ('L', x+21, y), ('Q', x+24, y, x+24, y+3),
            ('L', x+24, y+21), ('Q', x+24, y+24, x+21, y+24),
            ('L', x+3, y+24), ('Q', x, y+24, x, y+21),
            ('L', x, y+3), ('Q', x, y, x+3, y), ('Z',)]


TILES = [tile(25, 26), tile(25, 59), tile(58, 59)]
LIGHTNING = [('M', 70, 26), ('L', 59, 43), ('L', 68, 43), ('L', 64, 56),
             ('L', 84, 36), ('L', 74, 36), ('L', 78, 26), ('Z',)]


def path_data(commands):
    return ' '.join(cmd[0] + ','.join(str(v) for v in cmd[1:]) for cmd in commands)


def vector(paths, group=False):
    content = ''.join(f'    <path android:fillColor="{color}" android:pathData="{path_data(path)}" />\n'
                      for color, path in paths)
    if group:
        content = ('  <group android:pivotX="54" android:pivotY="54" '
                   'android:scaleX="0.8" android:scaleY="0.8">\n' + content + '  </group>\n')
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n'
            + content + '</vector>\n')


def points(commands):
    result = []
    previous = (0, 0)
    for command in commands:
        op, *v = command
        if op in ('M', 'L'):
            previous = tuple(v)
            result.append(previous)
        elif op == 'Q':
            control, end = v[:2], v[2:]
            for i in range(1, 33):
                t = i / 32
                result.append(tuple((1-t)**2*a + 2*(1-t)*t*b + t*t*c
                                    for a, b, c in zip(previous, control, end)))
            previous = tuple(end)
    return result


def draw_mark(image, size, factor=1, monochrome=False):
    draw = ImageDraw.Draw(image)
    for color, path in [(TILE, p) for p in TILES] + [(BOLT, LIGHTNING)]:
        draw.polygon([(((x-54)*factor+54)*size/108, ((y-54)*factor+54)*size/108)
                      for x, y in points(path)], fill='white' if monochrome else color)


def generate():
    branding = ROOT / 'assets/branding'
    branding.mkdir(exist_ok=True)
    mark = [(TILE, p) for p in TILES] + [(BOLT, LIGHTNING)]
    paths = [(BACKGROUND, OUTLINE)] + mark
    (branding / 'saisuite-icon.svg').write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">\n'
        '  <title>SaiSuite</title>\n' + ''.join(
            f'  <path fill="{color}" d="{path_data(path)}"/>\n' for color, path in paths)
        + '</svg>\n', encoding='utf-8')
    size = 108 * 8
    image = Image.new('RGBA', (size, size))
    ImageDraw.Draw(image).polygon([(x*8, y*8) for x, y in points(OUTLINE)], fill=BACKGROUND)
    draw_mark(image, size)
    image.resize((256, 256), Image.Resampling.LANCZOS).save(branding / 'saisuite-icon.png')
    image.save(ROOT / 'windows/runner/resources/app_icon.ico', format='ICO', sizes=SIZES)
    res = ROOT / 'android/app/src/main/res'
    (res / 'drawable/ic_saisuite.xml').write_text(vector(paths), encoding='utf-8')
    (res / 'drawable/ic_saisuite_foreground.xml').write_text(vector(mark, group=True), encoding='utf-8')
    (res / 'drawable/ic_saisuite_monochrome.xml').write_text(
        vector([('#FFFFFF', path) for _, path in mark], group=True), encoding='utf-8')
    (res / 'drawable/ic_saisuite_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
        f'  <solid android:color="{BACKGROUND}" />\n</shape>\n', encoding='utf-8')
    for density, pixels in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(res / f'mipmap-{density}/ic_launcher.png')
    for api in (26, 33):
        folder = res / f'mipmap-anydpi-v{api}'
        folder.mkdir(exist_ok=True)
        monochrome = '  <monochrome android:drawable="@drawable/ic_saisuite_monochrome" />\n' if api >= 33 else ''
        (folder / 'ic_launcher.xml').write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '  <background android:drawable="@drawable/ic_saisuite_background" />\n'
            '  <foreground android:drawable="@drawable/ic_saisuite_foreground" />\n'
            + monochrome + '</adaptive-icon>\n', encoding='utf-8')
    print(f'Generated shared mark, Android legacy/adaptive/themed icons, Windows ICO ({len(SIZES)} sizes).')


if __name__ == '__main__':
    generate()
