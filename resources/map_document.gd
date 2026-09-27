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
## Painted surfaces. surface_ids names up to MAX_SURFACES palette surfaces; slot k is
## surface_ids[k], and its weight at each sample is its coverage 0..255. surface_weights
## holds all eight slots in two planes, each exactly the RGBA8 pixel data of one weight
## texture: bytes [0, 4n) are image A (slots 0-3 in R, G, B, A) and [4n, 8n) image B
## (slots 4-7), for n = sample_count(). Planar rather than eight interleaved bytes per
## sample because the ground shader samples two RGBA8 textures: surface_plane() hands one
## plane to Image.create_from_data as a native slice, where an interleaved layout would
## need a GDScript split loop over every sample on each upload and save. A brush pays one
## extra multiply-add per channel (surface_offset()). The weights of all slots at one
## sample sum to at most 255; the remainder is automatic ground (rules and biomes), so a
## painted surface overrides it in proportion to its weight. set_surface_weight() keeps
## the sum; the writer and reader normalise any sample that breaks it.
##
## Water. water_bodies holds the rivers and ponds (WaterBody, flat water per body, stable
## ids); pond_mask is one byte per sample naming the pond whose area holds it (0 = none);
## water_flow is the baked map-wide flow map (WaterFlowBaker), RG8 pixel data of
## water_flow_size texels, empty when there is none. One flow map per map because the
## water shader has one flow sampler per level. WaterGeometry derives the wet samples and
## per-sample levels. Summary: docs/ARCHITECTURE.md "Water model and flow bake".
##
## The fields are plain vars because authoring mutates one document for a whole session;
## every helper here is pure except the surface_* mutators, which edit the fields.

const FORMAT := 1
const ROW_STRIDE := 10
const DEFAULT_SAMPLE_SPACING_M := 0.25

## Domain limits, enforced by MapDocumentIO.parse() on untrusted documents. 64 cells at
## the default 5 ft cell is about 97.5 m, over the 200 ft (61 m) authoring maximum.
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
## Painted surface slots: two RGBA8 weight images of SURFACE_CHANNELS slots each.
const MAX_SURFACES := 8
const SURFACE_CHANNELS := 4
## Water bodies per document, rivers among them, and control points per river. The flow
## bake's cost grows with the rivers and their length.
const MAX_WATER_BODIES := 64
const MAX_RIVERS := 32
const MAX_RIVER_POINTS := 512
## Largest flow map the reader accepts, per axis (the baker writes about 4 per metre).
const MAX_FLOW_TEXELS := 1024

var palette_version: String = ""
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
## Palette surface names painted on this map, at most MAX_SURFACES; slot order is
## channel order (see the header).
var surface_ids: PackedStringArray = PackedStringArray()
## sample_count() * 8 bytes in two RGBA8 planes (see the header). Empty exactly when
## surface_ids is.
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
## Derived, never saved: the wet dressing field (WaterDressing.compute(), RGBA8 per sample:
## bed, shore, depth) of the current heights and water, kept here so scatter jobs and the
## ground read one copy. Empty when there is no wet sample. Whoever changes the water or the
## ground under it calls WaterDressing.refresh() (AuthoringEditor, AuthoredTerrain.build).
var water_dressing: PackedByteArray = PackedByteArray()


## A flat, empty document with the default cell size (5 ft), sample spacing and tier
## height. Sizes are clamped to MIN_SIZE_CELLS..MAX_SIZE_CELLS; the authoring UI only
## asks for even counts (20, 30, 40) so grid lines stay on the origin.
static func create_flat(
	cells: Vector2i, surface: String, version: String, seed_value: int
) -> MapDocument:
	var doc := MapDocument.new()
	doc.size_cells = Vector2i(
		clampi(cells.x, MIN_SIZE_CELLS, MAX_SIZE_CELLS),
		clampi(cells.y, MIN_SIZE_CELLS, MAX_SIZE_CELLS)
	)
	doc.base_surface = surface
	doc.palette_version = version
	doc.map_seed = seed_value
	var flat := PackedFloat32Array()
	flat.resize(doc.samples_x() * doc.samples_z())
	doc.heights = flat
	return doc


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


## Byte index of `slot`'s weight at sample `sample` in surface_weights, for a grid of
## `count` samples (see the header). Static so brush loops can hoist sample_count().
static func surface_offset(sample: int, slot: int, count: int) -> int:
	return (slot >> 2) * count * SURFACE_CHANNELS + sample * SURFACE_CHANNELS + (slot & 3)


## `slot`'s weight 0..255 at sample `sample`; 0 when there are no painted surfaces or the
## slot is not in use.
func surface_weight(sample: int, slot: int) -> int:
	if slot < 0 or slot >= surface_ids.size() or surface_weights.is_empty():
		return 0
	return surface_weights[surface_offset(sample, slot, sample_count())]


