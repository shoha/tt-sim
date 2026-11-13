class_name PainterTreeMeshes
extends RefCounted
## The painted trees' shared meshes (docs/systems/painter.md "Trees"). No mesh belongs to a tree:
## every tree's MultiMesh instances one of these blocks, and the shaders build each piece in the
## vertex stage from the tree's packed masses (PainterTreePack). Ported from the painterspike
## branch's PPainter12 (sphere, stroke and quad blocks, with PPainter9's ellipsoid soup) and
## round 19's limb ribbon, which replaced round 10's tube:
##   block()      PainterTreePack.ELL_PER_INST unit spheres (ELL_SEGS x ELL_RINGS); VERTEX the
##                unit point, UV2.x which sphere of the instance (painter_tree_blockin kind10 0)
##   ribbon()     PainterTreePack.SEG_PER_INST limb ribbons of RIBBON_SUB pieces each; UV (which
##                edge 0 | 1, how far along the segment), UV2.x which segment (kind10 1)
##   strokes(l)   SLOT_PER_INST slots of ROOTS roots, each root 4^l quads (stroke level l); UV the
##                corner, UV2.x which quad (painter_tree_stroke pass10 l)
## Made once per session and shared by every cell; positions are zero or unit, so each carries a
## wide custom AABB (the cells set their own).

## Pieces a limb ribbon has along one segment (the spike's SUB19).
const RIBBON_SUB := 4
const BOUNDS := AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 45.0, 40.0))

static var _cache: Dictionary = {}


## The block-in's sphere block (cached).
static func block() -> ArrayMesh:
	if not _cache.has("block"):
		_cache["block"] = _sphere_block(PainterTreePack.ELL_SEGS, PainterTreePack.ELL_RINGS)
	return _cache["block"]


## The block-in's limb ribbon block (cached).
static func ribbon() -> ArrayMesh:
	if not _cache.has("ribbon"):
		_cache["ribbon"] = _ribbon_block()
	return _cache["ribbon"]


## Stroke level `level`'s quad block (cached).
static func strokes(level: int) -> ArrayMesh:
	var key := "strokes%d" % level
	if not _cache.has(key):
		_cache[key] = _quad_block(
			PainterTreePack.SLOT_PER_INST * PainterTreePack.ROOTS * int(pow(4.0, float(level)))
		)
	return _cache[key]


static func _mesh(
	v: PackedVector3Array, uv: PackedVector2Array, uv2: PackedVector2Array, idx: PackedInt32Array
) -> ArrayMesh:
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TEX_UV2] = uv2
	a[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mesh.custom_aabb = BOUNDS
	return mesh


## A unit sphere as (points, indices): rings + 1 rows of segs + 1 points, each quad two
## triangles wound clockwise seen from outside (Godot's front face), slivers at the poles dropped.
static func unit_sphere(segs: int, rings: int) -> Array:
	var v := PackedVector3Array()
	for iy in rings + 1:
		var phi := PI * float(iy) / float(rings)
		for ix in segs + 1:
			var th := TAU * float(ix) / float(segs)
			v.append(Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)))
	var idx := PackedInt32Array()
	for iy in rings:
		for ix in segs:
			var a := iy * (segs + 1) + ix
			var c := a + segs + 1
			_tri(v, idx, a, a + 1, c)
			_tri(v, idx, a + 1, c + 1, c)
	return [v, idx]


static func _tri(v: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int) -> void:
	var cr := (v[b] - v[a]).cross(v[c] - v[a])
	if cr.length_squared() < 1e-12:
		return
	if cr.dot(v[a] + v[b] + v[c]) > 0.0:
		idx.append_array(PackedInt32Array([a, c, b]))
	else:
		idx.append_array(PackedInt32Array([a, b, c]))


static func _sphere_block(segs: int, rings: int) -> ArrayMesh:
	var soup := unit_sphere(segs, rings)
	var points: PackedVector3Array = soup[0]
	var tris: PackedInt32Array = soup[1]
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in PainterTreePack.ELL_PER_INST:
		var base := v.size()
		v.append_array(points)
		for k in points.size():
			uv.append(Vector2.ZERO)
			uv2.append(Vector2(float(j), 0.0))
		for k in tris:
			idx.append(base + k)
	return _mesh(v, uv, uv2, idx)


static func _ribbon_block() -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in PainterTreePack.SEG_PER_INST:
		var base := v.size()
		for k in RIBBON_SUB + 1:
			for e in 2:
				v.append(Vector3.ZERO)
				uv.append(Vector2(float(e), float(k) / float(RIBBON_SUB)))
				uv2.append(Vector2(float(j), 0.0))
		for k in RIBBON_SUB:
			var a := base + k * 2
			# Seen from the eye with the limb running up: a left, a + 1 right, a + 2, a + 3 above.
			idx.append_array(PackedInt32Array([a, a + 2, a + 3, a, a + 3, a + 1]))
	return _mesh(v, uv, uv2, idx)


static func _quad_block(quads: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	v.resize(quads * 4)
	uv.resize(quads * 4)
	uv2.resize(quads * 4)
	idx.resize(quads * 6)
	for q in quads:
		var b := q * 4
		uv[b] = Vector2(0.0, 0.0)
		uv[b + 1] = Vector2(1.0, 0.0)
		uv[b + 2] = Vector2(1.0, 1.0)
		uv[b + 3] = Vector2(0.0, 1.0)
		for k in 4:
			uv2[b + k] = Vector2(float(q), 0.0)
		var i := q * 6
		idx[i] = b
		idx[i + 1] = b + 1
		idx[i + 2] = b + 2
		idx[i + 3] = b
		idx[i + 4] = b + 2
		idx[i + 5] = b + 3
	return _mesh(v, uv, uv2, idx)
