"""Tests for the --verify gate."""

import dataclasses
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import generate_sfx as cli
import sfx_recording
import sfx_spec
from sfx_render import render_spec
from sfx_synth import ms_to_samples, peak_normalize, tone
from tests.test_sfx_recording import LOOP, RATE, noisy_fire


class TestVerifyPalette(unittest.TestCase):
    def test_the_declared_palette_passes(self):
        self.assertEqual(cli.verify_palette(), [])


class TestVerifySamples(unittest.TestCase):
    def test_a_sharp_sound_is_rejected(self):
        # A tone with no attack ramp at all: exactly what we are moving away from.
        sharp = peak_normalize(tone(440.0, (1.0,), ms_to_samples(150.0)))
        failures = cli.verify_samples("click", sharp)
        self.assertTrue(any("attack" in f for f in failures))

    def test_a_quiet_sound_is_rejected(self):
        quiet = [v * 0.01 for v in render_spec(sfx_spec.SPECS["click"])]
        failures = cli.verify_samples("click", quiet)
        self.assertTrue(any("peak" in f for f in failures))

    def test_a_compliant_sound_has_no_failures(self):
        good = render_spec(sfx_spec.SPECS["click"])
        self.assertEqual(cli.verify_samples("click", good), [])


class TestVerifyRecording(unittest.TestCase):
    """--verify checks a recorded loop's committed file: its seam and guard sample."""

    def setUp(self):
        self.loop = LOOP
        self.samples = sfx_recording.process_loop(noisy_fire(3.0, RATE), RATE, LOOP)

    def _failures(self, samples, rate=None):
        with mock.patch.dict(sfx_spec.RECORDINGS, {"fire_roar": self.loop}):
            return cli.verify_recording("fire_roar", samples, rate or self.loop.sample_rate)

    def test_a_click_at_the_seam_is_rejected(self):
        clicked = list(self.samples)
        clicked[-2] = clicked[0] + 0.35
        self.assertTrue(any("seam" in f for f in self._failures(clicked)))

    def test_a_missing_guard_sample_is_rejected(self):
        self.assertTrue(any("guard" in f for f in self._failures(self.samples[:-1])))

    def test_the_wrong_rate_is_rejected(self):
        self.assertTrue(any("Hz" in f for f in self._failures(self.samples, 48000)))

    def test_a_good_loop_has_no_seam_or_guard_failures(self):
        failures = self._failures(self.samples)
        self.assertFalse(any("seam" in f or "guard" in f for f in failures), failures)


class TestVerifyExitCode(unittest.TestCase):
    def test_verify_returns_zero_when_the_palette_is_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(cli.main(["--out", tmp, "--verify"]), 0)

    def test_verify_returns_one_when_a_sound_fails(self):
        # The exit code is the whole point of --verify. Declare an onset the
        # renderer cannot possibly honour - a 500 ms attack on a 58 ms sound,
        # which envelope() clamps to the sound's length - so the gate sees a
        # real mismatch between declaration and render.
        #
        # Note a tiny attack no longer works as the corruption here: the gate
        # checks a sound against its OWN declared attack, so declaring 0.1 ms
        # and rendering 0.3 ms is agreement, not failure.
        impossible = dataclasses.replace(sfx_spec.SPECS["click"], attack_ms=500.0)
        with mock.patch.dict(sfx_spec.SPECS, {"click": impossible}):
            with tempfile.TemporaryDirectory() as tmp:
                self.assertEqual(cli.main(["--out", tmp, "--verify"]), 1)


if __name__ == "__main__":
    unittest.main()
