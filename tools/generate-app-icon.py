"""Generates Topaz's app icon in the neon colours of the TopBar wordmark
(tools/generate-wordmark.py). Two designs (see VARIANTS near the end):

  jukebox  (SHIPPED) a retro jukebox, no letters: arched cabinet with a neon tube
           outline (violet top, pink sides, cyan foot), a vinyl record in the
           glowing dome window, selector strip, speaker grille, neon base.
           <= 32 px: cabinet, record, two grille bars and base only, much thicker.
  tj       the earlier candidate: "TJ" monogram in Monoton (T pink -> violet,
           J cyan) in a neon jukebox arch; <= 48 px without the arch.

Outputs (repo root relative):
  app.ico                        Windows exe icon (app.rc), window/taskbar icon,
                                 AUTO PLAY notification icon
                                 (16, 20, 24, 32, 40, 48, 64, 128, 256 px)
  app_icon.png                   256 px, TopBar logo (a QML Image doesn't reliably
                                 pick the largest frame of a multi-size .ico)
  packaging/linux/topaz.png      256 px Linux launcher icon
  tools/app-icon-preview-<variant>.png  all sizes side by side, review only (untracked)
app_icon.png is also the About dialog's icon.

Unlike the wordmark SVGs, the icon master is only ever rasterized here (by
librsvg), never by Qt -- so it may use SVG filters (the Gaussian-blur glow).

Font (tj variant only): Monoton by Vernon Adams (SIL Open Font License 1.1),
downloaded at run time.

Try a design without touching the shipped files:
  ... python tools/generate-app-icon.py tj --preview

Run from the repo root (Git Bash, Docker Desktop running):

  MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/src" -w /src python:3.12-slim bash -c \
    "apt-get update -qq && apt-get install -y -qq librsvg2-bin >/dev/null && \
     pip install -q fonttools uharfbuzz pillow && python tools/generate-app-icon.py"
"""
import os
import sys
import subprocess
import tempfile
import urllib.request

import uharfbuzz as hb
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

FONT_URL = "https://github.com/google/fonts/raw/main/ofl/monoton/Monoton-Regular.ttf"
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


# Same tube colours as the wordmark
PINK = [(0, "#FFD1F0"), (0.5, "#FF4FB8"), (1, "#B03BFF")]
CYAN = [(0, "#D9FFFF"), (0.5, "#3BE8FF"), (1, "#2B8CFF")]

tmp = tempfile.gettempdir()
font_path = os.path.join(tmp, "Monoton-Regular.ttf")
if not os.path.exists(font_path):
    urllib.request.urlretrieve(FONT_URL, font_path)
tt = TTFont(font_path)
glyph_set = tt.getGlyphSet()
order = tt.getGlyphOrder()
face = hb.Face(hb.Blob.from_file_path(font_path))
hb_font = hb.Font(face)
upem = face.upem


def glyph_runs(text, size):
    """[(glyph name, x, y_offset)] kerned by HarfBuzz, at font size `size`."""
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(hb_font, buf, {"kern": True})
    s = size / upem
    x, out = 0.0, []
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        out.append((order[info.codepoint], x + pos.x_offset * s, pos.y_offset * s))
        x += pos.x_advance * s
    return out


def outline(name, size, x, baseline):
    s = size / upem
    pen = SVGPathPen(glyph_set)
    glyph_set[name].draw(TransformPen(pen, (s, 0, 0, -s, x, baseline)))
    bpen = BoundsPen(glyph_set)
    glyph_set[name].draw(TransformPen(bpen, (s, 0, 0, -s, x, baseline)))
    return pen.getCommands(), bpen.bounds   # bounds: (xmin, ymin, xmax, ymax)


def gradient(gid, y1, y2, stops):
    st = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return (f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" '
            f'x1="0" y1="{y1:.1f}" x2="0" y2="{y2:.1f}">{st}</linearGradient>')


def glow_filter(std):
    """Neon glow: wide + tight Gaussian blur under the sharp source."""
    return (f'<filter id="glow" x="-30%" y="-30%" width="160%" height="160%">'
            f'<feGaussianBlur in="SourceGraphic" stdDeviation="{std}" result="b1"/>'
            f'<feGaussianBlur in="SourceGraphic" stdDeviation="{std / 3:.1f}" result="b2"/>'
            f'<feMerge><feMergeNode in="b1"/><feMergeNode in="b1"/><feMergeNode in="b2"/>'
            f'<feMergeNode in="SourceGraphic"/></feMerge></filter>')


TILE = ('<radialGradient id="tile" gradientUnits="userSpaceOnUse" cx="128" cy="110" r="170">'
        '<stop offset="0" stop-color="#2A1242"/><stop offset="0.6" stop-color="#140A20"/>'
        '<stop offset="1" stop-color="#07040B"/></radialGradient>')
TILE_RECT = '<rect x="4" y="4" width="248" height="248" rx="52" fill="url(#tile)"/>'


