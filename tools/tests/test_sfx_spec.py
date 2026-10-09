"""Tests that the declared palette obeys its own design rules."""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import generate_sfx
import sfx_spec
import sfx_synth as s

REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
AUDIO_ROOT = os.path.join(REPO_ROOT, "assets", "audio")


def _installed_wavs() -> set:
    """(bus, name) for every .wav committed under assets/audio/<bus>/."""
    found = set()
    for bus in generate_sfx.GODOT_BUS:
        bus_dir = os.path.join(AUDIO_ROOT, bus)
        for filename in os.listdir(bus_dir):
            if filename.endswith(".wav"):
                found.add((bus, filename[: -len(".wav")]))
    return found


class TestPaletteCoverage(unittest.TestCase):
    """The spec, the installed files and the committed manifest name the same sounds.

    The count is derived from the spec, so adding a sound means adding its
    SoundSpec and running --install, not editing a number here.
    """

    def test_every_spec_has_exactly_one_installed_file(self):
        expected = {(spec.bus, name) for name, spec in sfx_spec.SPECS.items()}
        self.assertEqual(_installed_wavs(), expected)

    def test_committed_manifest_matches_the_spec(self):
        with open(generate_sfx.manifest_path(REPO_ROOT), "r", encoding="utf-8") as handle:
            manifest = json.load(handle)
        self.assertEqual(
            manifest["sounds"],
            generate_sfx.build_manifest(),
            "run tools/generate_sfx.py --manifest after editing tools/sfx_spec.py",
        )

    def test_every_bus_is_known(self):
        for name, spec in sfx_spec.SPECS.items():
            self.assertIn(spec.bus, generate_sfx.GODOT_BUS, name)


class TestPlaybackFields(unittest.TestCase):
    def test_priority_is_a_declared_tier(self):
        for name, spec in sfx_spec.SPECS.items():
            self.assertIn(spec.priority, sfx_spec.PRIORITIES, name)

    def test_an_outcome_outranks_the_panel_and_the_click_of_its_gesture(self):
        # Confirm + close (a dialog's OK) and click + confirm + close (a picker's
        # choose) must each play only the confirm.
        specs = sfx_spec.SPECS
        self.assertGreater(specs["confirm"].priority, specs["close"].priority)
        self.assertGreater(specs["close"].priority, specs["click"].priority)
        self.assertGreater(specs["click"].priority, specs["tick"].priority)
        self.assertGreater(specs["error"].priority, specs["success"].priority)

    def test_tick_jitter_stays_within_half_a_semitone(self):
        # tick plays constantly against the pentatonic notes around it; a wider
        # jitter (it was +-12%, about +-2 semitones) lands between scale notes.
        self.assertLessEqual(sfx_spec.SPECS["tick"].pitch_jitter, 0.5)

    def test_no_sound_jitters_by_more_than_a_semitone(self):
        # token_whoosh is exempt: it is off, and its pitch follows drag speed.
        for name, spec in sfx_spec.SPECS.items():
            if name == "token_whoosh":
                continue
            self.assertLessEqual(spec.pitch_jitter, 1.0, name)
            self.assertGreaterEqual(spec.pitch_jitter, 0.0, name)

    def test_cooldowns_are_short_and_non_negative(self):
        for name, spec in sfx_spec.SPECS.items():
            self.assertGreaterEqual(spec.cooldown_s, 0.0, name)
            self.assertLess(spec.cooldown_s, 1.0, name)


class TestPaletteRules(unittest.TestCase):
    def test_attacks_are_bimodal(self):
        # Quick interaction sounds onset almost instantly; deliberate ones swell.
        # The two chords are exempt: a chord's perceived onset is set by how its
        # notes beat against each other, not by its declared attack, so they sit
        # between the two groups by construction.
        quick = {
            "hover", "click", "tick", "token_hover",
            "token_drop", "token_pickup", "splash_enter", "splash_exit",
        }
        for name in quick:
            self.assertGreaterEqual(sfx_spec.SPECS[name].attack_ms, 1.5, name)
            self.assertLessEqual(sfx_spec.SPECS[name].attack_ms, 10.0, name)
        deliberate = {"confirm", "cancel", "leave_game", "open", "close"}
        for name in deliberate:
            self.assertGreaterEqual(sfx_spec.SPECS[name].attack_ms, 40.0, name)
        for name in ("error", "success"):
            self.assertTrue(sfx_spec.SPECS[name].chord, name)

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
        # "success" is now a chord (total_ms collapses to note_ms), so this
        # checks the plain multi-note formula against an ordinary, single-note
        # non-chord sound instead.
        spec = sfx_spec.SPECS["click"]
        self.assertAlmostEqual(
            spec.total_ms, len(spec.notes) * (spec.note_ms + spec.gap_ms), places=6
        )

    def test_chorded_sound_is_one_note_long(self):
        spec = sfx_spec.SPECS["error"]
        self.assertTrue(spec.chord)
        self.assertAlmostEqual(spec.total_ms, spec.note_ms, places=6)


if __name__ == "__main__":
    unittest.main()
