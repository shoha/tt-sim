# Villages and streets: composing lived-in settlements (design)

Status: DESIGN ONLY (card villages_design, topic `villages_design`, 2026-10-30). No code changed. Nothing
here is built; every "exists" claim cites the code as of tt-sim `4fa55739` and procgen `4b7c5d2`.
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
  takes its own stream (`lot<index>_<side>`), so what it is built of shifts no other lot.
- **Orientation.** Each lot's first side (the front) faces the street, a setback from the line; the gap is at
  least both neighbours' yard margins.
- **Species.** `ProcgenStreetSpecies` (`recipes/species/*.json`, 11 of them) replaces the lot sizes, gaps,
  heights, roofs and yard, and draws walls, roofs, facade styles, trims and chimneys by weight; the six newer
  ones (pueblo, villa, alpine, canal, tudor, minka) draw whole building styles ("bundles") and carry `region`
  tags. **Phase 0 done (batch_c, 2026-10-30):** the Street tool offers all 11. `Wall.ROW_PRESETS` is
  `ProcgenRow.PRESET_MINKA + 1` (11), the pane's tiles, the readout names and the tooltips come from
  `StreetSpeciesInfo` (built from `ProcgenStreetSpecies.NAMES`, only the plain label, icon and tooltip
  are tt-sim's), `MapWallIO` and the live-edit codec take 0 to 10, and `StreetSplit.region_tags` takes
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
   water checks, no prop within 1.5 m of a door's path (`DOOR_CLEAR_M` is 1.5, `structure_dressing.gd:29`),
   one density budget, and a character's palette. A drag past a limit clamps and shows the clamp, never an
   error, as the Building tool does.

### 3e. Paths, ground and bridges

- **Roads and door paths use the existing Paint layer, written at Dress time.** The Dress command paints
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
- **Bridges.** Phase 5: when the street polyline crosses water (`WaterGeometry.is_wet_at`), Dress offers a
  bridge through `CrossingEditor.plan` at the crossing, kind by character (planks for a hamlet, arch for a
  town, ford for a poor lane), as a separate undoable crossing; the street continues over it. The street
  data is untouched. This stays a suggestion chip, since a crossing changes the map's water reading.
- **Boundary walls and gates.** A `village_edge` rule can ask for a wall or hedge line round the settlement
  hull (a closed `Wall` or plantgen hedge) with gates at street ends; it is generated as derived geometry
  (a procgen wall along the hull) in phase 4, not as `Wall` records, to stay under `MAX_WALLS` 64.

### 3f. Collision and tokens

Walls today: a stone wall is a surface to stand on, a fence blocks nothing, and "blocking movement is a game
rule decision still to make" (`walls.md` "Not yet"). Props follow the same line so they add no rule:

- `blocks: none` (default): no collision (lamp post top, signpost, laundry, hedge segment, hay).
- `blocks: stand`: simple upward faces on the terrain layer so a token placed on it does not fall through
  (crate stack, cart bed, bench, well curb, stall counter), derived from tags like `StructureWalkable` does
  (`utils/structure_walkable.gd`); about 6 to 20 faces a prop.
- `blocks: solid`: all faces (well, shrine, cross, market stall posts), still a standing surface, not a rule.

Collision is merged into one `StaticBody3D` per cell (section 4 performance), carries `tt_prop` meta so the
ground tools and the Building tool skip it (as they skip `exclude_of` bodies). Owner call: whether tokens
should be blocked by solid props (section 6).

## 4. Phases

Each phase is independently shippable and ends with the repo gates green. Sizes are ideal working days for
one agent including tests and a render look round.

| Phase | Content | Size | Touches |
|-------|---------|------|---------|
| 0. Reach the species (DONE, batch_c) | Expose the six hidden street species: `Wall.ROW_PRESETS` 5 to 11, `MapWallIO` range, pane tiles (`StreetSpeciesInfo`), readout names, region tags; tests and a render of each; plus the street surfaces the newer species need (`WallGeometry.EXTRA_PART`) | 1 | tt-sim |
| 1. First dressing | `prop` family: 8 props (barrel, crate stack, well, lamp post, bench, hay stack, woodpile, signpost); `ProcgenSettlement` rules v1 with slots `street_edge`, `beside_door`, `back_yard`, `side_gap`; 2 kits (farming hamlet, market town); `Settlement` record, editor, IO, live edit, fingerprint; derived baked cells; **Dress this street** button | 6-8 | procgen, core-library, tt-sim |
| 2. Ground and yards | remaining props 9 to 14; road, door-path and yard paint at Dress time; gate prop in the yard fence; a decor `ground` mount in plantgen (hedge, garden bed); back-yard garden rule | 5-6 | procgen, plantgen, core-library, tt-sim |
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
