# Settlements: dressed streets (villages phase 1, host step B)

Card `settlement`, 2026-10-31. Design: `docs/systems/villages.md`; procgen half: `procgen/docs/props_and_settlements.md`.
A street of the Street tool can be dressed with furnishings (barrels, carts, wells, stalls, lamps ...) of a
character (a procgen settlement kit). The furnishings are a DERIVED layer: nothing but a small record is saved
or sent, and every peer derives the same list.

## The record

`Settlement` (`resources/settlement.gd`), at most `MapDocument.MAX_SETTLEMENTS` (8), ids 1 to 32:

| Field | Meaning |
|-------|---------|
| `kit` | one of `ProcgenSettlement.NAMES` (farming_hamlet, market_town, harbour_town, hill_fort_village) |
| `seed_value` | 0 to 1e9; Re-dress takes `SettlementEditor.next_seed` |
| `wealth` 0..1, `density` 0..1.5 | 0.01 steps; the kit clamps wealth to its own range |
| `source` | the id of the street (a row `Wall`), or 0 after "Split into buildings" |
| `frozen` | up to 2 `ProcgenFrontage.to_dict` records, used when `source` is 0 |
| `removed` | slot ids not drawn (at most 64) |
| `swapped` | slot id to another prop name |
| `pinned` | slot id to a placement `{prop, at, yaw, scale, seed}` drawn as recorded |
| `plazas` | up to 4 discs `{at: map XZ (1 cm), radius: 2..16 m}` (villages2); the first frontage carries them to procgen's `plaza.centre` and `plaza.edge` rules, and the Dress paves them. Left out of the saved entry when empty, so older maps re-save byte for byte |
| `ground` | up to 256 paint strokes the last Dress laid (villages3; `SettlementGroundIO`): `{surface, from, to, radius, seconds}` capsules in paint order, held to a hundredth. Saved as `"ground": {"surfaces": [...], "strokes": [[surface index, ax, az, bx, bz, radius, seconds], ...]}` (at most 4 surfaces), left out when empty; Clear and a re-dress take back exactly these |

One street has at most one settlement. A settlement whose street is gone draws nothing and returns with the
street on undo (it is not deleted with the street: undoing the removal must bring both back).
Slot ids are `<frontage key>:<procgen slot>`, for example `w3l:l2/door_barrel/d0r`; the frontage key is
`w<street id>l` or `r`, the lot `l<index along its side>` (empty plots count, so a lot keeps its name).

Saved as `settlements.json` (`MapSettlementIO`, version 1, 1 MB cap, beside `walls.json`): a map without the
entry loads unchanged, an older build ignores it. A hostile entry is skipped with a warning; the writer
refuses a document breaking the rules (`settlement_problem`). No format bump.

## Live edit

Kind `"settlements"` in `LiveEditCodec.KINDS` (whole list, JSON forms, `SettlementEditor.apply_list`),
read through `LiveEditReader._settlement_list` (same validation as the map reader). Undo and redo ride the
same method. A late joiner gets the settlements with the map document (they are part of it), and
`MapFingerprint` has a `settlements` key (record hashes, then one line per baked cell).

## Pure code

- `SettlementFrontage` (`utils/settlement_frontage.gd`): the `ProcgenFrontage` of each street side from
  `WallGeometry.row_lots`. The facade line is the centre line pushed out by the setback (mitred corners); a
  lot is the arc range of its front edge, its door the middle of the front (1.1 m), the strip to the kerb
  `0.75 x setback` (1 to 4 m); neighbouring `Structure`s within 14 m become obstacle discs.
- `SettlementPlan` (`utils/settlement_plan.gd`): `ProcgenSettlement.place` per side, then the overrides.
  Golden digests: `tests/fixtures/settlement_digests.txt` (11 species, frontage digest, plan digest, count).
- `SettlementBake` (`utils/settlement_bake.gd`): the placements of a cell merged into one surface per
  material, vertex colours and the cloth wind weights (UV2) kept.

## The layer

