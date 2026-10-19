"""Tests for sfx_recording: an original recording processed into a seamless loop.

The originals here are a few seconds written on the spot, so the tests never
need the real recording (kept out of git) and run in about a second.
"""

import array
import dataclasses
import math
import os
import random
import sys
import tempfile
import unittest
import wave

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sfx_measure as m
import sfx_recording as rec
import sfx_spec
from sfx_render import LOOP_SEAM_MAX_RATIO, PEAK_WINDOW_DBFS
from sfx_synth import one_pole_lp

RATE = 48000

# The roar's processing over 2 s of a 3 s original, with a shorter crossfade.
LOOP = dataclasses.replace(
    sfx_spec.RECORDINGS["fire_roar"], start_s=0.5, end_s=2.5, crossfade_ms=100.0
)


def write_source(path, samples, rate, channels=1, width=3):
    """Write mono samples as a 16- or 24-bit PCM WAV, copied to every channel."""
    if width == 2:
        frames = array.array("h", (int(v * 32767.0) for v in samples for _ in range(channels)))
        if sys.byteorder == "big":
            frames.byteswap()
        raw = frames.tobytes()
    else:
        raw = b"".join(
            int(v * 8388607.0).to_bytes(3, "little", signed=True) * channels for v in samples
        )
    with wave.open(path, "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(width)
        handle.setframerate(rate)
        handle.writeframes(raw)


def noisy_fire(seconds, rate, seed=0):
    """Low-passed noise standing in for a fire's roar."""
    generator = random.Random(seed)
    raw = [generator.uniform(-1.0, 1.0) for _ in range(int(seconds * rate))]
    return [0.6 * v for v in one_pole_lp(raw, 800.0, rate)]


def sine(freq, seconds, rate, amplitude):
    return [
        amplitude * math.sin(2.0 * math.pi * freq * i / rate)
        for i in range(int(seconds * rate))
    ]


def amplitude_at(samples, freq, rate):
    """The amplitude of the sinusoid at freq (a single-bin DFT, Goertzel)."""
    coefficient = 2.0 * math.cos(2.0 * math.pi * freq / rate)
    s1 = s2 = 0.0
    for value in samples:
        s1, s2 = value + coefficient * s1 - s2, s1
    power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
    return 2.0 * math.sqrt(max(0.0, power)) / len(samples)


class TestReadSource(unittest.TestCase):
    def test_reads_24_bit_and_mixes_to_mono(self):
        values = [0.5, -0.25, -1.0 + 1e-6, 0.0, 0.125]
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "stereo.wav")
            write_source(path, values, RATE, channels=2)
            samples, rate = rec.read_source(path)
        self.assertEqual(rate, RATE)
        self.assertEqual(len(samples), len(values))
        for got, want in zip(samples, values):
            self.assertAlmostEqual(got, want, places=5)

    def test_reads_16_bit(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "mono.wav")
            write_source(path, [0.5, -0.5], RATE, width=2)
            samples, _ = rec.read_source(path)
        self.assertAlmostEqual(samples[0], 0.5, places=3)
        self.assertAlmostEqual(samples[1], -0.5, places=3)


