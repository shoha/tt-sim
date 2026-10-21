"""Tests for --install and --manifest.

Every install here passes a sources root of its own (an empty one unless the
test writes an original into it), so no test depends on whether this machine
holds a recorded loop's original or spends seconds processing it.
"""

import contextlib
import dataclasses
import io
import json
import os
import sys
import tempfile
import unittest
import wave
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import generate_sfx as cli
import sfx_spec
from sfx_synth import read_wav
from tests.test_sfx_recording import noisy_fire, write_source


def _make_fake_assets(root):
    for bus in ("ui", "sfx"):
        os.makedirs(os.path.join(root, "assets", "audio", bus), exist_ok=True)


class TestInstall(unittest.TestCase):
    def test_writes_every_sound_into_its_bus_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            _make_fake_assets(tmp)
            written, _, kept = cli.install(tmp, seed=0, sources_root=tmp)
            self.assertEqual(len(written), len(sfx_spec.SPECS))
            takes = sum(len(shot.takes) for shot in sfx_spec.SHOTS.values())
            self.assertEqual(
                len(kept), len(sfx_spec.RECORDINGS) + takes, "no originals here"
            )
            for name, spec in sfx_spec.SPECS.items():
                expected = os.path.join(
                    tmp, "assets", "audio", spec.bus, "%s.wav" % name
                )
                self.assertTrue(os.path.isfile(expected), name)

    def test_removes_superseded_ogg_and_its_import_sidecar(self):
        with tempfile.TemporaryDirectory() as tmp:
            _make_fake_assets(tmp)
            ui_dir = os.path.join(tmp, "assets", "audio", "ui")
            ogg = os.path.join(ui_dir, "hover.ogg")
            sidecar = ogg + ".import"
            for path in (ogg, sidecar):
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write("stale")

            _, removed, _ = cli.install(tmp, seed=0, sources_root=tmp)

            self.assertFalse(os.path.exists(ogg))
            self.assertFalse(os.path.exists(sidecar))
            self.assertIn(ogg, removed)
            self.assertIn(sidecar, removed)

    def test_leaves_unrelated_files_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            _make_fake_assets(tmp)
            stray = os.path.join(tmp, "assets", "audio", "ui", "README.md")
            with open(stray, "w", encoding="utf-8") as handle:
                handle.write("keep me")
            for stray_name in ("unrelated.ogg", "unrelated.ogg.import"):
                stray_path = os.path.join(tmp, "assets", "audio", "ui", stray_name)
                with open(stray_path, "w", encoding="utf-8") as handle:
                    handle.write("keep me")
            cli.install(tmp, seed=0, sources_root=tmp)
            self.assertTrue(os.path.isfile(stray))
            for stray_name in ("unrelated.ogg", "unrelated.ogg.import"):
                stray_path = os.path.join(tmp, "assets", "audio", "ui", stray_name)
                self.assertTrue(os.path.isfile(stray_path))

    def test_creates_missing_bus_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            written, _, _ = cli.install(tmp, seed=0, sources_root=tmp)
            self.assertEqual(len(written), len(sfx_spec.SPECS))

    def test_installed_files_pass_verification(self):
        with tempfile.TemporaryDirectory() as tmp:
            written, _, _ = cli.install(tmp, seed=0, sources_root=tmp)
            for path in written:
                name = os.path.splitext(os.path.basename(path))[0]
                samples, _rate = read_wav(path)
                self.assertEqual(cli.verify_samples(name, samples), [], name)

    def test_a_failed_render_leaves_no_partial_wav(self):
        # The manifest points AudioManager at the .wav, so a truncated one would
        # play as garbage or not at all. A failed install must leave nothing.
        def half_write(path, samples, sample_rate=44100):
            with open(path, "wb") as handle:
                handle.write(b"RIFF truncated")
            raise IOError("disk full")

        with tempfile.TemporaryDirectory() as tmp:
            _make_fake_assets(tmp)
            ogg = os.path.join(tmp, "assets", "audio", "ui", "click.ogg")
            with open(ogg, "w", encoding="utf-8") as handle:
                handle.write("still good")

            with mock.patch.object(cli, "render_wav", side_effect=half_write):
                with self.assertRaises(IOError):
                    cli.install(tmp, seed=0, sources_root=tmp)

            for bus in ("ui", "sfx"):
                bus_dir = os.path.join(tmp, "assets", "audio", bus)
                leftovers = [
                    name
                    for name in os.listdir(bus_dir)
                    if name.endswith(".wav") or name.endswith(".tmp")
                ]
                self.assertEqual(leftovers, [], bus)
            self.assertTrue(os.path.exists(ogg))


