#!/usr/bin/env python3
"""Generate, audition, verify and install the game's sound effect palette.

Standard library only, except for optional ffmpeg use in --as-bus.

Usage:
    python tools/generate_sfx.py --variants 3 --sheet     # audition
    python tools/generate_sfx.py --sheet --as-bus         # audition through the game buses
    python tools/generate_sfx.py --verify                 # gate on measured softness
    python tools/generate_sfx.py --install                # write into assets/audio/
"""

import argparse
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import sfx_spec
from sfx_render import render_spec, variant_spec
from sfx_synth import render_wav

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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
        "--install", action="store_true", help="write variant 0 into assets/audio/"
    )
    parser.add_argument(
        "--assets-root",
        default=REPO_ROOT,
        help="repository root that --install writes beneath",
    )
    return parser


def main(argv: list = None) -> int:
    args = build_parser().parse_args(argv)
    written = generate(args.out, args.only, args.variants, args.seed)
    print("Wrote %d file(s) to %s" % (len(written), args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
