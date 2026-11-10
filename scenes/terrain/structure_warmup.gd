class_name StructureWarmup
extends Node

## Pays the first-use costs of a building before the first one is put down (hitches2 and hitches3,
## docs/PERFORMANCE.md "Build hitches, round 2" and "round 3"): opening the Structure or Village
## tool starts it, so a cold first place no longer parses the decor GLBs (about 70 ms), decodes the
## baked masonry (about 55 ms) and compiles each structure shader in the frame it lands.
##
## Model. One node under the map's AuthoredStructures, made once per map (warm() is idempotent). A
## worker task (never waited on from inside the pool) parses the decor library
## (StructureLoadInfo.info_of, thread-safe under AssetStore's lock) and decodes the masonry images.
## The main thread then works through a queue of units, two per (kind, role) of COMBOS, in that
## order (the surfaces a first building draws first): MAKE, one material through AuthoredStructures'
## own cache (so an install takes the same objects) and its RID (the shader compiles here, 6 to 30
## ms), and DRAW, that material drawn once, invisibly, through a PipelineWarmer (its pipelines
## compile in that frame's render, about 20 ms more). The two never share a frame: round 2 made and
## drew one a frame, 45 to 50 ms (and read its mesh back from the GPU each time through
## ArrayMesh.duplicate, about 5 ms). Per frame it takes units until BUDGET_MS of its own time has
## gone, a DRAW ending the frame; and it takes none in a frame that follows a slow one (over
## IDLE_FRAME_MS, at most MAX_WAIT_FRAMES in a row), so the compiles spread over idle frames instead
## of stacking on a stroke. Closing the tool pauses it (pause()); opening it again resumes where it
## stopped. Nothing it makes changes what a build looks like: the materials are the ones an install
## would make, made earlier.
##
## The first-launch graphics warm-up (GraphicsWarmupScreen) takes the heavy part of this off the
## tool open: warmup_samples() hands it one triangle per structure shader, on the layout of a
## building's surfaces, so the shaders' pipelines compile under the "Preparing graphics" screen.
## This session warm-up then finds them compiled and costs a few milliseconds.

## A unit: one material made (its shader compiles), or that material drawn once.
enum Phase { MAKE, DRAW }

const NODE_NAME := "StructureWarmup"
## One (kind, role) per structure shader and per distinct texture set (StructureMaterials.make),
## the surfaces of a common first building (walls, roof, trim, panes, ivy) first.
const COMBOS: Array[Array] = [
	["masonry", StructureLook.WALL],
	["tile", StructureLook.ROOF],
	["stone", StructureLook.TRIM],
	["glass", StructureLook.OPENING],
	["leaf", StructureLook.ORNAMENT],
	["boards", StructureLook.WALL],
	["plaster", StructureLook.WALL],
	["thatch", StructureLook.ROOF],
	["glass", StructureLook.PROP],
	["wood", StructureLook.PROP],
	[StructureGlow.KIND, StructureLook.PROP],
	["stone", StructureLook.WATER],
]
## Main-thread milliseconds a frame may spend before it stops taking units (a unit already begun
## runs to its end: one shader compile cannot be split).
const BUDGET_MS := 8.0
## A frame slower than this (the previous one, as process delta) is busy: no unit this frame.
const IDLE_FRAME_MS := 20.0
## Busy frames waited out in a row before a unit runs anyway (a slow machine still warms).
const MAX_WAIT_FRAMES := 4
## Units per combo, one per Phase.
const UNITS_PER_COMBO := 2
## The structure shaders the first-launch graphics warm-up draws (warmup_samples), by sample name:
## one bare ShaderMaterial each, since a pipeline is keyed by the shader and the vertex layout and
## not by uniform values. The wall shader serves masonry and boards, the ornament shader leaves,
## cloth, metal and wood, and so on; a style or a kind adds no pipeline.
const SAMPLE_SHADERS := {
	"structure_wall": StructureMaterials.WALL_SHADER,
	"structure_roof": StructureMaterials.ROOF_SHADER,
	"structure_style_wall": StructureMaterials.STYLE_WALL_SHADER,
	"structure_style_roof": StructureMaterials.STYLE_ROOF_SHADER,
	"structure_pane": StructureMaterials.PANE_SHADER,
	"structure_ornament": StructureMaterials.ORNAMENT_SHADER,
	"structure_lantern": StructureMaterials.LANTERN_SHADER,
	"structure_glow": StructureMaterials.GLOW_SHADER,
	"structure_water": StructureMaterials.WATER_SHADER,
}
const STONE_SAMPLE := "structure_stone"
const YARD_GROUND_SAMPLE := "structure_yard_ground"
const YARD_PROPS_SAMPLE := "structure_yard_props"

