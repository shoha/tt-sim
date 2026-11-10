class_name GraphicsWarmup
extends RefCounted

## The first-launch graphics warm-up's policy and helpers (GraphicsWarmupScreen runs it, behind
## the title since 2026-11-09: Root._start_warmup).
##
## On a cold shader and pipeline cache, a map's first load compiles the wind, ground and water
## shaders and their pipelines on the main thread: 3 to 4 s single frames on Metal, long
## enough for macOS to mark the app "Not Responding". The warm-up does that work once, behind
## the title screen (a door into a map waits for it), without blocking the main thread (see the
## screen's phases), and records
## a key so it runs again only when something that invalidates the caches changes: the engine
## version, the rendering method, the OS version, the GPU or (on Windows and Linux) its driver,
## or the code of a covered shader or any file it includes. On macOS the Metal compiler belongs
## to the OS and Godot reports no driver, so the OS version stands in for it.
## docs/PERFORMANCE.md "First-launch graphics warm-up" has the numbers.
##
## Every .gdshader under shaders/ is in exactly one of COVERED_SHADERS and EXCLUDED_SHADERS
## (a test checks). A new shader goes in one of them; see AGENTS.md "Adding Features".

## Started at boot, one per frame. Terrain, water, foliage, the structure shaders and the pack
## token look also get a built sample (sample_sources()); the rest are started only, which was
## enough in measurement.
const COVERED_SHADERS := [
	"res://shaders/authored_ground.gdshader",
	"res://shaders/authored_ground_looked.gdshader",
	# The ground clipmap (on by default in play since clipmap2): the read on every played map, the
	# strip bake and its copy. Excluded while it was off by default, which left the first played
	# map to compile the clip ground on a cold cache (clipmap3).
	"res://shaders/authored_ground_clip.gdshader",
	"res://shaders/authored_ground_clip_looked.gdshader",
	"res://shaders/authored_ground_bake.gdshader",
	"res://shaders/authored_ground_bake_looked.gdshader",
	"res://shaders/ground_clipmap_blit.gdshader",
	"res://shaders/avatar_figure.gdshader",
	"res://shaders/avatar_figure_double_sided.gdshader",
	"res://shaders/authored_ground_skirt.gdshader",
	"res://shaders/authored_ground_skirt_looked.gdshader",
	"res://shaders/authored_ground_skirt_ring.gdshader",
	"res://shaders/authored_ground_skirt_ring_looked.gdshader",
	"res://shaders/event_puff.gdshader",
	"res://shaders/fire_flames.gdshader",
	"res://shaders/fire_ground_bake.gdshader",
	"res://shaders/fire_smoke.gdshader",
	"res://shaders/fire_smoke_book.gdshader",
	"res://shaders/grid_overlay.gdshader",
	"res://shaders/ground_burn.gdshader",
	"res://shaders/ground_light_field_bake.gdshader",
	"res://shaders/ground_steep_bake.gdshader",
	"res://shaders/lofi_canvas.gdshader",
	"res://shaders/occlusion_fade.gdshader",
	"res://shaders/selection_glow.gdshader",
	"res://shaders/structure_glow.gdshader",
	"res://shaders/structure_lantern.gdshader",
	"res://shaders/structure_ornament.gdshader",
	"res://shaders/structure_pane.gdshader",
	"res://shaders/structure_roof.gdshader",
	"res://shaders/structure_style_roof.gdshader",
	"res://shaders/structure_style_wall.gdshader",
	"res://shaders/structure_wall.gdshader",
	"res://shaders/structure_water.gdshader",
	"res://shaders/submerged_marker.gdshader",
	"res://shaders/texel_copy_blit.gdshader",
	"res://shaders/token_ghost.gdshader",
	"res://shaders/token_marker.gdshader",
	"res://shaders/token_toon.gdshader",
	"res://shaders/ui_backdrop.gdshader",
	"res://shaders/ui_card_thumb.gdshader",
	"res://shaders/ui_scrim.gdshader",
	"res://shaders/ui_wash_split.gdshader",
	"res://shaders/water.gdshader",
	"res://shaders/waterfall.gdshader",
	"res://shaders/wind_foliage.gdshader",
	"res://shaders/wind_foliage_burn.gdshader",
	"res://shaders/wind_foliage_ground.gdshader",
	"res://shaders/wind_foliage_ground_no_aa.gdshader",
	"res://shaders/wind_foliage_no_aa.gdshader",
	"res://shaders/wind_foliage_painted.gdshader",
	"res://shaders/wind_foliage_painted_no_aa.gdshader",
]
const EXCLUDED_SHADERS := {
	"res://shaders/wind_foliage_debug_cheap_lighting.gdshader": "debug toggles only",
	"res://shaders/wind_foliage_debug_trivial.gdshader": "debug toggles only",
	"res://shaders/wind_foliage_debug_unshaded.gdshader": "debug toggles only",
	"res://shaders/street_sky.gdshader": "sky shader: needs a Sky, the eye view compiles it on entry",
	"res://shaders/pixelate.gdshader": "no references in the code",
	"res://shaders/sharpen.gdshader": "no references in the code",
	"res://shaders/selected_indicator.gdshader": "no references in the code",
}
## A user argument (after `--`) that forces the warm-up, whatever the skip rules say.
const FORCE_ARG := "--warm-graphics"
const MARKER_SECTION := "warmup"
const MARKER_KEY := "key"
const _INCLUDE_PATTERN := '#include\\s+"([^"]+)"'
## The longest finish_behind() waits for the shader in flight (one took up to about 90 ms).
const BEHIND_WAIT_MS := 1000

