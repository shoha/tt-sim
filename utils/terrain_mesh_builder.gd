class_name TerrainMeshBuilder
extends RefCounted

## Pure geometry for AuthoredTerrain: which 10 m chunk cells a MapDocument covers, which
## samples each chunk owns, the chunk meshes themselves and the collision heightfield's
## placement. No nodes and no side effects, so every seam rule is unit-testable headless.
##
## Chunks are ScatterChunker cells (CHUNK_SIZE_WORLD_UNITS on X and Z, cell = floor(p /
## size)), so a sculpt brush and scatter regeneration in phase 3 share one set of keys.
## The document's sample grid is not aligned to those cells (200 ft at 0.25 m nominal is a
## 0.24984 m step starting at -30.48 m), so a chunk cannot own "the samples from x0 to
## x0 + 40". Instead a chunk owns the sample columns from the first sample at or past its
## lower cell edge to the first sample at or past its upper edge, inclusive. Both ends use
## the same formula (first_sample_at), so a chunk's last column is exactly its
## neighbour's first: the two meshes share those vertices bit for bit and cannot crack.
## A chunk therefore reaches up to one sample step past its cell, which is harmless for
## culling and invisible on screen.
##
## Normals are central differences on the whole document grid, not the chunk, so the
## border vertices two chunks share get the same normal from both and lighting has no
## seam. At the map edge the difference is one-sided.
##
## UVs are world XZ in metres; the ground shader divides by each surface's tile size.
## UV2 carries the automatic dressing's per-vertex fields (phase 3, P3-4): x the curvature
## and y the steepness nearby of TerrainRules.sample_fields(), which read heights up to
## TerrainRules.CURVATURE_RADIUS_M away, so a height edit changes them that far out.

const CHUNK_SIZE_M := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
## Slack, in samples, for a sample that lands on a cell edge within float error: it
## counts as on the edge (ScatterChunker puts an edge point in the higher cell).
const EDGE_EPSILON_SAMPLES := 1e-4
## Rings of the ground skirt past its inner edge (build_skirt_arrays), spaced closer near
## the map where the fall-off curves most.
const SKIRT_RINGS := 8
const SKIRT_RING_SPACING_POWER := 1.5


## Index of the first sample at or past world coordinate `edge_m` on an axis of `samples`
## samples with the given `step_m`, whose first sample sits at `-extent_m / 2`. Clamped to
## the grid.
static func first_sample_at(edge_m: float, extent_m: float, step_m: float, samples: int) -> int:
	var continuous := (edge_m + extent_m * 0.5) / step_m
	return clampi(ceili(continuous - EDGE_EPSILON_SAMPLES), 0, samples - 1)


## Inclusive sample range [first, last] of the chunk in `cell_index` along one axis, or
## Vector2i(-1, -1) when the cell holds less than one sample step of the map.
static func axis_range(cell_index: int, extent_m: float, step_m: float, samples: int) -> Vector2i:
	var first := first_sample_at(cell_index * CHUNK_SIZE_M, extent_m, step_m, samples)
	var last := first_sample_at((cell_index + 1) * CHUNK_SIZE_M, extent_m, step_m, samples)
	if last <= first:
		return Vector2i(-1, -1)
	return Vector2i(first, last)


## The chunk's samples as Rect2i(first_x, first_z, columns - 1, rows - 1): position is the
## first sample and end is the last one, both inclusive. Size zero when the cell is not
## part of the map.
static func chunk_sample_rect(doc: MapDocument, cell: Vector2i) -> Rect2i:
	var extent := doc.extent_m()
	var step := doc.sample_step()
	var xs := axis_range(cell.x, extent.x, step.x, doc.samples_x())
	var zs := axis_range(cell.y, extent.y, step.y, doc.samples_z())
	if xs.x < 0 or zs.x < 0:
		return Rect2i()
	return Rect2i(xs.x, zs.x, xs.y - xs.x, zs.y - zs.x)


