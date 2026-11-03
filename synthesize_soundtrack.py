#!/usr/bin/env python3
# ==============================================================================
# 🎵 Cyberpunk Soundtrack & Voice-Over Synthesis Engine v2.0
# Generates 100% royalty-free 120 BPM electronic cyberpunk music + natural human voiceover
# with automatic sidechain audio ducking and sample-accurate synchronization.
# Voice: Samantha (English US) @ 162 WPM (Clear, natural conversational delivery)
# ==============================================================================

import os, math, subprocess, wave
import numpy as np

SAMPLE_RATE = 44100
BPM = 120
BEAT_LEN = 60.0 / BPM          # 0.5 sec
SIXTEENTH = BEAT_LEN / 4.0     # 0.125 sec
TOTAL_SECS = 70.0
NUM_SAMPLES = int(SAMPLE_RATE * TOTAL_SECS)

print(f"==> Synthesizing Cyberpunk Soundtrack: {TOTAL_SECS}s @ {BPM} BPM ({NUM_SAMPLES} samples)...")

# --- 1. DRUM SYNTHESIZERS ---
def make_kick():
    dur = 0.35
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    freq = 42.0 + 108.0 * np.exp(-t * 30.0)
    phase = 2.0 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    amp = np.exp(-t * 9.0)
    sig = np.sin(phase) * amp
    return np.tanh(sig * 1.5) * 0.85

def make_snare():
    dur = 0.28
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    noise = np.random.uniform(-1.0, 1.0, n) * np.exp(-t * 22.0)
    tone = np.sin(2.0 * np.pi * (185.0 * np.exp(-t * 15.0)) * t) * np.exp(-t * 16.0)
    sig = (noise * 0.65 + tone * 0.35) * 0.75
    return np.tanh(sig * 1.3)

def make_hihat(open_hat=False):
    dur = 0.20 if open_hat else 0.05
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    noise = np.random.uniform(-1.0, 1.0, n)
    decay = 18.0 if open_hat else 70.0
    return noise * np.exp(-t * decay) * 0.25

kick_sample = make_kick()
snare_sample = make_snare()
hat_closed = make_hihat(False)
hat_open = make_hihat(True)

music_L = np.zeros(NUM_SAMPLES, dtype=np.float32)
music_R = np.zeros(NUM_SAMPLES, dtype=np.float32)

def mix_sample(buf, sample, start_idx, gain=1.0):
    end_idx = min(start_idx + len(sample), len(buf))
    sz = end_idx - start_idx
    if sz > 0:
        buf[start_idx:end_idx] += sample[:sz] * gain

# --- 2. COMPOSE DRUMS (140 beats = 35 bars) ---
print("  -> Arranging rhythmic drum tracks (808 Kicks, Cyber Snares, Hi-Hats)...")
for beat in range(140):
    t_sec = beat * BEAT_LEN
    s_idx = int(t_sec * SAMPLE_RATE)
    if s_idx >= NUM_SAMPLES: break
    bar = beat // 4
    beat_in_bar = beat % 4
    
    # Four-on-the-floor Kicks
    mix_sample(music_L, kick_sample, s_idx, 0.9)
    mix_sample(music_R, kick_sample, s_idx, 0.9)
    
    # Cyber Snares on beats 2 and 4
    if beat_in_bar in [1, 3]:
        mix_sample(music_L, snare_sample, s_idx, 0.75)
        mix_sample(music_R, snare_sample, s_idx, 0.75)
        
    # 16th-note Hi-Hats
    for sub in range(4):
        h_idx = s_idx + int(sub * SIXTEENTH * SAMPLE_RATE)
        if h_idx < NUM_SAMPLES:
            if sub == 2 and beat_in_bar == 3 and bar % 2 == 1:
                mix_sample(music_L, hat_open, h_idx, 0.35)
                mix_sample(music_R, hat_open, h_idx, 0.40)
            else:
                gain = 0.40 if sub == 0 else (0.28 if sub == 2 else 0.16)
                mix_sample(music_L, hat_closed, h_idx, gain * 0.9)
                mix_sample(music_R, hat_closed, h_idx, gain * 1.1)

# --- 3. BASSLINE & CHORD PROGRESSION ---
NOTE_A1 = 55.0
NOTE_F1 = 43.65
NOTE_D1 = 36.71
NOTE_E1 = 41.20
NOTE_C2 = 65.41
NOTE_G1 = 48.99

