#!/usr/bin/env python3
import os, subprocess, wave
import numpy as np

# Scene timing (start_sec, max_speech_dur, text)
SCENES = [
    (1, 0.5, 4.8, "Meet Anti-Lag Shield Pro 3.8. The ultimate low-latency network sentinel and device revival suite for iOS."),
    (2, 6.6, 5.8, "New iOS updates cause severe UI stutter, background daemon battery drain, and antenna collisions on older devices."),
    (3, 13.6, 6.5, "Turbo UI mode bypasses heavy SpringBoard GPU blurs for instant zero-millisecond touch response and cooler temps."),
    (4, 21.6, 6.5, "The one-tap storage cleaner purges over a thousand stale diagnostic logs, restoring peak NAND read-write speeds."),
    (5, 29.6, 6.5, "Zero-Trust Sentinel locks your router in the Darwin kernel, blocking rogue ARP attacks with dynamic Retina TCP buffers."),
    (6, 37.6, 6.5, "Bluetooth Gamepad Acceleration eliminates antenna interference and boosts controllers to Real-Time VIP priority."),
    (7, 45.6, 6.0, "Available now on Sileo, Zebra, TrollStore, and TrollStore. Free and open source on GitHub by NightKnight24.")
]

for idx, start_t, max_d, text in SCENES:
    for voice in ["Daniel (English (UK))", "Samantha"]:
        v_tag = "daniel" if "Daniel" in voice else "samantha"
        f = f"/tmp/v_{v_tag}_{idx}.aiff"
        subprocess.run(["say", "-v", voice, "-r", "195", "-o", f, text])
        dur = float(subprocess.check_output(["ffprobe", "-i", f, "-show_entries", "format=duration", "-v", "quiet", "-of", "csv=p=0"]).decode().strip())
        print(f"[{v_tag}] Scene {idx}: speech dur={dur:.2f}s (budget: {max_d}s)")