## Every chunk cell that holds part of the map, row by row (Z then X).
static func chunk_cells(doc: MapDocument) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var half := doc.extent_m() * 0.5
	var low := Vector2i(floori(-half.x / CHUNK_SIZE_M), floori(-half.y / CHUNK_SIZE_M))
	var high := Vector2i(floori(half.x / CHUNK_SIZE_M), floori(half.y / CHUNK_SIZE_M))
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x, z)
			if chunk_sample_rect(doc, cell).size != Vector2i.ZERO:
				cells.append(cell)
	return cells


## The document height at sample (x, z), or 0 when heights are missing (a malformed or
## still-empty document renders flat rather than failing).
static func height_at(doc: MapDocument, x: int, z: int) -> float:
	var index := doc.sample_index(x, z)
	return doc.heights[index] if index < doc.heights.size() else 0.0


## World position of sample (x, z).
static func sample_position(doc: MapDocument, x: int, z: int) -> Vector3:
	var xz := doc.sample_to_world(Vector2(x, z))
	return Vector3(xz.x, height_at(doc, x, z), xz.y)


## Smooth normal at sample (x, z) from central differences on the whole document grid
## (one-sided at the map edge), so every chunk computes the same normal for a shared
## vertex.
static func sample_normal(doc: MapDocument, x: int, z: int) -> Vector3:
	var step := doc.sample_step()
	var x0 := maxi(x - 1, 0)
	var x1 := mini(x + 1, doc.samples_x() - 1)
	var z0 := maxi(z - 1, 0)
	var z1 := mini(z + 1, doc.samples_z() - 1)
	var slope_x := (height_at(doc, x1, z) - height_at(doc, x0, z)) / ((x1 - x0) * step.x)
	var slope_z := (height_at(doc, x, z1) - height_at(doc, x, z0)) / ((z1 - z0) * step.y)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()


## The rule fields (TerrainRules.sample_fields) of the whole grid of `doc`:
## {"curvature": PackedFloat32Array, "steep": PackedFloat32Array}, one value per sample.
static func grid_fields(doc: MapDocument) -> Dictionary:
	var fields := TerrainRules.sample_fields(
		collision_heights(doc),
		doc.samples_x(),
		doc.samples_z(),
		doc.sample_step(),
		Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	)
	return {"curvature": fields.curvature, "steep": fields.steep}


## Mesh arrays (vertex, normal, UV, UV2, index) for one chunk, or [] when the cell is not
## part of the map. Vertices are in world space, so the chunk node sits at the identity and
## its AABB is the chunk's world bounds (camera bounds and the reflection probe read it).
## `fields` is grid_fields() of the document (computed for the chunk alone when empty).
static func build_chunk_arrays(doc: MapDocument, cell: Vector2i, fields: Dictionary = {}) -> Array:
	var rect := chunk_sample_rect(doc, cell)
	if rect.size == Vector2i.ZERO:
		return []
	var columns := rect.size.x + 1
	var rows := rect.size.y + 1
	if fields.is_empty():
		fields = _local_fields(doc, Rect2i(rect.position, Vector2i(columns, rows)))
	var curvature: PackedFloat32Array = fields.curvature
	var steep: PackedFloat32Array = fields.steep
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	vertices.resize(columns * rows)
	normals.resize(columns * rows)
	uvs.resize(columns * rows)
	uv2s.resize(columns * rows)
	# The hot loop inlines sample_position() and sample_normal() (same arithmetic, same
	# results): the per-vertex helper calls cost about 10x the rest of the build.
	var heights := collision_heights(doc)
	var width := doc.samples_x()
	var depth := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	for row in rows:
		var sz := rect.position.y + row
		var z_m := sz * step.y - half.y
		var z0 := maxi(sz - 1, 0)
		var z1 := mini(sz + 1, depth - 1)
		var inv_dz := 1.0 / ((z1 - z0) * step.y)
		for column in columns:
			var sx := rect.position.x + column
			var x0 := maxi(sx - 1, 0)
			var x1 := mini(sx + 1, width - 1)
			var here := sz * width
			var slope_x := (heights[here + x1] - heights[here + x0]) / ((x1 - x0) * step.x)
			var slope_z := (heights[z1 * width + sx] - heights[z0 * width + sx]) * inv_dz
			var i := row * columns + column
			var x_m := sx * step.x - half.x
			vertices[i] = Vector3(x_m, heights[here + sx], z_m)
			normals[i] = Vector3(-slope_x, 1.0, -slope_z).normalized()
			uvs[i] = Vector2(x_m, z_m)
			uv2s[i] = Vector2(curvature[here + sx], steep[here + sx])
	var indices := PackedInt32Array()
	indices.resize((columns - 1) * (rows - 1) * 6)
	var k := 0
	for row in rows - 1:
		for column in columns - 1:
			# Clockwise seen from above: Godot's front face, so the ground faces +Y.
			var a := row * columns + column
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + columns
			indices[k + 3] = a + 1
			indices[k + 4] = a + columns + 1
			indices[k + 5] = a + columns
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## grid_fields()-shaped arrays (whole-grid size, zero outside) holding the fields of `rect`
## only: what a chunk built on its own needs.
static func _local_fields(doc: MapDocument, rect: Rect2i) -> Dictionary:
	var curvature := PackedFloat32Array()
	var steep := PackedFloat32Array()
	curvature.resize(doc.sample_count())
	steep.resize(doc.sample_count())
	var fields := TerrainRules.sample_fields(
		collision_heights(doc), doc.samples_x(), doc.samples_z(), doc.sample_step(), rect
	)
	TerrainRules.store_fields(fields, doc.samples_x(), curvature, steep)
	return {"curvature": curvature, "steep": steep}