class TestManifest(unittest.TestCase):
    def _read(self, root):
        with open(cli.manifest_path(root), "r", encoding="utf-8") as handle:
            return json.load(handle)

    def test_install_writes_a_manifest_entry_for_every_sound(self):
        with tempfile.TemporaryDirectory() as tmp:
            cli.install(tmp, seed=0, sources_root=tmp)
            sounds = self._read(tmp)["sounds"]
        every = cli.every_sound()
        self.assertEqual(set(sounds), set(every))
        for name, spec in every.items():
            entry = sounds[name]
            self.assertEqual(entry["bus"], cli.GODOT_BUS[spec.bus], name)
            self.assertEqual(entry["loop"], name in sfx_spec.RECORDINGS, name)
            self.assertEqual(
                entry["path"], "res://assets/audio/%s/%s.wav" % (spec.bus, name)
            )
            self.assertEqual(entry["takes"][0], entry["path"], name)
            self.assertEqual(len(entry["takes"]), cli.take_count(name), name)
            self.assertEqual(len(entry["take_gains_db"]), len(entry["takes"]), name)
            self.assertEqual(entry["volume_db"], spec.volume_db, name)
            self.assertEqual(entry["pitch_jitter"], spec.pitch_jitter, name)
            self.assertEqual(entry["cooldown_s"], spec.cooldown_s, name)
            self.assertEqual(entry["priority"], spec.priority, name)

    def test_manifest_is_byte_stable_with_lf_endings(self):
        with tempfile.TemporaryDirectory() as tmp:
            cli.write_manifest(tmp)
            with open(cli.manifest_path(tmp), "rb") as handle:
                first = handle.read()
            cli.write_manifest(tmp)
            with open(cli.manifest_path(tmp), "rb") as handle:
                second = handle.read()
        self.assertEqual(first, second)
        self.assertNotIn(b"\r\n", first)

    def test_manifest_flag_writes_no_audio(self):
        with tempfile.TemporaryDirectory() as tmp:
            code = cli.main(["--manifest", "--assets-root", tmp])
            self.assertEqual(code, 0)
            self.assertTrue(os.path.isfile(cli.manifest_path(tmp)))
            for bus in cli.GODOT_BUS:
                self.assertFalse(
                    os.path.isdir(os.path.join(tmp, "assets", "audio", bus)), bus
                )


class TestInstallWiring(unittest.TestCase):
    def test_main_install_flag_writes_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            code = cli.main(["--install", "--assets-root", tmp, "--sources-root", tmp])
            self.assertEqual(code, 0)
            self.assertTrue(
                os.path.isfile(os.path.join(tmp, "assets", "audio", "ui", "click.wav"))
            )
            self.assertTrue(os.path.isfile(cli.manifest_path(tmp)))


