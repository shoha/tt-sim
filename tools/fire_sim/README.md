# The fire's drawing book

The flames are drawn from a baked book of drawings, not from noise: 8 looping sequences of 48
drawings (96x128 texels, 12 a second) grown by a small 2D fire simulation, plus one tiling tear
layer. The game ships the book as `res://assets/fire/fire_book.res`, a `FireBook` resource
(`resources/fire_book.gd`, which documents each channel), stored in Git LFS. This folder holds the
tools that make it; nothing here is exported (every preset excludes `tools/*`), so runtime code
reads only the resource.

| File | What it does |
|------|--------------|
| `bake_fire_book.py` | the simulation and encoding; writes `fire_sim_book.bin` ("TTFSIM02") and contact sheets |
| `pack_fire_book.gd` | validates the `.bin`, builds each layer's mips and saves the compressed FireBook |

## Prerequisites

- Blender 5.2's bundled Python, which has numpy (dev only, never shipped; install nothing):
  `C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe`.
- Git LFS with the book pulled (`git lfs pull`). Without it `assets/fire/fire_book.res` is a
  pointer file, the flames draw nothing and `tests/unit/test_fire_book.gd` fails.

## Re-baking

Bake into a scratch folder, never into the repo (about 86 s, 11 s a sequence):

```
"C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" -I D:/dev/tt-sim/tools/fire_sim/bake_fire_book.py --out <scratch> --sheets <scratch>/sheets
```

`--out` is required; `--sheets` is optional (no sheets without it). `--only 0,5` bakes only those
sequences and writes only the sheets (no book), for quick looks while tuning; it needs `--sheets`.
Each sequence prints its body size, its mass height's spread over the loop, its band shares and
its bounds' area; rewriting a book over an old one also prints the bounds against the old book's.

Read the sheets before packing:

- `sheet_frames.png`: every drawing of the narrow sequence 1 and the wide sequence 6
  (`--sheet-seqs`), as the draw shows them at 1x. Look for lumpy bodies with separate tongues,
  torn flakes rather than round coins, no sequence going out.
- `sim_seam.png`: each sequence's drawings 42-47 then 0-5 in one row. The loop closes by a short
  morph; no drawing should pop at the seam.
- `sheet_tear.png`: every fourth drawing (0 to 20) of both at 3x through the draw's tear. Edges should read torn and
  notched, not smooth curves.

## Packing

```
godot --headless --path D:/dev/tt-sim --script res://tools/fire_sim/pack_fire_book.gd -- --in <scratch>/fire_sim_book.bin
```

The packer refuses anything but the book the flame shader is written for (magic "TTFSIM02", a
96x128 tile, at most 16 sequences, classes sorted, a size matching its header, 385 layers), writes
`res://assets/fire/fire_book.res` with `ResourceSaver.FLAG_COMPRESS`, reads it back and checks every
layer's bytes. Its last line gives the size, the source's sha256 (kept in the book as
`source_sha256`) and the save, load and texture times. `--out <path>` writes elsewhere.

The shipped book (2026-10-17) came from the round 6 look at spike-flipbook de7f3d16: its `.bin` is
18,923,704 bytes with sha256 `834da0babc340ff3c0179659e150cb0d905b07a77cc5703647c0391676b77a36`
(this script reproduces it exactly), and the packed resource is 12,252,468 bytes (11.7 MB, the
stored mips included); a headless load takes about 60 ms.

## After packing

1. `godot --headless --path D:/dev/tt-sim --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig_authoring.json -gselect=test_fire_book`
   (a changed sequence count changes this test and the packer's `EXPECTED_LAYERS` together).
2. `git -C D:/dev/tt-sim lfs status` lists `assets/fire/fire_book.res` as an LFS object to commit
   (`git -C D:/dev/tt-sim lfs ls-files` after the commit). `.gitattributes` routes
   `assets/fire/**` through LFS.
3. The export check: `godot --headless --path D:/dev/tt-sim --export-pack "Windows Desktop" <scratch>/check.zip`
   stores `res://assets/fire/fire_book.res` (the log's "Storing File" lines) and nothing from
   `tools/fire_sim`. Delete the zip afterwards.

## The smoke book

The smoke columns draw from a second, smaller book: 2 seeds of 24 held frames (128x160 RGBA8, no
mips), each a closed 12 s loop of the upright plume's signed distance, fake normal and tone
multiplier. It ships as `res://assets/fire/fire_smoke_book.res`, a `FireSmokeBook` resource
(`resources/fire_smoke_book.gd`), in Git LFS beside the flames' book. `fire_smoke_book_bake.gdshader`
here draws it; the GPU does the work, so the bake is a windowed render job, not a headless script:

```
godot --path D:/dev/tt-sim --windowed --resolution 1920x1080 --position 320,120 --script res://tools/render_jobs/run.gd -- fire_smoke_book
```

`probes/fire_smoke_book.gd` draws the atlas once, slices it, saves the book with
`ResourceSaver.FLAG_COMPRESS` and reloads it to check every byte; the job's last line gives the
file's size and the round trip. A step's `reference` (a shader path) bakes a second shader the same
way and compares it byte for byte. Then run `-gselect=test_fire_smoke_book` and check
`git lfs status` as for the flames' book.

The shipped smoke book (2026-10-18) is round 6's (spike-flipbook de7f3d16, which baked it at load):
baked with the spike's own `shaders/fire_smoke_flipbook_bake.gdshader` as the reference, all
3,932,160 bytes are equal, and the resource is 3,409,542 bytes (the compression saves little on
these smooth fields).
