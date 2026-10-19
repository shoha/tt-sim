#!/usr/bin/env python3
"""Turns an original recording into a palette loop (a RecordedLoop in sfx_spec),
or a recording's take into a one-shot (a RecordedShot's, process_shot).

Standard library only. No numpy, no scipy, no soundfile.

Every step is fixed by the spec, so the shipped file is reproducible from the
original: read it (16- or 24-bit PCM, mixed to mono), low-pass and halve the
rate down to the spec's `sample_rate` (the game's buses low-pass at 7 kHz, so
a 24 kHz file loses nothing audible at half the bytes), high-pass away the
rumble under `highpass_hz`, notch out a mains hum at `hum_hz`, trim to
`start_s`..`end_s`, fade the last `crossfade_ms` into the head at equal power,
and peak-normalize to the palette's target.

The crossfade is what makes the loop seamless: the head begins as the tail's
continuation and turns into the head over the overlap, so the loop's last
sample runs into its first as any two neighbours do. Godot's forward loop
wraps at the file's last frame (its import reads loop_end -1 as frames - 1,
measured in card F7), so one guard sample, a copy of the first, ends the file:
the loop plays every sample of the body and steps from its last to the guard
and then to the first, which are the same value.

The filters run over half a second before `start_s` (or what the original has
of it), so the trim cuts away their settling rather than the loop's head.
"""

import array
import math
import sys
import wave
from typing import Sequence

from sfx_synth import PEAK_TARGET_DBFS, peak_normalize

# Butterworth orders (two biquads each) and the notch's width.
HIGHPASS_ORDER = 4
LOWPASS_ORDER = 4
HUM_NOTCH_Q = 4.0

# The filters' run-in before the trim.
WARMUP_S = 0.5


