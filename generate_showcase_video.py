#!/usr/bin/env python3
"""Renders the 1080p 30fps Anti-Lag Shield v1.0.0 showcase video with strict bounds verification."""

import json
import math
import os
import subprocess
import sys
import time
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

WIDTH = 1920
HEIGHT = 1080
FPS = 30
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
HOME_DIR = os.path.expanduser("~")
OUTPUT_RAW = "/tmp/showcase_raw.mp4"
SCENE_PLAN_JSON = "/tmp/als_scene_plan.json"
FINAL_VIDEO = os.path.join(BASE_DIR, "AntiLagShield_Showcase.mp4")

MARGIN_X = 96
MAX_CONTENT_W = WIDTH - (MARGIN_X * 2)  # 1728 px

FONT_SANS = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"

# HelveticaNeue.ttc indices: 0=Regular, 1=Bold, 10=Medium
# Menlo.ttc indices: 0=Regular, 1=Bold
_FONT_CACHE = {}


def load_font(ttc_path, size, index=0):
    key = (ttc_path, size, index)
    if key not in _FONT_CACHE:
        try:
            _FONT_CACHE[key] = ImageFont.truetype(ttc_path, size, index=index)
        except Exception:
            _FONT_CACHE[key] = ImageFont.load_default()
    return _FONT_CACHE[key]


def sans_bold(size):
    return load_font(FONT_SANS, size, index=1)


def sans_med(size):
    return load_font(FONT_SANS, size, index=10)


def sans_reg(size):
    return load_font(FONT_SANS, size, index=0)


def mono_bold(size):
    return load_font(FONT_MONO, size, index=1)


def mono_reg(size):
    return load_font(FONT_MONO, size, index=0)


BG_COLOR = (10, 13, 20)
CARD_BG = (17, 22, 33)
INNER_BG = (12, 16, 25)
CARD_BORDER = (36, 49, 72)
CYAN = (0, 210, 245)
GREEN = (48, 209, 88)
PURPLE = (182, 102, 235)
AMBER = (255, 196, 46)
RED = (255, 78, 68)
WHITE = (248, 250, 252)
GRAY = (164, 174, 190)
MUTED = (108, 120, 138)


def load_asset_image(env_key, filename):
    path = os.environ.get(env_key, os.path.join(BASE_DIR, "assets", filename))
    if os.path.exists(path):
        return Image.open(path).convert("RGB")
    return None


IM_TOP = load_asset_image("ALS_LIVE_TOP", "Screenshot_1_Live_Telemetry.png")
IM_BOTTOM = load_asset_image("ALS_LIVE_BOTTOM", "Screenshot_4_Network_and_Gamepads.png")
IM_BANNER = load_asset_image("ALS_LIVE_BANNER", "Notification_Center_Banner.png")


def text_metrics(font, text):
    bbox = font.getbbox(text)
    return bbox[2] - bbox[0], bbox[3] - bbox[1], bbox[0], bbox[1]


def fit_font(text, builder_fn, max_size, max_width, min_size=11):
    for sz in range(max_size, min_size - 1, -1):
        f = builder_fn(sz)
        w, _, _, _ = text_metrics(f, text)
        if w <= max_width:
            return f
    f = builder_fn(min_size)
    w, _, _, _ = text_metrics(f, text)
    assert w <= max_width + 2, f"Text '{text}' ({w}px) exceeds box width ({max_width}px)"
    return f


def draw_text_in_box(draw, text, builder_fn, max_size, fill, box, align="left", valign="top"):
    x0, y0, x1, y1 = box
    avail_w = x1 - x0
    avail_h = y1 - y0
    assert avail_w > 4 and avail_h > 4, f"Invalid box {box} for '{text}'"

    font = fit_font(text, builder_fn, max_size, avail_w)
    w, h, bx0, by0 = text_metrics(font, text)
    assert w <= avail_w + 2, f"Horizontal overflow for '{text}': {w} > {avail_w}"
    assert h <= avail_h + 4, f"Vertical overflow for '{text}': {h} > {avail_h}"

    if align == "center":
        tx = x0 + (avail_w - w) // 2 - bx0
    elif align == "right":
        tx = x1 - w - bx0
    else:
        tx = x0 - bx0

    if valign == "center":
        ty = y0 + (avail_h - h) // 2 - by0
    else:
        ty = y0 - by0

    draw.text((tx, ty), text, font=font, fill=fill)
    return ty + by0 + h


def wrap_lines(text, font, max_width):
    out = []
    for para in text.split("\n"):
        words = para.split(" ")
        cur = []
        for word in words:
            cand = " ".join(cur + [word]) if cur else word
            w, _, _, _ = text_metrics(font, cand)
            if w <= max_width:
                cur.append(word)
            else:
                if cur:
                    out.append(" ".join(cur))
                    cur = [word]
                else:
                    out.append(word)
        if cur:
            out.append(" ".join(cur))
    return out


def draw_wrapped_in_box(draw, text, builder_fn, pref_size, fill, box, line_gap=6):
    x0, y0, x1, y1 = box
    avail_w = x1 - x0
    avail_h = y1 - y0

    chosen_font = None
    chosen_lines = None
    chosen_lh = 0

    for sz in range(pref_size, 11, -1):
        f = builder_fn(sz)
        lines = wrap_lines(text, f, avail_w)
        _, lh, _, _ = text_metrics(f, "Ay")
        total_h = len(lines) * lh + max(0, len(lines) - 1) * line_gap
        max_lw = max((text_metrics(f, ln)[0] for ln in lines), default=0)
        if total_h <= avail_h and max_lw <= avail_w:
            chosen_font = f
            chosen_lines = lines
            chosen_lh = lh
            break

    assert chosen_font is not None, f"Wrapped text overflowed box {box}: '{text}'"

    cy = y0
    for ln in chosen_lines:
        _, _, bx0, by0 = text_metrics(chosen_font, ln)
        draw.text((x0 - bx0, cy - by0), ln, font=chosen_font, fill=fill)
        cy += chosen_lh + line_gap
    return cy - line_gap


def draw_card(draw, box, fill=CARD_BG, outline=CARD_BORDER, radius=18, width=2):
    draw.rounded_rectangle(list(box), radius=radius, fill=fill, outline=outline, width=width)