`AuthoredSettlements` (`scenes/terrain/authored_settlements.gd`, node `AuthoredSettlements` under the map
root, created only when a settlement exists; `MapSourceLoader.add_authored_settlements`). Placements are stood on
`WaterGeometry.grounds_at` (a placement on water or on ground steeper than 0.8 is skipped, 3 cm sink), grouped
into 24 m cells `S<id>_<cx>_<cz>`, one `MeshInstance3D` per cell, one surface per (role, kind) material
(`StructureMaterials.make`, role `prop`). No collision (class none). The cell key is the md5 of its placement
lines (slot, variant, position, yaw, scale, ground y in mm): a refresh rebuilds only cells whose key moved, a
plan is cached per record and lot fingerprint. Prop variants (4 per prop, `StructureGeometry.build_one` over
`ProcgenProps.footprint(default_size_m)`) are built once and kept in a static cache (`clear_variants()` for
tests); `_process` builds variants and then cells within 3 ms a frame, `flush()` does all at once.
Refresh hooks: `WallEditor.apply_list` and `StructureEditor.apply_list` (so a sculpt, a street edit or a moved
house re-derives), `SettlementEditor.apply_list`.
A refresh that finds a plan's `sig` and the ground print it was stood on unchanged keeps the plan's stood rows (and
its skipped count) instead of standing them again: the print is `StructureGeometry.ground_fingerprint(doc)`, taken once
per refresh, and a plan with anything missing is always re-stood (hitches round 1: a Clear's refresh 16.9 to 3.1 ms;
`tests/unit/test_build_hitches.gd`).

## Editor and bar

`SettlementEditor` (`AuthoringEditor.settlements`): `dress(street, kit, wealth, density)` (a new settlement, or
the next seed and the kit for a dressed street), `redress`, `set_kit`, `set_feel`, `clear`, `freeze_street`;
each is one history entry. The picked street's bar (`WallToolPane.selection_box`) holds `SettlementSection`
(four ToggleChip characters, "Shabby to wealthy" and "Sparse to busy" sliders, "Dress this street" which
reads "Re-dress" once dressed, "Clear"); `SettlementBarLink` joins it to the editor and re-shows the street
after any edit, undo or redo.

A village's plazas and character are also edited in the Village tool (`VillageTool`, `VillageBrush`,
`VillageToolPane`): the pane's character tiles call `set_kit`, its size slider `resize_plaza`, Remove
`remove_plaza`; see `docs/systems/villages.md` section 10.

## Split into buildings

