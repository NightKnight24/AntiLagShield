#!/usr/bin/env python3
"""Generates 4K-supersampled 16:9 YouTube thumbnails using real iPad Retina captures."""

import math
import os
import shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Render at 4K (3840x2160) and downsample with LANCZOS for ultra-clean anti-aliasing
W = 3840
H = 2160

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
HOME_DIR = os.path.expanduser("~")
ASSETS_DIR = os.path.join(BASE_DIR, "assets")

FONT_SANS = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"

_FONT_CACHE = {}


def get_font(ttc_path, size, index):
    key = (ttc_path, size, index)
    if key not in _FONT_CACHE:
        _FONT_CACHE[key] = ImageFont.truetype(ttc_path, size, index=index)
    return _FONT_CACHE[key]


def font_display(size):
    return get_font(FONT_SANS, size, 9)  # Condensed Black


def font_bold(size):
    return get_font(FONT_SANS, size, 1)  # Bold


def font_med(size):
    return get_font(FONT_SANS, size, 10)  # Medium


def font_mono_bold(size):
    return get_font(FONT_MONO, size, 1)


def metrics(font, text):
    bb = font.getbbox(text)
    return bb[2] - bb[0], bb[3] - bb[1], bb[0], bb[1]


def fit_font(text, fn, max_sz, max_w, min_sz=24):
    for sz in range(max_sz, min_sz - 1, -2):
        f = fn(sz)
        w, _, _, _ = metrics(f, text)
        if w <= max_w:
            return f
    f = fn(min_sz)
    w, _, _, _ = metrics(f, text)
    assert w <= max_w + 2, f"Overflow '{text}': {w} > {max_w}"
    return f


