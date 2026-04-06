#!/usr/bin/env python3
import argparse
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

WIDTH = 1200
HEIGHT = 675
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

FONT_CANDIDATES = {
    "Black": [
        os.path.join(ROOT_DIR, "assets/fonts/noto-sans-jp/NotoSansJP-Black.otf"),
        os.path.join(ROOT_DIR, "assets/fonts/noto-sans-jp/NotoSansJP-Bold.otf"),
    ],
    "Bold": [
        os.path.join(ROOT_DIR, "assets/fonts/noto-sans-jp/NotoSansJP-Bold.otf"),
        os.path.join(ROOT_DIR, "assets/fonts/noto-sans-jp/NotoSansJP-Medium.otf"),
    ],
}

FONT_FALLBACKS = [
    os.path.expanduser("~/Library/Fonts/NotoSansJP[wght].ttf"),
    "/Library/Fonts/NotoSansJP[wght].ttf",
    "/System/Library/Fonts/Supplemental/NotoSansJP[wght].ttf",
    "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc",
]


def find_font(variation: str = "Bold"):
    for candidate in FONT_CANDIDATES.get(variation, []) + FONT_FALLBACKS:
        if os.path.exists(candidate):
            return candidate
    return None


def load_font(size: int, variation: str = "Bold"):
    path = find_font(variation)
    if path:
        return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def fit_font(text: str, max_width: int, start_size: int, min_size: int, variation: str):
    probe = Image.new("RGBA", (32, 32), (255, 255, 255, 0))
    draw = ImageDraw.Draw(probe)
    for size in range(start_size, min_size - 1, -2):
        font = load_font(size, variation)
        bbox = draw.textbbox((0, 0), text, font=font)
        if bbox[2] - bbox[0] <= max_width:
            return font
    return load_font(min_size, variation)


def add_grain(base: Image.Image):
    grain = Image.effect_noise((WIDTH, HEIGHT), 5).convert("L")
    grain = ImageOps.autocontrast(grain, cutoff=3)
    grain_rgba = Image.new("RGBA", (WIDTH, HEIGHT), (255, 255, 255, 0))
    grain_rgba.putalpha(grain.point(lambda p: 10 if p > 132 else 0))
    base.alpha_composite(grain_rgba)


