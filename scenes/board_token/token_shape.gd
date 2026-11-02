class_name TokenShape
extends RefCounted

## The collision shape of a pack token, built so it is the model's own size and place.
##
## A model is a tree: the GLB's meshes sit under nodes that carry scale (a horse's mesh node is
## 0.435, a pig's is 0.197 under an armature of 100) and the token factory puts the model's root
## into the token's rigid body at the root's own transform. A shape made from a mesh resource
## (`Mesh.create_convex_shape`) is in the mesh's own units and knows nothing of those nodes, and
## a shape node lifted out of the model for the rigid body leaves its parents behind, so either
## came out the size of the raw mesh data: a horse 2.3 times its model, a pig a speck
## (measured 2026-11-02, docs/CONVENTIONS.md "Token pin").
##
## Everything here is expressed in the rigid body's space and baked into the shape's points, so
## the shape node stays at the origin: the code that reads a token's footprint, base and top
## (grounding, drop indicator, water depth, glow, occlusion fade) reads the shape's box and the
## node's position only, and rotation or scale on the node would escape it.
##
## The shape for a model with no authored one is the convex hull of every visible mesh's
## vertices. A hull keeps what the owner sees (a horse's neck, a figure's raised arms) and sits
## on the model's own base, so a token stands on the ground and reads as large as it looks.
## An authored collision mesh (a `-convcolonly` node in the GLB) is kept and only moved into the
## same space. An avatar's capsule is built elsewhere (AvatarTokenFactory) and does not come here.

## The shape's local box, kept on a hull so reading a token's footprint does not rebuild its debug
## mesh (token markers read it twice a second per token).
const EXTENT_META := &"tt_extent"

## Posed vertices of skinned meshes: mesh id -> {"mesh": WeakRef, "points": PackedVector3Array}.
static var _posed: Dictionary = {}


## `node`'s transform in the space `model`'s parent lives in (the rigid body's, once the model is
## added to it): the product of every node transform from `node` up to and including `model`.
static func to_model_parent(node: Node3D, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node = node
	while current is Node3D:
		xf = (current as Node3D).transform * xf
		if current == model:
			break
		current = current.get_parent()
	return xf


## The convex hull of every visible mesh under `model` (the model itself included), in the
## space `model` is placed in. Null when the model has no mesh with vertices.
static func hull_of(model: Node3D) -> ConvexPolygonShape3D:
	var meshes := TokenGhost.meshes_of(model)
	if model is MeshInstance3D and (model as MeshInstance3D).mesh != null:
		meshes.append(model as MeshInstance3D)
	var points := PackedVector3Array()
	for mi in meshes:
		if mi.visible:
			points.append_array(mesh_points(mi, model))
	if points.size() < 4:
		return null
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	hull.set_meta(EXTENT_META, bounds_of(points))
	return hull


## One mesh instance's vertices, in the space `model` is placed in. A skinned mesh is drawn where
## its bones put it, in the skeleton's space (the sheep's vertex data lies on its side and its rest
## pose stands it up), so its points are the posed ones and the skeleton's transform places them.
static func mesh_points(mi: MeshInstance3D, model: Node3D) -> PackedVector3Array:
	var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin != null else null
	if skeleton != null:
		return to_model_parent(skeleton, model) * posed_points(mi, skeleton)
	var points := PackedVector3Array()
	for surface in mi.mesh.get_surface_count():
		var vertices: Variant = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		if vertices is PackedVector3Array:
			points.append_array(vertices as PackedVector3Array)
	return to_model_parent(mi, model) * points


## A skinned mesh's vertices in its skeleton's space with the skeleton at its current pose. Each
## vertex follows the bone that holds most of its weight (a blend of four would cost four times
## the work for a hull's bounds, and differs only at the joints). The result is kept per mesh
## resource, which every token of one model shares.
static func posed_points(mi: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var mesh := mi.mesh
	var kept: Variant = _posed.get(mesh.get_instance_id())
	if kept != null and (kept.mesh as WeakRef).get_ref() == mesh:
		return kept.points
	var matrices: Array[Transform3D] = []
	for bind in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
		var pose := skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
		matrices.append(pose * mi.skin.get_bind_pose(bind))
	var points := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: Variant = arrays[Mesh.ARRAY_BONES]
		var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if not (bones is PackedInt32Array and weights is PackedFloat32Array) or vertices.is_empty():
			points.append_array(vertices)
			continue
		var stride: int = (bones as PackedInt32Array).size() / vertices.size()
		var groups: Dictionary = {}
		for i in vertices.size():
			var best := 0
			var best_weight := -1.0
			for k in stride:
				var weight: float = (weights as PackedFloat32Array)[i * stride + k]
				if weight > best_weight:
					best_weight = weight
					best = (bones as PackedInt32Array)[i * stride + k]
			var group: PackedVector3Array = groups.get(best, PackedVector3Array())
			group.append(vertices[i])
			groups[best] = group
		for bind: int in groups:
			var group: PackedVector3Array = groups[bind]
			points.append_array(matrices[bind] * group if bind < matrices.size() else group)
	_posed[mesh.get_instance_id()] = {"mesh": weakref(mesh), "points": points}
	return points


## The box around `points`.
static func bounds_of(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var low := points[0]
	var high := points[0]
	for p in points:
		low = low.min(p)
		high = high.max(p)
	return AABB(low, high - low)


## An authored shape node moved into the space its model is placed in. `xf` is
## `to_model_parent(node, model)` taken before the node was lifted out of the model. A convex or
## concave shape gets a new resource with `xf` baked into its points (the resource may be shared
## with every other instance of the model, so it is never changed in place) and the node goes to
## the origin; any other shape keeps its resource and takes `xf` as its transform.
static func rebase(node: CollisionShape3D, xf: Transform3D) -> void:
	var shape := node.shape
	if shape is ConvexPolygonShape3D:
		var baked := ConvexPolygonShape3D.new()
		baked.points = xf * (shape as ConvexPolygonShape3D).points
		baked.set_meta(EXTENT_META, bounds_of(baked.points))
		node.shape = baked
		node.transform = Transform3D.IDENTITY
	elif shape is ConcavePolygonShape3D:
		var baked := ConcavePolygonShape3D.new()
		baked.set_faces(xf * (shape as ConcavePolygonShape3D).get_faces())
		node.shape = baked
		node.transform = Transform3D.IDENTITY
	else:
		node.transform = xf


## A shape's box in its own space, from the hull's kept box when it has one.
static func extent_of(shape: Shape3D) -> AABB:
	if shape.has_meta(EXTENT_META):
		return shape.get_meta(EXTENT_META)
	return shape.get_debug_mesh().get_aabb()