`WallEditor.split_street` freezes the frontage (`from_lots` without neighbour discs) into the settlement in
the same history group: `source` becomes 0 and the furnishings stay where they were. Phase 1 does NOT follow
later house moves after a split (the design's "group of structures along the former street" is phase 3).
Undo restores the street and the link.

## Look pass (topic settlement_look, 2026-10-31)

- **Street clearance.** `WallGeometry.street_corridor` gives every row wall one plank-like clearing per
  segment of its centre line, as wide as the facade lines are apart plus `STREET_CLEAR_EXTRA_M` (2 m) each side,
  so a trunk stands behind the houses and a crown does not hang over the street. It is the scatter's existing
  mechanism (`WallGeometry.clearance_crossings`, read by `ScatterGround.sampler` and the native scatter), with no
  second one, and it applies to every street whether dressed or not. The yards keep their own clearings
  (the lots' plots). Deterministic and regenerated with the scatter, so no saved map changes. Measured in
  forest renders: 0 of about 5,700 scatter rows inside the corridor rectangle. Phase 2's painted road (role
  `built`) stacks with it: the corridor is a floor under the paint, and a road narrower than the corridor
  leaves bare ground beside it, not plants.
- **Scale.** `SettlementBake.PROP_VISUAL_SCALE` 1.35 (`DOOR_VISUAL_SCALE` 1.12 for slots with `/d` or `/e`, the
  plan's door and entrance slots, so the door path keeps its width; the product is clamped to
  `MAX_VISUAL_SCALE` 1.7 and never below the placement's own scale). The plan and its digests keep true metres;
  only the drawn mesh grows, about its origin. The plan keeps props 0.7 of a radius plus 0.2 m apart, so at 1.35
  neighbours may touch at most.
- **Colour.** The prop role (`StructureMaterials.prop`): exposure 0.86, saturation 1.6, lit gain
  (1.34, 1.22, 1.06); the prop cloth leans and flutters 1.8 times a banner (`PROP_CLOTH_WIND`). Building
  materials are untouched.
- **Slopes.** The ground is read at the centre and 0.8 of the drawn radius (0.3 to 1.6 m) to each side
  (`AuthoredSettlements.footprint_reach`); a prop stands at the LOWEST of the five heights minus 3 cm and leans
  toward the ground's normal by at most 12 degrees (`SettlementBake.tilt_of`: identity on flat ground, never a
  flip). The slope limit (0.8 rise over run) uses the same reach. The tilt is in the cell key.
- **Cells.** `CELL_M` 48 and one surface per material look: see `docs/PERFORMANCE.md` "Settlement furnishings".

## Looks round two (topic looks2, 2026-10-31)

- **Hero props.** The four kits draw a few larger props per street (procgen `docs/props_and_settlements.md`
  section 10): a pick entry with a `scale` of 1.25 to 1.7 (wells 1.4 to 1.7, hand carts 1.35 to 1.5,
  haystacks and crate stacks 1.4 to 1.6, stalls 1.25 to 1.5), about one to one and a half per 60 m of
  street side (procgen's measurement), two to three at a plaza. The global 1.35 (`PROP_VISUAL_SCALE`) is unchanged; the drawn scale is
  the placement's scale times it, so a hero is drawn at up to 2.3, and `MAX_VISUAL_SCALE` is 2.4 (was
  1.7, which would have flattened every hero to the same size). Heroes ask the strip for less
  (`fit` 1.0): tt-sim's strip is 0.75 of the setback, 2.25 m at the Street tool's default, which an
  ordinary-fit prop of a hero's size would never find room in. The plan and its pins use true metres as
  before; a hero's clearance disc is `radius_m` times its scale. Measured on the two-street render job
  `looks2_street` (hamlet and market town, default setback): 31 and 46 placements before, 33 and 48
  after, 4 heroes (cart 1.38, haystack 1.57, well 1.63, cart 1.40), triangles 5836 and 14040 before,
  6420 and 15180 after (the hamlet 4 surfaces before, 5 after; both streets 13 before, 14 after: a prop
  kind new to a street, here a well, adds its surfaces), so one more draw per street at most.
  The home camera still hides most of a street's props behind the near house row; a hero at the kerb of
  the far side or in a plaza is what it sees.
- **Lantern glow.** A prop's `glass` part (the lamp posts' and wayside shrines' lanterns) is drawn by
  `StructureMaterials.lantern`, `shaders/structure_lantern.gdshader`: unshaded, the painted warm tone
  pulled toward amber and pushed to 1.35 so the environment glow takes it, a little deeper at the
  glass's edges. Steady. tt-sim has no day and night cycle, so there is nothing to brighten at dusk;
  when a time-of-day control exists, `energy` is the one number to drive. Wells' and troughs' water is
  unchanged (the WATER role). Test: `tests/unit/test_prop_look.gd`.

## Ground (topic villages2, 2026-10-31; villages phase 2, first slice)

A Dress gives the street a ground: a road along its centre line, a path from every door, and paving in
plazas. They are ordinary painted surfaces (the Paint tool's `SurfaceStroke` on the map's surface weights),
laid at Dress time, so they clear plants under them (the kits name `built`-role surfaces), tint their
surroundings with the trampled broad edge, show in the Paint tool, and reach every peer as the existing
`surface` live edit. There is no new live-edit kind.

- **The kit names the surfaces.** Each kit JSON carries `"ground": {"road", "door_path", "plaza"}`
  (procgen `ProcgenSettlement.ground_of`; at most 3 different surfaces, so at most 3 of the map's 64 painted
  slots, and two roles may share one). Farming hamlet: dirt_road_packed road and door paths (one slot),
  flagstone_sandstone plaza. Market town: flagstone_sandstone road and door paths, cobblestone plaza.
  Harbour town: dirt_road_caliche road, planks door paths, flagstone_sandstone plaza. Hill fort village:
  dirt_road_caliche road and door paths, flagstone_sandstone plaza. Chosen by eye: the dark cobblestone and
  stone_tiles sets read as a grey band as a road at game light, the warm sandstone and caliche read lit and
  painterly; cobblestone stays as a plaza accent. A surface missing from the palette is skipped (`unknown`).
- **The plan** (`SettlementGround`, `utils/settlement_ground.gd`, pure, tests in
  `tests/unit/test_settlement_ground.gd`): capsule strokes `{role, surface, from, to, radius, seconds}` in map
  metres (each held to a hundredth, so the record and the paint agree). Road: the centre line resampled every
  1.5 m (corners kept), half width `0.77 x setback` clamped to 1.2 to 3.2 m (2.31 m at the default 3 m; villages3
  widened it a third from 0.58 and 0.9 to 2.4 m, 1.74 m, because at home zoom the road hid behind the near
  house rows), brush radius 1.4 times that for the soft edge, nearly straight
  runs merged into one capsule (at most 30 m, under 4 degrees of drift), which cuts the dab cost about five
  times. A sample is refused (and the road stops there) when the centre or an edge is wet
  (`WaterGeometry.is_wet_at`), the ground rises more than 0.5 along or 0.7 across, or the road would touch a
  `Structure` footprint. Door paths: two strokes from each lot's door on the facade line to just inside the
  road's edge (half the half width), bent sideways up to 25 cm by a hash of street, side and lot (never the
  seed, so a re-dress moves no path), radius 0.75 m (1.05 m with the soft edge), refused when wet, steeper
  than 0.6, blocked, or the road stretch they join was refused. Plazas: one disc stroke at 1.12 times the
  radius, refused when the centre or a quarter of the rim is wet or the disc spans more than 0.45 slope.
  Paint order: road, plaza, door paths (the newest paint wins a sample). Counts of every refusal are in
  `plan["refused"]`.
