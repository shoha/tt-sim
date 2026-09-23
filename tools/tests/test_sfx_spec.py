"""Tests that the declared palette obeys its own design rules."""

import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sfx_spec
import sfx_synth as s

REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
AUDIO_MANAGER = os.path.join(REPO_ROOT, "autoloads", "audio_manager.gd")


def _gdscript_dict_keys(source: str, var_name: str) -> set:
    match = re.search(r"var %s := \{(.*?)\n\}" % re.escape(var_name), source, re.S)
    if match is None:
        raise AssertionError("could not find %s in audio_manager.gd" % var_name)
    body = re.sub(r"#.*", "", match.group(1))
    return set(re.findall(r'"([a-z_]+)"\s*:', body))


class TestPaletteCoverage(unittest.TestCase):
    def test_has_eighteen_sounds(self):
        self.assertEqual(len(sfx_spec.SPECS), 18)

    def test_covers_every_sound_audio_manager_expects(self):
        with open(AUDIO_MANAGER, "r", encoding="utf-8") as handle:
            source = handle.read()
        expected = _gdscript_dict_keys(source, "_ui_sounds") | _gdscript_dict_keys(
            source, "_sfx_sounds"
        )
        self.assertEqual(set(sfx_spec.SPECS), expected)

    def test_bus_matches_audio_manager_grouping(self):
        with open(AUDIO_MANAGER, "r", encoding="utf-8") as handle:
            source = handle.read()
        for name in _gdscript_dict_keys(source, "_ui_sounds"):
            self.assertEqual(sfx_spec.SPECS[name].bus, "ui", name)
        for name in _gdscript_dict_keys(source, "_sfx_sounds"):
            self.assertEqual(sfx_spec.SPECS[name].bus, "sfx", name)


class TestPaletteRules(unittest.TestCase):
    def test_every_attack_meets_the_minimum(self):
        for name, spec in sfx_spec.SPECS.items():
            self.assertGreaterEqual(spec.attack_ms, sfx_spec.MIN_ATTACK_MS, name)

    def test_every_note_is_in_the_pentatonic_scale(self):
        for name, spec in sfx_spec.SPECS.items():
            for note in spec.notes:
                self.assertIn(note[:1], sfx_spec.PENTATONIC, "%s: %s" % (name, note))

    def test_every_note_parses(self):
        for name, spec in sfx_spec.SPECS.items():
            for note in spec.notes:
                s.note_to_freq(note)

    def test_harmonics_fall_off(self):
        for name, spec in sfx_spec.SPECS.items():
            weights = spec.harmonics
            for earlier, later in zip(weights, weights[1:]):
                self.assertGreaterEqual(earlier, later, name)

    def test_noise_mix_is_a_fraction(self):
        for name, spec in sfx_spec.SPECS.items():
            self.assertGreaterEqual(spec.noise_mix, 0.0, name)
            self.assertLessEqual(spec.noise_mix, 1.0, name)

    def test_open_and_close_are_mirrors(self):
        opened = sfx_spec.SPECS["open"]
        closed = sfx_spec.SPECS["close"]
        self.assertEqual(opened.sweep_semitones, -closed.sweep_semitones)
        self.assertGreater(opened.sweep_semitones, 0.0)

    def test_splash_pair_are_mirrors(self):
        enter = sfx_spec.SPECS["splash_enter"]
        exit_spec = sfx_spec.SPECS["splash_exit"]
        self.assertEqual(enter.sweep_semitones, -exit_spec.sweep_semitones)
        self.assertGreater(enter.sweep_semitones, 0.0)

    def test_no_sound_plays_a_note_sequence(self):
        # Note sequences read as little tunes rather than interface feedback.
        # Motion belongs in a pitch glide within one struck note. A chord is
        # one event played at once, so it is exempt.
        for name, spec in sfx_spec.SPECS.items():
            if spec.chord:
                continue
            self.assertLessEqual(len(spec.notes), 1, name)

    def test_total_ms_accounts_for_every_note(self):
        spec = sfx_spec.SPECS["success"]
        self.assertAlmostEqual(
            spec.total_ms, len(spec.notes) * (spec.note_ms + spec.gap_ms), places=6
        )

    def test_chorded_sound_is_one_note_long(self):
        spec = sfx_spec.SPECS["error"]
        self.assertTrue(spec.chord)
        self.assertAlmostEqual(spec.total_ms, spec.note_ms, places=6)


if __name__ == "__main__":
    unittest.main()
