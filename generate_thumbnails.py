#!/usr/bin/env python3
# ==============================================================================
# 🎨 YouTube High-CTR Thumbnail Generator for Anti-Lag Shield
# Creates ultra-crisp, high-contrast, attention-grabbing 1280x720 & 1920x1080 thumbnails:
# - Bold typography with drop shadows and glowing neon accents
# - Real iPad hardware mockup showcasing the live app HUD (0.064ms ping)
# - "Stock iOS vs Anti-Lag Shield" latency comparison badges
# - "0% CPU" and "3 Quick Toggles" viral feature pills
# ==============================================================================

import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1920, 1080

FONT_BOLD = "/System/Library/Fonts/Supplemental/Impact.ttf"
FONT_ARIAL_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_HELVETICA = "/System/Library/Fonts/Helvetica.ttc"
FONT_MONO = "/System/Library/Fonts/Supplemental/Courier New Bold.ttf"

def get_font(path, size, index=0):
    try:
        return ImageFont.truetype(path, size, index=index)
    except Exception:
        try:
            return ImageFont.truetype(FONT_ARIAL_BOLD, size)
        except Exception:
            return ImageFont.load_default()

font_massive = get_font(FONT_BOLD, 125)
font_huge = get_font(FONT_BOLD, 95)
font_h1 = get_font(FONT_ARIAL_BOLD, 52)
font_h2 = get_font(FONT_ARIAL_BOLD, 38)
font_badge = get_font(FONT_ARIAL_BOLD, 30)
font_mono = get_font(FONT_MONO, 28)

LIVE_TOP_PATH = "/Users/jordanallison/.gemini/antigravity/brain/58a92e58-afdd-43ff-a171-1e809caa3c0b/antilag_live_top.png"
raw_ipad_img = Image.open(LIVE_TOP_PATH) if os.path.exists(LIVE_TOP_PATH) else None

def draw_text_with_outline(draw, pos, text, font, fill_color, outline_color=(0, 0, 0), outline_width=4):
    x, y = pos
    # Draw outline
    for dx in range(-outline_width, outline_width + 1):
        for dy in range(-outline_width, outline_width + 1):
            if dx*dx + dy*dy <= outline_width*outline_width:
                draw.text((x + dx, y + dy), text, font=font, fill=outline_color)
    # Draw main text
    draw.text((x, y), text, font=font, fill=fill_color)

def draw_text_with_glow(draw, img, pos, text, font, fill_color, glow_color, glow_radius=8):
    # Create glow overlay
    glow_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glow_img)
    x, y = pos
    for dx in [-4, -2, 0, 2, 4]:
        for dy in [-4, -2, 0, 2, 4]:
            g_draw.text((x + dx, y + dy), text, font=font, fill=glow_color)
    glow_blurred = glow_img.filter(ImageFilter.GaussianBlur(glow_radius))
    img.paste(glow_blurred, (0, 0), glow_blurred)
    draw.text((x, y), text, font=font, fill=fill_color)

def create_cyber_bg():
    img = Image.new("RGB", (W, H), (10, 13, 20))
    d = ImageDraw.Draw(img)
    
    # Diagonal dark gradient / speed slashes
    for i in range(-500, W + 500, 70):
        d.line([(i, 0), (i + 400, H)], fill=(16, 22, 34), width=2)
        
    # High-tech radial cyan corner glow
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-200, -200, 800, 800], fill=(0, 180, 240, 35))
    gd.ellipse([W - 600, H - 600, W + 400, H + 400], fill=(48, 209, 88, 25))
    glow_b = glow.filter(ImageFilter.GaussianBlur(80))
    img.paste(glow_b, (0, 0), glow_b)
    
    # Border vignette
    d.rectangle([0, 0, W, H], outline=(0, 210, 245), width=8)
    return img

