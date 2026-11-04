# Villages and streets: composing lived-in settlements (design, built through section 14)

Status (2026-11-03): sections 0 to 6 are the design (card villages_design, topic `villages_design`,
2026-10-30), written before any code, so their "exists" claims cite the code as of tt-sim `4fa55739` and
procgen `4b7c5d2`. The design is built in slices, each documented as built in sections 7 to 14: the record,
layer and Dress bar (7), the plaza ground and widened roads (8 and 9, details in `settlements.md` "Ground"), the
Village tool (10), fields (11), bridges (12), boundary walls and gates (13) and touchable furnishings with the
villages5 piece binding, buttons and canopy cut (14).
Read the as-built sections for what the code does; the design sections record why. The Verification list is at
the end of section 14.
The owner's call (2026-10-30): the next effort goes to world life, villages and streets, performance
hardening and test tooling; new styles are queued behind it (`procgen/docs/style_backlog.md`, whose last
line asks for "bridges, wells, market stalls, shrines and gates as small structures that make streets feel
lived in": this card).

The bar is the suite's guiding principle (`D:/dev/tabletop/AGENTS.md`): beautiful and expressive above any
metric, painterly (Ghibli), no sameness (a place is a shape plus a small palette of features the seed draws
from), and Tiny Glade as the model for authoring: direct gestures, a world that answers with its own detail,
no way to make something ugly.

## 0. Summary of the recommendation

1. Add a small-thing family to procgen: **props** (well, barrel, lamp post, stall...), the same pipeline as
   structures (recipe JSON, digests, mesh check, tags, anchors), under 500 triangles each, shipped in the
   library's existing `structures/` kind with `family: "prop"` (no new library kind in phase 1).
2. Add **settlement kits** (JSON data, like street species): which props, plants and ornaments a village
   character draws, and the placement rules, as a vocabulary of **slots** (street edge, beside a door, yard,
   plaza, water edge, village edge).
3. Props are a **derived layer with a small overrides list**, not structure records: a new `Settlement`
   record (kit, seed, region, plazas, removed and pinned props) is saved and live-edited; the props are
   recomputed by a pure function from it and the document. Section 3c argues it; the main reasons are the
   128-structure cap, history and live-edit cost, and that a village must answer when a house moves.
4. Gestures: a **Village character** picker and a **Dress this street** button on the Street tool, a Dress
   row on the Buildings selection bar, then a Village tool (drag a plaza, paint a garden, re-roll, remove or
   pin a prop).
5. First slice (about 6 to 8 days): 8 props, 2 kits, the `Settlement` record and one **Dress this street**
   button, plus exposing the six street species the Street tool does not offer today.

## 1. Inventory: what exists for composing settlements

### 1.1 Streets (the Wall tool's `row` kind)

There is no separate Street tool. A street is `Wall.Kind.ROW`, one of the Wall tool's tiles
(`scenes/states/authoring/tools/wall_tool.gd:20`, "Build a stone wall, a fence or a street of buildings";
`resources/wall.gd`).

- **Drawing.** Drag along the street's centre line (a chain of drags bends or extends it), at least 6 m.
  Q and E choose the side (left, right, both), Shift+wheel or brackets the setback (1.5 to 10 m, default 3),
  R remixes (`WallBrush`, `walls.md` "Streets"). At most `MAX_WALLS` = 64 walls and streets
  (`resources/map_document.gd:127`).
- **Lots are derived, never stored.** `WallGeometry.row_lots` (`utils/wall_geometry.gd:99`) calls procgen's
  `ProcgenRow.plan` (`procgen/gen/row_gen.gd:88`): walking the centre line it draws, per lot, width, depth,
  gap, height, pitch and ridge from the species, from `rng.sub("side<n>")`, with every draw made for every
  lot so a skipped plot shifts nobody (row_gen.gd:119). `skip_chance` leaves an empty plot; a lot over a bend
  turning more than 0.5 rad is left empty (`MAX_BEND`); the first 0.5 m is clear (`END_MARGIN_M`). A lot
  takes its own stream (`lot<index>_<side>`), so what it is built of shifts no other lot. On a map with water,
  `row_lots` then drops the lots on wet ground or on the street's crossing (`WallGeometry.row_plan` is the
  unfiltered plan; section 12 "Houses stand on dry ground"): a gap, never a reshuffle.
- **Orientation.** Each lot's first side (the front) faces the street, a setback from the line; the gap is at
  least both neighbours' yard margins.
