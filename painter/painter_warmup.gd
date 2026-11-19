class_name PainterWarmup
extends RefCounted
## Compiles the painted look's shaders and pipelines before the first Painted draw, off the main
## thread (card painter-perf-warmup, docs/systems/painter.md "Warm-up").
##
## The cost. The first Painted level of a session (and the first switch Classic -> Painted in a
## running level) draws the painter shaders (covered_shaders()) in their vertex layouts for the
## first time: about 94 surface pipelines in a first level (41 in a toggle, 12 more for the bare
## winter trees), each compiled on the main thread at the first draw. Windowed debug build, a warm
## Godot cache: a 1.1 s frame under the loading overlay; with the Godot shader and pipeline caches
## off (a first launch, a new GPU driver) the toggle froze 1.5 s and the winter switch 1.5 s again.
##
## The model. One coordinator thread (start()) loads the painter scripts (so the first Painted
## `take` compiles no GDScript), then builds one tiny mesh for every (shader, vertex layout) the
## painter draws, on a bare ShaderMaterial of the real shader (a pipeline is keyed by the shader and
## the layout, not by uniform values), several threads at once. A RenderingServer mesh made from a
## surface with a material compiles that material's surface pipelines on the calling thread
## (GraphicsWarmup, docs/PERFORMANCE.md "First-launch graphics warm-up"), so the compiles land on
## these workers and the real draw finds them. The layouts are listed below (LAYOUT_*), pure data
## with no palette or scene state, so the worker can run beside a level load; a test pins each of
## them against the format the real producer makes (and the format measured on a live level). Two
## groups: BASE (the summer look) is ready first, BARE (the leaf-drop tree shaders of a bare
## season) follows.
##
## Who calls it. Root starts it behind the title when the Look choice can paint (RenderStyle.choice
## is not Classic): that run is LITE (lite_title): it loads the scripts and the default sheet and
## compiles the shaders, and makes no samples. LevelEnvironmentManager requests the full run for
## each new world, before anything is drawn in it (a level's environment apply marks the world
## stale, the first Painted check requests the run), and holds the Painted draw until is_ready():
## polled each frame, so the window never freezes, and a level load keeps its overlay up meanwhile
## (painter_pending). A Classic session never starts it. Headless runs draw nothing: is_ready() is
## true there and start() does nothing.
##
## Why the title run makes no samples (card painter-perf-cold, first Painted level, Godot caches
## off, debug build): a full run at the title, then a second run over the level's world, left the
## main thread three frames of 1.0 to 1.8 s (the level's own first draws still compiled about 57
## surface and 48 specialization pipelines, and the main thread stalled 1.3 s as the second run's
## workers started), worst covered frame 1429 to 1521 ms in six runs. With the title run lite and
## the full run made once, over the level's world, before the Painted apply, the same level shows
## a worst frame of about 200 ms and no surface pipeline compiles at the apply.
##
## This script names no painter script (their constants are copied below and a test compares them),
## so loading it compiles none of the painter's GDScript on the main thread.

enum Phase { IDLE, BASE_RUNNING, BASE_DONE, ALL_DONE, LITE_DONE }