## The vertex stream of a chunk as ArrayMesh stores it, kept on the CPU so a height edit can
## rewrite only the rows it touched with ArrayMesh.surface_update_vertex_region() instead
## of rebuilding the chunk. Layout (Godot 4.7, uncompressed vertex + normal + UV + index
## surface, verified against RenderingServer.mesh_get_surface() in test_height_sculpt.gd):
## the vertex buffer holds every position as three floats (12 bytes per vertex), then every
## normal and tangent as two octahedral 16-bit pairs (8 bytes per vertex); UVs live in the
## separate attribute buffer and never change. Returns {"rect": chunk_sample_rect(),
## "columns", "rows", "positions": PackedFloat32Array (x, y, z per vertex), "normals":
## PackedInt32Array (normal, tangent per vertex), "attributes": PackedFloat32Array (the
## attribute stream: UV then UV2, interleaved, four floats per vertex; verified the same
## way)}, or {} when the cell is not on the map. `fields` is grid_fields() (computed for
## the chunk alone when empty).
static func chunk_vertex_mirror(
	doc: MapDocument, cell: Vector2i, fields: Dictionary = {}
) -> Dictionary:
	var rect := chunk_sample_rect(doc, cell)
	if rect.size == Vector2i.ZERO:
		return {}
	var columns := rect.size.x + 1
	var rows := rect.size.y + 1
	var owned := Rect2i(rect.position, Vector2i(columns, rows))
	if fields.is_empty():
		fields = _local_fields(doc, owned)
	var positions := PackedFloat32Array()
	positions.resize(columns * rows * 3)
	var attributes := PackedFloat32Array()
	attributes.resize(columns * rows * 4)
	var half := doc.extent_m() * 0.5
	var step := doc.sample_step()
	for row in rows:
		var z_m := (rect.position.y + row) * step.y - half.y
		for column in columns:
			var i := (row * columns + column) * 3
			var x_m := (rect.position.x + column) * step.x - half.x
			positions[i] = x_m
			positions[i + 2] = z_m
			var a := (row * columns + column) * 4
			attributes[a] = x_m
			attributes[a + 1] = z_m
	var normals := PackedInt32Array()
	normals.resize(columns * rows * 2)
	var mirror := {
		"rect": rect,
		"columns": columns,
		"rows": rows,
		"positions": positions,
		"normals": normals,
		"attributes": attributes,
	}
	write_vertex_region(doc, mirror, owned)
	write_attribute_region(mirror, owned, fields, doc.samples_x())
	return mirror


