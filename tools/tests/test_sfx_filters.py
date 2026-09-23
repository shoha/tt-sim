"""Unit tests for the filter and noise helpers."""

import math
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sfx_synth as s


def _rms(samples):
    if not samples:
        return 0.0
    return math.sqrt(sum(v * v for v in samples) / len(samples))


class TestOnePoleLowPass(unittest.TestCase):
    def test_passes_low_frequencies(self):
        signal = s.tone(200.0, (1.0,), 44100)
        filtered = s.one_pole_lp(signal, 6000.0)
        self.assertGreater(_rms(filtered), 0.8 * _rms(signal))

    def test_attenuates_high_frequencies(self):
        signal = s.tone(12000.0, (1.0,), 44100)
        filtered = s.one_pole_lp(signal, 1000.0)
        self.assertLess(_rms(filtered), 0.2 * _rms(signal))

    def test_preserves_length(self):
        self.assertEqual(len(s.one_pole_lp([0.1] * 500, 4000.0)), 500)

    def test_does_not_mutate_input(self):
        original = [0.5] * 100
        copy = list(original)
        s.one_pole_lp(original, 1000.0)
        self.assertEqual(original, copy)


class TestOnePoleHighPass(unittest.TestCase):
    def test_attenuates_low_frequencies(self):
        signal = s.tone(200.0, (1.0,), 44100)
        filtered = s.one_pole_hp(signal, 6000.0)
        self.assertLess(_rms(filtered), 0.2 * _rms(signal))

    def test_passes_high_frequencies(self):
        signal = s.tone(12000.0, (1.0,), 44100)
        filtered = s.one_pole_hp(signal, 1000.0)
        self.assertGreater(_rms(filtered), 0.8 * _rms(signal))


class TestNoiseBed(unittest.TestCase):
    def test_is_deterministic_for_a_seed(self):
        self.assertEqual(s.noise_bed(500, 7), s.noise_bed(500, 7))

    def test_differs_between_seeds(self):
        self.assertNotEqual(s.noise_bed(500, 7), s.noise_bed(500, 8))

    def test_is_darker_than_white_noise(self):
        bed = s.noise_bed(44100, 1, cutoff_hz=2000.0)
        high = s.one_pole_hp(bed, 8000.0)
        self.assertLess(_rms(high), 0.1 * _rms(bed))

    def test_length_matches_request(self):
        self.assertEqual(len(s.noise_bed(321, 3)), 321)


if __name__ == "__main__":
    unittest.main()