## The shaders the warm-up started, kept for the session so a later load by path returns the
## same Shader and so the same compiled RID.
static var _held: Array[Shader] = []
## The samples' materials, kept for the session (keep_materials).
static var _held_materials: Array[Material] = []
## WorkerThreadPool tasks still to be waited for (wait_later), collected in release_materials().
static var _late_tasks := PackedInt64Array()
## The compile behind the title of a launch that does not warm (compile_behind), null before it.
static var _behind: Thread = null
## Set by stop_behind(): that compile stops after its current shader, or never starts.
static var _behind_stop := false


static func hold(shader: Shader) -> void:
	assert(shader != null, "GraphicsWarmup.hold: null shader")
	if not _held.has(shader):
		_held.append(shader)


## Keeps the materials of `samples` for the session, so the shaders the warm-up compiled stay
## compiled (a StandardMaterial3D's generated shader goes with its last material) and so freeing
## them never waits on the pipelines the engine is still specializing in the background.
static func keep_materials(samples: Array) -> void:
	for sample: Dictionary in samples:
		var material: Material = sample.get("material")
		if material != null and not _held_materials.has(material):
			_held_materials.append(material)


## How many sample materials the session keeps (keep_materials).
static func kept_material_count() -> int:
	return _held_materials.size()


## Lets the kept materials go. Root calls it on its way out of the tree, while the engine's
## worker threads still run: a material freed with the script statics at exit waited for them
## after they had stopped, and the game never quit (measured, a dev run).
static func release_materials() -> void:
	_held_materials.clear()
	for task in _late_tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_late_tasks.clear()


## Waits for WorkerThreadPool task `task` (every task must be waited for once) at the session's
## end instead of now: the warm-up's drain probe when it gave up before the task ran.
static func wait_later(task: int) -> void:
	_late_tasks.append(task)


## Compiles every covered shader (get_rid) on a low-priority thread behind the title, on a launch
## that does not warm. The warm-up's caches outlive the process, but each process still compiles a
## shader on first use, on the main thread: a map's first sight of the ground cost about 220 ms
## in its creation and 220 ms more in its first view (the looked twins), and the wind shaders 25
## to 30 ms each under the loading sheet (card viewdraw, 2026-11-10, an exported build on warm
## caches). The shaders load and are held here; the thread only compiles. Returns whether it
## started: not headless, not after stop_behind(), once a session.
static func compile_behind() -> bool:
	if _behind != null or _behind_stop or DisplayServer.get_name() == "headless":
		return false
	var shaders: Array[Shader] = []
	for path: String in COVERED_SHADERS:
		var shader := load(path) as Shader
		if shader != null:
			hold(shader)
			shaders.append(shader)
	_behind = Thread.new()
	_behind.start(compile_shaders.bind(shaders), Thread.PRIORITY_LOW)
	return true


## Calls get_rid() on each of `shaders`, which compiles one not yet compiled, until stop_behind().
## Returns how many it reached. Any thread.
static func compile_shaders(shaders: Array[Shader]) -> int:
	var done := 0
	for shader in shaders:
		if _behind_stop:
			break
		shader.get_rid()
		done += 1
	return done


