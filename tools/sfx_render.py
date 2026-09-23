#!/usr/bin/env python3
"""Turns a SoundSpec into samples.

The acceptance thresholds live here rather than in the CLI so that the unit
tests and the --verify command apply exactly the same gate.
"""

import dataclasses
import random

from sfx_spec import SoundSpec
from sfx_synth import (
    PEAK_TARGET_DBFS,
    SAMPLE_RATE,
    envelope,
    ms_to_samples,
    noise_bed,
    note_to_freq,
    one_pole_lp,
    peak_normalize,
    tone,
)

# A sound must land near the attack it DECLARES, rather than clear one global
# floor. The band is asymmetric because a raised cosine reaches 90 percent at
# 79.5 percent of its length while the 5 ms RMS window used to measure attack
# lags a fast onset: a declared 2 ms attack measures near 3 ms, a declared
# 115 ms attack measures near 100 ms.
ATTACK_BAND_LOW = 0.6
ATTACK_BAND_HIGH_MS = 5.0

# Warmth is bounded from BOTH sides. The ceiling stops a sound drifting bright.
# The floor catches the opposite failure, which this project actually shipped
# once: a palette so dark it read as muffled rather than warm.
WARMTH_FLOOR_MARGIN_DB = 12.0

# Peak target of -3.0 dBFS with the same 1.5 dB tolerance the pre-commit
# normalizer uses, tightened to 1.0 dB because we control generation exactly.
PEAK_WINDOW_DBFS = (-4.0, -2.0)

DURATION_TOLERANCE = 0.2


def render_spec(spec: SoundSpec, seed: int = 0) -> list[float]:
    """Render one sound to peak-normalized mono samples."""
    attack = ms_to_samples(spec.attack_ms)
    release = ms_to_samples(spec.release_ms)
    decay_tau = max(1.0, spec.decay_tau_ms * SAMPLE_RATE / 1000.0)
    note_samples = ms_to_samples(spec.note_ms)
    gap_samples = ms_to_samples(spec.gap_ms)

    if spec.chord and spec.notes:
        layers = [
            tone(note_to_freq(name), spec.harmonics, note_samples, spec.sweep_semitones)
            for name in spec.notes
        ]
        mixed = [sum(values) / len(layers) for values in zip(*layers)]
        shape = envelope(note_samples, attack, decay_tau, release)
        body = [a * b for a, b in zip(mixed, shape)]
    else:
        names = spec.notes or ("",)
        stride = note_samples + gap_samples
        body = [0.0] * (len(names) * stride)
        tone_samples = (
            ms_to_samples(spec.tone_ms) if spec.tone_ms > 0.0 else note_samples
        )
        tone_samples = max(1, min(tone_samples, note_samples))
        shape = envelope(tone_samples, attack, decay_tau, release)
        for index, name in enumerate(names):
            if not name:
                continue
            voice = tone(
                note_to_freq(name), spec.harmonics, tone_samples, spec.sweep_semitones
            )
            start = index * stride
            for offset in range(tone_samples):
                body[start + offset] += voice[offset] * shape[offset]

    if spec.noise_mix > 0.0:
        delay = ms_to_samples(spec.noise_delay_ms)
        noise_length = max(1, len(body) - delay)
        bed = noise_bed(noise_length, seed, spec.noise_cutoff_hz)
        noise_attack = (
            ms_to_samples(spec.noise_attack_ms)
            if spec.noise_attack_ms > 0.0
            else attack
        )
        noise_tau = (
            spec.noise_decay_ms * SAMPLE_RATE / 1000.0
            if spec.noise_decay_ms > 0.0
            else decay_tau * 2.0
        )
        bed_shape = envelope(noise_length, noise_attack, max(1.0, noise_tau), release)
        mixed = list(body)
        for index in range(noise_length):
            position = delay + index
            if position < len(mixed):
                mixed[position] = (
                    (1.0 - spec.noise_mix) * mixed[position]
                    + spec.noise_mix * bed[index] * bed_shape[index]
                )
        body = mixed

    body = one_pole_lp(body, spec.lp_cutoff_hz)
    return peak_normalize(body, PEAK_TARGET_DBFS)


def variant_spec(spec: SoundSpec, index: int) -> SoundSpec:
    """Derive an audition variant by jittering attack and decay.

    Index 0 is always the declared spec, so variant 0 is what --install writes.
    """
    if index == 0:
        return spec
    generator = random.Random(index * 7919)
    attack = spec.attack_ms * generator.uniform(0.85, 1.25)
    decay = spec.decay_tau_ms * generator.uniform(0.8, 1.3)
    return dataclasses.replace(
        spec,
        attack_ms=max(1.0, attack),
        decay_tau_ms=decay,
    )