def make_ipad_bezel(raw_img, w=840, h=590):
    ipad = Image.new("RGB", (w, h), (26, 30, 40))
    d = ImageDraw.Draw(ipad)
    d.rounded_rectangle([0, 0, w, h], radius=26, fill=(18, 22, 30), outline=(0, 210, 245), width=4)
    
    pad = 18
    sw = w - (pad * 2)
    sh = h - (pad * 2)
    
    if raw_img:
        target_h = int(sw * (1536.0 / 2048.0))
        scaled = raw_img.resize((sw, target_h), Image.Resampling.LANCZOS)
        if target_h > sh:
            crop_top = 0  # Show top HUD clearly!
            scaled = scaled.crop((0, crop_top, sw, crop_top + sh))
        ipad.paste(scaled, (pad, pad))
    else:
        d.rectangle([pad, pad, pad + sw, pad + sh], fill=(12, 16, 24))
        
    # Camera dot
    d.ellipse([w // 2 - 5, 6, w // 2 + 5, 16], fill=(5, 5, 8))
    return ipad

# ==============================================================================
# THUMBNAIL 1: "0ms WI-FI LAG!" (High Shock Value & Comparison)
# ==============================================================================
def generate_thumbnail_1():
    img = create_cyber_bg()
    draw = ImageDraw.Draw(img)
    
    # 1. Top Viral Pill Badge
    pill_w, pill_h = 560, 52
    px, py = 80, 70
    draw.rounded_rectangle([px, py, px + pill_w, py + pill_h], radius=26, fill=(220, 20, 60), outline=(255, 255, 255), width=3)
    draw.text((px + 32, py + 10), "🔥 NEW iOS JAILBREAK TWEAK", font=font_badge, fill=(255, 255, 255))
    
    # 2. Main Title Line 1 (Yellow)
    draw_text_with_outline(draw, (80, 140), "FIX ALL iOS LAG!", font=font_massive, fill_color=(255, 220, 0), outline_color=(0, 0, 0), outline_width=6)
    
    # 3. Main Title Line 2 (White with Cyan Glow)
    draw_text_with_outline(draw, (80, 275), "0.064ms PING", font=font_huge, fill_color=(255, 255, 255), outline_color=(0, 0, 0), outline_width=6)
    
    # 4. Side-by-Side Comparison Box
    # Before (Stock iOS)
    bx, by = 80, 420
    bw = 420
    draw.rounded_rectangle([bx, by, bx + bw, by + 160], radius=18, fill=(35, 15, 20), outline=(255, 69, 58), width=3)
    draw.text((bx + 25, by + 20), "STOCK iOS:", font=font_h2, fill=(255, 69, 58))
    draw.text((bx + 25, by + 68), "❌ 140ms Jitter Spikes", font=font_mono, fill=(255, 255, 255))
    draw.text((bx + 25, by + 108), "❌ Background Battery Drain", font=font_mono, fill=(180, 180, 180))

    # After (Anti-Lag Shield)
    ax = bx + bw + 25
    draw.rounded_rectangle([ax, by, ax + bw, by + 160], radius=18, fill=(15, 35, 22), outline=(48, 209, 88), width=3)
    draw.text((ax + 25, by + 20), "ANTI-LAG SHIELD:", font=font_h2, fill=(48, 209, 88))
    draw.text((ax + 25, by + 68), "✅ 0.064ms Ultra Flat", font=font_mono, fill=(255, 255, 255))
    draw.text((ax + 25, by + 108), "✅ 0% CPU (Passive Kernel)", font=font_mono, fill=(0, 210, 245))

    # 5. Bottom 3 Key Badges
    badges = [
        ("⚡ 0% CPU OVERHEAD", (0, 210, 245)),
        ("🎛️ 3 QUICK TOGGLES", (255, 214, 10)),
        ("🔓 FREE & OPEN SOURCE", (48, 209, 88))
    ]
    bdg_y = 620
    bdg_x = 80
    for b_text, b_col in badges:
        bw_val = 265
        draw.rounded_rectangle([bdg_x, bdg_y, bdg_x + bw_val, bdg_y + 60], radius=14, fill=(18, 24, 36), outline=b_col, width=2)
        draw.text((bdg_x + 18, bdg_y + 16), b_text, font=font_badge, fill=(255, 255, 255))
        bdg_x += bw_val + 20

    # 6. Live iPad Mockup on Right Side
    ipad_mock = make_ipad_bezel(raw_ipad_img, w=890, h=620)
    # Add a glowing drop shadow behind iPad
    ipad_shadow = Image.new("RGBA", (930, 660), (0, 0, 0, 0))
    sd = ImageDraw.Draw(ipad_shadow)
    sd.rounded_rectangle([20, 20, 910, 640], radius=32, fill=(0, 210, 245, 80))
    ipad_shadow = ipad_shadow.filter(ImageFilter.GaussianBlur(25))
    
    img.paste(ipad_shadow, (980, 160), ipad_shadow)
    img.paste(ipad_mock, (1000, 180))
    
    # 7. Red Arrow & Highlight Banner pointing to the live ping
    arr_x, arr_y = 1040, 835
    draw.rounded_rectangle([arr_x, arr_y, arr_x + 810, arr_y + 80], radius=18, fill=(10, 18, 28), outline=(0, 210, 245), width=3)
    draw.text((arr_x + 25, arr_y + 22), "🔴 LIVE VERIFIED TEST: 0.064ms PING ON IPADOS 17", font=font_h2, fill=(0, 210, 245))

    return img

# ==============================================================================
# THUMBNAIL 2: "INSTANT 0ms TOUCH & NET" (Pro Gaming & Control Center Focus)
# ==============================================================================
def generate_thumbnail_2():
    img = create_cyber_bg()
    draw = ImageDraw.Draw(img)
    
    # 1. Top Banner
    pill_w, pill_h = 640, 52
    px, py = 80, 65
    draw.rounded_rectangle([px, py, px + pill_w, py + pill_h], radius=26, fill=(16, 45, 40), outline=(48, 209, 88), width=3)
    draw.text((px + 28, py + 10), "⚡ 100% PASSIVE KERNEL RESIDENT", font=font_badge, fill=(48, 209, 88))
    
    # 2. Main Title Line 1 (Cyan)
    draw_text_with_outline(draw, (80, 135), "ANTI-LAG SHIELD", font=font_massive, fill_color=(0, 210, 245), outline_color=(0, 0, 0), outline_width=6)
    
    # 3. Main Title Line 2 (Yellow)
    draw_text_with_outline(draw, (80, 270), "3 QUICK TOGGLES!", font=font_huge, fill_color=(255, 214, 10), outline_color=(0, 0, 0), outline_width=6)
    
    # 4. Feature Cards
    feats = [
        ("🎛️ CONTROL CENTER", "1-Swipe Toggle with CCSupport Bundle", (0, 210, 245)),
        ("🔔 NOTIFICATION BAR", "Pull-Down Interactive Streaming/Gaming Banner", (48, 209, 88)),
        ("⚡ SIRI SHORTCUTS", "1-Tap Home & Lock Screen Widgets", (175, 82, 222))
    ]
    fy = 415
    for title, desc, col in feats:
        draw.rounded_rectangle([80, fy, 80 + 860, fy + 78], radius=16, fill=(18, 24, 36), outline=col, width=2)
        draw.text((105, fy + 12), title, font=font_h2, fill=col)
        draw.text((105, fy + 48), desc, font=font_mono, fill=(220, 220, 220))
        fy += 92

    # Bottom Callout Pill
    draw.rounded_rectangle([80, 715, 80 + 860, 715 + 75], radius=16, fill=(220, 20, 60), outline=(255, 255, 255), width=2)
    draw.text((120, 735), "🚀 WORKS ON ALL 64-BIT iOS & iPadOS (12.0 – 18.x)", font=font_h2, fill=(255, 255, 255))

    # 5. Live iPad Mockup on Right Side
    ipad_mock = make_ipad_bezel(raw_ipad_img, w=890, h=620)
    ipad_shadow = Image.new("RGBA", (930, 660), (0, 0, 0, 0))
    sd = ImageDraw.Draw(ipad_shadow)
    sd.rounded_rectangle([20, 20, 910, 640], radius=32, fill=(48, 209, 88, 80))
    ipad_shadow = ipad_shadow.filter(ImageFilter.GaussianBlur(25))
    
    img.paste(ipad_shadow, (980, 160), ipad_shadow)
    img.paste(ipad_mock, (1000, 180))
    
    # Right Side Bottom Badge
    bx, by = 1000, 835
    draw.rounded_rectangle([bx, by, bx + 850, by + 80], radius=18, fill=(12, 16, 24), outline=(48, 209, 88), width=3)
    draw.text((bx + 35, by + 22), "🛡️ HARDWARE ARP LOCK + ADAPTIVE DELAYED ACK", font=font_h2, fill=(48, 209, 88))

    return img

def main():
    print("==> Generating High-CTR YouTube Thumbnails...")
    
    t1 = generate_thumbnail_1()
    t2 = generate_thumbnail_2()
    
    # Save Full-Res 1920x1080 and YouTube-Standard 1280x720
    paths = [
        ("/Users/jordanallison/Desktop/AntiLagShield_Thumbnail_1.png", t1),
        ("/Users/jordanallison/Downloads/AntiLagShield_Thumbnail_1.png", t1),
        ("/Users/jordanallison/.gemini/antigravity/brain/58a92e58-afdd-43ff-a171-1e809caa3c0b/AntiLagShield_Thumbnail_1.png", t1),
        ("/Users/jordanallison/Desktop/AntiLagShield_Thumbnail_2.png", t2),
        ("/Users/jordanallison/Downloads/AntiLagShield_Thumbnail_2.png", t2),
        ("/Users/jordanallison/.gemini/antigravity/brain/58a92e58-afdd-43ff-a171-1e809caa3c0b/AntiLagShield_Thumbnail_2.png", t2),
    ]
    
    for path, img in paths:
        img.save(path, quality=95)
        # Also save 1280x720 variant
        p_720 = path.replace(".png", "_720p.png")
        img_720 = img.resize((1280, 720), Image.Resampling.LANCZOS)
        img_720.save(p_720, quality=95)
        print(f"  -> Saved {path} ({os.path.getsize(path)/1024:.1f} KB)")
        
    print("==> SUCCESS: All thumbnails generated and exported!")

if __name__ == "__main__":
    main()
