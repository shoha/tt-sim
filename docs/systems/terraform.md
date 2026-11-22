# Terraforming core

The terrain redesign's core (approved 2026-11-22; design and plan:
`D:/dev/tabletop/docs/research/2026-11-22-terraform-audit/design.md` and `phase1_plan.md`). A map's
terrain becomes an ordered list of typed primitives (a plane, hills, a ridge, sculpt strokes,
rivers, ponds, paths, walls, paint coats), and every array the map shows or plays on is derived
from that list by a fixed chain of stages in C++. Erase is "remove the primitive", nothing is ever
frozen, and two peers holding the same list derive the same bits.

Phase 1 lands the core beside today's path and changes nothing the game draws or does. Card 1
(terraform-p1-native) moved the derive from the spike `terraform-s2-cpu` into `native/src`; nothing
in the game calls it yet. Later phase 1 cards add the stage table, the terrain section of
`map.ttmap` (format 6), the kind registry, the derived record and `TerraSession` behind a switch.

## Files

| File | What |
|---|---|
| `native/src/terra_core.h` | `Grid`, `Rect`, `Dirty` (one sub-rect per 64-sample tile), `Prim`, `Line`, resample, Chaikin, block pruning, `reads_hit` |
| `native/src/terra_math.h` | `det_exp`, `det_log`, `det_pow`, `det_atan`: the only transcendentals the derive uses |
| `native/src/terra_stages.h` | the stage functions' declarations and the opinionated constants (metres) and halos (samples) |
| `native/src/terra_kernels.h`, `terra_compose.cpp` | stage 1: the compose kernels (plane, hill, ridge, stroke) in a table |
| `native/src/terra_water.cpp` | stage 2 and 3: river and pond geometry, topology, solves, the carve |
| `native/src/terra_paths.cpp` | stages 3b and 4: paths and walls (line solves, then per-sample rects), paint coats |
| `native/src/terra_fields.cpp` | stages 5 and 6: slope, capped distances, the look field, the ground rules |
| `native/src/terra_derive.{h,cpp}` | the GDCLASS `TerraDerive`: setup, primitives, rules, derive, queries, digests |
| `utils/terraform/terra_core.gd` | `TerraCore`: `native_available()`, `NATIVE_VERSION`, the kind ids, `grid_for(doc)`, `make_derive(doc)`, `load_rules()`, `enabled()` (off) |
| `utils/terraform/rules/ground_rules.json` | the ground table (12 classes, 11 rows) and the look parameters the Painted cards read |

