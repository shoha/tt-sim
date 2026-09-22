"""Unit tests for the SFX synthesis engine."""

import math
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sfx_synth as s


class TestNoteToFreq(unittest.TestCase):
    def test_a4_is_440(self):
        self.assertAlmostEqual(s.note_to_freq("A4"), 440.0, places=6)

    def test_a2_is_110(self):
        self.assertAlmostEqual(s.note_to_freq("A2"), 110.0, places=6)

    def test_e4_is_concert_e(self):
        self.assertAlmostEqual(s.note_to_freq("E4"), 329.6275569, places=5)

    def test_octave_doubles_frequency(self):
        self.assertAlmostEqual(s.note_to_freq("C5"), 2.0 * s.note_to_freq("C4"), places=6)

    def test_unknown_letter_raises(self):
        with self.assertRaises(ValueError):
            s.note_to_freq("H4")


class TestRaisedCosineRamp(unittest.TestCase):
    def test_starts_at_zero_ends_at_one(self):
        ramp = s.raised_cosine_ramp(100)
        self.assertAlmostEqual(ramp[0], 0.0, places=9)
        self.assertAlmostEqual(ramp[-1], 1.0, places=9)

    def test_is_monotonic(self):
        ramp = s.raised_cosine_ramp(100)
        for a, b in zip(ramp, ramp[1:]):
            self.assertLessEqual(a, b)

    def test_initial_slope_is_near_zero(self):
        # This is the whole point of a raised cosine: a linear ramp has a
        # constant slope of 1/n at the onset, which the ear hears as a tick.
        n = 1000
        ramp = s.raised_cosine_ramp(n)
        linear_slope = 1.0 / (n - 1)
        self.assertLess(ramp[1] - ramp[0], linear_slope * 0.05)

    def test_zero_length_is_empty(self):
        self.assertEqual(s.raised_cosine_ramp(0), [])


class TestEnvelope(unittest.TestCase):
    def test_length_matches_request(self):
        env = s.envelope(1000, 100, 500.0, 50)
        self.assertEqual(len(env), 1000)

    def test_peaks_at_end_of_attack(self):
        env = s.envelope(1000, 100, 500.0, 50)
        self.assertAlmostEqual(max(env), 1.0, places=6)
        self.assertEqual(env.index(max(env)), 99)

    def test_is_continuous_at_attack_boundary(self):
        env = s.envelope(1000, 100, 500.0, 50)
        self.assertLess(abs(env[99] - env[100]), 0.01)

    def test_ends_at_silence(self):
        env = s.envelope(1000, 100, 500.0, 50)
        self.assertAlmostEqual(env[-1], 0.0, places=9)


class TestTone(unittest.TestCase):
    def test_length_matches_request(self):
        self.assertEqual(len(s.tone(440.0, (1.0,), 512)), 512)

    def test_pure_sine_stays_in_unit_range(self):
        samples = s.tone(440.0, (1.0,), 4410)
        self.assertLessEqual(max(abs(x) for x in samples), 1.0001)

    def test_sweep_lowers_final_frequency(self):
        # A falling sweep must cross zero fewer times than a static tone.
        n = 22050
        static = s.tone(440.0, (1.0,), n, sweep_semitones=0.0)
        falling = s.tone(440.0, (1.0,), n, sweep_semitones=-12.0)
        self.assertLess(_zero_crossings(falling), _zero_crossings(static))


class TestPeakNormalize(unittest.TestCase):
    def test_hits_target_exactly(self):
        out = s.peak_normalize([0.1, -0.05, 0.02], target_dbfs=-3.0)
        peak = max(abs(x) for x in out)
        self.assertAlmostEqual(20.0 * math.log10(peak), -3.0, places=6)

    def test_silence_is_left_alone(self):
        self.assertEqual(s.peak_normalize([0.0, 0.0]), [0.0, 0.0])


class TestWavRoundTrip(unittest.TestCase):
    def test_round_trip_preserves_samples(self):
        original = s.peak_normalize(s.tone(440.0, (1.0,), 1000))
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.wav")
            s.render_wav(path, original)
            restored, rate = s.read_wav(path)
        self.assertEqual(rate, s.SAMPLE_RATE)
        self.assertEqual(len(restored), len(original))
        for a, b in zip(original, restored):
            self.assertLess(abs(a - b), 1.0 / 256.0)

    def test_written_file_is_mono_16_bit(self):
        import wave
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.wav")
            s.render_wav(path, [0.0] * 100)
            with wave.open(path, "rb") as handle:
                self.assertEqual(handle.getnchannels(), 1)
                self.assertEqual(handle.getsampwidth(), 2)
                self.assertEqual(handle.getframerate(), 44100)


def _zero_crossings(samples):
    return sum(1 for a, b in zip(samples, samples[1:]) if (a < 0.0) != (b < 0.0))


if __name__ == "__main__":
    unittest.main()
