class_name AvatarExtent
extends RefCounted

## The body core of an assembled figure (AvatarKit.build_figure), which sizes an avatar
## token's collision capsule and through it the selection glow, the drag height, the landing
## and the occlusion fade.
##
## Measured on the posed skeleton, not the meshes' rest boxes, so a crouch is shorter and a
## lunge wider than the A-pose. Only the core bones count (spine, head and legs): a pushed
## stance's outstretched arms would make the capsule, and the glow under the token, much wider
## than the body a player aims at. Each core bone's head and tail (kit.json `skeleton`, glTF
## rest space) are carried through the figure's proportions (AvatarProportions) and its pose,
## as AvatarKit's ground rule carries the ground contacts. The top is the highest of them or
## the crown: the tallest part's rest top (hair over the head) carried with the Head bone.

const CORE_BONES: Array[String] = [
	"Hips",
	"Spine",
	"Chest",
	"UpperChest",
	"Neck",
	"Head",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"LeftToes",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"RightToes",
]
## Body volume around the core bone lines (about the hips' half-width).
const GIRTH_M := 0.1
const MIN_RADIUS_M := 0.15
## The contract's 0.6 m footprint (docs/ASSET_PIPELINE.md section 10).
const MAX_RADIUS_M := 0.3
## Capsule shapes are shared by size rounded to this (capsule_shape).
const SHAPE_STEP_M := 0.01

## Vector2(radius, height) -> ConvexPolygonShape3D (capsule_shape).
static var _shapes: Dictionary = {}


## {"radius", "height"} of the capsule round `figure`'s body core, with its soles on y = 0.
static func capsule(kit: AvatarKit, figure: Node3D) -> Dictionary:
	var sk := figure.get_node_or_null("Skeleton3D") as Skeleton3D
	var skeleton: Dictionary = kit.manifest.get("skeleton", {})
	if sk == null or skeleton.is_empty():
		return {"radius": MAX_RADIUS_M, "height": 1.6}
	var resolved: Dictionary = figure.get_meta("avatar_recipe", {})
	var maps: Dictionary = kit.cache.shape(resolved.get("proportions", {})).maps
	var globals := {}
	var top := 0.0
	var reach := 0.0
	for bone in CORE_BONES:
		var b := sk.find_bone(bone)
		if b < 0 or not skeleton.has(bone) or not maps.has(bone):
			continue
		var to_posed := _to_posed(sk, b, maps[bone], globals)
		var points: Array[Vector3] = [_vec(skeleton[bone].head), _vec(skeleton[bone].tail)]
		if bone == "Head":
			var tail := _vec(skeleton[bone].tail)
			points.append(Vector3(tail.x, maxf(tail.y, _parts_top(figure)), tail.z))
		for point in points:
			var p := to_posed * point
			top = maxf(top, p.y)
			reach = maxf(reach, Vector2(p.x, p.z).length())
	var radius := clampf(reach + GIRTH_M, MIN_RADIUS_M, MAX_RADIUS_M)
	return {"radius": radius, "height": maxf(top, radius * 2.0)}


## A capsule shape round the body core, its bottom on the token's origin: a convex hull of
## capsule points (an octagon at the equator of each cap, a smaller one halfway up the cap,
## and the two poles), because the selection glow, the occlusion fade and the submerged cue
## read a token's collision box in the shape's own space and expect a pack token's layout
## (feet at the origin, shape not offset). Computing a hull costs a millisecond or more, so
## shapes are shared by size, rounded to SHAPE_STEP_M (Shape3D resources are shareable).
static func capsule_shape(radius: float, height: float) -> ConvexPolygonShape3D:
	var r := snappedf(radius, SHAPE_STEP_M)
	var h := maxf(snappedf(height, SHAPE_STEP_M), r * 2.0)
	var key := Vector2(r, h)
	if _shapes.has(key):
		return _shapes[key]
	var points := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, h, 0.0)])
	# (ring radius, height): each cap's equator, and its 45-degree latitude.
	var rings: Array[Vector2] = [
		Vector2(r, r),
		Vector2(r, h - r),
		Vector2(r * 0.7071, r * 0.2929),
		Vector2(r * 0.7071, h - r * 0.2929),
	]
	for ring in rings:
		for k in 8:
			var a := TAU * k / 8.0
			points.append(Vector3(cos(a) * ring.x, ring.y, sin(a) * ring.x))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	if _shapes.size() >= 64:
		_shapes.clear()
	_shapes[key] = shape
	return shape


## Carries a point in glTF rest space on bone `b` to the posed figure's space.
static func _to_posed(sk: Skeleton3D, b: int, map: Dictionary, globals: Dictionary) -> Transform3D:
	return (
		posed_global(sk, b, globals)
		* sk.get_bone_global_rest(b).affine_inverse()
		* AvatarProportions.bone_map_transform(map)
	)


## Bone `b`'s global transform from the skeleton's local poses. Read from the poses, not
## get_bone_global_pose, which is stale for a skeleton posed outside the tree (AvatarKit).
static func posed_global(sk: Skeleton3D, b: int, cache: Dictionary) -> Transform3D:
	if cache.has(b):
		return cache[b]
	var parent := sk.get_bone_parent(b)
	var local := sk.get_bone_pose(b)
	var global := local if parent < 0 else posed_global(sk, parent, cache) * local
	cache[b] = global
	return global


## The highest rest-space point of the figure's parts (their mesh boxes).
static func _parts_top(figure: Node3D) -> float:
	var top := 0.0
	for mi in AvatarKit.figure_parts(figure):
		if mi.mesh != null:
			top = maxf(top, mi.mesh.get_aabb().end.y)
	return top


static func _vec(value: Variant) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
