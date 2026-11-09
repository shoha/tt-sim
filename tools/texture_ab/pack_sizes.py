"""Packed sizes of the candidate trees bytes_run.gd wrote.

Reads <tree>/<candidate>/<surface>/<kind>.<ext> (and the shipped PNGs for a_png from the core
library) and prints, per candidate and kind, the total bytes raw, after zstd level 19 and after
deflate level 6 (what a zip stores) and 9, each file compressed on its own (a zip entry, a pck
member). Writes <tree>/pack_sizes.json. Standard library only (Python 3.14 has compression.zstd).

    python -I pack_sizes.py <tree> <core surfaces folder>
"""

import json
import sys
import zlib
from compression import zstd
from pathlib import Path

KINDS = ["albedo", "normal", "orm", "height"]
CANDIDATES = ["a_png", "a8_png8", "b_webp_ll", "c_ttimg", "d95_webp", "d90_webp", "d85_webp"]


def sizes(data: bytes) -> dict:
    return {
        "raw": len(data),
        "zstd19": len(zstd.compress(data, level=19)),
        "zstd3": len(zstd.compress(data, level=3)),
        "deflate6": len(zlib.compress(data, 6)),
        "deflate9": len(zlib.compress(data, 9)),
    }


def main() -> None:
    tree = Path(sys.argv[1])
    core = Path(sys.argv[2])
    out: dict = {}
    surfaces = sorted(p.name for p in (tree / "c_ttimg").iterdir() if p.is_dir())
    for candidate in CANDIDATES:
        per_kind = {k: {"raw": 0, "zstd19": 0, "zstd3": 0, "deflate6": 0, "deflate9": 0} for k in KINDS}
        per_surface: dict = {}
        for surface in surfaces:
            total = {"raw": 0, "zstd19": 0, "zstd3": 0, "deflate6": 0, "deflate9": 0}
            for kind in KINDS:
                if candidate == "a_png":
                    path = core / surface / f"{kind}.png"
                else:
                    matches = list((tree / candidate / surface).glob(f"{kind}.*"))
                    path = matches[0]
                s = sizes(path.read_bytes())
                for key, value in s.items():
                    per_kind[kind][key] += value
                    total[key] += value
            per_surface[surface] = total
        out[candidate] = {"kinds": per_kind, "surfaces": per_surface}
        whole = {key: sum(per_kind[k][key] for k in KINDS) for key in per_kind["albedo"]}
        out[candidate]["total"] = whole
        print(candidate, {k: round(v / 1e6, 2) for k, v in whole.items()}, "MB over", len(surfaces), "surfaces")
        for kind in KINDS:
            print("   ", kind, {k: round(v / 1e6, 2) for k, v in per_kind[kind].items()})
    (tree / "pack_sizes.json").write_text(json.dumps(out, indent=1))


main()
