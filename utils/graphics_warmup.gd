class_name GraphicsWarmup
extends RefCounted

## The first-launch graphics warm-up's policy and helpers (the screen that runs it is
## GraphicsWarmupScreen, entered as Root.State.WARMING_UP).
##
## On a cold shader and pipeline cache, a map's first load compiles the wind, ground and water
## shaders and their pipelines on the main thread: 3 to 4 s single frames on Metal, long
## enough for macOS to mark the app "Not Responding". The warm-up does that work once, before
## the title screen, without blocking the main thread (see the screen's phases), and records
## a key so it runs again only when something that invalidates the caches changes: the engine
## version, the rendering method, the OS version, the GPU or (on Windows and Linux) its driver,
## or the code of a covered shader or any file it includes. On macOS the Metal compiler belongs
## to the OS and Godot reports no driver, so the OS version stands in for it.
## docs/PERFORMANCE.md "First-launch graphics warm-up" has the numbers.
##
## Every .gdshader under shaders/ is in exactly one of COVERED_SHADERS and EXCLUDED_SHADERS
## (a test checks). A new shader goes in one of them; see AGENTS.md "Adding Features".

## Started at boot, one per frame. Only those listed also get a built sample (terrain, water
## and foliage); the rest are started only, which was enough in measurement.
const COVERED_SHADERS := [
	"res://shaders/authored_ground.gdshader",
	"res://shaders/avatar_figure.gdshader",
	"res://shaders/avatar_figure_double_sided.gdshader",
	"res://shaders/authored_ground_skirt.gdshader",
	"res://shaders/event_puff.gdshader",
	"res://shaders/grid_overlay.gdshader",
	"res://shaders/lofi_canvas.gdshader",
	"res://shaders/occlusion_fade.gdshader",
	"res://shaders/selection_glow.gdshader",
	"res://shaders/submerged_marker.gdshader",
	"res://shaders/texel_copy_blit.gdshader",
	"res://shaders/ui_backdrop.gdshader",
	"res://shaders/ui_card_thumb.gdshader",
	"res://shaders/ui_map_placeholder.gdshader",
	"res://shaders/ui_scrim.gdshader",
	"res://shaders/water.gdshader",
	"res://shaders/waterfall.gdshader",
	"res://shaders/wind_foliage.gdshader",
	"res://shaders/wind_foliage_no_aa.gdshader",
]
const EXCLUDED_SHADERS := {
	"res://shaders/wind_foliage_debug_cheap_lighting.gdshader": "debug toggles only",
	"res://shaders/wind_foliage_debug_trivial.gdshader": "debug toggles only",
	"res://shaders/wind_foliage_debug_unshaded.gdshader": "debug toggles only",
	"res://shaders/pixelate.gdshader": "no references in the code",
	"res://shaders/sharpen.gdshader": "no references in the code",
	"res://shaders/selected_indicator.gdshader": "no references in the code",
}
## A user argument (after `--`) that forces the warm-up, whatever the skip rules say.
const FORCE_ARG := "--warm-graphics"
const MARKER_SECTION := "warmup"
const MARKER_KEY := "key"
const _INCLUDE_PATTERN := '#include\\s+"([^"]+)"'

## The shaders the warm-up started, kept for the session so a later load by path returns the
## same Shader and so the same compiled RID.
static var _held: Array[Shader] = []


static func hold(shader: Shader) -> void:
	assert(shader != null, "GraphicsWarmup.hold: null shader")
	if not _held.has(shader):
		_held.append(shader)


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
	return [
		TerrainMeshBuilder.warmup_samples,
		AuthoredWater.warmup_samples,
		WindFoliage.warmup_samples,
	]


## Every owner's warm-up samples.
static func collect_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for source in sample_sources():
		samples.append_array(source.call())
	return samples