const SCRIPTS: PackedStringArray = [
	"res://painter/painter_scene.gd",
	"res://painter/painter_surfaces.gd",
	"res://painter/trees/painter_trees.gd",
	"res://painter/painter_buildings.gd",
	"res://painter/buildings/manner_host.gd",
	"res://painter/painter_water.gd",
]
const GROUND := "res://painter/shaders/painter_ground.gdshader"
const PLANT := "res://painter/shaders/painter_plant.gdshader"
const SOLID := "res://painter/shaders/painter_solid.gdshader"
const STRUCTURE := "res://painter/shaders/painter_structure.gdshader"
const MANNER := "res://painter/shaders/painter_structure_manner.gdshader"
const YARD := "res://painter/shaders/painter_yard.gdshader"
const YARD_GROUND := "res://painter/shaders/painter_yard_ground.gdshader"
const PROP := "res://painter/shaders/painter_prop.gdshader"
const GLOW := "res://painter/shaders/painter_glow.gdshader"
## The decor ivy's contact shade (PainterIvyContact), a second pass over the decor's leaf cards.
const IVY_CONTACT := "res://painter/shaders/painter_ivy_contact.gdshader"
const TREE_STROKE := "res://painter/shaders/painter_tree_stroke.gdshader"
const TREE_BLOCKIN := "res://painter/shaders/painter_tree_blockin.gdshader"
const TREE_STROKE_BARE := "res://painter/shaders/painter_tree_stroke_bare.gdshader"
const TREE_BLOCKIN_BARE := "res://painter/shaders/painter_tree_blockin_bare.gdshader"
# The discard-free camera masses (PainterTreeFast), in leaf and in a bare season.
const TREE_BLOCKIN_FAST := "res://painter/shaders/painter_tree_blockin_fast.gdshader"
const TREE_BLOCKIN_FAST_BARE := "res://painter/shaders/painter_tree_blockin_fast_bare.gdshader"
# The variants a tree an event burns draws with (painter-fire), warmed with their group so the first
# fire compiles nothing on the main thread.
const TREE_STROKE_BURN := "res://painter/shaders/painter_tree_stroke_burn.gdshader"
const TREE_BLOCKIN_BURN := "res://painter/shaders/painter_tree_blockin_burn.gdshader"
const TREE_STROKE_BARE_BURN := "res://painter/shaders/painter_tree_stroke_bare_burn.gdshader"
const TREE_BLOCKIN_BARE_BURN := "res://painter/shaders/painter_tree_blockin_bare_burn.gdshader"
## The water's two shaders (PainterWater.SHADER, FALL_SHADER).
const WATER := "res://painter/shaders/painter_water.gdshader"
const WATERFALL := "res://painter/shaders/painter_waterfall.gdshader"
## The sky (PainterScene.SKY_SHADER) draws through a Sky, not a mesh: it is only compiled here.
const SKY := "res://painter/shaders/painter_sky.gdshader"
## The vertex layouts the painter draws, as the slots each fills (the engine adds the tangent flag
## itself where there are normals), measured on a live Painted level and pinned by
## test_painter_warmup: the ground's chunks and skirt, a plant's or a stand-in's surface (with and
## without vertex colour), a tree's blocks and strokes (PainterTreeMeshes), a structure's surface
## (StructureGeometry.surface_arrays), a yard's (StructureDressingShapes) and a manner mesh's
## (PainterMannerMesh.build).
const LAYOUT_GROUND: Array[int] = [
	Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX
]
const LAYOUT_LIT: Array[int] = [
	Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX
]
## A lantern halo's quad (StructureGlow.of).
const LAYOUT_GLOW: Array[int] = [
	Mesh.ARRAY_VERTEX,
	Mesh.ARRAY_NORMAL,
	Mesh.ARRAY_COLOR,
	Mesh.ARRAY_TEX_UV,
	Mesh.ARRAY_TEX_UV2,
	Mesh.ARRAY_INDEX
]
const LAYOUT_PLAIN: Array[int] = [
	Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX
]
const LAYOUT_TREE: Array[int] = [
	Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX
]
const LAYOUT_YARD: Array[int] = [
	Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX
]
const LAYOUT_MANNER: Array[int] = [
	Mesh.ARRAY_VERTEX,
	Mesh.ARRAY_NORMAL,
	Mesh.ARRAY_COLOR,
	Mesh.ARRAY_TEX_UV2,
	Mesh.ARRAY_CUSTOM0,
	Mesh.ARRAY_INDEX
]
## The falls' mesh (WaterFallMesh: curtain, ring and mist in one surface) and the authored water
## surface (WaterMeshBuilder), both with the fall frames in CUSTOM0 and CUSTOM1 (FRAME_FLAGS); a
## Blender plane and the river ribbon past the map edge are LAYOUT_PLAIN.
const LAYOUT_FALL: Array[int] = [
	Mesh.ARRAY_VERTEX,
	Mesh.ARRAY_NORMAL,
	Mesh.ARRAY_COLOR,
	Mesh.ARRAY_TEX_UV,
	Mesh.ARRAY_TEX_UV2,
	Mesh.ARRAY_CUSTOM0,
	Mesh.ARRAY_CUSTOM1,
	Mesh.ARRAY_INDEX
]
const LAYOUT_WATER: Array[int] = [
	Mesh.ARRAY_VERTEX,
	Mesh.ARRAY_NORMAL,
	Mesh.ARRAY_TEX_UV,
	Mesh.ARRAY_CUSTOM0,
	Mesh.ARRAY_CUSTOM1,
	Mesh.ARRAY_INDEX
]
## What the manner meshes carry in CUSTOM0 (PainterMannerMesh.FORMAT).
const MANNER_FLAGS := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
## What the water surface and the falls carry in CUSTOM0 and CUSTOM1 (WaterFallFrames.FORMAT).
const FRAME_FLAGS := (
	(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
)
const SHEET_SCRIPT := "res://painter/sheet.gd"
## The sheet a look names when it names none (RenderStyle.DEFAULT_SHEET).
const DEFAULT_SHEET := "core"
const MAX_WORKERS := 6
## The longest release() waits for the thread.
const EXIT_WAIT_MS := 1000

## What the last run did, for probes and tests: {"scripts_ms", "base_ms", "bare_ms", "samples"}.
static var stats: Dictionary = {}
## Threads that build samples at once; 0 picks from the processor count (probes set it).
static var worker_count := 0

static var _mutex := Mutex.new()
static var _phase := Phase.IDLE
static var _thread: Thread = null
## The samples' materials by sample name, kept for the session: a shader's compiled pipelines go
## with its last material (GraphicsWarmup.keep_materials). A new run replaces its own.
static var _kept: Dictionary = {}
static var _queue: Array[Dictionary] = []
static var _next := 0
static var _meshes: Array[RID] = []
## Set by release(): the thread and its workers stop after the step they are on.
static var _stop := false
## True from request() until the thread's last step (under _mutex).
static var _running := false
## A run was asked for (request(true)) while one was running: the thread makes another when it ends.
static var _again := false
## The run in progress is the title's: scripts and shaders only, no samples.
static var _lite := false
## Whether start() (the title's run) is lite; false makes it a full run (probes compare the two).
static var lite_title := true
## Whether the scripts and the default sheet were loaded (the first run does it).
static var _loaded := false


## Every painter shader this warms (a test compares it with painter/shaders).
static func covered_shaders() -> PackedStringArray:
	var all := base_shaders()
	all.append_array(bare_shaders())
	all.append(SKY)
	return all


## The shaders of the summer look.
static func base_shaders() -> PackedStringArray:
	return PackedStringArray(
		[
			GROUND,
			PLANT,
			SOLID,
			STRUCTURE,
			MANNER,
			YARD,
			YARD_GROUND,
			PROP,
			GLOW,
			IVY_CONTACT,
			TREE_STROKE,
			TREE_BLOCKIN,
			TREE_BLOCKIN_FAST,
			TREE_STROKE_BURN,
			TREE_BLOCKIN_BURN,
			WATER,
			WATERFALL
		]
	)


## The leaf-drop tree shaders of a bare season.
static func bare_shaders() -> PackedStringArray:
	return PackedStringArray(
		[
			TREE_STROKE_BARE,
			TREE_BLOCKIN_BARE,
			TREE_BLOCKIN_FAST_BARE,
			TREE_STROKE_BARE_BURN,
			TREE_BLOCKIN_BARE_BURN
		]
	)


## Whether the engine has anything to warm: false headless (nothing draws).
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


## Whether the look (`sheet` id, `mood`, sun `elevation`) draws its trees bare, as PainterTrees
## retone decides: the sheet's leaf-keep below 1.
static func needs_bare(sheet: String, mood: String, elevation: float) -> bool:
	var sheets: Variant = load(SHEET_SCRIPT)
	return float(sheets.number(sheets.load_sheet(sheet), mood, "leaf-keep", elevation)) < 0.999


## Starts the warm-up on a thread of its own the first time (a no-op when it has run or is running,
## and headless). At the title it compiles the shaders and loads the scripts.
static func start() -> void:
	request(false, lite_title)


## Starts a warm-up run: with `again` even after an earlier one finished, so the pipelines are made
## for the world a level has built (the engine compiles for the framebuffer, lights and environment
## features it knows of). A full run is also what follows a lite one (`lite`: scripts and shaders
## only, the title's). A run over finished work costs a few milliseconds. While one is running,
## `again` queues one more run behind it (the running one may have been made for an earlier
## world), and is_ready() is false until it is done.
static func request(again: bool, lite: bool = false) -> void:
	if not available():
		return
	_mutex.lock()
	var go := not _running and (
		again or _phase == Phase.IDLE or (_phase == Phase.LITE_DONE and not lite)
	)
	if go:
		_running = true
		_lite = lite and not again and _phase == Phase.IDLE
		_phase = Phase.BASE_RUNNING
	elif again and _running:
		_again = true
	_mutex.unlock()
	if not go:
		return
	if _thread != null:
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_coordinate)


