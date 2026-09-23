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

    def test_printed_order_matches_the_audio(self):
        # The human judges this palette by listening to a sheet while reading
        # its printed order. If the two ever drift apart, the judgement is made
        # on the wrong evidence and nothing else in this suite would notice.
        for bus in ("ui", "sfx"):
            samples, names = cli.build_sheet(bus, seed=0)
            envelope = m.amplitude_envelope(samples)
            peak = max(envelope)
            gap = cli.ms_to_samples(cli.SHEET_GAP_MS)
            cursor = 0
            for index, name in enumerate(names):
                if index > 0:
                    # Measure the middle of the gap. The sliding RMS window
                    # still holds the previous sound's tail at the gap's
                    # leading edge, so the edges are not a fair test of silence.
                    low = cursor + gap // 10
                    high = cursor + (gap * 9) // 10
                    self.assertLess(
                        max(envelope[low:high]),
                        0.001 * peak,
                        "%s: gap before %s is not silent" % (bus, name),
                    )
                    cursor += gap
                length = cli.ms_to_samples(sfx_spec.SPECS[name].total_ms)
                region = envelope[cursor:cursor + length]
                self.assertTrue(
                    region, "%s: %s runs past the end of the sheet" % (bus, name)
                )
                self.assertGreater(
                    max(region),
                    0.05 * peak,
                    "%s: %s region is silent" % (bus, name),
                )
                cursor += length
            self.assertLess(
                abs(len(samples) - cursor),
                3,
                "%s: sheet length does not match the sum of its parts" % bus,
            )


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
