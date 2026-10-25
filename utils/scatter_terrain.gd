class_name ScatterTerrain
extends RefCounted

## The terrain response of a rule (content library step S12a, docs/systems/scatter.md "Terrain
## response"): its slope minimum and its response curves on the slope, height, wet and water_dist
## axes (S12c: the distance grid below), as one
## keep ScatterGenerator._evaluate multiplies in after the slope-maximum test. Pure statics; every
## input is a pure function of the candidate's position, so region independence holds. Split out
## of ScatterGenerator (the lint cap is 1000 lines). The native port (S12b) repeats `keep`
## expression for expression.

## A rule's slope_min_deg is a band edge: full density from the minimum up, fading to none over
## this many degrees BELOW it. No allowance is added (ScatterPlan.SLOPE_ALLOWANCE_DEG is for the
## maximum only).
const SLOPE_MIN_FADE_DEG := 5.0
## The longest distance to water the `water_dist` axis tells apart, metres: the axis range's end
## (LibraryContracts.RESPONSE_AXES) and the cap of the distance grid. A point farther from any
## water (or on a map with no water) reads exactly this, so a curve's last value applies beyond it.
const WATER_DIST_MAX_M := 64.0
## The wet-line byte (WaterDressing channel A) of a sample that is water: compute() writes
## exactly 1.0 for a sample under the water or on a riffle and less than 0.96 one sample away.
const WATER_BYTE := 255
## Distance grids kept (a small newest-first list), see water_distance_grid().
const WATER_GRID_CACHE := 2

static var _grid_mutex := Mutex.new()
static var _grid_cache: Array[Dictionary] = []


## Callable(Vector2 map XZ) -> float: the shore weight 0..1 (WaterDressing channel G, bilinear) the
## `wet` axis reads, from the whole-grid stored field so a window never moves it; 0 everywhere on
## a document with no wet dressing.
static func wet_sampler(doc: MapDocument) -> Callable:
	var field := doc.water_dressing
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	if field.size() != doc.sample_count() * WaterDressing.CHANNELS:
		return func(_p: Vector2) -> float: return 0.0
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	return func(p: Vector2) -> float:
		return WaterDressing.sample(field, columns, rows, (p + half) / step).y


## The `water_dist` axis' grid for `doc`: one float32 per sample, the Euclidean distance in metres
## from that sample to the nearest water sample (a sample under the water, on a riffle or a fall's
## face: WaterDressing's wet-line byte at 255), 0 on water itself (never negative: a rule on the
## water is already kept off it by the bed weight, and an emergent rule asks for 0), capped at
## WATER_DIST_MAX_M. Exact (DistanceField) over the water's bounding rect grown by the cap; outside
## it every sample is at the cap by construction. Empty when the document has no wet dressing.
## A pure function of the document's stored dressing, never of a scatter window, so a cell
## generated alone, with neighbours or in the whole map reads the same grid. Cached by the
## dressing's content (newest first, WATER_GRID_CACHE entries, behind a mutex: workers share it),
## so a document pays the transform once per water change, not once per job.
static func water_distance_grid(doc: MapDocument) -> PackedFloat32Array:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var field := doc.water_dressing
	if field.size() != columns * rows * WaterDressing.CHANNELS:
		return PackedFloat32Array()
	var step := doc.sample_step()
	_grid_mutex.lock()
	for entry: Dictionary in _grid_cache:
		if (
			entry.columns == columns
			and entry.rows == rows
			and entry.step == step
			and entry.field == field
		):
			var hit: PackedFloat32Array = entry.grid
			_grid_mutex.unlock()
			return hit
	_grid_mutex.unlock()
	var built := _build_water_grid(field, columns, rows, step)
	_grid_mutex.lock()
	_grid_cache.push_front(
		{"columns": columns, "rows": rows, "step": step, "field": field.duplicate(), "grid": built}
	)
	while _grid_cache.size() > WATER_GRID_CACHE:
		_grid_cache.pop_back()
	_grid_mutex.unlock()
	return built


