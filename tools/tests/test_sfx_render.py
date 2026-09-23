"""Acceptance tests: every declared sound renders soft, warm and correctly levelled."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sfx_measure as m
import sfx_render as r
import sfx_spec


class TestRenderedPaletteMeetsDesignTargets(unittest.TestCase):
    """The core gate. If these pass, the palette is soft and warm by measurement."""

    @classmethod
    def setUpClass(cls):
        cls.rendered = {
            name: r.render_spec(spec, seed=0)
            for name, spec in sfx_spec.SPECS.items()
        }

    def test_every_sound_honours_its_declared_attack(self):
        for name, samples in self.rendered.items():
            spec = sfx_spec.SPECS[name]
            measured = m.attack_time_ms(samples)
            low = r.ATTACK_BAND_LOW * spec.attack_ms
            high = spec.attack_ms + r.ATTACK_BAND_HIGH_MS
            self.assertGreaterEqual(measured, low, name)
            self.assertLessEqual(measured, high, name)

    def test_every_sound_is_warm_but_not_muffled(self):
        for name, samples in self.rendered.items():
            spec = sfx_spec.SPECS[name]
            ratio = m.high_band_ratio_db(samples)
            self.assertLessEqual(ratio, spec.max_high_band_db, name)
            self.assertGreaterEqual(
                ratio, spec.max_high_band_db - r.WARMTH_FLOOR_MARGIN_DB, name
            )

    def test_every_sound_hits_the_peak_target(self):
        low, high = r.PEAK_WINDOW_DBFS
        for name, samples in self.rendered.items():
            peak = m.peak_dbfs(samples)
            self.assertGreaterEqual(peak, low, name)
            self.assertLessEqual(peak, high, name)

    def test_every_sound_matches_its_declared_duration(self):
        for name, samples in self.rendered.items():
            expected = sfx_spec.SPECS[name].total_ms
            actual = m.duration_ms(samples)
            self.assertLess(
                abs(actual - expected) / expected, r.DURATION_TOLERANCE, name
            )

    def test_no_sound_clips(self):
        for name, samples in self.rendered.items():
            self.assertLessEqual(max(abs(v) for v in samples), 1.0, name)

    def test_every_sound_ends_in_silence(self):
        # The release fade plus the low-pass leave a tiny residual rather than
        # an exact zero; anything under a thousandth of full scale is inaudible
        # and proves the tail was not cut off abruptly.
        for name, samples in self.rendered.items():
            self.assertLess(abs(samples[-1]), 1e-3, name)


class TestDeterminism(unittest.TestCase):
    def test_same_seed_gives_identical_output(self):
        spec = sfx_spec.SPECS["token_drop"]
        self.assertEqual(r.render_spec(spec, seed=3), r.render_spec(spec, seed=3))

    def test_different_seed_changes_a_noisy_sound(self):
        spec = sfx_spec.SPECS["token_drop"]
        self.assertNotEqual(r.render_spec(spec, seed=3), r.render_spec(spec, seed=4))


class TestVariantSpec(unittest.TestCase):
    def test_index_zero_is_the_original(self):
        spec = sfx_spec.SPECS["click"]
        self.assertEqual(r.variant_spec(spec, 0), spec)

    def test_variants_differ_from_the_original(self):
        spec = sfx_spec.SPECS["click"]
        self.assertNotEqual(r.variant_spec(spec, 1), spec)

    def test_variants_keep_a_positive_attack(self):
        for spec in sfx_spec.SPECS.values():
            for index in range(4):
                self.assertGreater(r.variant_spec(spec, index).attack_ms, 0.0)

    def test_variants_are_deterministic(self):
        spec = sfx_spec.SPECS["click"]
        self.assertEqual(r.variant_spec(spec, 2), r.variant_spec(spec, 2))


if __name__ == "__main__":
    unittest.main()
