#!/usr/bin/env python3
"""Synthesises every sound in res://audio/ from scratch (original, released as CC0).

Needs numpy and ffmpeg (with libvorbis) on PATH:  python tools/gen_audio.py
Overwrites audio/sfx/*.ogg and audio/music/*.ogg. Edit a recipe below and rerun to retune.
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "audio"


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack=0.005, decay=8.0):
    """Fast attack, exponential decay."""
    t = np.arange(n) / SR
    return np.minimum(1.0, t / attack) * np.exp(-decay * t)


def tone(f0, dur, f1=None, wave_="sine", decay=8.0, attack=0.004, vol=1.0):
    """Pitch sweep f0 -> f1 with an exponential decay envelope."""
    t = t_axis(dur)
    f1 = f0 if f1 is None else f1
    f = f0 + (f1 - f0) * (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if wave_ == "sine":
        s = np.sin(ph)
    elif wave_ == "tri":
        s = 2 / np.pi * np.arcsin(np.sin(ph))
    elif wave_ == "square":
        s = np.sign(np.sin(ph)) * 0.5
    else:
        raise ValueError(wave_)
    return s * env(len(t), attack, decay) * vol


def noise(dur, decay=20.0, lowpass=0.3, seed=1, vol=1.0):
    rng = np.random.default_rng(seed)
    n = rng.standard_normal(int(SR * dur))
    k = max(1, int(1 / lowpass))  # crude moving-average low-pass
    n = np.convolve(n, np.ones(k) / k, mode="same")
    return n * env(len(n), 0.002, decay) * vol


def place(parts):
    """parts: [(start_seconds, signal)] -> mixed array."""
    end = max(int(s * SR) + len(x) for s, x in parts)
    out = np.zeros(end)
    for s, x in parts:
        i = int(s * SR)
        out[i:i + len(x)] += x
    return out


def bell(f, dur=0.5, vol=1.0):
    return (tone(f, dur, decay=7, vol=vol) + tone(f * 2.01, dur, decay=11, vol=0.35 * vol)
            + tone(f * 3.0, dur, decay=16, vol=0.15 * vol))


def pour():
    n = int(SR * 0.5)
    t = np.arange(n) / SR
    parts = [(0, noise(0.5, decay=4, lowpass=0.12, vol=0.5) * np.minimum(1, t / 0.05))]
    parts += [(0.05 * i + 0.03 * (i % 2), tone(320 + 90 * i, 0.09, 520 + 110 * i, decay=28, vol=0.3))
              for i in range(8)]
    return place(parts)


SFX = {
    "tap": lambda: tone(760, 0.07, 700, decay=40, vol=0.8),
    "button": lambda: place([(0, tone(520, 0.09, 460, wave_="tri", decay=30)),
                             (0, noise(0.02, decay=100, vol=0.25))]),
    "back": lambda: tone(620, 0.12, 400, wave_="tri", decay=22, vol=0.8),
    "select": lambda: place([(0, tone(660, 0.08, decay=30)), (0.06, tone(880, 0.12, decay=24))]),
    "place": lambda: place([(0, tone(200, 0.14, 80, decay=24)), (0, noise(0.04, decay=70, lowpass=0.2, vol=0.6))]),
    "pour": pour,
    "pop": lambda: tone(380, 0.14, 950, decay=26),
    "merge": lambda: place([(0, tone(440, 0.22, 660, decay=12)), (0.05, tone(880, 0.2, 1100, decay=14, vol=0.4))]),
    "clear": lambda: place([(i * 0.07, tone(f, 0.22, decay=12, wave_="tri"))
                            for i, f in enumerate([523, 659, 784, 1047])]),
    "star": lambda: bell(1046, 0.55),
    "win": lambda: place([(i * 0.11, bell(f, 0.5, 0.8))
                          for i, f in enumerate([523, 659, 784, 1047])] +
                         [(0.45, bell(1319, 0.7, 0.8))]),
    "fail": lambda: place([(0, tone(392, 0.25, 370, wave_="tri", decay=7)),
                           (0.2, tone(311, 0.4, 260, wave_="tri", decay=6))]),
    "locked": lambda: place([(0, tone(150, 0.09, 130, wave_="square", decay=25, vol=0.7)),
                             (0.11, tone(150, 0.09, 130, wave_="square", decay=25, vol=0.7))]),
    "unlock": lambda: place([(i * 0.06, bell(f, 0.3, 0.6)) for i, f in enumerate([784, 988, 1175, 1568])]),
    # air rush that swells then cuts (result stars flying in)
    "swoosh": lambda: highpass(noise(0.26, decay=3, lowpass=0.5, seed=9), 1400) * np.linspace(0.05, 1, int(SR * 0.26)) ** 2,
}

# --- Music: 80s synthwave loops (neon arcade). Detuned saw pads, pulsing octave bass, gated arps
# with echo, drum machine kick/snare/hats and a little FFT reverb. Every voice is rendered over the
# whole loop and the ringing tail wraps to the start, so the loop is seamless. -----------------------

NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(
    ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name, octave):
    return NOTE[name] * 2 ** (octave - 4)


def saw(f, dur, detune=0.0, vib=0.0, seed=0):
    """Naive sawtooth (the low-pass below tames the fizz); vib = vibrato depth in semitones."""
    t = t_axis(dur)
    ff = f * 2 ** (detune / 1200) * 2 ** (vib * np.sin(2 * np.pi * 5.5 * t) / 12)
    ph = np.cumsum(ff) / SR + np.random.default_rng(seed).random()
    return 2 * (ph % 1.0) - 1


def pulse(f, dur, width=0.3):
    ph = (np.arange(int(SR * dur)) * f / SR) % 1.0
    return np.where(ph < width, 1.0, -1.0) - (2 * width - 1)


def lowpass(x, cutoff, order=2):
    """Gentle FFT low-pass (Butterworth-like magnitude), fine for offline rendering."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(spec / np.sqrt(1 + (f / cutoff) ** (2 * order)), len(x))


