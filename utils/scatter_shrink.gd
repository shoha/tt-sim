class_name ScatterShrink
extends RefCounted

## Shrink-out for scatter instances a brush removes, the reverse of AuthoredScatter's
## grow-in: the removed instances move to a temporary MultiMeshInstance3D beside their
## chunk, which shrinks away over SECONDS and frees itself. Without it, Thin / Clear and a
## repaint make trees pop out of existence, which reads as a glitch rather than as the
## world responding. Used by AuthoredScatter (regenerated cells) and BaseScatterEraser (a
## dressed Blender map's own scatter under the erase mask).
##
## Same two modes as the grow-in: a species whose every surface is a wind ShaderMaterial
## shrinks through the `grow` instance uniform every wind shader variant multiplies the
## vertex by (one value per node, no per-instance work); anything else (rocks, whose
## material has no such uniform) sinks into the ground by moving the temporary node.
## The node is built with ScatterGlbUtils.build_chunk, so it shares the chunk's mesh and
## materials and creates nothing new.

## Long enough to read as the plant withdrawing, short enough to keep up with a stroke.
const SECONDS := 0.3
const INFIX := "_shrink"
const GROW_UNIFORM := &"grow"

static var _serial: int = 0
## Held instances, per parent (its instance id): origin -> true. A terrain event that takes
## instances down itself (ForestFall) holds them, so the rebuild that removes them lets them go
## at once instead of standing them up again to shrink.
static var _held: Dictionary = {}


## Holds the instances of `parent`'s scatter standing at `origins` (see _held).
static func hold(parent: Node, origins: Array[Vector3]) -> void:
	var id := parent.get_instance_id()
	if not _held.has(id):
		_held[id] = {}
	for origin in origins:
		_held[id][origin] = true


## Lets go of instances hold() took.
static func release(parent: Node, origins: Array[Vector3]) -> void:
	var id := parent.get_instance_id()
	var held: Dictionary = _held.get(id, {})
	for origin in origins:
		held.erase(origin)
	if held.is_empty():
		_held.erase(id)


## `transforms` without the instances `parent` holds (all of them when it holds none).
static func unheld(parent: Node, transforms: Array[Transform3D]) -> Array[Transform3D]:
	var held: Dictionary = _held.get(parent.get_instance_id(), {})
	if held.is_empty():
		return transforms
	var kept: Array[Transform3D] = []
	for xform in transforms:
		if not held.has(xform.origin):
			kept.append(xform)
	return kept


## True when `mesh` can shrink through the grow uniform (every surface a wind
## ShaderMaterial); false means it sinks instead.
static func shrinks_by_shader(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if not (material is ShaderMaterial and material.has_meta("wind_category")):
			return false
	return true


## Starts a shrink-out of `transforms` of `mesh` under `parent` (which must be in the tree)
## and returns the temporary node, or null when there is nothing to animate. `stem`,
## `suffix` and `wind_category` are the chunk's (see ScatterGlbUtils.build_chunk; the node
## is named after it plus INFIX and a serial); `sink_depth` is how far a sinking species
## travels down (its height).
static func start(
	parent: Node3D,
	mesh: Mesh,
	stem: String,
	suffix: String,
	transforms: Array[Transform3D],
	wind_category: String,
	sink_depth: float,
	seconds: float = SECONDS
) -> MultiMeshInstance3D:
	transforms = unheld(parent, transforms)
	if transforms.is_empty() or mesh == null or seconds <= 0.0 or not parent.is_inside_tree():
		return null
	_serial += 1
	var node := ScatterGlbUtils.build_chunk(
		parent, mesh, stem, transforms, wind_category, suffix + INFIX + str(_serial)
	)
	if node == null:
		return null
	var by_shader := shrinks_by_shader(mesh)
	var depth := maxf(sink_depth, 0.05)
	_apply(1.0, node, by_shader, depth)
	var tween := node.create_tween()
	(
		tween
		. tween_method(_apply.bind(node, by_shader, depth), 1.0, 0.0, seconds)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN)
	)
	tween.tween_callback(node.queue_free)
	return node


## The tallest a set of instances stands: `mesh`'s height times the largest Y scale.
static func sink_depth_for(mesh: Mesh, transforms: Array[Transform3D]) -> float:
	var tallest := 0.0
	for xform in transforms:
		tallest = maxf(tallest, xform.basis.get_scale().y)
	var height := maxf(mesh.get_aabb().end.y, 0.0) if mesh else 0.0
	return height * tallest


static func _apply(value: float, node: MultiMeshInstance3D, by_shader: bool, depth: float) -> void:
	if not is_instance_valid(node):
		return
	if by_shader:
		node.set_instance_shader_parameter(GROW_UNIFORM, value)
	else:
		node.position.y = -depth * (1.0 - value)
