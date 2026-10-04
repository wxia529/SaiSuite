"""SaiSuite Windows worker. JSON stdin/stdout; writes only owned temporary files.

All subprocess arguments are separate argv entries (never shell commands).
PDFs remain vectors when arranging pages; previews are rendered with PDFium.
"""
import copy
import io
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import uuid

from PIL import Image, ImageDraw, ImageFont, ImageOps
from pypdf import PdfReader, PdfWriter
from pypdf.errors import WrongPasswordError, FileNotDecryptedError
import pypdfium2 as pdfium
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

ROOT = Path(sys.executable).resolve().parent
CACHE = None
CREATED = []
MANIFEST = None

def require(condition, message):
    if not condition:
        raise ValueError(message)

def output(ext):
    path = CACHE / ('saisuite_' + uuid.uuid4().hex + '.' + ext)
    CREATED.append(path)
    if MANIFEST:
        with MANIFEST.open('a', encoding='utf-8') as file:
            file.write(str(path) + '\n')
    return path

def checked(path, maximum=100 * 1024 * 1024):
    p = Path(path)
    require(p.is_file() and 0 < p.stat().st_size <= maximum, '文件为空或超过大小上限')
    return p

def reader(args):
    p = checked(args['path'])
    r = PdfReader(p)
    if r.is_encrypted:
        if not r.decrypt(args.get('password', '')):
            raise WrongPasswordError('PDF 密码错误或需要打开密码')
    require(1 <= len(r.pages) <= 500, '支持 1—500 页 PDF')
    return r

def pages(args, r):
    values = args.get('pages')
    values = list(range(len(r.pages))) if values is None else values
    require(0 < len(values) <= 500 and all(isinstance(i, int) and 0 <= i < len(r.pages) for i in values), '页面选择无效')
    return values

def save_pdf(writer):
    p = output('pdf')
    with p.open('wb') as f:
        writer.write(f)
    return str(p)

def image(path, limit=40_000_000, maxbytes=30 * 1024 * 1024):
    p = checked(path, maxbytes)
    with Image.open(p) as im:
        require(im.format in ('PNG', 'JPEG', 'WEBP'), '请选择 PNG、JPEG 或 WebP 图片')
        require(im.width * im.height <= limit, '图片超过像素上限，请先缩小图片')
        return ImageOps.exif_transpose(im).convert('RGBA')

def image_save(im, fmt='PNG', quality=90):
    p = output('png' if fmt == 'PNG' else 'jpg')
    if fmt != 'PNG':
        bg = Image.new('RGB', im.size, 'white')
        bg.paste(im, mask=im.getchannel('A') if im.mode == 'RGBA' else None)
        im = bg
    im.save(p, format='PNG' if fmt == 'PNG' else 'JPEG', quality=quality)
    return {'path': str(p), 'width': im.width, 'height': im.height, 'bytes': p.stat().st_size}

def font(size):
    fonts = Path(os.environ.get('WINDIR', 'C:/Windows')) / 'Fonts'
    for filename in ('msyh.ttc', 'simhei.ttf', 'arial.ttf'):
        if (fonts / filename).exists():
            return ImageFont.truetype(str(fonts / filename), size)
    return ImageFont.load_default(size=size)

