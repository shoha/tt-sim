class_name WaterMeshBuilder
extends RefCounted

## The geometry of a map document's authored water (MapDocument.water_bodies), pure: one
## merged surface mesh for every body, the surface collision and WaterZone footprint of each
## body, and the per-sample water levels the ground height field raises the grid to.
## AuthoredWater turns it into nodes. Summary: docs/systems/water.md (Runtime).
##
## One mesh for all bodies, because the water shader has one flow sampler per level
## (WaterGlbUtils, one map-wide flow map, WaterFlowBaker): it sits at the map origin with an
## identity transform and map-normalised UVs, u = (x + W/2) / W, v = (z + H/2) / H, the
## frame the flow bake is written in.
##
## Coverage, on the document's sample grid. Each sample takes the level of the highest body
## whose area holds it (WaterGeometry's rule); it is wet when its ground is below that level.
## A grid cell (the quad between four samples) is water when any of its corners is wet, at
## the level of its highest wet corner's body, flat. The cell reaches past the shoreline to
## its dry corners, where the ground is at or above the surface, so the depth test hides the
## part past the waterline and the shader's depth-based shallows and foam draw the edge. One
## more ring of cells (MARGIN_CELLS) is added where all of a cell's corners stand at or
## above the level: tucked under the banks, it keeps the mesh edge buried when the shader's
## bob lifts a vertex or the bank meets the surface exactly at a sample; a cell whose corner
## is below the level outside the body's area is never added (it would show a hard edge in
## the air). The sample grid is the resolution because coverage is decided per sample; a
## coarser mesh would need a wider margin, which cannot stay under a narrow bank.
##
## Cascades (P4-3). Between two reaches of one river (the upper one's last point is the
## lower one's first, the upper level higher) the carve leaves a riffle (WaterCarve); the
## flat surfaces cannot cover it, so the mesh adds a sheet that follows the riffle's ground
## CASCADE_FILM_M above it, clamped between the two levels, and never below a surface
## falling from the upper level to the lower at CASCADE_SLOPE (for a small step over deep
## water, where there is no riffle to follow), over the channel (within the lower reach's
## half-width of either course) from CASCADE_BACK_M above the shared point to the riffle's
## foot (cascades()). So shallow, the water shader draws it as white water, and the flow
## bake treats it as wet (WaterFlowBaker), so it runs downstream. Its cells replace the flat
## ones there, meet the flat surfaces at their levels and tuck their bank edge under the
## ground. No collision or zone: tokens stand on the riffle's ground. A free river end over a
## channel carved lower than its level (a river cut in two by an erase; the terrain stays
## carved) gets the same kind of sheet: the surface falls down the channel at RUN_OUT_SLOPE
## and trickles on over its bed as a film (_run_out), instead of ending in the air; an end
## that lies in other water (a confluence) needs none.
##
## Falls (phase 4c, P4c-3). A step that is a waterfall (WaterFalls.is_fall) gets no sheet: a
## height field cannot stand forward of a face, so cascades() skips the pair and the curtain
## is separate geometry (WaterFallMesh, the "falls" key of build(), its own node). The flat
## cells straddling the lip line would still stick one sample out over the face at the upper
## level; fall_cells() turns them into sheet cells whose downstream corners are tucked under
## the face (the lip roll of the curtain hides the tucked quad). Run-out ends are unchanged.

const MESH_NAME := "AuthoredWater-water"
## Rings of tucked cells added past the covered cells (see the header).
const MARGIN_CELLS := 1
## Reach steps (P4-3, cascades()): the sheet of water over a riffle stands this far above
## its bed, from this far above the shared point to the riffle's foot; its edge on the banks
## is tucked this far under the ground. Vertex keys of the sheet and of its tucked edge.
const CASCADE_FILM_M := 0.06
const CASCADE_BACK_M := 1.0
## The sheet falls from the upper level to the lower no more steeply than this, over deep
## water too (a small step in a deep river).
const CASCADE_SLOPE := 0.3
## A free river end over a channel carved lower (_run_out): the surface's fall per metre
## (steep: a gentle one reads as a slab of glass leaning into the dry channel), then a film
## over the channel's bed this much further (white water trickling out).
const RUN_OUT_SLOPE := 1.2
const RUN_OUT_FILM_M := 1.5
const CASCADE_TUCK_M := 0.05
## Across its banks (P4-5) a sheet thins by this much per metre toward the carve's waterline,
## where it meets the ground, and sinks under the bank past it, down to CASCADE_TUCK_M
## below. The thinning spans more than a sample each side (0.3 m in, 0.25 m out), so the
## triangles, which are the ground's own, put the waterline on a smooth curve: cutting the
## sheet off at the channel's half-width drew it as a sawtooth of the sample grid.
const CASCADE_EDGE_SLOPE := 0.2
const CASCADE_KEY := 255
const TUCKED_KEY := 254
## How many samples past a fall's lip line the flat cells are tucked under the face
## (fall_cells(): a cell straddling a diagonal lip line has a corner up to sqrt(2) samples
## past it).
const LIP_TUCK_SAMPLES := 1.5
## Side of the square tiles a body's WaterZone footprint is split into (metres).
const ZONE_TILE_M := 5.0