## Whether the compile behind the title is running now (the first-run quality pick waits for it).
static func behind_running() -> bool:
	return _behind != null and _behind.is_alive()


## Stops the compile behind the title after its current shader (or keeps it from starting): Root
## calls it at the doors into a map, which then compile what is left on first use.
static func stop_behind() -> void:
	_behind_stop = true


## Stops the compile behind the title and waits for its current shader, at most BEHIND_WAIT_MS
## (Root's exit: a thread must not be destroyed while it runs; one still running then stays
## referenced here). Returns how many shaders it compiled, or -1 when none ran or it is still
## running.
static func finish_behind() -> int:
	if _behind == null or not _behind.is_started():
		return -1
	_behind_stop = true
	var waited_from := Time.get_ticks_msec()
	while _behind.is_alive() and Time.get_ticks_msec() - waited_from < BEHIND_WAIT_MS:
		OS.delay_msec(5)
	if _behind.is_alive():
		return -1
	var done: int = _behind.wait_to_finish()
	_behind = null
	return done


## Whether `shader`'s get_rid() belongs on the warm-up's worker rather than the main thread.
## A texture_blit shader compiles synchronously on the thread that asks (spatial and
## canvas_item ones start on the WorkerThreadPool): texel_copy_blit cost a 480-490 ms main
## frame cold on an M1 Max, and 700-750 ms on the worker with no main frame over 30 ms.
static func compiles_on_worker(shader: Shader) -> bool:
	return shader.get_mode() == Shader.MODE_TEXTURE_BLIT


## "path\ncode" for each of `paths` and every file they include, transitively, each once,
## sorted. `read` maps a res path to its source text. Pure given `read`.
static func shader_sources_for(paths: Array, read: Callable) -> PackedStringArray:
	var include := RegEx.create_from_string(_INCLUDE_PATTERN)
	var seen := {}
	var todo: Array = paths.duplicate()
	var out := PackedStringArray()
	while not todo.is_empty():
		var path: String = todo.pop_back()
		if seen.has(path):
			continue
		seen[path] = true
		var code: String = read.call(path)
		out.append(path + "\n" + code)
		for found in include.search_all(code):
			var included := found.get_string(1)
			assert(
				included.begins_with("res://"),
				"GraphicsWarmup: %s includes %s; use a res:// path" % [path, included]
			)
			todo.append(included)
	out.sort()
	return out


static func shader_sources() -> PackedStringArray:
	return shader_sources_for(COVERED_SHADERS, _source_of)


## A Shader's or ShaderInclude's code. Loading does not compile: the RID, and with it the
## compile, is created on first get_rid().
static func _source_of(path: String) -> String:
	var resource := load(path)
	assert(resource is Shader or resource is ShaderInclude, "GraphicsWarmup: cannot load " + path)
	return String(resource.code)


static func key_inputs() -> Dictionary:
	return {
		"engine": Engine.get_version_info().string,
		"method": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(),
		# Empty on macOS, where the OS version stands in for the Metal compiler's.
		"driver": ",".join(OS.get_video_adapter_driver_info()),
		"os": OS.get_name() + " " + OS.get_version(),
		"shaders": "\n".join(shader_sources()),
	}


## A sha256 over every input, by name, so no two inputs can run together. Pure.
static func cache_key_for(inputs: Dictionary) -> String:
	var names := inputs.keys()
	names.sort()
	var parts := PackedStringArray()
	for name in names:
		parts.append("%s=%s" % [name, str(inputs[name]).sha256_text()])
	return "\n".join(parts).sha256_text()


static func cache_key() -> String:
	return cache_key_for(key_inputs())


## Whether to warm, from {"display", "editor", "method", "forced", "marker_key", "key"};
## "marker_key" and "key" are read only when neither forced nor skipped_for(). Pure.
static func should_run_for(inputs: Dictionary) -> bool:
	if inputs.forced:
		return true
	if skipped_for(inputs):
		return false
	return inputs.marker_key != inputs.key


## Headless runs draw nothing, the editor binary is a developer's machine, and the
## compatibility renderer has no pipeline caches to warm. Pure.
static func skipped_for(inputs: Dictionary) -> bool:
	return inputs.display == "headless" or inputs.editor or inputs.method == "gl_compatibility"


