"""Tests for --install."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import generate_sfx as cli
import sfx_spec


def _make_fake_assets(root):
    for bus in ("ui", "sfx"):
        os.makedirs(os.path.join(root, "assets", "audio", bus), exist_ok=True)


class TestInstall(unittest.TestCase):
    def test_writes_every_sound_into_its_bus_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            _make_fake_assets(tmp)
            written, _ = cli.install(tmp, seed=0)
            self.assertEqual(len(written), len(sfx_spec.SPECS))
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

            _, removed = cli.install(tmp, seed=0)

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
            cli.install(tmp, seed=0)
            self.assertTrue(os.path.isfile(stray))

    def test_creates_missing_bus_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            written, _ = cli.install(tmp, seed=0)
            self.assertEqual(len(written), len(sfx_spec.SPECS))

    def test_installed_files_pass_verification(self):
        from sfx_synth import read_wav

        with tempfile.TemporaryDirectory() as tmp:
            written, _ = cli.install(tmp, seed=0)
            for path in written:
                name = os.path.splitext(os.path.basename(path))[0]
                samples, _rate = read_wav(path)
                self.assertEqual(cli.verify_samples(name, samples), [], name)


class TestInstallWiring(unittest.TestCase):
    def test_main_install_flag_writes_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            code = cli.main(["--install", "--assets-root", tmp])
            self.assertEqual(code, 0)
            self.assertTrue(
                os.path.isfile(os.path.join(tmp, "assets", "audio", "ui", "click.wav"))
            )


if __name__ == "__main__":
    unittest.main()
