"""Tests for the generate_sfx command line interface."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import generate_sfx as cli
import sfx_spec


class TestGenerate(unittest.TestCase):
    def test_writes_one_file_per_sound_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            written = cli.generate(tmp, only=[], variants=1, seed=0)
            self.assertEqual(len(written), len(sfx_spec.SPECS))
            for path in written:
                self.assertTrue(os.path.isfile(path))

    def test_variant_zero_is_named_without_a_suffix(self):
        with tempfile.TemporaryDirectory() as tmp:
            cli.generate(tmp, only=["click"], variants=1, seed=0)
            self.assertTrue(os.path.isfile(os.path.join(tmp, "click.wav")))

    def test_extra_variants_are_suffixed(self):
        with tempfile.TemporaryDirectory() as tmp:
            written = cli.generate(tmp, only=["click"], variants=3, seed=0)
            self.assertEqual(len(written), 3)
            names = sorted(os.path.basename(p) for p in written)
            self.assertEqual(names, ["click.v1.wav", "click.v2.wav", "click.wav"])

    def test_only_filters_to_named_sounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            written = cli.generate(tmp, only=["click", "error"], variants=1, seed=0)
            self.assertEqual(len(written), 2)

    def test_unknown_name_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(SystemExit):
                cli.generate(tmp, only=["nope"], variants=1, seed=0)


class TestParser(unittest.TestCase):
    def test_defaults(self):
        args = cli.build_parser().parse_args([])
        self.assertEqual(args.variants, 1)
        self.assertEqual(args.only, [])
        self.assertEqual(args.seed, 0)
        self.assertFalse(args.sheet)
        self.assertFalse(args.install)
        self.assertFalse(args.verify)

    def test_only_accepts_multiple_names(self):
        args = cli.build_parser().parse_args(["--only", "click", "error"])
        self.assertEqual(args.only, ["click", "error"])


class TestMain(unittest.TestCase):
    def test_returns_zero_on_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            code = cli.main(["--out", tmp, "--only", "click"])
            self.assertEqual(code, 0)
            self.assertTrue(os.path.isfile(os.path.join(tmp, "click.wav")))


if __name__ == "__main__":
    unittest.main()
