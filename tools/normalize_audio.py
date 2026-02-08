#!/usr/bin/env python3
"""
Normalize all audio files in assets/audio/ to a consistent perceived loudness.

Uses ffmpeg's loudnorm filter (EBU R128 / LUFS-based) for perceptual normalization.
For files too short for LUFS measurement (< ~400ms), falls back to peak normalization
so that every file — even tiny clicks — gets consistent levels.

Requirements:
    - ffmpeg must be installed and on PATH
    - Python 3.8+

Usage:
    python tools/normalize_audio.py                 # Normalize all audio files
    python tools/normalize_audio.py --target -18    # Custom LUFS target (default: -18)
    python tools/normalize_audio.py --peak -3       # Custom peak target for short files (default: -3)
    python tools/normalize_audio.py --dry-run       # Preview what would be processed
    python tools/normalize_audio.py --backup        # Keep originals as .bak files
"""

import argparse
import json
import math
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

# Default peak target (dBFS) for short files that can't use LUFS.
# -3 dBFS leaves headroom while keeping short transients punchy.
DEFAULT_PEAK_TARGET = -3.0

# Tolerance: skip files already within this many dB of their target.
# 1.5 dB for LUFS accounts for measurement variance from re-encoding and limiting.
# A 1 dB loudness difference is barely perceptible in game SFX.
LUFS_TOLERANCE = 1.5
PEAK_TOLERANCE = 1.5


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


def get_codec_args(ext: str) -> list[str]:
    """Return ffmpeg codec arguments for the given file extension."""
    if ext == ".ogg":
        return ["-c:a", "libvorbis", "-q:a", "6"]
    elif ext == ".opus":
        return ["-c:a", "libopus", "-b:a", "128k"]
    elif ext == ".mp3":
        return ["-c:a", "libmp3lame", "-q:a", "2"]
    else:
        # WAV — PCM output
        return ["-c:a", "pcm_s16le"]


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


def is_lufs_valid(measurements: dict) -> bool:
    """Check whether the LUFS measurement is usable (not -inf / inf)."""
    try:
        val = float(measurements["input_i"])
        return math.isfinite(val)
    except (ValueError, KeyError, TypeError):
        return False


def get_peak_db(measurements: dict) -> float | None:
    """Extract the true peak value in dB from measurements."""
    try:
        val = float(measurements["input_tp"])
        return val if math.isfinite(val) else None
    except (ValueError, KeyError, TypeError):
        return None


# ---------------------------------------------------------------------------
# LUFS normalization (for files long enough for EBU R128)
# ---------------------------------------------------------------------------

def normalize_lufs(
    filepath: str,
    current_lufs: float,
    target_lufs: float,
    backup: bool = False,
) -> bool:
    """
    Normalize a file by applying the exact gain needed to reach the LUFS target,
    with a hard limiter to prevent clipping. More reliable for short game SFX
    than ffmpeg's loudnorm two-pass mode.
    """
    ext = os.path.splitext(filepath)[1].lower()
    gain_db = target_lufs - current_lufs

    # Apply gain and hard-limit to prevent peaks exceeding the ceiling
    af = f"volume={gain_db}dB,alimiter=limit={TRUE_PEAK_LIMIT}dB:attack=0.1:release=50"

    return _apply_filter(filepath, af, ext, backup)


# ---------------------------------------------------------------------------
# Peak normalization (fallback for very short files)
# ---------------------------------------------------------------------------

def normalize_peak(
    filepath: str,
    current_peak_db: float,
    target_peak_db: float,
    backup: bool = False,
) -> bool:
    """
    Normalize a short file by scaling its peak to the target level.
    Uses ffmpeg's volume filter with a simple gain adjustment.
    """
    ext = os.path.splitext(filepath)[1].lower()
    gain_db = target_peak_db - current_peak_db

    # Apply gain and hard-limit to prevent any overshoot
    af = f"volume={gain_db}dB,alimiter=limit={TRUE_PEAK_LIMIT}dB:attack=0.1:release=50"

    return _apply_filter(filepath, af, ext, backup)