def add_soft_glow(base: Image.Image, center, radius, fill):
    glow = Image.new("RGBA", base.size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(glow)
    x, y = center
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)
    glow = glow.filter(ImageFilter.GaussianBlur(radius // 2))
    base.alpha_composite(glow)


def shadowed_round_rect(base: Image.Image, rect, radius, fill, shadow_alpha=56):
    shadow = Image.new("RGBA", base.size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle(rect, radius=radius, fill=(30, 42, 68, shadow_alpha))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    base.alpha_composite(shadow)
    panel = Image.new("RGBA", base.size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(panel)
    draw.rounded_rectangle(rect, radius=radius, fill=fill)
    base.alpha_composite(panel)


def rounded_pill(draw: ImageDraw.ImageDraw, rect, fill):
    draw.rounded_rectangle(rect, radius=(rect[3] - rect[1]) // 2, fill=fill)


def compose_offset_card(base: Image.Image, title: str, subtitle: str):
    title_rect = (74, 84, 604, 420)
    shadowed_round_rect(base, title_rect, 28, (247, 243, 233, 242))
    shadowed_round_rect(base, (98, 346, 446, 400), 16, (19, 36, 74, 255), shadow_alpha=36)
    draw = ImageDraw.Draw(base)
    heavy = fit_font(title, 430, 78, 56, "Black")
    sub = fit_font(subtitle, 308, 32, 22, "Bold")
    draw.text((116, 136), title.split("\n")[0], font=heavy, fill=(19, 42, 92))
    if "\n" in title:
        draw.text((116, 244), title.split("\n", 1)[1], font=heavy, fill=(19, 42, 92))
    draw.text((132, 354), subtitle, font=sub, fill=(255, 255, 255))


def compose_side_badge(base: Image.Image, title: str, subtitle: str):
    title_rect = (84, 112, 530, 492)
    shadowed_round_rect(base, title_rect, 30, (247, 243, 233, 240))
    shadowed_round_rect(base, (84, 514, 420, 584), 16, (216, 96, 92, 248), shadow_alpha=30)
    draw = ImageDraw.Draw(base)
    heavy = fit_font(title, 360, 74, 52, "Black")
    sub = fit_font(subtitle, 292, 30, 22, "Bold")
    lines = title.split("\n")
    y = 152
    for line in lines:
        draw.text((118, y), line, font=heavy, fill=(19, 42, 92))
        y += 108
    draw.text((116, 528), subtitle, font=sub, fill=(255, 255, 255))


def compose_bottom_strip(base: Image.Image, title: str, subtitle: str):
    title_rect = (66, 74, 632, 360)
    shadowed_round_rect(base, title_rect, 26, (247, 243, 233, 242))
    shadowed_round_rect(base, (66, 388, 512, 452), 18, (19, 36, 74, 252), shadow_alpha=34)
    draw = ImageDraw.Draw(base)
    heavy = fit_font(title, 470, 72, 50, "Black")
    sub = fit_font(subtitle, 390, 28, 20, "Bold")
    lines = title.split("\n")
    y = 124
    for line in lines:
        draw.text((96, y), line, font=heavy, fill=(19, 42, 92))
        y += 102
    draw.text((92, 404), subtitle, font=sub, fill=(255, 255, 255))


def compose_orbital_caption(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    add_soft_glow(base, (930, 278), 140, (126, 179, 255, 44))
    for radius in (116, 156, 196):
        draw.ellipse((930 - radius, 278 - radius, 930 + radius, 278 + radius), outline=(88, 123, 208, 120), width=3)
    for cx, cy, color in (
        (798, 334, (249, 242, 231, 255)),
        (832, 334, (229, 126, 119, 255)),
        (866, 334, (138, 193, 255, 255)),
        (900, 334, (191, 199, 255, 255)),
    ):
        draw.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=color)
    shadowed_round_rect(base, (78, 92, 566, 412), 34, (248, 244, 236, 246))
    shadowed_round_rect(base, (108, 340, 404, 400), 22, (28, 46, 94, 255), shadow_alpha=28)
    heavy = fit_font(title, 390, 78, 54, "Black")
    sub = fit_font(subtitle, 250, 32, 22, "Bold")
    y = 140
    for line in title.split("\n"):
        draw.text((118, y), line, font=heavy, fill=(22, 44, 96))
        y += 108
    draw.text((132, 352), subtitle, font=sub, fill=(255, 255, 255))


def compose_soft_sticker(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    add_soft_glow(base, (984, 188), 90, (255, 232, 179, 32))
    add_soft_glow(base, (906, 478), 120, (114, 185, 255, 28))
    shadowed_round_rect(base, (88, 104, 594, 420), 36, (248, 244, 236, 248))
    for rect, fill in (
        ((838, 120, 914, 172), (122, 188, 245, 255)),
        ((938, 96, 1038, 154), (227, 116, 101, 255)),
        ((1070, 100, 1160, 156), (247, 243, 233, 255)),
    ):
        shadowed_round_rect(base, rect, 22, fill, shadow_alpha=18)
    rounded_pill(draw, (110, 346, 420, 408), (227, 116, 101, 255))
    rounded_pill(draw, (112, 349, 416, 404), (28, 46, 94, 255))
    heavy = fit_font(title, 404, 78, 54, "Black")
    sub = fit_font(subtitle, 264, 30, 22, "Bold")
    y = 140
    for line in title.split("\n"):
        draw.text((126, y), line, font=heavy, fill=(22, 44, 96))
        y += 106
    draw.text((140, 358), subtitle, font=sub, fill=(255, 255, 255))


def compose_vertical_ribbon(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    shadowed_round_rect(base, (78, 82, 480, 506), 30, (248, 244, 236, 246))
    panel = Image.new("RGBA", base.size, (255, 255, 255, 0))
    pdraw = ImageDraw.Draw(panel)
    pdraw.rounded_rectangle((490, 118, 548, 522), radius=26, fill=(226, 118, 103, 240))
    pdraw.rounded_rectangle((560, 118, 608, 448), radius=24, fill=(126, 179, 255, 220))
    panel = panel.filter(ImageFilter.GaussianBlur(0.8))
    base.alpha_composite(panel)
    shadowed_round_rect(base, (102, 420, 396, 478), 18, (28, 46, 94, 255), shadow_alpha=24)
    heavy = fit_font(title, 300, 72, 48, "Black")
    sub = fit_font(subtitle, 248, 30, 22, "Bold")
    y = 128
    for line in title.split("\n"):
        draw.text((116, y), line, font=heavy, fill=(22, 44, 96))
        y += 100
    draw.text((126, 432), subtitle, font=sub, fill=(255, 255, 255))


def compose_corner_stack(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    shadowed_round_rect(base, (86, 90, 574, 392), 32, (248, 244, 236, 244))
    draw.polygon([(0, 675), (0, 470), (238, 675)], fill=(213, 103, 97, 255))
    draw.polygon([(1200, 0), (1200, 176), (950, 0)], fill=(124, 183, 244, 255))
    shadowed_round_rect(base, (112, 326, 434, 386), 18, (28, 46, 94, 255), shadow_alpha=24)
    heavy = fit_font(title, 392, 78, 54, "Black")
    sub = fit_font(subtitle, 268, 30, 22, "Bold")
    y = 136
    for line in title.split("\n"):
        draw.text((124, y), line, font=heavy, fill=(22, 44, 96))
        y += 108
    draw.text((138, 338), subtitle, font=sub, fill=(255, 255, 255))


def compose_split_stage(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    gradient = Image.new("RGBA", base.size, (255, 255, 255, 0))
    gdraw = ImageDraw.Draw(gradient)
    gdraw.polygon([(0, 0), (0, 216), (370, 0)], fill=(39, 56, 96, 168))
    gdraw.polygon([(1200, 675), (904, 675), (1200, 456)], fill=(230, 116, 100, 136))
    base.alpha_composite(gradient)
    shadowed_round_rect(base, (86, 108, 604, 404), 34, (248, 244, 236, 245))
    shadowed_round_rect(base, (108, 334, 454, 396), 18, (28, 46, 94, 255), shadow_alpha=22)
    heavy = fit_font(title, 412, 76, 52, "Black")
    sub = fit_font(subtitle, 286, 30, 22, "Bold")
    y = 148
    for line in title.split("\n"):
        draw.text((122, y), line, font=heavy, fill=(22, 44, 96))
        y += 106
    draw.text((138, 346), subtitle, font=sub, fill=(255, 255, 255))


def compose_right_column(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    shadowed_round_rect(base, (708, 92, 1112, 468), 34, (248, 244, 236, 244))
    shadowed_round_rect(base, (734, 382, 1038, 444), 20, (28, 46, 94, 255), shadow_alpha=20)
    panel = Image.new("RGBA", base.size, (255, 255, 255, 0))
    pdraw = ImageDraw.Draw(panel)
    pdraw.rounded_rectangle((670, 132, 688, 534), radius=9, fill=(122, 188, 245, 220))
    pdraw.rounded_rectangle((652, 164, 664, 492), radius=6, fill=(226, 118, 103, 180))
    base.alpha_composite(panel)
    heavy = fit_font(title, 300, 66, 44, "Black")
    sub = fit_font(subtitle, 260, 30, 21, "Bold")
    y = 138
    for line in title.split("\n"):
        draw.text((740, y), line, font=heavy, fill=(22, 44, 96))
        y += 92
    draw.text((758, 394), subtitle, font=sub, fill=(255, 255, 255))


def compose_center_band(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    shadowed_round_rect(base, (162, 222, 1038, 476), 36, (248, 244, 236, 238))
    shadowed_round_rect(base, (350, 416, 850, 478), 20, (28, 46, 94, 255), shadow_alpha=18)
    heavy = fit_font(title.replace("\n", " "), 720, 72, 48, "Black")
    sub = fit_font(subtitle, 430, 30, 21, "Bold")
    title_text = title.replace("\n", " ")
    title_box = draw.textbbox((0, 0), title_text, font=heavy)
    title_w = title_box[2] - title_box[0]
    draw.text(((WIDTH - title_w) / 2, 286), title_text, font=heavy, fill=(22, 44, 96))
    sub_box = draw.textbbox((0, 0), subtitle, font=sub)
    sub_w = sub_box[2] - sub_box[0]
    draw.text(((WIDTH - sub_w) / 2, 428), subtitle, font=sub, fill=(255, 255, 255))


def compose_edge_stack(base: Image.Image, title: str, subtitle: str):
    draw = ImageDraw.Draw(base)
    panel = Image.new("RGBA", base.size, (255, 255, 255, 0))
    pdraw = ImageDraw.Draw(panel)
    pdraw.rounded_rectangle((38, 38, 438, 637), radius=34, fill=(16, 27, 56, 224))
    pdraw.rounded_rectangle((414, 96, 472, 594), radius=28, fill=(228, 118, 104, 236))
    pdraw.rounded_rectangle((462, 124, 506, 544), radius=22, fill=(112, 166, 255, 214))
    panel = panel.filter(ImageFilter.GaussianBlur(0.6))
    base.alpha_composite(panel)
    shadowed_round_rect(base, (64, 500, 388, 574), 24, (245, 241, 233, 248), shadow_alpha=20)
    heavy = fit_font(title, 288, 82, 56, "Black")
    sub = fit_font(subtitle, 248, 34, 24, "Black")
    y = 92
    for line in title.split("\n"):
        draw.text((78, y), line, font=heavy, fill=(244, 239, 230))
        y += 122
    draw.text((94, 516), subtitle, font=sub, fill=(22, 44, 96))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--background", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", required=True)
    families = [
        "offset-card",
        "side-badge",
        "bottom-strip",
        "orbital-caption",
        "soft-sticker",
        "vertical-ribbon",
        "corner-stack",
        "split-stage",
        "right-column",
        "center-band",
        "edge-stack",
    ]
    parser.add_argument("--family", choices=families, default="offset-card")
    args = parser.parse_args()

    bg = Image.open(args.background).convert("RGB")
    bg = ImageOps.fit(bg, (WIDTH, HEIGHT), method=Image.Resampling.LANCZOS)
    canvas = bg.convert("RGBA")
    add_grain(canvas)

    if args.family == "offset-card":
        compose_offset_card(canvas, args.title, args.subtitle)
    elif args.family == "side-badge":
        compose_side_badge(canvas, args.title, args.subtitle)
    elif args.family == "bottom-strip":
        compose_bottom_strip(canvas, args.title, args.subtitle)
    elif args.family == "orbital-caption":
        compose_orbital_caption(canvas, args.title, args.subtitle)
    elif args.family == "soft-sticker":
        compose_soft_sticker(canvas, args.title, args.subtitle)
    elif args.family == "vertical-ribbon":
        compose_vertical_ribbon(canvas, args.title, args.subtitle)
    elif args.family == "corner-stack":
        compose_corner_stack(canvas, args.title, args.subtitle)
    elif args.family == "right-column":
        compose_right_column(canvas, args.title, args.subtitle)
    elif args.family == "center-band":
        compose_center_band(canvas, args.title, args.subtitle)
    elif args.family == "edge-stack":
        compose_edge_stack(canvas, args.title, args.subtitle)
    else:
        compose_split_stage(canvas, args.title, args.subtitle)

    canvas.convert("RGB").save(args.output, format="PNG", compress_level=0)


if __name__ == "__main__":
    main()