## Whether the summer look (or, with `bare`, the bare season's tree shaders too) is compiled.
## True headless; false before start().
static func is_ready(bare: bool = false) -> bool:
	if not available():
		return true
	_mutex.lock()
	var phase := _phase
	var queued := _again
	_mutex.unlock()
	if queued:
		return false
	return phase == Phase.ALL_DONE or (phase == Phase.BASE_DONE and not bare)


## Stops the warm-up after the step it is on and lets the kept materials go (Root's exit; safe to
## call twice). A thread still running after EXIT_WAIT_MS stays referenced, so it is never destroyed
## running (GraphicsWarmup.finish_behind does the same).
static func release() -> void:
	_stop = true
	if _thread != null and _thread.is_started():
		var from := Time.get_ticks_msec()
		while _thread.is_alive() and Time.get_ticks_msec() - from < EXIT_WAIT_MS:
			OS.delay_msec(5)
		if _thread.is_alive():
			return
		_thread.wait_to_finish()
	_thread = null
	_kept.clear()


## The tiny triangle with a layout's slots filled: `slots` are Mesh.ARRAY_* indices.
static func triangle(slots: Array[int]) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var three := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD])
	var uv := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	for slot in slots:
		match slot:
			Mesh.ARRAY_VERTEX:
				arrays[slot] = three
			Mesh.ARRAY_NORMAL:
				arrays[slot] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
			Mesh.ARRAY_COLOR:
				arrays[slot] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				arrays[slot] = uv
			Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1:
				arrays[slot] = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0])
			Mesh.ARRAY_INDEX:
				arrays[slot] = PackedInt32Array([0, 1, 2])
	return arrays


