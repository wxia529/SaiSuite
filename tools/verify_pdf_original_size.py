"""Independent inspection of the PDF produced by test_pdf_original_size.ps1."""
from pathlib import Path

from PIL import Image, ImageChops, ImageOps
from pypdf import PdfReader


def main():
    reader = PdfReader('.buildlog/pdf-original-size-verified.pdf')
    fixtures = Path('.buildlog/pdf-original-size-fixtures')
    files = [fixtures / 'wide.png', fixtures / 'portrait.png'] + [
        fixtures / f'orientation-{i}.jpg' for i in range(1, 9)
    ]
    assert len(reader.pages) == len(files)
    for index, (page, path) in enumerate(zip(reader.pages, files), 1):
        with Image.open(path) as source:
            expected = ImageOps.exif_transpose(source).convert('RGBA')
        images = list(page.images)
        assert len(images) == 1
        actual = images[0].image.convert('RGBA')
        assert (float(page.mediabox.width), float(page.mediabox.height)) == expected.size
        assert actual.size == expected.size
        delta = max(channel[1] for channel in ImageChops.difference(actual, expected).getextrema())
        assert delta <= (3 if path.suffix == '.jpg' else 0), (index, delta)
        print(f'Page {index}: {actual.size}, RGBA max difference {delta}; original dimensions preserved')
    print('All 10 pages verified, including PNG alpha and all eight EXIF orientations.')


if __name__ == '__main__':
    main()