CHORD_MAP = [
    NOTE_A1, NOTE_A1, NOTE_F1, NOTE_G1, NOTE_A1,
    NOTE_A1, NOTE_D1, NOTE_F1, NOTE_E1,
    NOTE_A1, NOTE_F1, NOTE_C2, NOTE_G1, NOTE_A1,
    NOTE_A1, NOTE_F1, NOTE_D1, NOTE_G1, NOTE_E1, NOTE_A1,
    NOTE_F1, NOTE_G1, NOTE_A1, NOTE_C2, NOTE_G1,
    NOTE_F1, NOTE_G1, NOTE_E1, NOTE_A1,
    NOTE_F1, NOTE_G1, NOTE_A1, NOTE_F1, NOTE_G1, NOTE_A1
]

print("  -> Synthesizing rolling synthwave bassline & stereo harmonic pads...")
def synth_bass_note(freq, dur):
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    saw = (2.0 * (t * freq - np.floor(t * freq + 0.5)))
    sub = np.sin(2.0 * np.pi * (freq * 0.5) * t)
    cutoff = np.exp(-t * 12.0)
    sig = (saw * 0.55 * cutoff + sub * 0.45) * np.exp(-t * 6.0)
    return np.tanh(sig * 1.4) * 0.65

for bar_idx, root_f in enumerate(CHORD_MAP):
    bar_start_s = bar_idx * (4 * BEAT_LEN)
    for sixteenth_idx in range(16):
        note_t = bar_start_s + (sixteenth_idx * SIXTEENTH)
        note_s_idx = int(note_t * SAMPLE_RATE)
        if note_s_idx >= NUM_SAMPLES: break
        f = root_f * 2.0 if (sixteenth_idx % 4 == 2) else root_f
        b_sample = synth_bass_note(f, SIXTEENTH * 0.9)
        mix_sample(music_L, b_sample, note_s_idx, 0.60)
        mix_sample(music_R, b_sample, note_s_idx, 0.60)

