#!/usr/bin/env python3
"""Generate, audition, verify and install the game's sound effect palette.

Standard library only, except for optional ffmpeg use in --as-bus.

Usage:
    python tools/generate_sfx.py --variants 3 --sheet     # audition
    python tools/generate_sfx.py --sheet --as-bus         # audition through the game buses
    python tools/generate_sfx.py --verify                 # gate on measured softness
    python tools/generate_sfx.py --install                # write into assets/audio/
    python tools/generate_sfx.py --manifest               # rewrite only the manifest
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import sfx_measure as measure
import sfx_spec
from sfx_render import (
    ATTACK_BAND_HIGH_MS,
    ATTACK_BAND_LOW,
    DURATION_TOLERANCE,
    PEAK_WINDOW_DBFS,
    WARMTH_FLOOR_MARGIN_DB,
    render_spec,
    variant_spec,
)
from sfx_synth import ms_to_samples, render_wav

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The playback table AudioManager loads (autoloads/audio_manager.gd). JSON
# because this stdlib tool writes it byte-stable, both test suites read it in
# one line, a diff of it reads as a diff of the spec, and Godot exports .json
# files under the all_resources filter as it does assets/palette/palette.json.
MANIFEST_RELPATH = ("assets", "audio", "sfx_manifest.json")

# Spec bus (also the asset directory) to the Godot audio bus name.
GODOT_BUS = {"ui": "UI", "sfx": "SFX"}

SHEET_GAP_MS = 600.0

# Approximates default_bus_layout.tres so auditioning matches what the game
# will actually play. ffmpeg has no true reverb, so aecho stands in for the
# small-room AudioEffectReverb on the SFX bus.
#
# These cutoffs MIRROR default_bus_layout.tres. If you change a bus effect
# there, change it here too, or the audition preview stops predicting the game.
BUS_CHAINS = {
    "ui": "lowpass=f=7000",
    "sfx": "lowpass=f=7000,aecho=0.9:0.85:20|32:0.12|0.08",
}


def default_out_dir() -> str:
    """Scratch directory for auditioning. Never inside the repo."""
    return os.path.join(tempfile.gettempdir(), "tt-sim-sfx")


def _resolve_names(only: list) -> list:
    if not only:
        return list(sfx_spec.SPECS)
    unknown = [name for name in only if name not in sfx_spec.SPECS]
    if unknown:
        raise SystemExit(
            "unknown sound name(s): %s\nknown names: %s"
            % (", ".join(unknown), ", ".join(sorted(sfx_spec.SPECS)))
        )
    return list(only)


def variant_filename(name: str, index: int) -> str:
    """Variant 0 keeps the plain name so --install can use it directly."""
    return "%s.wav" % name if index == 0 else "%s.v%d.wav" % (name, index)


def generate(out_dir: str, only: list, variants: int, seed: int) -> list:
    """Render the requested sounds into out_dir. Returns the paths written."""
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name in _resolve_names(only):
        spec = sfx_spec.SPECS[name]
        for index in range(max(1, variants)):
            samples = render_spec(variant_spec(spec, index), seed=seed + index)
            path = os.path.join(out_dir, variant_filename(name, index))
            render_wav(path, samples)
            written.append(path)
    return written


def build_sheet(bus: str, seed: int) -> tuple:
    """Concatenate every sound on a bus, separated by silence.

    Returns the samples and the sound names in the order they appear, so the
    listener knows what they are hearing.
    """
    names = sorted(name for name, spec in sfx_spec.SPECS.items() if spec.bus == bus)
    gap = [0.0] * ms_to_samples(SHEET_GAP_MS)
    samples = []
    for index, name in enumerate(names):
        if index > 0:
            samples.extend(gap)
        samples.extend(render_spec(sfx_spec.SPECS[name], seed=seed))
    return samples, names


def apply_bus_chain(src_path: str, dst_path: str, bus: str) -> bool:
    """Filter a sheet through an approximation of the game's bus effects."""
    if shutil.which("ffmpeg") is None:
        return False
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y",
            "-i", src_path,
            "-af", BUS_CHAINS[bus],
            dst_path,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print("ffmpeg failed for %s: %s" % (bus, result.stderr.strip()))
        return False
    return True