def master_svg_jukebox(small):
    """Retro jukebox, no letters: arched cabinet with a neon tube outline, a
    vinyl record in the glowing dome window, selector strip, speaker grille,
    neon base. `small` (<= 32 px): cabinet, record and base only, much thicker."""
    W = 256
    s = small
    defs = (
        TILE
        # Cabinet tube: violet over the top, pink down the sides, cyan at the foot
        + '<linearGradient id="tube" gradientUnits="userSpaceOnUse" x1="0" y1="40" x2="0" y2="232">'
          '<stop offset="0" stop-color="#B03BFF"/><stop offset="0.5" stop-color="#FF4FB8"/>'
          '<stop offset="1" stop-color="#3BE8FF"/></linearGradient>'
        + '<linearGradient id="body" gradientUnits="userSpaceOnUse" x1="0" y1="40" x2="0" y2="230">'
          '<stop offset="0" stop-color="#2C1446"/><stop offset="1" stop-color="#110918"/></linearGradient>'
        + gradient("label", 100, 124, CYAN)
        + gradient("bars", 186, 216, PINK)
        + glow_filter(10 if s else 6)
    )
    cabinet = "M 60 226 L 60 112 A 68 68 0 0 1 196 112 L 196 226 Z"
    dome = "M 78 150 L 78 114 A 50 50 0 0 1 178 114 L 178 150 Z"
    rec_r = 38 if s else 28
    rec_y = 118 if s else 114

    body = TILE_RECT
    # Unlit parts first (no glow): cabinet body, dome window, record vinyl
    body += f'<path d="{cabinet}" fill="url(#body)"/>'
    if not s:
        body += f'<path d="{dome}" fill="#1E0F30"/>'
    body += f'<circle cx="128" cy="{rec_y}" r="{rec_r}" fill="#0A0610"/>'
    if not s:
        for gr in (22, 17):     # grooves
            body += (f'<circle cx="128" cy="{rec_y}" r="{gr}" fill="none" '
                     f'stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="1.2"/>')

    # Neon parts, all under one glow
    neon = []
    neon.append(f'<path d="{cabinet}" fill="none" stroke="url(#tube)" '
                f'stroke-width="{18 if s else 6}" stroke-linejoin="round"/>')
    if not s:
        neon.append(f'<path d="{dome}" fill="none" stroke="#3BE8FF" stroke-width="3.5" '
                    f'stroke-linejoin="round"/>')
    neon.append(f'<circle cx="128" cy="{rec_y}" r="{rec_r}" fill="none" stroke="#FF4FB8" '
                f'stroke-width="{9 if s else 2.5}"/>')
    neon.append(f'<circle cx="128" cy="{rec_y}" r="{14 if s else 9}" fill="url(#label)"/>')
    neon.append(f'<circle cx="128" cy="{rec_y}" r="{4 if s else 2}" fill="#0A0610"/>')
    if not s:
        # Selector strip with alternating pink/cyan buttons
        neon.append('<rect x="82" y="160" width="92" height="14" rx="4" fill="#120A1C" '
                    'stroke="#B03BFF" stroke-width="2.5"/>')
        for i in range(6):
            c = "#FF4FB8" if i % 2 == 0 else "#3BE8FF"
            neon.append(f'<circle cx="{92 + i * 14.4:.1f}" cy="167" r="2.6" fill="{c}"/>')
        # Speaker grille: five vertical tubes
        for x in (92, 110, 128, 146, 164):
            neon.append(f'<path d="M {x} 188 L {x} 214" stroke="url(#bars)" stroke-width="6" '
                        f'stroke-linecap="round"/>')
    else:
        # Grille hint: two fat bars
        for x in (108, 148):
            neon.append(f'<path d="M {x} 182 L {x} 208" stroke="url(#bars)" stroke-width="16" '
                        f'stroke-linecap="round"/>')
    neon.append(f'<path d="M 44 232 L 212 232" stroke="#3BE8FF" stroke-width="{16 if s else 6}" '
                f'stroke-linecap="round"/>')
    body += '<g filter="url(#glow)">' + "".join(neon) + '</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" '
            f'viewBox="0 0 {W} {W}"><defs>{defs}</defs>{body}</svg>')