## Copies the rule fields of the samples of `part` (grid coordinates, clipped to the chunk)
## from whole-grid `fields` (grid_fields() layout, `grid_columns` wide) into a mirror's
## attribute stream (UV2).
static func write_attribute_region(
	mirror: Dictionary, part: Rect2i, fields: Dictionary, grid_columns: int
) -> void:
	var rect: Rect2i = mirror.rect
	var columns: int = mirror.columns
	var region := part.intersection(Rect2i(rect.position, Vector2i(columns, mirror.rows)))
	if not region.has_area():
		return
	var attributes: PackedFloat32Array = mirror.attributes
	var curvature: PackedFloat32Array = fields.curvature
	var steep: PackedFloat32Array = fields.steep
	for sz in range(region.position.y, region.end.y):
		var base := (sz - rect.position.y) * columns - rect.position.x
		var here := sz * grid_columns
		for sx in range(region.position.x, region.end.x):
			var a := (base + sx) * 4
			attributes[a + 2] = curvature[here + sx]
			attributes[a + 3] = steep[here + sx]


## The bytes of mirror rows `first_row`..`last_row` of the attribute stream (UV and UV2,
## 16 bytes per vertex) for surface_update_attribute_region(): {"attributes": bytes,
## "attribute_offset": int}.
static func attribute_rows_bytes(mirror: Dictionary, first_row: int, last_row: int) -> Dictionary:
	var columns: int = mirror.columns
	var attributes: PackedFloat32Array = mirror.attributes
	return {
		"attributes":
		attributes.slice(first_row * columns * 4, (last_row + 1) * columns * 4).to_byte_array(),
		"attribute_offset": first_row * columns * 16,
	}


## Rewrites the heights and normals of the samples of `part` (grid coordinates, clipped to
## the chunk) in a chunk_vertex_mirror() from the document's current heights. Normals use
## the same whole-grid central differences as build_chunk_arrays(), so an updated chunk is
## bit-identical to a rebuilt one. Returns Vector2(lowest, highest) height written, or
## Vector2(INF, -INF) when `part` misses the chunk.
static func write_vertex_region(doc: MapDocument, mirror: Dictionary, part: Rect2i) -> Vector2:
	var rect: Rect2i = mirror.rect
	var columns: int = mirror.columns
	var owned := Rect2i(rect.position, Vector2i(columns, mirror.rows))
	var region := part.intersection(owned)
	var span := Vector2(INF, -INF)
	if not region.has_area():
		return span
	var positions: PackedFloat32Array = mirror.positions
	var normals: PackedInt32Array = mirror.normals
	var heights := collision_heights(doc)
	var width := doc.samples_x()
	var depth := doc.samples_z()
	var step := doc.sample_step()
	# Inlined like build_chunk_arrays(): per-vertex helper calls dominate otherwise.
	for sz in range(region.position.y, region.end.y):
		var z0 := maxi(sz - 1, 0)
		var z1 := mini(sz + 1, depth - 1)
		var inv_dz := 1.0 / ((z1 - z0) * step.y)
		var here := sz * width
		var base := (sz - rect.position.y) * columns - rect.position.x
		for sx in range(region.position.x, region.end.x):
			var x0 := maxi(sx - 1, 0)
			var x1 := mini(sx + 1, width - 1)
			var h := heights[here + sx]
			var slope_x := (heights[here + x1] - heights[here + x0]) / ((x1 - x0) * step.x)
			var slope_z := (heights[z1 * width + sx] - heights[z0 * width + sx]) * inv_dz
			var n := Vector3(-slope_x, 1.0, -slope_z).normalized()
			var i := base + sx
			positions[i * 3 + 1] = h
			# Vector2 arithmetic is single precision, like the engine's encoder; doubles
			# round differently on about one vertex in four hundred.
			var e := n.octahedron_encode() * 65535.0
			normals[i * 2] = int(e.x) | (int(e.y) << 16)
			# The tangent Godot generates for a surface without one (see encode_tangent).
			var t := Vector3(n.z, -n.x, n.y).cross(n).normalized().octahedron_encode()
			t = (t * Vector2(1.0, 0.5) + Vector2(0.0, 0.5)) * 65535.0
			normals[i * 2 + 1] = int(t.x) | (int(t.y) << 16)
			span.x = minf(span.x, h)
			span.y = maxf(span.y, h)
	return span


