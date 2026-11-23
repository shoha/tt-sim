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
(terraform-p1-kinds) the kind registry, card 5 (terraform-p1-cache) the derived record ("The
derived record"), and card 6 (terraform-p1-session) the `TerraSession` that attaches the core to a
loaded map behind a switch, off by default ("The session").

## Files

| File | What |
|---|---|
| `native/src/terra_core.h` | `Grid`, `Rect`, `Dirty` (one sub-rect per 64-sample tile), `Prim`, `Line`, resample, Chaikin, block pruning, `reads_hit` |
| `native/src/terra_math.h` | `det_exp`, `det_log`, `det_pow`, `det_atan`: the only transcendentals the derive uses |
| `native/src/terra_stage_table.{h,cpp}` | `STAGES[]` and `ARRAYS[]`: every stage's reads, writes, halo (samples) and reach (metres), the body parameters the halos come from, and `stage_region`; the only place a halo is declared |
| `native/src/terra_stages.h` | the stage functions' declarations and the water rules' constants (metres) |
| `native/src/terra_pool.h` | the worker pool a stage splits its tiles over |
| `native/src/terra_kinds.{h,cpp}` | the kind registry: `KindDef`, the self-registering `TERRA_KIND(...)`, `kind_def(id)` (see "Kinds") |
| `native/src/kinds/terra_kind_<name>.cpp` | one kind each: plane, hill, ridge, stroke, terrace, level, sculpt (compose stamps), paint (the paint stamp), path and wall (the line kinds' geometry, solve and rect) |
| `native/src/terra_compose.cpp` | stages 1, 1b and 5d: `stamp_rect` (a stamp stage's primitives applied by their kinds in document order), `smooth_rect` |
| `native/src/terra_water.cpp` | stage 2 and 3: river and pond geometry, topology, solves, the carve; the two water kinds register here |
| `native/src/terra_paths.cpp` | the line kinds' shared maths: `line_from`, `window_mean`, `grade`, `nearest_seg` |
| `native/src/terra_fields.cpp` | stages 5 and 6: slope, capped distances, the look field, the ground rules |
| `native/src/terra_consolidate.cpp` | `TerraDerive.consolidate(ids)`: a run of sculpt primitives folded into sculpt rasters (see "Sculpt kinds and folding") |
| `native/src/terra_derive.{h,cpp}` | the GDCLASS `TerraDerive`: setup, primitives and their seeds, rules, the stage loop, the three solves and the rect bodies' dispatch, queries, digests |
| `utils/terraform/terra_core.gd` | `TerraCore`: `native_available()`, `NATIVE_VERSION`, the built-in kind ids, `grid_for(doc)`, `make_derive(doc)`, `load_rules()`, `enabled()` (the switch: `tt_sim/terrain/core`, default off; `switch_override` for tests) |
| `utils/terraform/terra_cache.gd` | `TerraCache`: the derived record (`terrain/derived.bin`, digests only): `make_record`, `prepare`, `derive_for`, `check`, `derive_and_check`, `encode` / `decode` |
| `utils/terraform/terra_session.gd` | `TerraSession`, a Node: the core attached to a loaded map (see "The session") |
| `utils/terraform/terra_bridge.gd` | `TerraBridge`: the session's derived ground and water written into `MapDocument.heights`, `water_bodies` and `pond_mask` (see "The bridge"); `seed_new_map` |
| `utils/terraform/landform_prims.gd` | `LandformPrims`: a new map's starting landform as primitives (switch on; "The bridge", "New maps") |
| `utils/terraform/terra_water_bridge.gd` | `TerraWaterBridge`: `water_records()` and `falls()` as `WaterBody` reaches and ponds and the pond mask; the signature, the changed region |
| `scenes/states/authoring/terra_editor.gd` | `TerraEditor` (`AuthoringEditor.terra`): gestures as history entries, the inverse builder, the shared landing, the tool routes and the peers' apply (see "The editor") |
| `native/src/terra_bridge.cpp` | `TerraDerive.doc_heights()` and `doc_heights_diff()`: H2 at the document's samples, whole or as the tight differing rect |
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
built in, 9 is the folded sculpt raster, 10 to 15 reserved, new kinds start at 16.

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
| 9 | sculpt | x0, z0, sx, sz, nx, nz, layers, then nx * nz height deltas (and as many smoothing-weight deltas with 2 layers): a folded run (see "Sculpt kinds and folding") |
| 16 | terrace | per dab cx, cz, radius, tier_m, softness (the riser's share of a tier, 0 to 1) |
| 17 | level | per dab ax, az, bx, bz (one frame's capsule), radius, target_y, strength, edge (0 flatten, 1 tier, 2 tier cut) |

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

## Sculpt kinds and folding

Card terraform-p2-sculpt-kinds (2026-11-22) ported today's sculpt (`HeightBrush`, `HeightStroke`)
onto primitives for card 6's tools:

- **Raise, Lower, Smooth: stroke (3).** The falloff is HeightBrush's `(1 - t^2)^2`. A held frame's
  capsule becomes point dabs at most radius / 4 apart (`StrokeKind.capsule_dabs`), sharing the
  frame's exposure so they lay down the capsule's volume (`KindLayout.capsule_points`); raise and
  lower carry `HeightBrush.raise_speed(radius)` x seconds metres. Smooth dabs add seconds of
  exposure to SW; the smooth stage moves a sample by `1 - exp(-4 SW)` toward the mean of a box whose
  variance grows with the exposure (HeightStroke's repeated per-dab smoothing is diffusion; the one
  pass matches it to second order), box sums from an exact fixed-point summed-area table, half width
  up to `SMOOTH_R` 24 samples.
- **Flatten, Tier, Tier cut: level (17).** Capsule dabs (HeightStroke's distance to the segment):
  flatten approaches `target_y` by `1 - exp(-4 w seconds)` per dab; a run of tier dabs at one target
  is one completed tier stroke, `HeightBrush.tier_goal` ported to C++ (`LevelKind.flatten_dab`,
  `tier_dab`).
- **Against HeightStroke** (`test_terra_sculpt_kinds`, the same 60-frame stroke both ways, 200 ft
  map, radius 3 m, 2 s): raise and lower within 3.0 mm, flatten 17.2 mm, tier and tier cut under
  0.1 mm, smooth 150 mm at worst (1.3 cm mean; the card's bar was 5 cm, missed: one pass cannot
  follow 60 passes where the blur is as wide as the feature; the exact port is open).
- **Folding.** `TerraDerive.consolidate(ids)` (`terra_consolidate.cpp`) takes a run of consecutive
  compose primitives (strokes, levels, terraces) and returns one sculpt raster per 64-sample tile the
  run changed: compose from the same start without and with the run, the difference as heights and,
  where the run smoothed, a second layer of smoothing weight. Put in the run's place by one splice,
  the rasters derive within 2e-7 m of the run; the inverse splice restores every digest. Peers get
  the rasters as data. A fold freezes the run's reading of the ground before it (a level or terrace
  over a hill moved later); a folded smooth stroke's weight stays live. Tiles run on the pool;
  nothing is written; empty while an async derive runs. At 320 ft, 4096 dabs: consolidate 6.9 ms, 124
  rasters, full derive 28.4 ms folded (30.4 live). `TerraSculpt` (when to fold: KEEP_LIVE 8,
  CONSOLIDATE_DABS 4096) is card 6's.

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
| 1b | smooth | rect | Hraw, SW | H0 | `SMOOTH_R` 24 |
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
list; the arrays hash in parallel on the pool, one chain each, unless an async derive holds it).
C++ stages built on a derive read `derived()`, a view of every array. For tests and this
doc: `stages()` (the table: name, shape, reads, writes, halo, reach_m), `arrays()` (name, kind,
bytes a sample), `array_bytes(name)` (a per-sample array's whole-map bytes) and
`debug_set_sample(name, i, j, value, dirty_all)` (sets one sample outside the chain and marks it,
or the whole array, changed for the next `derive()`). The registry: `kinds()` (per kind id, name,
stage, shape, header, stride, ascending id), `kind_bounds(kind, floats)` (a primitive's world box),
`kind_conflicts()` and `debug_kinds_in_order(order)`.

## The derived record

Card terraform-p1-cache (2026-11-22). Digests only, never the arrays (owner, 2026-11-22: "we can go
with teh checksum approach"; plan Q1): a derive takes tens of milliseconds, the arrays would add
megabytes to every map and its late-join transfer, and the three-platform golden shows the derive
agrees everywhere CI builds. `TerraCache` (`utils/terraform/terra_cache.gd`) makes and checks it;
`MapTerrainIO` writes it as `terrain/derived.bin` beside `terrain/prims.bin` (format 6 only; bytes in
map_document.md "Terrain section (format 6)"), and `TerraDoc.derived` holds it in memory (`{}` for
none).

- **The key** is `TerraDoc.derive_key(size, extent)`: SHA-256 over the canonical `prims.bin` bytes with
  `next_id` written as 0, the derive grid (`TerraDoc.grid_bytes`) and `NATIVE_VERSION`. `next_id` is
  left out because the derive never reads it (it reads ids, kinds, flags, floats and order, all still
  covered), so an add and its undo keep the key; `TerraDoc.digest()` keeps `next_id`, because peers
  must agree on the id the next add takes. The record also stores the grid bytes and the core
  version, so `miss_reason` can say which part moved ("version", "grid" or "primitives").
- **The digests** (`TerraCache.DIGESTS`, 22): FNV-1a 64 of each per-sample array (Hraw SW H0 H1 WL
  Hp H2 SL DW DP DF PW HB CV PM FM WM PI CT), of the fall records (`falls`) and of the wall pads and
  openings (`walls`), all from `digests()`; and `water`, the first 8 bytes of SHA-256 over
  `water_records()` (river ids, receivers, half widths, fall counts, levels and lines; pond ids and
  levels), hashed in GDScript since the records are small. The intermediates are kept beside the
  arrays the game reads (H2, WL, CT, the water, falls and pads) because a mismatch that names the
  first diverging stage is the useful report.
- **At load** (`derive_and_check(terra, doc)`, which card 6's session calls): `derive_for` sets every
  primitive that is not muted in document order and runs `derive_full`, then `check` compares. A key
  that misses is quiet (status `miss`: the map simply re-derives); equal digests are `match`; any
  digest that differs is `mismatch`, warned once (one line naming every differing array and the
  count), the cross-machine determinism check peers rely on. The derive is handed back for reuse.
- **At save** `MapTerrainIO.serialize` writes the record only while its key matches the document, so
  an edit after the record was made drops it rather than saving it stale.
- **Size and time** (headless, indicative, 2026-11-22, the terraced corpus): the record is 331 bytes
  at every map size. Derive plus compare: 17.5 ms at 200 ft (489 x 489 samples: derive 15.3 ms,
  compare 2.1 ms) and 37.7 ms at 320 ft (781 x 781: 33.1 ms and 5.2 ms). With `digests()` serial the
  compare was 13.7 ms and 34.8 ms, as much as the derive at 320 ft, which is why it now runs on the
  pool (same values; the golden is unchanged).

## The session

Card terraform-p1-session (2026-11-22). `TerraSession` (`utils/terraform/terra_session.gd`, a Node
named `TerraSession` under the map root) is the core attached to a loaded map. Nothing reads it in
phase 1; phase 2's first card writes its derived heights into `MapDocument` (the S4 bridge).

- **The switch.** `TerraCore.enabled()` reads the project setting `tt_sim/terrain/core` (default
  false; `TerraCore.switch_override` forces it in tests). `MapSourceLoader.add_terra_session(root,
  doc)` is called from `_create_authored_root_async` right after the root shell is made, and adds a
  session only when the document has a terrain section, the switch is on and the library is built.
  Play and authoring open authored maps through that one function (`AuthoringController` and
  `LevelLoader` both call `build_async` / `load_async`). The loader finds the terraform scripts by
  path, so a map without a section never loads them and the start-up script graph is unchanged.
  Switch off: no node, no `TerraDerive` (`TerraCore.derives_made` counts them), no signal; the built
  map's `MapFingerprint` equals the stripped map's in every key but `terra` (which reports the
  section).
- **Attach.** `attach(doc)` runs `TerraCache.derive_and_check` on a copy of the terrain document on a
  WorkerThreadPool task and keeps the derive it returns, so the full derive (about 33 ms at 320 ft,
  plus 5 ms of digests) overlaps the chunk build. `check` holds the result (status none, miss, match
  or mismatch, warned once).
- **Edits.** `apply(edit)` (`{"op": add | replace | append | remove | mute | unmute | move, ...}`)
  changes `doc.terra` at once and tells the derive the same change (`set_prim`, checked;
  `append_dabs`; `remove_prim`; a muted primitive is left out, since the derive has no flags; unmute
  and move re-set the primitives from that position, since the derive has no move), then starts
  `derive_async()`. An edit while a derive runs is queued and told on the landing; a told add, replace
  or re-set carries a copy of its floats, since `TerraDoc.append` grows the document's array in place
  (shared by reference): before card terraform-p2-sculpt round 3 a held add whose primitive a later
  frame appended to told those floats twice, and the settled derive no longer answered for its
  document (`test_terra_interleave`: shuffled releases, presses, undos and redos). Returns the
  primitive's id, or -1 with nothing changed.
- **Queries.** `is_ready()` (the plan's `ready()`; a Node already has a `ready` signal) is true when a
  derive has landed, none runs and no edit waits; `height_at`, `water_at` (NAN until then) and
  `digests()` (`{}` until then) answer only then, so the derive is never read while it writes.
  `settled` fires when it turns true.
- **Polling.** `_process` runs only while a task or derive is in flight and never waits: work is
  landed only once `is_task_completed` or `not is_busy()`.
- **Closing.** A session freed mid-derive parks its task or busy derive in a static list, let go once
  complete (polled on `process_frame`, `PainterZoneMaps`' pattern): `TerraDerive`'s destructor joins
  its thread, so dropping a busy derive would block.
- **Saving.** `attach` sets `TerraDoc.before_save` to `capture_for_save()`, which
  `MapDocumentSnapshot.capture()` calls first: when the session is ready and the record is not the
  settled derive's, it sets `terra.derived = TerraCache.make_record(...)`. While a derive runs the
  record is left alone and the writer drops it if stale.
- **Load A/B** (headless, indicative, 2026-11-22, another card's gate running beside it): a 320 ft
  flat map with the corpus through `build_async`, 5 rounds after a warm-up. Root ready: switch off
  median 257 ms (218 to 282), on 230 ms (221 to 284): no difference within the noise. The session
  landed one frame after the root in every round, a median of 14 ms later.

## The bridge

Card terraform-p2-bridge (phase 2 card 1, 2026-11-22; plan `phase2_plan.md` section 2). With the
switch on, on a map with a terrain section, the core is the ground truth: `TerraBridge` writes the
session's derived ground H2 into today's `MapDocument.heights` (document sample (a, b) is derive
sample (2a, 2b)) and its water into `water_bodies` and `pond_mask`, and the game's own consumers
build from them unchanged. The bridge law (`test_terra_bridge_law.gd`): after every landing
`doc.heights == derive.doc_heights()` bit for bit, and the bodies and mask equal `water_of(derive)`.

- **Load.** `MapSourceLoader._create_authored_root_async` adds the session first, waits for the
  attach's derive a frame at a time (`TerraSession.attaching()` / `poll()`), makes the bridge and
  swaps the whole height array (`swap_heights`) before `AuthoredLoadPrep` and the terrain build,
  so chunks, collision and skirt are built once, from the derive. A whole swap happens only there
  and in a new map's build: later swaps would strand the references `AuthoredTerrain` keeps.
- **Landings.** `TerraSession.take_changed()` is the union of the H2 rects (derive samples, the
  native `h2_rect` of each derive) since the last call; the bridge halves it (`doc_rect`), asks
  `doc_heights_diff` for the tight rect whose bits differ and writes it row by row in place. The
  rect goes to the authoring editor's queue (`HeightEditor.external_rect` during an external
  stroke, else `queue_heights` and `work`) or, without an editor, to the map's `AuthoredTerrain`
  (chunks, and the collision and settle on a release).
- **Held frames.** `TerraBridge.held(edit)`: `TerraSession.apply_held` tells the derive and runs
  `derive()` synchronously when nothing is in flight (else it queues as `apply` does), then
  `land(true)` writes heights only. Releases, undo and live ops use `apply` (async); `settled`
  lands them with `land(false)`, heights then water.
- **Water** (card terraform-p2-bridge-water). `TerraWaterBridge.bodies(records, falls, doc)`
  (`TerraBridge.water_of(derive, doc)`) turns `water_records()` into today's model: one
  `WaterBody.river` per run of equal levels (a flat reach), consecutive reaches sharing the
  midpoint of the segment their level steps across (where WL changes level, and where a fall
  record sits, so `WaterFalls` finds the same lips), every 4th point of the 0.25 m line kept
  (WaterGeometry smooths it again); the record's half-width; the depth class nearest the
  primitive's depth, ties deeper (so `WaterMeshBuilder.hold_depth` never calls the carved bed
  perched); points past the map edge as the first reach's `beyond_up` and the last one's
  `beyond` (`RiverExits.split_line`). Ponds: the record's level, the outline rounded as the derive
  rounds it (Chaikin x3, closed) and rasterised into `pond_mask`. Ids: rivers in document order,
  their reaches downstream, then ponds, from 1, so a reload or a late joiner derives the same.
  Past `MAX_RIVERS` or `MAX_WATER_BODIES` it returns an error and the bridge leaves the water as
  it was (warned), never truncating; the tools check the caps first (card terraform-p2-water).
  Written only when `TerraWaterBridge.signature` (the water digest, the fall records, the water
  primitives' floats) moves, never on a held frame: at load by `swap_water` before
  `AuthoredLoadPrep` (so the dressing, flow and water build from it), and on `settled`, where the
  changed region (`TerraWaterBridge.region`: changed rivers' bounds, changed mask samples) goes to
  `WaterEditor.land_external(rect, record)`: an edit's `_land` / `_settle` / `_finish` without
  plan and carve (dressing, AuthoredWater, wet rocks through `WaterWetRocks`, followers,
  regrowth), filling `record` (`TerraBridge.last_water_record`) instead of the history; without
  an editor the bridge refreshes the dressing and AuthoredWater itself. Measured on the corpus at
  200 ft: 80 of 4677 derive-wet samples differ from today's wet set, all on the shoreline; the
  fall's lip, top and bottom equal the record's. A switch-on new map's water is its landform's
  rivers and ponds as primitives (see "New maps").
- **HeightEditor hooks** for later cards: `begin_external` / `external_rect` / `end_external` (a
  stroke whose heights another writer puts in; returns the ground record instead of recording)
  and `apply_ground(rect, before, record, redo, spread)` (`apply_diff` without the heights diff).
- **New maps** (`NewMapBuild`, switch on; card terraform-p2-landforms): the starting landform is
  made of primitives. `LandformPrims.apply(kind, doc, seed, biome)` (`utils/terraform/landform_prims.gd`,
  called by `NewMap.create` through the spec's `prims`, the script loaded by path) runs the recipe
  first (`StartingLandform.apply`: every seeded draw, chance and painted surface is the switch-off
  map's), then reads its shape from the recipe's `form` hints and its carved rivers, and adds: a
  plane; Valley a negative ridge on the bent axis (profile 2, its value at the floor's edge the
  floor's mean depth), flatten level dabs along the floor toward its fall, a bluff as one tier-cut
  run along the bank (a narrow bench under the face where the recipe had the cosine slope), a dry
  wash as paint; Hilltop hills (profile 2.3 for the cosine bump), the crown as one tier run (a disc
  and 12 lobes on its warped outline), the ledge as tier dabs along its arc; Terraces per plateau,
  lowest first, one tier run of capsule spines filling its rounded box (step edge wobbled by the
  recipe's noise); Lakeshore the plane raised by the rise with a negative hill about the lake, the
  lake a pond on the warped shore that goes round an islet hill by a slit; Gorge tier-cut dabs along
  the axis toward the floor's falling height; LandformGrowth's knolls as hills and tarns as ponds;
  each river run as one river (its widest width, its depth class; an end inside the map reaches 1 m
  on so it joins a lake or the river it meets). One synchronous derive_full, the heights and water
  swapped in, the record made, then the recipe's crossings placed again on the derived water
  (`place_crossing`, or an arch's `span_crossing` on its anchors). Checked at seeds 1234, 7 and 99
  per landform (`test_landform_prims`): the report's features, stage, water and crossings match the
  switch-off recipe. `TerraBridge.seed_new_map` (one plane) remains for a document without a section
  after the build (the proving ground).
- **Flat reaches.** River levels start from today's conditioner (`WaterConditioner.fit_levels`),
  scaled with the slope (card terraform-p2-reaches, `native/src/terra_stages.h`): the running
  minimum on the 5 cm lattice (`LEVEL_QUANTUM_M`); a sharp drop of `FALL_MIN` (0.75 m) within
  `FALL_RUN` (1.5 m) pinned as one fall step at most every `FALL_GAP` (6 m), running on down a
  cliff while each further `FALL_CLIFF_RUN` (1 m) still drops at `FALL_CLIFF_SLOPE` (0.3) or more,
  so a riser is one tall fall at its lip; the river split into sections at its fall-sized steps
  (the pinned falls, the join); per section a dead band of its mean slope times `REACH_TARGET_M`
  (8 m) within `REACH_DEAD_BAND_M` (0.5 m) and `REACH_DEAD_BAND_MAX_M` (0.7 m, so the sweep makes
  riffles only) swept from the outlet up; reaches under `MIN_REACH_M` (6 m) merged into the
  neighbour they differ from least, across any step but a section's bound, so where the slope
  steepens two riffles become a small fall and two falls a taller one. Every step of 0.75 m or more
  is a fall record; the carve's water stands at the nearer point's reach (the bed eases across the
  step), so WL holds one level per reach and a reach is one flat `WaterBody` (card 2). The spike's
  sloped rapids may return in phase 3. Measured (2026-11-22, before -> after): the corpus main river
  12 reaches of about 5 m with 0.25 m riffles -> 6 of about 10 m with 0.5 m; its tributary 4.8 m
  fall plus four 0.55 m riffles -> a 5.65 m fall and one 1.4 m fall; valley seed 7's river 6
  reaches of 15 m -> 3 of 29 to 43 m; the hilltop crown fall unchanged (5.3 m, then one 0.5 m
  riffle); a straight 40 m flank river off the hilltop crown 11 reaches (a fall and a ladder of
  0.45 to 0.7 m riffles) -> one 5.8 m fall and a calm 36 m reach. On uniform slopes 0.02 / 0.05 /
  0.1 / 0.15 / 0.3 over 52 m: 1 / 4 / 6 / 4 / 5 steps (`test_terra_reaches`).
- **Cost** (headless, indicative, 320 ft corpus, 60 held raise dabs, 2026-11-22): `apply_held`'s
  derive 2.0 ms median (p95 2.2) dry, 2.2 (p95 5.2) across the main river; the bridge's diff
  0.01 ms and row writes 0.01 to 0.09 ms median (0.6 ms p95 over the river). Today's chunk work
  after it is the consumers' cost, not the core's.

## The editor

Card terraform-p2-editor (phase 2 card 3, 2026-11-22; plan `phase2_plan.md` section 4).
`TerraEditor` (`scenes/states/authoring/terra_editor.gd`, `AuthoringEditor.terra`, part of the editor
like `HeightEditor`) is the spine from a gesture to the primitives. `active()` is true when the switch is
on, the document has a terrain section and the map has its `TerraSession`; `create` connects to the
session's `settled` and sets the bridge's editor (`TerraBridge.set_editor`), so the bridge's written
rects go to the editor's height queue.

- **One entry per gesture.** `begin_gesture()`, `edit(change, held)` per change (applied at once through
  `TerraSession.apply`, or `TerraBridge.held` for a held frame; its inverse built first from the document
  as it stood), `end_gesture(label, ground, land)`; a caller that applied its own edits calls
  `record_gesture(label, edits, inverse, ground)`. The history entry is `{"label", "undo":
  undo_gesture.bind(g), "redo": redo_gesture.bind(g), "bytes"}`; the gesture `g` holds `edits`,
  `inverse`, `ground` (the `HeightEditor` ground record), `doc_digest` and `digest_before`
  (`TerraDoc.digest`), and `digests_after` / `digests_before` (`TerraEditor.CHECKED`: H2, WL, CT, falls,
  walls, water), filled when each side lands. `compact()` folds an add's appends into it, and an append
  or replace of a primitive the gesture already added or restored records no inverse, so a held stroke
  is one edit each way.
- **The inverse builder** (`TerraEditor.inverse_of(terra, change)`, pure): add gives a splice that
  removes the new id and puts `next_id` back; append and replace a replace with the floats before;
  remove a splice inserting the primitive back at its position with its id; mute and unmute the other;
  move a move back; a splice a splice removing what it inserted (and `next_id` back), then one splice per
  removed primitive at its old position, ascending. So undo returns `TerraDoc.digest()` and every derived
  digest to their values before (`test_terra_editor`).
- **The splice** (`TerraSession.apply({"op": "splice", "remove", "insert", "at", "next_id"})`,
  `TerraSession.splice`, `TerraDoc.splice`): all or nothing, ids, order, flags and `next_id` restored
  exactly; the derive re-sets the primitives from the first inserted one's position on (it has no
  insert). For undo now, folding (card 4) and the wall sync (card 9).
- **One landing.** Do (with `land`), undo, redo and a peer's op share it: the edits go through the
  session (async); on `settled`, after the bridge wrote the heights (it connects first), the written
  document rect is `doc_heights_diff` of the settled derive against the heights before the apply, and
  `HeightEditor.apply_ground(rect, before, ground, redo, spread)` lands the ground record (props,
  followers, kept rocks, settle, water refresh, regeneration). An apply that arrives while a landing is
  pending waits and runs on that landing: a redo pressed before its undo lands queues, never
  interleaves (`test_a_redo_before_the_undo_lands_queues`: the undo lands on the digests before, then
  the redo). `has_work()` joins `AuthoringEditor.has_height_work`, so the live-edit sender and a peer's
  queue wait for landings; `finish_work()` (in `finish_height_work`) polls the session until they land.
- **Never blocking** (card terraform-p2-noblock). No press, undo or redo waits for a derive while
  `active()`: `TerraEditor.prepare_gesture()` replaces `finish_height_work` in `WallEditor._change` and
  the Paint press (it still finishes the height work when the core is not active), and
  `AuthoringController`'s and `PlayEvents`' undo and redo skip `WaterEditor.finish_work` (the water lands
  with its gesture). A gesture opened while landings are pending first applies the queued undos and
  redos to the document (it is built on the document as it stands; `sync_walls` opens it before
  reading the walls), and every landing's edits go behind `TerraSession.cut()`: the session holds them
  back until it has settled on the edits before, emitting `settled` once per stage with the derive
  answering exactly for that stage (`stage()`, `settled_stage()`; splice, unmute and move read the
  primitives they re-set when applied, so a held-back tell never sees later edits). The landings
  queue (`_landings`), each lands on its own stage in order, its heights before being the ones the
  landing ahead of it left, and each side's document digest is taken when its edits are applied.
  Only `finish_work()` waits (`op_of`, a save, a peer's catch-up), counted in `waits`
  (`test_terra_noblock`: two walls in one frame, and a wall, its undo and a second wall with the first
  pad deriving, never wait and land on the digests a serial run lands on; final digests equal a fresh
  build and a peer's, `MapFingerprint` too). A landing due while the water's worker still computes
  (`WaterEditor.is_computing`: the wet dressing refresh the landing before started, 400+ ms at 200 ft,
  which `HeightEditor.apply_ground` would wait for) waits for it instead: the session holds its next
  stage (`TerraSession.pause` / `resume`, an edit meanwhile starts a held stage) and `step()` lands it on
  the frame the worker is done. Bench (corpus 200 ft, windowed, two stone walls in consecutive frames, 3
  runs): the second wall's frame 483 ms before, 30.6 ms after (max 31.1), 0 frames over 33; the first
  wall's frame unchanged (16.1 / 15.5 ms medians). Still waiting: the bridge's `land_external` finishes
  a water job before starting one, and the other editors' presses (structures, crossings, settlements,
  fire, table move) still call `finish_height_work`.
- **Peers.** `LiveEditCodec` kind `"terra"`: `args = [the side's edits (its edits, or for an undo its
  inverse), the ground record's side, TerraDoc.digest after it, its CHECKED digests]`, from
  `op_of` on `TerraEditor.redo_gesture` / `undo_gesture`. The host's digests ride in the op itself:
  `op_of` finishes the height work, the landings included, so the side has settled. A peer applies it
  through `TerraEditor.apply_edits` (spread), and once landed compares (`last_check`; a mismatch warns
  once, naming the arrays; resync is phase 6). `"terra_check"` (`LiveEditCodec.terra_check_op`,
  `TerraEditor.apply_check`) carries the digests alone. `LiveEditReader` checks every edit: the session's
  ops only, ids in 1..`MAX_ID`, finite floats within the caps, each added or inserted primitive against
  `TerraKinds.problem` (loaded by path: the reader is on the start-up graph), no reserved flag, digests
  as 64 hex digits and a short name table; a map without a terrain section refuses both kinds.
- **The refusal.** With the switch off on a map with a terrain section (or the core on but not built),
  `refusal()` refuses Sculpt, River, Pond, Paint and Wall with a toast naming the switch
  (`SWITCH_OFF`), and nothing changes (`test_switch_off_refuses_every_ground_tool_and_changes_nothing`:
  the fingerprint before and after are equal, no entry, no derive). A map without a section takes
  today's routes untouched.

### Tools

`AuthoringEditor`'s stroke entry points, and the water and wall hooks on `TerraEditor` itself (the
brushes call them; `AuthoringEditor` is at its public-method cap), route each tool to a `TerraEditor`
op while `active()` and to today's editor otherwise; each op refuses with `NOT_YET` ("... is not on
terrain primitives yet") until its card lands, so those cards edit only their op in `terra_editor.gd`
(and this row), never `authoring_editor.gd`.

| Tool | Route | `TerraEditor` op | Card | State |
|---|---|---|---|---|
| Sculpt | `AuthoringEditor.begin_height_stroke`, `height_dab`, `stroke_dab`, `flush`, `end_stroke`, `cancel_stroke` | `begin_sculpt`, `dab`, `flush`, `end_stroke`, `cancel_stroke`, forwarded to `TerraSculpt` (`scenes/states/authoring/terra/terra_sculpt.gd`; see "Sculpt on primitives" below) while no water stroke is open | terraform-p2-sculpt (6) | on primitives |
| River | `TerraEditor.carve_river` (WaterBrush.carve, after `through_rises`) | `river`: `TerraWaterTools.add_river` (`scenes/states/authoring/terra/terra_water_tools.gd`): the line in map XZ, `WaterCourseFit.condition` (within half a half-width), one `add` of [2 x the widest half-width, `WaterBody.DEPTH_M` of the tile, points]; points past the edge kept (the bridge's `beyond`). The caps first: the reaches it can make (`reach_bound`: one per 2 m of length or per 0.25 m of drop, plus two) must fit `MAX_RIVERS` beside today's, else `FULL`. The derive flips, levels, joins and carves; the bridge's `land_external` dresses (wet rocks, crossings, regrowth) and its record becomes the gesture's water side (`g.water`, `TerraEditor.ground_of`: its props rows come back on undo). `test_terra_water_tools`: the flank river joins the main one at its level, every step of 0.75 m or more is a fall, uphill flipped, a line over a rise wet along its whole line, `beyond` past the edge, undo and redo exact, a peer matches digests and `MapFingerprint`, two releases in one frame never wait | terraform-p2-water (7) | on primitives |
| Pond, Water erase | `TerraEditor.paint_pond_begin`, `erase_water_begin` (WaterBrush.begin), then the stroke routes (`is_stroking`, `dab`, `end_stroke`, `cancel_stroke` forward to `water_tools`) | `begin_pond`, `begin_water_erase`: dabs are capsules in a scratch list, traced on release (`PondOutline.trace`, `utils/terraform/pond_outline.gd`: a capsule-distance field on a 0.25 m grid, marching squares, the largest loop, Douglas-Peucker 5 cm) to one `add`, or with the press inside a pond one `replace` of its outline merged with the stroke (`Geometry2D.merge_polygons`); a new pond is clipped out of others. Erase: rivers whose derived line the stroke touches go whole with every river whose `recv_river` chain ends in one (their carve goes too, deliberately); ponds it covers are clipped (`replace`) or removed under 1 m2, and their level re-solves to the new rim (it may rise by the rim's change: measured +1 mm on an extension; the core keeps no old level) | terraform-p2-water (7) | on primitives |
| Paint | `AuthoringEditor.begin_surface_stroke`, `surface_refusal`, the stroke routes | `begin_paint`, `paint_refusal` | terraform-p2-paint-path (8) | refuses |
| Wall | `TerraEditor.begin_wall_edit` (WallBrush.press), then `WallEditor._change` (place, extend, reroll, remove, street split) calls `TerraEditor.sync_walls` | `begin_wall`, `sync_walls`: `TerraWallSync.sync(doc)` (`utils/terraform/terra_wall_sync.gd`, pure) is one `splice` making the wall primitives (kind 7) mirror `doc.walls` in list order, stone and fence only (thickness `WallGeometry.thickness_m`: 0.45 and 0.1 m; a closed wall repeats its first point; a street row adds none; a wall primitive with no wall behind it is dropped); it keeps the matching run at the front and rebuilds the rest under new ids in place. The list change and the sync's gesture are one `AuthoringHistory` group (joining a street split's open group); its ground record `{"walls": {"area"}}` refreshes the walls on the landed pad on do, undo and redo. Undo, redo and a live walls op run `apply_list` alone: the group's terra part carries the pads. `test_terra_walls`: level across the footprint 0.0000 m (bar 2 cm; the slope there 0.33 m), the river opens 19 of 45 line points, undo returns every digest, a peer matches | terraform-p2-walls (9) | on primitives |

### Sculpt on primitives

Card terraform-p2-sculpt (phase 2 card 6, 2026-11-22). `TerraSculpt` (`TerraEditor.sculpt`) runs every
Sculpt tile while `active()`; one stroke is one `TerraEditor` gesture and one history entry.

- **Tiles.** Raise / Lower (Ctrl) / Smooth (Shift, any tile): one stroke primitive (kind 3, modes 0, 1,
  2), each frame's capsule as point dabs (`StrokeKind.capsule_dabs`). Flatten, Tier, Tier cut (Ctrl):
  one level primitive (kind 17), a capsule dab per frame toward the press's target (`LevelKind`). With
  the core on (`SculptTool.tiles()`: two rows of three) the pane adds **Terrace** (kind 16;
  `utils/terraform/kinds/terrace/terrace_tool.gd`, the tool half of the kind's folder: treads half a map
  tier high, dabs every radius / 4 along the path travelled, since a terrace dab pulls fully at its
  centre) and **Soften** (`TerraSoften`, the erase: each frame the strokes, levels and terraces under
  the ring keep `exp(-3 x seconds x falloff)` of their dabs' strength, a hill wholly inside the ring of
  its height; a dab or hill under 5 % of its strength at the press goes, a tier or terrace dab, which
  has no strength, once half softened; an emptied primitive is removed; one replace or remove per
  touched primitive, `TerraEditor.compact` merging a primitive's replaces). Soften is local: a
  primitive whose footprint reaches past the ring (a landform hill, ridge, river, pond, path, wall, a
  folded raster) is never scaled or removed; where the ring lies over one (`TerraSoften.smooths`) the
  gesture lays a smooth stroke (kind 3, mode 2) along the ring instead (round 3: one drag had removed a
  whole hill and moved water far outside the brush; `test_soften_changes_only_the_ground_under_its_ring`:
  no such primitive changes, the ground moves only within the ring plus 1.5 m). Terrace and Soften refuse on a map without a
  terrain section (`SculptTool.TERRA_ONLY`). Cursor tints: Terrace between Raise and Smooth (golden green), Soften between Flatten and Lower (mauve).
- **Frames.** The first frame with dabs `add`s the primitive, each later one `append`s, through
  `TerraEditor.edit(change, true)` (`TerraBridge.held`: derived at once when the session is free)
  inside `HeightEditor`'s external stroke, whose record (props before and after, kept rocks, crossings,
  walls and structures re-anchored) is the gesture's ground side; `end_gesture(label, record, false)`.
  A cancel takes the edits back as an undo (`TerraEditor.abandon_gesture`, `apply_edits`), recording
  nothing.
- **Never blocking.** `HeightEditor.begin_external(false)` does the edit before's main-thread leftovers
  and refuses, starting nothing, while the water's or the rock keeper's worker still runs (their
  landing reads the snap's start); the stroke keeps its dabs and puts them in on the first frame it can
  (the ground catches up). Only a release before that waits (`TerraSculpt.waits`).
- **Folding.** At a stroke's end, when the session is idle, `TerraSculpt.fold_run` takes the oldest
  maximal run of consecutive compose primitives (other stages skipped) that are unmuted strokes, levels
  or terraces, older than the newest `KEEP_LIVE` 8 of them; past `CONSOLIDATE_DABS` 4096 dabs
  `consolidate` folds it and `fold_edit`'s splice goes into the stroke's gesture, so its undo restores
  the run. A new map's landform levels fold as part of such a run.

## Versions and the library

`TerraDerive.version()` is `TerraCore.NATIVE_VERSION`, now `terra 7 reaches` (the slope-scaled
flat reaches; before it `terra 6 sculpt kinds`: the level and sculpt kinds, `consolidate`, the smooth
stage's exposure model), and the golden fixture's `version` follows it. The scatter library's string carries `terra`
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
| `test_terra_cache.gd` | the derived record: with a matching key a fresh derive gives the recorded digests through the map document (the record reads back bit for bit, under 512 bytes); the snapshot's copy; a stale record is not written; each key change (grid, core version, a mute, a moved float) misses quietly while an add and its undo keep the key; one H2 sample set outside the chain gives `mismatch` naming only H2 with one warning; every truncation, a trailing byte, the entry cap, bad magic, a newer version, too many digests, names out of order or malformed are refused while the terrain still loads; a map without terrain is unaffected |
| `test_terra_session.gd` | the session through `MapSourceLoader`: switch off makes no session and no `TerraDerive` and the fingerprint equals the stripped map's (but `terra`); switch on without a section makes none; the setting's default; switch on, the digests equal a fresh `derive_full`, the save writes the record, and a reload through `load_async` matches it with equal digests; every edit op (one queued during the attach, some back to back) lands equal to a fresh derive; closing mid-attach and mid-`derive_async` parks and later lets go; a refused section is kept and saved back untouched in format 6 |
| `test_terra_bridge.gd` | `doc_rect`; `doc_heights` is H2 at the even samples and `doc_heights_diff` the tight rect (bits, clipping, another grid refused); a load with the switch on swaps in the derived ground and the collision equals `height_at` at 200 random samples; a new map with the switch on has a one-plane section, derived heights and a matching record, with it off none |
| `test_terra_bridge_law.gd` | the bridge law over a 40-dab held raise through `TerraBridge.held` across the corpus rivers, every frame derived at once, then an async release; the collision equals the bridged heights, which equal a build; the water half (bodies with their ids and the pond mask equal `water_of`) after the load, the press and the release, none written on a held frame; a pond added and removed lands through `WaterEditor.land_external` (the record filled, the dressing and AuthoredWater follow) |
| `test_terra_water_bridge.gd` | runs and depth classes; the corpus as one body per run of equal levels and one per pond (ids from 1, valid for the writer); the wet set of `WaterGeometry.levels` against WL > H2 at even samples (only shoreline samples differ: 80 of 4677 at 200 ft); `WaterFalls.falls` against the fall records (exact); a river past the edge keeps its drawn course; the river cap refused, not truncated; ids and mask equal after a reload and a late join (each re-derived); AuthoredWater, the flow and the Painted water field build |
| `test_terra_editor.gd` | a scripted add / append / remove / splice gesture is one entry whose undo and redo return `TerraDoc.digest()` and every derived digest (and the bridged heights) to their before and after values; a redo pressed before the undo lands queues and lands after it; the inverse builder and the splice restore the encoded section exactly, and a refused splice changes nothing; switch off on a map with a section: every ground tool refuses naming the switch and the fingerprint is unchanged; without a section today's routes; switch on, each route refuses until its card |
| `test_terra_live_edits.gd` | host and peer through bytes: after the gesture, a second gesture, both undos and a redo, equal documents, digests and `MapFingerprint`, and the peer's own check agrees; a `terra_check` op agrees, and a wrong digest is reported naming H2; malformed `terra` ops (unknown op, NaN, a short or unknown kind, a reserved flag, bad ids, next_id, digests, arity, direction) and a map without a section are refused |
| `test_terra_noblock.gd` | two walls placed in one frame, and a wall, its undo and a second wall with the first pad deriving: no call waits (`TerraEditor.waits` 0, the derive still in flight on return, each call under 50 ms), each landing lands in order on the digests a serial run lands on, the final digests and heights equal a fresh build, and a peer following the entries through bytes matches every check, the digests and `MapFingerprint` |
| `test_terra_stage_table.gd` | the table's order (each read an input or an earlier write, one writer per array); halo honesty: one H2 sample (then one FM sample) of a built map set outside the chain, every downstream stage re-run over the whole map, and each array changes only within the reach the table declares from it (the halos summed along the way), with the incremental derive giving the same bytes. A halo one sample short fails it (checked 2026-11-22 with the look row at 13) |

`tests/unit/terra_corpus.gd` (`TerraCorpus`) is the spike's test scene placed on a map document's
frame; `tests/unit/terra_rig.gd` (`TerraRig`) loads it through `MapSourceLoader` with an editor over it.
Phase 2's cards also run the gate once with the switch on: `godot --headless --path <checkout> --script
res://tools/gut_shards.gd -- -gconfig=tests/.gutconfig_terra_on.json` (its pre-run hook,
`tests/gut_pre_run_terra_on.gd`, sets `tt_sim/terrain/core` in memory, so every test that leaves
`switch_override` null runs with the core on). `.github/native/parity.sh` runs `test_terra_golden` on every platform CI builds, debug and
release, and fails if it is pending or does not report its matched digests. A platform that
disagrees is a bug in `terra_math.h`, never in the fixture. A deliberate change to the derive (a
stage, a constant, the ground rules) regenerates the fixture: the failing test prints the new
cases as JSON.