## Every sample of a group: GraphicsWarmup's shape, one per (shader, layout). Pure resources, no
## palette and no shared state, so it is safe on the worker while the main thread loads a level.
## `bare` is the leaf-drop tree shaders; else the summer look's.
static func collect(bare: bool) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if bare:
		_add(samples, "tree_stroke_bare", TREE_STROKE_BARE, LAYOUT_TREE, 0)
		_add(samples, "tree_blockin_bare", TREE_BLOCKIN_BARE, LAYOUT_TREE, 0)
		_add(samples, "tree_blockin_fast_bare", TREE_BLOCKIN_FAST_BARE, LAYOUT_TREE, 0)
		_add(samples, "tree_stroke_bare_burn", TREE_STROKE_BARE_BURN, LAYOUT_TREE, 0)
		_add(samples, "tree_blockin_bare_burn", TREE_BLOCKIN_BARE_BURN, LAYOUT_TREE, 0)
		return samples
	_add(samples, "ground", GROUND, LAYOUT_GROUND, 0)
	# A GLB map's terrain (PainterGlbMap) is a Blender mesh: no second UV set.
	_add(samples, "ground_plain", GROUND, LAYOUT_PLAIN, 0)
	_add(samples, "plant_lit", PLANT, LAYOUT_LIT, 0)
	_add(samples, "plant_plain", PLANT, LAYOUT_PLAIN, 0)
	_add(samples, "solid_lit", SOLID, LAYOUT_LIT, 0)
	_add(samples, "solid_plain", SOLID, LAYOUT_PLAIN, 0)
	_add(samples, "tree_stroke", TREE_STROKE, LAYOUT_TREE, 0)
	_add(samples, "tree_blockin", TREE_BLOCKIN, LAYOUT_TREE, 0)
	_add(samples, "tree_blockin_fast", TREE_BLOCKIN_FAST, LAYOUT_TREE, 0)
	_add(samples, "tree_stroke_burn", TREE_STROKE_BURN, LAYOUT_TREE, 0)
	_add(samples, "tree_blockin_burn", TREE_BLOCKIN_BURN, LAYOUT_TREE, 0)
	_add(samples, "structure", STRUCTURE, LAYOUT_LIT, 0)
	# A street row's wood carries its house flags in UV2 (WallGeometry.house_flags).
	_add(samples, "structure_row_wood", STRUCTURE, LAYOUT_GLOW, 0)
	_add(samples, "ivy_contact", IVY_CONTACT, LAYOUT_LIT, 0)
	_add(samples, "yard", YARD, LAYOUT_YARD, 0)
	_add(samples, "yard_ground", YARD_GROUND, LAYOUT_YARD, 0)
	_add(samples, "prop", PROP, LAYOUT_LIT, 0)
	_add(samples, "glow", GLOW, LAYOUT_GLOW, 0)
	_add(samples, "manner", MANNER, LAYOUT_MANNER, MANNER_FLAGS)
	_add(samples, "water", WATER, LAYOUT_PLAIN, 0)
	_add(samples, "water_framed", WATER, LAYOUT_WATER, FRAME_FLAGS)
	_add(samples, "waterfall", WATERFALL, LAYOUT_FALL, FRAME_FLAGS)
	return samples