## A unit normal as the vertex buffer stores it: octahedral, two 16-bit unorm halves
## (x low, y high).
static func encode_normal(n: Vector3) -> int:
	var e := n.octahedron_encode() * 65535.0
	return int(e.x) | (int(e.y) << 16)


## The tangent Godot writes for a surface given normals but no tangents: the normal's
## (z, -x, y) crossed with the normal, octahedral with the bitangent sign folded into y
## (positive).
static func encode_tangent(n: Vector3) -> int:
	var t := Vector3(n.z, -n.x, n.y).cross(n).normalized().octahedron_encode()
	t = (t * Vector2(1.0, 0.5) + Vector2(0.0, 0.5)) * 65535.0
	return int(t.x) | (int(t.y) << 16)


## The bytes of mirror rows `first_row`..`last_row` (chunk-local, inclusive) for
## surface_update_vertex_region(): {"positions": bytes at "position_offset", "normals":
## bytes at "normal_offset"}. Whole rows, so one call per stream covers any edited part.
static func vertex_rows_bytes(mirror: Dictionary, first_row: int, last_row: int) -> Dictionary:
	var columns: int = mirror.columns
	var count: int = columns * int(mirror.rows)
	var positions: PackedFloat32Array = mirror.positions
	var normals: PackedInt32Array = mirror.normals
	return {
		"positions":
		positions.slice(first_row * columns * 3, (last_row + 1) * columns * 3).to_byte_array(),
		"position_offset": first_row * columns * 12,
		"normals":
		normals.slice(first_row * columns * 2, (last_row + 1) * columns * 2).to_byte_array(),
		"normal_offset": count * 12 + first_row * columns * 8,
	}


## One chunk as an ArrayMesh with `material` on its surface, or null when the cell is not
## part of the map.
static func build_chunk_mesh(
	doc: MapDocument, cell: Vector2i, material: Material, fields: Dictionary = {}
) -> ArrayMesh:
	return mesh_of(build_chunk_arrays(doc, cell, fields), material)


## The chunk mesh of build_chunk_arrays() output `arrays` (null when empty) with `material`:
## the main-thread half, when a worker built the arrays (AuthoredLoadPrep).
static func mesh_of(arrays: Array, material: Material) -> ArrayMesh:
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## The skirt's height `distance_m` past the map edge where the map's boundary height is
## `edge_y`: back down to the base level (0, the map floor) over `fall_m`, eased at both
## ends (smoothstep) so the ground rolls off the edge and settles instead of carrying a
## raised edge straight out into the backdrop. Pure.
static func skirt_height(edge_y: float, distance_m: float, fall_m: float) -> float:
	var t := clampf(distance_m / maxf(fall_m, 1e-4), 0.0, 1.0)
	return edge_y * (1.0 - t * t * (3.0 - 2.0 * t))


## d skirt_height / d distance.
static func _skirt_slope(edge_y: float, distance_m: float, fall_m: float) -> float:
	var fall := maxf(fall_m, 1e-4)
	var t := clampf(distance_m / fall, 0.0, 1.0)
	return -edge_y * 6.0 * t * (1.0 - t) / fall