def draw_status_dot(draw, cx, cy, r, color):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def draw_shield_mark(draw, cx, cy, size, color, fill_bg=(14, 34, 48)):
    half_w = size * 0.46
    top_y = cy - size * 0.50
    mid_y = cy + size * 0.06
    bot_y = cy + size * 0.52
    pts = [
        (cx, top_y),
        (cx + half_w, top_y + size * 0.16),
        (cx + half_w * 0.88, mid_y),
        (cx, bot_y),
        (cx - half_w * 0.88, mid_y),
        (cx - half_w, top_y + size * 0.16),
    ]
    draw.polygon(pts, fill=fill_bg, outline=color)
    bolt = [
        (cx + size * 0.05, cy - size * 0.24),
        (cx - size * 0.14, cy + size * 0.02),
        (cx + size * 0.01, cy + size * 0.02),
        (cx - size * 0.06, cy + size * 0.25),
        (cx + size * 0.15, cy - size * 0.03),
        (cx + size * 0.00, cy - size * 0.03),
    ]
    draw.polygon(bolt, fill=color)


def create_base_frame(t, scene_idx, total_scenes, global_progress):
    img = Image.new("RGB", (WIDTH, HEIGHT), BG_COLOR)
    draw = ImageDraw.Draw(img)

    grid_spacing = 80
    pulse = int(6 + 3 * math.sin(t * 1.4))
    grid_col = (14 + pulse, 19 + pulse, 30 + pulse)
    for x in range(0, WIDTH, grid_spacing):
        draw.line([(x, 0), (x, HEIGHT)], fill=grid_col, width=1)
    for y in range(0, HEIGHT, grid_spacing):
        draw.line([(0, y), (WIDTH, y)], fill=grid_col, width=1)

    draw.rectangle([0, 0, WIDTH, 3], fill=CYAN)

    # Bottom footer bar with scene indicator & progress bar
    footer_y = 1018
    draw.line([(MARGIN_X, footer_y), (WIDTH - MARGIN_X, footer_y)], fill=(26, 36, 52), width=1)
    draw_text_in_box(
        draw,
        f"ANTI-LAG SHIELD v1.0.0  •  SCENE {scene_idx} OF {total_scenes}",
        mono_reg,
        14,
        MUTED,
        (MARGIN_X, footer_y + 16, MARGIN_X + 520, footer_y + 38),
        align="left",
        valign="center",
    )
    draw_text_in_box(
        draw,
        "NightKnight24  •  github.com/NightKnight24/AntiLagShield",
        mono_reg,
        14,
        MUTED,
        (WIDTH - MARGIN_X - 560, footer_y + 16, WIDTH - MARGIN_X, footer_y + 38),
        align="right",
        valign="center",
    )

    bar_x0 = MARGIN_X + 560
    bar_x1 = WIDTH - MARGIN_X - 590
    bar_y0 = footer_y + 24
    bar_y1 = footer_y + 30
    draw.rounded_rectangle([bar_x0, bar_y0, bar_x1, bar_y1], radius=3, fill=(24, 32, 46))
    fill_w = max(6, int((bar_x1 - bar_x0) * max(0.0, min(1.0, global_progress))))
    draw.rounded_rectangle([bar_x0, bar_y0, bar_x0 + fill_w, bar_y1], radius=3, fill=CYAN)

    return img, draw