def highpass(x, cutoff):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(spec * (f / cutoff) ** 2 / (1 + (f / cutoff) ** 2), len(x))


def adsr(n, a, d, s, r):
    """Attack/decay/sustain level/release in seconds over n samples (release ends the note)."""
    t = np.arange(n) / SR
    dur = n / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    return e * np.clip((dur - t) / max(r, 1e-4), 0, 1)


def reverb(x, seconds=1.6, mix=0.25, seed=7):
    """Convolution with a decaying noise burst: a big 80s plate on everything it touches."""
    rng = np.random.default_rng(seed)
    n = int(SR * seconds)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 5.0 / seconds)
    ir = lowpass(ir, 5000)
    size = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
    wet *= np.max(np.abs(x)) / (np.max(np.abs(wet)) or 1)
    out = np.zeros(size)
    out[:len(x)] += x * (1 - mix)
    return out + wet * mix


def echo(x, delay, feedback=0.4, taps=4):
    out = np.zeros(len(x) + int(delay * SR * taps))
    for k in range(taps + 1):
        i = int(k * delay * SR)
        out[i:i + len(x)] += x * feedback ** k
    return out


def kick():
    t = t_axis(0.35)
    f = 45 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = (np.sin(ph) + 0.35 * np.sin(2 * ph)) * np.exp(-t * 7)  # 2nd harmonic: audible on phones
    click = noise(0.01, decay=300, lowpass=0.5, vol=0.35)
    body[:len(click)] += click
    return body


def snare():
    return reverb(place([(0, highpass(noise(0.25, decay=14, lowpass=0.6, seed=3), 900) * 0.9),
                         (0, tone(190, 0.12, 160, decay=30, vol=0.5))]), 1.2, 0.45, seed=4)


def hat(open_=False):
    return highpass(noise(0.18 if open_ else 0.04, decay=14 if open_ else 90, lowpass=1.0, seed=5), 6000) * 0.5


