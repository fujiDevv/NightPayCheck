"""Render the editable master and App Store exports. Requires Pillow and resvg-py."""
import base64
import html
import io
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

from PIL import Image
import resvg_py

ROOT = Path(__file__).resolve().parents[1]
W, H = 440, 956
INK, PAPER, GOLD = "#242320", "#f6f3ec", "#f3b94e"
PANELS = [
    ("welcome", "Missing $36", "on payday?", "Check the weekend line on your payslip."),
    ("roster", "Your nights,", "in one place.", "Keep planned shifts and actual hours together."),
    ("rates", "Set your", "hourly rates.", "Add your night and weekend differentials."),
    ("estimate", "See what your", "shifts earn.", "Follow the hours behind your gross estimate."),
    ("compare", "Check your", "payslip.", "Compare your payslip with a finished period."),
]


def svg_text(x, y, value, size, color, weight=400, spacing=0):
    return (f'<text x="{x}" y="{y}" font-family="Helvetica Neue, Arial" '
            f'font-size="{size}" font-weight="{weight}" letter-spacing="{spacing}" '
            f'fill="{color}">{html.escape(value)}</text>')


def embedded(path):
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def phone(key, x, y, width, angle):
    height = width * H / W
    capture = ROOT / "captures" / f"{key}.png"
    with Image.open(capture) as im:
        assert im.size == (1320, 2868)
    clip = f"display-{key}"
    return "".join([
        f'<g id="phone-{key}" transform="translate({x} {y}) rotate({angle} {width/2} {height/2})">',
        f'<rect x="-7" y="-7" width="{width+14}" height="{height+14}" rx="46" fill="#151515" stroke="#8e8d88" stroke-width="2"/>',
        f'<defs><clipPath id="{clip}"><rect width="{width}" height="{height}" rx="39"/></clipPath></defs>',
        f'<image width="{width}" height="{height}" clip-path="url(#{clip})" href="{embedded(capture)}"/>',
        f'<rect x="{width/2-30}" y="8" width="60" height="17" rx="9" fill="#101010"/>',
        '</g>',
    ])


def connected_layout():
    # All artwork uses panorama coordinates. Only the final raster is sliced.
    paper, ink, muted = "#f1f1ee", "#111210", "#53544f"
    ribbon = "M-100 650 C160 992 368 920 565 720 S920 617 1090 757 S1435 949 1620 749 S1970 515 2300 735"
    artwork = [
        f'<rect width="2200" height="956" fill="{paper}"/>',
        '<g id="continuous-ribbon" fill="none">',
        f'<path d="{ribbon}" stroke="#d4d5cf" stroke-width="85"/>',
        f'<path d="{ribbon}" stroke="#f8f8f5" stroke-width="2"/>',
        '</g>',
    ]
    for i, (_, line1, line2, description) in enumerate(PANELS):
        x = i * W + 28
        artwork.extend([
            svg_text(x, 42, "NIGHTPAYCHECK", 12, muted, 650, 1.0),
            svg_text(x+365, 42, f"0{i+1}", 12, muted, 500),
            svg_text(x, 130, line1, 56, ink, 700, -2.8),
            svg_text(x, 190, line2, 56, ink, 700, -2.8),
            svg_text(x, 231, description, 17, muted, 400, -.4),
        ])
    artwork.extend([
        phone("roster", 500, 330, 327, 5),
        phone("rates", 939, 344, 323, -5),
        phone("estimate", 1384, 320, 329, 4),
        phone("compare", 1825, 343, 327, -4),
        # The illustration crosses the first join while the owl's face stays on panel one.
        f'<image id="night-owl" x="99" y="290" width="385" height="440" href="{embedded(ROOT.parent / "Mascot" / "NightOwl.png")}"/>',
        '<g id="rate-sticker" transform="translate(32 765) rotate(-6)">',
        '<rect width="300" height="92" rx="18" fill="#151613" stroke="white" stroke-width="3"/>',
        svg_text(19, 30, "WEEKEND EXTRA · EXAMPLE", 12, "#d0d1ca", 600, 1.1),
        svg_text(18, 70, "12h × $3 = $36", 34, "white", 700, -1.2),
        '</g>',
        '<g id="shift-sticker" transform="translate(698 849) rotate(5)">',
        '<rect width="210" height="52" rx="26" fill="#151613" stroke="white" stroke-width="3"/>',
        '<path d="M32 14a12 12 0 1 0 10 18 13 13 0 0 1-10-18z" fill="#fafaf6"/>',
        svg_text(54, 34, "7 PM – 7 AM", 22, "white", 700, -.4),
        '</g>',
        '<g id="pay-sticker" transform="translate(1133 691) rotate(-6)">',
        '<path d="M0 8Q0 0 8 0H220Q228 0 228 8V119L215 113 202 119 189 113 176 119 163 113 150 119 137 113 124 119 111 113 98 119 85 113 72 119 59 113 46 119 33 113 20 119 7 113 0 116Z" fill="#fff" stroke="#31322e" stroke-width="2"/>',
        svg_text(16, 27, "ESTIMATED GROSS", 12, muted, 650, .8),
        svg_text(15, 69, "$2,993.58", 40, ink, 700, -1.8),
        '<path d="M16 80H211" stroke="#c1c2ba" stroke-dasharray="3 3"/>',
        svg_text(16, 101, "NOV 2 – 15", 12, muted, 600, .8),
        '</g>',
        '<g id="check-sticker" transform="translate(1758 788) rotate(9)">',
        '<circle r="45" fill="#fff" stroke="#232420" stroke-width="2"/>',
        '<circle r="38" fill="none" stroke="#a3a49c" stroke-dasharray="2 3"/>',
        '<path d="M-15 0l10 11 22-26" fill="none" stroke="#191a17" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>',
        '</g>',
    ])
    return "".join(artwork)


