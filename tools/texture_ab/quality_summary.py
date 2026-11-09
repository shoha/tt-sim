"""Compact table of quality_run.gd's JSON files.

For each lossy candidate and kind: over the surfaces in the files, the mean and worst (lowest)
PSNR of bake(candidate) against bake(PNG), the mean SSIM, the largest level difference, the
99.9th percentile (worst surface) and the share of samples over 4 levels (mean). Also the floor
(two bakes of the PNG) and the BC loss itself (bake(PNG) against the decoded PNG).

    python -I quality_summary.py q1.json q2.json ...
"""

import json
import sys

KINDS = ["albedo", "normal", "orm", "height"]
CANDS = ["d95_webp", "d90_webp", "d85_webp"]


def agg(rows: list, key: str) -> str:
    psnr = [r[key]["psnr"] for r in rows]
    ssim = [r[key]["ssim"] for r in rows]
    worst = max(r[key]["max"] for r in rows)
    p999 = max(r[key]["p999"] for r in rows)
    over4 = sum(r[key]["over4"] for r in rows) / len(rows)
    return (
        f"psnr mean {sum(psnr) / len(psnr):5.1f} min {min(psnr):5.1f} | "
        f"ssim mean {sum(ssim) / len(ssim):.4f} min {min(ssim):.4f} | max {worst:3d} p999 {p999:2d} "
        f"| >4: {over4 * 100:5.2f}%"
    )


def main() -> None:
    data: dict = {}
    for path in sys.argv[1:]:
        data.update(json.load(open(path)))
    print("surfaces:", ", ".join(sorted(data)))
    for kind in KINDS:
        print(f"== {kind}")
        rows = [data[s][kind] for s in data]
        print("  floor (bake vs bake)    ", agg([{"x": r["floor"]} for r in rows], "x"))
        print("  bc loss (bake vs source)", agg([{"x": r["bc_src"]} for r in rows], "x"))
        for cand in CANDS:
            sub = [r[cand] for r in rows]
            kb = sum(r["bytes"] for r in sub) / len(sub) / 1000
            print(f"  {cand} ({kb:6.1f} KB/map)")
            for key, label in (("png", "vs bake(PNG)"), ("src", "vs source   "), ("raw", "codec only  ")):
                print(f"      {label}", agg(sub, key))


main()