## The water of `doc`: {"arrays": Mesh arrays of the merged surface ([] with no water),
## "levels": PackedFloat32Array per sample (the owning body's level, WaterGeometry.DRY where
## no body's area holds the sample), "wet": PackedByteArray per sample (1 where the ground is
## below its level), "bodies": Array of {"id", "level", "floats" (bool), "faces"
## (PackedVector3Array, the body's triangles for its surface collision), "tiles" (Array of
## Rect2, map XZ, the WaterZone footprint)}, one per body with covered cells, "falls": Mesh
## arrays of the waterfalls (WaterFallMesh.build; [] with none), "falls_aabb": their bounds
## grown by the largest mist puff (ArrayMesh.custom_aabb)}.
@warning_ignore("integer_division")
static func build(doc: MapDocument) -> Dictionary:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var count := columns * rows
	var owner := sample_owners(doc)
	var levels := PackedFloat32Array()
	levels.resize(count)
	levels.fill(WaterGeometry.DRY)
	var wet := PackedByteArray()
	wet.resize(count)
	var heights := doc.heights
	for i in count:
		if owner[i] >= 0:
			levels[i] = doc.water_bodies[owner[i]].level_m
			if heights[i] < levels[i]:
				wet[i] = 1
	var cells := cell_owners(doc, owner, levels, wet)
	var out := {
		"arrays": [], "levels": levels, "wet": wet, "bodies": [], "falls": [], "falls_aabb": AABB()
	}
	if cells.is_empty():
		return out
	var buried := {}
	var sheets := cascades(doc, buried)
	var falls := WaterFalls.falls(doc)
	var tucked := fall_cells(doc, falls, wet)
	for i: int in tucked:
		if not sheets.has(i):
			sheets[i] = tucked[i]
	out["arrays"] = _arrays(doc, cells, sheets, owner, wet, buried)
	out["bodies"] = _bodies(doc, cells, wet, owner)
	var fall_mesh := WaterFallMesh.build(doc, falls)
	out["falls"] = fall_mesh.arrays
	out["falls_aabb"] = fall_mesh.aabb
	return out


## The cascade sheets over reach steps (see the header): sample index -> the sheet's height
## there, for every riffle sample between two joined reaches of `doc`'s rivers where the
## sheet stands over the ground. `buried`, when given, receives the sheet's height where it
## has sunk under the bank past the waterline (CASCADE_EDGE_SLOPE): the mesh's corners there,
## so the sheet's edge is where the ground cuts it, not the edge of its samples. A step that
## is a waterfall (WaterFalls.is_fall) gets no sheet (P4c-3: the curtain is WaterFallMesh's).
static func cascades(doc: MapDocument, buried: Dictionary = {}) -> Dictionary:
	var out := {}
	if doc.heights.size() != doc.sample_count():
		return out
	for a in doc.water_bodies:
		if not a.is_river() or a.points.size() < 2:
			continue
		for b in doc.water_bodies:
			if b == a or not b.is_river() or b.points.size() < 2 or b.level_m >= a.level_m:
				continue
			if a.points[-1].distance_squared_to(b.points[0]) < WaterGeometry.JOIN_EPSILON_SQ:
				if WaterFalls.is_fall(doc, a, b):
					continue
				_cascade(doc, a, b, out, buried)
		var joined := WaterGeometry.flush_ends(doc.water_bodies, a)
		if joined.x == 0:
			_run_out(doc, a, false, out, buried)
		if joined.y == 0:
			_run_out(doc, a, true, out, buried)
	for i: int in out:
		buried.erase(i)
	return out