class TestRecordedShots(unittest.TestCase):
    """A recorded shot installs one file per take from the takes' originals, and
    drops a take file past its count (a take taken out of the spec)."""

    def test_present_originals_give_one_file_per_take_and_stale_takes_go(self):
        shot = sfx_spec.SHOTS["plant_tick"]
        with tempfile.TemporaryDirectory() as tmp:
            for key in {take.original for take in shot.takes}:
                source = os.path.join(tmp, *sfx_spec.ORIGINALS[key].source.split("/"))
                os.makedirs(os.path.dirname(source), exist_ok=True)
                write_source(source, noisy_fire(2.5, 44100), 44100, width=2)
            _make_fake_assets(tmp)
            stale = cli.installed_path(tmp, "plant_tick", "sfx", len(shot.takes))
            with open(stale, "wb") as handle:
                handle.write(b"a dropped take")
            with mock.patch.dict(sfx_spec.SHOTS, {"plant_tick": shot}, clear=True):
                written, removed, _ = cli.install(tmp, seed=0, sources_root=tmp)
            with open(cli.manifest_path(tmp), encoding="utf-8") as handle:
                sounds = json.load(handle)["sounds"]
            for index in range(len(shot.takes)):
                path = cli.installed_path(tmp, "plant_tick", "sfx", index)
                self.assertIn(path, written)
                samples, rate = read_wav(path)
                self.assertEqual(rate, shot.sample_rate)
                self.assertEqual(cli.verify_shot("plant_tick", index, samples, rate), [])
            self.assertIn(stale, removed)
            self.assertFalse(os.path.exists(stale))
        entry = sounds["plant_tick"]
        self.assertEqual(len(entry["takes"]), len(shot.takes))
        self.assertEqual(entry["take_gains_db"], [take.gain_db for take in shot.takes])
        self.assertEqual(entry["gain_jitter_db"], shot.gain_jitter_db)


class TestRecordedLoops(unittest.TestCase):
    """A recorded loop is processed from its original when present, and its
    committed file is kept, never a failure, when it is not (a fresh clone)."""

    def test_a_missing_original_keeps_the_committed_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            _make_fake_assets(tmp)
            committed = cli.installed_path(tmp, "fire_roar", "sfx")
            with open(committed, "wb") as handle:
                handle.write(b"the committed loop")
            with mock.patch.dict(sfx_spec.SHOTS, {}, clear=True):
                _, _, kept = cli.install(tmp, seed=0, sources_root=tmp)
            self.assertEqual(kept, [committed])
            with open(committed, "rb") as handle:
                self.assertEqual(handle.read(), b"the committed loop")
            self.assertIn("fire_roar", self._sounds(tmp))

    def test_install_says_it_kept_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            _make_fake_assets(tmp)
            with open(cli.installed_path(tmp, "fire_roar", "sfx"), "wb") as handle:
                handle.write(b"the committed loop")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = cli.main(["--install", "--assets-root", tmp, "--sources-root", tmp])
        self.assertEqual(code, 0)
        self.assertIn("kept the committed", out.getvalue())
        self.assertIn("fire_roar.wav", out.getvalue())

    def test_a_present_original_is_processed_to_a_mono_16_bit_loop(self):
        loop = dataclasses.replace(sfx_spec.RECORDINGS["fire_roar"], start_s=0.5, end_s=2.5)
        with tempfile.TemporaryDirectory() as tmp:
            source = os.path.join(tmp, *loop.source.split("/"))
            os.makedirs(os.path.dirname(source))
            write_source(source, noisy_fire(3.0, 48000), 48000, channels=2)
            with mock.patch.dict(sfx_spec.RECORDINGS, {"fire_roar": loop}):
                with mock.patch.dict(sfx_spec.SHOTS, {}, clear=True):
                    written, _, kept = cli.install(tmp, seed=0, sources_root=tmp)
            path = cli.installed_path(tmp, "fire_roar", "sfx")
            self.assertIn(path, written)
            self.assertEqual(kept, [])
            with wave.open(path, "rb") as handle:
                self.assertEqual(handle.getnchannels(), 1, "mono stays mono")
                self.assertEqual(handle.getsampwidth(), 2)
                self.assertEqual(handle.getframerate(), loop.sample_rate)
            samples, _ = read_wav(path)
        expected = round(loop.total_ms * loop.sample_rate / 1000.0) + 1
        self.assertEqual(len(samples), expected, "the loop and its guard sample")
        self.assertEqual(samples[-1], samples[0])

    def _sounds(self, root):
        with open(cli.manifest_path(root), "r", encoding="utf-8") as handle:
            return json.load(handle)["sounds"]


if __name__ == "__main__":
    unittest.main()