def write_sheets(out_dir: str, seed: int, as_bus: bool) -> list:
    """Write one audition sheet per bus. Returns the paths written."""
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for bus in ("sfx", "ui"):
        samples, names = build_sheet(bus, seed)
        path = os.path.join(out_dir, "sheet_%s.wav" % bus)
        render_wav(path, samples)
        written.append(path)
        print("sheet_%s.wav order: %s" % (bus, ", ".join(names)))
        if as_bus:
            bus_path = os.path.join(out_dir, "sheet_%s_bus.wav" % bus)
            if apply_bus_chain(path, bus_path, bus):
                written.append(bus_path)
            else:
                print("Skipped --as-bus for %s (ffmpeg unavailable)" % bus)
    return written


def verify_samples(name: str, samples: list) -> list:
    """Check one rendered sound against the palette's design targets."""
    spec = sfx_spec.SPECS[name]
    failures = []

    attack = measure.attack_time_ms(samples)
    low = ATTACK_BAND_LOW * spec.attack_ms
    high = spec.attack_ms + ATTACK_BAND_HIGH_MS
    if not low <= attack <= high:
        failures.append(
            "%s: attack %.1f ms is outside [%.1f, %.1f] for a declared %.1f ms onset"
            % (name, attack, low, high, spec.attack_ms)
        )

    peak = measure.peak_dbfs(samples)
    low, high = PEAK_WINDOW_DBFS
    if not low <= peak <= high:
        direction = "too quiet" if peak < low else "too loud"
        failures.append(
            "%s: peak %.2f dBFS is outside [%.1f, %.1f] (%s)"
            % (name, peak, low, high, direction)
        )

    ratio = measure.high_band_ratio_db(samples)
    if ratio > spec.max_high_band_db:
        failures.append(
            "%s: high-band ratio %.1f dB exceeds %.1f dB (too bright)"
            % (name, ratio, spec.max_high_band_db)
        )
    elif ratio < spec.max_high_band_db - WARMTH_FLOOR_MARGIN_DB:
        failures.append(
            "%s: high-band ratio %.1f dB is more than %.0f dB below its %.1f dB target (muffled)"
            % (name, ratio, WARMTH_FLOOR_MARGIN_DB, spec.max_high_band_db)
        )

    expected = spec.total_ms
    actual = measure.duration_ms(samples)
    if abs(actual - expected) / expected > DURATION_TOLERANCE:
        failures.append(
            "%s: duration %.0f ms differs from the declared %.0f ms by more than %.0f percent"
            % (name, actual, expected, DURATION_TOLERANCE * 100.0)
        )

    return failures


def verify_palette() -> list:
    """Render and check every declared sound. Returns all failures."""
    failures = []
    for name, spec in sfx_spec.SPECS.items():
        failures.extend(verify_samples(name, render_spec(spec)))
    return failures


def build_manifest() -> dict:
    """The playback table for every sound in the spec, keyed by name.

    Each entry names the installed file, its Godot bus and the spec's playback
    fields (volume_db, pitch_jitter in semitones, cooldown_s, priority).
    """
    return {
        name: {
            "bus": GODOT_BUS[spec.bus],
            "path": "res://assets/audio/%s/%s.wav" % (spec.bus, name),
            "volume_db": spec.volume_db,
            "pitch_jitter": spec.pitch_jitter,
            "cooldown_s": spec.cooldown_s,
            "priority": spec.priority,
        }
        for name, spec in sorted(sfx_spec.SPECS.items())
    }


def manifest_path(assets_root: str) -> str:
    """Where the manifest lives beneath a repository root."""
    return os.path.join(assets_root, *MANIFEST_RELPATH)


