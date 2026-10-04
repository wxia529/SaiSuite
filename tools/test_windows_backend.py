"""End-to-end checks against the bundled interpreter and real PDF/image/video engine."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image, ImageChops, ImageOps
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
BACKEND = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else ROOT / '.buildlog/windows-runtime'

class DesktopFiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='saisuite_windows_test_')
        cls.cache = Path(cls.temp.name)
        cls.png = cls.cache / '原始 透明图片.png'
        Image.new('RGBA', (5000, 200), (34, 120, 80, 128)).save(cls.png)
        cls.jpg = cls.cache / '旋转.jpg'
        im = Image.new('RGB', (240, 480), 'red')
        exif = Image.Exif()
        exif[274] = 6
        im.save(cls.jpg, exif=exif)
        cls.originals = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in (cls.png, cls.jpg)}
        cls.fixture = cls.call('pdf', 'fixture', count=3)

    @classmethod
    def tearDownClass(cls):
        for p, value in cls.originals.items():
            assert hashlib.sha256(p.read_bytes()).hexdigest() == value, 'Original input modified'
        cls.temp.cleanup()

    @classmethod
    def call(cls, channel, method, **args):
        request = {'channel': 'saisuite/' + channel, 'method': method, 'args': args, 'cache': str(cls.cache)}
        p = subprocess.run([str(BACKEND / 'python.exe'), '-X', 'utf8', str(BACKEND / 'worker.py')], input=json.dumps(request).encode(), capture_output=True)
        if p.returncode:
            raise AssertionError(p.stderr.decode('utf8', 'replace'))
        result = json.loads(p.stdout)
        if 'error' in result:
            raise ValueError(result['code'] + ': ' + result['error'])
        return result['result']

    def test_pdf_pages_and_text(self):
        f = self.fixture
        info = self.call('pdf', 'inspect', path=f)
        self.assertEqual(info['count'], 3)
        self.assertIn('Test Page 1', self.call('pdf', 'text', path=f, pages=[0]))
        ordered = self.call('pdf', 'transform', path=f, pages=[2, 0, 2], rotation=90, rotationPages=[2])
        out = PdfReader(ordered)
        self.assertEqual([p.rotation for p in out.pages], [90, 0, 90])
        self.assertIn('Page 3', out.pages[2].extract_text())
        merged = self.call('pdf', 'merge', sources=[{'path': f, 'pages': [0]}, {'path': f, 'pages': [1]}])
        self.assertEqual(len(PdfReader(merged).pages), 2)
        self.assertTrue(Path(self.call('pdf', 'render', path=f, page=1, dpi=72)).exists())
        with self.assertRaises(ValueError):
            self.call('pdf', 'transform', path=f, pages=[99])

    def test_original_size_alpha_orientation(self):
        result = self.call('pdf', 'images', images=[str(self.png), str(self.jpg)], paper='按图片尺寸', landscape=True, margin=100)
        r = PdfReader(result)
        self.assertEqual([(int(p.mediabox.width), int(p.mediabox.height)) for p in r.pages], [(5000, 200), (480, 240)])
        for i, source in enumerate((self.png, self.jpg)):
            extracted = r.pages[i].images[0].image.convert('RGBA')
            with Image.open(source) as im:
                original = ImageOps.exif_transpose(im).convert('RGBA')
                self.assertEqual(ImageChops.difference(extracted, original).getbbox(), None)
        a4 = self.call('pdf', 'images', images=[str(self.png)], paper='A4', margin=20, landscape=True)
        self.assertAlmostEqual(float(PdfReader(a4).pages[0].mediabox.width), 841.88976378, places=3)

    def test_encryption_and_watermark(self):
        encrypted = self.call('pdf', 'encrypt', path=self.fixture, newPassword='科研-test-密码')
        self.assertTrue(PdfReader(encrypted).is_encrypted)
        with self.assertRaisesRegex(ValueError, 'PASSWORD'):
            self.call('pdf', 'inspect', path=encrypted, password='wrong')
        self.assertEqual(self.call('pdf', 'inspect', path=encrypted, password='科研-test-密码')['count'], 3)
        clear = self.call('pdf', 'decrypt', path=encrypted, password='科研-test-密码')
        self.assertFalse(PdfReader(clear).is_encrypted)
        marked = self.call('pdf', 'watermark', path=clear, pages=[0], text='电解液 配方', size=24, opacity=.3, position='center')
        self.assertGreater(len(PdfReader(marked).pages[0].images), 0)
        self.assertEqual(len(PdfReader(marked).pages[1].images), 0)
        self.assertTrue(Path(self.call('pdf', 'render', path=marked, page=0)).exists())

    def test_image_prepare_export_watermark(self):
        prepared = self.call('media', 'imagePrepareEditor', path=str(self.jpg))
        self.assertEqual((prepared['width'], prepared['height']), (480, 240))
        out = self.call('media', 'imageEditorExport', path=str(self.png), maxEdge=1000, format='PNG')
        with Image.open(out['path']) as im:
            self.assertEqual(im.size, (1000, 40))
            self.assertEqual(im.getpixel((0, 0))[3], 128)
        jpeg = self.call('media', 'imageEditorExport', path=str(self.png), maxEdge=500, format='JPEG', quality=90)
        with Image.open(jpeg['path']) as im:
            self.assertEqual(im.mode, 'RGB')
        mark = self.call('media', 'imageProcess', paths=[str(self.jpg)], width=360, format='PNG', watermark='电解液')
        self.assertEqual(mark['width'], 360)

    def test_video_decode_frame_clip(self):
        path = str(ROOT / '.buildlog/windows-fixture.mp4')
        info = self.call('media', 'videoInfo', path=path)
        self.assertAlmostEqual(info['duration'], 3, delta=.2)
        frame = self.call('media', 'videoFrame', path=path, seconds=.8)
        with Image.open(frame['path']) as im:
            self.assertEqual(im.size, (320, 240))
        thumb = self.call('media', 'videoThumbnail', path=path, seconds=1.2)
        with Image.open(thumb['path']) as im:
            self.assertLessEqual(max(im.size), 320)
        clip = self.call('media', 'videoProcess', path=path, start=.5, end=2, mute=True, height=0, bitrate=1000000, progressPath=str(self.cache / 'progress.txt'))
        self.assertAlmostEqual(clip['duration'], 1.5, delta=.2)
        self.assertGreater(clip['bytes'], 0)
        # Exercise AAC preservation and actual muting with a source that has audio.
        audio = self.cache / 'with-audio.mp4'
        subprocess.run([str(BACKEND / 'ffmpeg/ffmpeg.exe'), '-v', 'error', '-nostdin', '-y',
                        '-f', 'lavfi', '-i', 'testsrc2=duration=2:size=160x120:rate=24',
                        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2',
                        '-c:v', 'h264_mf', '-hw_encoding', '0', '-c:a', 'aac', str(audio)], check=True)
        def streams(file):
            data = subprocess.check_output([str(BACKEND / 'ffmpeg/ffprobe.exe'), '-v', 'error', '-show_streams', '-of', 'json', file])
            return [s['codec_type'] for s in json.loads(data)['streams']]
        for mute in (False, True):
            out = self.call('media', 'videoProcess', path=str(audio), start=.25, end=1.5,
                            mute=mute, height=0, bitrate=400000, progressPath=str(self.cache / 'audio-progress.txt'))
            self.assertEqual('audio' in streams(out['path']), not mute)

if __name__ == '__main__':
    unittest.main(verbosity=2)
