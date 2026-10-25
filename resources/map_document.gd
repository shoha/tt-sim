class_name MapDocument
extends RefCounted

## Everything authored in tt-sim for one level: the in-memory form of `map.ttmap`, the
## ZIP document that sits beside `level.json` (and the optional Blender-made `map.glb`)
## in the level folder. MapDocumentIO reads and writes it and owns the file format and
## its caps; this class owns the map geometry and the domain limits the reader enforces.
## Design: docs/superpowers/specs/2026-09-26-in-game-map-authoring-design.md (local,
## gitignored), "The map document"; summary in docs/ARCHITECTURE.md.
##
## Geometry. The map is size_cells.x * cell_size_m by size_cells.y * cell_size_m metres,
## centred on the world origin (X from -W/2 to W/2, Z from -H/2 to H/2), floor at Y = 0.
## Heights, the erase mask and the biome masks all share one sample grid: samples_x() by
## samples_z() samples, row-major with Z rows and X columns, the first sample at the
## (-W/2, -H/2) corner and the last at (W/2, H/2).
##
## sample_spacing_m is the nominal spacing: the sample count per axis is
## round(extent / spacing) + 1, and the grid then spans the extent exactly, so the real
## step is extent / (samples - 1) (sample_step()). The two differ by under half a spacing
## over the whole map (200 ft at 0.25 m: 0.24984 m), and the payoff is that the outermost
## samples sit exactly on the map edges for every cell size, instead of overshooting them.
##
## Instance rows. scatter and props map a palette asset id to that asset's rows, flattened
## into one PackedFloat32Array with ROW_STRIDE floats per row in the
## [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz] Y-up format ScatterGlbUtils already reads.
## Flat packed arrays rather than an Array of row Arrays because this is the form that is
## held for the whole authoring session and edited by brushes: 40 bytes per row against
## several hundred for ten boxed Variants in their own Array, which matters at the
## 1,000,000-row cap, and a brush appends or filters a slice without allocating an object
## per instance. ScatterGlbUtils.build_scatter() takes Array rows, so the load path
## converts once with scatter_groups(); that conversion is transient.
##
## Masks are PackedByteArrays on the sample grid (one byte per sample) rather than
## Images, for the same reason: a brush dab writes bytes by index. MapDocumentIO turns
## them into PNG entries on write. An empty mask means the document has none.
##
## Painted surfaces (format 2). surface_ids names up to MAX_SURFACES palette surfaces; slot
## k is surface_ids[k]. Each sample keeps at most SURFACE_ENTRIES painted surfaces as
## (index, weight) entries: the index is a slot, the weight its coverage 0..255. The
## surface_weights bytes are two planes, each exactly the RGBA8 pixel data of one texture:
## bytes [0, 4n) the index plane (entry e of sample i at 4i + e, surfaces_index.png) and
## [4n, 8n) the weight plane (surfaces_weight.png), for n = sample_count(). Planar so a plane
## goes to Image.create_from_data (and the index ground shader) as a native slice
## (surface_plane()); surface_offset() is the byte of one entry in one plane. Canonical
## entries, which every writer here keeps and the reader restores: weights high to low
## (ties in any order), each index with a weight below surface_ids.size(), no index twice
## in one sample, an unused entry (0, 0), and the weights of one sample summing to at most
## 255. The remainder is automatic ground (rules and biomes), so a painted surface overrides
## it in proportion to its weight. set_surface_weight() keeps all of that; painting a fifth
## surface over a sample drops its weakest entry, whose weight returns to the ground.
## Format 1 stored one channel per slot (8 slots); the reader migrates it
## (entries_from_slots()). The index ground shader (ground layers G3) uploads the two planes
## as they are, so the authoring tools claim up to PAINT_SURFACE_LIMIT (= MAX_SURFACES) slots.
##
## Water. water_bodies holds the rivers and ponds (WaterBody, flat water per body, stable
## ids); pond_mask is one byte per sample naming the pond whose area holds it (0 = none);
## water_flow is the baked map-wide flow map (WaterFlowBaker), RG8 pixel data of
## water_flow_size texels, empty when there is none. One flow map per map because the
## water shader has one flow sampler per level. WaterGeometry derives the wet samples and
## per-sample levels. Summary: docs/systems/water.md (Water model and flow bake).
##
## Crossings. crossings holds the plank bridges and stepping stones (Crossing, stable ids),
## built from their fields alone (CrossingGeometry). Summary: docs/systems/crossings.md.
##
## Fire. fire_mask is the persistent ground fire, one intensity byte per sample (fire.png);
## where flames may stand (not wet, not steep) is derived by FireField, never saved.
##
## The fields are plain vars because authoring mutates one document for a whole session;
## every helper here is pure except the surface_* mutators, which edit the fields.