class TestProcessLoop(unittest.TestCase):
    def test_trims_to_the_range_at_the_spec_rate_with_one_guard_sample(self):
        out = rec.process_loop(noisy_fire(3.0, RATE), RATE, LOOP)
        body = round(LOOP.total_ms * LOOP.sample_rate / 1000.0)
        self.assertEqual(len(out), body + 1)
        self.assertEqual(out[-1], out[0], "the guard sample is the first")
        low, high = PEAK_WINDOW_DBFS
        self.assertTrue(low <= m.peak_dbfs(out) <= high, "normalized to the palette's peak")

    def test_the_lead_in_is_cut(self):
        # A loud 300 Hz lead-in before start_s, then the fire: none of the tone is left.
        source = sine(300.0, 0.5, RATE, 0.9) + noisy_fire(2.5, RATE)
        out = rec.process_loop(source, RATE, LOOP)
        self.assertLess(amplitude_at(out, 300.0, LOOP.sample_rate), 0.1 * m.rms(out))

    def test_the_high_pass_and_notch_take_the_hum_and_keep_the_body(self):
        hum = sine(50.0, 3.0, RATE, 0.3)
        body = sine(250.0, 3.0, RATE, 0.3)
        source = [a + b for a, b in zip(hum, body)]
        for loop, least_db in ((LOOP, 30.0), (dataclasses.replace(LOOP, hum_hz=0.0), 10.0)):
            out = rec.process_loop(source, RATE, loop)
            kept = amplitude_at(out, 250.0, loop.sample_rate)
            left = amplitude_at(out, 50.0, loop.sample_rate)
            self.assertGreater(20.0 * math.log10(kept / left), least_db, loop.hum_hz)

    def test_the_loop_joins_its_start_without_a_click(self):
        out = rec.process_loop(noisy_fire(3.0, RATE, seed=4), RATE, LOOP)
        body = out[:-1]
        self.assertLessEqual(m.loop_seam_ratio(body), LOOP_SEAM_MAX_RATIO)
        # 50 ms either side of the seam, against the loop's own 100 ms windows.
        width = LOOP.sample_rate // 10
        levels = [m.rms(body[i : i + width]) for i in range(0, len(body) - width + 1, width)]
        seam = m.rms(body[-width // 2 :] + body[: width // 2])
        self.assertGreaterEqual(seam, min(levels))
        self.assertLessEqual(seam, max(levels))

    def test_a_jump_at_the_seam_is_caught(self):
        body = rec.process_loop(noisy_fire(3.0, RATE), RATE, LOOP)[:-1]
        body[-1] = body[0] + 0.35
        self.assertGreater(m.loop_seam_ratio(body), LOOP_SEAM_MAX_RATIO)

    def test_processing_is_reproducible(self):
        source = noisy_fire(3.0, RATE, seed=2)
        self.assertEqual(rec.process_loop(source, RATE, LOOP), rec.process_loop(source, RATE, LOOP))

    def test_a_range_outside_the_recording_is_refused(self):
        with self.assertRaises(ValueError):
            rec.process_loop(noisy_fire(1.0, RATE), RATE, LOOP)


class TestCrossfade(unittest.TestCase):
    def test_the_head_continues_the_tail(self):
        samples = [float(v) for v in range(10)]
        out = rec.crossfade_loop(samples, 3)
        self.assertEqual(len(out), 7)
        self.assertEqual(out[0], samples[7], "the first sample follows the last")
        self.assertEqual(out[3:], samples[3:7], "past the overlap, the input as it was")

    def test_equal_power_holds_the_level_of_uncorrelated_noise(self):
        generator = random.Random(1)
        noise = [generator.uniform(-1.0, 1.0) for _ in range(48000)]
        out = rec.crossfade_loop(noise, 12000)
        head = m.rms(out[4000:8000])
        self.assertAlmostEqual(head / m.rms(noise), 1.0, delta=0.05)


class TestProcessShot(unittest.TestCase):
    """A take of an original becomes a short faded one-shot at the shot's rate."""

    SHOT = sfx_spec.SHOTS["plant_tick"]

    def _take(self, start_s, end_s):
        return sfx_spec.Take("foliage_1", start_s, end_s)

    def test_rate_length_peak_and_silent_edges(self):
        source = noisy_fire(3.0, 44100)
        out = rec.process_shot(source, 44100, self._take(1.0, 1.2), self.SHOT)
        self.assertEqual(len(out), int(round(0.2 * self.SHOT.sample_rate)))
        low, high = PEAK_WINDOW_DBFS
        self.assertTrue(low <= m.peak_dbfs(out) <= high)
        # The fades start and end the take at rest: no click on either edge.
        self.assertLess(abs(out[0]), 1e-6)
        self.assertLess(abs(out[-1]), 0.01)

    def test_reproducible_and_refuses_a_range_outside(self):
        source = noisy_fire(1.0, 44100)
        take = self._take(0.2, 0.4)
        self.assertEqual(
            rec.process_shot(source, 44100, take, self.SHOT),
            rec.process_shot(source, 44100, take, self.SHOT),
        )
        with self.assertRaises(ValueError):
            rec.process_shot(source, 44100, self._take(2.0, 2.2), self.SHOT)
        with self.assertRaises(ValueError):
            rec.process_shot(source, 48000, take, self.SHOT)

    def test_fade_edges_is_raised_cosine(self):
        out = rec.fade_edges([1.0] * 100, 10, 20)
        self.assertEqual(out[0], 0.0)
        self.assertAlmostEqual(out[5], 0.5, places=6)
        self.assertEqual(out[50], 1.0)
        self.assertEqual(out[-1], 0.0)
        self.assertAlmostEqual(out[-11], 0.5, places=6)


if __name__ == "__main__":
    unittest.main()