def pdf(method, a):
    if method == 'images':
        paths = a['images']
        require(1 <= len(paths) <= 100, '每次支持 1—100 张图片')
        original = a.get('paper') == '按图片尺寸'
        if original:
            require(sum(checked(p).stat().st_size for p in paths) <= 100 * 1024 * 1024, '输入文件总量需小于 100 MB')
        p = output('pdf')
        c = canvas.Canvas(str(p))
        total = 0
        for path in paths:
            im = image(path, 16_000_000 if original else 40_000_000, 100 * 1024 * 1024)
            if original:
                require(max(im.size) <= 14400, '长边最多 14400 px；未自动缩小图片')
                total += im.width * im.height
                require(total <= 64_000_000, '每批最多 6400 万像素，请分批转换')
                size, margin = im.size, 0
            else:
                im.thumbnail((4096, 4096), Image.Resampling.LANCZOS)
                size = (612, 792) if a.get('paper') == 'Letter' else (595.275590551, 841.88976378)
                if a.get('landscape'):
                    size = size[::-1]
                margin = float(a.get('margin', 20)) * 72 / 25.4
            require(math.isfinite(margin) and 0 <= margin * 2 < min(size), '边距过大')
            c.setPageSize(size)
            scale = min((size[0] - margin * 2) / im.width, (size[1] - margin * 2) / im.height)
            w, h = im.width * scale, im.height * scale
            c.drawImage(ImageReader(im), (size[0] - w) / 2, (size[1] - h) / 2, w, h, mask='auto')
            c.showPage()
        c.save()
        return str(p)
    if method in ('merge', 'transform'):
        sources = a.get('sources') or [a]
        require(1 <= len(sources) <= 30, '每次合并支持 1—30 份文件')
        writer = PdfWriter()
        for src in sources:
            r = reader(src)
            for i in pages(src, r):
                require(len(writer.pages) < 500, '导出最多 500 页')
                # Independent copy for duplicated pages, including different rotations.
                page = writer.add_page(copy.deepcopy(r.pages[i]))
                if a.get('rotation') and (a.get('rotationPages') is None or i in a['rotationPages']):
                    page.rotate(int(a['rotation']))
        return save_pdf(writer)
    if method == 'fixture':
        p = output('pdf')
        c = canvas.Canvas(str(p))
        c.setTitle('SaiSuite test fixture')
        for i in range(a.get('count', 3)):
            c.setPageSize((612, 792) if i == 1 else (595.275590551, 841.88976378))
            c.drawString(50, 700, f'SaiSuite Test Page {i + 1}')
            c.showPage()
        c.save()
        return str(p)
    r = reader(a)
    if method == 'inspect':
        metadata = r.metadata or {}
        return {'count': len(r.pages), 'bytes': Path(a['path']).stat().st_size, 'encrypted': r.is_encrypted,
                **{key: str(metadata.get('/' + key.title(), '') or '') for key in ('title', 'author', 'subject', 'producer')},
                'pages': [{'width': float(p.cropbox.width), 'height': float(p.cropbox.height), 'rotation': p.rotation} for p in r.pages],
                'forms': '/AcroForm' in r.trailer['/Root'], 'signed': any(f.get('/FT') == '/Sig' and f.get('/V') for f in (r.get_fields() or {}).values())}
    if method == 'render':
        index = int(a.get('page', 0))
        require(0 <= index < len(r.pages), '页面不存在')
        doc = pdfium.PdfDocument(str(a['path']), password=a.get('password', ''))
        try:
            page = doc[index]
            w, h = page.get_size()
            scale = min(max(36, min(300, float(a.get('dpi', 100)))) / 72, 4096 / max(w, h))
            bitmap = page.render(scale=scale)
            im = bitmap.to_pil().copy()
            bitmap.close()
            page.close()
        finally:
            doc.close()
        return image_save(im, a.get('format', 'PNG'))['path']
    if method == 'text':
        return '\n'.join(f'--- 第 {i + 1} 页 ---\n{r.pages[i].extract_text() or ""}\n' for i in pages(a, r))
    writer = PdfWriter(clone_from=r)
    if method == 'encrypt':
        password = a.get('newPassword', '')
        require(0 < len(password.encode('utf-8')) <= 127, '密码需为 1—127 个 UTF-8 字节')
        writer.encrypt(password, algorithm='AES-256')
    elif method == 'watermark':
        text = a.get('text', '')
        require(a.get('image') or text.strip(), '请输入文字或选择水印图片')
        require(len(text) <= 128, '文字水印最多 128 字符')
        size = max(8, min(144, float(a.get('size', 24))))
        opacity = max(0, min(1, float(a.get('opacity', .25))))
        if a.get('image'):
            mark = image(a['image'], maxbytes=100 * 1024 * 1024)
        else:
            f = font(72)
            box = f.getbbox(text)
            mark = Image.new('RGBA', (max(1, min(8192, box[2] - box[0])), max(1, box[3] - box[1])), (0, 0, 0, 0))
            ImageDraw.Draw(mark).text((-box[0], -box[1]), text, font=f, fill='black')
        for i in pages(a, r):
            page = writer.pages[i]
            box = page.cropbox
            w, h = float(box.width), float(box.height)
            mw = min(w * .9, size * 8 if a.get('image') else mark.width * size / 72)
            mh = mw * mark.height / mark.width
            x = float(box.left) + (w - mw) / 2
            y = float(box.bottom) + {'top': h - mh - 24, 'bottom': 24}.get(a.get('position'), (h - mh) / 2)
            data = io.BytesIO()
            c = canvas.Canvas(data, pagesize=(float(page.mediabox.width), float(page.mediabox.height)))
            c.setFillAlpha(opacity)
            c.drawImage(ImageReader(mark), x, y, mw, mh, mask='auto')
            c.save()
            page.merge_page(PdfReader(data).pages[0])
    elif method != 'decrypt':
        raise ValueError('PDF 操作不支持')
    return save_pdf(writer)