## The last warm-up's units in order, {"frame", "combo", "phase", "ms"} (process frame, COMBOS
## index, Phase, main-thread ms); the hitches probe and the tests read it.
static var last_log: Array[Dictionary] = []
## False makes an authoring open warm nothing ahead of the Structure tool
## (StructureTool.warm_ahead): the performance harness's in-run A/B switch (card structopen).
static var ahead_enabled: bool = true

## Units done so far (unit u: combo u / UNITS_PER_COMBO, phase u % UNITS_PER_COMBO), and whether
## the worker's part is taken.
var units_done: int = 0
var worker_taken: bool = false
## While true (the tool was closed) no unit runs; the worker's part still finishes.
var paused: bool = false
## Per-instance copies of the limits, so a test can tighten them.
var budget_ms: float = BUDGET_MS
var idle_frame_ms: float = IDLE_FRAME_MS

var _structures: AuthoredStructures = null
var _styles: PackedStringArray = PackedStringArray()
var _root: String = PaletteLibrary.DEFAULT_ROOT
var _task: int = -1
var _images: Dictionary = {}
var _warmer: PipelineWarmer = null
var _quad_arrays: Array = []
var _made: Array[Material] = []
var _waited: int = 0


## Starts (or resumes) the warm-up for `structures`' map, its buildings in the styles `styles` (the
## map's biome ids). A call while one exists resumes it and returns it; after it finished, does
## nothing and returns null.
static func warm(
	structures: AuthoredStructures, styles: PackedStringArray, root: String
) -> StructureWarmup:
	if structures == null:
		return null
	var held := structures.get_node_or_null(NODE_NAME) as StructureWarmup
	if held != null:
		held.paused = false
		return held
	if structures.has_meta(NODE_NAME):
		return null
	structures.set_meta(NODE_NAME, true)
	last_log = []
	var node := StructureWarmup.new()
	node.name = NODE_NAME
	node._structures = structures
	node._styles = styles if not styles.is_empty() else PackedStringArray([""])
	node._root = root
	structures.add_child(node)
	return node


## Starts the library maps a MAKE unit would bake in its own frame on the prebake lane, behind any
## map a load waits for (SurfaceStore.PRIORITY_AHEAD): the planks of `boards:wall`
## (StructureMaterials._timber), whose three maps baked in that unit, a 267 ms frame of the tool's
## first open in a fresh user folder (card structopen). An authoring open calls it as it begins;
## maps already baked or queued are left alone.
static func prebake_surfaces() -> void:
	SurfaceStore.prebake(
		PackedStringArray([LibraryBindings.crossing_planks()]), SurfaceStore.PRIORITY_AHEAD
	)


## Holds `structures`' warm-up where it is (the Structure or Village tool was put down), so its
## compiles never land on another tool's strokes. Safe with none running.
static func pause(structures: AuthoredStructures) -> void:
	if structures == null:
		return
	var held := structures.get_node_or_null(NODE_NAME) as StructureWarmup
	if held != null:
		held.paused = true


## pause() for the AuthoredStructures under map root `map_root`, when there is one (never made
## here).
static func pause_map(map_root: Node) -> void:
	if map_root != null and is_instance_valid(map_root):
		pause(map_root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures)


## Lets the warm-up under map root `map_root` go on after a pause_map() (the brush is up again).
static func resume_map(map_root: Node) -> void:
	if map_root == null or not is_instance_valid(map_root):
		return
	var structures := map_root.get_node_or_null(AuthoredStructures.NODE_NAME)
	var held := structures.get_node_or_null(NODE_NAME) as StructureWarmup if structures else null
	if held != null:
		held.paused = false


## The number of units in a full warm-up.
static func unit_count() -> int:
	return COMBOS.size() * UNITS_PER_COMBO


## GraphicsWarmup samples (the first-launch warm-up screen draws them): one triangle in each
## structure shader on the layout a building's surfaces have, plus the modelled stone and the two
## yard materials, so the pipelines a first building needs compile under the "Preparing graphics"
## screen and not when the Structure tool opens (docs/PERFORMANCE.md "Structure shaders in the
## first-launch warm-up"). Safe on a worker thread: it only makes resources.
static func warmup_samples() -> Array[Dictionary]:
	var arrays := quad_arrays()
	var samples: Array[Dictionary] = []
	for sample_name: String in SAMPLE_SHADERS:
		var shader: Shader = SAMPLE_SHADERS[sample_name]
		samples.append(_sample(sample_name, arrays, GraphicsWarmup.material_for(shader)))
	samples.append(_sample(STONE_SAMPLE, arrays, _stone_material()))
	var yard := yard_arrays()
	samples.append(_sample(YARD_GROUND_SAMPLE, yard, StructureMaterials.dressing_ground()))
	samples.append(_sample(YARD_PROPS_SAMPLE, yard, StructureMaterials.dressing_props()))
	return samples