## The format written while the map uses only the core library. The reader accepts MIN_FORMAT
## up to MAX_FORMAT; 2 stores painted surfaces as entries (see the header), so a format 1 build
## refuses a format 2 document instead of reading it as unpainted. 3 (FORMAT_LIBRARIES) is
## written when the map uses a library other than core: its ids are prefixed
## `<library>__...`, which a build that does not know libraries would take for unknown plants
## and drop on its next save, so an older build refuses the document instead.
const FORMAT := 2
const FORMAT_LIBRARIES := 3
const MAX_FORMAT := 3
const MIN_FORMAT := 1
## Libraries a manifest may name (the registry serves at most this many).
const MAX_LIBRARIES := 16
const ROW_STRIDE := 10
const DEFAULT_SAMPLE_SPACING_M := 0.25

## Domain limits, enforced by MapDocumentIO.parse() on untrusted documents. 64 cells at
## the default 5 ft cell is 320 ft (about 97.5 m) per axis, the largest map a new build may
## make: a larger document fails to parse on any peer that has not raised this limit.
const MIN_SIZE_CELLS := 1
const MAX_SIZE_CELLS := 64
const MIN_CELL_SIZE_M := 0.1
const MAX_CELL_SIZE_M := 10.0
const MIN_SAMPLE_SPACING_M := 0.1
const MAX_SAMPLE_SPACING_M := 1.0
const MIN_TIER_HEIGHT_M := 0.05
const MAX_TIER_HEIGHT_M := 100.0
const MAX_SAMPLES_PER_AXIS := 641
## Heights outside +-this are rejected as corrupt; far beyond any tabletop terrain.
const MAX_ABS_HEIGHT_M := 1000.0
## An erase-mask byte above this marks the sample erased.
const ERASE_THRESHOLD := 127
## Biome slots are one byte with 0 meaning none, so at most 255 biomes per document.
const MAX_BIOMES := 255
## Painted surfaces a document may list, and entries per sample (see the header).
const MAX_SURFACES := 64
const SURFACE_ENTRIES := 4
## Bytes per sample in each RGBA8 plane, the two planes, and the bytes per sample in all.
const SURFACE_CHANNELS := 4
const SURFACE_INDEX_PLANE := 0
const SURFACE_WEIGHT_PLANE := 1
const SURFACE_BYTES := SURFACE_CHANNELS * 2
## Slots the authoring tools claim (ensure_surface): every surface a document can list, since
## the index ground shader (ground layers G3) draws them all.
const PAINT_SURFACE_LIMIT := MAX_SURFACES
## Painted slots a format 1 document stored, one weight channel each.
const FORMAT_1_SLOTS := 8
## Water bodies per document, rivers among them, and control points per river. The flow
## bake's cost grows with the rivers and their length.
const MAX_WATER_BODIES := 64
const MAX_RIVERS := 32
const MAX_RIVER_POINTS := 512
## Largest flow map the reader accepts, per axis (the baker writes about 4 per metre).
const MAX_FLOW_TEXELS := 1024
## Crossings (bridges, stepping stones) per document.
const MAX_CROSSINGS := 64