def ffmpeg(args):
    result = subprocess.run([str(ROOT / 'ffmpeg/ffmpeg.exe'), '-hide_banner', '-nostdin', '-y', *args], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
    require(result.returncode == 0, '视频处理失败：' + result.stderr.decode('utf-8', 'replace')[-1600:])

def video_info(path):
    p = checked(path, 500 * 1024 * 1024)
    result = subprocess.run([str(ROOT / 'ffmpeg/ffprobe.exe'), '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(p)], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
    require(result.returncode == 0, '无法读取视频')
    data = json.loads(result.stdout)
    stream = next(s for s in data['streams'] if s['codec_type'] == 'video')
    rotation = next((int(d.get('rotation', 0)) for d in stream.get('side_data_list', []) if 'rotation' in d), 0)
    width, height = stream['width'], stream['height']
    if rotation % 180:
        width, height = height, width
    return {'duration': float(data['format']['duration']), 'width': width, 'height': height, 'rotation': rotation, 'bytes': p.stat().st_size, 'bitrate': int(data['format'].get('bit_rate', 0))}

def media(method, a):
    if method.startswith('video'):
        info = video_info(a['path'])
        if method == 'videoInfo':
            return info
        if method in ('videoFrame', 'videoThumbnail'):
            seconds = float(a.get('seconds', 0))
            require(math.isfinite(seconds) and 0 <= seconds < info['duration'], '截帧时间须小于视频时长')
            small = method == 'videoThumbnail'
            p = output('jpg' if small else 'png')
            vf = f'scale=min(iw\\,{320 if small else 1920}):min(ih\\,{320 if small else 1080}):force_original_aspect_ratio=decrease'
            ffmpeg(['-ss', str(seconds), '-i', a['path'], '-frames:v', '1', '-vf', vf, str(p)])
            with Image.open(p) as im:
                return {'path': str(p), 'bytes': p.stat().st_size, 'width': im.width, 'height': im.height}
        if method == 'videoProcess':
            start, end = float(a['start']), float(a['end'])
            require(math.isfinite(start) and math.isfinite(end) and 0 <= start < end <= info['duration'], '视频时间范围无效')
            height = int(a.get('height', 0))
            require(height in (0, 360, 480, 720, 1080), '分辨率无效')
            bitrate = int(a.get('bitrate', 3000000))
            require(128000 <= bitrate <= 20000000, '目标码率无效')
            p = output('mp4')
            args = ['-ss', str(start), '-i', a['path'], '-t', str(end - start), '-map', '0:v:0', '-map', '0:a:0?', '-vf', f'scale=-2:{min(height, info["height"]) // 2 * 2 if height else "trunc(ih/2)*2"}', '-c:v', 'h264_mf', '-hw_encoding', '0', '-b:v', str(bitrate), '-pix_fmt', 'yuv420p']
            args += ['-an'] if a.get('mute') else ['-c:a', 'aac', '-b:a', '128k']
            args += ['-movflags', '+faststart', '-progress', a['progressPath'], str(p)]
            ffmpeg(args)
            return {'path': str(p), **video_info(str(p))}
        raise ValueError('视频操作不支持')
    if method == 'imageInfo':
        p = checked(a['path'], 30 * 1024 * 1024)
        with Image.open(p) as im:
            require(im.width * im.height <= 40_000_000, '图片超过 4000 万像素')
            return {'width': im.width, 'height': im.height, 'mime': Image.MIME.get(im.format, ''), 'orientation': im.getexif().get(274, 1), 'bytes': p.stat().st_size}
    if method in ('imagePrepareEditor', 'imageEditorExport'):
        im = image(a['path'])
        original_size = im.size
        edge = int(a.get('maxEdge', 4096))
        require(1 <= edge <= 4096, '导出长边无效')
        im.thumbnail((edge, edge), Image.Resampling.LANCZOS)
        result = image_save(im, a.get('format', 'PNG'), int(a.get('quality', 90)))
        if method == 'imagePrepareEditor':
            result.update({'originalWidth': original_size[0], 'originalHeight': original_size[1]})
        return result
    if method == 'imageProcess':
        paths = a['paths']
        require(len(paths) == 1, '多张图片请使用拼图工作台')
        im = image(paths[0])
        width = int(a.get('width', 1080))
        require(16 <= width <= 4096, '输出宽度须为 16—4096 px')
        height = max(1, round(im.height * width / im.width))
        require(height <= 4096, '输出高度超过 4096 px，请减小宽度')
        im = im.resize((width, height), Image.Resampling.LANCZOS)
        if a.get('watermark'):
            text = a['watermark']
            require(len(text) <= 128, '水印最多 128 字符')
            draw = ImageDraw.Draw(im)
            f = font(max(16, width // 24))
            box = draw.textbbox((0, 0), text, font=f)
            draw.text((max(8, width - box[2] - 16), max(8, height - box[3] - 16)), text, font=f, fill='white', stroke_width=1, stroke_fill='black')
        return image_save(im, a.get('format', 'JPEG'), int(a.get('quality', 90)))
    raise ValueError('图片操作不支持')

def creative(method, a):
    source = checked(a['path'], 500 * 1024 * 1024)
    if method == 'ocr':
        result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                                 '-File', str(ROOT / 'ocr.ps1'), '-ImagePath', str(source.resolve())],
                                capture_output=True, encoding='utf-8', errors='replace', timeout=90,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        failure = result.stderr.strip()[-1500:]
        if 'Chinese OCR language resources unavailable' in failure:
            failure = '请在 Windows 设置 → 时间和语言 → 语言中安装中文 OCR 资源后重试。'
        require(result.returncode == 0, failure or 'Windows OCR 未就绪')
        return json.loads(result.stdout.strip())
    if method in ('exifRead', 'exifWrite'):
        with Image.open(source) as im:
            require(im.format == 'JPEG', '照片信息编辑目前支持 JPEG')
            exif = im.getexif()
        fields = {'拍摄时间': 36867, '作者': 315, '版权': 33432, '描述': 270,
                  '相机': 272, '方向': 274}
        if method == 'exifRead':
            values = {k: str(exif.get(tag, '')) for k, tag in fields.items()}
            nested = exif.get_ifd(34665) if 34665 in exif else {}
            values['拍摄时间'] = str(nested.get(36867, exif.get(36867, '')))
            gps = exif.get_ifd(34853) if 34853 in exif else {}
            values['纬度'] = str(gps.get(2, ''))
            values['经度'] = str(gps.get(4, ''))
            return values
        if a.get('clear'):
            orientation = exif.get(274)
            exif = Image.Exif()
            if orientation is not None:
                exif[274] = orientation
        else:
            for key, value in a.get('fields', {}).items():
                require(key in ('拍摄时间', '作者', '版权', '描述') and len(value) <= 500, '信息字段无效')
                require(all(32 <= ord(c) <= 126 for c in value), '为兼容 EXIF 照片软件，文字字段请使用英文、数字和常用半角符号')
                if key == '拍摄时间':
                    import re
                    require(not value or re.fullmatch(r'\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}', value), '拍摄时间格式为 YYYY:MM:DD HH:MM:SS')
                    nested = exif.get_ifd(34665) if 34665 in exif else {}
                    nested[36867] = value
                    exif[34665] = nested
                else:
                    exif[fields[key]] = value
        data = source.read_bytes()
        # Replace only EXIF APP1; leave JPEG entropy-coded pixels and other segments untouched.
        payload = exif.tobytes()
        require(len(payload) + 2 < 65536, 'EXIF 信息过大')
        assembled = bytearray(b'\xff\xd8\xff\xe1' + (len(payload) + 2).to_bytes(2, 'big') + payload)
        position = 2
        while position < len(data):
            require(data[position] == 255, 'JPEG 结构不完整')
            marker = data[position + 1]
            if marker in (0xda, 0xd9):
                assembled.extend(data[position:]); break
            length = int.from_bytes(data[position + 2:position + 4], 'big')
            require(length >= 2 and position + 2 + length <= len(data), 'JPEG 段无效')
            segment = data[position:position + 2 + length]
            if not (marker == 0xe1 and segment[4:10] == b'Exif\x00\x00'):
                assembled.extend(segment)
            position += 2 + length
        target = output('jpg'); target.write_bytes(assembled)
        return {'path': str(target)}
    if method == 'extractAudio':
        target = output('m4a')
        ffmpeg(['-i', str(source), '-map', '0:a:0', '-vn', '-c:a', 'aac', '-b:a', '192k', str(target)])
        return {'path': str(target), 'bytes': target.stat().st_size}
    raise ValueError('不支持的创作操作')

def main():
    global CACHE, MANIFEST
    request = json.load(sys.stdin)
    CACHE = Path(request['cache']).resolve()
    MANIFEST = Path(request['manifest']) if request.get('manifest') else None
    CACHE.mkdir(parents=True, exist_ok=True)
    try:
        result = pdf(request['method'], request['args']) if request['channel'] == 'saisuite/pdf' else creative(request['method'], request['args']) if request['channel'] == 'saisuite/creative' else media(request['method'], request['args'])
        print(json.dumps({'result': result}, ensure_ascii=True))
    except Exception as error:
        for path in CREATED:
            path.unlink(missing_ok=True)
        code = 'PASSWORD' if isinstance(error, (WrongPasswordError, FileNotDecryptedError)) else 'FILE_ERROR'
        print(json.dumps({'error': str(error), 'code': code}, ensure_ascii=True))

if __name__ == '__main__':
    main()