# ---------------------------------------------------------------------------
# Shared filter application
# ---------------------------------------------------------------------------

def _apply_filter(filepath: str, af: str, ext: str, backup: bool) -> bool:
    """Apply an ffmpeg audio filter, writing to a temp file then replacing the original."""
    codec_args = get_codec_args(ext)

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

        if backup:
            bak_path = filepath + ".bak"
            shutil.copy2(filepath, bak_path)

        shutil.move(tmp_path, filepath)
        return True

    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

def format_lufs(value: str) -> str:
    """Format a LUFS value string for display."""
    try:
        return f"{float(value):+.1f} LUFS"
    except (ValueError, TypeError):
        return str(value)


def format_db(value: float) -> str:
    """Format a dB value for display."""
    return f"{value:+.1f} dB"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Normalize audio files to consistent perceived loudness (EBU R128 / LUFS)."
    )
    parser.add_argument(
        "--target", type=float, default=DEFAULT_TARGET_LUFS,
        help=f"Target loudness in LUFS (default: {DEFAULT_TARGET_LUFS})"
    )
    parser.add_argument(
        "--peak", type=float, default=DEFAULT_PEAK_TARGET,
        help=f"Target peak in dBFS for short files (default: {DEFAULT_PEAK_TARGET})"
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
    peak_target = args.peak
    mode = "DRY RUN" if args.dry_run else "NORMALIZING"

    print(f"LUFS target:  {target} LUFS  (files >= 400ms)")
    print(f"Peak target:  {peak_target} dBFS  (short files)")
    print(f"Peak ceiling: {TRUE_PEAK_LIMIT} dBTP")
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

        input_tp = measurements.get("input_tp", "?")
        current_peak = get_peak_db(measurements)

        if is_lufs_valid(measurements):
            # ---- LUFS path (normal-length files) ----
            current_lufs = float(measurements["input_i"])
            print(f"    Current: {current_lufs:+.1f} LUFS  (peak: {input_tp} dBTP)")

            if abs(current_lufs - target) < LUFS_TOLERANCE:
                print(f"    Already within LUFS target — skipping")
                skip_count += 1
                continue

            gain = target - current_lufs
            print(f"    Gain: {format_db(gain)}")

            if args.dry_run:
                print(f"    Would normalize to {target} LUFS")
                success_count += 1
                continue

            ok = normalize_lufs(filepath, current_lufs, target, backup=args.backup)
            if ok:
                verify = measure_loudness(filepath, target)
                if verify and is_lufs_valid(verify):
                    print(f"    Normalized: {float(verify['input_i']):+.1f} LUFS")
                else:
                    print(f"    Normalized (could not verify)")
                success_count += 1
            else:
                print(f"    FAILED to normalize")
                fail_count += 1

        elif current_peak is not None:
            # ---- Peak path (short files) ----
            print(f"    Current: too short for LUFS  (peak: {current_peak:+.1f} dBFS)")

            if abs(current_peak - peak_target) < PEAK_TOLERANCE:
                print(f"    Already within peak target — skipping")
                skip_count += 1
                continue

            gain = peak_target - current_peak
            print(f"    Gain: {format_db(gain)}")

            if args.dry_run:
                print(f"    Would peak-normalize to {peak_target} dBFS")
                success_count += 1
                continue

            ok = normalize_peak(filepath, current_peak, peak_target, backup=args.backup)
            if ok:
                verify = measure_loudness(filepath, target)
                v_peak = get_peak_db(verify) if verify else None
                if v_peak is not None:
                    print(f"    Peak-normalized: {v_peak:+.1f} dBFS")
                else:
                    print(f"    Peak-normalized (could not verify)")
                success_count += 1
            else:
                print(f"    FAILED to peak-normalize")
                fail_count += 1

        else:
            print(f"    No valid LUFS or peak measurement — skipping")
            fail_count += 1
            continue

    # Summary
    print("\n" + "-" * 60)
    print(f"Done. {success_count} processed, {skip_count} skipped, {fail_count} failed.")


if __name__ == "__main__":
    main()
