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
}

# --- Music: soft looping pads + sparse plucks, pentatonic so nothing clashes -----------

NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(
    ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name, octave):
    return NOTE[name] * 2 ** (octave - 4)


def music(bpm, chords, melody, seed):
    """chords: list of (root, third, fifth) triples per bar (4 beats); melody: per bar, list of 8 eighth-note
    slots (note name/octave tuple or None). Renders seamlessly: the reverb tail wraps to the start."""
    beat = 60 / bpm
    bar = 4 * beat
    total = bar * len(chords)
    out = np.zeros(int(SR * (total + 2.0)))
    rng = np.random.default_rng(seed)
    for b, ch in enumerate(chords):
        for note in ch:
            pad = tone(hz(*note), bar + 0.8, wave_="tri", decay=0.7, attack=0.25, vol=0.16)
            i = int(b * bar * SR)
            out[i:i + len(pad)] += pad
        bass = tone(hz(ch[0][0], ch[0][1] - 1), beat * 2, wave_="sine", decay=2.5, vol=0.3)
        for k in (0, 2):
            i = int((b * bar + k * beat) * SR)
            out[i:i + len(bass)] += bass
    for b, slots in enumerate(melody):
        for s, note in enumerate(slots):
            if note is None:
                continue
            pl = place([(0, tone(hz(*note), 0.9, decay=4.5, vol=0.28)),
                        (0, tone(hz(*note) * 2, 0.5, decay=9, vol=0.06))])
            i = int((b * bar + s * beat / 2) * SR) + int(rng.integers(0, 300))
            out[i:i + len(pl)] += pl
    n = int(SR * total)
    loop = out[:n].copy()
    tail = out[n:]
    loop[:len(tail)] += tail  # wrap the ringing-out tail onto the start
    return loop


MUSIC = {
    # hub / menus: bright and easy
    "menu": lambda: music(
        96,
        [(("C", 3), ("E", 3), ("G", 3)), (("A", 2), ("C", 3), ("E", 3)),
         (("F", 2), ("A", 2), ("C", 3)), (("G", 2), ("B", 2), ("D", 3))] * 2,
        [[("E", 5), None, ("G", 5), None, ("C", 6), None, ("G", 5), None],
         [("A", 5), None, ("E", 5), None, ("C", 5), ("E", 5), None, None],
         [("C", 5), None, ("F", 5), None, ("A", 5), None, ("F", 5), None],
         [("G", 5), None, ("D", 5), None, ("B", 4), ("D", 5), None, None],
         [("E", 5), ("G", 5), None, ("C", 6), None, ("D", 6), None, None],
         [("C", 6), None, ("A", 5), None, ("E", 5), None, ("A", 5), None],
         [("F", 5), None, ("A", 5), ("C", 6), None, ("A", 5), None, None],
         [("D", 6), None, ("B", 5), None, ("G", 5), None, None, None]], 1),
    # in-game: calmer so it never fights the gameplay sounds
    "game": lambda: music(
        84,
        [(("D", 3), ("F", 3), ("A", 3)), (("A#", 2), ("D", 3), ("F", 3)),
         (("F", 2), ("A", 2), ("C", 3)), (("C", 3), ("E", 3), ("G", 3))] * 2,
        [[None, None, ("A", 4), None, None, None, ("D", 5), None],
         [("F", 5), None, None, None, ("D", 5), None, None, None],
         [None, None, ("C", 5), None, ("A", 4), None, None, None],
         [("E", 5), None, None, None, ("G", 4), None, None, None],
         [None, ("D", 5), None, ("F", 5), None, ("A", 5), None, None],
         [("F", 5), None, None, None, ("D", 5), None, ("A", 4), None],
         [None, None, ("C", 5), None, ("F", 5), None, ("E", 5), None],
         [("D", 5), None, None, None, None, None, None, None]], 2),
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