def render_ipad_bezel(raw_img, w, h):
    ipad = Image.new("RGB", (w, h), BG_COLOR)
    d = ImageDraw.Draw(ipad)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=24, fill=(20, 25, 35), outline=(62, 78, 104), width=2)

    pad = 16
    sw = w - pad * 2
    sh = h - pad * 2

    if raw_img is not None:
        src_w, src_h = raw_img.size
        scale = min(sw / float(src_w), sh / float(src_h))
        nw = max(1, int(round(src_w * scale)))
        nh = max(1, int(round(src_h * scale)))
        resized = raw_img.resize((nw, nh), Image.Resampling.LANCZOS)
        d.rounded_rectangle([pad, pad, pad + sw, pad + sh], radius=12, fill=(10, 13, 20))
        ox = pad + (sw - nw) // 2
        oy = pad + (sh - nh) // 2
        ipad.paste(resized, (ox, oy))
    else:
        d.rounded_rectangle([pad, pad, pad + sw, pad + sh], radius=12, fill=(10, 13, 20))

    d.ellipse([w // 2 - 4, 5, w // 2 + 4, 13], fill=(9, 11, 16))
    return ipad


def render_scene_header(draw, kicker, title, subtitle, accent=CYAN):
    draw_text_in_box(
        draw,
        kicker,
        mono_bold,
        15,
        accent,
        (MARGIN_X, 52, WIDTH - MARGIN_X, 74),
        align="left",
        valign="center",
    )
    draw_text_in_box(
        draw,
        title,
        sans_bold,
        42,
        WHITE,
        (MARGIN_X, 80, WIDTH - MARGIN_X, 132),
        align="left",
        valign="center",
    )
    draw_text_in_box(
        draw,
        subtitle,
        sans_reg,
        21,
        GRAY,
        (MARGIN_X, 138, WIDTH - MARGIN_X, 168),
        align="left",
        valign="center",
    )


# ==============================================================================
# SCENE 1: HERO INTRO
# ==============================================================================
def render_scene_1(frame_idx, _total_frames, global_prog):
    t = frame_idx / FPS
    img, draw = create_base_frame(t, 1, 7, global_prog)

    # Top release pill
    pill_w, pill_h = 430, 42
    px0 = (WIDTH - pill_w) // 2
    py0 = 92
    draw_card(draw, (px0, py0, px0 + pill_w, py0 + pill_h), fill=(14, 38, 28), outline=GREEN, radius=21, width=2)
    draw_status_dot(draw, px0 + 28, py0 + pill_h // 2, 6, GREEN)
    draw_text_in_box(
        draw,
        "OFFICIAL OPEN-SOURCE RELEASE  •  v1.0.0",
        sans_bold,
        16,
        GREEN,
        (px0 + 44, py0 + 4, px0 + pill_w - 20, py0 + pill_h - 4),
        align="center",
        valign="center",
    )

    draw_shield_mark(draw, WIDTH // 2, 198, 72, CYAN)

    draw_text_in_box(
        draw,
        "ANTI-LAG SHIELD",
        sans_bold,
        74,
        WHITE,
        (MARGIN_X, 250, WIDTH - MARGIN_X, 340),
        align="center",
        valign="center",
    )

    draw.rounded_rectangle([WIDTH // 2 - 280, 352, WIDTH // 2 + 280, 356], radius=2, fill=CYAN)

    draw_text_in_box(
        draw,
        "Passive XNU Socket Buffer, Delayed-ACK & Radio Coexistence Controller",
        sans_med,
        28,
        CYAN,
        (MARGIN_X, 374, WIDTH - MARGIN_X, 416),
        align="center",
        valign="center",
    )
    draw_text_in_box(
        draw,
        "Built for 64-Bit iPadOS & iOS Devices (iOS 12.0 – 18.x  •  Rootless & Rootful)",
        sans_reg,
        21,
        GRAY,
        (MARGIN_X, 422, WIDTH - MARGIN_X, 454),
        align="center",
        valign="center",
    )

    pillars = [
        ("0.0% IDLE CPU", "One-shot SUID helper mutates XNU sysctls and exits in <25 ms", GREEN),
        ("3 KERNEL PROFILES", "Dedicated Streaming, Gaming, and Normal stock XNU modes", CYAN),
        ("NOTIFICATION BANNER", "Pinned 1-tap switcher + Clear RAM & Clear Cache buttons", AMBER),
        ("PRIVACY LOCKED", "Zero telemetry, zero cloud servers, local gateway ARP lock", PURPLE),
    ]
    gap = 24
    cw = (MAX_CONTENT_W - 3 * gap) // 4
    cy0, cy1 = 496, 696
    for idx, (head, desc, col) in enumerate(pillars):
        cx0 = MARGIN_X + idx * (cw + gap)
        cx1 = cx0 + cw
        draw_card(draw, (cx0, cy0, cx1, cy1), fill=CARD_BG, outline=col, radius=18, width=2)
        draw.rounded_rectangle([cx0 + 24, cy0 + 24, cx0 + 68, cy0 + 30], radius=3, fill=col)
        draw_text_in_box(
            draw,
            head,
            sans_bold,
            21,
            WHITE,
            (cx0 + 24, cy0 + 44, cx1 - 24, cy0 + 78),
            align="left",
            valign="center",
        )
        draw_wrapped_in_box(
            draw,
            desc,
            sans_reg,
            18,
            GRAY,
            (cx0 + 24, cy0 + 88, cx1 - 24, cy1 - 22),
            line_gap=6,
        )

    # Privacy & verification banner
    b_y0, b_y1 = 742, 956
    draw_card(draw, (MARGIN_X, b_y0, WIDTH - MARGIN_X, b_y1), fill=(14, 22, 34), outline=CARD_BORDER, radius=20, width=2)
    draw_text_in_box(
        draw,
        "VERIFIED ON REAL HARDWARE  •  100% ON-DEVICE PRIVACY",
        sans_bold,
        22,
        CYAN,
        (MARGIN_X + 36, b_y0 + 26, WIDTH - MARGIN_X - 36, b_y0 + 60),
        align="center",
        valign="center",
    )
    draw_wrapped_in_box(
        draw,
        "Captured live on iPad (iPadOS 17.7.11, arm64). Every kernel parameter shown in the app is read directly via "
        "sysctlbyname(), host_statistics64(), and getifaddrs() with zero hardcoded metrics — and all private LAN IP "
        "and router MAC addresses are masked in this showcase.",
        sans_reg,
        19,
        WHITE,
        (MARGIN_X + 80, b_y0 + 74, WIDTH - MARGIN_X - 80, b_y1 - 24),
        line_gap=7,
    )

    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


# ==============================================================================
# SCENE 2: PASSIVE KERNEL ARCHITECTURE
# ==============================================================================
def render_scene_2(frame_idx, _total_frames, global_prog):
    t = frame_idx / FPS
    img, draw = create_base_frame(t, 2, 7, global_prog)

    render_scene_header(
        draw,
        "KERNEL ARCHITECTURE",
        "Passive XNU Tuning vs. Background Polling Daemons",
        "Why persistent daemon tweaks drain battery and trigger Jetsam kills — and how Anti-Lag Shield avoids both:",
        accent=CYAN,
    )

    col_w = (MAX_CONTENT_W - 36) // 2
    lx0, lx1 = MARGIN_X, MARGIN_X + col_w
    rx0, rx1 = lx1 + 36, WIDTH - MARGIN_X
    cy0, cy1 = 192, 976

    # Left card
    draw_card(draw, (lx0, cy0, lx1, cy1), fill=CARD_BG, outline=RED, radius=20, width=2)
    draw_card(draw, (lx0 + 28, cy0 + 24, lx1 - 28, cy0 + 76), fill=(42, 16, 20), outline=RED, radius=12, width=1)
    draw_text_in_box(
        draw,
        "TRADITIONAL POLLING TWEAKS",
        sans_bold,
        22,
        RED,
        (lx0 + 44, cy0 + 28, lx1 - 44, cy0 + 72),
        align="center",
        valign="center",
    )

    left_rows = [
        ("Always-On Background Daemons", "Spawn persistent launchd loops that poll network interfaces and process lists every few seconds."),
        ("Continuous CPU & Thermal Wakeups", "Prevents A-series and M-series cores from holding deep idle states during video playback or standby."),
        ("Extra Jetsam Memory Pressure", "Resident background daemons consume 15–40 MB of wired/dirty pages on RAM-constrained iPads."),
        ("SpringBoard Hook Instability", "Heavy UI timers inside SpringBoard cause scroll hitching and unexpected resprings."),
    ]
    ry = cy0 + 102
    for title, desc in left_rows:
        draw_card(draw, (lx0 + 28, ry, lx1 - 28, ry + 152), fill=INNER_BG, outline=(52, 32, 38), radius=14, width=1)
        draw_status_dot(draw, lx0 + 50, ry + 30, 6, RED)
        draw_text_in_box(
            draw,
            title,
            sans_bold,
            21,
            AMBER,
            (lx0 + 68, ry + 14, lx1 - 46, ry + 46),
            align="left",
            valign="center",
        )
        draw_wrapped_in_box(
            draw,
            desc,
            sans_reg,
            18,
            GRAY,
            (lx0 + 48, ry + 54, lx1 - 48, ry + 140),
            line_gap=5,
        )
        ry += 168

    # Right card
    draw_card(draw, (rx0, cy0, rx1, cy1), fill=CARD_BG, outline=GREEN, radius=20, width=2)
    draw_card(draw, (rx0 + 28, cy0 + 24, rx1 - 28, cy0 + 76), fill=(14, 40, 26), outline=GREEN, radius=12, width=1)
    draw_text_in_box(
        draw,
        "ANTI-LAG SHIELD  •  PASSIVE XNU ENGINE",
        sans_bold,
        22,
        GREEN,
        (rx0 + 44, cy0 + 28, rx1 - 44, cy0 + 72),
        align="center",
        valign="center",
    )

    right_rows = [
        ("One-Shot SUID Kernel Helper (shield_ctl)", "Writes TCP socket buffers, delayed_ack, tso, and blackhole sysctls into Darwin kernel state, then exits."),
        ("0.0% Persistent CPU & 0 MB Daemon RAM", "No background polling loop runs while you watch 4K streams or play games — the XNU stack enforces rules natively."),
        ("Eliminates AirDrop Scan Micro-Stutter", "Temporarily pauses awdl0 periodic peer discovery during Streaming or Gaming and restores it cleanly in Normal mode."),
        ("Instant Multi-Surface Sync", "Uses lightweight Darwin notify_post() events so the App, Control Center, and Notification Banner stay in lockstep."),
    ]
    ry = cy0 + 102
    for title, desc in right_rows:
        draw_card(draw, (rx0 + 28, ry, rx1 - 28, ry + 152), fill=INNER_BG, outline=(28, 58, 42), radius=14, width=1)
        draw_status_dot(draw, rx0 + 50, ry + 30, 6, GREEN)
        draw_text_in_box(
            draw,
            title,
            sans_bold,
            21,
            GREEN,
            (rx0 + 68, ry + 14, rx1 - 46, ry + 46),
            align="left",
            valign="center",
        )
        draw_wrapped_in_box(
            draw,
            desc,
            sans_reg,
            18,
            WHITE,
            (rx0 + 48, ry + 54, rx1 - 48, ry + 140),
            line_gap=5,
        )
        ry += 168

    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


# ==============================================================================
# SCENE 3: LIVE IPAD APP TOP VIEW
# ==============================================================================
def render_scene_3(frame_idx, _total_frames, global_prog):
    t = frame_idx / FPS
    img, draw = create_base_frame(t, 3, 7, global_prog)

    render_scene_header(
        draw,
        "LIVE HARDWARE CAPTURE  •  APP DASHBOARD",
        "Updated Native App: Streaming, Gaming & Normal Profiles",
        "Captured at @2x Retina resolution directly from iPadOS 17.7.11 — real kernel telemetry, zero mockups:",
        accent=CYAN,
    )

    left_w = 960
    lx0 = MARGIN_X
    rx0 = lx0 + left_w + 32
    rx1 = WIDTH - MARGIN_X
    cy0, cy1 = 192, 976

    ipad_img = render_ipad_bezel(IM_TOP, left_w, cy1 - cy0)
    img.paste(ipad_img, (lx0, cy0))

    draw_card(draw, (rx0, cy0, rx1, cy1), fill=CARD_BG, outline=CYAN, radius=20, width=2)
    draw_text_in_box(
        draw,
        "LIVE TELEMETRY & 1-TAP CONTROLS",
        sans_bold,
        24,
        CYAN,
        (rx0 + 28, cy0 + 24, rx1 - 28, cy0 + 58),
        align="left",
        valign="center",
    )

    # Metrics box
    m_y0, m_y1 = cy0 + 72, cy0 + 244
    draw_card(draw, (rx0 + 28, m_y0, rx1 - 28, m_y1), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
    draw_text_in_box(
        draw,
        "REAL-TIME HARDWARE READOUTS:",
        mono_bold,
        15,
        GRAY,
        (rx0 + 46, m_y0 + 16, rx1 - 46, m_y0 + 40),
    )
    metrics = [
        ("• Gateway / 1.1.1.1 RTT:  4.7 ms  /  15.7 ms", GREEN),
        ("• Streaming Auto-Buffer:  4.0 MB Max (512 KB Init)", CYAN),
        ("• Gaming Mode ACK / TSO:  delayed_ack=0, tso=0", AMBER),
        ("• Normal Mode Restore:    Stock XNU & awdl0 Up", WHITE),
    ]
    my = m_y0 + 48
    for line, col in metrics:
        draw_text_in_box(draw, line, mono_reg, 15, col, (rx0 + 46, my, rx1 - 46, my + 26), valign="center")
        my += 29

    # Feature breakdown cards
    feats = [
        (
            "3-Way Segmented Profile Switcher",
            "Switch cleanly between 4 MB buffer Streaming mode, 0 ms Immediate-ACK Gaming mode, and stock iOS Normal mode.",
            GREEN,
        ),
        (
            "Turbo UI Compositor Toggle",
            "Disables SpringBoard blur shaders and motion animations on demand to free GPU fill-rate on older iPads.",
            CYAN,
        ),
        (
            "Memorystatus Warning Guard",
            "Sets kern.memorystatus_purge_on_warning = 0 so XNU stops flushing cached video/game assets prematurely.",
            AMBER,
        ),
    ]
    fy = m_y1 + 22
    for title, desc, col in feats:
        draw_card(draw, (rx0 + 28, fy, rx1 - 28, fy + 154), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
        draw_status_dot(draw, rx0 + 48, fy + 30, 6, col)
        draw_text_in_box(
            draw,
            title,
            sans_bold,
            20,
            col,
            (rx0 + 66, fy + 14, rx1 - 44, fy + 44),
            valign="center",
        )
        draw_wrapped_in_box(
            draw,
            desc,
            sans_reg,
            17,
            WHITE,
            (rx0 + 46, fy + 52, rx1 - 46, fy + 142),
            line_gap=5,
        )
        fy += 170

    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


# ==============================================================================
# SCENE 4: PERSISTENT NOTIFICATION BAR BANNER + CC + SHORTCUTS
# ==============================================================================
def render_scene_4(frame_idx, _total_frames, global_prog):
    t = frame_idx / FPS
    img, draw = create_base_frame(t, 4, 7, global_prog)

    render_scene_header(
        draw,
        "INSTANT SYSTEM-WIDE ACCESS",
        "New Persistent Notification Bar Banner, Control Center & Shortcuts",
        "Switch modes or clear RAM and caches from inside any full-screen app or game without leaving what you are doing:",
        accent=GREEN,
    )

    # Top hero showcase for the REAL live SpringBoard Notification Banner capture
    top_y0, top_y1 = 190, 526
    draw_card(draw, (MARGIN_X, top_y0, WIDTH - MARGIN_X, top_y1), fill=CARD_BG, outline=GREEN, radius=20, width=2)

    # Left side inside top card: Live SpringBoard Banner PNG
    ban_box_x0 = MARGIN_X + 32
    ban_box_y0 = top_y0 + 30
    ban_box_w = 860
    ban_box_h = top_y1 - top_y0 - 60
    draw_card(
        draw,
        (ban_box_x0, ban_box_y0, ban_box_x0 + ban_box_w, ban_box_y0 + ban_box_h),
        fill=(11, 15, 23),
        outline=(42, 62, 88),
        radius=18,
        width=1,
    )
    draw_text_in_box(
        draw,
        "LIVE SPRINGBOARD CAPTURE  •  PULL-DOWN NOTIFICATION CENTER",
        mono_bold,
        14,
        GREEN,
        (ban_box_x0 + 24, ban_box_y0 + 14, ban_box_x0 + ban_box_w - 24, ban_box_y0 + 38),
        align="center",
        valign="center",
    )
    if IM_BANNER is not None:
        target_w = 790
        target_h = int(round(target_w * (IM_BANNER.size[1] / float(IM_BANNER.size[0]))))
        max_h = ban_box_h - 62
        if target_h > max_h:
            target_h = max_h
            target_w = int(round(target_h * (IM_BANNER.size[0] / float(IM_BANNER.size[1]))))
        ban_scaled = IM_BANNER.resize((target_w, target_h), Image.Resampling.LANCZOS)
        bx = ban_box_x0 + (ban_box_w - target_w) // 2
        by = ban_box_y0 + 46 + (max_h - target_h) // 2
        img.paste(ban_scaled, (bx, by))

    # Right side inside top card: Explanation of the 5 Notification Banner buttons
    info_x0 = ban_box_x0 + ban_box_w + 36
    info_x1 = WIDTH - MARGIN_X - 32
    draw_text_in_box(
        draw,
        "NEW: PERSISTENT NOTIFICATION BAR BANNER",
        sans_bold,
        25,
        GREEN,
        (info_x0, top_y0 + 30, info_x1, top_y0 + 66),
        valign="center",
    )
    draw_wrapped_in_box(
        draw,
        "Pinned right at the top of Notification Center (CoverSheet) via AntiLagShieldBanner.dylib — swipe down from the top bar at any time for 5 native controls:",
        sans_reg,
        18,
        WHITE,
        (info_x0, top_y0 + 76, info_x1, top_y0 + 148),
        line_gap=5,
    )
    banner_pts = [
        ("• Streaming / Gaming / Normal:  1-tap live XNU profile switching", CYAN),
        ("• Clear RAM Button:  Purges inactive pages & shows +MB freed live", GREEN),
        ("• Clear Cache Button:  Sweeps diagnostic logs & expired caches", AMBER),
        ("• Can be shown or hidden anytime via the in-app Banner switch", GRAY),
    ]
    bpy = top_y0 + 162
    for txt, col in banner_pts:
        draw_text_in_box(draw, txt, sans_med, 18, col, (info_x0, bpy, info_x1, bpy + 30), valign="center")
        bpy += 36

    # Bottom two cards: Control Center Module & Siri Shortcuts / URL Schemes
    bot_y0, bot_y1 = 554, 976
    half_w = (MAX_CONTENT_W - 32) // 2
    c1_x0, c1_x1 = MARGIN_X, MARGIN_X + half_w
    c2_x0, c2_x1 = c1_x1 + 32, WIDTH - MARGIN_X

    # Card 1: Control Center
    draw_card(draw, (c1_x0, bot_y0, c1_x1, bot_y1), fill=CARD_BG, outline=CYAN, radius=20, width=2)
    draw_text_in_box(
        draw,
        "CONTROL CENTER MODULE  (CCSupport)",
        sans_bold,
        23,
        CYAN,
        (c1_x0 + 28, bot_y0 + 24, c1_x1 - 28, bot_y0 + 58),
        valign="center",
    )
    draw_card(draw, (c1_x0 + 28, bot_y0 + 74, c1_x1 - 28, bot_y0 + 184), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
    draw.rounded_rectangle([c1_x0 + 48, bot_y0 + 94, c1_x0 + 118, bot_y0 + 164], radius=16, fill=(0, 148, 200))
    draw_shield_mark(draw, c1_x0 + 83, bot_y0 + 129, 44, WHITE, fill_bg=(0, 110, 160))
    draw_text_in_box(
        draw,
        "AntiLagShieldCC.bundle",
        sans_bold,
        21,
        WHITE,
        (c1_x0 + 140, bot_y0 + 98, c1_x1 - 46, bot_y0 + 130),
        valign="center",
    )
    draw_text_in_box(
        draw,
        "Tap to toggle  •  Synced via Darwin notifications",
        sans_reg,
        17,
        GREEN,
        (c1_x0 + 140, bot_y0 + 132, c1_x1 - 46, bot_y0 + 162),
        valign="center",
    )
    draw_wrapped_in_box(
        draw,
        "• Installed into /var/jb/Library/ControlCenter/Bundles/ for 1-swipe toggling.\n"
        "• Automatically updates its highlight state whenever you switch modes from the Notification Banner, App, or CLI.",
        sans_reg,
        18,
        GRAY,
        (c1_x0 + 28, bot_y0 + 206, c1_x1 - 28, bot_y1 - 24),
        line_gap=8,
    )

    # Card 2: Siri Shortcuts & URL Schemes
    draw_card(draw, (c2_x0, bot_y0, c2_x1, bot_y1), fill=CARD_BG, outline=PURPLE, radius=20, width=2)
    draw_text_in_box(
        draw,
        "SIRI SHORTCUTS & AUTOMATION URLS",
        sans_bold,
        23,
        PURPLE,
        (c2_x0 + 28, bot_y0 + 24, c2_x1 - 28, bot_y0 + 58),
        valign="center",
    )
    draw_card(draw, (c2_x0 + 28, bot_y0 + 74, c2_x1 - 28, bot_y0 + 184), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
    urls = [
        ("shield://streaming   ->  4 MB Buffer + Adaptive ACK", CYAN),
        ("shield://gaming      ->  0 ms ACK + Low-Jitter TCP", GREEN),
        ("shield://normal      ->  Restores Stock XNU Stack", WHITE),
    ]
    uy = bot_y0 + 88
    for u_txt, col in urls:
        draw_text_in_box(draw, u_txt, mono_reg, 15, col, (c2_x0 + 46, uy, c2_x1 - 46, uy + 26), valign="center")
        uy += 30

    draw_wrapped_in_box(
        draw,
        "• Trigger profiles automatically in Apple Shortcuts when opening YouTube, Stremio, Netflix, Roblox, or Moonlight.\n"
        "• Supports hands-free Siri voice activation and Home Screen bookmark icons.",
        sans_reg,
        18,
        GRAY,
        (c2_x0 + 28, bot_y0 + 206, c2_x1 - 28, bot_y1 - 24),
        line_gap=8,
    )

    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


# ==============================================================================
# SCENE 5: SCROLLED APP VIEW — KERNEL SYSCTLS, ARP LOCK & BANNER SWITCH
# ==============================================================================
def render_scene_5(frame_idx, _total_frames, global_prog):
    t = frame_idx / FPS
    img, draw = create_base_frame(t, 5, 7, global_prog)

    render_scene_header(
        draw,
        "LIVE KERNEL STATE & PRIVACY",
        "Static Gateway ARP Lock, Radio Coexistence & App Controls",
        "Scrolled view of Anti-Lag Shield showing all 7 live XNU sysctl rows, scheduler policy, and Banner / Boot switches:",
        accent=AMBER,
    )

    left_w = 960
    lx0 = MARGIN_X
    rx0 = lx0 + left_w + 32
    rx1 = WIDTH - MARGIN_X
    cy0, cy1 = 192, 976

    ipad_img = render_ipad_bezel(IM_BOTTOM, left_w, cy1 - cy0)
    img.paste(ipad_img, (lx0, cy0))

    draw_card(draw, (rx0, cy0, rx1, cy1), fill=CARD_BG, outline=AMBER, radius=20, width=2)
    draw_text_in_box(
        draw,
        "UNDER-THE-HOOD XNU PROTECTIONS",
        sans_bold,
        24,
        AMBER,
        (rx0 + 28, cy0 + 24, rx1 - 28, cy0 + 58),
        valign="center",
    )

    arp_y0, arp_y1 = cy0 + 72, cy0 + 244
    draw_card(draw, (rx0 + 28, arp_y0, rx1 - 28, arp_y1), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
    draw_text_in_box(
        draw,
        "PRIVACY-MASKED GATEWAY BINDING (en0):",
        mono_bold,
        15,
        GRAY,
        (rx0 + 46, arp_y0 + 16, rx1 - 46, arp_y0 + 40),
    )
    arp_lines = [
        ("• Gateway IPv4:  192.168.X.X  [MASKED ON VIDEO]", GREEN),
        ("• Router MAC:    ••:••:••:••:••:••  [LOCAL ONLY]", GREEN),
        ("• Radio State:   awdl0 Paused (Zero Scan Stutter)", CYAN),
        ("• TCP Stack:     somaxconn=512, blackhole=2", AMBER),
    ]
    ay = arp_y0 + 48
    for ln, col in arp_lines:
        draw_text_in_box(draw, ln, mono_reg, 15, col, (rx0 + 46, ay, rx1 - 46, ay + 26), valign="center")
        ay += 29

    cards = [
        (
            "Fixes Streaming & AirPlay Stutter (awdl0)",
            "Pauses periodic Apple Wireless Direct Link channel-hopping scans that cause 50–120 ms Wi-Fi stalls on iPad.",
            GREEN,
        ),
        (
            "Static Router ARP + Process Nice (-10)",
            "Locks your gateway MAC in the kernel ARP table and elevates media/game daemons (mediaserverd, WebKit, Roblox) to -10.",
            CYAN,
        ),
        (
            "In-App Banner & Boot LaunchDaemon Switches",
            "Toggle the Notification Center Banner or optional one-shot boot persistence directly from the bottom settings card.",
            AMBER,
        ),
    ]
    ky = arp_y1 + 22
    for title, desc, col in cards:
        draw_card(draw, (rx0 + 28, ky, rx1 - 28, ky + 154), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
        draw_status_dot(draw, rx0 + 48, ky + 30, 6, col)
        draw_text_in_box(
            draw,
            title,
            sans_bold,
            20,
            col,
            (rx0 + 66, ky + 14, rx1 - 44, ky + 44),
            valign="center",
        )
        draw_wrapped_in_box(
            draw,
            desc,
            sans_reg,
            17,
            WHITE,
            (rx0 + 46, ky + 52, rx1 - 46, ky + 142),
            line_gap=5,
        )
        ky += 170

    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


# ==============================================================================
# SCENE 6: CLEAR RAM & CLEAR CACHE MAINTENANCE
# ==============================================================================
def render_scene_6(frame_idx, _total_frames, global_prog):
    t = frame_idx / FPS
    img, draw = create_base_frame(t, 6, 7, global_prog)

    render_scene_header(
        draw,
        "MEMORY & STORAGE HYGIENE",
        "Safe XNU Inactive RAM Purge & Diagnostic Cache Cleaner",
        "Available in both the main app and the pull-down Notification Bar Banner with instant live feedback:",
        accent=AMBER,
    )

    col_w = (MAX_CONTENT_W - 36) // 2
    lx0, lx1 = MARGIN_X, MARGIN_X + col_w
    rx0, rx1 = lx1 + 36, WIDTH - MARGIN_X
    cy0, cy1 = 192, 976

    # Left card: Clear RAM
    draw_card(draw, (lx0, cy0, lx1, cy1), fill=CARD_BG, outline=AMBER, radius=20, width=2)
    draw_text_in_box(
        draw,
        "CLEAR RAM  •  INACTIVE PAGE PURGE",
        sans_bold,
        24,
        AMBER,
        (lx0 + 32, cy0 + 26, lx1 - 32, cy0 + 62),
        valign="center",
    )
    draw_card(draw, (lx0 + 32, cy0 + 78, lx1 - 32, cy0 + 220), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
    draw_text_in_box(
        draw,
        "LIVE VERIFIED BENCHMARK ON IPAD 6TH GEN (2 GB RAM):",
        mono_bold,
        15,
        GRAY,
        (lx0 + 50, cy0 + 94, lx1 - 50, cy0 + 118),
    )
    draw_text_in_box(
        draw,
        "• Reclaimed Memory:   +607 MB Freed in 1 Tap",
        mono_reg,
        16,
        GREEN,
        (lx0 + 50, cy0 + 128, lx1 - 50, cy0 + 156),
    )
    draw_text_in_box(
        draw,
        "• Jetsam Safety:      0 Foreground Apps Terminated",
        mono_reg,
        16,
        CYAN,
        (lx0 + 50, cy0 + 164, lx1 - 50, cy0 + 192),
    )

    ram_items = [
        ("XNU Kernel Purge Syscall", "Invokes Darwin's native memory purge path via shield_ctl instead of allocating giant dummy arrays that crash apps."),
        ("Eliminates Tab & Stream Reloads", "Reclaims stale file-backed caches before launching heavy 4K streams, emulators, or 3D games."),
        ("Live Delta Reporting", "Measures exact free + speculative VM pages via host_statistics64() before and after every purge."),
    ]
    ry = cy0 + 246
    for title, desc in ram_items:
        draw_card(draw, (lx0 + 32, ry, lx1 - 32, ry + 158), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
        draw_status_dot(draw, lx0 + 52, ry + 32, 6, AMBER)
        draw_text_in_box(draw, title, sans_bold, 21, WHITE, (lx0 + 70, ry + 16, lx1 - 48, ry + 48), valign="center")
        draw_wrapped_in_box(draw, desc, sans_reg, 18, GRAY, (lx0 + 50, ry + 56, lx1 - 50, ry + 146), line_gap=5)
        ry += 174

    # Right card: Clear Cache
    draw_card(draw, (rx0, cy0, rx1, cy1), fill=CARD_BG, outline=GREEN, radius=20, width=2)
    draw_text_in_box(
        draw,
        "CLEAR CACHE  •  SAFE LOG & TEMP TRIMMER",
        sans_bold,
        24,
        GREEN,
        (rx0 + 32, cy0 + 26, rx1 - 32, cy0 + 62),
        valign="center",
    )
    draw_card(draw, (rx0 + 32, cy0 + 78, rx1 - 32, cy0 + 220), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
    draw_text_in_box(
        draw,
        "TARGETED CLEANUP SCOPE (ZERO USER DATA RISK):",
        mono_bold,
        15,
        GRAY,
        (rx0 + 50, cy0 + 94, rx1 - 50, cy0 + 118),
    )
    draw_text_in_box(
        draw,
        "• CrashReporter & DiagnosticReports (.ips / .synced)",
        mono_reg,
        16,
        GREEN,
        (rx0 + 50, cy0 + 128, rx1 - 50, cy0 + 156),
    )
    draw_text_in_box(
        draw,
        "• Expired System Logs & Orphan Temporary Caches",
        mono_reg,
        16,
        CYAN,
        (rx0 + 50, cy0 + 164, rx1 - 50, rx1 - 50 if False else cy0 + 192),
    )

    cache_items = [
        ("Strict Allowlist Directory Scanner", "Only removes verified diagnostic crash logs and expired temporary files — never touches app logins, saves, or photos."),
        ("Exact Byte & File Count Audit", "Reports exact files removed and megabytes freed right on the button and inside the Notification Bar Banner."),
        ("Reduces Flash Storage Clutter", "Keeps /var/mobile/Library/Logs clean so older 16 GB and 32 GB iPads maintain responsive APFS free space."),
    ]
    ry = cy0 + 246
    for title, desc in cache_items:
        draw_card(draw, (rx0 + 32, ry, rx1 - 32, ry + 158), fill=INNER_BG, outline=CARD_BORDER, radius=14, width=1)
        draw_status_dot(draw, rx0 + 52, ry + 32, 6, GREEN)
        draw_text_in_box(draw, title, sans_bold, 21, WHITE, (rx0 + 70, ry + 16, rx1 - 48, ry + 48), valign="center")
        draw_wrapped_in_box(draw, desc, sans_reg, 18, GRAY, (rx0 + 50, ry + 56, rx1 - 50, ry + 146), line_gap=5)
        ry += 174

    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


# ==============================================================================
# SCENE 7: OUTRO & INSTALLATION
# ==============================================================================
def render_scene_7(frame_idx, _total_frames, global_prog):
    t = frame_idx / FPS
    img, draw = create_base_frame(t, 7, 7, global_prog)

    draw_shield_mark(draw, WIDTH // 2, 118, 60, CYAN)
    draw_text_in_box(
        draw,
        "GET ANTI-LAG SHIELD v1.0.0",
        sans_bold,
        62,
        WHITE,
        (MARGIN_X, 162, WIDTH - MARGIN_X, 236),
        align="center",
        valign="center",
    )
    draw_text_in_box(
        draw,
        "100% Free & Open Source  •  App + Control Center + Notification Bar Banner + CLI",
        sans_med,
        24,
        CYAN,
        (MARGIN_X, 244, WIDTH - MARGIN_X, 282),
        align="center",
        valign="center",
    )

    gap = 28
    cw = (MAX_CONTENT_W - 2 * gap) // 3
    c1_x0 = MARGIN_X
    c2_x0 = c1_x0 + cw + gap
    c3_x0 = c2_x0 + cw + gap
    cy0, cy1 = 316, 760

    cards = [
        (
            c1_x0,
            "SILEO & ZEBRA REPO",
            CYAN,
            "Add Official APT Repository:",
            "https://nightknight24.github.io/\nAntiLagShield/repo",
            "One-Tap Package Manager Install:",
            "Search for Anti-Lag Shield in Sileo or Zebra and tap Install — auto-configures permissions and uicache.",
        ),
        (
            c2_x0,
            "1-LINE TERMINAL / .DEB",
            GREEN,
            "SSH or NewTerm Quick Install:",
            "curl -sL https://nightknight24.github.io/\nAntiLagShield/install.sh | bash",
            "Rootless & Rootful Support:",
            "Supports palera1n, Dopamine, checkra1n, unc0ver, and Odyssey across iOS & iPadOS 12.0 through 18.x.",
        ),
        (
            c3_x0,
            "GITHUB OPEN SOURCE",
            PURPLE,
            "Full Objective-C Source & Releases:",
            "github.com/NightKnight24/\nAntiLagShield",
            "Auditable & MIT Licensed:",
            "Inspect every line of AntiLagShield.app, AntiLagShieldBanner.dylib, AntiLagShieldCC, and shield_ctl.",
        ),
    ]

    for x0, heading, col, lbl1, code_txt, lbl2, body_txt in cards:
        x1 = x0 + cw
        draw_card(draw, (x0, cy0, x1, cy1), fill=CARD_BG, outline=col, radius=20, width=2)
        draw.rounded_rectangle([x0 + 28, cy0 + 24, x0 + 76, cy0 + 30], radius=3, fill=col)
        draw_text_in_box(
            draw,
            heading,
            sans_bold,
            23,
            col,
            (x0 + 28, cy0 + 44, x1 - 28, cy0 + 78),
            valign="center",
        )
        draw_text_in_box(
            draw,
            lbl1,
            sans_med,
            17,
            GRAY,
            (x0 + 28, cy0 + 94, x1 - 28, cy0 + 120),
            valign="center",
        )
        draw_card(draw, (x0 + 24, cy0 + 128, x1 - 24, cy0 + 224), fill=INNER_BG, outline=CARD_BORDER, radius=12, width=1)
        draw_wrapped_in_box(
            draw,
            code_txt,
            mono_bold,
            16,
            WHITE,
            (x0 + 38, cy0 + 144, x1 - 38, cy0 + 210),
            line_gap=8,
        )
        draw_text_in_box(
            draw,
            lbl2,
            sans_med,
            18,
            col,
            (x0 + 28, cy0 + 244, x1 - 28, cy0 + 272),
            valign="center",
        )
        draw_wrapped_in_box(
            draw,
            body_txt,
            sans_reg,
            17,
            WHITE,
            (x0 + 28, cy0 + 282, x1 - 28, cy1 - 24),
            line_gap=6,
        )

    cta_y0, cta_y1 = 796, 976
    draw_card(draw, (MARGIN_X, cta_y0, WIDTH - MARGIN_X, cta_y1), fill=(14, 22, 35), outline=CYAN, radius=20, width=2)
    draw_text_in_box(
        draw,
        "Comment your iPad or iPhone model & iOS version below — Like & Subscribe for more releases!",
        sans_bold,
        24,
        WHITE,
        (MARGIN_X + 40, cta_y0 + 34, WIDTH - MARGIN_X - 40, cta_y0 + 78),
        align="center",
        valign="center",
    )
    draw_text_in_box(
        draw,
        "Direct repo URL, .deb download, and full source code are linked in the description.",
        sans_reg,
        20,
        CYAN,
        (MARGIN_X + 40, cta_y0 + 96, WIDTH - MARGIN_X - 40, cta_y0 + 136),
        align="center",
        valign="center",
    )

    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


DEFAULT_DURATIONS = [15.5, 13.2, 14.7, 15.5, 14.4, 14.5, 13.2]
RENDER_FNS = [
    render_scene_1,
    render_scene_2,
    render_scene_3,
    render_scene_4,
    render_scene_5,
    render_scene_6,
    render_scene_7,
]


def build_scene_schedule():
    meta_path = "/tmp/als_leda_meta.json"
    durations = list(DEFAULT_DURATIONS)
    if os.path.exists(meta_path):
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
        by_scene = {int(m["scene"]): float(m["duration"]) for m in meta}
        for i in range(7):
            s_num = i + 1
            if s_num in by_scene:
                pad = 2.4 if s_num == 7 else 1.7
                dur_frames = int(math.ceil((by_scene[s_num] + pad) * FPS))
                durations[i] = dur_frames / float(FPS)

    plan = []
    cur_sec = 0.0
    scenes = []
    for idx, dur_sec in enumerate(durations):
        n_frames = int(round(dur_sec * FPS))
        actual_dur = n_frames / float(FPS)
        plan.append({"scene": idx + 1, "start_sec": round(cur_sec, 4), "duration_sec": round(actual_dur, 4)})
        scenes.append((n_frames, RENDER_FNS[idx]))
        cur_sec += actual_dur

    with open(SCENE_PLAN_JSON, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=2)
    return scenes, plan


def main():
    scenes, plan = build_scene_schedule()
    total_frames = sum(n for n, _ in scenes)
    print(f"==> Rendering {len(scenes)} scenes: {total_frames} frames ({total_frames / FPS:.2f}s @ {FPS} fps)...")

    # Pre-verify 1 sample frame per scene before full video encode to catch any layout/bounds issue immediately
    for s_idx, (num_f, fn) in enumerate(scenes):
        _ = fn(0, num_f, float(s_idx) / len(scenes))
    print("==> Bounds pre-flight check passed across all 7 scenes (0 text overflows).")

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(OUTPUT_RAW, fourcc, FPS, (WIDTH, HEIGHT))

    global_frame = 0
    t0 = time.time()
    for s_idx, (num_f, render_fn) in enumerate(scenes):
        print(f"  -> Scene {s_idx + 1}/{len(scenes)} ({num_f} frames, {plan[s_idx]['duration_sec']:.2f}s)...")
        # Cache static body frame per scene where grid pulse updates every 2 frames for fast, crisp encoding
        cached_bgr = None
        for f in range(num_f):
            prog = global_frame / float(max(1, total_frames - 1))
            if f % 2 == 0 or cached_bgr is None:
                cached_bgr = render_fn(f, num_f, prog)
            out.write(cached_bgr)
            global_frame += 1

    out.release()
    print(f"==> Video stream rendered to {OUTPUT_RAW} in {time.time() - t0:.1f}s.")

    synth_script = os.path.join(BASE_DIR, "synthesize_soundtrack.py")
    subprocess.run([sys.executable, synth_script], check=True)

    audio_path = "/tmp/master_soundtrack_with_voice.wav"
    if not os.path.exists(audio_path):
        print("ERROR: Master soundtrack missing!", file=sys.stderr)
        sys.exit(1)

    print("==> Muxing H.264 High Profile + AAC 256k MP4...")
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            OUTPUT_RAW,
            "-i",
            audio_path,
            "-c:v",
            "libx264",
            "-profile:v",
            "high",
            "-pix_fmt",
            "yuv420p",
            "-preset",
            "fast",
            "-crf",
            "18",
            "-movflags",
            "+faststart",
            "-c:a",
            "aac",
            "-b:a",
            "256k",
            "-shortest",
            FINAL_VIDEO,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )

    sz_mb = os.path.getsize(FINAL_VIDEO) / (1024.0 * 1024.0)
    print(f"==> SUCCESS: {FINAL_VIDEO} ({sz_mb:.2f} MB)")

    for dst_dir in (os.path.join(HOME_DIR, "Desktop"), os.path.join(HOME_DIR, "Downloads")):
        if os.path.isdir(dst_dir):
            dst = os.path.join(dst_dir, "AntiLagShield_Showcase.mp4")
            subprocess.run(["cp", "-f", FINAL_VIDEO, dst], check=True)


if __name__ == "__main__":
    main()
