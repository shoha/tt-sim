class_name PipelineWarmer
extends Node3D

## Draws meshes once, invisibly, so the GPU pipelines their first real draw needs (depth,
## colour and shadow passes of that mesh and material as a MultiMesh) compile now rather than
## in the frame they first appear on screen. AuthoredScatter warms each species as it
## resolves, one per frame, which took the wind shader's draw-time compilations off the first
## stroke of a biome (docs/PERFORMANCE.md "First-use pipeline compilation in authoring").
## The first-launch graphics warm-up (GraphicsWarmupScreen) uses it too, for every sample,
## with warm_mesh() for the ones the game draws through a MeshInstance3D.
##
## A warm-up node is a real scatter chunk node (ScatterGlbUtils.build_chunk, so the same
## shadow and cull settings as the nodes it stands in for) holding one instance a thousandth
## of its size just under the ground at the view centre: inside the frustum and the shadow
## cascades, so every pass draws it, but covering no pixel. It lives FRAMES frames. It
## carries no wind_foliage_category meta, so the density budget and the occlusion fade never
## see it.

const FRAMES := 2
const SCALE := 0.001
## How far below the ground under the view centre the instance sits.
const SINK_M := 0.05
const NAME_SUFFIX := "_PipelineWarm"

## {"node": MultiMeshInstance3D, "frames": int} for each warm-up node still being drawn.
var _pending: Array[Dictionary] = []


## True when warming can do anything for `node`: a real renderer (a headless run draws
## nothing) and a camera in its viewport.
static func available(node: Node) -> bool:
	return (
		DisplayServer.get_name() != "headless"
		and node.is_inside_tree()
		and node.get_viewport().get_camera_3d() != null
	)


## Where the centre of the view meets the horizontal plane at `ground_y`, or a point ahead
## of the camera when the view runs parallel to it. Pure.
static func view_ground_point(camera: Camera3D, viewport_size: Vector2, ground_y: float) -> Vector3:
	var centre := viewport_size * 0.5
	var origin := camera.project_ray_origin(centre)
	var direction := camera.project_ray_normal(centre)
	if absf(direction.y) < 0.001:
		return origin + direction * 10.0
	return origin + direction * ((ground_y - origin.y) / direction.y)


func _ready() -> void:
	set_process(false)


## Draws `mesh` (its surface materials as they are now) as a one-instance MultiMesh for FRAMES
## frames, invisibly. For meshes the game draws through MultiMeshes (the scatter).
func warm(mesh: Mesh, stem: String, wind_category: String) -> void:
	if not available(self):
		return
	var transforms: Array[Transform3D] = [_warm_transform()]
	var node := ScatterGlbUtils.build_chunk(self, mesh, stem, transforms, wind_category)
	node.name = stem + NAME_SUFFIX
	node.remove_meta("wind_foliage_category")
	_track(node)


## Draws `mesh` through a plain MeshInstance3D for FRAMES frames, invisibly. For meshes the
## game draws that way (terrain, water).
func warm_mesh(mesh: Mesh, stem: String) -> void:
	if not available(self):
		return
	var node := MeshInstance3D.new()
	node.name = stem + NAME_SUFFIX
	node.mesh = mesh
	node.transform = _warm_transform()
	add_child(node)
	_track(node)


## The tiny, sunk placement at the view centre every warm-up instance uses.
func _warm_transform() -> Transform3D:
	var viewport := get_viewport()
	var at := view_ground_point(
		viewport.get_camera_3d(), viewport.get_visible_rect().size, global_position.y
	)
	return Transform3D(Basis.from_scale(Vector3.ONE * SCALE), to_local(at) + Vector3.DOWN * SINK_M)


func _track(node: Node) -> void:
	_pending.append({"node": node, "frames": FRAMES})
	set_process(true)


## Warm-up nodes still being drawn.
func pending_count() -> int:
	return _pending.size()


func _process(_delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var entry: Dictionary = _pending[i]
		entry.frames -= 1
		if entry.frames <= 0:
			var node: Node = entry.node
			if is_instance_valid(node):
				node.free()
			_pending.remove_at(i)
	if _pending.is_empty():
		set_process(false)
