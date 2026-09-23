#!/usr/bin/env python3
"""Measurement helpers that turn "soft and warm" into assertable numbers.

Standard library only. No FFT is needed: high-band energy is measured with a
two-pole high-pass and an RMS ratio, which is accurate enough to catch a sound
that has drifted bright.
"""

import math
from collections import deque
from typing import Sequence

from sfx_synth import SAMPLE_RATE, one_pole_hp


def rms(samples: Sequence[float]) -> float:
    """Root mean square amplitude."""
    if not samples:
        return 0.0
    return math.sqrt(sum(v * v for v in samples) / len(samples))


def peak_dbfs(samples: Sequence[float]) -> float:
    """Absolute peak in dB relative to full scale."""
    peak = max((abs(v) for v in samples), default=0.0)
    if peak == 0.0:
        return float("-inf")
    return 20.0 * math.log10(peak)


def amplitude_envelope(
    samples: Sequence[float], window_ms: float = 5.0, sample_rate: int = SAMPLE_RATE
) -> list[float]:
    """Sliding-window RMS. Smooths the oscillation out of an amplitude reading."""
    width = max(1, int(round(window_ms * sample_rate / 1000.0)))
    out = []
    window: deque = deque()
    total = 0.0
    for value in samples:
        squared = value * value
        window.append(squared)
        total += squared
        if len(window) > width:
            total -= window.popleft()
        out.append(math.sqrt(max(0.0, total) / len(window)))
    return out


def attack_time_ms(
    samples: Sequence[float], sample_rate: int = SAMPLE_RATE
) -> float:
    """Time for the amplitude envelope to first reach 90 percent of its maximum.

    This is the number that distinguishes "soft" from "sharp". A sampled UI
    click typically measures under 2 ms; the palette targets 9 ms or more.
    """
    envelope_values = amplitude_envelope(samples, sample_rate=sample_rate)
    peak = max(envelope_values, default=0.0)
    if peak <= 0.0:
        return 0.0
    threshold = 0.9 * peak
    for index, value in enumerate(envelope_values):
        if value >= threshold:
            return index * 1000.0 / sample_rate
    return 0.0


def high_band_ratio_db(
    samples: Sequence[float], cutoff_hz: float = 6000.0
) -> float:
    """RMS of the high-passed signal relative to the full-band RMS, in dB.

    The high-pass is applied twice (12 dB per octave). A single pole rolls off
    too gently to discriminate: an E5 fundamental at 659 Hz still measures
    about -18 dB through one pole, which would fail a -20 dB warmth target even
    though the sound is demonstrably warm.

    Measured through two poles on this implementation: E5 sits at -35 dB, a
    110 Hz token thump at -67 dB, and a bright 9 kHz sine at -7.5 dB. The
    discrete filter attenuates more than the analog RC response predicts (0.65
    per pole at 9 kHz rather than 0.83), so the bright end lands near -7.5 dB
    and not the -3 dB the continuous-time formula suggests.
    """
    full = rms(samples)
    if full == 0.0:
        return float("-inf")
    high = rms(one_pole_hp(one_pole_hp(samples, cutoff_hz), cutoff_hz))
    if high == 0.0:
        return float("-inf")
    return 20.0 * math.log10(high / full)


def duration_ms(samples: Sequence[float], sample_rate: int = SAMPLE_RATE) -> float:
    """Length of the buffer in milliseconds."""
    return len(samples) * 1000.0 / sample_rate
