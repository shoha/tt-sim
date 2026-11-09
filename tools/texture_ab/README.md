# Texture A/B harness (perf audit 2026-11, card textures)

What a surface map SHIPS as, judged by what the player SEES. The player never sees a surface PNG:
`SurfaceBake` turns it into BC7 (albedo), BC5 (normal), BC1 (ORM) or L8 (height) with a mip chain
at first use. So a candidate format is compared on candidate -> decode -> `SurfaceBake.bake` ->
decompress against the same chain from the shipped PNG, with the encoder's own run-to-run noise
(two bakes of the PNG) as the floor. Nothing here changes a shipped asset or the game.

Candidates (`texture_ab.gd` `CANDIDATES`): `a_png` the file as shipped, `a8_png8` the decoded image
re-saved by Godot as an 8-bit PNG (the shipped height maps are 16-bit PNGs; the game reads them as
L8), `b_webp_ll` lossless WebP, `c_ttimg` the baked map in the `SurfaceCache` file format (no decode
and no bake at load), `d95_webp` / `d90_webp` / `d85_webp` lossy WebP at quality 95 / 90 / 85 (then
the runtime bake as today).

Tools (headless runs need no lane; the render and sheet steps do):

- `bytes_run.gd`: writes every candidate's files for `--surfaces=all|a,b` under `--out=<dir>` and
  `bytes.json` (bytes, encode / decode / bake ms, exactness of the lossless ones, Godot-zstd decode
  of the ttimg).
- `pack_sizes.py <tree> <core surfaces dir>`: bytes after zstd 19, zstd 3 and deflate 6 / 9, each file
  alone (a zip entry or pck member), per candidate and kind. Standard library only.
- `quality_run.gd`: PSNR, SSIM (8x8 blocks), max level difference, 99.9th percentile and the share
  over 4 levels, per surface and kind, for the lossy candidates against the PNG's bake, plus the
  floor.
- `install_arm.gd` + `ab_look.json`: `install_arm.gd --arm=<png|d95m|d90m|d85m|d85all>` rebuilds
  the `.ttimg` files in the user cache from the candidate's pixels (same hash folder, so the game
  takes them as cache hits), and the render job captures home and zoom 4 of the same seeded map.
  One render run per arm, `--out render_jobs/textures_<arm> --full`.
- `sheet.gd`: windowed; assembles labelled 1:1 crops of the arms' captures into one JPG, plus the
  amplified difference from the reference arm and the whole-frame difference numbers.
- `texture_sheet.gd`: windowed; the worst case, the baked texture itself at 1:1 texels, PNG against
  the lossy candidates with the amplified difference.
- `quality_summary.py`, `bytes_summary.py`: compact tables of the JSON the runners write (quality per
  kind and candidate; load cost per candidate and packed totals for per-kind mixes).
- `jpg_fit.gd`: trims a sheet's window margin and limits it to 1600 px for the review board.

Measured 2026-11-09 on the 39 core surfaces and the 100 ft temperate forest map (the card's
report is `docs/plans/handoffs/textures.md` in the checkout that ran it): the shipped height maps
are 16-bit PNGs (78 of the 151 MB) that the game reads as L8; see the report for the numbers.
