class_name DressingGround
extends RefCounted

## The ground heights of a dressing document (MapDocument.has_base_map): a Blender-made
## map.glb brings its own terrain, so the document's heights are not a terrain anyone sees
## but the ground the scatter generator stands its instances on (Y, the normal that tilts
## normal-aligned species, the slope that thins steep ground). They are sampled from the
## GLB's collision, one downward ray per document sample on the terrain layer (layer 1,
## DragPlaceController.raycast_terrain_down, the ground tokens and props land on), every
## time authoring opens a dressed map, so a re-exported GLB is followed too. Nothing renders
## them: MapSourceLoader builds AuthoredTerrain only for a document without a GLB, and a
## play-time load uses the saved rows as they are.
##
## Sampling runs in slices (step()) so the authoring loading screen stays responsive:
## about 4 us per ray, 180 ms for a 170 ft dressing (43k samples), measured on Deciduous
## clusters. A sample whose ray misses (the document is a whole number of cells, so its
## corners can overhang the terrain) takes the height of the nearest sample that hit, or 0
## when none did.
##
## Before this existed a dressed document's heights stayed flat 0, so everything painted
## was generated at Y = 0, floating over dips and buried under rises. snap_rows() moves such
## rows onto the sampled ground (see AuthoringController._fit_dressing_to_ground).
##
## The same sampler, over any regular grid (begin_grid), gives a Blender map's grid overlay
## its ground at play time (GroundHeightField, MapSourceLoader.fit_grid_ground_async).

## Rows that move less than this are left as they are (the float32 round trip of a height).
const ROW_TOLERANCE_M := 0.002

var heights: PackedFloat32Array = PackedFloat32Array()
## One byte per sample: 1 where the ray hit, 0 where it missed (before fill_misses()).
var hits: PackedByteArray = PackedByteArray()
## Microseconds spent casting rays so far.
var usec: int = 0

var _world: World3D = null
var _transform: Transform3D = Transform3D.IDENTITY
var _inverse: Transform3D = Transform3D.IDENTITY
var _top: float = 0.0
var _next: int = 0
## The grid sampled: map-frame XZ of sample (0, 0), the step between samples, and its size.
var _origin: Vector2 = Vector2.ZERO
var _step: Vector2 = Vector2.ONE
var _columns: int = 0
var _rows: int = 0


## A sampler for `doc`, whose frame is the map root's (`map_transform`, its global
## transform), casting in `world` from world height `top_y`, which must be above every
## collision surface.
static func begin(
	doc: MapDocument, world: World3D, map_transform: Transform3D, top_y: float
) -> DressingGround:
	return begin_grid(
		world,
		map_transform,
		top_y,
		-doc.extent_m() * 0.5,
		doc.sample_step(),
		doc.samples_x(),
		doc.samples_z()
	)


## A sampler for a regular grid of `columns` x `rows` samples in the frame placed by
## `map_transform`: sample (x, z) at map-frame XZ `origin + Vector2(x, z) * step`, row-major.
## Casts as begin() does.
static func begin_grid(
	world: World3D,
	map_transform: Transform3D,
	top_y: float,
	origin: Vector2,
	step: Vector2,
	columns: int,
	rows: int
) -> DressingGround:
	var sampler := DressingGround.new()
	sampler._world = world
	sampler._transform = map_transform
	sampler._inverse = map_transform.affine_inverse()
	sampler._top = top_y
	sampler._origin = origin
	sampler._step = step
	sampler._columns = columns
	sampler._rows = rows
	sampler.heights.resize(columns * rows)
	sampler.hits.resize(columns * rows)
	return sampler


## Casts rays for up to `budget_usec` (at least one row of samples). Returns true once every
## sample is cast and the misses are filled; `heights` is then final.
@warning_ignore("integer_division")
func step(budget_usec: int) -> bool:
	if _next >= heights.size():
		return true
	var started := Time.get_ticks_usec()
	var space := _world.direct_space_state
	var columns := _columns
	while _next < heights.size():
		var z := _next / columns
		for x in columns:
			var local := _origin + Vector2(x, z) * _step
			var world := _transform * Vector3(local.x, 0.0, local.y)
			var hit := DragPlaceController.raycast_terrain_down(space, world, _top)
			var index := _next + x
			if hit != Vector3.INF:
				heights[index] = clampf(
					(_inverse * hit).y, -MapDocument.MAX_ABS_HEIGHT_M, MapDocument.MAX_ABS_HEIGHT_M
				)
				hits[index] = 1
		_next += columns
		if Time.get_ticks_usec() - started >= budget_usec:
			break
	usec += Time.get_ticks_usec() - started
	if _next < heights.size():
		return false
	heights = fill_misses(heights, hits, columns, _rows)
	return true


## How many samples missed the ground (valid once step() returned true).
func miss_count() -> int:
	return hits.count(0)


