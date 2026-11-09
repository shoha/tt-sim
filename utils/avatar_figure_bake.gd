class_name AvatarFigureBake
extends RefCounted

## An avatar token's figure as one static mesh (the perf audit's F-tokens-2, 2026-11-09).
##
## A figure from AvatarKit.build_figure is a Skeleton3D with a skinned MeshInstance3D per part,
## and each part mesh holds one surface per body region, all drawn with the part's one material:
## about 18 surfaces per figure, each a draw in the colour pass, the depth pre-pass and every
## shadow cascade. That made avatars the dearest tokens to submit (0.025-0.04 ms of render CPU
## each). A figure on the board never moves its bones once it is posed, so bake() skins it once
## on the CPU: each part's surfaces joined into one surface, posed through the part's Skin and the
## skeleton's local poses (its global pose is stale outside the tree, see AvatarKit), with the
## part's blend shapes at their weights. The result is one ArrayMesh with one surface per part,
## named by the part, holding the vertices the GPU would have skinned, so the part's own material
## draws it unchanged. AvatarTokenView sets those materials as surface overrides, which keeps a
## baked mesh shareable between figures that differ only in colour or face: cached() keys it by
## the parts' meshes, skins, blend weights and the pose.
##
## Only what the figure shader reads is kept: position, normal, UV (palette), UV2 (detail and
## face) and COLOR (light response). A part without UV2 or COLOR gets zeros or white, what the
## shader reads when they are absent.

## Baked meshes kept (the table is dropped when it passes this, as AvatarFigureCache does).
const MAX_ENTRIES := 48

static var _cache: Dictionary = {}


## The baked mesh for `figure`, shared with every figure of the same geometry and pose.
static func cached(figure: Node3D) -> ArrayMesh:
	var key := geometry_key(figure)
	if not _cache.has(key):
		if _cache.size() >= MAX_ENTRIES:
			_cache.clear()
		_cache[key] = bake(figure)
	return _cache[key]


## Drops every cached bake (tests).
static func clear_cache() -> void:
	_cache.clear()


## What the baked geometry depends on: each part's mesh and skin (shared resources, so equal
## parts and proportions give equal ids), its blend shape weights, and the skeleton's pose.
static func geometry_key(figure: Node3D) -> String:
	var sk := figure.get_node_or_null("Skeleton3D") as Skeleton3D
	var pose := 0
	if sk != null:
		pose = hash([sk.get_meta("avatar_pose", {}), sk.get_meta("avatar_offsets", {})])
	var parts := PackedStringArray([str(pose)])
	for mi in AvatarKit.figure_parts(figure):
		if mi.mesh == null:
			continue
		var weights := PackedFloat32Array()
		for i in mi.mesh.get_blend_shape_count():
			weights.append(snappedf(mi.get_blend_shape_value(i), 0.0001))
		parts.append(
			(
				"%s:%d:%d:%s"
				% [
					mi.name,
					mi.mesh.get_instance_id(),
					mi.skin.get_instance_id() if mi.skin != null else 0,
					str(weights)
				]
			)
		)
	return "|".join(parts)


## `figure`'s parts posed and joined: one surface per part with a mesh, in figure_parts order,
## each named by its part (the MeshInstance3D's name), positions in the figure's space.
static func bake(figure: Node3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	var sk := figure.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk == null:
		return out
	var globals := {}
	for mi in AvatarKit.figure_parts(figure):
		if mi.mesh == null:
			continue
		var arrays := part_arrays(mi, sk, globals)
		if arrays.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_name(out.get_surface_count() - 1, String(mi.name))
	return out


## One part's surfaces skinned and joined into the arrays of one triangle surface; empty when the
## part has no triangles.
static func part_arrays(mi: MeshInstance3D, sk: Skeleton3D, globals: Dictionary) -> Array:
	var mesh: Mesh = mi.mesh
	if mesh.get_blend_shape_count() > 0:
		mesh = mi.bake_mesh_from_current_blend_shape_mix()
	var mats := skin_matrices(mi.skin, sk, globals)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n := v.size()
		if n == 0:
			continue
		var base := verts.size()
		var skinned := skin_surface(
			v, a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_BONES], a[Mesh.ARRAY_WEIGHTS], mats
		)
		verts.append_array(skinned[0])
		normals.append_array(skinned[1])
		uv.append_array(_or_zero(a[Mesh.ARRAY_TEX_UV], n))
		uv2.append_array(_or_zero(a[Mesh.ARRAY_TEX_UV2], n))
		colours.append_array(_or_white(a[Mesh.ARRAY_COLOR], n))
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			for i in n:
				index.append(base + i)
		elif base == 0:
			index.append_array(idx)
		else:
			for i in idx as PackedInt32Array:
				index.append(base + i)
	if index.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


## Per bind of `skin`, the bone's posed global transform times the bind pose (what the renderer
## hands the skinning pass). Without a skin, the binds are the skeleton's bones at their global
## rests, as Godot builds them.
static func skin_matrices(skin: Skin, sk: Skeleton3D, globals: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if skin == null:
		for b in sk.get_bone_count():
			out.append(
				AvatarExtent.posed_global(sk, b, globals) * sk.get_bone_global_rest(b).affine_inverse()
			)
		return out
	for i in skin.get_bind_count():
		var name := skin.get_bind_name(i)
		var b := sk.find_bone(String(name)) if name != StringName() else skin.get_bind_bone(i)
		var pose := AvatarExtent.posed_global(sk, b, globals) if b >= 0 else Transform3D.IDENTITY
		out.append(pose * skin.get_bind_pose(i))
	return out


## [positions, normals] of one surface carried through `mats` by its bone indices and weights
## (4 or 8 per vertex), normals normalised; a surface without bones is returned as it is.
static func skin_surface(
	verts: PackedVector3Array,
	normals_in: Variant,
	bones_in: Variant,
	weights_in: Variant,
	mats: Array[Transform3D]
) -> Array:
	var n := verts.size()
	var normals: PackedVector3Array = (
		normals_in if normals_in != null else _filled_vec3(n, Vector3.UP)
	)
	if bones_in == null or weights_in == null or (bones_in as PackedInt32Array).is_empty():
		return [verts, normals]
	var bones: PackedInt32Array = bones_in
	var weights: PackedFloat32Array = weights_in
	var stride := bones.size() / n
	var bound := mats.size()
	var out_v := PackedVector3Array()
	out_v.resize(n)
	var out_n := PackedVector3Array()
	out_n.resize(n)
	for i in n:
		var v := verts[i]
		var nm := normals[i]
		var p := Vector3.ZERO
		var q := Vector3.ZERO
		var o := i * stride
		for k in stride:
			var w := weights[o + k]
			var bi := bones[o + k]
			if w > 0.0 and bi < bound:
				var m := mats[bi]
				p += (m * v) * w
				q += (m.basis * nm) * w
		out_v[i] = p
		out_n[i] = q.normalized()
	return [out_v, out_n]


static func _or_zero(values: Variant, n: int) -> PackedVector2Array:
	if values != null and (values as PackedVector2Array).size() == n:
		return values
	var out := PackedVector2Array()
	out.resize(n)
	return out


static func _or_white(values: Variant, n: int) -> PackedColorArray:
	if values != null and (values as PackedColorArray).size() == n:
		return values
	var out := PackedColorArray()
	out.resize(n)
	out.fill(Color.WHITE)
	return out


static func _filled_vec3(n: int, value: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(n)
	out.fill(value)
	return out