var palette_version: String = ""
## The content libraries this map used when it was saved: [{id, version, hash}], one per
## library whose biome or asset it holds (MapLibraries.record_for). Read from the manifest;
## the writer recomputes it from the document's ids, so this is what the file CLAIMED. Empty
## for a map saved before libraries, which counts as core only.
var libraries: Array[Dictionary] = []
var map_seed: int = 0
var size_cells: Vector2i = Vector2i(20, 20)
var cell_size_m: float = LevelData.DEFAULT_GRID_CELL_SIZE
var sample_spacing_m: float = DEFAULT_SAMPLE_SPACING_M
## One height tier; defaults to one grid cell (5 ft), per the design.
var tier_height_m: float = LevelData.DEFAULT_GRID_CELL_SIZE
## Palette surface preset name (e.g. "grass_alpine") the whole map starts as.
var base_surface: String = ""
## True when this document dresses a Blender-made map.glb in the same level folder.
var has_base_map: bool = false
## samples_x() * samples_z() heights in metres, row-major (Z rows, X columns).
var heights: PackedFloat32Array = PackedFloat32Array()
## Baked generator output: palette asset id -> flat rows (see the header).
var scatter: Dictionary[String, PackedFloat32Array] = {}
## Hand-placed assets: palette asset id -> flat rows, same format as scatter.
var props: Dictionary[String, PackedFloat32Array] = {}
## One byte per sample, > ERASE_THRESHOLD = erased; empty when there is no mask.
var erase_mask: PackedByteArray = PackedByteArray()
## Palette biome ids; a biome slot value s > 0 means biome_ids[s - 1].
var biome_ids: PackedStringArray = PackedStringArray()
## One byte per sample: 0 = no biome, else an index + 1 into biome_ids. Empty = none.
var biome_slots: PackedByteArray = PackedByteArray()
## One byte per sample: painted density 0..255. Empty exactly when biome_slots is.
var biome_density: PackedByteArray = PackedByteArray()
## Palette surface names painted on this map, at most MAX_SURFACES; an entry's index is a
## position in this list (see the header).
var surface_ids: PackedStringArray = PackedStringArray()
## sample_count() * SURFACE_BYTES bytes: the index plane, then the weight plane (see the
## header). Empty exactly when surface_ids is.
var surface_weights: PackedByteArray = PackedByteArray()
## Rivers and ponds, at most MAX_WATER_BODIES (see the header).
var water_bodies: Array[WaterBody] = []
## One byte per sample: 0 = no pond, else the id of the pond whose area holds the sample.
## Empty = no pond areas.
var pond_mask: PackedByteArray = PackedByteArray()
## Baked flow map: water_flow_size.x * water_flow_size.y texels of RG8, row-major, row j
## at v = (j + 0.5) / water_flow_size.y (WaterFlowBaker documents the frame). Empty = none.
var water_flow: PackedByteArray = PackedByteArray()
var water_flow_size: Vector2i = Vector2i.ZERO
## Plank bridges and stepping stones over the water (Crossing), at most MAX_CROSSINGS.
var crossings: Array[Crossing] = []
## One byte per sample: the persistent ground fire's intensity 0..255 (0 = no fire), painted by
## the Fire tool and drawn by FireField. Empty = no fire. The ash it leaves is a painted
## surface, a separate layer, so putting fire out never touches it.
var fire_mask: PackedByteArray = PackedByteArray()
## The grass-mass anchors of the scatter rows (contract section 9, "Saved levels: mass
## anchors"): per scatter asset id, (dx, dz) metres per row of scatter[asset id], in row order,
## from the row to its mass anchor (ScatterMass.anchors_entry). Saved rather than recomputed so a
## level does not depend on today's placement rules. Empty = none (an older level: each tuft takes
## its zone's hue where it stands).
var mass_anchors: Dictionary[String, PackedFloat32Array] = {}
## Derived, never saved: the wet dressing field (WaterDressing.compute(), RGBA8 per sample:
## bed, shore, depth) of the current heights and water, kept here so scatter jobs and the
## ground read one copy. Empty when there is no wet sample. Whoever changes the water or the
## ground under it calls WaterDressing.refresh() (AuthoringEditor, AuthoredTerrain.build).
var water_dressing: PackedByteArray = PackedByteArray()