- **The slot budget** (`SettlementGround.affordable`): roles are served road, door path, plaza; a surface the
  map already paints costs no slot, each new one takes one of the 64 (`MapDocument.PAINT_SURFACE_LIMIT`); a
  role with no slot left is skipped and counted (`refused.slots`), and the street is still dressed.
- **One history entry.** `SettlementEditor` opens a history group, `SettlementPaint.lay` writes each run of
  strokes on one surface as a `SurfaceStroke` (one `surface` entry each, applied through
  `AuthoringEditor.apply_surface_diff`), then the record change is recorded, and the group ends: one Ctrl+Z
  takes back the props, the record, the paint and the slots. A peer receives `LiveEditCodec.ops_of(entry)`:
  the surface ops, then the `settlements` op (`test_a_peer_receives_the_paint_as_surface_ops_...` applies
  them to a second document and compares the weights byte for byte, and an undo the same way).
- **When it paints.** `dress` (a new settlement, or a re-dress), `redress`, `set_kit` and `pave(id)` take back
  the strokes the record lists and then lay the new plan, in the same history group, so a re-dress after the
  street was moved or bent lays the road where the street is now; `add_plaza(id, at, radius)` adds just that
  disc to the list (one entry; at most 4; `REFUSED_PLAZA` for a disc the record refuses). `set_feel` paints
  nothing. `remove_plaza` keeps the paving (it stays in the list and goes with the next re-dress or Clear).
  `last_ground` holds the last plan's counts and the plan, paint, take-back and entry numbers; `lays_ground`
  false is the A/B switch (it neither paints nor takes back). If the list would pass 256 strokes the tail (door
  paths) is not painted.
- **Taking the paint back** (villages3, `SettlementUnpaint`, `utils/settlement_unpaint.gd`; tests
  `tests/unit/test_settlement_unpaint.gd`). Paint blends (the newest wins a sample and scales the rest down), so
  a stroke cannot be subtracted from the map alone. The record's list is replayed on an empty scratch grid
  through the same `SurfaceStroke` code, which gives what the dressing left on its own, per sample and per
  surface; the map loses that much weight on the surfaces the dressing laid (never below 0), and where the
  dressing's paint is still whole on a full sample the author's paint of other surfaces, which it squeezed, is
  scaled back up by the room it gave. Where nothing of the dressing remains (the author painted over it, or
  erased it) the sample is left as it is. The result is an ordinary `SurfaceStroke` diff recorded by
  `SettlementPaint.unlay` as one `surface` entry in the caller's group, so undo and a peer's `surface` op need
  nothing new. A clean Dress then Clear (or re-dress) restores the weights and the slot list byte for byte
  (tests); ground painted by hand is untouched away from the dressing and comes back under it to within a few
  of 255. Limits: two dressed streets that cross share one surface there, so taking one back thins the other
  a little at the crossing (re-dress it); a sliver of author paint that a stroke squeezed to almost nothing
  comes back as that sliver (the weight it had is not recorded); a settlement dressed before villages3 has no
  list, so its first re-dress lays the new ground over the old and only the new strokes are remembered.
