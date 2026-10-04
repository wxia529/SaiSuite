# Noto Emoji fallback

`NotoColorEmoji.ttf` is the unmodified Windows-compatible color font from
[googlefonts/noto-emoji](https://github.com/googlefonts/noto-emoji), commit
`e20cbc2bbec1926686be9f9bee7d1d2cfa1fea0e`, file
`2D/fonts/NotoColorEmoji_WindowsCompatible.ttf`.

- Size: 10,739,048 bytes.
- SHA-256: `2c7ede2f5438f9c1da098778bd681535933a345334008bb03fc51119f6b1cd72`.
- License: SIL Open Font License 1.1, bundled in
  `assets/licenses/noto-emoji-LICENSE.txt` and registered in the app's licenses.
- Flutter family alias: `SaiEmoji`. The poster canvas, custom sticker input and
  sticker chips use this fallback so newer emoji do not rely on the device font.

The asset is bundled; runtime use makes no font download request.