def read_source(path) -> tuple[list[float], int]:
    """Read a 16- or 24-bit PCM WAV into mono floats in [-1, 1] and its rate."""
    with wave.open(str(path), "rb") as handle:
        width = handle.getsampwidth()
        channels = handle.getnchannels()
        rate = handle.getframerate()
        raw = handle.readframes(handle.getnframes())
    if width == 2:
        frames = array.array("h")
        frames.frombytes(raw)
        scale = 32768.0
    elif width == 3:
        # Each little-endian 3-byte sample into the top three bytes of a 32-bit
        # one, which carries its sign along.
        wide = bytearray(len(raw) // 3 * 4)
        wide[1::4] = raw[0::3]
        wide[2::4] = raw[1::3]
        wide[3::4] = raw[2::3]
        frames = array.array("i")
        frames.frombytes(bytes(wide))
        scale = 2147483648.0
    else:
        raise ValueError("expected 16- or 24-bit PCM: %s" % path)
    if sys.byteorder == "big":
        frames.byteswap()
    values = [v / scale for v in frames]
    if channels > 1:
        values = [
            sum(values[i : i + channels]) / channels
            for i in range(0, len(values), channels)
        ]
    return values, rate


def biquad(samples: Sequence[float], coefficients: tuple) -> list[float]:
    """Run one normalized biquad section (b0, b1, b2, a1, a2) from rest."""
    b0, b1, b2, a1, a2 = coefficients
    out = [0.0] * len(samples)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(samples):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out[i] = y
    return out


def section(kind: str, cutoff_hz: float, q: float, sample_rate: int) -> tuple:
    """One RBJ cookbook biquad: "low", "high" or "notch" at cutoff_hz with Q q."""
    w0 = 2.0 * math.pi * cutoff_hz / sample_rate
    cos_w0 = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    if kind == "low":
        b = ((1.0 - cos_w0) / 2.0, 1.0 - cos_w0, (1.0 - cos_w0) / 2.0)
    elif kind == "high":
        b = ((1.0 + cos_w0) / 2.0, -(1.0 + cos_w0), (1.0 + cos_w0) / 2.0)
    elif kind == "notch":
        b = (1.0, -2.0 * cos_w0, 1.0)
    else:
        raise ValueError("unknown section kind: %r" % kind)
    a0 = 1.0 + alpha
    return (b[0] / a0, b[1] / a0, b[2] / a0, -2.0 * cos_w0 / a0, (1.0 - alpha) / a0)


def butterworth(
    samples: Sequence[float], kind: str, cutoff_hz: float, order: int, sample_rate: int
) -> list[float]:
    """An even-order Butterworth low- or high-pass as a cascade of biquads."""
    out = list(samples)
    for k in range(order // 2):
        q = 1.0 / (2.0 * math.cos((2 * k + 1) * math.pi / (2 * order)))
        out = biquad(out, section(kind, cutoff_hz, q, sample_rate))
    return out


def crossfade_loop(samples: Sequence[float], overlap: int) -> list[float]:
    """Fade the last `overlap` samples into the first at equal power.

    The result is `overlap` samples shorter. Its first sample is the one that
    followed its last in the input, so played round it has no seam.
    """
    length = len(samples) - overlap
    if overlap <= 0 or length < overlap:
        raise ValueError("an overlap of %d does not fit %d samples" % (overlap, len(samples)))
    out = list(samples[:length])
    for i in range(overlap):
        t = 0.5 * math.pi * i / overlap
        out[i] = samples[i] * math.sin(t) + samples[length + i] * math.cos(t)
    return out


def process_loop(source: Sequence[float], rate: int, loop) -> list[float]:
    """The loop file's samples (body plus guard) at loop.sample_rate. Pure.

    `loop` is a sfx_spec.RecordedLoop; `source` and `rate` are read_source's.
    """
    if rate % loop.sample_rate != 0:
        raise ValueError("%d Hz does not divide into %d Hz" % (rate, loop.sample_rate))
    begin = int(round(loop.start_s * rate))
    end = int(round(loop.end_s * rate))
    if not 0 <= begin < end <= len(source):
        raise ValueError("%.2f-%.2f s is outside the recording" % (loop.start_s, loop.end_s))
    factor = rate // loop.sample_rate
    first = max(0, begin - int(round(WARMUP_S * rate)))
    first += (begin - first) % factor  # the trim lands on a kept sample
    run = list(source[first:end])
    if factor > 1:
        run = butterworth(run, "low", loop.lowpass_hz, LOWPASS_ORDER, rate)[::factor]
    run = butterworth(run, "high", loop.highpass_hz, HIGHPASS_ORDER, loop.sample_rate)
    if loop.hum_hz > 0.0:
        run = biquad(run, section("notch", loop.hum_hz, HUM_NOTCH_Q, loop.sample_rate))
    trimmed = run[(begin - first) // factor :]
    overlap = int(round(loop.crossfade_ms * loop.sample_rate / 1000.0))
    body = peak_normalize(crossfade_loop(trimmed, overlap), PEAK_TARGET_DBFS)
    return body + body[:1]


def fade_edges(samples: Sequence[float], fade_in: int, fade_out: int) -> list[float]:
    """Raised-cosine fades over the first `fade_in` and the last `fade_out` samples."""
    out = list(samples)
    count = len(out)
    for i in range(min(fade_in, count)):
        out[i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade_in)
    for i in range(min(fade_out, count)):
        out[count - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade_out)
    return out


def process_shot(source: Sequence[float], rate: int, take, shot) -> list[float]:
    """One take's file samples at shot.sample_rate. Pure.

    `take` is a sfx_spec.Take of `source` (read_source's samples at `rate`) and
    `shot` its sfx_spec.RecordedShot: low-pass and halve the rate, high-pass,
    trim to the take, fade both edges, peak-normalize. The filters run in
    before the take as for a loop, so the trim cuts away their settling.
    """
    if rate % shot.sample_rate != 0:
        raise ValueError("%d Hz does not divide into %d Hz" % (rate, shot.sample_rate))
    begin = int(round(take.start_s * rate))
    end = min(len(source), int(round(take.end_s * rate)))
    if not 0 <= begin < end:
        raise ValueError("%.2f-%.2f s is outside the recording" % (take.start_s, take.end_s))
    factor = rate // shot.sample_rate
    first = max(0, begin - int(round(WARMUP_S * rate)))
    first += (begin - first) % factor
    run = butterworth(source[first:end], "low", shot.lowpass_hz, LOWPASS_ORDER, rate)[::factor]
    run = butterworth(run, "high", shot.highpass_hz, HIGHPASS_ORDER, shot.sample_rate)
    trimmed = run[(begin - first) // factor :]
    per_ms = shot.sample_rate / 1000.0
    faded = fade_edges(
        trimmed, int(round(shot.fade_in_ms * per_ms)), int(round(shot.fade_out_ms * per_ms))
    )
    return peak_normalize(faded, PEAK_TARGET_DBFS)
