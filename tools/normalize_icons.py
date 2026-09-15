"""Normalise Tabler SVG icons so Godot can tint them with modulate.

Usage:
    python tools/normalize_icons.py SRC_DIR DEST_DIR [--suffix=-filled] NAME [NAME ...]

For every NAME, reads SRC_DIR/NAME.svg, replaces currentColor with #ffffff,
drops class attributes and Tabler's invisible 24x24 hit-box path, and writes
DEST_DIR/NAME<suffix>.svg. Standard library only. Never fetches anything.
Exit code 1 lists the names that were missing in SRC_DIR.
"""
import pathlib
import re
import sys

HITBOX = re.compile(r'<path[^>]*d="M0 0h24v24H0z"[^>]*/>')
CLASS_ATTR = re.compile(r'\s+class="[^"]*"')


def normalise(svg: str) -> str:
    svg = svg.replace("currentColor", "#ffffff")
    svg = HITBOX.sub("", svg)
    svg = CLASS_ATTR.sub("", svg)
    return svg


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__)
        return 2
    src = pathlib.Path(argv[1])
    dst = pathlib.Path(argv[2])
    suffix = ""
    names = argv[3:]
    if names and names[0].startswith("--suffix="):
        suffix = names[0].split("=", 1)[1]
        names = names[1:]
    dst.mkdir(parents=True, exist_ok=True)
    missing: list[str] = []
    for name in names:
        source = src / f"{name}.svg"
        if not source.exists():
            missing.append(name)
            continue
        target = dst / f"{name}{suffix}.svg"
        target.write_text(normalise(source.read_text(encoding="utf-8")), encoding="utf-8")
        print(f"wrote {target}")
    if missing:
        print("missing:", " ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
