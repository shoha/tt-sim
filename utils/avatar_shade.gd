class_name AvatarShade
extends RefCounted

## Whether an avatar figure stands in shade: one ray from about chest height toward the sun,
## taken on the CPU when the figure is placed or moved and handed to the figure shader as its
## `shade` instance value (AvatarKit.set_shade). The shader ignores the sun's shadow map,
## whose soft-filter stipple lands on the painted colour blocks (the avatar probe).
##
## The ray is tested against two things. The ground's collision (layer 1), so a figure behind
## a hill from the sun is in shade. And canopies: tree crowns are scatter MultiMesh instances
## or placed props without collision, so each visual instance whose mesh stands at least
## CANOPY_MIN_HEIGHT tall counts as its mesh box's upper CROWN_SHARE, narrowed to
## CROWN_WIDTH of its footprint, and the ray is tested against that box in the instance's
## own space. Shade under canopy is the main case; a figure's own parts, anything short
## (grass, rocks, other figures) and anything much wider than tall (ground chunks, water,
## MAX_SPREAD) never count.

const CANOPY_MIN_HEIGHT := 2.5
const CROWN_SHARE := 0.6
const CROWN_WIDTH := 0.8
const MAX_SPREAD := 2.5
const RAY_ORIGIN_HEIGHT := 1.0
const RAY_LENGTH := 60.0
const GROUND_MASK := 1


## 1.0 when the ray from `position` (the figure's feet) toward the sun meets ground or a
## canopy under `root`, else 0.0. `toward_sun` is the unit direction to the sun (a
## DirectionalLight3D's global basis z); a sun at or below the horizon gives 1.0.
static func shade_at(root: Node3D, position: Vector3, toward_sun: Vector3) -> float:
	return 0.0 if blocker(root, position, toward_sun).is_empty() else 1.0


## What puts `position` in shade: "" in sun, else "below horizon", "ground" or the canopy
## node's name (with the MultiMesh instance index).
static func blocker(root: Node3D, position: Vector3, toward_sun: Vector3) -> String:
	if toward_sun.y <= 0.0:
		return "below horizon"
	var from := position + Vector3.UP * RAY_ORIGIN_HEIGHT
	var to := from + toward_sun.normalized() * RAY_LENGTH
	var world := root.get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(from, to, GROUND_MASK)
		if not world.direct_space_state.intersect_ray(query).is_empty():
			return "ground"
	return canopy_hit(root, from, to)


## The canopy the segment meets under `root` ("" when none): a node name, and for a
## MultiMesh the instance index.
static func canopy_hit(root: Node, from: Vector3, to: Vector3) -> String:
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var i := _multimesh_hit(node as MultiMeshInstance3D, from, to)
		if i >= 0:
			return "%s #%d" % [node.name, i]
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree():
			continue
		if _crown_hit(mi.mesh.get_aabb(), mi.global_transform, from, to):
			return String(mi.name)
	return ""


## The first instance whose crown the segment meets, or -1.
static func _multimesh_hit(mmi: MultiMeshInstance3D, from: Vector3, to: Vector3) -> int:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null or not mmi.is_visible_in_tree():
		return -1
	var box := mm.mesh.get_aabb()
	if box.size.y < CANOPY_MIN_HEIGHT * 0.5:
		return -1
	var xf := mmi.global_transform
	if (xf * mm.get_aabb()).intersects_segment(from, to) == null:
		return -1
	var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	for i in count:
		if _crown_hit(box, xf * mm.get_instance_transform(i), from, to):
			return i
	return -1


## The ray against the crown part of a mesh box placed by `xf` (tested in the mesh's space).
static func _crown_hit(box: AABB, xf: Transform3D, from: Vector3, to: Vector3) -> bool:
	var scale_y := xf.basis.get_scale().y
	if box.size.y * scale_y < CANOPY_MIN_HEIGHT:
		return false
	# Ground chunks, water and skirts are wide and low; a tree is about as tall as it is wide.
	if maxf(box.size.x, box.size.z) > box.size.y * MAX_SPREAD:
		return false
	var crown := box
	crown.position.y = box.position.y + box.size.y * (1.0 - CROWN_SHARE)
	crown.size.y = box.size.y * CROWN_SHARE
	var inset := box.size * (1.0 - CROWN_WIDTH) * 0.5
	crown.position.x += inset.x
	crown.position.z += inset.z
	crown.size.x -= inset.x * 2.0
	crown.size.z -= inset.z * 2.0
	var inv := xf.affine_inverse()
	return crown.intersects_segment(inv * from, inv * to) != null