## The lip cells of `falls` (WaterFalls.falls(doc); see the header): sample index -> height
## for the samples just downstream of each lip line (within LIP_TUCK_SAMPLES samples of it,
## within the channel and its banks across) that are not under water (`wet`), at
## CASCADE_TUCK_M under their ground. Merged into the sheets _arrays() draws, every flat cell
## straddling a lip line becomes a sheet cell: its upstream corners stay at the upper level
## (wet, the owner's level) and its downstream corners sink under the face.
static func fall_cells(
	doc: MapDocument, falls: Array[Dictionary], wet: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var out := {}
	if doc.heights.size() != doc.sample_count():
		return out
	var step := doc.sample_step()
	var reach := maxf(step.x, step.y) * LIP_TUCK_SAMPLES
	var last := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
	for fall in falls:
		var lip: Vector2 = fall.lip
		var direction: Vector2 = fall.dir
		if direction == Vector2.ZERO:
			continue
		var half := float(fall.half_width) + WaterGeometry.RIVER_BANK_M
		var box := Vector2.ONE * (half + reach)
		var first := doc.world_to_sample(lip - box).floor().clamp(Vector2.ZERO, last)
		var stop := doc.world_to_sample(lip + box).ceil().clamp(Vector2.ZERO, last)
		for z in range(int(first.y), int(stop.y) + 1):
			for x in range(int(first.x), int(stop.x) + 1):
				var p := doc.sample_to_world(Vector2(x, z))
				var along := (p - lip).dot(direction)
				if along <= 0.0 or along > reach or absf((p - lip).cross(direction)) > half:
					continue
				var i := doc.sample_index(x, z)
				if i < wet.size() and wet[i] != 0:
					continue
				out[i] = doc.heights[i] - CASCADE_TUCK_M
	return out


## The film a sheet keeps over its ground at edge offset `e` (metres past the carve's
## waterline, negative in the channel): CASCADE_FILM_M in the channel, thinning to nothing at
## the waterline and sinking to CASCADE_TUCK_M under the bank past it.
static func _edge_film(e: float) -> float:
	return clampf(-e * CASCADE_EDGE_SLOPE, -CASCADE_TUCK_M, CASCADE_FILM_M)


## How far past the waterline a sheet's samples reach: past the thinning, plus a sample.
static func _edge_reach(doc: MapDocument) -> float:
	var step := doc.sample_step()
	return CASCADE_TUCK_M / CASCADE_EDGE_SLOPE + maxf(step.x, step.y)


## Merges a sheet height at sample `i` over ground `ground` into `out` (over the ground) or
## `buried` (at or under it), the higher sheet winning.
static func _put_sheet(
	i: int, sheet: float, ground: float, out: Dictionary, buried: Dictionary
) -> void:
	var into := out if sheet > ground else buried
	into[i] = maxf(float(into.get(i, -INF)), sheet)


## A free river end (`at_end`: the last point, else the first) whose channel carries on
## below its level (a river cut in two by an erase: the terrain stays carved): the surface
## falls down the channel at RUN_OUT_SLOPE and trickles on over its bed as a film for
## RUN_OUT_FILM_M, instead of ending in the air. Nothing where the ground past the end stands
## above the level (a carved end tapers up to it). An end at the map edge stays at its level
## out to the edge: the river runs on past it (RiverExits).
static func _run_out(
	doc: MapDocument, body: WaterBody, at_end: bool, out: Dictionary, buried: Dictionary
) -> void:
	var course: PackedVector2Array = WaterGeometry.river_course(body)[0]
	var end := course[-1] if at_end else course[0]
	# An end in other water is a confluence (WaterEdit.join_line): the water carries on there.
	if WaterGeometry.is_wet_at(doc, end, body.id):
		return
	var outward := WaterGeometry.end_direction(course, at_end)
	if not at_end:
		outward = -outward
	var half := body.half_widths[-1] if at_end else body.half_widths[0]
	var level := body.level_m
	var reach := body.depth_m() / RUN_OUT_SLOPE + RUN_OUT_FILM_M
	var slope := RUN_OUT_SLOPE
	var gap := RiverExits.edge_distance(end, doc.extent_m() * 0.5)
	if gap <= WaterCarve.EDGE_MARGIN_M:
		# A river leaving the map (P6-1, RiverExits): it runs on past the edge at its level
		# (the skirt's ribbon), so the surface stays flat out to the edge instead of falling.
		slope = 0.0
		reach = gap + maxf(doc.sample_step().x, doc.sample_step().y) * 2.0
	var edge_reach := _edge_reach(doc)
	var near := _near(course, end, reach + half + edge_reach)
	var last := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
	var box := Vector2.ONE * (reach + half + edge_reach)
	var first := doc.world_to_sample(end - box).floor().clamp(Vector2.ZERO, last)
	var stop := doc.world_to_sample(end + box).ceil().clamp(Vector2.ZERO, last)
	var heights := doc.heights
	for z in range(int(first.y), int(stop.y) + 1):
		for x in range(int(first.x), int(stop.x) + 1):
			var p := doc.sample_to_world(Vector2(x, z))
			var along := (p - end).dot(outward)
			if along <= 0.0 or along > reach:
				continue
			# Lateral: from the line through the end along the course.
			var lateral := absf((p - end).cross(outward))
			if (
				lateral > half + edge_reach
				or WaterGeometry.nearest_on_polyline(near, p).x < along - 0.01
			):
				continue
			var i := doc.sample_index(x, z)
			var ground := heights[i]
			# Falling from the level, then a thin film trickling on down the channel's bed,
			# thinning to the waterline across the banks.
			var film := ground + _edge_film(lateral - half)
			var sheet := minf(maxf(level - along * slope, film), level)
			_put_sheet(i, sheet, ground, out, buried)


## The sheet of the step from reach `upper` into reach `lower`, merged into `out`.
static func _cascade(
	doc: MapDocument, upper: WaterBody, lower: WaterBody, out: Dictionary, buried: Dictionary
) -> void:
	var joint := upper.points[-1]
	var below: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	var above: PackedVector2Array = WaterGeometry.river_course(upper)[0]
	var direction := WaterGeometry.end_direction(below, false)
	var half := lower.half_widths[0]
	var edge_reach := _edge_reach(doc)
	var length := WaterCarve.riffle_length(upper.level_m, lower.level_m, lower.depth_m())
	var reach := length + half + edge_reach + CASCADE_BACK_M + 1.0
	# Only the course near the step can be nearest to its samples.
	var near_above := _near(above, joint, reach + half)
	var near_below := _near(below, joint, reach + half)
	var last := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
	var first := doc.world_to_sample(joint - Vector2(reach, reach)).floor().clamp(
		Vector2.ZERO, last
	)
	var end := doc.world_to_sample(joint + Vector2(reach, reach)).ceil().clamp(Vector2.ZERO, last)
	var heights := doc.heights
	var drop := upper.level_m - lower.level_m
	var run := maxf(drop / CASCADE_SLOPE, 0.5)
	for z in range(int(first.y), int(end.y) + 1):
		for x in range(int(first.x), int(end.x) + 1):
			var p := doc.sample_to_world(Vector2(x, z))
			var along := (p - joint).dot(direction)
			if along < -CASCADE_BACK_M or along > maxf(length, run) + 0.5:
				continue
			var lateral := minf(
				WaterGeometry.nearest_on_polyline(near_above, p).x,
				WaterGeometry.nearest_on_polyline(near_below, p).x
			)
			if lateral > half + edge_reach:
				continue
			var i := doc.sample_index(x, z)
			var ground := heights[i]
			if along < 0.0 and ground < upper.level_m:
				continue
			# The film over the riffle, thinning to the waterline across the banks, or at least
			# the surface falling from the upper level to the lower over `run` (a small step
			# over deep water; it meets the banks as a flat surface does).
			var ramp := lerpf(upper.level_m, lower.level_m, clampf(along / run, 0.0, 1.0))
			var film := clampf(ground + _edge_film(lateral - half), lower.level_m, upper.level_m)
			var sheet := maxf(film if ground >= lower.level_m else lower.level_m, ramp)
			if sheet <= lower.level_m + 0.005:
				continue
			_put_sheet(i, sheet, ground, out, buried)


## The run of `course`'s points within `radius` of `at` (with one more point on each side),
## a polyline; the whole course when none is near.
static func _near(course: PackedVector2Array, at: Vector2, radius: float) -> PackedVector2Array:
	var first := -1
	var last := -1
	for i in course.size():
		if course[i].distance_to(at) <= radius:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return course
	return course.slice(maxi(first - 1, 0), mini(last + 2, course.size()))


## The index into doc.water_bodies of the body owning each sample (the highest level among
## the bodies whose area holds it), -1 where none does.
static func sample_owners(doc: MapDocument) -> PackedInt32Array:
	var count := doc.sample_count()
	var owner := PackedInt32Array()
	owner.resize(count)
	owner.fill(-1)
	var best := PackedFloat32Array()
	best.resize(count)
	best.fill(WaterGeometry.DRY)
	for b in doc.water_bodies.size():
		var body := doc.water_bodies[b]
		for i in WaterGeometry.body_area(doc, body):
			if body.level_m > best[i]:
				best[i] = body.level_m
				owner[i] = b
	return owner


## Covered cells: {Vector2i(x, z) of the cell's lower corner -> body index} (see the
## header: covered by a wet corner, plus MARGIN_CELLS rings of tucked cells). Visits only
## the cells around wet samples.
@warning_ignore("integer_division")
static func cell_owners(
	doc: MapDocument, owner: PackedInt32Array, levels: PackedFloat32Array, wet: PackedByteArray
) -> Dictionary:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var cells := {}
	for i in wet.size():
		if wet[i] == 0:
			continue
		var sx := i % columns
		var sz := i / columns
		for z in range(maxi(sz - 1, 0), mini(sz, rows - 2) + 1):
			for x in range(maxi(sx - 1, 0), mini(sx, columns - 2) + 1):
				var cell := Vector2i(x, z)
				var current: int = cells.get(cell, -1)
				if current < 0 or levels[i] > doc.water_bodies[current].level_m:
					cells[cell] = owner[i]
	var ring := cells
	for _pass in MARGIN_CELLS:
		var added := {}
		for cell: Vector2i in ring:
			var body: int = ring[cell]
			var level := doc.water_bodies[body].level_m
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var next := cell + Vector2i(dx, dz)
					if next.x < 0 or next.y < 0 or next.x >= columns - 1 or next.y >= rows - 1:
						continue
					if cells.has(next) or added.has(next):
						continue
					if _tucked(doc.heights, next, columns, level):
						added[next] = body
		for cell in added:
			cells[cell] = added[cell]
		ring = added
	return cells


## Sample indices of cell (x, z)'s corners.
static func _corners(x: int, z: int, columns: int) -> PackedInt32Array:
	var a := z * columns + x
	return PackedInt32Array([a, a + 1, a + columns, a + columns + 1])


## True when every corner of `cell` has ground at or above `level` (the cell lies under the
## banks).
static func _tucked(
	heights: PackedFloat32Array, cell: Vector2i, columns: int, level: float
) -> bool:
	for i in _corners(cell.x, cell.y, columns):
		if heights[i] < level:
			return false
	return true


## The merged surface: one vertex per (sample, body) used, flat at the body's level, normal
## up, map-normalised UV; two triangles per cell, clockwise seen from above (Godot's front
## face, as TerrainMeshBuilder's chunks). Then the cascade sheets (`cascade`, cascades()):
## every cell with a sheet corner, in place of any flat cell there, its corners at the
## sheet's height, the owning body's level where the ground is under water, else tucked
## under the ground (at the sheet's own height where it has sunk under a bank, `buried`).
static func _arrays(
	doc: MapDocument,
	cells: Dictionary,
	cascade: Dictionary = {},
	owner: PackedInt32Array = PackedInt32Array(),
	wet: PackedByteArray = PackedByteArray(),
	buried: Dictionary = {}
) -> Array:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var vertex_of := {}
	# Cells with a cascade corner are drawn as the sheet (below), not flat.
	var sheet_cells := {}
	for i: int in cascade:
		@warning_ignore("integer_division")
		var sz := i / columns
		var sx := i - sz * columns
		for z in range(maxi(sz - 1, 0), mini(sz, rows - 2) + 1):
			for x in range(maxi(sx - 1, 0), mini(sx, columns - 2) + 1):
				sheet_cells[Vector2i(x, z)] = true
	var keys: Array = cells.keys()
	keys.sort()
	for cell: Vector2i in keys:
		if sheet_cells.has(cell):
			continue
		var body: int = cells[cell]
		var level := doc.water_bodies[body].level_m
		var quad := PackedInt32Array()
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var s: Vector2i = cell + corner
			var key := (s.y * columns + s.x) * 256 + body
			var v: int = vertex_of.get(key, -1)
			if v < 0:
				v = vertices.size()
				vertex_of[key] = v
				vertices.append(Vector3(s.x * step.x - half.x, level, s.y * step.y - half.y))
				normals.append(Vector3.UP)
				uvs.append(Vector2(float(s.x) / (columns - 1), float(s.y) / (rows - 1)))
			quad.append(v)
		indices.append_array(
			PackedInt32Array([quad[0], quad[1], quad[2], quad[1], quad[3], quad[2]])
		)
	var sheet_keys: Array = sheet_cells.keys()
	sheet_keys.sort()
	for cell: Vector2i in sheet_keys:
		var quad := PackedInt32Array()
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var s: Vector2i = cell + corner
			var at := s.y * columns + s.x
			var y := doc.heights[at] - CASCADE_TUCK_M
			var slot := TUCKED_KEY
			if cascade.has(at):
				y = cascade[at]
				slot = CASCADE_KEY
			elif at < wet.size() and wet[at] == 1 and owner[at] >= 0:
				y = doc.water_bodies[owner[at]].level_m
				slot = owner[at]
			elif buried.has(at):
				y = buried[at]
			var key := at * 256 + slot
			var v: int = vertex_of.get(key, -1)
			if v < 0:
				v = vertices.size()
				vertex_of[key] = v
				vertices.append(Vector3(s.x * step.x - half.x, y, s.y * step.y - half.y))
				normals.append(Vector3.UP)
				uvs.append(Vector2(float(s.x) / (columns - 1), float(s.y) / (rows - 1)))
			quad.append(v)
		indices.append_array(
			PackedInt32Array([quad[0], quad[1], quad[2], quad[1], quad[3], quad[2]])
		)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Per body with cells: its surface triangles and its zone tiles (the bounds of its cells
## with a wet corner, per ZONE_TILE_M tile; the tucked margin is dry land).
static func _bodies(
	doc: MapDocument, cells: Dictionary, wet: PackedByteArray, owner: PackedInt32Array
) -> Array:
	var columns := doc.samples_x()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var faces := {}
	var tiles := {}
	var keys: Array = cells.keys()
	keys.sort()
	for cell: Vector2i in keys:
		var body: int = cells[cell]
		var level := doc.water_bodies[body].level_m
		var p0 := Vector3(cell.x * step.x - half.x, level, cell.y * step.y - half.y)
		var p1 := p0 + Vector3(step.x, 0.0, 0.0)
		var p2 := p0 + Vector3(0.0, 0.0, step.y)
		var p3 := p0 + Vector3(step.x, 0.0, step.y)
		var list: PackedVector3Array = faces.get(body, PackedVector3Array())
		list.append_array(PackedVector3Array([p0, p1, p2, p1, p3, p2]))
		faces[body] = list
		var covered := false
		for i in _corners(cell.x, cell.y, columns):
			if wet[i] == 1 and owner[i] == body:
				covered = true
		if not covered:
			continue
		var rect := Rect2(p0.x, p0.z, step.x, step.y)
		var tile := Vector2i(
			floori((p0.x + half.x) / ZONE_TILE_M), floori((p0.z + half.y) / ZONE_TILE_M)
		)
		var per_body: Dictionary = tiles.get(body, {})
		per_body[tile] = (per_body[tile] as Rect2).merge(rect) if per_body.has(tile) else rect
		tiles[body] = per_body
	var out := []
	for body: int in faces:
		var water := doc.water_bodies[body]
		var body_tiles: Array[Rect2] = []
		var per_body: Dictionary = tiles.get(body, {})
		var tile_keys: Array = per_body.keys()
		tile_keys.sort()
		for tile in tile_keys:
			body_tiles.append(per_body[tile])
		(
			out
			. append(
				{
					"id": water.id,
					"level": water.level_m,
					"floats": not WaterBody.is_wadeable(water.depth),
					"faces": faces[body],
					"tiles": body_tiles,
				}
			)
		)
	return out


## A copy of the parts of `doc` build(), WaterFlowBaker.bake() and RiverExitMesh read (grid,
## seed, heights, water bodies, pond mask), safe to hand to a worker thread while `doc` keeps
## being edited.
static func snapshot(doc: MapDocument) -> MapDocument:
	var copy := MapDocument.new()
	copy.size_cells = doc.size_cells
	copy.cell_size_m = doc.cell_size_m
	copy.sample_spacing_m = doc.sample_spacing_m
	copy.map_seed = doc.map_seed
	copy.heights = doc.heights.duplicate()
	copy.pond_mask = doc.pond_mask.duplicate()
	var bodies: Array[WaterBody] = []
	for body in doc.water_bodies:
		bodies.append(body.copy())
	copy.water_bodies = bodies
	return copy