- **Species.** `ProcgenStreetSpecies` (`recipes/species/*.json`, 11 of them) replaces the lot sizes, gaps,
  heights, roofs and yard, and draws walls, roofs, facade styles, trims and chimneys by weight; the six newer
  ones (pueblo, villa, alpine, canal, tudor, minka) draw whole building styles ("bundles") and carry `region`
  tags. **Phase 0 done (batch_c, 2026-10-30):** the Street tool offers all 11. `Wall.ROW_PRESETS` is
  `ProcgenRow.PRESET_MINKA + 1` (11), the pane's tiles, the readout names and the tooltips come from
  `StreetSpeciesInfo` (built from `ProcgenStreetSpecies.NAMES`, only the plain label, icon and tooltip
  are tt-sim's, and a default setback where a species has one: modern row 3.6 m, `walls.md` "Setback per
  species"), `MapWallIO` and the live-edit codec take 0 to 10, and `StreetSplit.region_tags` takes
  the newer species' tags from procgen. Numbering (saved as the index, never reorder): 0 mixed, 1 terrace,
  2 guild houses, 3 village, 4 cottages, 5 pueblo village, 6 villa street, 7 alpine hamlet, 8 canal row,
  9 tudor lane, 10 minka village; the first five keep their indices and tile ids.
  **A bug the phase found:** the six newer species draw plaster, adobe, brick, log and boards walls and
  tile, slate, shingle, thatch and turf roofs, which `WallGeometry` filed under a key `AuthoredWalls`
  never drew, so a pueblo, canal, Tudor or minka street showed only windows and roofs. Fixed host-side:
  `WallGeometry.EXTRA_PART` carries those surfaces and `AuthoredWalls._wall_node` draws each in the
  material of its kind (`StructureMaterials.make`). Tests: `test_every_street_species_builds_closes_
  saves_and_survives_the_live_edit` (build, walls drawn, procgen mesh check closed at its default
  settings with Tudor's known single leaked ray allowed, a saved map, the live-edit round trip, the
  same digest of the parts each time). Render job `batch_c_streets` (the pane with all 11 tiles, one
  24 m street of each newer species): all six read as buildings of their kind. Procgen-side notes (not
  fixed): the Tudor lane leaks one ray on flat ground (known); all six species share one roof
  palette (orange, green, grey and red tile), so a pueblo has no flat adobe-coloured roof difference and a
  minka looks like a Western farm with a thatch tone; wall tones are pale (pueblo, Tudor, minka read
  nearly white under the game light); the species have no yard dressing beyond a fence or low wall.
- **Yards.** The only yard dressing a street draws is a post and rail fence (1.0 m) or a low stone wall
  (0.7 m) round the plot with a 1.4 m gate gap in front (`row_gen.gd:48-55`, `_yard` at :222). Species
  "village" uses the fence, "cottages" the wall; others none. There is no garden, tree, path or prop inside
  a yard ("Not yet: ... a yard that is not fence or low wall (gardens, trees)", `walls.md`).
- **Regions.** `StreetSplit.region_of` (`utils/street_split.gd:66-90`) names a street's region tags from the
  biome under its middle and its species; exclusive regions (desert, mediterranean, alpine, nordic) replace
  the generic structure set, flavour regions (english, dutch) join it with `W_REGION` 4. `regional` is a tag
  on 85 of 100 core structures (the Building palette dropped the chip because it filtered nothing).
- **Split.** "Split into buildings" turns a street into `Structure` records, one per lot, matched by
  `StreetSplit.match_row` to the best core recipe; yards, trim and some facade detail are lost
  (`structures.md` "Splitting a street"). After a split the street, and with it any notion of "a village", is
  gone: only a set of independent structures remains. This matters for the design (section 3c).
- **Scatter.** Plants are cleared under each lot and its yard (`WallGeometry.clearance_crossings`, fed
  through the crossing clearance, `walls.md` "Not yet").

### 1.2 Buildings (the Building tool)

`StructureTool` (rail `structure`, label "Buildings"): about 100 library structures in 17 families (cottage 12,
house 15, townhouse 16, toon 13, fantasy 6, ruin 6, hall 5, roundhouse 5, courtyard 4, tower 3, castle 3,
farm 2, stilt house 2, windmill 2, temple 2, inn 1, granary 1; from
`libraries/core/structures/index.json`). Ghost lot, click or drag-to-size, turn, re-roll, select, handles,
door edge, variants, chips and search (`structures.md` "The tool", "Editing a building", "Palette round 2").
A `Structure` is `recipe + footprint (3..24 points) + seed + params + style`, at most `MAX_STRUCTURES` = 128,
ids 1..255 (`map_document.gd:129`, `structures.md` "Data"). Smallest default size in core: 3.2 m on a side.

- **Legal ground.** No sampled point wet, slope at most 0.445, inside the map, 0.4 m clear of other
  structures (`StructurePlacement.lot_problem`, `utils/structure_placement.gd:237`); `nearest_legal`
  slides the ghost to the closest legal spot within 7 m (`REACH_M`, :36).
- **The plan rules refuse small things.** `ProcgenPlan.problems` demands sides of at least 0.5 m and an area
  of at least 2 m2 (`procgen/core/procgen_plan.gd:16-19`), so a 1.2 m well cannot be a `Structure`.
- **Yard dressing.** `StructureDressing` (`utils/structure_dressing.gd`, probe B, 2026-10-28) draws, per
  building and derived from its record (nothing stored, `StructurePaint.mix(seed, id)` stream): a worn-earth
  skirt and a swaying door path (alpha mesh draped on the terrain), and at most `MAX_CLUSTERS` = 11 prop
  blobs by family (cottage: flower shrubs, stepping stones, tufts, a woodpile half the time; townhouse: paved
  step and two planters; house: shrubs, boulders, a step), 250 to 650 triangles and 2 draws a building.
  Clearance against water and neighbours (`NEIGHBOUR_CLEAR_M` 1.0, `NEIGHBOUR_RANGE_M` 14). This is
  the existing precedent for "a derived layer that answers to the building"; it is per building, so nothing
  in it knows about the street, a neighbour's door, a plaza or a village.
- **Ornaments** (`StructureOrnaments`, nine kinds: ivy, corner turret, buttresses, rose window, weathervane,
  hanging sign, flower boxes, awning, banners) are stored as two reserved `params` entries, `ornaments` (a
  bit mask) and `ivy_amount` (`utils/structure_ornaments.gd:22-25`; `structures.md` "Ornaments"). "Surprise
  me" picks two or three by theme. Jewel colours come from the structure's seed (`PAINT`, :86).
- **Decor plants.** Ivy and window planters are plantgen assets mounted on procgen **anchors**
  (`StructureDecor`, `structures.md` "Decor plants"): baked into ONE node per structure, capped at
  `MAX_TRIANGLES` 3000 (`structure_decor.gd:53`), shared wind materials; 30 decorated buildings are 30
  nodes and 85k triangles. The catalog contract for such assets is `placement: {scatter:false, mount,
  size_m}` (plantgen `AGENTS.md` "Decor assets"). Mounts today: `wall` and `sill` only.

### 1.3 Walls, fences, bridges

- **Wall tool** stone walls (0.4 to 2.0 m, walkable coping, `StaticBody3D` on the terrain layer) and fences
  (no collision) along a drawn line, closed loops allowed, follows the ground; one history entry per change
  (`walls.md`). There is no gate piece: a fence or wall is a continuous line. A yard's gate is only a gap.
- **Bridge tool** (planks, stones, arch, ford; `crossings.md` "Authoring") plans a crossing from two
  anchors on opposite banks (`CrossingEditor.plan`); it is a separate gesture and nothing links a street to it.

### 1.4 Ground and paths

- **Paint tool** ("Lay paths, yards and rock", `paint_tool.gd:18`): a palette surface painted into the
  document's weights, up to `GroundLayers.MAX_PAINTED` = 64 surfaces (`utils/ground_layers.gd:46`). Surfaces
  with role `built` clear plants under them and thin a fringe beside them (`utils/scatter_ground.gd:8, 48`)
  and tint the surrounding ground with a trampled edge (`authored_terrain.md` "Broad edge",
  `TRAMPLE_WEIGHT` 0.55). Core carries road and paving sets (`cobblestone`, `dirt_road_packed`,
  `dirt_road_caliche`, `flagstone`, `gravel`, `planks`, `stone_tiles`; `core-library/surfaces/`).
- **Nothing connects a street to ground paint.** A street has no road; the player paints one by hand.
  The only automatic worn ground is the per-building skirt and door path of `StructureDressing`.

### 1.5 Scatter, clearance, plants

The scatter (biome rules) clears under structures with strips along the front edge,
`StructureGeometry.clearance_crossings` (`utils/structure_geometry.gd:419`, `CLEAR_STRIP_M` 0.75,
`CLEAR_MAX_STRIPS` 12, `CLEAR_TRIM_M` 0.55). The Place tool sets "a hero tree, rock or log" and the live
edit kind `props` (`utils/live_edit_codec.gd:57, 93`) carries those. **Naming warning:** tt-sim already uses
"props" for those hero scatter objects, so the new layer must not be called `props` in tt-sim code or in
the map file (section 3).

### 1.6 What a player can build in five minutes, and what is missing

In five minutes a player can: sculpt a lane, drag a Village-species street (cottages with fenced yards and
dirt skirts), re-roll it, split it, swap a few houses, add ivy and flower boxes with Surprise me, lay a
stone wall round a green, paint a dirt path, put a plank bridge over a stream and scatter a forest around.
The result is a row of good houses on bare ground. It reads as "buildings placed", not "somewhere people
live", for these reasons:

- no road, no centre of the village (well, green, market), nothing in the street at all;
- nothing between doors and street but a faded path; yards hold shrubs and a woodpile;
- the same props per family (cottage yards all draw from one short list);
- no variation of the whole place: one street, one species; wealth, trade and landscape do not show;
- the village does not answer: move a house and the bridge, wall and path stay where they were.

## 2. Gap analysis against a good village

"Have" is what exists today; "Cheap" and "Hard" are the cost classes used in section 4.

| Need | Have | Gap | Cost |
|------|------|-----|------|
| Street furniture: wells, carts, barrels, crates, benches, troughs, signs | woodpile, shrub, boulder blobs in yards | no street-side props at all | props + street-edge rule |
| Lamp posts, hanging lanterns | none (window glow not built: `structures.md` "Not yet") | lamps give the evening mood; a warm emissive accent | prop + material |
| Market stalls, awnings, banners | awning and banners ornaments on a building | free-standing stalls, plaza layout | prop + plaza rule |
| Shrines, crosses, standing stones | none (temple family is a building) | wayside and village-centre pieces | prop |
| Laundry lines, hay, woodpiles, coops, beehives | woodpile blob | yard life, character-specific | props + yard rule |
| Plazas and greens | none | a shape the street opens into, with a centre piece and a rim of things | plaza gesture + rule |
| Door paths and yard paving | skirt + path per building (alpha mesh) | paths that join the street, road surface, paved plazas | ground paint at Dress time |
| Gardens, orchards, allotments | shrubs, flower shrubs in yards | vegetable beds, fruit trees in rows, hedges | plantgen decor + garden rule |
| Boundary walls and gates | yard fence, stone wall, wall tool | gate pieces, village edge gate, wall that follows the settlement | gate props + boundary rule |
| Bridges where a street crosses water | Bridge tool, manual | detect crossing, offer a bridge, choose by character | Hard (water + street intersect) |
| Harbour | stilt houses, crossings | jetties, boats, nets, crates at the water edge | props + water-edge rule |
| Character by region and wealth | 11 street species (5 reachable), region tags, `regional` | one species per street, no wealth, no props or plants by character | kits |
| Density | `skip_chance`, yard margin | nothing governs how full a street is; no emptiness rule | density rule |
| Responds to edits | structures follow ground edits (`StructureEditor.follow`) | props do not exist | derived layer |

Density is a design problem as much as a count: the bar is "not every house has a barrel". A kit sets a
budget in props per 10 m of frontage, and every rule draws with a chance, so a character has quiet stretches.

## 3. Proposed architecture

### 3a. Props: a new family in the structure pipeline

A prop is a small procgen structure: same recipe format (`plantgen-graph`, `interface`, `@name` bindings),
same evaluator (`evaluate_structure`), same digests, same mesh check (`ProcgenMeshCheck`, closed meshes,
clockwise winding), same tags and provenance, same anchors for plants. What is new:

- **Family `prop`, tag `prop` plus a kind tag** (`prop`, `well`, `lamp`, ...), shipped in the library's
  `structures/` folder (index entry `family: "prop"`). Phase 1 needs no new library kind: reading, hashing,
  transfer, Verify and tiles already handle the folder. The Building palette hides the family (a
  `StructurePalette.GROUPS` filter) so props do not appear among houses.
- **Budget: under 500 triangles each**, 300 target (compare the building median 1,838, `structure_performance.md`;
  the yard blobs 250 to 650 per building). Verify's per-structure check adds a prop limit (fail over 500).
- **Input is a point, not a polygon.** The host synthesises a small rectangle (centre, yaw, size) as the
  guide. Because `ProcgenPlan.problems` refuses under 2 m2 (`procgen_plan.gd:19`), procgen needs a
  prop-aware entry (`evaluate_prop`, or `problems(points, min_area)`): a procgen change of a few lines,
  keeping the building rules untouched. Prop recipes expose `width`, `height`, `variant`, colour hints.
- **Extra index keys** (read by procgen's `ProcgenStructureIndex`, the one place the key lists live):
  `slots` (where it may go: `street_edge`, `beside_door`, `yard`, `plaza`, `water_edge`, `village_edge`,
  `field`), `radius_m` (its clearance disc), `blocks` (`none`, `stand`, `solid`; section 3f) and `tint`
  (`none`, `jewel`, `wood`), so a kit can pick by slot and a tool can reject by size without evaluating.
- **Variants are cached, not unique.** A building is built once per structure because its footprint is
  unique. A prop is the same mesh in many places, so each prop id is built for a few variants (seeds 0..3) and
  instances are transforms of the cached variant (plus a tint). That keeps build cost at (props x variants),
  not (props placed). At the measured 17 ms per 1,000 triangles a 300 triangle prop is about 5 ms, so a
  20-prop set at 4 variants is about 0.4 s of worker time, once, instead of 0.75 s per village on every
  edit. Determinism is untouched: the variant index comes from the placement's seed.
- **Plants stay plantgen.** Hedges, fruit trees, planters, vegetable beds, flowers and ivy are plantgen
  assets with a `decor` placement (`scatter:false`) that gain new `mount` values (`ground`, `row`). Procgen
  props carry anchors for them exactly as ornaments do (`StructureDecor` pattern), so a market stall or a
  coop can ask for a planter.

**Starter list: 20 props, ranked by value.** Value is how much a street changes when it appears; the rank
is the build order. All procgen props unless marked plantgen. Triangles are targets.

| # | Prop | Slot | Tris | Characters | Note |
|---|------|------|------|-----------|------|
| 1 | Barrel (single, pair) | beside door, street edge | 150 | all | cheapest, most common read of "lived in" |
| 2 | Crate stack | beside door, quay | 120 | town, harbour | stand-on collision |
| 3 | Well | plaza centre, junction, yard | 400 | all | the village centre; roofed or open |
| 4 | Lamp post / hanging lantern | street edge | 200 | town, harbour, wealthy | warm accent; later emissive |
| 5 | Bench | street edge, plaza, green | 150 | town, wealthy | stand-on |
| 6 | Market stall (awning, jewel palette) | plaza edge | 450 | market town | one or two awning colours from seed |
| 7 | Hay stack / bale | yard, field | 250 | farming | painterly mound |
| 8 | Woodpile (shared with the existing dressing blob) | yard, beside door | 200 | farming, highland | replace the blob |
| 9 | Hand cart / wagon | street edge, yard | 450 | farming, market | stand-on bed |
| 10 | Signpost (crossroads, inn sign on a post) | junction, village edge | 180 | all | tied to the village name later |
| 11 | Wayside shrine / cross / standing stone | village edge, green | 300 | by character | character carries the variant |
| 12 | Gate (field gate, yard gate, wall gate arch) | boundary, village edge | 250 | all | fixes the Wall tool's missing gate |
| 13 | Water trough | street edge, yard | 160 | farming | beside a well |
| 14 | Laundry line (two poles, cloth in jewel colours) | yard | 260 | town, poor | the cheapest source of colour |
| 15 | Hedge segment (plantgen) | boundary, yard | n/a | farming, English | clipped, tiled along an edge |
| 16 | Garden bed / vegetable rows (plantgen) | yard, field | n/a | farming | painted row decor |
| 17 | Beehive skeps | yard | 120 | farming | tiny, characterful |
| 18 | Market cross / fountain (plaza centre piece) | plaza centre | 450 | market town | alternative to the well |
| 19 | Jetty / mooring post with boat | water edge | 450 | harbour | needs the water-edge rule |
| 20 | Scarecrow / coop / dovecote | field, yard | 250 | farming | one prop file, three variants |

Fruit trees for orchards are plantgen species placed in rows by the garden rule, not props.

### 3b. Settlement kits: village composition rules as data

A **settlement kit** is JSON, a sibling of the street species: it names what a village character draws and
where. It is evaluated by a pure procgen function, `ProcgenSettlement.place(kit, frontage, extras, seed)`,
with no scene tree, so it runs in procgen's module-only tests (`tools/procgen.ps1 test`, about 9 s) and on a
worker. In phase 1 kits live in procgen (`recipes/kits/*.json`, golden-file test like
`tests/test_street_species.gd`); in phase 4 they become a library kind (`kits/`) so a user library can ship a
village character with its own props.

**Inputs.** A *frontage* list, one entry per building: `door` point, `front` direction, `footprint`, `plot`
(the lot's yard rectangle when it comes from a street, else the footprint grown 1.5 m), `street_side` and
`street_distance`. A street gives these from `row_lots` directly; standing `Structure`s give them from their
record and `ProcgenBuildingLayout.door_opening()` (what `StructureDressing._door` already does, falling back
to the middle of edge 0). Also: the street polyline, the plazas, the water and ground queries (the same
environment callbacks the evaluators use), and the other structures' footprints. Because both sources
reduce to a frontage list, **the same kit dresses a generated street and a hand-placed village**.

**Slots (the vocabulary).**

| Slot | Meaning | Typical contents |
|------|---------|------------------|
| `street_edge` | a strip beside the street line at intervals, between doors | lamp, bench, trough, cart |
| `beside_door` | within 0.6 to 1.8 m of a door, off the path | barrel, crate, planter, bench |
| `side_gap` | the gap between two lots | woodpile, hay, cart, hedge end |
| `front_yard` / `back_yard` | inside a lot's plot | laundry, coop, garden bed, hive, hay |
| `plaza` (`centre`, `edge`) | in a plaza shape | well or cross; stalls on the rim; benches |
| `junction` | where two streets meet or a street bends sharply | signpost, well, shrine |
| `water_edge` | within 2.5 m of a bank | jetty, boat, crates, nets |
| `village_edge` | the first and last 4 m of the street, and the boundary line | gate, signpost, shrine, hedge |
| `field` | a free polygon the player painted (phase 3) | crop rows, orchard, scarecrow |

**Rule shape (data).**

```
{ "format": "ttsim-settlement-kit", "version": 1, "name": "farming_hamlet",
  "street": {"species": "village", "yard": "hedge", "road": "dirt_road_packed"},
  "region": ["english"], "wealth": [0.0, 0.55], "density": 0.55,
  "rules": [
    {"id": "door_barrel", "slot": "beside_door", "chance": 0.45, "max_per_lot": 1,
     "pick": [{"prop": "barrel", "w": 3}, {"prop": "crate_stack", "w": 1}]},
    {"id": "lamps", "slot": "street_edge", "every_m": [20, 30], "side": "alternate",
     "min_wealth": 0.4, "keep_from_door_m": 1.5, "pick": [{"prop": "lamp_post", "w": 1}]},
    {"id": "yard_life", "slot": "back_yard", "count": [0, 2],
     "pick": [{"prop": "haystack", "w": 2}, {"prop": "woodpile", "w": 2}, {"prop": "laundry_line", "w": 1}]},
    {"id": "centre", "slot": "plaza.centre", "count": 1, "pick": [{"prop": "well", "w": 1}]},
    {"id": "gate", "slot": "village_edge", "pick": [{"prop": "gate_field", "w": 1}]} ],
  "ornaments": {"flower_boxes": 0.4, "ivy": 0.3},
  "ground": {"door_path": "dirt", "plaza": "cobblestone", "yard": "grass_meadow"} }
```

**Characters.** A character is a kit plus the species and region it implies. Four to start, each a distinct
mixture rather than a theme skin (the no-sameness rule: a seed also draws a **wealth** scalar inside the kit's
range, which gates lamps, paving, planters, awnings and banners, and a **density** jitter):

| Character | Species | Draws |
|-----------|---------|-------|
| Farming hamlet | village / cottages | hay, woodpile, cart, trough, hedges, gardens, field gates; no lamps; dirt road |
| Harbour town | canal row / guild houses | quay crates, jetties, boats, lamps, signs, stalls; paved edge |
| Hill fort village | alpine hamlet / cottages | low walls, shrine, standing stone, gate, woodpiles, sheep trough |
| Market town | terrace / guild houses | plaza with cross or fountain, stalls, benches, lamps, signs, laundry |
| Modern town (2026-11-01) | modern row | kerb lamps, bins, post boxes, bollards, bike racks, parked cars, hero phone boxes, planters and bus shelters; asphalt road, kerb paving, concrete plaza |

Pueblo, minka and tudor species map to later kits (ovens, ladders, rice drying racks); regional props follow
the `regional` tag convention: a prop tagged with a region joins only that region's kits.

**Determinism and stability.** Every candidate has a **slot key** (settlement seed, frontage key, slot name,
index) and its own stream `PlantRng.sub(slot key)`, exactly as `ProcgenRow.plan` isolates lots. Moving a
house changes only the slots of that frontage. Candidates are tested against fixed-priority earlier
placements only (clearance discs, footprints, water, slope, a spatial hash), never against later ones, so
there are no cascades. Counts and offsets are computed on integer millimetre lattices so a boundary does not
flip between platforms (the `floor` and `ceil` hazard in `structures.md` "Determinism"); positions are
rounded to 1 cm. A golden digest file (`expected_settlement_digests.txt`) pins `kit x street x seed` to the
list of `(prop, x, z, yaw, variant)`.

### 3c. Entity or derived layer: the decision

Options, with the facts that decide them:

| | A. Every prop a record | B. Pure derived layer | C. Derived + overrides (recommended) |
|-|-|-|-|
| Save size | 150 records | tens of bytes | tens of bytes + overrides |
| Document cap | `MAX_STRUCTURES` is 128 (ids 1..255), already full at 60 buildings + 150 props | none | small per-settlement caps |
| History | "Dress" = 150 entries or one huge entry | one entry | one entry |
| Live edit | whole list per commit (about 1 KB per structure; 128 KB at 128) | tiny | tiny |
| Build keys | `keys_of` costs 0.36 ms each, 36 ms at 100 (`structure_performance.md`) | none | none |
| House moves, ground edits | props stay, now inside a wall | village answers | village answers |
| Fine control | full | none | removed, moved and added props |
| Tiny Glade feel | tedious | magical but frustrating | both |

Decision: **C.** The village is a `Settlement` record; props are derived; the player's exceptions are
overrides, each tiny and explicit.

- **Record** (`resources/settlement.gd`, map entry `settlements.json`, `MapSettlementIO` modelled on
  `MapStructureIO`): `id` (1..32), `kit` (`<library>:<name>` once kits are a library kind, else a procgen
  name), `seed`, `wealth` (0..1, 0.01 steps), `density` (0..1), `source` (a `Wall` id of a street, or a copy
  of the centre line and side and setback after a split; so a settlement survives "Split into buildings",
  which today erases all knowledge of the village), `plazas` (up to 4 polygons or discs), `fields` (phase 3),
  and three override lists: `removed` (slot keys), `pinned` (explicit props: `ref`, position at 1 cm, yaw,
  scale, variant) and `swapped` (slot key to another ref). Caps: 8 settlements, 64 overrides each.
  Validation reuses the reader rules (untrusted input, every problem a warning and a skipped record, byte-
  identical re-save).
- **Which buildings belong to a settlement.** A structure belongs to the settlement whose street or plaza
  region it fronts (its door within the street's reach). Settlement membership is computed, not stored.
- **Editor** (`SettlementEditor`, `AuthoringEditor.settlements`): one history entry per change holding the
  list before and after, the pattern of `StructureEditor.apply_list`. `follow(area)` re-derives after a
  sculpt, water or structure edit in the same history entry, as `walls.follow` and `structures.follow` do.
- **Live edit.** A new kind `settlements` in `LiveEditCodec.KINDS` (`live_edit_codec.gd:57`) carrying the
  whole (tiny) list, validated by `MapSettlementIO.parse_list`; props are never sent, every peer derives
  the same list (hence the determinism pins). `MapFingerprint` gets a `settlements` key: the records, and
  one line per baked cell node (vertex count and AABB, like `AuthoredStructures`).
- **Order of work after an edit.** Structures change first (their keys), then `follow` recomputes the
  settlements that touch the changed area: the frontage list, the placements, then re-bakes only the cells
  whose placements changed (cell hash in the key).
- **The structure params pattern.** Ornaments chose "reserved `params` entries" because a building owns its
  ornaments. A settlement owns its props, so it gets its own record, but the same ideas hold: nothing derived
  is stored, the seed is stored, a re-roll is the next seed of a series, and the record validates and
  round-trips byte-identically.
- **Saved maps and compatibility.** An older build ignores the unknown entry (as with walls and structures,
  accepted: it drops the settlement on its next save). A map's `libraries` record lists the library of the
  kit and of every prop reference, so a missing library shows a gap, not a crash (a missing prop is skipped
  and counted; nothing placeholder-sized). The suite has no real users (`AGENTS.md` "Nothing is off limits"),
  so no migration is needed for the street species change of section 4.

### 3d. Street gestures (Tiny Glade style)

All gestures write the `Settlement` record; none edits a prop directly unless the player pins one.

1. **Village character picker** on the Street tool's pane: today five species tiles
   (`WallToolPane`, `wall_brush.gd:31`); it becomes the four characters above, each with a thumbnail of its
   rendered street, and "Mixed" (no kit) stays. Picking a character before drawing sets species and kit;
   picking over a laid street re-characters it. This is where the six unreachable species become visible.
2. **Dress this street** button: on a picked street's bar (next to Split) and on the Buildings selection
   bar ("Dress around here": the settlement of the selection, or a new one grown from the nearest street and
   structures). One history entry. A **Re-dress** key (R over a settlement) draws the next seed. It also
   paints the road and door paths (3e below). Undo removes the whole dressing in one step.
3. **Drag to add a plaza.** In the Village tool (phase 3), a drag from a point opens a round-edged plaza
   (disc or rounded rectangle) that the street flows into; the plaza's rim takes the plaza slot rules,
   the centre piece comes from the kit, the ground under it is painted paving, and buildings that front it
   are not moved (the plaza only decides where props go; a building inside it is a warning chip, not an
   error). Resize by dragging the rim, delete with Del.
4. **Paint a garden / field.** A second drag mode paints a free polygon (3..16 points) with a type tile:
   Garden, Orchard, Field, Green. The field rule fills it with plantgen rows or a hedge edge. This is also
   how an orchard or allotment is made behind a row of houses.
5. **Props are touchable.** A hover outline picks a derived prop by proximity to its disc (the derived list
   is also the pick table; baked meshes have no per-prop nodes). Click selects: Remove (adds a `removed`
   key), Swap (cycles `swapped`), Move (drag; becomes `pinned`), Pin (freeze where it is), Re-roll one.
6. **No way to make something ugly.** The rules, not the player, prevent bad outcomes: clearances, slope and
   water checks, no prop within 1.5 m of a door's path (`DOOR_CLEAR_M` is 1.5, `structure_dressing.gd:31`),
   one density budget, and a character's palette. A drag past a limit clamps and shows the clamp, never an
   error, as the Building tool does.

### 3e. Paths, ground and bridges

- **Roads and door paths use the existing Paint layer, written at Dress time (BUILT, topic villages2,
  2026-10-31: section 8).** The Dress command paints
  the kit's `road` surface along the street's centre line (width from the setback), joins each door to the
  street with the kit's `door_path` surface (a few world-metre strokes), and fills plazas with `plaza`
  surface. These are `SurfaceStroke`s through the paint editor, in the same history entry, so they undo
  with the dressing, clear plants under them (role `built`), tint their surroundings and appear for every
  peer through the existing `surface` live edit. Cost: they take painted-surface slots
  (`MAX_PAINTED` 64, shared with the map), so a kit names at most three. The alpha skirt of
  `StructureDressing` stays for single buildings and is hidden where a path stroke already joins the door.
  Alternative considered: a derived alpha road mesh like the skirt. It is cheaper to roll back but is
  invisible to scatter, to the broad tint and to the Paint tool, and never matches the player's own paint;
  rejected for roads, kept for the soft yard skirt.
- **Yards** keep the species' fence or wall (`row_gen.gd:222`); the kit adds a `yard` surface and the
  back-yard rules. The fence piece gains a real gate prop at the gap (prop 12), replacing the 1.4 m hole.
- **Bridges (BUILT, topic bridges, 2026-10-31: section 12; laid by Dress in its own entry, not a
  suggestion chip).** Phase 5: when the street polyline crosses water (`WaterGeometry.is_wet_at`), Dress offers a
  bridge through `CrossingEditor.plan` at the crossing, kind by character (planks for a hamlet, arch for a
  town, ford for a poor lane), as a separate undoable crossing; the street continues over it. The street
  data is untouched. This stays a suggestion chip, since a crossing changes the map's water reading.
- **Boundary walls and gates (BUILT, topic bounds, 2026-10-31: section 13; drawn by the Dress from the kit
  and seed, not a `village_edge` rule).** A `village_edge` rule can ask for a wall or hedge line round the settlement
  hull (a closed `Wall` or plantgen hedge) with gates at street ends; it is generated as derived geometry
  (a procgen wall along the hull) in phase 4, not as `Wall` records, to stay under `MAX_WALLS` 64.

### 3f. Collision and tokens

Walls today: a stone wall is a surface to stand on, a fence blocks nothing, and "blocking movement is a game
rule decision still to make" (`walls.md` "Not yet"). Props follow the same line so they add no rule:

- `blocks: none` (default): no collision (lamp post top, signpost, laundry, hedge segment, hay).
- `blocks: stand` (BUILT, topic propstand, 2026-11-03, owner verdict TK1: a token dropped on hay or crates
  stands ON them): simple upward boxes on the terrain layer so a token placed on it lands on its top and is
  grounded there. Built for the bulky props only: crate stack, haystack, barrel, woodpile, hand cart, farm
  wagon (`PropStand.STANDING`); the well, bench, stall and the rest stay `none` until asked for.
- `blocks: solid`: all faces (well, shrine, cross, market stall posts), still a standing surface, not a rule.
  Not built.

How `stand` is built (`utils/prop_stand.gd`, `AuthoredSettlements._add_stand`). The boxes are MEASURED from
each prop variant's own mesh, not tabulated, because a draw changes the shape (a crate stack is one to three
crates tall, a hay stack a mound, a twin mound or bales): the variant's upward faces are sampled on a 0.12 m
lattice, a cell takes the lowest top at its corners and centre (a token sinks a little into hay rather than
floating over a slope), heights are floored to 0.06 m, and runs of equal height merge into boxes. If a variant
needs more boxes than its limit (24, haystack 72) the height quantum grows by 1.5 until it fits. The boxes
are placed with the mesh's own transform (tilt, yaw, drawn scale folded into the box size, since a physics shape
cannot be scaled), one `StaticBody3D` `Stand_<cell>` per bake cell (layer 1, mask 0, not ray pickable, meta
`tt_stand`), made and freed with the cell's mesh. Measured on the farming hamlet (seed 1234): crate stack 3 to 9
boxes (tops 0.48 and 1.02 m at default size), haystack 24 boxes (tops 0.61 and 1.22 of a 1.83 apex before the
1.3 drawn scale; the apex is a cone, a token stands on its upper part), hand cart about 10, wagon about 18,
barrel 9 to 18, woodpile 8 to 10. Since topic haytop (2026-11-04) a mound ends in a broad flat crown instead
of a cone apex, so a token stands on one box 0.96 x 0.84 m (0.50 of the 1.68 m foot across, was 0.48 x 0.48 m);
see structures.md "Hay crown".

- A token's landing (`WaterSurface.landing_below`, terrain layer) needs no change: it meets the box tops. The
  eye view's sphere, the brush rays, the building test and the dressing ground fit EXCLUDE these bodies
  (`AuthoredSettlements.exclude_of`), so a prop is never a wall to the eye or ground to a brush or a plant.
  The drag pointer ray, the drop indicator, the ruler and the measure tool do see them (a token dragged over hay
  follows its top).
- A play load waits for the furnishings' bake (`StructureLoadWait.wait_settlements_async`) before tokens are set
  down and the ground fit runs, so a saved token standing on a crate is not pulled to the ground.
- A saved token standing on the ground inside a prop with its top under the prop's top is not moved (the cast
  starts inside the box and meets no face); one whose top is above the prop's is set on the prop at the next
  re-ground. Synced moves are unchanged: the host's landing is what peers receive.
- Not covered: a token pushed against a prop is not blocked (`solid` and any movement rule are still an owner
  call, section 6); the owner's real-mouse drag over hay and crates is unverified.

**Measured, card eyepin (2026-11-03), the input for the real-collision card.** A token's drop lands through
`TokenWater.landing_position` -> `WaterSurface.landing_below`, a cast on the terrain layer only, and the baked
prop cells have no collision yet, so a token dropped on a haystack or a crate stack lands on the ground inside
it (street map, seed 1234, farming hamlet, 27 bulky props: token at the haystack (-24.46, -16.11) and at the
crate stack (-15.56, -20.7), y = 0.0). At the eye the bales and crates then go through the figure's legs and
torso. A footprint push-out (a pure box test: default size x placement scale x yaw, drop moved to the nearest
ground outside by the token radius, four rounds) was prototyped and unit-tested, then dropped by the owner
(2026-11-04: "collision", real collision as its own card, no push-out); it would also have kept the player from
placing a token against a prop on purpose. The default sizes it used, width x depth in metres at scale 1
(procgen `props_and_settlements.md`), are the size table the collision faces can be checked against:

| Prop | W x D | Prop | W x D |
|------|-------|------|-------|
| barrel | 1.5 x 1.2 | water_trough | 1.8 x 0.8 |
| crate_stack | 1.3 x 1.0 | beehive_skeps | 1.6 x 1.0 |
| well | 1.8 x 1.8 | planter | 0.9 x 0.9 |
| haystack | 2.2 x 2.0 | hand_cart | 1.3 x 2.3 |
| woodpile | 1.6 x 0.9 | farm_wagon | 1.8 x 3.4 |
| market_stall | 2.4 x 1.7 | parked_car | 1.9 x 4.3 |
| wayside_shrine | 1.1 x 1.1 | | |

Low and thin props (bench, signpost, lamp post, gates, laundry) were left out as ones a token may stand
against. Open points the prototype showed: a one-metre gap in a closed yard fits a 0.6 m token but a
push-out loop could eject it; synced moves are the host's landing, so any rule must run on the host; a
reground on load must apply it too (a saved token already inside a prop stays).

## 4. Phases

Each phase is independently shippable and ends with the repo gates green. Sizes are ideal working days for
one agent including tests and a render look round.

| Phase | Content | Size | Touches |
|-------|---------|------|---------|
| 0. Reach the species (DONE, batch_c) | Expose the six hidden street species: `Wall.ROW_PRESETS` 5 to 11, `MapWallIO` range, pane tiles (`StreetSpeciesInfo`), readout names, region tags; tests and a render of each; plus the street surfaces the newer species need (`WallGeometry.EXTRA_PART`) | 1 | tt-sim |
| 1. First dressing | `prop` family: 8 props (barrel, crate stack, well, lamp post, bench, hay stack, woodpile, signpost); `ProcgenSettlement` rules v1 with slots `street_edge`, `beside_door`, `back_yard`, `side_gap`; 2 kits (farming hamlet, market town); `Settlement` record, editor, IO, live edit, fingerprint; derived baked cells; **Dress this street** button | 6-8 | procgen, core-library, tt-sim |
| 2. Ground and yards (road, door paths and plaza paint DONE, villages2) | remaining props 9 to 14; road, door-path and yard paint at Dress time; gate prop in the yard fence; a decor `ground` mount in plantgen (hedge, garden bed); back-yard garden rule | 5-6 | procgen, plantgen, core-library, tt-sim |
| 3. Gestures | Village tool: plaza drag, garden/field paint, prop select/remove/swap/pin; character picker with thumbnails; wealth and density sliders in the bar | 6-8 | tt-sim (Village tool, pane, hints), procgen |
| 4. Characters and library kind | harbour and hill-fort kits (jetty, boat, shrine, standing stone, water-edge and village-edge rules); kits become a library kind (`kits/` folder: reader, hash, transfer, Verify, structgen kit editor view); boundary hull | 6-8 | procgen, tt-sim, core-library, structgen |
| 5. Water and bridges | auto-suggest a bridge where a street crosses water; harbour quays; merge chunk LOD if measured necessary | 3-4 | tt-sim, procgen |

### 4.1 Tests

- **procgen** (module-only, `tools/procgen.ps1 test`): pure rule tests, a **golden placement digest** file
  (`kit x street preset x seed` to the list of props, rounded), slot tests (door clearance, water, slope,
  neighbour footprint, density budget, move-one-house-only-changes-its-frontage), and per-prop **mesh check**
  and triangle budget (under 500) via the existing structure pins (`pins.txt` gains the props).
- **tt-sim** (gate): `test_settlement_io.gd` (round trip, hostile reader, caps, byte-identical re-save),
  `test_settlement_editor.gd` (history, live edit op end to end, `follow` after a sculpt and after moving a
  house), `test_settlement_build.gd` (cells, keys, bake counts, collision, pick table), the determinism
  workflow gains the settlement pins (`tools/determinism_report.gd` kind `settlement`), fingerprint key.
- **Render jobs:** `settlement_look` (each character before and after, home and two close views, plus a
  night/evening look when lamps exist), `settlement_perf_village` (the 60 + 150 case below). Render jobs keep
  no level and remove their `_settlement_` levels.

### 4.2 Performance: a 60-structure village with 150 props

Reference (`structure_performance.md`, 2026-10-30, indicative): 64 structures build at median 1,838
triangles and 35 ms; materials are shared (24 for 100 structures); each structure is about 7.1 mesh
instances; 100 structures add about 700 visible draws and 440 shadow draws and 0.4 ms CPU; 30 baked decor
nodes are 85k triangles, 10.8 MB.

| Item | Naive (one node per prop) | Plan (baked cells) |
|------|---------------------------|--------------------|
| Triangles | 150 x about 300 = 45k | same 45k (roughly +40 percent of a dressed street's yard blobs, 60 x 450 = 27k, which the props replace in part) |
| Draw calls | 150 x 1-3 surfaces = 150 to 450 | cells of 24 m: a 150 m street is 6 to 9 cells x 3 surfaces (opaque painterly, cloth double-sided, glow) = 18 to 27 draws |
| Nodes | 150 | 6 to 9 `MeshInstance3D` + 6 to 9 collision bodies |
| Build (worker) | 150 x about 5 ms = 0.75 s per village | 80 cached variants (20 props x 4) built once, 0.4 s; re-dressing is transforms |
| Memory | about 6 MB of arrays | about 6 MB baked (decor reference: 85k tris is 10.8 MB; line 40 MB) |
| Pick/collision | per node | one pick table, one body per cell |

Plan: bake each cell's placements into one `ArrayMesh` with one surface per material kind (the
`StructureDecor.bake` pattern, `structures.md` "Nodes (baked, polish3)"; arrays in and out, pure), wind
weights in vertex colour for the few moving pieces (cloth, hedge), shadows on for tall props only. Total
village draw calls: 60 structures about 430 + yard dressing 120 (2 per building) + props 18 to 27, so props
add under 5 percent. A budget of 600 derived props per map and 400 per settlement, enforced by the density
rule, keeps the worst case at 120k triangles. Measure with the render job and the `docs/PERFORMANCE.md`
procedure before relying on any number; merge-and-LOD beyond cells is deferred until a measured need
(consistent with the struct_perf conclusion).

### 4.3 Which repos each phase touches

procgen: props, `ProcgenSettlement`, kits, golden files, prop-aware plan rule, index keys. plantgen: `ground`
and `row` decor mounts, hedge, garden bed, fruit tree rows, plus rebuilt core GLBs. core-library: prop
recipes and `index.json`, kits, thumbnails (rendered by tt-sim). tt-sim: record, IO, editor, nodes, tool,
pane, hints, live edit, fingerprint, docs. structgen: previews props (family is just a structure) in
phase 1 for free, and a kit viewer in phase 4. Pins: procgen moves at each milestone in both hosts
(`D:/dev/tabletop/AGENTS.md` "Keep procgen's pins current at milestones"); the core library copy follows
the "Updating core" procedure.

## 5. First-phase recommendation

**Smallest slice that visibly changes a street: phase 0 + phase 1, about 7 to 9 days**, in this order:

1. Phase 0 (1 day, ships alone): the Street tool offers all 11 species. It already changes what a newcomer
   sees on the first street and needs no new concept.
2. Eight props (barrel, crate stack, well, lamp post, bench, hay stack, woodpile, signpost) in procgen with
   pins and budget checks, exported to core.
3. `ProcgenSettlement` v1, two kits (farming hamlet, market town), golden digests.
4. The `Settlement` record, editor and live edit, derived baked cells, and a **Dress this street** button on
   a picked street's bar (and R to re-dress). No new tool, no plaza gesture, no ground paint yet.

Why this slice: it touches every layer once (procgen data, library, record, editor, nodes, UI) so the design
is proven end to end, while the high-risk items (plazas, bridges, library kind for kits) wait for what the
slice teaches. Acceptance: a Village-species street of 12 houses with Dress gets 25 to 45 props whose
spacing differs on each re-dress, none inside a door path, a wall, water or a neighbour; undo removes them in
one step; a saved and reloaded map and a live-edit peer show identical props; moving a house changes only
the props of that frontage; added draws under 30; added triangles under 15k.

Risks to watch in the slice: the prop-aware plan rule in procgen (small but cross-repo, needs both pins);
variant caching and the bake pipeline (reuse `StructureDecor.bake`); naming (keep `prop` out of tt-sim code
and map files, use `Furnishing` in tt-sim: `Settlement` record, `settlement_props` nodes).

## 6. Open questions that need the owner

1. **Do tokens collide with props?** Stand-on faces for crates, carts and benches are cheap and consistent
   with walls today. Blocking sideways movement (a well or a stall as an obstacle) is a game rule decision
   the walls doc has deferred; the design works either way, but `solid` props should not ship before that call.
2. **Scope of derived props in play.** Should the GM be able to dress, re-dress and remove props live in
   play (the Events pane lists the Wall and Building brushes), or authoring only at first? Authoring-only
   saves the Events pane wiring in phases 1 to 3.
3. **A new Village tool, or grow the Street tool?** The Wall tool already carries stone, fence and street
   and its pane would take the character picker and plaza/garden gestures. This design recommends a new
   tool only at phase 3; the owner may prefer to keep everything on the Street tile and not add a rail icon.

Smaller calls this doc made on its own (reverse freely): `family: "prop"` inside the existing `structures/`
kind rather than a new library kind; four starting characters; roads painted via the Paint layer rather than
a derived mesh; props named `Furnishing` in tt-sim to avoid the existing hero-prop `props` kind.

## 7. Phase 1 as built (host step B, topic `settlement`, 2026-10-31)

The record, codec, layer and the Dress bar are built; see `docs/systems/settlements.md`. Deviations from the
design above:

- Named `Settlement` (record, editor, layer `AuthoredSettlements`); no `Furnishing` class (the placements are
  plain dictionaries). Map entry `settlements.json`, cap 8, ids 1 to 32.
- `pinned` stores the whole placement (a pin must survive a re-dress), not a bare slot id.
- A removed street leaves its settlement in the document (draws nothing, returns on undo) instead of
  deleting it.
- Split freezes the frontage (props stay put); following later house moves is not built.
- Cells have 4 to 5 surfaces each (opaque wood, stone, thatch, accent, cloth, glass, water), so a dressed
  52 m two-sided street is 4 to 5 cells and 21 to 25 surfaces: more than the estimate of 18 to 27 draws for
  150 props. Measured numbers in `docs/PERFORMANCE.md` "Settlement furnishings".
- Addendum (topic settlement_look, 2026-10-31; `docs/systems/settlements.md` "Look pass"): the scatter now
  keeps out of every street's corridor (facade line to facade line plus 2 m, dressed or not) through the
  existing wall clearance; props are drawn 1.35 times larger (1.12 at doors), the prop role is more saturated
  and warm, props stand at the lowest ground under their footprint and lean up to 12 degrees to the slope, cells
  are 48 m and look-alike prop kinds share a surface (64 to 34 surfaces for 152 props). The painted road of
  phase 2 still comes on top. Cloth sway reads at storm strength at close zoom; calm is subtle, and the
  default camera sees the back of the near house row, so a street's own props are mostly hidden at home zoom
  (a camera matter, not a clearance one).

## 8. Phase 2, first slice as built (topic villages2, 2026-10-31)

The first bullet of section 3e plus the `plazas` record field; details and numbers in
`docs/systems/settlements.md` "Ground". What changed against the design above:

- The kit's `ground` block did not exist in the kit JSON (the design only sketched it): procgen now carries
  `"ground": {"road", "door_path", "plaza"}` in the four kits and `ProcgenSettlement.ground_of` validates it
  (three surfaces at most, two roles may share a slot).
- Road width is `0.58 x setback` a side (1.74 m at the default), door paths are two strokes bent a few
  centimetres, a plaza is one disc stroke; all refused on water, steep ground and buildings, counted.
- Plazas are discs (not polygons yet), up to 4 per settlement, created through `SettlementEditor.add_plaza`
  only; the Village tool is phase 3.
- Dress is one history group: props, record and paint undo together, and the paint reaches peers as `surface`
  ops (no new kind). (Villages3 changed the rest of this bullet: see section 9.)
- The alpha path ribbon of a building's yard gives way where paint already runs out of its door
  (`StructureDoorPaint`); a street's lots are not structures, so it matters after a split.
- Still to do from this section: the yard surface, bridges (3e second bullet), boundary walls and fields, the
  Village tool, and the dressing following house moves after a split.

## 9. Phase 2, second slice as built (topic villages3, 2026-10-31)

Two owner decisions after the villages2 look: "Clear removes only the paint Dress laid" and "widen roads by
about a third". Details and numbers in `docs/systems/settlements.md` "Ground".

- The settlement record now carries `ground`, the compact list of paint strokes its Dress laid (up to 256
  capsules, 4 surfaces, a hundredth of a metre; validated, serialized like plazas, left out when empty, round
  trip byte for byte, hostile input skips the record). It is what turns the paint from "the map's now" into
  something the village can take back.
- Clear takes the record's strokes back with the record (one history entry, undo restores both); a re-dress,
  a change of character and `pave` take the previous strokes back and lay the new plan in one entry, so the
  road follows street edits made since. Ground painted by hand is never in the list and is left alone. The
  removal replays the list on a scratch grid through the Paint tool's own code and subtracts what it left,
  so a Dress then Clear restores the weights byte for byte (`SettlementUnpaint`); the cost of a take-back is
  about that of laying (settlements.md "Ground", PERFORMANCE.md "Settlement ground").
- The road is a third wider: `0.77 x setback` a side clamped to 1.2 to 3.2 m (2.31 m at the default setback,
  was 1.74 m).
- Still open: where two dressed streets cross, taking one back thins the other at the crossing; the Village
  tool (built in section 10); a paint stroke alone does not rebuild a building's yard.

## 10. The Village tool, plazas and character (topic villagetool, 2026-10-31)

Owner decision 2026-10-31: the next slice is the Village tool UI, "drag out a plaza, pick the kit and ground;
makes the new ground usable by authors". Built as the design's section 3d.3 intended, scoped to plazas and the
character pick. No bridges, walls, fields or touchable props. No new live-edit op kind, no format change.

**A rail tool of its own** (`VillageTool`, `scenes/states/authoring/tools/village_tool.gd`, rail icon `village`,
authoring only, no shortcut like its neighbours; disabled on a Blender map as Wall is). The Wall tool's picked-street
bar keeps "Dress this street"; the Village tool is where a village is edited once it exists. The code and UI taste
favoured a rail item over growing the street bar: a plaza is not a property of one street, the street bar only
shows while a street is picked, and the Wall pane is already the longest.

**Gestures** (`VillageBrush`, a `BrushMode`; pure rules in `VillagePlazas`, `utils/village_plazas.gd`):

- Click bare ground: a plaza of `DEFAULT_RADIUS_M` (5 m) opens there. Drag from bare ground: the radius is how far
  the pointer goes from the centre (2 to 16 m, tenths; a drag under 1.5 m is a click). The release is the edit.
  A kit can raise the tool's floor (`VillagePlazas.KIT_MIN_RADIUS_M`; the record still takes anything): the market
  town's is 6 m, since its stalls line a plaza's edge every 7 m and at 5 m hide the cobble (villagetool2 capture
  `j_market_5_6_7`: 5 m overstuffed, 6 m reads paved round the well, 7 m roomy). A market click lays 6 m; a rim grab
  never pushes a plaza already under the floor up.
- Drag a plaza's rim (a band of 12 px, at least 0.9 m, each side of the edge, or within 22 px of one of its four
  handle dots, the S6 44 px target): the rim follows the pointer without jumping where it was grabbed. Click inside a plaza: picks it; press inside and drag past the 1.5 m click threshold (topic
  plazamove, 2026-11-01): MOVES it (below). Delete or Backspace over a plaza (the Structure
  tool's `decide` table, `picks`/`has_target`) removes it; the pane's Remove does the same for the picked plaza;
  `[` `]` and Shift+wheel over a plaza step it a metre (one history entry each); Escape drops a held gesture, then
  lets go of the picked plaza; right click puts the brush down as everywhere.
- Which village a press joins: the nearest within 60 m of its street line or a plaza edge, the picked one keeping
  the press while it is at most 6 m farther than the nearest. Until the author picks a village (a press, a plaza
  click, the pane's village row) the picked one follows the pointer, as the village a press there would join, so the
  pane, the ghost and its hint name the same village (round 1's captures showed the pane on the first village while the
  ghost's hint named the other: a real disagreement, `test_the_pane_and_the_ghost_name_one_village_and_a_pick_stays`).
  An author's pick stays; the ghost over another village's ground then names that village ("Click for a plaza in
  village 1") and a press there moves the pick. No village in reach, or four plazas already: a toast says so (`NO_VILLAGE`, `FULL`), nothing is
  laid. A plaza refused for wet or steep ground is still recorded and furnished, as `add_plaza` always did (the
  paving is skipped and counted in `last_ground["refused"]`).
- While a gesture is held the ring is a preview and nothing is repaved; the release repaves once. (A repave
  mid-drag would cost the 30 to 70 ms the villages2 numbers give per lay on every pointer step.)
- **Moving a plaza** (topic plazamove). A press in a plaza's interior (the rim band and the handle dots keep
  sizing: `VillagePlazas.pick` gives the rim priority, and the dots are the 44 px target) is a pick until the pointer
  is `DRAG_MIN_M` (1.5 m) from where it landed, then a move (`GESTURE_MOVE`); once begun it stays a move. The disc
  keeps its place under the pointer (`grab_offset`, `moved_to`, tenths of a metre), so it never jumps to the pointer.
  Escape or right click drops it. The place is judged every frame it changes (`VillagePlazas.move_problem`, map
  facts built once at the start of the move): no village in reach (the 60 m rule, measured with the plaza itself
  taken out of its village: `destination_village`), a full village it would join, water, ground too steep across
  it (`SettlementGround.plaza_problem`, the same rule that decides whether a plaza is paved) or a house
  (`VillageFieldGround.covers_building`, with its 0.75 m grace) refuse it; the disc turns salmon, the pill says why
  ("Too wet: needs dry ground", "Too steep: needs level ground", "Over a building: put it on open ground", "Too
  far from the village", "Four plazas already"), and the release changes nothing: the plaza stays where it was and
  a toast gives the long wording. A plaza carried back to where it began is never refused. The village it belongs
  to afterwards is `destination_village`'s: its own while it is at most 6 m (`PICKED_SLACK_M`) farther than the
  nearest, else the nearer village (the pill then says "Release to move it to village 2"). Fields are not movable
  yet (their press still only picks).

**The edits** are `SettlementEditor.add_plaza`, `resize_plaza`, `remove_plaza` and `move_plaza`, each one history group (the paving
and the record undo together), reaching peers as the ordinary `surface` ops and one `settlements` op
(`test_a_peer_ends_level_through_add_resize_remove_and_their_undos`). Resize and remove take back exactly the
plaza's own paving stroke (settlements.md "Ground"); that is the one change to the editor, plus `_replace`'s
`drop` argument. `move_plaza` adds no op kind: inside its own village it is one `_replace` (the old stroke
dropped, the new disc paved, the record's plaza replaced in place; the furnishings are derived from the record, so
they stand at the new place), and between villages it is a `remove_plaza` and an `add_plaza` in one group
(`AuthoringHistory.is_grouping`, so `_replace` joins the open group instead of opening its own). It refuses what
`VillagePlazas.move_problem` refuses, with `last_refusal` one of `REFUSED_REACH`, `FULL`, `WATER`, `STEEP`,
`BUILDING`. Tests: `tests/unit/test_village_plaza_move.gd` (pure rules, the editor, the peer for a move inside a
village and between two, the brush).

**Feedback** (`VillageRings`, round 2 topic villagetool2). Every plaza of the map is a soft ring on the ground (a glow,
a dark keyline and a bright line over a faint fill) in four weights that keep the states apart: the ghost a thin
chalk line (0.55 of the brush cursor's widths) over a disc of the kit's paving colour at half opacity (the plaza
surface's average, lifted toward white, `VillageSwatch.paving_color`); a calm plaza quiet paper (0.9); the picked one
the Wall tool's gold (1.35) with handle dots of 5.5 px; the one under the pointer heavier still (1.75) with 8 px dots.
While a drag sizes a plaza its disc is a flat tint of the kit's paving at the new radius (no repave until the
release) and the pane's size reads the same width live (the mode's signature carries the preview radius;
`VillagePlazas.with_preview`). A pill says what a press does ("Click for a plaza, or drag to size it", with two or more
villages "Click for a plaza in village 2, ...", "Drag the edge to size this plaza", over a plaza's interior "Drag to
move this plaza, click to pick it" (plazamove), over the picked one "Drag to move it, drag the edge to size it", "Plaza  33 ft
across" while sizing, "Release to put it here" (or "... to move it to village 2") while a plaza is carried, a
refusal in salmon). A carried plaza is a paving-tint disc in the picked gold with its handle dots, the place it left
a calm ring at full ink, and over a refused place a disc washed in the erase salmon (0.28) inside the erase ring's
5.5 px ink-backed stroke (plazamove fix round: the paving-grey fill turned bright grass chalky olive, so the carried
disc and the ghost now share one warm wash, `WASH_TINT` pulled 0.7 over the kit's paving at 0.2 to 0.24 alpha; the
handle dots carry an ink outline; the ghost is a dot and a pill, never a disc, where it would cross a standing plaza,
`VillagePlazas.overlaps_any`); the pane's caption reads "Drag a plaza to move it, drag its edge to size it."; a field's pill keeps its old words ("Drag the edge to size it,
Delete removes it"). The ghost's pill sits just past the ghost's right rim so it never covers it. With two or more
villages each street carries a glass chip with its name ("Village 2", gold when picked) at its middle
(`VillagePlazas.anchor_of`).

**The pane** (`VillageToolPane`): one line for the gesture, then, when two or more villages exist, a row naming them
("Village 1", "Village 2": one word, the board's chips' and the hint's), the primary choice; under it that village's
character ("Character of village 2"), five tiles (the modern town's since topic moderntown) on one line, the name
breaking between its words under a 24 px picture (`TileRow.wrap_labels`; the 2x2 rows beside-the-picture of round 4
took a third row with the fifth and passed the 720 budget, 622 px against 589; now 588), each a small painted
vignette of the kit's plaza (`VillageSwatch`, generated in code: the kit's plaza paving as a disc on a ground colour
of its own, meadow green, warm ochre, harbour blue, heather slate, cool mint, with a well, a striped stall, barrels, a
lamp or a red phone box; the tooltip names the road and plaza surfaces in
plain words); then the plazas: a body line saying how many more the village can hold ("Room for 3 more
plazas", "Four plazas: the village is full"; short so it never meets the pane's edge, and it wraps), and for the picked plaza (or the one a drag is sizing) one row with the size slider (shown as the width
across in the level's units; keys reach it) and Remove. With no plaza picked the row is gone (no disabled boxes) and a
caption says to click one. With no village it says to dress a street with the Wall tool first. At 1280x720 the whole
pane fits without scrolling (capture `k_720_pane`). A character tile calls
`SettlementEditor.set_kit`: the road, door paths, plaza and furnishings follow in one entry (villages3's take-back
and lay), so "pick the kit and ground" is one gesture. The pane reads the document through
`VillagePlazas.state_of` whenever the mode says the view changed (a signature of the villages, plazas and the pick,
compared each frame), so undo and redo keep it right.

**Tests:** `tests/unit/test_village_tool.gd` (pure rules, the swatch, resize and remove with their paint, the peer,
the brush's gestures on a `BrushTool`, the pane). Render job `jobs/villagetool_look.json`.

**Limits left:** a plaza is a disc (it moves since plazamove, but a field does not yet); no polygons; the paving of a plaza resized while its door paths overlap is laid on top of them
(newest paint wins), so a door path ends at the plaza's new edge; gardens, fields, props, bridges and walls are
not in this tool; a village's feel sliders are still on the Wall tool's street bar; keyboard reach of the tiles is
as every tile row (mouse; the slider and Remove take focus); a plaza only joins a village that has a street or a
frozen frontage in reach. Round 2 left: a picked plaza can sit under the left pane (no pan to clear it: the world
renders in a scaled SubViewport and the brush holds no camera controller, so a framing pan needs plumbing of its own);
until the author picks a village the pane follows the pointer, so crossing another village's ground on the way to the
pane moves it (its chip on the board shows which); the paving colours of the four kits are close (pale sands and
greys), so the ghost's tint says "paved here" more than which kit; only the market town's floor was measured (the
harbour town's quay stalls may want one too).

## 11. Phase 3, first slice as built (topic fields, 2026-10-31)

A village's edge is no longer bare grass: the Village tool lays FIELDS as it lays plazas. Decided in the card (owner
away): discs, up to 4 per village, three kinds, no polygons, no move, no bridges, walls or touchable props.

- **Record:** `Settlement.fields`, discs `{at, radius 2.5..18 m, kind}`; saved, validated and round-tripped like
  plazas (settlements.md "The record"), left out when empty, so a map without fields saves byte for byte as before.
- **Kinds** (`VillageFields`, `utils/village_fields.gd`, pure): crops (round 5, `VillageCrops`: a disc of light warm
  earth, `dirt_opening`, standing rows of real plants from the core library in one of four tones, see "Round 5"
  below; a scarecrow, a haystack on two fields in three, a hedgerow); orchard (warm `grass_meadow` with fruit trees, the grassland meadow's broadleaf and oaks at
  0.42..0.55 scale, on a loose quincunx 3.4 m apart turned by the seed, bee skeps by some); garden (a small `grass_meadow`
  disc with two or three earth beds, one flower per bed in lavender or bloom mounds, one or two flowering shrubs at
  the rim). A kit decides the kinds and its default (`KIT_KINDS`): farming hamlet crops, orchard, garden; market
  town garden, orchard; hill fort garden, crops; harbour town none; modern town garden, orchard (flower beds and
  allotment orchards, never ploughland).
- **Paint** goes into the record's `ground` (role `field`, first in `SettlementGround.PAINT_ORDER`, so a road
  laid later runs over a field); `SettlementGroundIO.MAX_SURFACES` went from 4 to 8 to hold the field surfaces.
  Because the strokes follow from the record and the seed, a resize or a removal finds exactly a field's strokes
  (`VillageFields.stroke_indices`) and takes them back through `_replace`'s `drops` (was one `drop`); a re-dress
  and a change of character replan the fields with everything else. Clear and undo need nothing new.
- **Furnishings** are derived: props through `SettlementPlan.place` (slots `f<k>:scarecrow`, removable), plants
  through `AuthoredFieldPlants` (`scenes/terrain/authored_field_plants.gd`, the scatter's own `build_scatter`, one
  MultiMesh per species), refreshed with the settlement layer, play time included.
- **Editor:** `SettlementEditor.add_field`, `resize_field`, `remove_field`, one history group each, peers through
  the existing `surface` and `settlements` ops (`test_village_fields.gd`).
- **Tool and pane:** one "Lay out" row of four picture tiles above the character (round 2; moved up in round 4): Plaza, pictured by the
  village's own plaza vignette (`VillageSwatch.kit_texture`), then Crops, Orchard and Garden
  (`VillageSwatch.field_texture`); the kit's default kind is lit when a field is laid. A kind the character does
  not keep is greyed, and the row's caption line says so in words (`VillageToolPane.missing_note`: "Market town
  keeps no crops", "Harbour town keeps no fields"), not only in a tooltip. The tool's summary names plazas and
  fields; the hint line under it says the gesture for what is picked ("... to lay a crop field."). The brush picks
  plazas and fields alike (`VillageFields.pick_any`, `selected_group`), the ghost takes the kind's tint
  (`KIND_TINTS`) and default size, the pills name the field.
- **Look (job `fields_look`, two rounds):** where a field lay on the board, the green rows on brown earth read as a
  ploughed field in bold soft stripes, the scarecrow and haystack read well; but the job's map is 62.5 m across and
  the fields sat in the board's fog margin, so the home-zoom read is NOT verified. Round 3 (320 ft map, the format's
  64-cell limit; villages on short streets with fields past their ends): the pane fits at 1280x720 with the room line
  and size row in view (`f_720_pane`, `h_720_pane_market`). The board does NOT pass: inside a crop field's picked
  ring there is meadow grass, flowers and a scarecrow but no tilled earth or rows (`f_720_pane`, `d_ghost_crops`), at
  home zoom no field reads apart from the biome's own yellow flower patches (`a_home_fields`), and the garden's ring
  sits over a market building with a patch of earth and flower beds beside it rather than under it
  (`h_720_pane_market`).
- **Round 3 (fields3): the diagnosis.** A headless probe of the painted weights after `add_field` (crops at
  (6, -14) r 6 on a 61 m map) found the paint exactly under the ring (earth 245, rows 253 inside; 0 at every
  mirrored point and 3 m past the rim), and the scatter sampler open at 1.0 for every role over it: the field was
  hidden under the wild cover, not misplaced. A second cause showed in the game: the scatter's workers read a
  document snapshot (`ScatterRegen.snapshot`, `RockKeep.snapshot`) that copied walls and structures but not
  settlements. The "garden beside its ring" was the ring drawn over a market roof standing in front of it (a
  roof hides the ground behind it; the footprint test finds no overlap).
- **Plants** (`VillageFieldGround`, `utils/village_field_ground.gd`, pure): each field clears the scatter under it
  as a structure's footprint does, as strips across the disc 2 m apart given to ScatterGround and the native
  scatter as plank-like Crossings (no native change). They stop 0.5 m inside the rim and the clearance's soft edge
  does the rest. Every kind clears all wild roles, rocks included: crops are bare tilled earth and rows, a garden's
  beds and lawn are clear, and an orchard keeps its painted meadow and its own trees (AuthoredFieldPlants is not
  scatter) with no wild flower or bush under them; the orchard's grass is therefore the painted surface, not grass
  plants. The strips run east-west whatever the seed. A settlement edit asks the scatter to regrow the changed
  fields' ground (`area_of`, through `apply_list`'s area, so undo, redo and peers regrow too).
- **Buildings:** a field may not cover a building, a structure's footprint or a street's house
  (`WallGeometry.row_lots`), by more than 0.75 m (`covers_building`). `add_field` refuses it and a resize that
  grows into one (`SettlementEditor.REFUSED_BUILDING`, toast "A field cannot cover a building: lay it on open
  ground."); the ghost shows the refusal marker and the salmon pill "Over a building" when a click's disc would
  cover one, while a press there may still drag a field down to the kind's smallest size. Refused, not trimmed: a
  trimmed disc would need a shape the record does not have.
- **Look, round 3** (job `fields_look`, captures in `render_jobs/fields_look`): at close zoom the crop fields read as
  ploughed fields, broad dark furrows and pale gold rows inside their rings with a scarecrow and haystack and no
  wild plant on them (`b_close_crops`, `g_close_crops_redressed`, the rows turned by the re-dress); the orchard is a
  grove of seven small trees on cleared meadow (`c_close_orchard`); the refusal pill shows by a house
  (`d_ghost_crops`). At home zoom (`a_home_fields`) the fields read as striped shapes but small, half hidden behind
  the hamlet's houses in this layout, and the biome's yellow patches and bushes still carry the board: not yet the
  bold read wanted. The gold rows read more as straw than wheat, and an orchard's painted meadow is close in colour
  to the meadow round it.
- **Round 4 (fields4): the home-zoom read.** Two different mechanisms were probed on the same hamlet at home zoom
  (job `fields_look`, captures `a0_home_plain`, `a1_home_hedge`, `a2_home_fringe`, `a3_home_both`): (1) a field
  silhouette, a HEDGEROW of meadow bushes round each crop field just past its rim (`VillageFields.hedge_of`, plants
  through AuthoredFieldPlants, a gate gap where the haystack stands); (2) a calm fringe, the field's clearance and a
  meadow paint disc reaching 3 m past the rim. The hedge made each field an enclosed parcel, the boldest shape on the
  board; the fringe changed nothing that reads (the meadow's yellow patches are ground paint, which a plant clearance
  cannot touch, and the cleared margin vanished into the green). The hedge was kept for crops (`HEDGE_KINDS`), the
  fringe dropped. Placement mattered as much: fields past a street's far end sit behind its roofs from the board's
  camera, so the job now lays them where an author would and the camera sees them (the street's near end, beside the
  last houses). The orchard got mown green alleys between its tree rows (`ALLEY`, painted) and pink bloom mounds round
  each trunk past the canopy (`BLOSSOM`), so it reads as tended rows rather than a grove; the garden got broad beds
  (1 m, 2.8 m apart) each one mass of a single flower in two staggered lines, two or three shrubs, and a 5.5 m default
  (4.5 was a speck at home zoom). Verdict (`a_home_fields`, `c_close_orchard`, `c2_close_garden`, `--full`): crops pass
  at home zoom; the orchard is a modest pass (core has no fruit-tree species: the trees are slender meadow oaks); the
  garden is a small, distinct planted plot. The biome's yellow paint patches still carry much of the board.
- **Round 4, the pane and rings** (UI critic findings): the field ghost, the calm rings and the refused disc take the
  brush ring's own stroke (`BrushCursor.ring_strokes`: ink under the tint, at full weight; the ghost was a pale 1-2 px
  hairline about 1.2:1 over grass), and a click that would cover a house draws its refused disc in salmon. The pane
  puts "Lay out" (was "Lay") above the character in its largest tiles (76x96, 58 px pictures) and the character in a
  compact 2x2 row (picture beside the name); the "keeps no crops" reason sits on its own line under the tiles and the
  greyed tile's tooltip says the same; the greyed label is the theme's solid disabled role (TEXT_SOFT, over 4.5:1 on
  glass, `test_a_greyed_kind_reads_in_the_solid_disabled_role`); the room line is caption weight; no-break spaces keep
  "a crop field." whole on the hint's last line; the refusal pill reads "Over a building: lay it on open ground". At
  1280x720 (content scale 1.4, a 771 px canvas) the pane is 508 px from y 122 with two villages; three villages and a
  wrapped harbour note measure 534 px, inside the 589 px that leaves 60 px of slack
  (`test_the_pane_fits_720_with_three_villages_and_a_wrapped_note`). World labels under the pane are not hidden.
- **Round 5 (fields5): the crop look.** The user judged round 4's crops bad: dark `dirt_peat` furrows under pale
  gold rows "read more like a striped chocolate desert". Three genuinely different looks were built behind a switch
  (`VillageCrops.look`, never saved or sent) and compared at home zoom in one sheet (job `fields_crops`,
  `sheet_crops.png`, three neighbouring crop fields): (A) rows, broad soft crop rows over light earth with narrow
  furrows, one tone per field; (B) patchwork, three broad strips of different tones per field with a faint row hint;
  (C) plants, rows of real plants standing on the earth. A read as tan sand discs (thin painted rows lose to the light
  earth; ripe gold on tan is invisible); B as washed-out strips of lawn and sand; C as farmland, and won. C's four
  tones (`VillageCrops.TONES`): barley (meadow tall grass on the earth), young (the same grass on a `grass_alpine`
  disc), buckwheat (daisies in rows on `grass_alpine`) and ripe wheat (the savanna's golden tall grass), rows 1.15 m
  apart with a plant every 0.55 m at 1.3..1.7 scale (about 250 plants for an 8 m field, one MultiMesh per species
  through AuthoredFieldPlants). Neighbouring fields take different tones: the tone is the field centre's cell on a
  16 m lattice coloured (x + 2 z) mod 4, so cells touching on a side or corner differ, shifted by the seed so a
  re-dress repaints the quilt. Verdict (`plants_home`, `--full`): golden wheat, white flowering buckwheat and a young
  yellow-green crop, each hedged, read as a quilt of farmland. The ripe field is close in hue to the biome's yellow
  paint patches and out-reads them only by its rows and hedge; the young field is close to the meadow green.
- **Limits left:** taking back a field that overlaps a road or path thins that paint (as for plazas); the plants'
  wind materials are not registered with the level's wind re-tuning; plants stand again only on a settlement
  refresh (a sculpt under an orchard leaves them floating until the next edit); fields refused for wet or steep
  ground are recorded and furnished but unpainted (their wild plants are still cleared); a building placed later
  over a field is not refused (the field stays under it).

## 12. Phase 3, second slice as built: bridges (topic bridges, 2026-10-31)

Where a dressed street crosses water, its Dress lays a bridge so the street continues over it (section 3e, third
bullet). Decided in the card (owner away; for the board): the bridge is laid BY Dress, in the same history group as
the props, the record and the road paint, not offered as a suggestion chip. A chip is a second gesture an author can
miss, leaving a street that runs into a river; in Dress's own entry one Undo or Clear takes the bridge back with the
rest, and a peer receives it as the ordinary `crossings` op inside the group (no new op kind, no new record type).

- **Detection** (`VillageBridges.wet_runs`, `utils/village_bridges.gd`, pure over a wet predicate): the street
  polyline is sampled every 0.25 m along its arc against `WaterGeometry.is_wet_at`; wet samples across a dry gap under
  0.8 m join one run (a sandbar), a run needs at least 1 m of wet street (a puddle gets nothing) and dry street on both
  sides (a street that ends in a pond gets nothing). One bridge per run.
- **Placement:** each run is planned by the Bridge tool's own `CrossingPlacement.place`, drawn along the street's chord
  from the last dry sample before the water to the first after it, so the deck lines up with the street and its
  anchors snap to the real banks exactly as a drawn bridge's do; it follows later sculpts and water edits like any
  crossing. The width is the painted road's full width held to the kind's range (3 m for planks and arches at the
  default setback, 4 m for a ford). The road paint already stops at the water (`SettlementGround` refuses wet
  samples), so nothing paints on water.
- **Kind by character** (`kinds_for`): planks for a farming hamlet and a harbour town, a stone arch for a market town,
  a hill fort and a modern town (the only built span there is), a ford first for a poor street (wealth under 0.25) where the water is wadeable. Each falls back to
  the next (a ford over deep water becomes the kit's bridge, an arch that will not stand becomes planks).
- **Record:** `Settlement.bridges`, the ids of the crossings the last Dress laid (up to 8, ids 1..255, saved as a list,
  left out when empty, hostile input skips the record). Clear, a re-dress, a change of character and `pave` take back
  exactly those (`CrossingEditor.swap`: one crossings entry, the old ids reused, nothing recorded when the list comes
  out the same, so a re-dress over the same water keeps its bridge) and never a crossing placed by hand. A run already
  crossed by a crossing the village did not lay is left to it (`covered`).
- **Refusals** are a toast, never a refused Dress (`SettlementBarLink.tell_bridges`, the street bar's Dress and
  character, the Village tool's character tiles): a map already holding 64 crossings, a span over 24 m, a waterfall
  within reach, no dry bank (`VillageBridges.refusal_text`).
- **Tests:** `tests/unit/test_village_bridges.gd` (the runs, kind and width, one entry with undo and redo, Clear leaves
  a hand bridge, a change of character swaps the kind under the same id and a re-dress keeps it, a poor lane fords, a
  full map toasts, the record round trip and hostile input, a live-edit peer through dress, character, Clear and the
  undos); `tests/unit/test_village_dry_ground.gd` (the lot filter leaves a gap, a lot's sample grid meets a narrow
  stream, the corridors, a prop's ring at the water's edge, a dry map's street is exactly its plan and keeps its key,
  a street over a river stands lots on both banks and builds nothing on the water). Render job
  `jobs/bridges_look.json` (before: dressed with `bridges: false`; after: `pave` with the same seeds).
- **Houses stand on dry ground** (`utils/village_dry_ground.gd`, `VillageDryGround`, round 2). procgen's
  `ProcgenRow.plan` knows nothing of water, so tt-sim filters its lots: `WallGeometry.row_plan` is every lot the
  recipe builds, and `WallGeometry.row_lots` (the preview, the scatter clearing, the frontages and so the props, the
  fields' refusal, Split) is the ones that stand. A lot is dropped when any sample of its building (a grid at most
  1 m apart over its rectangle grown by 1 m: eaves and a strip of bank) or of its yard's plot is wet, or when a
  sample of its building lies in the street's crossing corridor (each wet run of the street, the bridge's width
  plus 0.5 m a side, reaching 2 m past each bank). Lots stay derived, never stored, and the filter runs after the
  plan, so it changes no draw: the same seed gives the same houses minus the dropped ones, and a dropped lot leaves
  a gap, never a reshuffle. The built street is the recipe's, which builds every lot, so `build_one` takes the
  dropped lots' triangles out by provenance path ("left/lot3"), their collision faces by where they stand.
  `key_of` adds the standing lots' paths on a map with water (water under a lot, not under the line, moves them).
  A map with no water body takes none of this: `row_lots` returns the plan itself and the key its old fields.
- **Props stand clear of water and bridges** (`AuthoredSettlements._stand`): a prop is dropped when its centre or
  a ring at its drawn radius plus 0.5 m is wet (`VillageDryGround.prop_ring`), or when it stands within 1 m of a
  crossing's deck or 3 m past an anchor (`crossing_corridors`, every crossing, a hand-placed one too); the plan
  cache keys on the crossings, so a bridge laid or moved stands the props again.
- **Look** (`render_jobs/bridges_look3`, `--full`, streets z -24..24): at home zoom the stream reads across both
  villages; the hamlet's plank bridge is a clear shape between houses on both banks, each back from the water on a
  grass strip (`b_home_after`, `c_close_hamlet`). The town's stone arch stands bank to bank (`f_town_open`) but at
  home zoom is hidden by the south-bank house on the camera side of its landing and a scatter tree.
- **Limits left:** a house beside a landing on the camera's side can hide a bridge at home zoom (a bridgehead
  clearance would cost a riverside street most of its houses on a short street); a street moved after its Dress keeps its bridges where they
  were until the next re-dress or `pave`; a bridge the author erases by hand returns with the next re-dress; a bridge
  laid by a village that a later water edit removed leaves its id in the record (harmless: a take-back skips ids the
  document no longer holds, and a hand crossing that reuses the id over the same street would be taken back with it).

## 13. Phase 3, third slice as built: boundary walls and gates (topic bounds, 2026-10-31)

A village can have a boundary: a low stone wall or a hedge round its edge with gates where its street leaves, so it
reads as one place at home zoom (section 3e, last bullet). Decided in the card (owner away; for the board): the
Dress draws it from the character and the seed, no `village_edge` kit rule. User verdict 2026-11-01: ship that AND a
pane switch, so the author can override it per village (see "The pane switch" below).

- **Record:** `Settlement.boundary`, "" (none), `wall`, `low_wall` or `hedge`; saved as a name, left out when "", a
  hostile value skips the record. Only the kind is stored; everything else is derived on every peer, so a Dress,
  Clear, Undo and a peer need nothing new (the `settlements` op carries it). A village dressed before this slice has
  none until its next re-dress or change of character.
- **Kind by character** (`VillageBoundary.kind_for`, `KIT_RULES`): a hill fort village always a stone wall (1.0 m,
  gate piers 1.55 m); a market town a low stone wall (0.75 m, piers 1.2 m) on two seeds in three; a farming hamlet a
  hedge on one seed in two; a harbour town and a modern town (kerbs and front gardens, no ring wall) none. A re-dress draws again (no sameness).
- **The pane switch** (2026-11-01; a dropdown first, rebuilt as tiles after the UI critic's FAIL: an OptionButton had
  no visible edge and no sibling row uses one): a `TileField` under the Village pane's character tiles, captioned
  "Boundary of village N" (just "Boundary" with one village) like its sibling rows, five text tiles in one row: Auto
  (the kit's own pick and the default; the caption line's note names it, "Auto: hedge", and the tile's tooltip says it
  in full), None, Hedge, Low wall, Wall (`VillageToolPane.BOUNDARY_CHOICES`, `boundary_picked`, each tile with a
  tooltip; a tile is 60 x 40). To keep the pane in the 720p budget the hint became one line and the Lay out and
  character tiles 4 px shorter each. A choice is one
  `SettlementEditor` call and one history entry "Village boundary" (`VillageTool.apply_boundary`): `set_boundary`
  for None and the kinds, `auto_boundary` for Automatic. "Automatic" needs to be told apart from an author's None
  (both are `boundary == ""` on a harbour town), so the record carries `Settlement.boundary_manual`: true once the
  author picked (saved as `"boundary_manual": true`, left out when false, a non-flag skips the record). While it is
  set a re-dress and a change of character keep `boundary`; `auto_boundary` clears it and draws the kit's kind again
  (`kind_for`), so Automatic restores exactly the kit-driven result, including its seed draw. `VillagePlazas.state_of`
  carries `boundary`, `boundary_manual` and `boundary_auto` for the pane. The row fits the 720p budget
  (`test_the_pane_fits_720_with_three_villages_and_a_wrapped_note`; 533 px tall at full size with three villages,
  `bounds_pane`); `test_the_boundary_tiles_share_one_row_with_their_labels_whole` keeps the five on one line.
- **The line** (`VillageBoundary`, `utils/village_boundary.gd`, pure): the convex hull of the street's standing lots
  (yards included), the street widened 1 m past its road (so a one-sided street still has a line beyond its road)
  and the plazas, grown 2 m with rounded corners and sampled every 0.5 m. Fields are not in the hull.
- **The gaps:** a sample within a street's road plus 0.8 m a side is a GATE (the village's own street is taken 14 m
  past both ends, so its two ends are always gates; another street through the line gets one too); a sample is
  BLOCKED when wet (`VillageDryGround.wet_flags`), within 0.5 m of a crossing's corridor (its deck and landings), within
  1.6 m of one of the village's fields' rims (past their hedgerow) or within 0.8 m of any building (structures and
  every street's houses). Runs under 2 m are dropped. A gate has a pier either side; a blocked gap has none.
- **Stone:** each run is simplified (0.08 m) and cut into lines of at most 40 m, built as transient `Wall` records
  (never in `MapDocument.walls`, so `MAX_WALLS` 64 is untouched) through `WallGeometry.build_one`, the procgen stone
  wall recipe, and merged into one node per village under `AuthoredBoundaries` (`scenes/terrain/authored_boundaries.gd`,
  an `AuthoredWalls`), its masonry in the street lots' warm painterly material (the yards' walls' look). No collision:
  walk-through like the furnishings. It rebuilds when the walls or the ground under them move (`WallGeometry.key_of`).
- **Hedge:** the fields' hedgerow bushes (`VillageFields.HEDGE_SHRUBS`) every 1 m along each run at 0.9..1.2 scale,
  through `AuthoredFieldPlants`.
- **Scatter:** the scatter clears a strip under each run (`VillageBoundary.clearance_crossings`, inside
  `VillageFieldGround.clearance_crossings`, so the GDScript and native scatter both take it); a settlement edit that
  changes a bounded village regrows round its street (`VillageBoundary.area_of`, merged into the op's area).
- **Tests:** `tests/unit/test_village_boundary.gd` (the ring round a hull, a one-sided street, gates at the street's
  ends with four piers, water, a house and a field breaking the line without piers, stubs dropped, the kind by
  character, a hill fort Dress with Undo, redo and Clear, a hedged hamlet, a river village with no wall on the water,
  the round trip and hostile input, a village dressed without a boundary saving and clearing as before, the pane's five
  choices and what Automatic names, a pane choice reaching the village, Automatic restoring the kit's kind, a re-dress
  keeping an author's None, one undo entry per choice). Render jobs `jobs/bounds_look.json` and
  `jobs/bounds_pane.json` (the pane at 720p, a Hedge and a Wall chosen from the pane's path).
- **Look** (`render_jobs/bounds_look`, two rounds, `--full` for the verdict): round 1's 0.6 m low wall was a hairline
  at home zoom; at 0.75 m it reads. At home zoom (`b_home_after` beside `a_home_before`) each village reads as one
  place: the hamlet wrapped by a dark green hedge band, the market town's low cream wall along its front with a gap at
  its paved road, the hill fort enclosed by a cream wall with rounded corners and a gate at each end. Close
  (`c_close_fort_gate`), warm coursed masonry, the yards' walls' look, with a pier either side of the gate where the
  road leaves. Weak: a town with no yards has its wall 2 m off its facades; a hedge behind the roofs is hidden from the
  board's camera.
- **Limits left:** the hull is convex, so a bent street's boundary encloses the open ground inside the bend; a hand
  drawn wall or fence crossing the line is not a gap; a boundary does not follow a crossing edit until the next
  settlement refresh; a split street (source 0) has no boundary; the plan is derived several times per refresh (the
  layer, the hedge plants, the scatter clearance), each reading every street's lots.

## 14. Phase 3, fourth slice as built: touchable furnishings (topic villages4, 2026-11-02)

The design's section 3d.5, "Props are touchable": the barrels, stalls, benches and lamps a Dress places can be picked,
moved, turned, swapped and taken away in the Village tool. Decided in the card (owner away; for the board): it is the
first undone slice in the design's order (plazas, fields, bridges and boundaries are built; the free-polygon field and
moving a field are refinements of built gestures, the wealth and density sliders already live on the Wall tool's street
bar), and it needs no owner decision (tokens colliding with props, section 6, is not touched: pieces stay walk-through).
No format change and no new live-edit op: the record's `removed`, `swapped` and `pinned` lists (settlements.md "The
record") were saved, validated and applied by `SettlementPlan` since phase 1 and had no gesture.

- **Pick** (`VillageProps`, `scenes/states/authoring/village_props.gd`, owned by `VillageBrush.props`; pure rules in
  `VillageFurnishings`, `utils/village_furnishings.gd`). The pick table is the layer's own standing rows
  (`AuthoredSettlements.standing`, ground applied), so a piece the layer skipped (wet, steep) cannot be picked. A pointer
  is over a piece by where it is DRAWN (the critic's P1, 2026-11-02): the screen distance from the pointer to the piece's
  drawn centre (0.8 of its radius above its foot) within 0.9 of its drawn radius (floor 0.45 m) plus a 10 px pad, the
  nearest in share winning, and NOT when a building stands between the camera and that centre
  (`BrushTool.structure_blocks`, a physics segment against the authored structures AND the wall rows' houses; the pick
  through a roof to a piece behind it is gone, and a carried piece whose pointer is over a building
  (`BrushTool.building_under_pointer`) is refused as "Over a building", since the ground the brush ray reaches through a
  roof is hidden behind it). Without a camera (the unit tests) the ground point under the pointer is used instead.
  A piece beats a plaza's rim band and its interior (the plaza's stalls stand on the rim, so a rim that won would make
  them unpickable); the plaza is still sized from the rim where no piece stands. The
  plaza's centre piece (the well or cross) is NOT touchable (`VillageFurnishings.is_centre_piece`): it stands where the
  plaza's centre does and presses on it move the plaza. A hovered piece is outlined (`VillagePropRings`: the plaza rings' strokes at the piece's
  radius plus 0.2 m, handle-less: chalk under the pointer, the Wall tool's gold when picked) and the plaza under it is
  not highlighted, its ring faded to 0.35 while any piece is hovered or picked. Pill: "Drag to move this piece, click to
  pick it". The hint bar says which keys are live (`VillageTool.key_hints`: Drag Move piece, Q E Turn piece, R Re-roll,
  Del Remove; a field's piece only Del), and returns to the base hints when no piece is hovered or picked.
- **Gestures.** Click picks (Escape lets go). Press and drag past the plaza move's 1.5 m click threshold MOVES it: the
  piece keeps its place under the pointer (`grab_offset`), the place it left is a calm ring, a translucent copy of the
  piece (`AuthoredSettlements.ghost_of`, 0.55 transparent, 0.68 where refused) is carried at the pointer and the REAL
  piece steps out of its baked cell while it is carried (`AuthoredSettlements.hidden`, a slot set the next refresh
  leaves out; the rows still hold it), so only the copy is drawn and the place it left is the calm ring. The carried
  ring is gold ("Release to put it here"), or where `VillageFurnishings.problem` refuses the line tools' erase ring
  (`#FFB6A8`, 3 px (weight 1.2) over its ink outline, no wash, no cross; a picked piece's ring is weight 1.9, a hovered
  neighbour's 1.2, so the pick always outweighs the hover: `VillagePropRings.PICKED_WEIGHT` / `HOVER_WEIGHT`) with the reason on the pill. Rings of pieces are
  BARE (`style["bare"]` in `VillageRings.draw_plaza`: no interior disc), so a ring never dims a barrel or a bench. The
  reasons: water (the layer's ring test), ground steeper than the layer's 0.8 limit, a house
  (`VillageFieldGround.covers_building`), a bridge's deck and landings (`VillageDryGround.crossing_corridors`), more
  than 60 m from the village, inside another piece's clearance (0.6 of the radii), and off its HOME
  (`VillagePieceHome`, topic villages5, owner board VP1, 2026-11-03): a plaza's own piece (`...:p0/...`) stays inside
  that plaza's disc ("Keep it inside the plaza"), a lot's piece on its own lot ("Keep it on its own lot: that piece
  belongs to the house beside it", `OFF_LOT`), a street's piece on its street ("Keep it on its street: that piece
  belongs along the street", `OFF_STREET`), with the same refusal ring. The home is read from the slot name the plan
  gave the piece (a pin keeps its slot, so a moved piece keeps its home): the owner (`p<k>` plaza, `l<k>` lot) and the
  rule's slot kind in the kit. `beside_door`, `side_gap`, `front_yard` and `back_yard` pieces are the lot's;
  `street_edge`, `junction` and `village_edge` pieces are the street's even when procgen names the lot they stand before
  as their owner (a lamp is owned by a lot but belongs to the street). The geometry is the frontage record's: a lot is
  its range of the facade line, the side gap after it included (the frontage gives it to the lot before), from its
  back yard (`depth_m + yard_m`) to the kerb (`gap_m`), with 0.5 m of slack; a street is every side of it, from 0.5 m
  behind the facades across to the facades opposite (twice the setback; a frozen village with no street keeps its
  strip and the narrowest road), 3 m past either end, plus 5 m round each junction point. A piece whose lot is gone
  (a pin after a re-plan) and a field's piece have no home and keep only the 60 m reach. Swap does not ask the home
  (the piece does not move). `test_village_piece_home.gd` checks every planned piece of two kits and two seeds stands
  at home, and a refusal table for the three kinds. The pills draw at 16 px (`VillageProps.PILL_PX`, the body size: the
  shared Caption chip's 14 falls to about 13 at a 720p window). The release pins the piece (`pin_furnishing`); a refused release changes nothing and
  toasts the long wording. Q and E turn the piece under the pointer (else the picked one) 15 degrees, Shift a quarter;
  R shows the next of its four draws (`ProcgenSettlement.VARIANTS`); both pin it. Delete or Backspace (and the pane's
  Remove) takes it away and says so: a toast "Removed barrel" with a "Put back" button that puts that ONE piece back
  (`SettlementEditor.restore_furnishing`, a new history entry, so it still works after newer edits). The toast is tagged
  (`UIManager.show_action_toast(..., tag)`, `UIManager.dismiss_toasts`) and `VillageProps.sync` takes it down once its
  piece is no longer removed (pane Put back, undo, redo, a peer) or its village or removal is gone (a re-dress, a clear).
  Toasts stand on the centre line of the board the open drawers leave free, the hint bar's (`ToastContainer._process`). A field's own scarecrow, haystack or skeps can be picked and removed but not moved, turned or
  swapped (they stand where their field puts them, `VillageFurnishings.is_field_piece`).
- **Swap** (the pane's button). The candidates are the props the kit's rules draw for the same slot kind
  (`street_edge`, `beside_door`, `plaza.edge`, `back_yard` ...), in the kit's order, the piece's own included so it
  cycles: a door's barrel may become a crate, a bench or a cart, a plaza's stall a bench or a lamp. The next one that
  FITS where the piece stands (the same `problem` test with the new prop's radius) is taken; "Nothing else fits here."
  when none does. A piece that is not pinned gets a `swapped` entry; a pinned one has its pin's prop changed. The
  button is disabled with a tooltip when nothing else belongs in that place.
- **Edits** (`SettlementEditor`): `remove_furnishing`, `pin_furnishing`, `swap_furnishing`, `unpin_furnishing`,
  `restore_furnishings`, each ONE history entry ("Remove piece", "Place piece", "Swap piece", "Put piece back", "Put
  pieces back"), reaching peers as the ordinary `settlements` op (`test_village_furnishings.gd`: a peer ends byte for byte
  level through a move, a removal and their undos). The 64-override cap is a refusal ("A village keeps at most 64 ...").
  **Decision for the board:** a re-dress now KEEPS pins (the design's "a pin must survive a re-dress", section 7, which
  the code did not do) and still drops `removed` and `swapped` (they name slots of the old draw); a change of character
  drops everything. A pin that lands on a house of the new draw is the author's choice; Undo is one step.
- **Pane** (`VillageFurnishBox`, inside the plaza box): with a piece picked, a rule and its name ("Barrel", the Heading
  variation, 19 px), then Swap, "Back to its spot" (only when pinned: it returns a moved or turned piece to where the rules put it) and
  Remove; it stands where the size row stands, which only a picked plaza or field uses, so the pane grows no taller.
  Once the picked village has had pieces taken away a "Put back 1 removed piece" / "Put back N removed pieces" button
  brings them all back (the two buttons were both "Put back" until the 2026-11-02 critic); while the pointer is over it a
  ring and a faint copy of each removed piece stand where it would return (`VillageProps.preview_restore`,
  `AuthoredSettlements.rows_if_restored`). The caption names the gesture ("Click a barrel or stall to move or
  swap it").
- **Buttons beside the ring** (`VillagePieceButtons`, topic villages5): the picked piece also shows Swap (only when
  another prop belongs there), Back (only when pinned) and Remove (a field's piece: Remove only) as glass pills at 16 px
  in a row just outside the piece and its ring, the same size on screen at any zoom. The row goes below the piece's
  screen box (its ring and its mesh's bounds), else above, right or left: the first that fits on the board the open
  drawers leave free (`DrawerContainer.free_span`, 64 px kept above the hint bar), slid along that side to fit; when
  none fits it stays on the screen even if it must overlap. Hidden while nothing is picked, while a press is held (a
  carried piece shows its pill instead) and when the tool is put down. The pills are real `Button`s on the cursor's
  overlay (flat, drawing `MapOverlayUtils.draw_chip`, words gold under the pointer), so a click on one is the GUI's:
  `GameMap` gives the brush no press over a control, and the click cannot also move, pick or let go of the piece. They
  call the pane's own actions (`VillageBrush._act`: `props.swap`, `props.unpin`, `props.remove`, so Remove leaves the
  "Removed barrel" toast with Put back).
- **The canopy cut round the picked piece** (topic villages5b): a picked piece clears the bush or crown it stands in,
  trunks and stems included, so it reads at once instead of standing among bare stems (the brush window keeps stems
  by design). `VillageBrush.fade_cut` asks `CanopyFade.set_cut` for a disc at the piece (its carried place while a
  move is held) of `VillageFurnishings.cut_radius` (the drawn radius plus 1 m, at least 1.4 m); the foliage shader's
  `canopy_cut` term clears the ground disc round the piece and the column between it and the camera, leaf cards
  full inside 0.6 of the radius, bark (limbs and trunks) full out to the radius and gone by 1.5 times it, so at the
  soft edge a bush keeps leaves over missing stems rather than stems without leaves. Camera pass only (shadows
  stay), opened and closed over the brush window's 0.15 s and 0.4 s, off with no pick or the tool put down, never in
  play. It replaced holding the brush window open over the piece while the pointer is on its buttons.
- **Limits left:** the tool does not draw per-piece thumbnails; Swap has no chooser (it cycles); a pinned piece does not
  follow its house when the street is edited (a pin is absolute, as the design says); fields still cannot be moved or
  drawn as polygons; the wealth and density sliders are still on the Wall tool's street bar; props stay walk-through.
- **Verification (villages5).** `tests/unit/test_village_piece_home.gd`: `VillagePieceHome` (every planned piece of two
  kits and two seeds stands at home; the refusal table for plaza, lot and street; the refusal reasons `OFF_LOT` and
  `OFF_STREET` are constants of `VillageFurnishings`) and the `VillagePieceButtons` layout, actions and press behaviour.
  `tests/unit/test_canopy_fade.gd`: `CanopyFade.set_cut` / `step_cut` and `BrushMode.fade_cut` with no pick. Not
  covered by a test: `VillageBrush.fade_cut` itself and the shader's cut constants (`CANOPY_CUT_INNER`,
  `CANOPY_CUT_BARK`, `CANOPY_CUT_BEHIND` in `shaders/wind_foliage_include.gdshaderinc`; audit1, 2026-11-03). Render job
  `tools/render_jobs/jobs/villages5_buttons.json` (topic villages5, keeps no level): the pills beside a picked barrel
  and cart, hover, click and the drag-refused states, 14 captures with an `INDEX.md`.
