class_name StructureGlow
extends RefCounted

## The soft warm halo round a lantern (topic looks3, 2026-10-31; docs/systems/structures.md "Lantern
## glow"). A prop's lantern is a small box of `glass` (procgen's lamp_post, the wayside shrine's
## light): lit and unshaded it was a flat cream box with no glow in daylight, because the
## environment's glow threshold only lifts what is very bright against a dark sky. The halo is drawn
## instead: one quad per lantern, four vertices at the pane's centre, its corner in the UV (-1 or 1
## each way) and its half-size in metres in the second UV set's x, which structure_glow.gdshader
## turns into a camera-facing, alpha-soft disc. No light node, no extra texture; two triangles per
## lamp. The quads are NOT in StructureGeometry's `meshes` (so digests, budgets and every test of a
## mesh list stay as they were) but in `parts.glow`, and AuthoredStructures and AuthoredSettlements
## draw them beside the meshes.
##
## Pure and thread-safe (StructureGeometry.build_one calls it on a worker).

## The surface kind of a halo (StructureMaterials.glow).
const KIND := "glow"
## The quad's half-size as a multiple of the pane's largest extent: the visible halo (it fades out
## toward the quad's edge) is about two and a half panes across.
const HALF_SIZE_K := 3.0
## The room a halo's mesh instance is given beyond its (empty) bounds so it is not culled at the
## screen's edge, metres: a little over the largest halo.
const CULL_MARGIN_M := 2.5
## Vertices closer than this (metres) are one corner of a box.
const WELD_M := 0.001


## The halo quads for the lanterns among `meshes` (StructureGeometry mesh dictionaries): [] when
## there are none, otherwise one mesh dictionary of kind KIND in the prop role holding a quad per
## lantern.
static func of(meshes: Array) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for mesh: Dictionary in meshes:
		if mesh.role != StructureLook.PROP or mesh.kind != StructureLook.GLASS_KIND:
			continue
		for box: Dictionary in boxes_of(mesh.arrays):
			var centre: Vector3 = box.centre
			var extent: Vector3 = box.extent
			var half := HALF_SIZE_K * maxf(extent.x, maxf(extent.y, extent.z))
			var base := vertices.size()
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				vertices.append(centre)
				normals.append(Vector3.UP)
				colors.append(Color.WHITE)
				uvs.append(corner)
				uv2s.append(Vector2(half, 0.0))
			indices.append_array(
				PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3])
			)
	if vertices.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var tags := PackedInt32Array()
	tags.resize(vertices.size())
	tags.fill(-1)
	return [{"kind": KIND, "role": StructureLook.PROP, "arrays": arrays, "tags": tags}]


## The boxes (separate pieces of connected or coincident vertices) of a mesh: [{"centre", "extent"}]
## with the middle of each one's bounds and its size. A lantern's pane is a box whose six faces have
## their own vertices, so faces that meet are joined by position.
static func boxes_of(arrays: Array) -> Array[Dictionary]:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var parent := PackedInt32Array()
	parent.resize(vertices.size())
	for v in vertices.size():
		parent[v] = v
	var at := {}
	for v in vertices.size():
		var p := vertices[v]
		var key := Vector3i(roundi(p.x / WELD_M), roundi(p.y / WELD_M), roundi(p.z / WELD_M))
		if at.has(key):
			_union(parent, int(at[key]), v)
		else:
			at[key] = v
	for k in range(0, indices.size() - 2, 3):
		_union(parent, indices[k], indices[k + 1])
		_union(parent, indices[k], indices[k + 2])
	var low := {}
	var high := {}
	for v in vertices.size():
		var root := _root(parent, v)
		var p := vertices[v]
		low[root] = (low[root] as Vector3).min(p) if low.has(root) else p
		high[root] = (high[root] as Vector3).max(p) if high.has(root) else p
	var roots: Array = low.keys()
	roots.sort()
	var out: Array[Dictionary] = []
	for root: int in roots:
		var lo: Vector3 = low[root]
		var hi: Vector3 = high[root]
		out.append({"centre": (lo + hi) * 0.5, "extent": hi - lo})
	return out


static func _root(parent: PackedInt32Array, v: int) -> int:
	var at := v
	while parent[at] != at:
		parent[at] = parent[parent[at]]
		at = parent[at]
	return at


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _root(parent, a)
	var rb := _root(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)
