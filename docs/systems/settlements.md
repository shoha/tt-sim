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

## Editor and bar

`SettlementEditor` (`AuthoringEditor.settlements`): `dress(street, kit, wealth, density)` (a new settlement, or
the next seed and the kit for a dressed street), `redress`, `set_kit`, `set_feel`, `clear`, `freeze_street`;
each is one history entry. The picked street's bar (`WallToolPane.selection_box`) holds `SettlementSection`
(four ToggleChip characters, "Shabby to wealthy" and "Sparse to busy" sliders, "Dress this street" which
reads "Re-dress" once dressed, "Clear"); `SettlementBarLink` joins it to the editor and re-shows the street
after any edit, undo or redo.

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

## Not done (phase 1 scope)

Ground painting (roads, door paths, plazas), the Dress row on the Buildings bar, the Village tool, plazas,
garden paint, GM Events pane wiring, pin/remove/swap gestures (the record and plan support them), collision
`stand`/`solid`.