- **Plazas are made in the Village tool** (topic villagetool, 2026-10-31; `docs/systems/villages.md` section
  10): `add_plaza`, `resize_plaza` and `remove_plaza` are the editor calls under its gestures (the probe action
  `plaza` still calls the first). Discs only (the design allowed polygons); a hand-placed building inside a
  plaza is not refused.
- **Resize and remove take the plaza's paving back** (villagetool). A plaza's paving is the one disc stroke
  `from == to == at`, radius 1.12 times the plaza's, that `add_plaza` appended to `Settlement.ground`
  (`VillagePlazas.stroke_index` finds it). `resize_plaza(id, index, radius)` takes that stroke back
  (`SettlementPaint.unlay` of the one stroke, `SettlementUnpaint` as for Clear), lays the new disc and forgets
  the old stroke in the record, all in one history group: one Ctrl+Z, one `surface` op plus one `settlements`
  op per peer entry. `remove_plaza` takes the stroke back with the plaza (it used to leave the paving until the
  next re-dress). A plaza with no listed stroke (paving off, or refused for wet or steep ground) changes the
  record only. Paint laid over the disc afterwards by the door paths or by hand is handled as Clear handles it
  (the author's other paint gets its room back; a sliver squeezed to almost nothing comes back as the sliver).
- **The building's own path gives way.** `StructureDressing` leaves out its alpha path ribbon (stones and
  steps stay) where the map's paint already covers the ground 0.8 m and 1.8 m out of the door
  (`StructureDoorPaint`, cover of 128 of 255 or more, any surface); the answer is part of the structure's
  key (`ground_samples`). A street's lots are not Structures, so this is for the buildings of a split street
  (whose door paths stay painted) and for a path the author painted. A paint stroke alone does not rebuild a
  yard: it follows at the next structure rebuild (a split, any structure edit).
- **Measured** (2026-10-31, indicative, shared GPU): `jobs/villages2_perf.json`, a 250 ft forest map, three
  52 m two-sided market streets, in-run A/B twice: a street's 22 strokes (2 road capsules and 20 door-path
  strokes), 1 painted slot (2 with a plaza), cost 36 to 60 ms to dress bare and 88 to 131 ms with the ground
  (plan 3 to 13 ms, paint 30 to 70 ms of which the ground update and scatter request are 14 to 53 ms, the
  first of a run the dearest), a one-off click hitch; the worst CPU frame of the three dresses stayed 124 to
  148 ms either way, and the settled GPU render time was 2.60 and 2.82 ms bare against 2.86 and 2.89 ms with
  paint (a rise inside the 0.2 ms drift of the run). `docs/PERFORMANCE.md` "Settlement ground".
- **Measured, villages3** (indicative): taking a street's 23 strokes back (Clear, re-dress, change of character) costs
  113 to 119 ms on the same 52 m street, so a re-dress is about 200 ms once (take-back plus lay) and a Clear about
  115 ms; no frame cost afterwards.
- **Look, villages3** (full-size captures `render_jobs/villages3_street`, `villages3_before`, `villages3_clear`
  under `user://`): a road a third wider reads almost the same at home zoom as before, because on a two-sided
  street the camera still sees the road only through gaps between the near houses; it shows at street ends,
  yard gaps and the plaza (not re-checked on a one-sided street, `jobs/villages2_lane.json`). Clear removes the market's road, door paths and plaza paving and leaves the hamlet's; a fresh Dress or a
  re-dress lays the same ground byte for byte.

## Not done

The Dress row on the Buildings bar, the rest of the Village tool (plaza move and polygons, garden paint, prop
select, move, swap, pin; the plaza gestures and the character tiles are built), plaza polygons, a yard surface, bridges, boundary walls and fields, GM Events pane wiring,
pin/remove/swap gestures (the record and plan support them), collision `stand`/`solid`, the settlement
following later house moves after a split, and a rebuild of a building's yard after a paint stroke alone.
