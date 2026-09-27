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

const CHUNK_SIZE_M := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
## Slack, in samples, for a sample that lands on a cell edge within float error: it
## counts as on the edge (ScatterChunker puts an edge point in the higher cell).
const EDGE_EPSILON_SAMPLES := 1e-4


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


## Mesh arrays (vertex, normal, UV, index) for one chunk, or [] when the cell is not part
## of the map. Vertices are in world space, so the chunk node sits at the identity and
## its AABB is the chunk's world bounds (camera bounds and the reflection probe read it).
static func build_chunk_arrays(doc: MapDocument, cell: Vector2i) -> Array:
	var rect := chunk_sample_rect(doc, cell)
	if rect.size == Vector2i.ZERO:
		return []
	var columns := rect.size.x + 1
	var rows := rect.size.y + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(columns * rows)
	normals.resize(columns * rows)
	uvs.resize(columns * rows)
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
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## One chunk as an ArrayMesh with `material` on its surface, or null when the cell is not
## part of the map.
static func build_chunk_mesh(doc: MapDocument, cell: Vector2i, material: Material) -> ArrayMesh:
	var arrays := build_chunk_arrays(doc, cell)
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## Mesh arrays (vertex, normal, UV, index) for the ground skirt: a ring around the map
## `width_m` wide, one quad per boundary sample step. Its inner edge is the map's boundary
## vertices exactly (same positions and heights as the chunks'), its outer edge those
## pushed straight out (diagonally at the corners, so the ring is a square annulus) at the
## same height. UVs are world XZ like the chunks', so the ground shader continues across
## the edge without a seam. Normals point up; every triangle faces +Y.
static func build_skirt_arrays(doc: MapDocument, width_m: float) -> Array:
	var loop := boundary_samples(doc)
	var count := loop.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(count * 2)
	normals.resize(count * 2)
	uvs.resize(count * 2)
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	for i in count:
		var sample := loop[i]
		var inner := sample_position(doc, sample.x, sample.y)
		var out := Vector3(
			-1.0 if sample.x == 0 else (1.0 if sample.x == last.x else 0.0),
			0.0,
			-1.0 if sample.y == 0 else (1.0 if sample.y == last.y else 0.0)
		)
		var outer := inner + out * width_m
		vertices[i] = inner
		vertices[count + i] = outer
		normals[i] = Vector3.UP
		normals[count + i] = Vector3.UP
		uvs[i] = Vector2(inner.x, inner.z)
		uvs[count + i] = Vector2(outer.x, outer.z)
	var indices := PackedInt32Array()
	indices.resize(count * 6)
	for i in count:
		var j := (i + 1) % count
		_add_up_triangle(indices, i * 6, vertices, i, j, count + j)
		_add_up_triangle(indices, i * 6 + 3, vertices, i, count + j, count + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


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
