class_name PainterBodies
extends RefCounted

## What PainterOcclusion reads off a scatter mesh, once per mesh (split out of it, card
## painter-trunk-contact): its separate BODIES (`islands`: a mesh of three stones is three
## boxes, stones side by side stay apart though their boxes overlap, only a body mostly inside
## another is part of it, `nested`), its triangles (`soup`, which PainterSites.feet cuts into a
## body's plan sections) and, for a scatter tree, its trunk's lowest ring (`trunk_of`: the foot
## the trunk's contact mark is made from). Pure functions of the mesh; the host keeps the results
## by the mesh's instance id.
##
## MANAGED BY: PainterOcclusion (painter/painter_occlusion.gd). Classic never loads this file.

## The most bodies of one mesh that get their own footprint (the largest), the largest mesh (in
## vertices) that is split at all, and the grid (metres) its vertices are welded on.
const MAX_ISLANDS := 12
const MAX_SPLIT_VERTICES := 6000
const WELD_M := 0.002
## The share of the smaller body's plan that must lie inside another's for the two to be one body.
const NEST_SHARE := 0.5
## A scatter tree's trunk is read from its mesh's lowest ring (trunk_of): the vertices within
## TRUNK_BAND_M, or TRUNK_BAND_K of its height if more, of its underside.
const TRUNK_BAND_M := 0.15
const TRUNK_BAND_K := 0.03


## Every triangle of `mesh`, three corners each (nothing for a mesh islands() does not split).
static func soup(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return out
	for s in array_mesh.get_surface_count():
		if array_mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := array_mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if out.size() + verts.size() > 6 * MAX_SPLIT_VERTICES:
			return PackedVector3Array()
		if arrays[Mesh.ARRAY_INDEX] == null:
			out.append_array(verts)
			continue
		for index: int in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
			out.append(verts[index])
	return out


## The separate bodies of `mesh`, as boxes in its own space: its triangles joined where they share
## a vertex (welded on WELD_M), and bodies whose plans overlap taken as one (a stone built of nested
## shells, two stones that touch). A mesh that is one body, is not triangles, or is too large to
## split gives its whole box. At most MAX_ISLANDS, the largest in plan.
static func islands(mesh: Mesh) -> Array[AABB]:
	var whole: Array[AABB] = [mesh.get_aabb()]
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return whole
	var parent := PackedInt32Array()
	var points := PackedVector3Array()
	var ids := {}
	for s in array_mesh.get_surface_count():
		if array_mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return whole
		var arrays := array_mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if points.size() + verts.size() > MAX_SPLIT_VERTICES:
			return whole
		var welded := PackedInt32Array()
		welded.resize(verts.size())
		for k in verts.size():
			var key := Vector3i((verts[k] / WELD_M).round())
			if not ids.has(key):
				ids[key] = points.size()
				parent.append(points.size())
				points.append(verts[k])
			welded[k] = ids[key]
		var index := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			index = arrays[Mesh.ARRAY_INDEX]
		var indexed := not index.is_empty()
		var corners := index.size() if indexed else verts.size()
		for t in range(0, corners - 2, 3):
			var a := _root(parent, welded[index[t] if indexed else t])
			var b := _root(parent, welded[index[t + 1] if indexed else t + 1])
			parent[b] = a
			var c := _root(parent, welded[index[t + 2] if indexed else t + 2])
			parent[c] = a
	var by_root := {}
	for k in points.size():
		var root := _root(parent, k)
		if by_root.has(root):
			by_root[root] = (by_root[root] as AABB).expand(points[k])
		else:
			by_root[root] = AABB(points[k], Vector3.ZERO)
	var out: Array[AABB] = []
	out.assign(by_root.values())
	if out.size() <= 1 or out.size() > 8 * MAX_ISLANDS:
		return whole
	# A body that lies mostly inside another's plan is part of it. Stones set side by side stay
	# apart: their boxes overlap at the corners, and joined on any overlap the core library's
	# cluster of five was one box again, its mark an oval a metre wide (card
	# painter-rocks-forms-finish).
	var merged := true
	while merged:
		merged = false
		var i := 0
		while i < out.size():
			for j in range(out.size() - 1, i, -1):
				if nested(_plan(out[i]), _plan(out[j])):
					out[i] = out[i].merge(out[j])
					out.remove_at(j)
					merged = true
			i += 1
	out.sort_custom(func(a: AABB, b: AABB) -> bool: return _plan(a).get_area() > _plan(b).get_area())
	if out.size() > MAX_ISLANDS:
		out.resize(MAX_ISLANDS)
	return out


## Whether the smaller of two plans lies mostly (NEST_SHARE of its area) inside the other: a shell
## nested in a stone, a chip on its top. A plan with no area that touches the other is inside it.
static func nested(a: Rect2, b: Rect2) -> bool:
	if not a.intersects(b, true):
		return false
	return a.intersection(b).get_area() >= NEST_SHARE * minf(a.get_area(), b.get_area())


## The trunk of a scatter tree's mesh as (x, z, r) in the mesh's frame: the middle and the mean
## radius of its vertices in the lowest TRUNK_BAND_M (at least TRUNK_BAND_K of its height), the
## trunk's lowest ring; zero for a mesh with nothing there.
static func trunk_of(mesh: Mesh) -> Vector3:
	var box := mesh.get_aabb()
	var top := box.position.y + maxf(TRUNK_BAND_M, TRUNK_BAND_K * box.size.y)
	var ring := PackedVector2Array()
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return Vector3.ZERO
	for s in array_mesh.get_surface_count():
		var verts: PackedVector3Array = array_mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			if v.y <= top:
				ring.append(Vector2(v.x, v.z))
	if ring.is_empty():
		return Vector3.ZERO
	var mid := Vector2.ZERO
	for q: Vector2 in ring:
		mid += q
	mid /= ring.size()
	var r := 0.0
	for q: Vector2 in ring:
		r += q.distance_to(mid)
	return Vector3(mid.x, mid.y, r / ring.size())


static func _plan(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