static func _add(
	samples: Array[Dictionary], sample_name: String, path: String, layout: Array[int], flags: int
) -> void:
	samples.append(
		{
			"name": sample_name,
			"primitive": Mesh.PRIMITIVE_TRIANGLES,
			"arrays": triangle(layout),
			"material": GraphicsWarmup.material_for(load(path) as Shader),
			"multimesh": false,
			"flags": flags,
		}
	)


## The thread: runs once, then again for as long as a request(true) arrived meanwhile.
static func _coordinate() -> void:
	while _run_once():
		_mutex.lock()
		var more := _again and not _stop
		_again = false
		if more:
			_phase = Phase.BASE_RUNNING
			_lite = false
		else:
			_running = false
		_mutex.unlock()
		if not more:
			return
	_finish_run()


## One run of the groups, true when it got to the end (false: release() stopped it).
static func _run_once() -> bool:
	var t0 := Time.get_ticks_msec()
	if not _loaded:
		for path in SCRIPTS:
			if _stop:
				return false
			ResourceLoader.load(path)
		# The default sheet's parse (about 140 ms) off the main thread: nothing reads the sheet
		# cache until is_ready() says the base group is done.
		var sheets: Variant = load(SHEET_SCRIPT)
		sheets.load_sheet(DEFAULT_SHEET)
		_loaded = true
	var t1 := Time.get_ticks_msec()
	if _lite:
		var all: Array[Shader] = []
		for path in covered_shaders():
			var shader := load(path) as Shader
			if shader != null:
				all.append(shader)
		all.append_array(FireVariants.all_variants())
		GraphicsWarmup.compile_shaders(all)
		_set_phase(Phase.LITE_DONE)
		return true
	var total := 0
	var base := collect(false)
	total += base.size()
	var shaders: Array[Shader] = []
	var sky := load(SKY) as Shader
	if sky != null:
		shaders.append(sky)
	# The Painted fire's variants (FireVariants), so the first event fire compiles nothing.
	shaders.append_array(FireVariants.all_variants())
	GraphicsWarmup.compile_shaders(shaders)
	_build(base)
	var t2 := Time.get_ticks_msec()
	_set_phase(Phase.BASE_DONE)
	var bare := collect(true)
	total += bare.size()
	_build(bare)
	var t3 := Time.get_ticks_msec()
	stats = {"scripts_ms": t1 - t0, "base_ms": t2 - t1, "bare_ms": t3 - t2, "samples": total}
	_set_phase(Phase.ALL_DONE)
	return true


static func _set_phase(phase: Phase) -> void:
	_mutex.lock()
	_phase = phase
	_mutex.unlock()


static func _finish_run() -> void:
	_mutex.lock()
	_running = false
	_mutex.unlock()


## Builds every sample on several threads and waits for them: each makes a RenderingServer mesh,
## which compiles the sample's pipelines.
static func _build(samples: Array[Dictionary]) -> void:
	_queue = samples
	_next = 0
	var workers := worker_count
	if workers <= 0:
		workers = clampi(OS.get_processor_count() / 2, 2, MAX_WORKERS)
	var threads: Array[Thread] = []
	for i in workers:
		var thread := Thread.new()
		thread.start(_work)
		threads.append(thread)
	for thread in threads:
		thread.wait_to_finish()
	_mutex.lock()
	for sample in samples:
		_kept[sample.name] = sample.material
	_mutex.unlock()
	for mesh in _meshes:
		RenderingServer.free_rid(mesh)
	_meshes.clear()


static func _work() -> void:
	while true:
		_mutex.lock()
		var index := _next
		_next += 1
		_mutex.unlock()
		if index >= _queue.size() or _stop:
			return
		var sample: Dictionary = _queue[index]
		var mesh := RenderingServer.mesh_create_from_surfaces([GraphicsWarmup.surface_data(sample)])
		_mutex.lock()
		_meshes.append(mesh)
		_mutex.unlock()