## Mesh arrays (vertex, normal, UV, index) for the ground skirt: a ring around the map
## `width_m` wide, one quad per boundary sample step and ring. Its inner edge is the map's
## boundary vertices exactly (same positions and heights as the chunks'); SKIRT_RINGS rings
## step out from them (diagonally at the corners, so each ring is a square annulus) with
## the height falling back to the map floor over `fall_m` (skirt_height; `fall_m` <= 0 means
## `width_m`), so a raised or sunken edge rolls off into the base level. UVs are world XZ
## like the chunks', so the ground shader continues across the edge without a seam. Normals
## follow the fall-off; every triangle faces +Y. Vertex r * count + i is ring r's copy of
## boundary sample i (ring 0 is the inner edge).
static func build_skirt_arrays(doc: MapDocument, width_m: float, fall_m: float = -1.0) -> Array:
	var loop := boundary_samples(doc)
	var count := loop.size()
	var rings := SKIRT_RINGS + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(count * rings)
	normals.resize(count * rings)
	uvs.resize(count * rings)
	for i in count:
		for r in rings:
			var v := skirt_vertex(doc, loop[i], r, width_m, fall_m)
			var k := r * count + i
			vertices[k] = v[0]
			normals[k] = v[1]
			uvs[k] = Vector2(v[0].x, v[0].z)
	var indices := PackedInt32Array()
	indices.resize(count * SKIRT_RINGS * 6)
	for r in SKIRT_RINGS:
		var inner_ring := r * count
		var outer_ring := (r + 1) * count
		for i in count:
			var j := (i + 1) % count
			var at := (r * count + i) * 6
			_add_up_triangle(indices, at, vertices, inner_ring + i, inner_ring + j, outer_ring + j)
			_add_up_triangle(
				indices, at + 3, vertices, inner_ring + i, outer_ring + j, outer_ring + i
			)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Ring `ring` of the skirt for boundary sample `sample`: [position, normal] (see
## build_skirt_arrays; `fall_m` <= 0 means `width_m`). Its XZ never depends on heights, so
## the skirt's triangles and UVs stay fixed while an edit moves the edge.
static func skirt_vertex(
	doc: MapDocument, sample: Vector2i, ring: int, width_m: float, fall_m: float
) -> Array:
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	var fall := fall_m if fall_m > 0.0 else width_m
	var inner := sample_position(doc, sample.x, sample.y)
	var out := Vector3(
		-1.0 if sample.x == 0 else (1.0 if sample.x == last.x else 0.0),
		0.0,
		-1.0 if sample.y == 0 else (1.0 if sample.y == last.y else 0.0)
	)
	var along := out.normalized()
	var distance := width_m * pow(float(ring) / SKIRT_RINGS, SKIRT_RING_SPACING_POWER)
	var point := inner + out * distance
	point.y = skirt_height(inner.y, distance, fall)
	var slope := _skirt_slope(inner.y, distance, fall)
	return [point, Vector3(-along.x * slope, 1.0, -along.z * slope).normalized()]


## Ranges [start, end) of boundary loop indices (boundary_samples order) whose samples lie
## in `rect` (grid coordinates).
static func skirt_ranges(doc: MapDocument, rect: Rect2i) -> Array[Vector2i]:
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	var ranges: Array[Vector2i] = []
	var lo := rect.position
	var hi := rect.end - Vector2i.ONE
	if lo.y <= 0 and hi.y >= 0:
		var a := maxi(lo.x, 0)
		var b := mini(hi.x, last.x - 1)
		if a <= b:
			ranges.append(Vector2i(a, b + 1))
	if lo.x <= last.x and hi.x >= last.x:
		var a := maxi(lo.y, 0)
		var b := mini(hi.y, last.y - 1)
		if a <= b:
			ranges.append(Vector2i(last.x + a, last.x + b + 1))
	if lo.y <= last.y and hi.y >= last.y:
		var a := maxi(lo.x, 1)
		var b := mini(hi.x, last.x)
		if a <= b:
			var base := last.x + last.y
			ranges.append(Vector2i(base + last.x - b, base + last.x - a + 1))
	if lo.x <= 0 and hi.x >= 0:
		var a := maxi(lo.y, 1)
		var b := mini(hi.y, last.y)
		if a <= b:
			var base := 2 * last.x + last.y
			ranges.append(Vector2i(base + last.y - b, base + last.y - a + 1))
	return ranges


## A CPU copy of the skirt's vertex stream (positions, then octahedral normal and tangent
## pairs: the layout chunk_vertex_mirror documents) for in-place edge updates:
## {"count": boundary samples, "positions", "normals"}.
static func skirt_vertex_mirror(doc: MapDocument, width_m: float, fall_m: float) -> Dictionary:
	var count := boundary_samples(doc).size()
	var positions := PackedFloat32Array()
	var normals := PackedInt32Array()
	positions.resize(count * (SKIRT_RINGS + 1) * 3)
	normals.resize(count * (SKIRT_RINGS + 1) * 2)
	var mirror := {"count": count, "positions": positions, "normals": normals}
	write_skirt_region(doc, mirror, Vector2i(0, count), width_m, fall_m)
	return mirror


## Rewrites loop indices [range.x, range.y) of every ring in a skirt_vertex_mirror() from the
## document's current boundary heights.
static func write_skirt_region(
	doc: MapDocument, mirror: Dictionary, indices: Vector2i, width_m: float, fall_m: float
) -> void:
	var loop := boundary_samples(doc)
	var count: int = mirror.count
	var positions: PackedFloat32Array = mirror.positions
	var normals: PackedInt32Array = mirror.normals
	for i in range(indices.x, indices.y):
		for r in SKIRT_RINGS + 1:
			var v := skirt_vertex(doc, loop[i], r, width_m, fall_m)
			var k := r * count + i
			var p: Vector3 = v[0]
			positions[k * 3] = p.x
			positions[k * 3 + 1] = p.y
			positions[k * 3 + 2] = p.z
			normals[k * 2] = encode_normal(v[1])
			normals[k * 2 + 1] = encode_tangent(v[1])


## The samples on the map's boundary as one closed loop, each once: along z = 0, up x = last,
## back along z = last, down x = 0.
static func boundary_samples(doc: MapDocument) -> Array[Vector2i]:
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	var loop: Array[Vector2i] = []
	for x in range(0, last.x):
		loop.append(Vector2i(x, 0))
	for z in range(0, last.y):
		loop.append(Vector2i(last.x, z))
	for x in range(last.x, 0, -1):
		loop.append(Vector2i(x, last.y))
	for z in range(last.y, 0, -1):
		loop.append(Vector2i(0, z))
	return loop


## Writes triangle (a, b, c) at `at`, reordered if needed so it faces +Y (Godot's front
## face is clockwise seen from the front, the chunks' convention).
static func _add_up_triangle(
	indices: PackedInt32Array, at: int, vertices: PackedVector3Array, a: int, b: int, c: int
) -> void:
	var facing := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).y
	indices[at] = a
	indices[at + 1] = b if facing < 0.0 else c
	indices[at + 2] = c if facing < 0.0 else b