## `values` with every sample whose `hit` byte is 0 given the value of the nearest sample
## that hit (breadth-first over the 4-neighbour grid, so "nearest" is in grid steps), or 0
## everywhere when nothing hit. Pure.
@warning_ignore("integer_division")
static func fill_misses(
	values: PackedFloat32Array, hit: PackedByteArray, columns: int, rows: int
) -> PackedFloat32Array:
	var filled := values.duplicate()
	var reached := hit.duplicate()
	var queue := PackedInt32Array()
	for i in reached.size():
		if reached[i] != 0:
			queue.append(i)
		else:
			filled[i] = 0.0
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % columns
		var z := i / columns
		for n in [
			i - 1 if x > 0 else -1,
			i + 1 if x < columns - 1 else -1,
			i - columns if z > 0 else -1,
			i + columns if z < rows - 1 else -1,
		]:
			if n >= 0 and reached[n] == 0:
				reached[n] = 1
				filled[n] = filled[i]
				queue.append(n)
	return filled


## Makes `new_heights` the ground of `doc` and moves the generated rows `scatter` (the
## AuthoredScatter built from the document) holds from the old ground onto the new one
## (snap_rows), rebuilding only the cells that changed, in place with no animation. Returns
## how many rows moved: 0 for a document whose heights were already right or that has
## nothing generated yet. Hand-placed props are not touched: the Place brush beds each one
## on the collision under it when it is placed, so they were never on the flat heights.
static func settle(
	doc: MapDocument, new_heights: PackedFloat32Array, scatter: AuthoredScatter, aligned: Dictionary
) -> int:
	var before := ScatterGenerator.document_fields(ground_document(doc, doc.heights), "")
	var after := ScatterGenerator.document_fields(ground_document(doc, new_heights), "")
	doc.heights = new_heights
	if not is_instance_valid(scatter):
		return 0
	var moved := 0
	var changed := {}
	var by_cell := AuthoredScatter.rows_by_cell_of(scatter.rows_by_asset())
	for cell in by_cell:
		var snapped := snap_rows(by_cell[cell], before, after, aligned)
		if snapped.moved > 0:
			moved += snapped.moved
			changed[cell] = snapped.rows
	if not changed.is_empty():
		scatter.set_cells(changed, false)
	return moved


## A copy of the parts of `doc` ScatterGenerator.document_fields() reads for heights, with
## `with_heights` in place of its own.
static func ground_document(doc: MapDocument, with_heights: PackedFloat32Array) -> MapDocument:
	var copy := MapDocument.new()
	copy.size_cells = doc.size_cells
	copy.cell_size_m = doc.cell_size_m
	copy.sample_spacing_m = doc.sample_spacing_m
	copy.heights = with_heights
	return copy


## The asset ids the biomes place normal-aligned (species "align": "normal").
static func aligned_assets(
	biome_ids: PackedStringArray, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
	var aligned := {}
	for biome_id in biome_ids:
		for rule in PaletteLibrary.species(biome_id, root):
			if rule.get("align", "upright") == "normal":
				for asset_id in rule.get("assets", []):
					aligned[asset_id] = true
	return aligned


## Generated rows (asset id -> flat rows) moved from the ground `before` to the ground
## `after` (document_fields() dictionaries): Y becomes after's height, and a normal-aligned
## asset (in `aligned`) turns by the arc from before's normal to after's, which keeps its
## yaw and its random lean. Returns {"rows": asset id -> rows, "moved": rows changed}; an
## asset whose rows did not move keeps the very same array. Pure.
@warning_ignore("integer_division")
static func snap_rows(
	rows_by_asset: Dictionary, before: Dictionary, after: Dictionary, aligned: Dictionary
) -> Dictionary:
	var stride := MapDocument.ROW_STRIDE
	var out := {}
	var moved := 0
	for asset_id in rows_by_asset:
		var rows: PackedFloat32Array = rows_by_asset[asset_id]
		var tilt: bool = aligned.has(asset_id)
		var copy := PackedFloat32Array()
		for r in rows.size() / stride:
			var b := r * stride
			var p := Vector2(rows[b], rows[b + 2])
			var y: float = after.height_at.call(p)
			var turn := Quaternion.IDENTITY
			if tilt:
				var from: Vector3 = before.normal_at.call(p)
				var to: Vector3 = after.normal_at.call(p)
				if from.angle_to(to) > 0.0001:
					turn = Quaternion(from, to)
			if absf(y - rows[b + 1]) <= ROW_TOLERANCE_M and turn == Quaternion.IDENTITY:
				continue
			if copy.is_empty():
				copy = rows.duplicate()
			moved += 1
			copy[b + 1] = y
			if turn != Quaternion.IDENTITY:
				var q := Quaternion(rows[b + 3], rows[b + 4], rows[b + 5], rows[b + 6])
				if q.length_squared() > 0.0:
					q = (turn * q.normalized()).normalized()
					copy[b + 3] = q.x
					copy[b + 4] = q.y
					copy[b + 5] = q.z
					copy[b + 6] = q.w
		out[asset_id] = rows if copy.is_empty() else copy
	return {"rows": out, "moved": moved}