def synthwave(bpm, chords, melody, seed, drums="full", lead_vol=0.22, arp_vol=0.11):
    """chords: per bar a list of (name, octave) notes, root first; melody: per bar 8 eighth-note slots
    ((name, octave) or None). drums: "full" (kick, gated snare, hats) or "soft" (kick + hats only)."""
    beat = 60 / bpm
    bar = 4 * beat
    total = bar * len(chords)
    pad_l, bass_l, arp_l, lead_l, drum_l = [], [], [], [], []
    for b, ch in enumerate(chords):
        t0 = b * bar
        for k, note in enumerate(ch):  # pad: three detuned saws per note, slow swell
            v = sum(saw(hz(*note), bar + 0.05, d, seed=seed + 10 * b + k + j) for j, d in enumerate((-9, 0, 9)))
            pad_l.append((t0, v * adsr(len(v), 0.35, 1.0, 0.8, 0.12) * 0.1))
        root = (ch[0][0], ch[0][1] - 1)
        for e in range(8):  # driving eighth-note octave bass
            note = root if e % 2 == 0 else (root[0], root[1] + 1)
            v = saw(hz(*note), beat / 2) + 0.5 * pulse(hz(*note) / 2, beat / 2, 0.5)
            bass_l.append((t0 + e * beat / 2, v * adsr(len(v), 0.004, 0.08, 0.5, 0.03) * 0.14))
        tones = [hz(*n) * 2 for n in ch] + [hz(*ch[0]) * 4]
        order = [0, 1, 2, 3, 2, 1, 2, 3]
        for s in range(16):  # sixteenth-note arpeggio, pulse wave
            f = tones[order[s % 8] % len(tones)]
            v = pulse(f, beat / 4 * 0.9, 0.25)
            arp_l.append((t0 + s * beat / 4, v * adsr(len(v), 0.002, 0.05, 0.25, 0.02) * arp_vol))
        for k in range(4):
            drum_l.append((t0 + k * beat, kick() * (0.9 if drums == "full" else 0.55)))
            if drums == "full" and k % 2 == 1:
                drum_l.append((t0 + k * beat, snare() * 0.55))
            for h in range(2):
                drum_l.append((t0 + k * beat + h * beat / 2, hat(open_=h == 1 and k == 3) * (0.35 if h else 0.2)))
    for b, slots in enumerate(melody):
        for s, note in enumerate(slots):
            if note is None:
                continue
            length = beat * (1.5 if s + 1 < 8 and slots[s + 1] is None else 0.5)
            f = hz(*note)
            v = saw(f, length, -6, vib=0.12) + saw(f, length, 6, vib=0.12) + 0.4 * pulse(f * 2, length, 0.5)
            lead_l.append((b * bar + s * beat / 2, v * adsr(len(v), 0.01, 0.25, 0.6, 0.06) * lead_vol))

    def bus(parts, cutoff, verb=0.0, delay=None):
        if not parts:
            return np.zeros(1)
        x = lowpass(place(parts), cutoff)
        if delay:
            x = echo(x, delay, 0.38, 4)
        if verb:
            x = reverb(x, 1.8, verb, seed)
        return x

    stems = [bus(pad_l, 1600, 0.35), bus(bass_l, 900), bus(arp_l, 2600, 0.25, beat * 0.75),
             bus(lead_l, 3200, 0.3, beat * 0.75), bus(drum_l, 9000)]
    n = int(SR * total)
    loop = np.zeros(n)
    for x in stems:
        x = x[:n * 2]
        loop[:min(n, len(x))] += x[:n]
        tail = x[n:]
        loop[:len(tail)] += tail  # wrap the ringing-out tail onto the start
    return np.tanh(loop * 1.4) / 1.4  # a touch of tape saturation glues it together


AM, F_, C_, G_ = ([("A", 3), ("C", 4), ("E", 4)], [("F", 3), ("A", 3), ("C", 4)],
                  [("C", 4), ("E", 4), ("G", 4)], [("G", 3), ("B", 3), ("D", 4)])
DM, BB, FM, CM = ([("D", 3), ("F", 3), ("A", 3)], [("A#", 2), ("D", 3), ("F", 3)],
                  [("F", 3), ("A", 3), ("C", 4)], [("C", 3), ("E", 3), ("G", 3)])

MUSIC = {
    # hub / menus: neon-lit synthwave drive, vi-IV-I-V with a singing saw lead
    "menu": lambda: synthwave(
        108, [AM, F_, C_, G_] * 2,
        [[("E", 5), None, None, ("A", 5), None, ("C", 6), None, ("B", 5)],
         [("A", 5), None, None, None, ("F", 5), None, ("A", 5), None],
         [("G", 5), None, None, ("E", 5), None, ("G", 5), None, ("C", 6)],
         [("B", 5), None, None, None, ("D", 6), None, None, None],
         [("E", 6), None, None, ("D", 6), None, ("C", 6), None, ("A", 5)],
         [("C", 6), None, None, None, ("A", 5), None, ("F", 5), None],
         [("G", 5), None, ("E", 5), None, ("G", 5), None, ("C", 6), None],
         [("B", 5), None, None, None, None, None, None, None]], 1),
    # in-game: same world, no snare or lead so it sits under the gameplay sounds
    "game": lambda: synthwave(100, [DM, BB, FM, CM] * 2, [], 2, drums="soft", arp_vol=0.13),
}


def write_ogg(signal, path, quality):
    signal = np.asarray(signal, dtype=np.float64)
    fade = int(SR * 0.004)
    signal[-fade:] *= np.linspace(1, 0, fade)  # no click at the end
    peak = np.max(np.abs(signal)) or 1.0
    pcm = (signal / peak * 0.85 * 32767).astype(np.int16)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        wav = Path(d) / "x.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis",
                        "-q:a", str(quality), "-map_metadata", "-1", str(path)], check=True)


def main():
    for name, fn in SFX.items():
        write_ogg(fn(), OUT / "sfx" / f"{name}.ogg", 3)
    for name, fn in MUSIC.items():
        sig = fn() * 0.8  # music sits quieter; Feedback also lowers its bus volume
        write_ogg(sig, OUT / "music" / f"{name}.ogg", 2)
    total = sum(p.stat().st_size for p in OUT.rglob("*.ogg"))
    print("wrote %d files, %.0f KB" % (len(list(OUT.rglob('*.ogg'))), total / 1024))


if __name__ == "__main__":
    main()
