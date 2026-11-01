extends RefCounted

## The bounds of a loaded model as it renders at rest, in the model root's child space (the root's
## own transform is not applied). A rigid mesh uses its mesh box through its parent chain. A skinned
## mesh renders in its skeleton's space with every vertex moved by its bones' pose times the skin's
## bind matrix, and a bind matrix can scale the mesh (the Quaternius pug is drawn 2.5 times larger
## than its raw mesh box), so the bounds come from the skinned vertices, not `get_aabb()`.


static func of(root: Node3D) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := -low
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var points := _points(mesh)
		var space: Node3D = mesh
		var skeleton := _skeleton_of(mesh)
		if skeleton != null and mesh.skin != null:
			space = skeleton
		var to_root := _chain(space, root)
		for point in points:
			var p := to_root * point
			low = low.min(p)
			high = high.max(p)
	return AABB(low, high - low)


static func _skeleton_of(mesh: MeshInstance3D) -> Skeleton3D:
	return mesh.get_node_or_null(mesh.skeleton) as Skeleton3D


## The mesh's points in its render space: skeleton space when skinned, else its own space.
static func _points(mesh: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var skeleton := _skeleton_of(mesh)
	if skeleton == null or mesh.skin == null:
		var box := mesh.get_aabb()
		for corner in 8:
			out.append(box.position + box.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1))
		return out
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := bones.size() / maxi(verts.size(), 1)
		for i in verts.size():
			var p := Vector3.ZERO
			for k in stride:
				var weight := weights[i * stride + k]
				if weight > 0.0:
					var bind := bones[i * stride + k]
					var bone := mesh.skin.get_bind_bone(bind)
					if bone < 0:
						bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
					var skin_matrix := skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind)
					p += (skin_matrix * verts[i]) * weight
			out.append(p)
	return out


## The transform from `node`'s space to `root`'s child space (parents' transforms up to `root`).
static func _chain(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		xf = (current as Node3D).transform * xf
		current = current.get_parent()
	return xf
