#!/usr/bin/env python3
"""Synthesizes the 120 BPM backing soundtrack and mixes scene-synced voiceover."""

import json
import math
import os
import subprocess
import wave
import numpy as np

SAMPLE_RATE = 44100
BPM = 120
BEAT_LEN = 60.0 / BPM
SIXTEENTH = BEAT_LEN / 4.0

VOICE_SCRIPT = [
    (
        1,
        15.5,
        "Welcome to Anti-Lag Shield. It's a lightweight, passive XNU kernel network tuner "
        "built for iPadOS and iOS, designed to eliminate streaming stutter and gaming "
        "latency with zero background CPU drain.",
    ),
    (
        2,
        13.2,
        "Instead of running heavy background daemons that poll your device and drain battery, "
        "Anti-Lag Shield writes socket buffer and TCP rules directly into the Darwin kernel, "
        "then exits cleanly.",
    ),
    (
        3,
        14.7,
        "Inside the native app, you can switch between Streaming, Gaming, and Normal modes, "
        "monitor live gateway latency and free memory, toggle Turbo UI, and flush inactive "
        "RAM pages in a single tap.",
    ),
    (
        4,
        15.5,
        "Right inside the pull-down Notification Center, a persistent native banner gives you "
        "one-tap buttons for Streaming, Gaming, and Normal mode, plus Clear RAM and Clear Cache, "
        "alongside a Control Center toggle and Siri Shortcuts.",
    ),
    (
        5,
        14.4,
        "Under the hood, Anti-Lag Shield locks your router gateway into the kernel ARP table, "
        "pauses background AirDrop radio scans to prevent Wi-Fi stutter, and keeps your IP and "
        "MAC addresses completely private on device.",
    ),
    (
        6,
        14.5,
        "When memory gets tight, Clear RAM reclaims hundreds of megabytes of inactive pages "
        "safely without triggering Jetsam crashes, while Clear Cache removes stale crash logs "
        "and expired system caches.",
    ),
    (
        7,
        13.2,
        "Anti-Lag Shield is free and open source on GitHub by NightKnight24, and ready to "
        "install through Sileo, Zebra, or the Debian package linked in the description below.",
    ),
]


def load_scene_timings():
    plan_path = "/tmp/als_scene_plan.json"
    if os.path.exists(plan_path):
        with open(plan_path, "r", encoding="utf-8") as f:
            plan = json.load(f)
        return [(int(row["scene"]), float(row["start_sec"]), float(row["duration_sec"])) for row in plan]

    timings = []
    cur = 0.0
    for idx, dur, _ in VOICE_SCRIPT:
        timings.append((idx, cur, dur))
        cur += dur
    return timings


def make_kick():
    dur = 0.35
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    freq = 42.0 + 108.0 * np.exp(-t * 30.0)
    phase = 2.0 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    sig = np.sin(phase) * np.exp(-t * 9.0)
    return np.tanh(sig * 1.5) * 0.82


def make_snare():
    dur = 0.26
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    rng = np.random.default_rng(42)
    noise = rng.uniform(-1.0, 1.0, n) * np.exp(-t * 22.0)
    tone = np.sin(2.0 * np.pi * (185.0 * np.exp(-t * 15.0)) * t) * np.exp(-t * 16.0)
    return np.tanh((noise * 0.62 + tone * 0.38) * 0.72 * 1.3)


def make_hihat(open_hat=False):
    dur = 0.20 if open_hat else 0.05
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    rng = np.random.default_rng(108 if open_hat else 77)
    noise = rng.uniform(-1.0, 1.0, n)
    decay = 18.0 if open_hat else 70.0
    return noise * np.exp(-t * decay) * 0.22


def mix_sample(buf, sample, start_idx, gain=1.0):
    end_idx = min(start_idx + len(sample), len(buf))
    sz = end_idx - start_idx
    if sz > 0:
        buf[start_idx:end_idx] += sample[:sz] * gain


def synth_bass_note(freq, dur):
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    saw = 2.0 * (t * freq - np.floor(t * freq + 0.5))
    sub = np.sin(2.0 * np.pi * (freq * 0.5) * t)
    cutoff = np.exp(-t * 12.0)
    sig = (saw * 0.52 * cutoff + sub * 0.48) * np.exp(-t * 6.0)
    return np.tanh(sig * 1.35) * 0.62