def make_studio_backdrop(glow_specs):
    """Creates a rich dark studio background with radial spotlights and subtle dot grid."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    bg = np.zeros((H, W, 3), dtype=np.float32)
    bg[:, :, 0] = 7.0
    bg[:, :, 1] = 10.0
    bg[:, :, 2] = 18.0

    for cx, cy, rx, ry, col, strength in glow_specs:
        dx = (xx - cx) / rx
        dy = (yy - cy) / ry
        dist2 = dx * dx + dy * dy
        falloff = np.exp(-dist2 * 1.35) * strength
        for c in range(3):
            bg[:, :, c] += falloff * col[c]

    # Subtle vignette near outer edges
    vx = (xx - W * 0.5) / (W * 0.58)
    vy = (yy - H * 0.5) / (H * 0.58)
    vig = np.clip(1.0 - 0.28 * (vx * vx + vy * vy), 0.65, 1.0)
    bg *= vig[:, :, None]

    arr = np.clip(bg, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr, mode="RGB").convert("RGBA")

    # Subtle architectural micro-dots in background
    dot_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dot_layer)
    step = 96
    for y in range(48, H, step):
        for x in range(48, W, step):
            dd.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(255, 255, 255, 14))
    return Image.alpha_composite(img, dot_layer)


def make_rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def paste_with_shadow_and_glow(canvas, card_rgba, pos, shadow_offset=(0, 36), shadow_blur=64, glow_col=None, glow_blur=42):
    x, y = pos
    cw, ch = card_rgba.size
    alpha = card_rgba.split()[3]

    if glow_col is not None:
        pad = glow_blur * 3
        glow_layer = Image.new("RGBA", (cw + pad * 2, ch + pad * 2), (0, 0, 0, 0))
        tint = Image.new("RGBA", (cw, ch), (glow_col[0], glow_col[1], glow_col[2], glow_col[3]))
        glow_layer.paste(tint, (pad, pad), mask=alpha)
        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=glow_blur))
        canvas.alpha_composite(glow_layer, (x - pad, y - pad))

    pad_s = shadow_blur * 3
    sh_layer = Image.new("RGBA", (cw + pad_s * 2, ch + pad_s * 2), (0, 0, 0, 0))
    black = Image.new("RGBA", (cw, ch), (0, 0, 0, 215))
    sh_layer.paste(black, (pad_s, pad_s), mask=alpha)
    sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(radius=shadow_blur))
    canvas.alpha_composite(sh_layer, (x - pad_s + shadow_offset[0], y - pad_s + shadow_offset[1]))

    canvas.alpha_composite(card_rgba, (x, y))


def build_ipad_card(src_png, crop_box, card_w, card_h, border_col=(78, 102, 138)):
    im = Image.open(src_png).convert("RGB").crop(crop_box)
    card = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)

    outer_r = 56
    bezel = 30
    d.rounded_rectangle([0, 0, card_w - 1, card_h - 1], radius=outer_r, fill=(18, 23, 33, 255), outline=(*border_col, 255), width=5)
    d.rounded_rectangle([5, 5, card_w - 6, card_h - 6], radius=outer_r - 4, outline=(255, 255, 255, 32), width=2)

    sw = card_w - bezel * 2
    sh = card_h - bezel * 2
    scaled = im.resize((sw, sh), Image.Resampling.LANCZOS).convert("RGBA")
    smask = make_rounded_mask((sw, sh), outer_r - 18)
    card.paste(scaled, (bezel, bezel), mask=smask)

    # Subtle top camera lens dot
    d.ellipse([card_w // 2 - 7, 9, card_w // 2 + 7, 23], fill=(8, 10, 15, 255))
    return card


def build_banner_callout(banner_png, target_w, rim_col=(0, 220, 255)):
    raw = Image.open(banner_png).convert("RGBA")
    rw, rh = raw.size
    # Native corner radius in 850x248 @2x capture is 44px
    native_mask = make_rounded_mask((rw, rh), 44)
    clean_rgba = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    clean_rgba.paste(raw, (0, 0), mask=native_mask)

    scale = target_w / float(rw)
    th = int(round(rh * scale))
    scaled = clean_rgba.resize((target_w, th), Image.Resampling.LANCZOS)
    scaled_r = int(round(44 * scale))

    d = ImageDraw.Draw(scaled)
    d.rounded_rectangle(
        [1, 1, target_w - 2, th - 2],
        radius=scaled_r,
        outline=(*rim_col, 235),
        width=5,
    )
    return scaled


def draw_gradient_headline(canvas, text, font, x, y, max_w, top_rgb, bot_rgb, shadow_shift=(0, 14)):
    w, h, bx0, by0 = metrics(font, text)
    assert w <= max_w, f"Headline '{text}' width {w} exceeds max_w {max_w}"

    pad = 48
    tw, th = w + pad * 2, h + pad * 2
    mask = Image.new("L", (tw, th), 0)
    md = ImageDraw.Draw(mask)
    md.text((pad - bx0, pad - by0), text, font=font, fill=255)

    # Drop shadow
    sh = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    sh_fill = Image.new("RGBA", (tw, th), (0, 0, 0, 210))
    sh.paste(sh_fill, (0, 0), mask=mask)
    sh = sh.filter(ImageFilter.GaussianBlur(radius=18))
    canvas.alpha_composite(sh, (x - pad + shadow_shift[0], y - pad + shadow_shift[1]))

    # Vertical gradient fill
    grad = np.zeros((th, tw, 4), dtype=np.uint8)
    t_vals = np.clip((np.arange(th, dtype=np.float32) - pad) / max(1.0, float(h)), 0.0, 1.0)
    for c in range(3):
        col_line = (top_rgb[c] * (1.0 - t_vals) + bot_rgb[c] * t_vals).astype(np.uint8)
        grad[:, :, c] = col_line[:, None]
    grad[:, :, 3] = np.array(mask)

    canvas.alpha_composite(Image.fromarray(grad, mode="RGBA"), (x - pad, y - pad))
    return y + h


def draw_pill_with_text(
    canvas, box, text, font_fn, pref_sz, text_col, bg_rgba, border_rgba, dot_col=None, check_col=None, auto_width=False
):
    x0, y0, x1, y1 = box
    max_pw = x1 - x0
    ph = y1 - y0

    left_pad = 38
    if dot_col is not None:
        left_pad += 38
    elif check_col is not None:
        left_pad += 62
    right_pad = 44

    avail_w = max_pw - left_pad - right_pad
    avail_h = ph - 24
    assert avail_w > 20 and avail_h > 10, f"Invalid pill box {box}"

    f = fit_font(text, font_fn, pref_sz, avail_w)
    tw, th, bx0, by0 = metrics(f, text)
    assert tw <= avail_w + 2 and th <= avail_h + 4, f"Pill overflow '{text}' in {box}"

    pw = (left_pad + tw + right_pad) if auto_width else max_pw
    layer = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = ph // 2 if auto_width else min(ph // 2, 34)
    d.rounded_rectangle([0, 0, pw - 1, ph - 1], radius=r, fill=bg_rgba, outline=border_rgba, width=4)

    icon_x = 38
    if dot_col is not None:
        cy = ph // 2
        d.ellipse([icon_x, cy - 11, icon_x + 22, cy + 11], fill=(*dot_col, 255))
    elif check_col is not None:
        cy = ph // 2
        cx = icon_x + 20
        d.ellipse(
            [cx - 22, cy - 22, cx + 22, cy + 22],
            fill=(check_col[0], check_col[1], check_col[2], 38),
            outline=(*check_col, 230),
            width=3,
        )
        d.line([(cx - 10, cy + 1), (cx - 2, cy + 9), (cx + 11, cy - 8)], fill=(*check_col, 255), width=5, joint="curve")

    tx = left_pad - bx0
    ty = (ph - th) // 2 - by0
    d.text((tx, ty), text, font=f, fill=(*text_col, 255))
    canvas.alpha_composite(layer, (x0, y0))


def draw_metric_chip(canvas, box, big_val, sub_lbl, accent_rgb):
    x0, y0, x1, y1 = box
    cw, ch = x1 - x0, y1 - y0
    chip = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    d = ImageDraw.Draw(chip)
    d.rounded_rectangle([0, 0, cw - 1, ch - 1], radius=34, fill=(13, 19, 30, 248), outline=(*accent_rgb, 245), width=5)

    pad_x = 34
    f_big = fit_font(big_val, font_display, 108, cw - pad_x * 2)
    bw, bh, bbx0, bby0 = metrics(f_big, big_val)
    f_sub = fit_font(sub_lbl, font_bold, 34, cw - pad_x * 2)
    sw, sh, sbx0, sby0 = metrics(f_sub, sub_lbl)

    total_h = bh + 16 + sh
    assert total_h <= ch - 24, f"Chip vertical overflow: {big_val}"
    top_y = (ch - total_h) // 2

    d.text(((cw - bw) // 2 - bbx0, top_y - bby0), big_val, font=f_big, fill=(*accent_rgb, 255))
    d.text(((cw - sw) // 2 - sbx0, top_y + bh + 16 - sby0), sub_lbl, font=f_sub, fill=(242, 247, 255, 255))
    paste_with_shadow_and_glow(canvas, chip, (x0, y0), shadow_offset=(0, 28), shadow_blur=44, glow_col=(*accent_rgb, 95), glow_blur=30)


# ==============================================================================
# THUMBNAIL 1: "STOP iPAD WI-FI LAG" — Hero App + Floating Notification Banner
# ==============================================================================
def render_thumbnail_1():
    canvas = make_studio_backdrop([
        (2750, 980, 1150, 880, (0, 175, 235), 0.42),
        (2350, 1560, 920, 620, (36, 210, 105), 0.34),
        (680, 760, 900, 760, (0, 120, 190), 0.18),
    ])

    # Right side: Zoomed live iPad UI card (cropped tightly to the 680pt UI cards)
    top_src = os.path.join(ASSETS_DIR, "Screenshot_1_Live_Telemetry.png")
    ipad_card = build_ipad_card(
        top_src,
        crop_box=(270, 36, 1778, 1164),  # exact 4:3 crop around live UI
        card_w=1860,
        card_h=1395,
        border_col=(72, 118, 160),
    )
    paste_with_shadow_and_glow(
        canvas,
        ipad_card,
        pos=(1830, 185),
        shadow_offset=(0, 44),
        shadow_blur=76,
        glow_col=(0, 200, 255, 85),
        glow_blur=54,
    )

    # Floating Notification Bar Banner popping forward over lower-left of iPad
    banner_src = os.path.join(ASSETS_DIR, "Notification_Center_Banner.png")
    banner_card = build_banner_callout(banner_src, target_w=1660, rim_col=(48, 225, 120))
    paste_with_shadow_and_glow(
        canvas,
        banner_card,
        pos=(1560, 1390),
        shadow_offset=(0, 42),
        shadow_blur=68,
        glow_col=(48, 220, 115, 115),
        glow_blur=44,
    )

    # Left side typography (strictly within x=150..1500, clear of right visuals & bottom-right timestamp)
    left_x = 156
    max_left_w = 1380

    draw_pill_with_text(
        canvas,
        (left_x, 195, left_x + 920, 299),
        "iOS & iPadOS 12 – 18  •  FREE",
        font_bold,
        36,
        (72, 242, 130),
        bg_rgba=(14, 42, 30, 235),
        border_rgba=(48, 215, 105, 235),
        dot_col=(58, 235, 115),
        auto_width=True,
    )

    f_h1 = fit_font("STOP iPAD", font_display, 302, max_left_w)
    y_after_1 = draw_gradient_headline(
        canvas,
        "STOP iPAD",
        f_h1,
        left_x,
        366,
        max_left_w,
        top_rgb=(255, 255, 255),
        bot_rgb=(222, 234, 248),
    )

    f_h2 = fit_font("WI-FI LAG", font_display, 302, max_left_w)
    y_after_2 = draw_gradient_headline(
        canvas,
        "WI-FI LAG",
        f_h2,
        left_x,
        y_after_1 + 28,
        max_left_w,
        top_rgb=(0, 238, 255),
        bot_rgb=(48, 228, 122),
    )

    # Clean 3-item feature pills on bottom-left (uniform tight width, readable on mobile)
    pill_y = y_after_2 + 86
    pills = [
        ("0% CPU XNU Kernel Fix", (0, 224, 255), (12, 28, 44, 235), (0, 185, 230, 210)),
        ("Notification Bar Control", (62, 232, 122), (12, 36, 28, 235), (48, 205, 105, 210)),
        ("1-Tap Clear RAM & Cache", (255, 206, 58), (36, 30, 14, 235), (235, 182, 42, 210)),
    ]
    for label, accent, bg_c, bd_c in pills:
        draw_pill_with_text(
            canvas,
            (left_x, pill_y, left_x + 860, pill_y + 132),
            label,
            font_bold,
            52,
            (250, 252, 255),
            bg_rgba=bg_c,
            border_rgba=bd_c,
            check_col=accent,
        )
        pill_y += 158

    assert pill_y <= H - 90, f"Left column exceeded bottom margin: {pill_y}"
    return canvas.convert("RGB")


# ==============================================================================
# THUMBNAIL 2: "NO MORE STUTTER" — Banner Hero + Live Kernel Controls + Chips
# ==============================================================================
def render_thumbnail_2():
    canvas = make_studio_backdrop([
        (2680, 820, 1180, 820, (36, 205, 115), 0.36),
        (2480, 1520, 1050, 760, (0, 180, 245), 0.36),
        (680, 920, 920, 820, (235, 155, 28), 0.18),
    ])

    # Back-right: Scrolled live kernel parameters & switches card (showing sysctls + Banner switch cleanly)
    bot_src = os.path.join(ASSETS_DIR, "Screenshot_4_Network_and_Gamepads.png")
    kernel_card = build_ipad_card(
        bot_src,
        crop_box=(270, 140, 1778, 1268),  # exact 4:3 crop showing live sysctls + Banner switch ON
        card_w=1740,
        card_h=1305,
        border_col=(68, 112, 152),
    )
    paste_with_shadow_and_glow(
        canvas,
        kernel_card,
        pos=(1940, 575),
        shadow_offset=(0, 44),
        shadow_blur=74,
        glow_col=(0, 195, 255, 80),
        glow_blur=48,
    )

    # Top-right hero: Huge crisp Notification Center Banner callout
    banner_src = os.path.join(ASSETS_DIR, "Notification_Center_Banner.png")
    banner_hero = build_banner_callout(banner_src, target_w=1840, rim_col=(0, 228, 255))
    paste_with_shadow_and_glow(
        canvas,
        banner_hero,
        pos=(1760, 155),
        shadow_offset=(0, 44),
        shadow_blur=70,
        glow_col=(0, 220, 255, 120),
        glow_blur=48,
    )

    # Floating hardware benchmark chip positioned cleanly on the lower-left bezel edge
    draw_metric_chip(
        canvas,
        (1480, 1560, 2090, 1855),
        "+607 MB",
        "1-TAP RAM PURGE",
        (58, 235, 122),
    )

    # Left column typography
    left_x = 156
    max_left_w = 1440

    draw_pill_with_text(
        canvas,
        (left_x, 195, left_x + 920, 299),
        "ANTI-LAG SHIELD v1.0",
        font_bold,
        38,
        (0, 230, 255),
        bg_rgba=(12, 32, 48, 235),
        border_rgba=(0, 210, 245, 235),
        dot_col=(0, 230, 255),
        auto_width=True,
    )

    f_h1 = fit_font("NO MORE", font_display, 296, max_left_w)
    y1 = draw_gradient_headline(
        canvas,
        "NO MORE",
        f_h1,
        left_x,
        366,
        max_left_w,
        top_rgb=(255, 255, 255),
        bot_rgb=(224, 234, 246),
    )

    f_h2 = fit_font("STUTTER", font_display, 296, max_left_w)
    y2 = draw_gradient_headline(
        canvas,
        "STUTTER",
        f_h2,
        left_x,
        y1 + 28,
        max_left_w,
        top_rgb=(255, 220, 64),
        bot_rgb=(255, 148, 28),
    )

    pill_y = y2 + 86
    pills = [
        ("Streaming & Gaming Modes", (0, 228, 255), (12, 28, 44, 235), (0, 190, 235, 215)),
        ("Notification Bar Control", (62, 232, 122), (12, 36, 28, 235), (48, 205, 105, 215)),
        ("iOS & iPadOS 12.0 – 18.x", (196, 128, 255), (28, 18, 44, 235), (175, 102, 235, 215)),
    ]
    for label, accent, bg_c, bd_c in pills:
        draw_pill_with_text(
            canvas,
            (left_x, pill_y, left_x + 920, pill_y + 132),
            label,
            font_bold,
            52,
            (250, 252, 255),
            bg_rgba=bg_c,
            border_rgba=bd_c,
            check_col=accent,
        )
        pill_y += 158

    assert pill_y <= H - 90, f"Left column exceeded bottom margin: {pill_y}"
    return canvas.convert("RGB")


def save_youtube_ready(img_4k, base_name, out_dirs):
    im_1080 = img_4k.resize((1920, 1080), Image.Resampling.LANCZOS)
    im_720 = img_4k.resize((1280, 720), Image.Resampling.LANCZOS)

    primary_1080 = os.path.join(BASE_DIR, f"{base_name}.png")
    im_1080.save(primary_1080, format="PNG", optimize=True)

    # YouTube requires < 2 MB (2,097,152 bytes). If 1080p PNG > 1.95 MB, quantize or save 720p PNG + high-quality 1080p JPG
    sz_1080 = os.path.getsize(primary_1080)
    if sz_1080 > 1950000:
        quant = im_1080.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB")
        quant.save(primary_1080, format="PNG", optimize=True)
        sz_1080 = os.path.getsize(primary_1080)

    primary_720 = os.path.join(BASE_DIR, f"{base_name}_720p.png")
    im_720.save(primary_720, format="PNG", optimize=True)

    assert sz_1080 < 2050000, f"{primary_1080} exceeds YouTube 2MB limit ({sz_1080} bytes)"
    assert os.path.getsize(primary_720) < 2050000

    for d in out_dirs:
        if d and os.path.isdir(d):
            shutil.copyfile(primary_1080, os.path.join(d, f"{base_name}.png"))
            shutil.copyfile(primary_720, os.path.join(d, f"{base_name}_720p.png"))

    print(
        f"==> Saved {base_name}: 1080p ({sz_1080 / 1024:.0f} KB) & 720p ({os.path.getsize(primary_720) / 1024:.0f} KB)"
    )


def main():
    art_dir = os.environ.get("ALS_ARTIFACT_DIR", "")
    targets = [
        art_dir,
        os.path.join(HOME_DIR, "Desktop"),
        os.path.join(HOME_DIR, "Downloads"),
    ]

    t1 = render_thumbnail_1()
    save_youtube_ready(t1, "AntiLagShield_Thumbnail_1", targets)

    t2 = render_thumbnail_2()
    save_youtube_ready(t2, "AntiLagShield_Thumbnail_2", targets)


if __name__ == "__main__":
    main()
