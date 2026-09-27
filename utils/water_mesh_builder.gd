class_name WaterMeshBuilder
extends RefCounted

## The geometry of a map document's authored water (MapDocument.water_bodies), pure: one
## merged surface mesh for every body, the surface collision and WaterZone footprint of each
## body, and the per-sample water levels the ground height field raises the grid to.
## AuthoredWater turns it into nodes. Summary: docs/ARCHITECTURE.md "Authored water at
## runtime".
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

const MESH_NAME := "AuthoredWater-water"
## Rings of tucked cells added past the covered cells (see the header).
const MARGIN_CELLS := 1
## Side of the square tiles a body's WaterZone footprint is split into (metres).
const ZONE_TILE_M := 5.0

## The water of `doc`: {"arrays": Mesh arrays of the merged surface ([] with no water),
## "levels": PackedFloat32Array per sample (the owning body's level, WaterGeometry.DRY where
## no body's area holds the sample), "wet": PackedByteArray per sample (1 where the ground is
## below its level), "bodies": Array of {"id", "level", "floats" (bool), "faces"
## (PackedVector3Array, the body's triangles for its surface collision), "tiles" (Array of
## Rect2, map XZ, the WaterZone footprint)}, one per body with covered cells}.
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
	var out := {"arrays": [], "levels": levels, "wet": wet, "bodies": []}
	if cells.is_empty():
		return out
	out["arrays"] = _arrays(doc, cells)
	out["bodies"] = _bodies(doc, cells, wet, owner)
	return out


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
## face, as TerrainMeshBuilder's chunks).
static func _arrays(doc: MapDocument, cells: Dictionary) -> Array:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var vertex_of := {}
	var keys: Array = cells.keys()
	keys.sort()
	for cell: Vector2i in keys:
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


## A copy of the parts of `doc` build() and WaterFlowBaker.bake() read (grid, heights, water
## bodies, pond mask), safe to hand to a worker thread while `doc` keeps being edited.
static func snapshot(doc: MapDocument) -> MapDocument:
	var copy := MapDocument.new()
	copy.size_cells = doc.size_cells
	copy.cell_size_m = doc.cell_size_m
	copy.sample_spacing_m = doc.sample_spacing_m
	copy.heights = doc.heights.duplicate()
	copy.pond_mask = doc.pond_mask.duplicate()
	var bodies: Array[WaterBody] = []
	for body in doc.water_bodies:
		bodies.append(body.copy())
	copy.water_bodies = bodies
	return copy
