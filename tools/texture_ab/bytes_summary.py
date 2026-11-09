"""Load cost and mixed-format totals from bytes_run.gd's bytes.json and pack_sizes.py's JSON.

Prints, per candidate, the average per-surface load cost (decode + bake to the in-memory baked
map, four maps) and, for hand-picked per-kind mixes, the packed totals over all surfaces
(deflate 6 is what a zip stores, zstd 19 the best a zstd depot does).

    python -I bytes_summary.py <tree>/bytes.json <tree>/pack_sizes.json
"""

import json
import sys

KINDS = ["albedo", "normal", "orm", "height"]
CANDS = ["a_png", "a8_png8", "b_webp_ll", "c_ttimg", "d95_webp", "d90_webp", "d85_webp"]

MIXES = {
    "A8: 8-bit PNG for all": dict.fromkeys(KINDS, "a8_png8"),
    "B: lossless WebP for all": dict.fromkeys(KINDS, "b_webp_ll"),
    "B + height 8-bit PNG": {"albedo": "b_webp_ll", "normal": "b_webp_ll", "orm": "b_webp_ll", "height": "a8_png8"},
    "D95 albedo+height, lossless normal+ORM": {"albedo": "d95_webp", "normal": "b_webp_ll", "orm": "b_webp_ll", "height": "d95_webp"},
    "D90 albedo+height, lossless normal+ORM": {"albedo": "d90_webp", "normal": "b_webp_ll", "orm": "b_webp_ll", "height": "d90_webp"},
    "D85 albedo+height, lossless normal+ORM": {"albedo": "d85_webp", "normal": "b_webp_ll", "orm": "b_webp_ll", "height": "d85_webp"},
    "D90 albedo+height+normal, lossless ORM": {"albedo": "d90_webp", "normal": "d90_webp", "orm": "b_webp_ll", "height": "d90_webp"},
    "D90 for all four": dict.fromkeys(KINDS, "d90_webp"),
    "D85 for all four": dict.fromkeys(KINDS, "d85_webp"),
}


def main() -> None:
    timings = json.load(open(sys.argv[1]))
    packs = json.load(open(sys.argv[2]))
    n = len(timings)
    print(f"load cost, ms per surface (4 maps), mean over {n} surfaces: decode / bake / total")
    for cand in CANDS:
        dec = sum(timings[s][k][cand]["dec_ms"] for s in timings for k in KINDS) / n
        bake = sum(timings[s][k][cand]["bake_ms"] for s in timings for k in KINDS) / n
        extra = ""
        if cand == "c_ttimg":
            z = sum(timings[s][k][cand]["zstd_ms"] for s in timings for k in KINDS) / n
            extra = f"  (+ zstd inflate {z:.1f})"
        print(f"  {cand:10s} {dec:6.1f} / {bake:6.1f} / {dec + bake:6.1f}{extra}")
    print("\nper-kind mixes, MB over all surfaces: raw / zstd19 / deflate6")
    for name, mix in MIXES.items():
        tot = {key: sum(packs[mix[k]]["kinds"][k][key] for k in KINDS) for key in ("raw", "zstd19", "deflate6")}
        print(f"  {name:42s} {tot['raw'] / 1e6:6.1f} / {tot['zstd19'] / 1e6:6.1f} / {tot['deflate6'] / 1e6:6.1f}")


main()