## Paints `slot` to `value` (clamped to 0..255) at sample `sample`. When the slots would
## then sum past 255 the other slots are scaled down to fit, so the newest paint wins,
## as it does over automatic ground. Does nothing for a slot not in use.
@warning_ignore("integer_division")
func set_surface_weight(sample: int, slot: int, value: int) -> void:
	if slot < 0 or slot >= surface_ids.size() or surface_weights.is_empty():
		return
	var count := sample_count()
	var target := clampi(value, 0, 255)
	var others := 0
	for other in surface_ids.size():
		if other != slot:
			others += surface_weights[surface_offset(sample, other, count)]
	if others + target > 255:
		var room := 255 - target
		for other in surface_ids.size():
			if other != slot:
				var at := surface_offset(sample, other, count)
				surface_weights[at] = surface_weights[at] * room / others
	surface_weights[surface_offset(sample, slot, count)] = target


## The RGBA8 pixel data of weight image `image` (0: slots 0-3, 1: slots 4-7), a copy
## ready for Image.create_from_data; empty when there are no painted surfaces.
func surface_plane(image: int) -> PackedByteArray:
	if surface_weights.is_empty():
		return PackedByteArray()
	var plane := sample_count() * SURFACE_CHANNELS
	return surface_weights.slice(image * plane, (image + 1) * plane)


## The slot painting `surface` uses: its existing slot, else a new one (allocating the
## weights for the first), else the first slot whose weights are all zero, renamed. -1
## when `surface` is empty or all MAX_SURFACES slots hold paint.
func ensure_surface(surface: String) -> int:
	if surface == "":
		return -1
	var existing := surface_ids.find(surface)
	if existing >= 0:
		return existing
	if surface_ids.size() < MAX_SURFACES:
		if surface_weights.is_empty():
			surface_weights.resize(sample_count() * SURFACE_CHANNELS * 2)
		surface_ids.append(surface)
		return surface_ids.size() - 1
	for slot in surface_ids.size():
		if surface_slot_unused(slot):
			surface_ids[slot] = surface
			return slot
	return -1


## True when `slot` has zero weight at every sample (or is not in use). The Paint tool
## asks at stroke end and when a tile is picked with every slot taken, so the walk is a
## strided index loop over the slot's channel (no call per sample: about 3 ms on a
## 200 ft map where the slot is empty, less where paint is found early).
func surface_slot_unused(slot: int) -> bool:
	if slot < 0 or slot >= surface_ids.size() or surface_weights.is_empty():
		return true
	var count := sample_count()
	var weights := surface_weights
	var start := surface_offset(0, slot, count)
	var end := start + count * SURFACE_CHANNELS
	for at in range(start, end, SURFACE_CHANNELS):
		if weights[at] != 0:
			return false
	return true


## Drops trailing slots with no paint (cheap: no channel moves), and the weights with
## the last slot, so a map painted with four surfaces or fewer saves one image.
func trim_unused_surfaces() -> void:
	while not surface_ids.is_empty() and surface_slot_unused(surface_ids.size() - 1):
		surface_ids.resize(surface_ids.size() - 1)
	if surface_ids.is_empty():
		surface_weights = PackedByteArray()


## `weights` (two planes for `count` samples) with the channels of slots `used` and up
## zeroed and every sample whose slots sum past 255 scaled down to fit. Returns
## {"weights": PackedByteArray, "stray": samples with paint in an unused slot,
## "over": samples scaled}. Pure: `weights` is duplicated before the first fix, since
## packed arrays are shared by reference. Shared by the writer and the reader.
@warning_ignore("integer_division")
static func normalized_surface_weights(
	weights: PackedByteArray, count: int, used: int
) -> Dictionary:
	var out := weights
	var copied := false
	var stray := 0
	var over := 0
	var plane := count * SURFACE_CHANNELS
	# Image B is only walked when a slot there is in use or it holds anything at all
	# (a native count, not a per-sample loop): the common case touches one plane.
	var slots := MAX_SURFACES
	if used <= SURFACE_CHANNELS and weights.slice(plane).count(0) == plane:
		slots = SURFACE_CHANNELS
	for sample in count:
		var sum := 0
		var stray_here := false
		for slot in slots:
			var value := out[(slot >> 2) * plane + sample * SURFACE_CHANNELS + (slot & 3)]
			if slot < used:
				sum += value
			elif value != 0:
				stray_here = true
		if not stray_here and sum <= 255:
			continue
		if not copied:
			out = out.duplicate()
			copied = true
		for slot in slots:
			var at := (slot >> 2) * plane + sample * SURFACE_CHANNELS + (slot & 3)
			if slot >= used:
				out[at] = 0
			elif sum > 255:
				out[at] = out[at] * 255 / sum
		stray += 1 if stray_here else 0
		over += 1 if sum > 255 else 0
	return {"weights": out, "stray": stray, "over": over}


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


## Whole rows across every asset of `rows_by_asset` (scatter or props).
@warning_ignore("integer_division")
static func row_count(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> int:
	var total := 0
	for asset_id in rows_by_asset:
		total += rows_by_asset[asset_id].size() / ROW_STRIDE
	return total