static func should_run() -> bool:
	var inputs := {
		"display": DisplayServer.get_name(),
		"editor": OS.has_feature("editor"),
		"method": RenderingServer.get_current_rendering_method(),
		"forced": OS.get_cmdline_user_args().has(FORCE_ARG),
	}
	# The key loads and hashes every covered shader and include: only pay for it when the
	# marker decides.
	if not inputs.forced and not skipped_for(inputs):
		inputs["marker_key"] = read_marker()
		inputs["key"] = cache_key()
	return should_run_for(inputs)


## The key of the last completed warm-up, or "" when the marker is missing or unreadable (so
## the warm-up runs).
static func read_marker(path: String = Paths.GRAPHICS_WARMUP_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return ""
	return str(config.get_value(MARKER_SECTION, MARKER_KEY, ""))


## Records `key` as warmed. Returns false (with a warning) when the file cannot be written;
## the warm-up then runs again next launch, which costs time but nothing else.
static func write_marker(key: String, path: String = Paths.GRAPHICS_WARMUP_PATH) -> bool:
	var config := ConfigFile.new()
	config.set_value(MARKER_SECTION, MARKER_KEY, key)
	var err := config.save(path)
	if err != OK:
		push_warning("GraphicsWarmup: could not write %s: %s" % [path, error_string(err)])
	return err == OK


## The flag bits of a surface format (compression and the like), without the per-array bits
## and the format version, for add_surface_from_arrays(..., flags) to rebuild the same layout.
static func format_flags(format: int) -> int:
	return (
		format
		& ~((1 << Mesh.ARRAY_MAX) - 1)
		& ~(
			RenderingServer.ARRAY_FLAG_FORMAT_VERSION_MASK
			<< RenderingServer.ARRAY_FLAG_FORMAT_VERSION_SHIFT
		)
	)


static func valid_sample(sample: Dictionary) -> bool:
	return (
		sample.get("name") is String
		and not String(sample.get("name")).is_empty()
		and sample.get("primitive") is int
		and sample.get("arrays") is Array
		and sample.get("material") is Material
		and sample.get("multimesh") is bool
		and sample.get("flags", 0) is int
	)


## The RenderingServer surface of `sample` with its material, for mesh_create_from_surfaces.
## Built through a scratch mesh because mesh_create_surface_data_from_arrays is not bound in
## GDScript. Safe on a worker thread.
static func surface_data(sample: Dictionary) -> Dictionary:
	assert(
		not (sample.arrays as Array).is_empty(), "GraphicsWarmup: %s has no arrays" % sample.name
	)
	var scratch := RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(
		scratch,
		sample.primitive as RenderingServer.PrimitiveType,
		sample.arrays,
		[],
		{},
		int(sample.get("flags", 0))
	)
	var data: Dictionary = RenderingServer.mesh_get_surface(scratch, 0)
	RenderingServer.free_rid(scratch)
	data["material"] = (sample.material as Material).get_rid()
	return data


## The same surface as an ArrayMesh, for drawing on the main thread once the worker has
## compiled its pipelines.
static func sample_mesh(sample: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		sample.primitive as Mesh.PrimitiveType, sample.arrays, [], {}, int(sample.get("flags", 0))
	)
	mesh.surface_set_material(0, sample.material)
	return mesh


## A bare ShaderMaterial on `shader`. Uniform values do not change pipelines, so a sample
## needs no more than this unless its owner builds a real material cheaply.
static func material_for(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


## Each owner's warmup_samples(), one Callable per owner, so the screen can show progress
## between them. Called on the warm-up's worker thread.
static func sample_sources() -> Array[Callable]:
	# The owners' scripts are loaded by path: naming them would put the play and authoring code
	# on the start-up graph, and this runs only on a first launch (perf audit boot2).
	var water: Variant = load("res://scenes/terrain/authored_water.gd")
	var structures: Variant = load("res://scenes/terrain/structure_warmup.gd")
	var toon: Variant = load("res://scenes/board_token/token_toon.gd")
	return [
		TerrainMeshBuilder.warmup_samples,
		water.warmup_samples,
		WindFoliage.warmup_samples,
		structures.warmup_samples,
		toon.warmup_samples,
	]


## What the screen's status line calls each source's samples, in sample_sources() order.
static func sample_labels() -> PackedStringArray:
	return PackedStringArray(["the ground", "water", "plants", "buildings", "tokens"])


## Every owner's warm-up samples.
static func collect_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for source in sample_sources():
		samples.append_array(source.call())
	return samples