static func _build_water_grid(
	field: PackedByteArray, columns: int, rows: int, step: Vector2
) -> PackedFloat32Array:
	var grid := PackedFloat32Array()
	grid.resize(columns * rows)
	grid.fill(WATER_DIST_MAX_M)
	var wet_rect := Rect2i()
	for z in rows:
		var row := z * columns
		var first := -1
		var last := -1
		for x in columns:
			if field[(row + x) * WaterDressing.CHANNELS + 3] == WATER_BYTE:
				if first < 0:
					first = x
				last = x
		if first >= 0:
			wet_rect = MaskBrush.merge_rect(wet_rect, Rect2i(first, z, last - first + 1, 1))
	if not wet_rect.has_area():
		return grid
	var pad := ceili(WATER_DIST_MAX_M / minf(step.x, step.y))
	var rect := wet_rect.grow(pad).intersection(Rect2i(0, 0, columns, rows))
	var feature := PackedByteArray()
	feature.resize(rect.size.x * rect.size.y)
	for j in rect.size.y:
		var row := (rect.position.y + j) * columns + rect.position.x
		for i in rect.size.x:
			if field[(row + i) * WaterDressing.CHANNELS + 3] == WATER_BYTE:
				feature[j * rect.size.x + i] = 1
	var distance_sq: PackedFloat32Array = (
		DistanceField.transform(feature, rect.size.x, rect.size.y, step).distance_sq
	)
	var cap_sq := WATER_DIST_MAX_M * WATER_DIST_MAX_M
	for j in rect.size.y:
		var row := (rect.position.y + j) * columns + rect.position.x
		for i in rect.size.x:
			var d_sq := distance_sq[j * rect.size.x + i]
			if d_sq < cap_sq:
				grid[row + i] = sqrt(d_sq)
	return grid


## Callable(Vector2 map XZ) -> float: the distance to the nearest water in metres, bilinear on
## water_distance_grid (the same filter as the wet sampler), WATER_DIST_MAX_M everywhere on a
## document with no water. The grid is built on the first call, so a job whose rules have no
## water_dist curve never pays for it.
static func water_dist_sampler(doc: MapDocument) -> Callable:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var held := {"grid": PackedFloat32Array(), "built": false}
	return func(p: Vector2) -> float:
		if not held.built:
			held.grid = water_distance_grid(doc)
			held.built = true
		var grid: PackedFloat32Array = held.grid
		if grid.size() != columns * rows:
			return WATER_DIST_MAX_M
		return sample_grid(grid, columns, rows, (p + half) / step)


## `grid` (one float per sample) bilinearly at continuous sample coordinates `s`, clamped to the
## grid, with WaterDressing.sample's corner and weight arithmetic; the native port repeats it.
static func sample_grid(grid: PackedFloat32Array, columns: int, rows: int, s: Vector2) -> float:
	var fx := clampf(s.x, 0.0, columns - 1)
	var fz := clampf(s.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var a := z0 * columns + x0
	var c := a + columns
	var top := lerpf(grid[a], grid[a + 1], tx)
	var bottom := lerpf(grid[c], grid[c + 1], tx)
	return lerpf(top, bottom, tz)


## The product of a plan entry's terrain response at `p`, 0..1, only ever lowering the keep: the
## slope minimum band, then the slope, height (the ground's world y), wet (the shore weight) and
## water_dist (metres to the nearest water) curves, each a ScatterPlan.curve_value. `normal` is
## the ground normal when the slope maximum already fetched it, else Vector3.ZERO.
static func keep(ctx: Dictionary, entry: Dictionary, p: Vector2, normal: Vector3) -> float:
	var result := 1.0
	var curve_slope: PackedFloat64Array = entry.curve_slope
	var slope_min_cos: float = entry.slope_min_cos
	if slope_min_cos > -1.5 or not curve_slope.is_empty():
		if normal == Vector3.ZERO:
			normal = ctx.normal_at.call(p)
		var flatter := slope_min_cos > -1.5 and normal.y > slope_min_cos
		if flatter or not curve_slope.is_empty():
			var angle := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
			if flatter:
				result *= clampf(1.0 - (entry.slope_min - angle) / SLOPE_MIN_FADE_DEG, 0.0, 1.0)
			if not curve_slope.is_empty():
				result *= ScatterPlan.curve_value(curve_slope, angle)
	var curve_height: PackedFloat64Array = entry.curve_height
	if not curve_height.is_empty():
		result *= ScatterPlan.curve_value(curve_height, ctx.height_at.call(p))
	var curve_wet: PackedFloat64Array = entry.curve_wet
	if not curve_wet.is_empty():
		result *= ScatterPlan.curve_value(curve_wet, ctx.wet_at.call(p))
	var curve_water_dist: PackedFloat64Array = entry.curve_water_dist
	if not curve_water_dist.is_empty():
		result *= ScatterPlan.curve_value(curve_water_dist, ctx.water_dist_at.call(p))
	return result
