#!/usr/bin/env python3
"""Renders the three timer sounds the website synthesizes with WebAudio
(recipe.html playBeep) into WAV files, so they can also be used as
notification sounds. Run from the ios/ directory."""
import math
import struct
import wave

SR = 44100
OUT = "Recipes/Resources/Sounds"


def render(notes, total):
    n = int(SR * total)
    buf = [0.0] * n
    for freq, start, dur, g0 in notes:
        for i in range(int(dur * SR)):
            t = i / SR
            # exponentialRampToValueAtTime(0.001) from g0 over dur
            g = g0 * (0.001 / g0) ** (t / dur)
            j = int(start * SR) + i
            if j < n:
                buf[j] += g * math.sin(2 * math.pi * freq * t)
    k = 0.85 / max(abs(x) for x in buf)
    return b"".join(struct.pack("<h", int(x * k * 32767)) for x in buf)


SOUNDS = {
    "bell": ([(880, o, 0.4, 0.3) for o in (0, 0.55, 1.1)], 1.6),
    "beep": ([(440, 0, 0.6, 0.4)], 0.7),
    "melody": ([(f, i * 0.25, 0.3, 0.3) for i, f in enumerate((523, 659, 784))], 0.9),
}

for name, (notes, total) in SOUNDS.items():
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(render(notes, total))
    print("wrote", name)