`utils/terraform/` is kept apart from `utils/terrain/` (today's shade field and back caster) so the
old code is easy to delete when the core replaces it.

## The grid

The derive grid is the map document's own frame, doubled. For a document of n samples on an axis
(`MapDocument.samples_x()`), the derive has `2 (n - 1) + 1`, spanning the same extent: sample
(i, j) sits at world `(-W/2 + i sx, -H/2 + j sz)` with `sx = W / (w - 1)` and `sz = H / (h - 1)`
computed in double inside `setup`. Every second derive sample is a document sample, so writing
derived heights into the document (phase 2) and the Painted read are strided copies. A 200 ft map
is 489 squared samples at 0.12492 m, a 320 ft one 781 squared; the document's 641-sample cap means
at most 1281 per axis. The two axes may differ by the document's rounding on a non-square map; the
slope and the distance transform use each axis's own step.

Primitive positions are world metres in that frame (the origin is the map centre); a plane's base
is its height at the centre. Halos are in samples, constants in metres.

## Primitives

A primitive is an id, a kind and a float list. Kind ids are stable and never reused: 0 to 8 are
built in, 9 to 15 reserved (one for phase 2's consolidated sculpt raster), new kinds start at 16.

| Id | Kind | Floats |
|---|---|---|
| 0 | plane | base, slope_x, slope_z |
| 1 | hill | cx, cz, height, radius, profile (the exponent of `(1 - t^2)`) |
| 2 | ridge | height, width, profile, then x, z per point |
| 3 | stroke | per dab cx, cz, radius, strength, mode (0 raise, 1 lower, 2 smooth) |
| 4 | river | width, depth, then x, z per point (drawn uphill is flipped) |
| 5 | pond | depth, then the outline's x, z per point |
| 6 | path | width, then x, z per point |
| 7 | wall | height, thickness, then x, z per point |
| 8 | paint | per dab cx, cz, radius, surface id |

Document order is the order compose applies. `append_dabs` grows a stroke or paint coat and dirties
only the new dabs' bounds.

## The stage chain

`derive()` runs the stages over what the pending edits dirtied; `derive_full()` over the whole map.
A stage's region is the change in its reads, grown by its halo, plus its own seeds; each stage
snapshots its outputs per tile and diffs them bit for bit (memcmp, so -0 and +0 differ), so the
next stage sees only real change. Every stage is a per-sample pure function of whole-map inputs
with a fixed summation order, so a rect gives the same bits as the whole map: update equals build.

| # | Stage | Reads | Writes | Halo |
|---|---|---|---|---|
| 1 | compose | compose prims | Hraw, SW | 0 (each kind's bounds) |
| 1b | smooth | Hraw, SW | H0 | `SMOOTH_R` 8 |
| 2 | water solve | H0 at each body's read points | levels, fall records | exact read hit (`reads_hit`) |
| 3 | carve | H0, levels | H1, WL | 0; a moved level dirties its arc bbox + `hw + BANK_REACH + 0.5` m |
| 3b | paths | H1, WL | Hp, PM | 0; a moved profile dirties `hw + 1.7` m |
| 4 | footprints | Hp, WL | H2, FM, WM | 0; a moved pad dirties `thick + 2` m |
| 5a | slope | H2 | SL | 1 |
| 5b | distances | WM, PM, FM | DW, DP, DF | `DIST_HALO` 48 |
| 5c | look | H2 | HB, CV | `LOOK_WIDE` 14 |
| 5d | paint | paint prims | PI, PW | 0 |
| 6 | rules | the fields, the ground table | CT | 0 |

H2 is the ground, WL the water level (H1 - 1 where dry), CT four control bytes a sample (base
class, overlay class, blend, wetness). The worker pool splits a stage by tile; the bits never
depend on the thread count. `derive_async()` runs a derive on a worker thread (a stroke's release);
poll `take_result()`, and touch nothing else until it returns a result.

## Portable maths

The derive is the authority peers agree on, so its digests must match on Windows, Linux and macOS
(x86_64 and arm64), unlike the scatter library, whose native parity is per platform. libm's `pow`,
`exp` and `atan` differ in their last bits between C runtimes, so the derive never calls them:
`terra_math.h` reduces the range and evaluates a fixed polynomial with `+ - * /` only, which IEEE
754 rounds identically everywhere under the build's `-ffp-contract=off` and no fast-math. `sqrt`,
`floor`, `frexp` and `ldexp` are exact by the standard and stay allowed. A new stage that needs
another transcendental adds it there. Hash noise is integer arithmetic.

## API (GDScript, through `TerraCore`)

`TerraCore.make_derive(doc)` returns a `TerraDerive` on the document's grid with the ground rules
set (null without the library). Then `set_prim(id, kind, floats)`, `append_dabs`, `remove_prim`,
`derive()` or `derive_full()`, and the queries: `height_at`, `water_at`, `raycast`, `falls()` (7
floats a record), `walls()`, `water_records()`, `tile_bytes(tile, kind)`, `tile_collision(tile,
stride)` (heights in metres and their step), `grid()`, `digests()` (FNV-1a of every array and record
list). C++ stages built on a derive read `derived()`, a view of every array.

## Versions and the library

`TerraDerive.version()` is `TerraCore.NATIVE_VERSION`, now `terra 1 core`; later cards step it
("terra 2 stages", "terra 3 kinds", "terra 4 cache"). The scatter library's string carries `terra`
(`ttscatter 10 curves water chunk fields wfield2 terra`), so a stale DLL fails
`test_scatter_native`. After pulling a change here, rebuild `native/` (AGENTS.md "Testing").
Without the library every terra test is pending with "the native library is not built", which CI
treats as a failure.

## Tests

| Test | Covers |
|---|---|
| `test_terra_update_equals_build.gd` | the corpus added one primitive at a time, a 40-dab held raise across both rivers, smooth, lower, an undone hill, a moved wall, an async river landing: every digest equals a fresh `derive_full` |
| `test_terra_determinism.gd` | two runs of one instance, serial against 1 and 8 workers, two instances deriving at once |
| `test_terra_water_laws.gd` | no level climbs downstream, the tributary joins and falls, the wall opens at the river, the pond holds water |
| `test_terra_golden.gd` | `version()`, and the corpus on a 40 x 40 and a 40 x 48 cell map against `tests/fixtures/terra_corpus_digests.json` |

`tests/unit/terra_corpus.gd` (`TerraCorpus`) is the spike's test scene placed on a map document's
frame. `.github/native/parity.sh` runs `test_terra_golden` on every platform CI builds, debug and
release, and fails if it is pending or does not report its matched digests. A platform that
disagrees is a bug in `terra_math.h`, never in the fixture. A deliberate change to the derive (a
stage, a constant, the ground rules) regenerates the fixture: the failing test prints the new
cases as JSON.