def synth_lead_note(freq, dur, pan=0.0):
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    sq = np.sign(np.sin(2.0 * np.pi * freq * t)) * 0.28
    saw = (2.0 * (t * freq - np.floor(t * freq + 0.5))) * 0.36
    env = np.exp(-t * 8.0) * (1.0 - np.exp(-t * 120.0))
    sig = (sq + saw) * env * 0.26
    gain_l = math.cos((pan + 1.0) * math.pi / 4.0)
    gain_r = math.sin((pan + 1.0) * math.pi / 4.0)
    return sig * gain_l, sig * gain_r


def load_voice_clip(scene_idx, fallback_text):
    leda_wav = f"/tmp/als_leda_scene_{scene_idx}.wav"
    resampled_wav = f"/tmp/als_voice_44k_{scene_idx}.wav"

    if os.path.exists(leda_wav):
        subprocess.run(
            ["ffmpeg", "-y", "-i", leda_wav, "-ar", str(SAMPLE_RATE), "-ac", "1", resampled_wav],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
    else:
        aiff_f = f"/tmp/als_fallback_{scene_idx}.aiff"
        subprocess.run(["say", "-v", "Samantha", "-r", "165", "-o", aiff_f, fallback_text], check=True)
        subprocess.run(
            ["ffmpeg", "-y", "-i", aiff_f, "-ar", str(SAMPLE_RATE), "-ac", "1", resampled_wav],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        if os.path.exists(aiff_f):
            os.remove(aiff_f)

    with wave.open(resampled_wav, "rb") as wf:
        raw = wf.readframes(wf.getnframes())
    if os.path.exists(resampled_wav):
        os.remove(resampled_wav)

    arr = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    peak = float(np.max(np.abs(arr))) if len(arr) > 0 else 0.0
    if peak > 1e-4:
        arr = (arr / peak) * 0.92

    fade_n = min(int(SAMPLE_RATE * 0.015), len(arr) // 4)
    if fade_n > 1:
        ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, fade_n, dtype=np.float32))
        arr[:fade_n] *= ramp
        arr[-fade_n:] *= ramp[::-1]
    return arr


def main():
    timings = load_scene_timings()
    total_secs = sum(dur for _, _, dur in timings)
    num_samples = int(round(SAMPLE_RATE * total_secs))
    num_beats = int(math.ceil(total_secs / BEAT_LEN))
    num_bars = int(math.ceil(num_beats / 4.0))

    print(f"==> Synthesizing soundtrack: {total_secs:.1f}s @ {BPM} BPM...")

    kick_sample = make_kick()
    snare_sample = make_snare()
    hat_closed = make_hihat(False)
    hat_open = make_hihat(True)

    music_l = np.zeros(num_samples, dtype=np.float32)
    music_r = np.zeros(num_samples, dtype=np.float32)

    for beat in range(num_beats):
        s_idx = int(beat * BEAT_LEN * SAMPLE_RATE)
        if s_idx >= num_samples:
            break
        bar = beat // 4
        beat_in_bar = beat % 4

        mix_sample(music_l, kick_sample, s_idx, 0.88)
        mix_sample(music_r, kick_sample, s_idx, 0.88)

        if beat_in_bar in (1, 3):
            mix_sample(music_l, snare_sample, s_idx, 0.72)
            mix_sample(music_r, snare_sample, s_idx, 0.72)

        for sub in range(4):
            h_idx = s_idx + int(sub * SIXTEENTH * SAMPLE_RATE)
            if h_idx < num_samples:
                if sub == 2 and beat_in_bar == 3 and bar % 2 == 1:
                    mix_sample(music_l, hat_open, h_idx, 0.34)
                    mix_sample(music_r, hat_open, h_idx, 0.38)
                else:
                    gain = 0.38 if sub == 0 else (0.26 if sub == 2 else 0.15)
                    mix_sample(music_l, hat_closed, h_idx, gain * 0.9)
                    mix_sample(music_r, hat_closed, h_idx, gain * 1.1)

    chord_roots = [
        55.00, 55.00, 43.65, 48.99,
        55.00, 36.71, 43.65, 41.20,
        55.00, 43.65, 65.41, 48.99,
        43.65, 48.99, 41.20, 55.00,
    ]

    for bar_idx in range(num_bars):
        root_f = chord_roots[bar_idx % len(chord_roots)]
        bar_start_s = bar_idx * (4.0 * BEAT_LEN)
        for sixteenth_idx in range(16):
            note_s_idx = int((bar_start_s + sixteenth_idx * SIXTEENTH) * SAMPLE_RATE)
            if note_s_idx >= num_samples:
                break
            f = root_f * 2.0 if (sixteenth_idx % 4 == 2) else root_f
            b_sample = synth_bass_note(f, SIXTEENTH * 0.9)
            mix_sample(music_l, b_sample, note_s_idx, 0.58)
            mix_sample(music_r, b_sample, note_s_idx, 0.58)

    arp_offsets = [1.0, 1.2, 1.5, 2.0, 1.5, 1.2, 1.0, 0.75]
    for beat in range(num_beats):
        bar = beat // 4
        root = chord_roots[bar % len(chord_roots)] * 4.0
        for sub in range(4):
            note_idx = beat * 4 + sub
            s_idx = int(note_idx * SIXTEENTH * SAMPLE_RATE)
            if s_idx >= num_samples:
                break
            f = root * arp_offsets[note_idx % len(arp_offsets)]
            pan = 0.45 * math.sin(note_idx * 0.8)
            lead_l, lead_r = synth_lead_note(f, SIXTEENTH * 1.5, pan=pan)
            mix_sample(music_l, lead_l, s_idx, 0.60)
            mix_sample(music_r, lead_r, s_idx, 0.60)

    fade_len = min(int(SAMPLE_RATE * 2.8), num_samples // 4)
    fade_env = np.linspace(1.0, 0.0, fade_len, dtype=np.float32)
    music_l[-fade_len:] *= fade_env
    music_r[-fade_len:] *= fade_env

    peak = max(float(np.max(np.abs(music_l))), float(np.max(np.abs(music_r))), 1e-4)
    music_l = (music_l / peak) * 0.78
    music_r = (music_r / peak) * 0.78

    script_by_scene = {idx: txt for idx, _, txt in VOICE_SCRIPT}
    voice_l = np.zeros(num_samples, dtype=np.float32)
    voice_r = np.zeros(num_samples, dtype=np.float32)
    speech_mask = np.zeros(num_samples, dtype=np.float32)

    has_leda = all(os.path.exists(f"/tmp/als_leda_scene_{i}.wav") for i in range(1, 8))
    print(f"==> Mixing voiceover ({'Gemini Leda 24kHz->44.1kHz' if has_leda else 'System TTS fallback'})...")

    for scene_idx, start_sec, scene_dur in timings:
        v_data = load_voice_clip(scene_idx, script_by_scene[scene_idx])
        offset_sec = 0.55
        s_idx = int((start_sec + offset_sec) * SAMPLE_RATE)
        max_end_idx = min(int((start_sec + scene_dur - 0.15) * SAMPLE_RATE), num_samples)
        e_idx = min(s_idx + len(v_data), max_end_idx)
        sz = e_idx - s_idx
        if sz > 0:
            voice_l[s_idx:e_idx] += v_data[:sz] * 0.96
            voice_r[s_idx:e_idx] += v_data[:sz] * 0.96
            pad_pre = max(0, s_idx - int(0.12 * SAMPLE_RATE))
            pad_post = min(num_samples, e_idx + int(0.18 * SAMPLE_RATE))
            speech_mask[pad_pre:pad_post] = 1.0

    kernel_sz = int(SAMPLE_RATE * 0.24)
    kernel = np.ones(kernel_sz, dtype=np.float32) / float(kernel_sz)
    smoothed_speech = np.clip(np.convolve(speech_mask, kernel, mode="same") * 2.2, 0.0, 1.0)

    duck_curve = 0.70 - (smoothed_speech * 0.52)
    music_l *= duck_curve
    music_r *= duck_curve

    master_l = music_l + voice_l
    master_r = music_r + voice_r
    master_peak = max(float(np.max(np.abs(master_l))), float(np.max(np.abs(master_r))), 1e-4)
    if master_peak > 0.95:
        master_l = (master_l / master_peak) * 0.95
        master_r = (master_r / master_peak) * 0.95

    interleaved = np.empty((num_samples * 2,), dtype=np.int16)
    interleaved[0::2] = np.clip(master_l * 32767.0, -32768, 32767).astype(np.int16)
    interleaved[1::2] = np.clip(master_r * 32767.0, -32768, 32767).astype(np.int16)

    master_audio_path = "/tmp/master_soundtrack_with_voice.wav"
    with wave.open(master_audio_path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(interleaved.tobytes())

    sz_mb = os.path.getsize(master_audio_path) / (1024.0 * 1024.0)
    print(f"==> Master soundtrack saved: {master_audio_path} ({sz_mb:.1f} MB)")


if __name__ == "__main__":
    main()