def svg(body, start, width, height, view_width):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'preserveAspectRatio="none" viewBox="{start} 0 {view_width} {H}">{body}</svg>')


def png(svg_string, path):
    with Image.open(io.BytesIO(resvg_py.svg_to_bytes(svg_string=svg_string))) as im:
        im.convert("RGB").save(path)


def ipad_panel():
    capture = ROOT / "captures" / "ipad-roster.png"
    with Image.open(capture) as image:
        assert image.size == (2064, 2752)
    body = "".join([
        '<rect width="1032" height="1376" fill="#242320"/>',
        '<circle cx="58" cy="56" r="8" fill="#f3b94e"/>',
        svg_text(79, 64, "NightPayCheck", 25, PAPER, 650, -.6),
        '<path d="M50 96H982" stroke="#53514b"/>',
        svg_text(50, 200, "Your nights, in one place.", 70, PAPER, 700, -2.8),
        svg_text(52, 254, "Keep planned shifts and actual hours together.", 28, "#cbc7be"),
        '<path d="M0 300H1032" stroke="#53514b" stroke-dasharray="4 7"/>',
        '<rect x="138" y="340" width="756" height="1004" rx="28" fill="#101010" stroke="#787670"/>',
        '<defs><clipPath id="tablet"><rect x="144" y="346" width="744" height="992" rx="22"/></clipPath></defs>',
        f'<image href="{embedded(capture)}" x="144" y="346" width="744" height="992" clip-path="url(#tablet)"/>',
    ])
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="2064" height="2752" viewBox="0 0 1032 1376">{body}</svg>'


def main():
    artwork = connected_layout()
    count = len(PANELS)
    master = svg(artwork, 0, W * count, H, W * count)
    (ROOT / "source" / "NightPayCheck-Master.svg").write_text(master)
    png(master, ROOT / "preview.png")
    with ZipFile(ROOT / "NightPayCheck-App-Store-Screenshots.zip", "w", ZIP_DEFLATED) as archive:
        for name, width, height in [("iPhone-large", 1320, 2868), ("iPhone-medium", 1206, 2622)]:
            folder = ROOT / "exports" / name
            folder.mkdir(parents=True, exist_ok=True)
            panorama = svg(artwork, 0, width * count, height, W * count)
            with Image.open(io.BytesIO(resvg_py.svg_to_bytes(svg_string=panorama))) as rendered:
                strip = rendered.convert("RGB")
                for i, item in enumerate(PANELS):
                    filename = f"{i+1:02}-{item[0]}.png"
                    tile = strip.crop((i*width, 0, (i+1)*width, height))
                    tile.save(folder / filename)
                    archive.write(folder / filename, f"{name}/{filename}")
        tablet = ipad_panel()
        (ROOT / "source" / "NightPayCheck-iPad.svg").write_text(tablet)
        target = ROOT / "exports" / "iPad-13" / "01-roster.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        png(tablet, target)
        archive.write(target, f"iPad-13/{target.name}")


if __name__ == "__main__":
    main()
