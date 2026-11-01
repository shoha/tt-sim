extends RefCounted

## The geometry half of the Folk build (tools/roster/build_folk.gd): lowers a T-posed humanoid's
## arms to an A-pose and bakes that pose into static vertices, and collects baked surfaces into
## one merged group per material.
##
## All Quaternius parts (bodies, outfits, hairstyles) share one 65-bone skeleton, so a part is
## skinned with the same per-bone matrices whichever file it came from. Baking removes the
## skeleton from the shipped GLB: a token is a rigid mesh, the A-pose is the figure's one pose.

## The error the simplifier may accept before it stops short of the target triangle count.
const SIMPLIFY_ERROR := 0.05


## One merged surface: every source surface of one material appended into shared arrays.
class Group:
	extends RefCounted
	var material: StandardMaterial3D
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	## Appends skinned vertex data and the triangles `keep` allows (every triangle when `keep` is
	## empty), renumbering the vertices the kept triangles use.
	func append(
		p_verts: PackedVector3Array,
		p_normals: PackedVector3Array,
		p_uvs: PackedVector2Array,
		p_indices: PackedInt32Array,
		keep: PackedByteArray
	) -> void:
		var remap := {}
		for t in range(p_indices.size() / 3):
			if not keep.is_empty() and keep[t] == 0:
				continue
			for k in 3:
				var old := p_indices[t * 3 + k]
				if not remap.has(old):
					remap[old] = verts.size()
					verts.append(p_verts[old])
					normals.append(p_normals[old])
					uvs.append(p_uvs[old])
				indices.append(remap[old])

	## Moves and scales every vertex: `p = (p + shift) * factor`.
	func transform(shift: Vector3, factor: float) -> void:
		for i in verts.size():
			verts[i] = (verts[i] + shift) * factor

	func triangle_count() -> int:
		return indices.size() / 3

	## Reduces the triangles to about `ratio` of their count (meshoptimizer through
	## SurfaceTool), dropping the vertices that no remaining triangle uses.
	func simplify(ratio: float) -> void:
		if ratio >= 1.0 or indices.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var tool := SurfaceTool.new()
		tool.create_from_arrays(arrays)
		var target := maxi(int(indices.size() * ratio) / 3 * 3, 3)
		var reduced := tool.generate_lod(SIMPLIFY_ERROR, target)
		var old_verts := verts
		var old_normals := normals
		var old_uvs := uvs
		verts = PackedVector3Array()
		normals = PackedVector3Array()
		uvs = PackedVector2Array()
		indices = PackedInt32Array()
		append(old_verts, old_normals, old_uvs, reduced, PackedByteArray())


## Per-bone skinning matrices for an A-pose: the arms dropped `drop` radians from the T-pose about
## the front-back axis, the clavicles taking `clavicle_share` of it so the shoulder does not fold.
## Matrix `b` maps a rest-pose vertex of bone `b` to the posed skeleton.
static func a_pose_matrices(
	skeleton: Skeleton3D, drop: float, clavicle_share: float
) -> Array[Transform3D]:
	# The chain is computed here rather than read from the Skeleton3D, whose global poses do not
	# refresh outside a scene tree. Parents come before their children in the bone order.
	var count := skeleton.get_bone_count()
	var rest_global: Array[Transform3D] = []
	var locals: Array[Transform3D] = []
	for b in count:
		var parent := skeleton.get_bone_parent(b)
		locals.append(skeleton.get_bone_rest(b))
		rest_global.append(locals[b] if parent < 0 else rest_global[parent] * locals[b])
	var turns := {}
	for side in ["l", "r"]:
		# The left arm points to +X, so a negative turn about +Z lowers it; the right mirrors.
		var sign := -1.0 if side == "l" else 1.0
		turns[skeleton.find_bone("clavicle_" + side)] = Basis(Vector3.BACK, sign * drop * clavicle_share)
		turns[skeleton.find_bone("upperarm_" + side)] = Basis(Vector3.BACK, sign * drop)
	var posed: Array[Transform3D] = []
	var out: Array[Transform3D] = []
	for b in count:
		var parent := skeleton.get_bone_parent(b)
		var local := locals[b]
		if turns.has(b):
			# A world-space turn of this bone: its local basis becomes parent^-1 * turn * rest.
			var target: Basis = turns[b] * rest_global[b].basis
			local.basis = posed[parent].basis.inverse() * target
		posed.append(local if parent < 0 else posed[parent] * local)
		out.append(posed[b] * rest_global[b].affine_inverse())
	return out


## Skins one surface's arrays (vertex, normal, bones, weights) with `matrices`; returns
## `{"verts": PackedVector3Array, "normals": PackedVector3Array}`. `skin` maps the mesh's bone
## slots to skeleton bones (identity when the file has no bind names).
static func skin_surface(arrays: Array, skin: Skin, matrices: Array[Transform3D]) -> Dictionary:
	var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_v.resize(src.size())
	out_n.resize(src.size())
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex := bones.size() / maxi(src.size(), 1)
	for i in src.size():
		var pos := Vector3.ZERO
		var normal := Vector3.ZERO
		for k in per_vertex:
			var w := weights[i * per_vertex + k]
			if w <= 0.0:
				continue
			var m := matrices[bone_of(skin, bones[i * per_vertex + k])]
			pos += (m * src[i]) * w
			normal += (m.basis * nrm[i]) * w
		out_v[i] = pos
		out_n[i] = normal.normalized()
	return {"verts": out_v, "normals": out_n}


## For each triangle of a surface, 1 when all three vertices are mostly bound to a bone in
## `bones` (used to cut a head out of a full body), else 0.
static func triangles_bound_to(arrays: Array, skin: Skin, bones: PackedInt32Array) -> PackedByteArray:
	var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per_vertex := bone_ids.size() / maxi(count, 1)
	var inside := PackedByteArray()
	inside.resize(count)
	for i in count:
		var best := -1.0
		var best_bone := -1
		for k in per_vertex:
			if weights[i * per_vertex + k] > best:
				best = weights[i * per_vertex + k]
				best_bone = bone_of(skin, bone_ids[i * per_vertex + k])
		inside[i] = 1 if best_bone in bones else 0
	var keep := PackedByteArray()
	keep.resize(indices.size() / 3)
	for t in keep.size():
		var all_in := inside[indices[t * 3]] + inside[indices[t * 3 + 1]] + inside[indices[t * 3 + 2]]
		keep[t] = 1 if all_in == 3 else 0
	return keep


## The skeleton bone a mesh bone slot refers to.
static func bone_of(skin: Skin, slot: int) -> int:
	if skin != null and slot < skin.get_bind_count() and skin.get_bind_bone(slot) >= 0:
		return skin.get_bind_bone(slot)
	return slot
