#!/usr/bin/env python3
"""Pure-function synthesis engine for the game's sound effect palette.

Standard library only. No numpy, no scipy, no soundfile.

The design goal is "soft and warm". Softness is a property of the attack
envelope, not of the spectrum: a linear ramp still has a discontinuity in its
first derivative at onset, which the ear hears as a tick. Every envelope here
uses a raised cosine so the slope starts and ends at zero.
"""

import array
import math
import random
import sys
import wave
from typing import Sequence

SAMPLE_RATE = 44100

# Matches the peak target of tools/normalize_audio.py so the pre-commit hook
# finds generated files already within tolerance and leaves them untouched.
PEAK_TARGET_DBFS = -3.0

# C major pentatonic. Semitone offsets from C within an octave.
NOTE_SEMITONES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_to_freq(name: str) -> float:
    """Convert a scientific pitch name such as 'E4' to a frequency in Hz."""
    letter = name[:1].upper()
    if letter not in NOTE_SEMITONES:
        raise ValueError("unknown note letter: %r" % name)
    try:
        octave = int(name[1:])
    except ValueError:
        raise ValueError("unparseable octave: %r" % name)
    midi = 12 * (octave + 1) + NOTE_SEMITONES[letter]
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def ms_to_samples(ms: float) -> int:
    """Convert milliseconds to a whole number of samples."""
    return int(round(ms * SAMPLE_RATE / 1000.0))


def raised_cosine_ramp(n: int) -> list[float]:
    """An n-sample ramp from 0 to 1 whose slope is zero at both ends."""
    if n <= 0:
        return []
    if n == 1:
        return [1.0]
    return [0.5 - 0.5 * math.cos(math.pi * i / (n - 1)) for i in range(n)]


def envelope(total: int, attack: int, decay_tau: float, release: int) -> list[float]:
    """Raised-cosine attack, exponential decay, raised-cosine release.

    decay_tau is in samples. The release is applied as a multiplicative fade
    over the final `release` samples so the tail reaches exact silence.
    """
    if total <= 0:
        return []
    attack = max(0, min(attack, total))
    out = raised_cosine_ramp(attack)
    tau = max(1.0, decay_tau)
    out.extend(math.exp(-i / tau) for i in range(total - attack))

    release = max(0, min(release, total))
    if release > 0:
        fade = list(reversed(raised_cosine_ramp(release)))
        start = total - release
        out = [v * fade[i - start] if i >= start else v for i, v in enumerate(out)]
    return out


def tone(
    freq: float,
    harmonics: Sequence[float],
    n: int,
    sweep_semitones: float = 0.0,
) -> list[float]:
    """An additive sine stack, optionally glided by sweep_semitones over its length.

    Warmth comes from few harmonics weighted steeply downward. Phase is
    accumulated per sample so a frequency sweep stays continuous.
    """
    if n <= 0:
        return []
    out = [0.0] * n
    total_weight = sum(abs(w) for w in harmonics) or 1.0
    for index, weight in enumerate(harmonics, start=1):
        if weight == 0.0:
            continue
        phase = 0.0
        for i in range(n):
            position = i / (n - 1) if n > 1 else 0.0
            current = freq * (2.0 ** (sweep_semitones * position / 12.0)) * index
            phase += 2.0 * math.pi * current / SAMPLE_RATE
            out[i] += weight * math.sin(phase)
    return [v / total_weight for v in out]


def peak_normalize(
    samples: Sequence[float], target_dbfs: float = PEAK_TARGET_DBFS
) -> list[float]:
    """Scale samples so their absolute peak sits at target_dbfs."""
    peak = max((abs(v) for v in samples), default=0.0)
    if peak == 0.0:
        return list(samples)
    gain = (10.0 ** (target_dbfs / 20.0)) / peak
    return [v * gain for v in samples]


def render_wav(path, samples: Sequence[float], sample_rate: int = SAMPLE_RATE) -> None:
    """Write samples to a 16-bit mono WAV file."""
    frames = array.array(
        "h", (int(max(-1.0, min(1.0, v)) * 32767.0) for v in samples)
    )
    if sys.byteorder == "big":
        frames.byteswap()
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(frames.tobytes())


def read_wav(path) -> tuple[list[float], int]:
    """Read a 16-bit mono WAV file into floats in [-1, 1] plus its sample rate."""
    with wave.open(str(path), "rb") as handle:
        if handle.getsampwidth() != 2:
            raise ValueError("expected 16-bit audio: %s" % path)
        channels = handle.getnchannels()
        rate = handle.getframerate()
        raw = handle.readframes(handle.getnframes())
    frames = array.array("h")
    frames.frombytes(raw)
    if sys.byteorder == "big":
        frames.byteswap()
    values = [v / 32768.0 for v in frames]
    if channels > 1:
        values = [
            sum(values[i : i + channels]) / channels
            for i in range(0, len(values), channels)
        ]
    return values, rate


def one_pole_lp(
    samples: Sequence[float], cutoff_hz: float, sample_rate: int = SAMPLE_RATE
) -> list[float]:
    """Single-pole low-pass. Rolls off brightness without ringing."""
    dt = 1.0 / sample_rate
    rc = 1.0 / (2.0 * math.pi * max(1.0, cutoff_hz))
    alpha = dt / (rc + dt)
    out = []
    y = 0.0
    for value in samples:
        y += alpha * (value - y)
        out.append(y)
    return out


def one_pole_hp(
    samples: Sequence[float], cutoff_hz: float, sample_rate: int = SAMPLE_RATE
) -> list[float]:
    """Single-pole high-pass. Used for measuring high-band energy, not for tone."""
    dt = 1.0 / sample_rate
    rc = 1.0 / (2.0 * math.pi * max(1.0, cutoff_hz))
    alpha = rc / (rc + dt)
    out = []
    previous_input = 0.0
    y = 0.0
    for value in samples:
        y = alpha * (y + value - previous_input)
        previous_input = value
        out.append(y)
    return out


def noise_bed(n: int, seed: int, cutoff_hz: float = 2000.0) -> list[float]:
    """Low-passed white noise, deterministic for a given seed.

    Provides the breath and material texture that a pure sine stack lacks.
    """
    generator = random.Random(seed)
    raw = [generator.uniform(-1.0, 1.0) for _ in range(n)]
    return one_pole_lp(raw, cutoff_hz)