## Where a ray (map frame; `direction` need not be unit length) first meets the terrain
## surface, the same triangles the chunks draw and the collision uses, within
## `max_distance`: {"position": Vector3, "normal": Vector3 (the triangle's, facing up),
## "distance": float}, or {} for a miss. `height_span` (lowest, highest ground; anything that
## encloses them) clips the ray to the slab the surface lives in, so only the quads under
## that part of the ray are tested, walked in order (Amanatides-Woo over the sample grid):
## a few dozen quads for a camera ray, well under a tenth of a millisecond. This is how the
## sculpt brush finds the ground it is shaping while the collision still has the heights of
## the stroke's start.
static func raycast(
	doc: MapDocument, origin: Vector3, direction: Vector3, max_distance: float, height_span: Vector2
) -> Dictionary:
	var dir := direction.normalized()
	if dir == Vector3.ZERO:
		return {}
	var heights := collision_heights(doc)
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var low := Vector3(-half.x, height_span.x - 0.01, -half.y)
	var high := Vector3(half.x, height_span.y + 0.01, half.y)
	var t0 := 0.0
	var t1 := max_distance
	for axis in 3:
		if absf(dir[axis]) < 1e-9:
			if origin[axis] < low[axis] or origin[axis] > high[axis]:
				return {}
			continue
		var ta := (low[axis] - origin[axis]) / dir[axis]
		var tb := (high[axis] - origin[axis]) / dir[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return {}
	var start := origin + dir * t0
	var sx := (start.x + half.x) / step.x
	var sz := (start.z + half.y) / step.y
	var ix := clampi(floori(sx), 0, columns - 2)
	var iz := clampi(floori(sz), 0, rows - 2)
	var dsx := dir.x / step.x
	var dsz := dir.z / step.y
	var next_x := INF
	var next_z := INF
	var delta_x := INF
	var delta_z := INF
	if absf(dsx) > 1e-12:
		next_x = t0 + (ix + (1 if dsx > 0.0 else 0) - sx) / dsx
		delta_x = 1.0 / absf(dsx)
	if absf(dsz) > 1e-12:
		next_z = t0 + (iz + (1 if dsz > 0.0 else 0) - sz) / dsz
		delta_z = 1.0 / absf(dsz)
	for _quad in (columns + rows) * 2:
		var hit := _quad_hit(heights, columns, ix, iz, step, half, origin, dir)
		if not hit.is_empty() and float(hit.distance) <= t1 + 0.001:
			return hit
		if next_x < next_z:
			if next_x > t1:
				break
			ix += 1 if dsx > 0.0 else -1
			next_x += delta_x
		else:
			if next_z > t1:
				break
			iz += 1 if dsz > 0.0 else -1
			next_z += delta_z
		if ix < 0 or iz < 0 or ix > columns - 2 or iz > rows - 2:
			break
	return {}


## The nearest hit of the ray with the two triangles of quad (ix, iz), or {}.
static func _quad_hit(
	heights: PackedFloat32Array,
	columns: int,
	ix: int,
	iz: int,
	step: Vector2,
	half: Vector2,
	origin: Vector3,
	dir: Vector3
) -> Dictionary:
	var i := iz * columns + ix
	var x0 := ix * step.x - half.x
	var z0 := iz * step.y - half.y
	var a := Vector3(x0, heights[i], z0)
	var b := Vector3(x0 + step.x, heights[i + 1], z0)
	var c := Vector3(x0, heights[i + columns], z0 + step.y)
	var d := Vector3(x0 + step.x, heights[i + columns + 1], z0 + step.y)
	var best := {}
	for triangle in [[a, b, c], [b, d, c]]:
		var p: Vector3 = triangle[0]
		var e1: Vector3 = triangle[1] - p
		var e2: Vector3 = triangle[2] - p
		var pv := dir.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var inv := 1.0 / det
		var tv := origin - p
		var u := tv.dot(pv) * inv
		if u < -1e-6 or u > 1.0 + 1e-6:
			continue
		var qv := tv.cross(e1)
		var v := dir.dot(qv) * inv
		if v < -1e-6 or u + v > 1.0 + 1e-6:
			continue
		var t := e2.dot(qv) * inv
		if t < 0.0 or (not best.is_empty() and t >= float(best.distance)):
			continue
		var normal := e1.cross(e2).normalized()
		if normal.y < 0.0:
			normal = -normal
		best = {"position": origin + dir * t, "normal": normal, "distance": t}
	return best


## Heights for a HeightMapShape3D over the whole grid: the document heights when they
## match the grid, else a flat field of the right size.
static func collision_heights(doc: MapDocument) -> PackedFloat32Array:
	if doc.heights.size() == doc.sample_count():
		return doc.heights
	var flat := PackedFloat32Array()
	flat.resize(doc.sample_count())
	return flat


## Transform for the node carrying the collision HeightMapShape3D. The shape puts sample
## (i, j) at local (i - (w - 1) / 2, h, j - (d - 1) / 2), one unit apart and centred on its
## origin; the document is centred on the world origin too, so scaling X and Z by the real
## sample step lands every sample on doc.sample_to_world() exactly. Y is not scaled, so
## heights stay in metres.
static func collision_transform(doc: MapDocument) -> Transform3D:
	var step := doc.sample_step()
	return Transform3D(Basis.from_scale(Vector3(step.x, 1.0, step.y)), Vector3.ZERO)


## The document's heights as a one-channel 32-bit float image, texel (x, z) = sample (x, z)
## (AuthoredTerrain.get_height_texture, which the grid overlay reads).
static func height_image(doc: MapDocument) -> Image:
	return Image.create_from_data(
		doc.samples_x(),
		doc.samples_z(),
		false,
		Image.FORMAT_RF,
		collision_heights(doc).to_byte_array()
	)


## The ground height (world Y) at world XZ `world_xz` of a terrain for `doc` placed by
## `to_world` (the level's map scale and offset), on the triangles the mesh and the collision
## share (ScatterGenerator.triangle_height). Past the map edge it continues the edge heights.
static func world_ground_height(
	doc: MapDocument, to_world: Transform3D, world_xz: Vector2
) -> float:
	var local := to_world.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	var at := doc.world_to_sample(Vector2(local.x, local.z))
	var h := ScatterGenerator.triangle_height(
		collision_heights(doc), doc.samples_x(), doc.samples_z(), at
	)
	return (to_world * Vector3(local.x, h, local.z)).y