def master_svg_tj(small):
    """256x256 master. `small` = simplified variant for tiny sizes."""
    W = 256
    size = 196 if small else 126            # Monoton font size
    runs = glyph_runs("TJ", size)
    # First pass at baseline 0 to measure, then centre the monogram.
    paths, boxes = [], []
    for name, x, _ in runs:
        d, b = outline(name, size, x, 0)
        boxes.append(b)
    xmin = min(b[0] for b in boxes); xmax = max(b[2] for b in boxes)
    ymin = min(b[1] for b in boxes); ymax = max(b[3] for b in boxes)
    cx_target, cy_target = W / 2, (W / 2 + (16 if not small else 0))
    dx = cx_target - (xmin + xmax) / 2
    dy = cy_target - (ymin + ymax) / 2
    for name, x, _ in runs:
        d, b = outline(name, size, x + dx, dy)
        paths.append((d, b))
    (dT, bT), (dJ, bJ) = paths

    glow = 9 if small else 7
    defs = (
        gradient("pink", bT[1], bT[3], PINK)
        + gradient("cyan", bJ[1], bJ[3], CYAN)
        # Arch frame: pink at the sides, violet over the top, cyan at the base
        + '<linearGradient id="arch" gradientUnits="userSpaceOnUse" x1="0" y1="20" x2="0" y2="236">'
          '<stop offset="0" stop-color="#B03BFF"/><stop offset="0.55" stop-color="#FF4FB8"/>'
          '<stop offset="1" stop-color="#3BE8FF"/></linearGradient>'
        + '<radialGradient id="tile" gradientUnits="userSpaceOnUse" cx="128" cy="110" r="170">'
          '<stop offset="0" stop-color="#2A1242"/><stop offset="0.6" stop-color="#140A20"/>'
          '<stop offset="1" stop-color="#07040B"/></radialGradient>'
        + f'<filter id="glow" x="-30%" y="-30%" width="160%" height="160%">'
          f'<feGaussianBlur in="SourceGraphic" stdDeviation="{glow}" result="b1"/>'
          f'<feGaussianBlur in="SourceGraphic" stdDeviation="{glow / 3:.1f}" result="b2"/>'
          f'<feMerge><feMergeNode in="b1"/><feMergeNode in="b1"/><feMergeNode in="b2"/>'
          f'<feMergeNode in="SourceGraphic"/></feMerge></filter>'
    )
    body = '<rect x="4" y="4" width="248" height="248" rx="52" fill="url(#tile)"/>'
    if not small:
        # Jukebox arch: straight sides, semicircular top, open at the bottom
        # (the ends curl inwards a little like a jukebox's base).
        arch = ("M 38 210 L 38 118 A 90 90 0 0 1 218 118 L 218 210")
        body += (f'<g filter="url(#glow)"><path d="{arch}" fill="none" stroke="url(#arch)" '
                 f'stroke-width="7" stroke-linecap="round"/>'
                 f'<path d="M 28 222 L 228 222" fill="none" stroke="#3BE8FF" stroke-width="6" '
                 f'stroke-linecap="round"/></g>')
    body += (f'<g filter="url(#glow)"><path d="{dT}" fill="url(#pink)"/>'
             f'<path d="{dJ}" fill="url(#cyan)"/></g>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" '
            f'viewBox="0 0 {W} {W}"><defs>{defs}</defs>{body}</svg>')


def render(svg_text, px, path):
    src = os.path.join(tmp, "topaz-icon-master.svg")
    with open(src, "w") as f:
        f.write(svg_text)
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), src, "-o", path], check=True)


# Usage: generate-app-icon.py [tj|jukebox] [--preview]
#   variant   which design (default: VARIANT below = the one Topaz ships)
#   --preview only write tools/app-icon-preview-<variant>.png, touch nothing else
VARIANT = "jukebox"
VARIANTS = {   # name: (master builder, largest size that uses the small master)
    "tj":      (master_svg_tj, 48),
    "jukebox": (master_svg_jukebox, 32),
}
args = [a for a in sys.argv[1:] if not a.startswith("--")]
variant = args[0] if args else VARIANT
preview_only = "--preview" in sys.argv
builder, small_max = VARIANTS[variant]

big, small = builder(False), builder(True)
frames = []
for px in SIZES:
    p = os.path.join(tmp, f"topaz-icon-{px}.png")
    render(small if px <= small_max else big, px, p)
    frames.append(Image.open(p).convert("RGBA"))


def review_sheet(path):
    """Every size at 1:1 on the TopBar background."""
    sheet = Image.new("RGBA", (sum(SIZES) + 12 * len(SIZES) + 12, 256 + 24), "#131313")
    x = 12
    for im in frames:
        sheet.alpha_composite(im, (x, 12 + 256 - im.height))
        x += im.width + 12
    sheet.save(path)


if preview_only:
    review_sheet(f"tools/app-icon-preview-{variant}.png")
    print(f"tools/app-icon-preview-{variant}.png written (preview only)")
    sys.exit(0)

largest = frames[-1]
# bitmap_format="bmp": classic 32-bit BMP frames (with alpha), like the original
# app.ico -- the format proven with windres, the Windows shell and Qt's own ICO
# reader (window icon on Linux, AUTO PLAY notification icon). Pillow's default
# would store every frame as PNG.
largest.save("app.ico", format="ICO", sizes=[(s, s) for s in SIZES],
             append_images=frames[:-1], bitmap_format="bmp")
largest.save("packaging/linux/topaz.png")
largest.save("app_icon.png")

review_sheet(f"tools/app-icon-preview-{variant}.png")
print(f"[{variant}] app.ico, app_icon.png, packaging/linux/topaz.png, "
      f"tools/app-icon-preview-{variant}.png written")
