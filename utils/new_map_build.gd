class_name NewMapBuild
extends RefCounted

## NewMap.from_spec on a worker thread while the loading screen shows (P5-8). The recipe and
## the starting cover are pure document work: a 200 ft gorge took one 1.2 s frame when it ran
## on the main thread in the frame that started the open (docs/PERFORMANCE.md "Phase 5
## (starting landforms)"). AuthoringController starts a build once the loading screen is up
## and awaits wait(), which polls once a frame, then builds the map from the document.
##
## Thread safety. The recipe touches only the new MapDocument (a RefCounted) and objects it
## makes itself (RefCounted crossings and water bodies, a FastNoiseLite, seeded
## RandomNumberGenerators); no Node, no texture or other resource the renderer owns, no
## static var but the palette cache. start() therefore fills that cache on the main thread
## (PaletteLibrary.get_palette) and draws the seed there (from_spec would otherwise draw it
## from the global RNG on the worker), so the worker only reads shared state. Under the
## headless dummy renderer (GlbUtils.threaded_loads_safe false) the build stays on the
## calling thread, as every other threaded load does there; the document is the same.

## The terraforming core's scripts, by path (MapSourceLoader.TERRA_CORE and TERRA_BRIDGE).
const TERRA_CORE := "res://utils/terraform/terra_core.gd"
const TERRA_BRIDGE := "res://utils/terraform/terra_bridge.gd"

var _task: int = -1
var _out: Dictionary = {}


## Starts building the document of new-map `spec` (NewMap.from_spec's keys) under palette
## `root`: on a worker when `threaded`, else now, on the calling thread.
static func start(
	spec: Dictionary,
	root: String = PaletteLibrary.DEFAULT_ROOT,
	threaded: bool = GlbUtils.threaded_loads_safe()
) -> NewMapBuild:
	var build := NewMapBuild.new()
	var seeded := spec.duplicate()
	if not seeded.has("seed"):
		seeded["seed"] = NewMap.random_seed()
	PaletteLibrary.get_palette(root)
	var out := build._out
	var bridge := NewMapBuild._terra_bridge()
	if not threaded:
		out["doc"] = NewMapBuild._build(seeded, root, bridge)
		return build
	build._task = WorkerThreadPool.add_task(
		func() -> void: out["doc"] = NewMapBuild._build(seeded, root, bridge),
		false,
		"NewMapBuild"
	)
	return build


## The recipe, then (switch on) the terrain section TerraBridge.seed_new_map gives it, its whole
## height array swapped for the derive's before any terrain is built.
static func _build(spec: Dictionary, root: String, bridge: GDScript) -> MapDocument:
	var doc := NewMap.from_spec(spec, root)
	if bridge != null:
		bridge.call("seed_new_map", doc)
	return doc


## The bridge script when the terraforming core's switch is on and its library is built, else
## null (loaded by path on the main thread, as MapSourceLoader does, so the start-up script graph
## and the switch-off build are unchanged).
static func _terra_bridge() -> GDScript:
	var core: GDScript = load(TERRA_CORE)
	if not core.call("enabled") or not core.call("native_available"):
		return null
	return load(TERRA_BRIDGE)


## True when the document is ready.
func is_done() -> bool:
	return _task < 0 or WorkerThreadPool.is_task_completed(_task)


## The document, waiting for the worker if it has not finished.
func finish() -> MapDocument:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	return _out.get("doc")


## finish() without blocking a frame: waits a frame at a time on `tree` until the worker is
## done.
func wait(tree: SceneTree) -> MapDocument:
	while not is_done():
		await tree.process_frame
	return finish()