# --- 4. STEREO ARPEGGIO & SYNTH LEAD ---
print("  -> Generating melodic cyberpunk arpeggios & chord progressions...")
def synth_lead_note(freq, dur, pan=0.0):
    n = int(SAMPLE_RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    sq = np.sign(np.sin(2.0 * np.pi * freq * t)) * 0.3
    saw = (2.0 * (t * freq - np.floor(t * freq + 0.5))) * 0.4
    env = np.exp(-t * 8.0) * (1.0 - np.exp(-t * 120.0))
    sig = (sq + saw) * env * 0.28
    gain_L = math.cos((pan + 1.0) * math.pi / 4.0)
    gain_R = math.sin((pan + 1.0) * math.pi / 4.0)
    return sig * gain_L, sig * gain_R

ARP_OFFSETS = [1.0, 1.2, 1.5, 2.0, 1.5, 1.2, 1.0, 0.75]
for beat in range(140):
    bar = beat // 4
    if bar >= len(CHORD_MAP): break
    root = CHORD_MAP[bar] * 4.0
    for sub in range(4):
        note_idx = beat * 4 + sub
        note_t = note_idx * SIXTEENTH
        s_idx = int(note_t * SAMPLE_RATE)
        if s_idx >= NUM_SAMPLES: break
        offset = ARP_OFFSETS[note_idx % len(ARP_OFFSETS)]
        f = root * offset
        pan = 0.5 * math.sin(note_idx * 0.8)
        lead_L, lead_R = synth_lead_note(f, SIXTEENTH * 1.5, pan=pan)
        mix_sample(music_L, lead_L, s_idx, 0.65)
        mix_sample(music_R, lead_R, s_idx, 0.65)

# Smooth Outro Fade Out (last 3 seconds)
fade_len = int(SAMPLE_RATE * 3.0)
fade_start = NUM_SAMPLES - fade_len
fade_env = np.linspace(1.0, 0.0, fade_len)
music_L[fade_start:] *= fade_env
music_R[fade_start:] *= fade_env

peak = max(np.max(np.abs(music_L)), np.max(np.abs(music_R)), 1e-4)
music_L = (music_L / peak) * 0.82
music_R = (music_R / peak) * 0.82

# --- 5. NATURAL HUMAN VOICE-OVER (SAMANTHA @ 162 WPM) ---
print("==> Synthesizing Voice-Over with Apple Natural Voice (Samantha @ 162 WPM)...")

VOICE_SCRIPT = [
    (1, 0.6, "Welcome to Anti-Lag Shield version 1.0. A passive XNU kernel resident for iOS and iPadOS with zero percent CPU overhead."),
    (2, 10.6, "Unlike traditional tweaks that run battery-draining background daemons, Anti-Lag Shield operates passively at the kernel layer."),
    (3, 19.1, "Here is live footage of the native app on an iPad, dynamically shifting between 4K streaming and instant ACK zero-latency gaming."),
    (4, 30.0, "You get three convenient quick-toggle options: a native Control Center module, an interactive notification banner with pull-down buttons, and one-tap Siri Shortcuts."),
    (5, 41.5, "Hardware Static ARP Lock binds your router gateway into the Darwin kernel while completely protecting your private IP and MAC address."),
    (6, 51.5, "The Mach memory purge frees inactive RAM without triggering Jetsam, while the flash cleaner safely trims stale diagnostic logs."),
    (7, 60.0, "Anti-Lag Shield is free and open source on GitHub by NightKnight24, and available on Sileo and Zebra. Check the description to install.")
]

voice_L = np.zeros(NUM_SAMPLES, dtype=np.float32)
voice_R = np.zeros(NUM_SAMPLES, dtype=np.float32)
speech_mask = np.zeros(NUM_SAMPLES, dtype=np.float32)

for idx, start_sec, text in VOICE_SCRIPT:
    aiff_f = f"/tmp/scene_voice_{idx}.aiff"
    wav_f = f"/tmp/scene_voice_{idx}.wav"
    subprocess.run(["say", "-v", "Samantha", "-r", "162", "-o", aiff_f, text], check=True)
    subprocess.run(["ffmpeg", "-y", "-i", aiff_f, "-ar", "44100", "-ac", "1", wav_f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    
    with wave.open(wav_f, "rb") as wf:
        v_bytes = wf.readframes(wf.getnframes())
        v_data = np.frombuffer(v_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        
    s_idx = int(start_sec * SAMPLE_RATE)
    e_idx = min(s_idx + len(v_data), NUM_SAMPLES)
    sz = e_idx - s_idx
    if sz > 0:
        voice_L[s_idx:e_idx] += v_data[:sz] * 0.95
        voice_R[s_idx:e_idx] += v_data[:sz] * 0.95
        speech_mask[s_idx:e_idx] = 1.0

# --- 6. AUTOMATIC SIDECHAIN DUCKING ---
print("==> Applying Sidechain Compression (Music automatically ducks under voiceover)...")
kernel_sz = int(SAMPLE_RATE * 0.22)
kernel = np.ones(kernel_sz) / kernel_sz
smoothed_speech = np.convolve(speech_mask, kernel, mode="same")
smoothed_speech = np.clip(smoothed_speech * 2.5, 0.0, 1.0)

duck_curve = 0.85 - (smoothed_speech * 0.63)
music_L *= duck_curve
music_R *= duck_curve

# --- 7. MASTER MIX ---
master_L = music_L + voice_L
master_R = music_R + voice_R

master_peak = max(np.max(np.abs(master_L)), np.max(np.abs(master_R)), 1e-4)
if master_peak > 0.95:
    master_L = (master_L / master_peak) * 0.95
    master_R = (master_R / master_peak) * 0.95

interleaved = np.empty((NUM_SAMPLES * 2,), dtype=np.int16)
interleaved[0::2] = np.clip(master_L * 32767.0, -32768, 32767).astype(np.int16)
interleaved[1::2] = np.clip(master_R * 32767.0, -32768, 32767).astype(np.int16)

master_audio_path = "/tmp/master_soundtrack_with_voice.wav"
with wave.open(master_audio_path, "wb") as wf:
    wf.setnchannels(2)
    wf.setsampwidth(2)
    wf.setframerate(SAMPLE_RATE)
    wf.writeframes(interleaved.tobytes())

print(f"==> Master soundtrack generated: {master_audio_path} ({os.path.getsize(master_audio_path)/(1024*1024):.1f} MB)")
