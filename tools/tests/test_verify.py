"""Tests for the --verify gate."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import generate_sfx as cli
import sfx_spec
from sfx_render import render_spec
from sfx_synth import ms_to_samples, peak_normalize, tone


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


class TestVerifyExitCode(unittest.TestCase):
    def test_verify_returns_zero_when_the_palette_is_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(cli.main(["--out", tmp, "--verify"]), 0)


if __name__ == "__main__":
    unittest.main()
