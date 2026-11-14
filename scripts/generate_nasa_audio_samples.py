import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100


def write_wav_mono(path: str, samples: list[float]) -> int:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = bytearray()
    for s in samples:
        clamped = max(-0.98, min(0.98, s))
        pcm.extend(struct.pack("<h", int(round(clamped * 32767.0))))
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(bytes(pcm))
    return os.path.getsize(path)


def raised_cosine_env(i: int, n: int, attack_s: float = 0.005, release_s: float = 0.008) -> float:
    att = max(1, int(attack_s * SAMPLE_RATE))
    rel = max(1, int(release_s * SAMPLE_RATE))
    if i < att:
        return 0.5 * (1.0 - math.cos(math.pi * i / att))
    if i > n - rel:
        rem = max(0, n - i)
        return 0.5 * (1.0 - math.cos(math.pi * rem / rel))
    return 1.0


def synth_vab_snap() -> list[float]:
    # 0.12s crisp mechanical latch transient + confirmation harmonic (880 Hz + 1320 Hz)
    dur = 0.12
    n = int(dur * SAMPLE_RATE)
    rng = random.Random(1969)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        # Short mechanical click impulse in first 18ms
        click = (rng.uniform(-1.0, 1.0) * math.exp(-t / 0.0045)) * 0.45
        latch_thump = math.sin(2.0 * math.pi * 190.0 * t) * math.exp(-t / 0.012) * 0.45
        # Clean avionics confirmation harmonic
        tone = (
            0.34 * math.sin(2.0 * math.pi * 880.0 * t)
            + 0.22 * math.sin(2.0 * math.pi * 1320.0 * t)
        ) * math.exp(-max(0.0, t - 0.008) / 0.032)
        env = raised_cosine_env(i, n, 0.001, 0.015)
        samples.append((click + latch_thump + tone) * env * 0.72)
    return samples


def synth_quindar_beep() -> list[float]:
    # 0.25s authentic Apollo/DSN Quindar tone (2525 Hz intro -> 2475 Hz outro)
    dur = 0.25
    n = int(dur * SAMPLE_RATE)
    half = n // 2
    samples = []
    phase = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 2525.0 if i < half else 2475.0
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        # Subtle 15ms silent gap between dual Quindar tones? No, continuous or brief dip:
        if half - int(0.008 * SAMPLE_RATE) <= i <= half + int(0.008 * SAMPLE_RATE):
            gap_env = 0.25
        else:
            gap_env = 1.0
        env = raised_cosine_env(i, n, 0.006, 0.012) * gap_env
        # Add subtle VHF radio warmth (soft harmonic)
        sig = 0.85 * math.sin(phase) + 0.06 * math.sin(2.0 * phase)
        samples.append(sig * env * 0.36)
    return samples


def synth_ui_hover_tick() -> list[float]:
    # 0.04s subtle micro-tick (1800 Hz damped sine)
    dur = 0.04
    n = int(dur * SAMPLE_RATE)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        sig = math.sin(2.0 * math.pi * 1800.0 * t) * math.exp(-t / 0.008)
        env = raised_cosine_env(i, n, 0.001, 0.008)
        samples.append(sig * env * 0.24)
    return samples


def synth_thruster_burn() -> list[float]:
    # 1.20s loopable low-frequency rocket thruster rumble (45-260 Hz band-limited noise + 62 Hz resonance)
    dur = 1.20
    n = int(dur * SAMPLE_RATE)
    rng = random.Random(2026)

    # Generate extra samples for seamless overlap-add crossfade looping
    xfade = int(0.15 * SAMPLE_RATE)
    total = n + xfade
    raw = [rng.uniform(-1.0, 1.0) for _ in range(total)]

    # Cascaded single-pole IIR low-pass & DC-blocking high-pass (approx 45 Hz - 260 Hz)
    lp1 = 0.0
    lp2 = 0.0
    hp_prev_in = 0.0
    hp_prev_out = 0.0
    alpha_lp = (2.0 * math.pi * 240.0 / SAMPLE_RATE) / (1.0 + 2.0 * math.pi * 240.0 / SAMPLE_RATE)
    alpha_hp = 1.0 / (1.0 + 2.0 * math.pi * 42.0 / SAMPLE_RATE)

    filtered = [0.0] * total
    for i in range(total):
        x = raw[i]
        lp1 += alpha_lp * (x - lp1)
        lp2 += alpha_lp * (lp1 - lp2)
        hp_out = alpha_hp * (hp_prev_out + lp2 - hp_prev_in)
        hp_prev_in = lp2
        hp_prev_out = hp_out
        t = i / SAMPLE_RATE
        # Add subtle chamber fundamental & subharmonic synchronized to loop length
        f_base = round(62.0 * dur) / dur
        chamber = 0.22 * math.sin(2.0 * math.pi * f_base * t) + 0.14 * math.sin(2.0 * math.pi * (2.0 * f_base) * t)
        filtered[i] = hp_out * 2.8 + chamber

    # Crossfade tail into head for click-free loop
    samples = filtered[:n]
    for i in range(xfade):
        w = i / float(xfade)
        samples[i] = samples[i] * w + filtered[n + i] * (1.0 - w)

    # Normalize gently
    peak = max(abs(v) for v in samples) or 1.0
    gain = 0.42 / peak
    return [v * gain for v in samples]