## A flat, empty document `cells` in size with the default cell size (5 ft), sample spacing
## and tier height. A size outside MIN_SIZE_CELLS..MAX_SIZE_CELLS on either axis is refused:
## null, with an error, never a silently smaller map (callers check size_in_range() first).
## An even count keeps grid lines on the origin; an odd one leaves half a square at each edge.
static func create_flat(
	cells: Vector2i, surface: String, version: String, seed_value: int
) -> MapDocument:
	if not size_in_range(cells):
		push_error(
			(
				"MapDocument: a %d x %d cell map is outside %d..%d cells per axis"
				% [cells.x, cells.y, MIN_SIZE_CELLS, MAX_SIZE_CELLS]
			)
		)
		return null
	var doc := MapDocument.new()
	doc.size_cells = cells
	doc.base_surface = surface
	doc.palette_version = version
	doc.map_seed = seed_value
	var flat := PackedFloat32Array()
	flat.resize(doc.samples_x() * doc.samples_z())
	doc.heights = flat
	return doc


## True when a map `cells` in size fits the format on both axes (MIN_SIZE_CELLS to
## MAX_SIZE_CELLS). Pure.
static func size_in_range(cells: Vector2i) -> bool:
	return (
		cells.x >= MIN_SIZE_CELLS
		and cells.y >= MIN_SIZE_CELLS
		and cells.x <= MAX_SIZE_CELLS
		and cells.y <= MAX_SIZE_CELLS
	)


## Samples along one axis of `extent_m` metres at a nominal `spacing_m`: never fewer than
## two, so both edges always have a sample. Pure and static because the reader checks the
## sample cap from manifest values before any document exists.
static func samples_for(extent_axis_m: float, spacing_m: float) -> int:
	if spacing_m <= 0.0:
		return 2
	return maxi(2, roundi(extent_axis_m / spacing_m) + 1)


