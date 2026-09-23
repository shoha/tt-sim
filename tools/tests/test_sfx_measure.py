"""Unit tests for the audio measurement helpers."""

import math
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sfx_measure as m
import sfx_synth as s


class TestPeakDbfs(unittest.TestCase):
    def test_full_scale_is_zero_db(self):
        self.assertAlmostEqual(m.peak_dbfs([1.0, -0.5]), 0.0, places=6)

    def test_half_scale_is_minus_six_db(self):
        self.assertAlmostEqual(m.peak_dbfs([0.5]), -6.0206, places=3)

    def test_silence_is_negative_infinity(self):
        self.assertEqual(m.peak_dbfs([0.0, 0.0]), float("-inf"))


class TestAttackTime(unittest.TestCase):
    def test_soft_attack_measures_near_expected(self):
        # 40 ms raised-cosine attack reaches 90 percent at about 0.795 * 40 ms.
        n = s.ms_to_samples(400.0)
        attack = s.ms_to_samples(40.0)
        signal = [
            a * b
            for a, b in zip(
                s.tone(330.0, (1.0,), n), s.envelope(n, attack, 4000.0, 220)
            )
        ]
        measured = m.attack_time_ms(signal)
        self.assertGreater(measured, 25.0)
        self.assertLess(measured, 55.0)

    def test_instant_attack_measures_near_zero(self):
        n = s.ms_to_samples(400.0)
        signal = [
            a * b
            for a, b in zip(s.tone(330.0, (1.0,), n), s.envelope(n, 1, 4000.0, 220))
        ]
        self.assertLess(m.attack_time_ms(signal), 5.0)

    def test_twelve_ms_attack_clears_the_nine_ms_floor(self):
        n = s.ms_to_samples(200.0)
        attack = s.ms_to_samples(12.0)
        signal = [
            a * b
            for a, b in zip(
                s.tone(330.0, (1.0,), n), s.envelope(n, attack, 2000.0, 220)
            )
        ]
        self.assertGreaterEqual(m.attack_time_ms(signal), 9.0)

    def test_silence_returns_zero(self):
        self.assertEqual(m.attack_time_ms([0.0] * 1000), 0.0)


class TestHighBandRatio(unittest.TestCase):
    def test_low_tone_is_well_below_threshold(self):
        signal = s.tone(330.0, (1.0, 0.3, 0.08), 44100)
        self.assertLess(m.high_band_ratio_db(signal), -20.0)

    def test_bright_tone_is_above_threshold(self):
        # A 9 kHz sine measures -7.5 dB through the two-pole high-pass. The
        # warmest palette sound measures -67 dB and the least warm -16.6 dB,
        # so -10 dB sits clear of both sides.
        signal = s.tone(9000.0, (1.0,), 44100)
        self.assertGreater(m.high_band_ratio_db(signal), -10.0)

    def test_silence_returns_negative_infinity(self):
        self.assertEqual(m.high_band_ratio_db([0.0] * 1000), float("-inf"))


class TestDuration(unittest.TestCase):
    def test_one_second_of_samples(self):
        self.assertAlmostEqual(m.duration_ms([0.0] * 44100), 1000.0, places=6)


class TestAmplitudeEnvelope(unittest.TestCase):
    def test_length_matches_input(self):
        self.assertEqual(len(m.amplitude_envelope([0.1] * 5000)), 5000)

    def test_is_non_negative(self):
        env = m.amplitude_envelope(s.tone(440.0, (1.0,), 5000))
        self.assertTrue(all(v >= 0.0 for v in env))


if __name__ == "__main__":
    unittest.main()
