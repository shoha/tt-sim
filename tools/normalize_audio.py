#!/usr/bin/env python3
"""
Normalize all audio files in assets/audio/ to a consistent perceived loudness.

Uses ffmpeg's loudnorm filter (EBU R128 / LUFS-based) for perceptual normalization,
so sounds from different sources sit well together regardless of original levels.

Requirements:
    - ffmpeg must be installed and on PATH
    - Python 3.8+

Usage:
    python tools/normalize_audio.py                 # Normalize all audio files
    python tools/normalize_audio.py --target -18    # Custom LUFS target (default: -18)
    python tools/normalize_audio.py --dry-run       # Preview what would be processed
    python tools/normalize_audio.py --backup        # Keep originals as .bak files
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

# Supported audio extensions
AUDIO_EXTENSIONS = {".wav", ".ogg", ".mp3", ".opus"}

# Default loudness target (LUFS) — good range for game SFX is -16 to -20
DEFAULT_TARGET_LUFS = -18

# True peak ceiling (dBTP) — prevents clipping after normalization
TRUE_PEAK_LIMIT = -1.0

# Loudness range target (LRA) — how much dynamic range to preserve
LOUDNESS_RANGE = 11.0


def find_audio_files(audio_dir: str) -> list[str]:
    """Recursively find all audio files under the given directory."""
    files = []
    for root, _dirs, filenames in os.walk(audio_dir):
        for filename in sorted(filenames):
            ext = os.path.splitext(filename)[1].lower()
            if ext in AUDIO_EXTENSIONS:
                files.append(os.path.join(root, filename))
    return files


def check_ffmpeg() -> bool:
    """Verify ffmpeg is available."""
    try:
        result = subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def measure_loudness(filepath: str, target_lufs: float) -> dict | None:
    """
    First pass: measure the file's loudness using ffmpeg's loudnorm filter.
    Returns the measured values needed for the second (normalization) pass.
    """
    cmd = [
        "ffmpeg", "-i", filepath,
        "-af", f"loudnorm=I={target_lufs}:TP={TRUE_PEAK_LIMIT}:LRA={LOUDNESS_RANGE}:print_format=json",
        "-f", "null", "-"
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        return None

    # The loudnorm JSON is printed at the end of stderr
    stderr = result.stderr
    # Find the JSON block (between the last { and })
    json_start = stderr.rfind("{")
    json_end = stderr.rfind("}") + 1
    if json_start == -1 or json_end == 0:
        return None

    try:
        return json.loads(stderr[json_start:json_end])
    except json.JSONDecodeError:
        return None


def normalize_file(
    filepath: str,
    measurements: dict,
    target_lufs: float,
    backup: bool = False,
) -> bool:
    """
    Second pass: apply loudnorm normalization using the measured values.
    Overwrites the original file (optionally backing up first).
    """
    ext = os.path.splitext(filepath)[1].lower()

    # Build the loudnorm filter string with measured values
    af = (
        f"loudnorm=I={target_lufs}:TP={TRUE_PEAK_LIMIT}:LRA={LOUDNESS_RANGE}"
        f":measured_I={measurements['input_i']}"
        f":measured_TP={measurements['input_tp']}"
        f":measured_LRA={measurements['input_lra']}"
        f":measured_thresh={measurements['input_thresh']}"
        f":offset={measurements['target_offset']}"
        f":linear=true"
    )

    # Output codec depends on format
    codec_args = []
    if ext == ".ogg":
        codec_args = ["-c:a", "libvorbis", "-q:a", "6"]
    elif ext == ".opus":
        codec_args = ["-c:a", "libopus", "-b:a", "128k"]
    elif ext == ".mp3":
        codec_args = ["-c:a", "libmp3lame", "-q:a", "2"]
    else:
        # WAV — PCM output
        codec_args = ["-c:a", "pcm_s16le"]

    # Write to a temp file first, then replace the original
    fd, tmp_path = tempfile.mkstemp(suffix=ext)
    os.close(fd)

    try:
        cmd = [
            "ffmpeg", "-y", "-i", filepath,
            "-af", af,
            *codec_args,
            tmp_path,
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            os.unlink(tmp_path)
            return False

        # Backup original if requested
        if backup:
            bak_path = filepath + ".bak"
            shutil.copy2(filepath, bak_path)

        # Replace original with normalized version
        shutil.move(tmp_path, filepath)
        return True

    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def format_lufs(value: str) -> str:
    """Format a LUFS value string for display."""
    try:
        return f"{float(value):+.1f} LUFS"
    except (ValueError, TypeError):
        return str(value)


def main():
    parser = argparse.ArgumentParser(
        description="Normalize audio files to consistent perceived loudness (EBU R128 / LUFS)."
    )
    parser.add_argument(
        "--target", type=float, default=DEFAULT_TARGET_LUFS,
        help=f"Target loudness in LUFS (default: {DEFAULT_TARGET_LUFS})"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Measure and report loudness without modifying files"
    )
    parser.add_argument(
        "--backup", action="store_true",
        help="Keep original files as .bak before overwriting"
    )
    parser.add_argument(
        "paths", nargs="*",
        help="Specific files or directories to process (default: assets/audio/)"
    )
    args = parser.parse_args()

    # Check ffmpeg
    if not check_ffmpeg():
        print("Error: ffmpeg is not installed or not on PATH.", file=sys.stderr)
        print("Install it from https://ffmpeg.org/download.html", file=sys.stderr)
        sys.exit(1)

    # Find project root (parent of tools/)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    # Determine which files to process
    audio_files = []
    if args.paths:
        for path in args.paths:
            abs_path = os.path.abspath(path)
            if os.path.isdir(abs_path):
                audio_files.extend(find_audio_files(abs_path))
            elif os.path.isfile(abs_path):
                audio_files.append(abs_path)
            else:
                print(f"Warning: '{path}' not found, skipping.", file=sys.stderr)
    else:
        audio_dir = os.path.join(project_root, "assets", "audio")
        if not os.path.isdir(audio_dir):
            print(f"No audio directory found at: {audio_dir}", file=sys.stderr)
            print("Create it and add audio files, or pass paths explicitly.", file=sys.stderr)
            sys.exit(1)
        audio_files = find_audio_files(audio_dir)

    if not audio_files:
        print("No audio files found.")
        sys.exit(0)

    # Process
    target = args.target
    mode = "DRY RUN" if args.dry_run else "NORMALIZING"

    print(f"Target loudness: {target} LUFS")
    print(f"True peak limit: {TRUE_PEAK_LIMIT} dBTP")
    print(f"Mode: {mode}")
    print(f"Files: {len(audio_files)}")
    print("-" * 60)

    success_count = 0
    skip_count = 0
    fail_count = 0

    for filepath in audio_files:
        rel_path = os.path.relpath(filepath, project_root)

        # Pass 1: Measure
        print(f"\n  {rel_path}")
        measurements = measure_loudness(filepath, target)

        if measurements is None:
            print(f"    FAILED to measure — skipping")
            fail_count += 1
            continue

        input_lufs = format_lufs(measurements.get("input_i", "?"))
        input_tp = measurements.get("input_tp", "?")
        offset = measurements.get("target_offset", "?")

        print(f"    Current: {input_lufs}  (peak: {input_tp} dBTP, offset: {offset} dB)")

        # Check if already within tolerance (±0.5 LUFS)
        try:
            current = float(measurements["input_i"])
            if abs(current - target) < 0.5:
                print(f"    Already within target — skipping")
                skip_count += 1
                continue
        except (ValueError, KeyError):
            pass

        if args.dry_run:
            print(f"    Would normalize to {target} LUFS")
            success_count += 1
            continue

        # Pass 2: Normalize
        ok = normalize_file(filepath, measurements, target, backup=args.backup)
        if ok:
            # Verify result
            verify = measure_loudness(filepath, target)
            if verify:
                result_lufs = format_lufs(verify.get("input_i", "?"))
                print(f"    Normalized: {result_lufs}")
            else:
                print(f"    Normalized (could not verify)")
            success_count += 1
        else:
            print(f"    FAILED to normalize")
            fail_count += 1

    # Summary
    print("\n" + "-" * 60)
    print(f"Done. {success_count} processed, {skip_count} skipped, {fail_count} failed.")


if __name__ == "__main__":
    main()
