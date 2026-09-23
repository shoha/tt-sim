"""Tests for the audition sheets."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import generate_sfx as cli
import sfx_measure as m
import sfx_spec
from sfx_synth import read_wav


class TestBuildSheet(unittest.TestCase):
    def test_ui_sheet_contains_every_ui_sound(self):
        _, names = cli.build_sheet("ui", seed=0)
        expected = [n for n, s in sfx_spec.SPECS.items() if s.bus == "ui"]
        self.assertEqual(sorted(names), sorted(expected))

    def test_sheet_is_long_enough_for_content_plus_gaps(self):
        samples, names = cli.build_sheet("ui", seed=0)
        content = sum(sfx_spec.SPECS[n].total_ms for n in names)
        minimum = content + (len(names) - 1) * cli.SHEET_GAP_MS
        self.assertGreaterEqual(m.duration_ms(samples) + 1.0, minimum)

    def test_sheet_does_not_clip(self):
        samples, _ = cli.build_sheet("sfx", seed=0)
        self.assertLessEqual(max(abs(v) for v in samples), 1.0)


class TestWriteSheets(unittest.TestCase):
    def test_writes_one_sheet_per_bus(self):
        with tempfile.TemporaryDirectory() as tmp:
            written = cli.write_sheets(tmp, seed=0, as_bus=False)
            names = sorted(os.path.basename(p) for p in written)
            self.assertEqual(names, ["sheet_sfx.wav", "sheet_ui.wav"])

    def test_sheets_are_readable_wav_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            for path in cli.write_sheets(tmp, seed=0, as_bus=False):
                samples, rate = read_wav(path)
                self.assertEqual(rate, 44100)
                self.assertGreater(len(samples), 44100)


class TestMainWiring(unittest.TestCase):
    def test_sheet_flag_produces_sheets(self):
        with tempfile.TemporaryDirectory() as tmp:
            code = cli.main(["--out", tmp, "--sheet"])
            self.assertEqual(code, 0)
            self.assertTrue(os.path.isfile(os.path.join(tmp, "sheet_ui.wav")))
            self.assertTrue(os.path.isfile(os.path.join(tmp, "sheet_sfx.wav")))


if __name__ == "__main__":
    unittest.main()