def synth_spe_alarm() -> list[float]:
    # 0.45s dual-tone aerospace Master Caution alert (800 Hz / 1000 Hz alternating)
    dur = 0.45
    n = int(dur * SAMPLE_RATE)
    seg = n // 3
    samples = []
    phase = 0.0
    for i in range(n):
        freq = 980.0 if (i // max(1, seg // 2)) % 2 == 0 else 760.0
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        # Smooth tone gating at transitions
        pulse_pos = (i % max(1, seg // 2)) / float(max(1, seg // 2))
        pulse_env = 1.0
        if pulse_pos < 0.06:
            pulse_env = pulse_pos / 0.06
        elif pulse_pos > 0.92:
            pulse_env = (1.0 - pulse_pos) / 0.08
        sig = 0.72 * math.sin(phase) + 0.24 * math.sin(2.0 * phase)
        env = raised_cosine_env(i, n, 0.005, 0.015) * pulse_env
        samples.append(sig * env * 0.44)
    return samples


def synth_touchdown_confirm() -> list[float]:
    # 0.35s dual ascending harmonic chime (D5 587.33 Hz -> A5 880.0 Hz)
    dur = 0.35
    n = int(dur * SAMPLE_RATE)
    split = int(0.14 * SAMPLE_RATE)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        # First note
        n1 = (
            0.70 * math.sin(2.0 * math.pi * 587.33 * t)
            + 0.20 * math.sin(2.0 * math.pi * 1174.66 * t)
        ) * math.exp(-t / 0.11)
        # Second ascending note overlapping cleanly
        n2 = 0.0
        if i >= split:
            t2 = (i - split) / SAMPLE_RATE
            att2 = min(1.0, t2 / 0.005)
            n2 = (
                0.75 * math.sin(2.0 * math.pi * 880.0 * t2)
                + 0.22 * math.sin(2.0 * math.pi * 1760.0 * t2)
            ) * math.exp(-t2 / 0.14) * att2
        env = raised_cosine_env(i, n, 0.004, 0.025)
        samples.append((n1 + n2) * env * 0.45)
    return samples


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    godot_subdir = os.path.join(project_root, "space-app-challenge-2026---astra-rex")
    audio_base = godot_subdir if os.path.isdir(godot_subdir) else project_root
    audio_dir = os.path.join(audio_base, "assets", "audio")
    os.makedirs(audio_dir, exist_ok=True)

    outputs = {
        "vab_snap.wav": synth_vab_snap(),
        "quindar_beep.wav": synth_quindar_beep(),
        "ui_hover_tick.wav": synth_ui_hover_tick(),
        "thruster_burn.wav": synth_thruster_burn(),
        "spe_alarm.wav": synth_spe_alarm(),
        "touchdown_confirm.wav": synth_touchdown_confirm(),
    }

    total_bytes = 0
    for name, data in outputs.items():
        path = os.path.join(audio_dir, name)
        sz = write_wav_mono(path, data)
        total_bytes += sz
        print(f"[WAV] {name}: {len(data) / SAMPLE_RATE:.2f}s | {sz / 1024.0:.1f} KB")

    print(f"[TOTAL] {len(outputs)} WAV files | {total_bytes / 1024.0:.1f} KB (< 400 KB budget)")


if __name__ == "__main__":
    main()
