class_name StructureWarmup
extends Node

## Pays the first-use costs of a building before the first one is put down (hitches2, docs/
## PERFORMANCE.md "Build hitches, round 2"): opening the Structure or Village tool starts it, so a
## cold first place no longer parses the decor GLBs (about 70 ms), decodes the baked masonry (about
## 55 ms) and compiles each structure shader (15 to 25 ms apiece) in the frame it lands.
##
## Model. One node under the map's AuthoredStructures, made once (warm() is idempotent). A worker
## task (never waited on from inside the pool) parses the decor library (StructureLoadInfo.info_of,
## thread-safe under AssetStore's lock) and decodes the masonry images; the main thread then makes
## one material of each structure shader per frame, through AuthoredStructures' own material cache
## (so an install takes the same objects), and draws each once, invisibly, through a
## PipelineWarmer. Nothing it makes changes what a build looks like: the materials are the ones an
## install would make, made earlier.

const NODE_NAME := "StructureWarmup"
## One (kind, role) per structure shader and per distinct texture set (StructureMaterials.make).
const COMBOS: Array[Array] = [
	["masonry", StructureLook.WALL],
	["boards", StructureLook.WALL],
	["tile", StructureLook.ROOF],
	["thatch", StructureLook.ROOF],
	["plaster", StructureLook.WALL],
	["stone", StructureLook.TRIM],
	["glass", StructureLook.OPENING],
	["leaf", StructureLook.ORNAMENT],
	["glass", StructureLook.PROP],
	["wood", StructureLook.PROP],
	[StructureGlow.KIND, StructureLook.PROP],
	["stone", StructureLook.WATER],
]

## Steps done so far (a step: one material), and whether the worker's part has been taken.
var steps_done: int = 0
var worker_taken: bool = false

var _structures: AuthoredStructures = null
var _styles: PackedStringArray = PackedStringArray()
var _root: String = PaletteLibrary.DEFAULT_ROOT
var _task: int = -1
var _images: Dictionary = {}
var _warmer: PipelineWarmer = null
var _quad: ArrayMesh = null


## Starts the warm-up for `structures`' map, its buildings in the styles `styles` (the map's biome
## ids). A second call while one exists, or after it finished, does nothing. Returns the node.
static func warm(
	structures: AuthoredStructures, styles: PackedStringArray, root: String
) -> StructureWarmup:
	if structures == null:
		return null
	var held := structures.get_node_or_null(NODE_NAME) as StructureWarmup
	if held != null:
		return held
	if structures.has_meta(NODE_NAME):
		return null
	structures.set_meta(NODE_NAME, true)
	var node := StructureWarmup.new()
	node.name = NODE_NAME
	node._structures = structures
	node._styles = styles if not styles.is_empty() else PackedStringArray([""])
	node._root = root
	structures.add_child(node)
	return node


func _ready() -> void:
	if GlbUtils.threaded_loads_safe():
		_task = WorkerThreadPool.add_task(_work, false, "Structure warm-up")
	_warmer = PipelineWarmer.new()
	_warmer.name = "Pipelines"
	add_child(_warmer)


## The worker's part: pure reads (the decor GLBs under AssetStore's lock, the masonry images).
func _work() -> void:
	if StructureDecor.available(_root):
		StructureLoadInfo.info_of(_root)
	_images = MasonryTextures.decode()


func _process(_delta: float) -> void:
	if not worker_taken:
		if _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
			return
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
			MasonryTextures.adopt(_images)
		_task = -1
		_images = {}
		worker_taken = true
		return
	if steps_done < COMBOS.size():
		_step(COMBOS[steps_done])
		steps_done += 1
		return
	if _warmer.pending_count() == 0:
		set_process(false)
		queue_free()


## One material of `combo` for the first style (the shader compiles here), drawn once.
func _step(combo: Array) -> void:
	if not is_instance_valid(_structures):
		return
	var material := _structures.shared_material(String(combo[0]), String(combo[1]), _styles[0])
	if material == null:
		return
	var mesh := _quad_mesh().duplicate() as ArrayMesh
	mesh.surface_set_material(0, material)
	_warmer.warm_mesh(mesh, "structure_%s_%s" % [combo[0], combo[1]])


## A one-triangle mesh with the attributes a structure surface carries (normal, colour, UV).
func _quad_mesh() -> ArrayMesh:
	if _quad != null:
		return _quad
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	_quad = ArrayMesh.new()
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _quad


func _exit_tree() -> void:
	# A map closed mid warm-up: the worker reads only shared, locked data; wait it out.
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
