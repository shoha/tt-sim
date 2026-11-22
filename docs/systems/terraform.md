# Terraforming core

The terrain redesign's core (approved 2026-11-22; design and plan:
`D:/dev/tabletop/docs/research/2026-11-22-terraform-audit/design.md` and `phase1_plan.md`). A map's
terrain becomes an ordered list of typed primitives (a plane, hills, a ridge, sculpt strokes,
rivers, ponds, paths, walls, paint coats), and every array the map shows or plays on is derived
from that list by a fixed chain of stages in C++. Erase is "remove the primitive", nothing is ever
frozen, and two peers holding the same list derive the same bits.

Phase 1 lands the core beside today's path and changes nothing the game draws or does. Card 1
(terraform-p1-native) moved the derive from the spike `terraform-s2-cpu` into `native/src`; nothing
in the game calls it yet. Card 2 (terraform-p1-stages) made the chain one loop over a stage table,
card 3 (terraform-p1-document) added the terrain section of `map.ttmap` (format 6), and card 4
(terraform-p1-kinds) the kind registry. Later phase 1 cards add the derived record and
`TerraSession` behind a switch.

## Files

| File | What |
|---|---|
| `native/src/terra_core.h` | `Grid`, `Rect`, `Dirty` (one sub-rect per 64-sample tile), `Prim`, `Line`, resample, Chaikin, block pruning, `reads_hit` |
| `native/src/terra_math.h` | `det_exp`, `det_log`, `det_pow`, `det_atan`: the only transcendentals the derive uses |
| `native/src/terra_stage_table.{h,cpp}` | `STAGES[]` and `ARRAYS[]`: every stage's reads, writes, halo (samples) and reach (metres), the body parameters the halos come from, and `stage_region`; the only place a halo is declared |
| `native/src/terra_stages.h` | the stage functions' declarations and the water rules' constants (metres) |
| `native/src/terra_pool.h` | the worker pool a stage splits its tiles over |
| `native/src/terra_kinds.{h,cpp}` | the kind registry: `KindDef`, the self-registering `TERRA_KIND(...)`, `kind_def(id)` (see "Kinds") |
| `native/src/kinds/terra_kind_<name>.cpp` | one kind each: plane, hill, ridge, stroke, terrace (compose stamps), paint (the paint stamp), path and wall (the line kinds' geometry, solve and rect) |
| `native/src/terra_compose.cpp` | stages 1, 1b and 5d: `stamp_rect` (a stamp stage's primitives applied by their kinds in document order), `smooth_rect` |
| `native/src/terra_water.cpp` | stage 2 and 3: river and pond geometry, topology, solves, the carve; the two water kinds register here |
| `native/src/terra_paths.cpp` | the line kinds' shared maths: `line_from`, `window_mean`, `grade`, `nearest_seg` |
| `native/src/terra_fields.cpp` | stages 5 and 6: slope, capped distances, the look field, the ground rules |
| `native/src/terra_derive.{h,cpp}` | the GDCLASS `TerraDerive`: setup, primitives and their seeds, rules, the stage loop, the three solves and the rect bodies' dispatch, queries, digests |
| `utils/terraform/terra_core.gd` | `TerraCore`: `native_available()`, `NATIVE_VERSION`, the built-in kind ids, `grid_for(doc)`, `make_derive(doc)`, `load_rules()`, `enabled()` (off) |
| `utils/terraform/terra_kinds.gd` | `TerraKinds`: the GDScript registry, one preload line per kind; `script_for(id)`, `name_of`, `ids()`, `table()`, `problem(id, data)` |
| `utils/terraform/kinds/<name>/<name>_kind.gd` | one script per kind (layout, `validate`, `bounds`, label, defaults); `kinds/kind_layout.gd` holds the checks they share |
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
| 16 | terrace | per dab cx, cz, radius, tier_m, softness (the riser's share of a tier, 0 to 1) |

Document order is the order compose applies. `append_dabs` grows a stroke, terrace or paint coat
and dirties only the new dabs' bounds. The terrace is not additive: it pulls the height composed so
far toward its tiers, so a terrace after a hill steps that hill.

## Kinds

Every kind is registered twice, once per side, and `test_terra_kinds` fails when the two disagree on
an id, name, stage, shape, header or stride (card terraform-p1-kinds, 2026-11-22).

- **Native:** `native/src/kinds/terra_kind_<name>.cpp` holds the kernel and ends in one line,
  `TERRA_KIND(16, "terrace", STAGE_COMPOSE, 0, 5, terrace_bounds, terrace_apply);`: a static
  registrar that runs when the library loads (SCons links every object file of `src/` and
  `src/kinds/`), so no table names a kind. `bounds` is the world box an edit can change, reaches
  included (a river's carve, a path's bench, a wall's pad), which is what the edit seeds; `apply` is
  a stamp's per-sample kernel (null for a line or water kind). The table is kept sorted by id and
  every lookup is by id, so nothing depends on the order the linker ran the registrars in (tested by
  `debug_kinds_in_order`); a repeated id is counted (`kind_conflicts()`, 0 in a sound build). A kind's
  stage decides its shape (a rect stage: stamp, a line stage: line, the graph stage: water) and the
  input its edits seed. `set_prim` refuses an unregistered id (returns false, nothing changes).
- **GDScript:** `utils/terraform/kinds/<name>/<name>_kind.gd` declares `NAME`, `ID`, `STAGE` (the
  native stage's name), `SHAPE`, `HEADER`, `STRIDE`, `MIN_ITEMS`, `LABEL`, `DEFAULTS` and static
  `validate(data) -> bool`, `bounds(data) -> Rect2` (the native box, empty for the whole map) and
  `describe()`; `TerraKinds.KINDS` lists one preload line per kind. The map reader and writer
  (`MapTerrainIO`) take kind names and validation from it: an unknown id refuses the whole section
  ("made by a newer version"), a primitive its kind's `validate` refuses is dropped.

| Shape | Kinds | How the stage runs it |
|---|---|---|
| stamp | plane, hill, ridge, stroke, terrace (compose); paint (paint) | `stamp_rect`: zero the stage's outputs over the rect, then each primitive whose bounds meet it, in document order |
| line | path (paths), wall (pads) | the stage's solve builds and grades each line, then its rect body |
| water | river, pond (water_solve) | one graph solve over every body (`terra_water.cpp`) |

A new tool is one kind folder, one kernel file and one registry line, plus a rebuild: the terrace
was added that way (its folder, its kernel and the `KINDS` line; the test corpus, the golden case
and the update equals build step are tests). A water kind is the exception: water is one graph
solve, so a new one (a spring, say) is an edit of `terra_water.cpp`. A new rule is one row in
`ground_rules.json`; a new stage is a `StageDef` row and its body.

## The stage chain

`derive()` runs the stages over what the pending edits dirtied; `derive_full()` over the whole map.
It is one loop over `STAGES[]` (`terra_stage_table.h`), whose rows declare each stage's shape,
reads, writes and halo; nothing else names a halo. The arrays are inputs (the primitive groups and
the ground table, changed where the pending edits seeded them), per-sample arrays and one solved
record (the water levels). A rect stage's region is the change in its per-sample reads grown by its
halo, plus the change in its input and record reads, plus the seeds its own line solve added. The
loop snapshots each per-sample write per tile, runs the body and diffs each write bit for bit
(memcmp, so -0 and +0 differ), so the next stage sees only real change, array by array. A solve
tests its read points against the change in its per-sample reads, ungrown. Every stage is a
per-sample pure function of whole-map inputs with a fixed summation order, so a rect gives the
same bits as the whole map: update equals build. A `static_assert` (`table_ok`) proves the order:
each read is an input or an earlier stage's write, and each array has one writer.

| # | Stage (`name`) | Shape | Reads | Writes | Halo (samples) |
|---|---|---|---|---|---|
| 1 | compose | rect | compose prims | Hraw, SW | 0 (each kind's bounds seed it) |
| 1b | smooth | rect | Hraw, SW | H0 | `SMOOTH_R` 8 |
| 2 | water_solve | graph | H0 at each body's read points, water prims | levels | exact read hit (`reads_hit`) |
| 3 | carve | rect | H0, levels | H1, WL | 0; a moved level marks its arc bbox + `hw + CARVE_REACH_M` (5.5 m) as changed levels |
| 3b | paths | line + rect | H1, WL, path prims | Hp, PM | 0; a moved profile seeds `hw + PATH_REACH_M` (1.7 m) |
| 4 | pads (footprints) | line + rect | Hp, WL, wall prims | H2, FM, WM | 0; a moved pad seeds `thick + PAD_REACH_M` (2 m) |
| 5a | slope | rect | H2 | SL | `SLOPE_R` 1 |
| 5b | distance | rect | WM, PM, FM | DW, DP, DF | the largest cap, 48 (caps 48 / 24 / 24) |
| 5c | look | rect | H2 | HB, CV | `LOOK_WIDE` 14 |
| 5d | paint | rect | paint prims | PI, PW | 0 |
| 6 | rules | rect | H2 WL SL DW DP DF PW PM PI CV, ground table | CT | 0 |

`derive()` returns `usec` and `work` (tiles run) per stage name, `work.water_solved` (bodies
solved), and the changed tiles per layer. Card 2 kept every body as it was; the regions follow the
declared reads, so pads no longer re-run where only H1 or PM changed and rules no longer where only
H1 or HB did (their bodies never read them), and CT's change is the samples that changed rather
than the whole tile rect. The golden digests did not move.

A new stage is a row in `STAGES[]` (and an array in `ARRAYS[]` for each new output), a body in
`TerraDerive::rect_body` or a solve, and nothing in the loop.

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
list). C++ stages built on a derive read `derived()`, a view of every array. For tests and this
doc: `stages()` (the table: name, shape, reads, writes, halo, reach_m), `arrays()` (name, kind,
bytes a sample), `array_bytes(name)` (a per-sample array's whole-map bytes) and
`debug_set_sample(name, i, j, value, dirty_all)` (sets one sample outside the chain and marks it,
or the whole array, changed for the next `derive()`). The registry: `kinds()` (per kind id, name,
stage, shape, header, stride, ascending id), `kind_bounds(kind, floats)` (a primitive's world box),
`kind_conflicts()` and `debug_kinds_in_order(order)`.

## Versions and the library

`TerraDerive.version()` is `TerraCore.NATIVE_VERSION`, now `terra 3 kinds`; the cache card steps it
("terra 4 cache"), and the golden fixture's `version` follows it. The scatter library's string carries `terra`
(`ttscatter 10 curves water chunk fields wfield2 terra`), so a stale DLL fails
`test_scatter_native`. After pulling a change here, rebuild `native/` (AGENTS.md "Testing").
Without the library every terra test is pending with "the native library is not built", which CI
treats as a failure.

## Tests

| Test | Covers |
|---|---|
| `test_terra_update_equals_build.gd` | the corpus added one primitive at a time, a 40-dab held raise across both rivers, smooth, lower, an undone hill, a moved wall, a 12-dab held terrace, an async river landing: every digest equals a fresh `derive_full` |
| `test_terra_kinds.gd` | the two registries agree; ids and names unique, none in 9 to 15; registration order never changes the table; each kind accepts the corpus (and the terraced corpus) and refuses a short, long, too-few-items, NaN, Inf or out-of-range layout and its own field ranges; GDScript and native bounds agree; `set_prim` and the map reader refuse an unknown id |
| `test_terra_determinism.gd` | two runs of one instance, serial against 1 and 8 workers, two instances deriving at once |
| `test_terra_water_laws.gd` | no level climbs downstream, the tributary joins and falls, the wall opens at the river, the pond holds water |
| `test_terra_golden.gd` | `version()`, and the corpus on a 40 x 40 and a 40 x 48 cell map, plus the terraced corpus on 40 x 40, against `tests/fixtures/terra_corpus_digests.json` |
| `test_terra_stage_table.gd` | the table's order (each read an input or an earlier write, one writer per array); halo honesty: one H2 sample (then one FM sample) of a built map set outside the chain, every downstream stage re-run over the whole map, and each array changes only within the reach the table declares from it (the halos summed along the way), with the incremental derive giving the same bytes. A halo one sample short fails it (checked 2026-11-22 with the look row at 13) |

`tests/unit/terra_corpus.gd` (`TerraCorpus`) is the spike's test scene placed on a map document's
frame. `.github/native/parity.sh` runs `test_terra_golden` on every platform CI builds, debug and
release, and fails if it is pending or does not report its matched digests. A platform that
disagrees is a bug in `terra_math.h`, never in the fixture. A deliberate change to the derive (a
stage, a constant, the ground rules) regenerates the fixture: the failing test prints the new
cases as JSON.