## Converts flat rows (ROW_STRIDE floats each) to the Array-of-Array rows
## ScatterGlbUtils.build_scatter() takes, per asset id. A trailing partial row is dropped.
static func scatter_groups(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> Dictionary:
	var groups := {}
	for asset_id in rows_by_asset:
		var flat: PackedFloat32Array = rows_by_asset[asset_id]
		var rows: Array = []
		for start in range(0, flat.size() - ROW_STRIDE + 1, ROW_STRIDE):
			rows.append(Array(flat.slice(start, start + ROW_STRIDE)))
		groups[asset_id] = rows
	return groups


## Map size in metres: (width along X, depth along Z).
func extent_m() -> Vector2:
	return Vector2(size_cells) * cell_size_m


func samples_x() -> int:
	return samples_for(extent_m().x, sample_spacing_m)


func samples_z() -> int:
	return samples_for(extent_m().y, sample_spacing_m)


func sample_count() -> int:
	return samples_x() * samples_z()


## The real distance between neighbouring samples along X and Z (see the header).
func sample_step() -> Vector2:
	return extent_m() / Vector2(samples_x() - 1, samples_z() - 1)


## World XZ (Vector2(x, z)) to continuous sample coordinates: (0, 0) at the (-W/2, -H/2)
## corner, (samples_x() - 1, samples_z() - 1) at the opposite one. Not clamped, so a
## caller can tell a point off the map; round or floor it to pick a sample.
func world_to_sample(world_xz: Vector2) -> Vector2:
	return (world_xz + extent_m() * 0.5) / sample_step()


## Continuous sample coordinates back to world XZ; the inverse of world_to_sample().
func sample_to_world(sample: Vector2) -> Vector2:
	return sample * sample_step() - extent_m() * 0.5


## Index of sample (x, z) in heights and the masks.
func sample_index(x: int, z: int) -> int:
	return z * samples_x() + x


## True when the erase-mask sample nearest to world XZ `world_xz` is erased. A point off
## the map, or any point when there is no mask, is not erased.
func is_erased(world_xz: Vector2) -> bool:
	if erase_mask.size() != sample_count():
		return false
	var sample := world_to_sample(world_xz).round()
	if sample.x < 0 or sample.y < 0 or sample.x >= samples_x() or sample.y >= samples_z():
		return false
	return erase_mask[sample_index(int(sample.x), int(sample.y))] > ERASE_THRESHOLD


## A keep-predicate for GLB scatter rows, `func(origin: Vector3) -> bool`, that drops the
## instances whose origin falls on an erased sample (is_erased of its X and Z), or an
## empty Callable when the mask erases nothing, so a caller can skip filtering entirely.
## Origins are in the GLB-root frame, which is the document's frame: a document that
## dresses a map.glb sits under the same LevelMap, centred on the same origin.
func erase_filter() -> Callable:
	if erase_mask.size() != sample_count():
		return Callable()
	var any_erased := false
	for value in erase_mask:
		if value > ERASE_THRESHOLD:
			any_erased = true
			break
	if not any_erased:
		return Callable()
	# The same arithmetic as is_erased(), hoisted: this runs once per scatter row.
	var mask := erase_mask
	var half := extent_m() * 0.5
	var step := sample_step()
	var width := samples_x()
	var depth := samples_z()
	return func(origin: Vector3) -> bool:
		var x := roundi((origin.x + half.x) / step.x)
		var z := roundi((origin.z + half.y) / step.y)
		if x < 0 or z < 0 or x >= width or z >= depth:
			return true
		return mask[z * width + x] <= ERASE_THRESHOLD


## Byte index of entry `entry` of sample `sample` in plane `plane` (SURFACE_INDEX_PLANE or
## SURFACE_WEIGHT_PLANE) of surface_weights, for a grid of `count` samples (see the
## header). Static so brush loops can hoist sample_count().
static func surface_offset(sample: int, entry: int, plane: int, count: int) -> int:
	return plane * count * SURFACE_CHANNELS + sample * SURFACE_CHANNELS + entry


## True when the painted surfaces are allocated and sized for the sample grid.
func has_surface_entries() -> bool:
	return not surface_ids.is_empty() and surface_weights.size() == sample_count() * SURFACE_BYTES


## `slot`'s weight 0..255 at sample `sample`: its entry's weight, 0 when the sample has no
## entry for it, there are no painted surfaces, or the slot is not in use.
func surface_weight(sample: int, slot: int) -> int:
	if slot < 0 or slot >= surface_ids.size() or not has_surface_entries():
		return 0
	var at := sample * SURFACE_CHANNELS
	var weights_at := sample_count() * SURFACE_CHANNELS + at
	for e in SURFACE_ENTRIES:
		var weight := surface_weights[weights_at + e]
		if weight != 0 and surface_weights[at + e] == slot:
			return weight
	return 0


## Paints `slot` to `value` (clamped to 0..255) at sample `sample`. When the entries would
## then sum past 255 the others are scaled down to fit, so the newest paint wins, as it
## does over automatic ground; when the sample already holds SURFACE_ENTRIES other
## surfaces, the weakest is dropped (its weight returns to the automatic ground). A value
## of 0 removes the slot's entry. Does nothing for a slot not in use.
@warning_ignore("integer_division")
func set_surface_weight(sample: int, slot: int, value: int) -> void:
	if slot < 0 or slot >= surface_ids.size() or not has_surface_entries():
		return
	var target := clampi(value, 0, 255)
	var count := sample_count()
	var entries := SurfaceEntries.read_sample(surface_weights, sample, count)
	var indices: PackedInt32Array = entries[0]
	var weights: PackedInt32Array = entries[1]
	var mine := indices.find(slot)
	if mine >= 0:
		indices.remove_at(mine)
		weights.remove_at(mine)
	elif target > 0 and indices.size() >= SURFACE_ENTRIES:
		# read_sample() returns the entries high to low: the last is the weakest.
		indices.resize(SURFACE_ENTRIES - 1)
		weights.resize(SURFACE_ENTRIES - 1)
	var others := 0
	for w in weights:
		others += w
	if others + target > 255:
		var room := 255 - target
		for e in weights.size():
			weights[e] = weights[e] * room / others
	if target > 0:
		indices.append(slot)
		weights.append(target)
	SurfaceEntries.write_sample(surface_weights, sample, count, indices, weights)


## A copy of plane `plane` of surface_weights (SURFACE_INDEX_PLANE: the indices,
## SURFACE_WEIGHT_PLANE: the weights; RGBA8 pixel data ready for Image.create_from_data);
## empty when there are no painted surfaces.
func surface_plane(plane: int) -> PackedByteArray:
	if surface_weights.is_empty():
		return PackedByteArray()
	var size := sample_count() * SURFACE_CHANNELS
	return surface_weights.slice(plane * size, (plane + 1) * size)


## The slot painting `surface` uses: its existing slot, else a new one (allocating the
## entries for the first) while fewer than `limit` are listed, else the first slot with no
## weight anywhere, renamed. -1 when `surface` is empty or all `limit` slots hold paint.
## `limit` defaults to PAINT_SURFACE_LIMIT, every slot the renderer draws.
func ensure_surface(surface: String, limit: int = PAINT_SURFACE_LIMIT) -> int:
	if surface == "":
		return -1
	var existing := surface_ids.find(surface)
	if existing >= 0:
		return existing
	if surface_ids.size() < mini(limit, MAX_SURFACES):
		if surface_weights.is_empty():
			surface_weights.resize(sample_count() * SURFACE_BYTES)
		surface_ids.append(surface)
		return surface_ids.size() - 1
	var used := used_surface_slots()
	for slot in surface_ids.size():
		if used[slot] == 0:
			surface_ids[slot] = surface
			return slot
	return -1


## True when `slot` has no weight at any sample (or is not in use).
func surface_slot_unused(slot: int) -> bool:
	if slot < 0 or slot >= surface_ids.size() or not has_surface_entries():
		return true
	return used_surface_slots()[slot] == 0


## One byte per slot of surface_ids: 1 when an entry of that slot has weight somewhere.
## One pass over the entries (SurfaceEntries.used_slots).
func used_surface_slots() -> PackedByteArray:
	if not has_surface_entries():
		var none := PackedByteArray()
		none.resize(surface_ids.size())
		return none
	return SurfaceEntries.used_slots(surface_weights, sample_count(), surface_ids.size())


## Drops trailing slots with no paint (no index moves), and the entries with the last
## slot.
func trim_unused_surfaces() -> void:
	var used := used_surface_slots()
	var keep := surface_ids.size()
	while keep > 0 and used[keep - 1] == 0:
		keep -= 1
	if keep < surface_ids.size():
		surface_ids.resize(keep)
	if surface_ids.is_empty():
		surface_weights = PackedByteArray()


## The water body with id `body_id`, or null.
func water_body(body_id: int) -> WaterBody:
	for body in water_bodies:
		if body.id == body_id:
			return body
	return null


## The id a new water body gets: one past the highest in use, else the lowest free id
## (so ids stay stable: an existing body's id never changes); -1 when the document already
## holds MAX_WATER_BODIES bodies.
func next_water_id() -> int:
	if water_bodies.size() >= MAX_WATER_BODIES:
		return -1
	var used := {}
	var highest := 0
	for body in water_bodies:
		used[body.id] = true
		highest = maxi(highest, body.id)
	if highest < WaterBody.MAX_ID:
		return highest + 1
	for candidate in range(1, WaterBody.MAX_ID + 1):
		if not used.has(candidate):
			return candidate
	return -1


## The crossing with id `crossing_id`, or null.
func crossing(crossing_id: int) -> Crossing:
	for entry in crossings:
		if entry.id == crossing_id:
			return entry
	return null


## The id a new crossing gets: one past the highest in use, else the lowest free id; -1 when
## the document already holds MAX_CROSSINGS crossings.
func next_crossing_id() -> int:
	if crossings.size() >= MAX_CROSSINGS:
		return -1
	var used := {}
	var highest := 0
	for entry in crossings:
		used[entry.id] = true
		highest = maxi(highest, entry.id)
	if highest < Crossing.MAX_ID:
		return highest + 1
	for candidate in range(1, Crossing.MAX_ID + 1):
		if not used.has(candidate):
			return candidate
	return -1


## Whole rows across every asset of `rows_by_asset` (scatter or props).
@warning_ignore("integer_division")
static func row_count(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> int:
	var total := 0
	for asset_id in rows_by_asset:
		total += rows_by_asset[asset_id].size() / ROW_STRIDE
	return total