## One triangle with the layout of a structure surface (StructureGeometry.surface_arrays: vertex,
## normal, UV, colour, tangent, index).
static func quad_arrays() -> Array:
	return StructureGeometry.surface_arrays(
		"stone",
		PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]),
		PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
		PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		PackedInt32Array([0, 1, 2])
	)


## One triangle with the layout of a yard mesh (StructureDressingShapes: vertex, normal, colour,
## index; no UV and no tangent).
static func yard_arrays() -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	return arrays


static func _sample(sample_name: String, arrays: Array, material: Material) -> Dictionary:
	return {
		"name": sample_name,
		"primitive": Mesh.PRIMITIVE_TRIANGLES,
		"arrays": arrays,
		"material": material,
		"multimesh": false,
	}


## The modelled stone of a trim (StructureMaterials._stone, AuthoredCrossings.surface_material):
## a vertex-colour ORM material with albedo, normal and ORM textures, triplanar. The textures are
## placeholders; a pipeline does not depend on what a sampler holds.
static func _stone_material() -> ORMMaterial3D:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var material := ORMMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.normal_enabled = true
	material.normal_texture = texture
	material.orm_texture = texture
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	return material


func _ready() -> void:
	_made.resize(COMBOS.size())
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


func _process(delta: float) -> void:
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
	if units_done >= unit_count():
		if _warmer.pending_count() == 0:
			set_process(false)
			queue_free()
		return
	if paused:
		return
	if delta * 1000.0 > idle_frame_ms and _waited < MAX_WAIT_FRAMES:
		_waited += 1
		return
	_waited = 0
	_run_frame()


## Takes units until the budget is spent, a draw ends the frame, or the next unit is the DRAW of a
## material made this frame.
func _run_frame() -> void:
	var frame := Engine.get_process_frames()
	var began := Time.get_ticks_usec()
	while units_done < unit_count():
		var combo := units_done / UNITS_PER_COMBO
		var phase := units_done % UNITS_PER_COMBO
		if phase == Phase.DRAW and _made_in(combo) == frame:
			return
		var unit_began := Time.get_ticks_usec()
		if phase == Phase.MAKE:
			_make(combo)
		else:
			_draw(combo)
		last_log.append(
			{
				"frame": frame,
				"combo": combo,
				"phase": phase,
				"ms": (Time.get_ticks_usec() - unit_began) / 1000.0,
			}
		)
		units_done += 1
		if phase != Phase.MAKE or (Time.get_ticks_usec() - began) / 1000.0 >= budget_ms:
			return


## The process frame combo `combo`'s material was made in (from the log), or -1.
func _made_in(combo: int) -> int:
	for k in range(last_log.size() - 1, -1, -1):
		var entry: Dictionary = last_log[k]
		if int(entry.combo) == combo and int(entry.phase) == Phase.MAKE:
			return int(entry.frame)
	return -1


## One material of COMBOS[`combo`] for the first style and its RID (the shader compiles here; a
## StandardMaterial3D's own shader is generated here too, not in the DRAW frame).
func _make(combo: int) -> void:
	if not is_instance_valid(_structures):
		return
	var pair: Array = COMBOS[combo]
	var material := _structures.shared_material(String(pair[0]), String(pair[1]), _styles[0])
	if material != null:
		material.get_rid()
	_made[combo] = material


## Draws the material made for `combo` once, invisibly (its pipelines compile in this frame's
## render).
func _draw(combo: int) -> void:
	var material := _made[combo]
	if material == null:
		return
	var pair: Array = COMBOS[combo]
	_warmer.warm_mesh(_quad_mesh(material), "structure_%s_%s" % [pair[0], pair[1]])


## A one-triangle mesh with the attributes a structure surface carries (normal, colour, UV,
## tangent) in `material`, built from its arrays (duplicating an ArrayMesh reads its buffers back
## from the GPU).
func _quad_mesh(material: Material) -> ArrayMesh:
	if _quad_arrays.is_empty():
		_quad_arrays = quad_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad_arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _exit_tree() -> void:
	# A map closed mid warm-up: the worker reads only shared, locked data; wait it out.
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