def write_manifest(assets_root: str) -> str:
    """Write the manifest beneath assets_root with LF endings. Returns its path."""
    path = manifest_path(assets_root)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    document = {
        "generated_by": "tools/generate_sfx.py from tools/sfx_spec.py; edit the spec",
        "sounds": build_manifest(),
    }
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(document, indent=2, sort_keys=True) + "\n")
    return path


def install(assets_root: str, seed: int) -> tuple:
    """Write variant 0 of every sound into assets/audio/, drop stale .ogg files,
    and write the manifest AudioManager loads.

    The manifest names each .wav path explicitly, so a surviving .ogg for the
    same sound name would never be loaded again; it is removed here.
    """
    written = []
    removed = []
    for name, spec in sfx_spec.SPECS.items():
        bus_dir = os.path.join(assets_root, "assets", "audio", spec.bus)
        os.makedirs(bus_dir, exist_ok=True)

        wav_path = os.path.join(bus_dir, "%s.wav" % name)
        # Write to a temporary file beside the target and move it into place.
        # os.replace is atomic on the same filesystem, so an interrupted render
        # can never leave a truncated .wav behind where the manifest points.
        temp_path = wav_path + ".tmp"
        try:
            render_wav(temp_path, render_spec(spec, seed=seed))
            os.replace(temp_path, wav_path)
        except Exception:
            if os.path.exists(temp_path):
                os.remove(temp_path)
            raise
        written.append(wav_path)

        for stale in ("%s.ogg" % name, "%s.ogg.import" % name):
            stale_path = os.path.join(bus_dir, stale)
            if os.path.exists(stale_path):
                os.remove(stale_path)
                removed.append(stale_path)
    write_manifest(assets_root)
    return written, removed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate the warm synthesized SFX palette."
    )
    parser.add_argument(
        "--out", default=default_out_dir(), help="output directory for generated files"
    )
    parser.add_argument(
        "--only", nargs="+", default=[], help="generate only these sound names"
    )
    parser.add_argument(
        "--variants", type=int, default=1, help="variants per sound (default 1)"
    )
    parser.add_argument("--seed", type=int, default=0, help="noise seed (default 0)")
    parser.add_argument(
        "--sheet", action="store_true", help="also write per-bus audition sheets"
    )
    parser.add_argument(
        "--as-bus",
        dest="as_bus",
        action="store_true",
        help="render sheets through an approximation of the game's bus chain",
    )
    parser.add_argument(
        "--verify", action="store_true", help="check the palette against its targets"
    )
    parser.add_argument(
        "--install",
        action="store_true",
        help="write variant 0 and the manifest into assets/audio/ "
        "(ignored if --verify is also given)",
    )
    parser.add_argument(
        "--manifest",
        action="store_true",
        help="rewrite only assets/audio/sfx_manifest.json, for playback-only edits "
        "(volume_db, pitch_jitter, cooldown_s, priority)",
    )
    parser.add_argument(
        "--assets-root",
        default=REPO_ROOT,
        help="repository root that --install and --manifest write beneath",
    )
    return parser


def main(argv: list = None) -> int:
    args = build_parser().parse_args(argv)

    if args.verify:
        failures = verify_palette()
        if failures:
            print("Palette verification FAILED:")
            for failure in failures:
                print("  " + failure)
            return 1
        print("Palette verification passed: %d sounds." % len(sfx_spec.SPECS))
        return 0

    if args.install:
        written, removed = install(args.assets_root, args.seed)
        print("Installed %d file(s) into %s" % (len(written), args.assets_root))
        print("Wrote %s" % manifest_path(args.assets_root))
        for path in removed:
            print("  removed superseded %s" % os.path.relpath(path, args.assets_root))
        print("Next: godot --headless --import --path .")
        return 0

    if args.manifest:
        print("Wrote %s" % write_manifest(args.assets_root))
        return 0

    written = generate(args.out, args.only, args.variants, args.seed)
    print("Wrote %d file(s) to %s" % (len(written), args.out))
    if args.sheet:
        sheets = write_sheets(args.out, args.seed, args.as_bus)
        print("Wrote %d sheet(s) to %s" % (len(sheets), args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
