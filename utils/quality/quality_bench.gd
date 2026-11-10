class_name QualityBench
extends Node

## A short GPU measurement behind the title: how long this computer takes to draw a small fixed
## table with the shipped graphics defaults, for QualityAuto's first-run pick and Settings'
## Re-detect (docs/systems/graphics_quality.md).
##
## The table is the game's own frame in miniature: the game's environment and sun
## (LevelEnvironmentManager, as the graphics warm-up builds them: sky, glow, the camera's
## attributes, the sun's four blended cascades at the Soft High tier, ambient occlusion on), a
## textured ground and a field of alpha-cut foliage cards that cast shadows, seen through the
## warm-up's home-view camera, in a viewport of the world render's pixel size for this window
## (InterfaceSize.world_pixel_size, the game's full render). So it pays the passes the game pays
## (the depth pre-pass with its normal buffer, the shadow maps, the opaque pass's filtered shadow
## lookups, the occlusion and the glow) in about the game's proportions; QualityAuto's
## GAME_PER_BENCH maps its time to a real map's.
##
## Phases, each a few frames, none of them long:
##   BUILD   one Thread makes the meshes and the materials and creates a RenderingServer mesh of
##           each, so their pipelines compile there and not at the first draw on the main thread
##           (GraphicsWarmup.surface_data; the warm-up's BUILD does the same).
##   RAMP    the viewport draws for at least RAMP_MS, until its GPU time stops falling
##           (settled()), so the GPU's clocks rise to their working level. At the title, vsync is
##           off and the frame rate uncapped meanwhile (LoadPacing's cover plus Engine.max_fps 0:
##           nothing moves on the title, so no tear shows), else a fast GPU drawing a few ms per
##           paced frame stays at idle clocks and reads slower than it is. It also waits until no
##           pipeline has compiled for QUIET_MS: on a cold driver cache the specialized pipelines
##           compile in the background while slower ubershaders draw.
##   SAMPLE  the viewport's measured GPU time, per frame, for at least SAMPLE_MS and MIN_SAMPLES
##           frames; the result is their median. A compile meanwhile sends it back to RAMP.
## Then it puts back what it changed (vsync, the frame cap, the global soft-shadow tier), frees its
## viewport and
## emits `measured` once: {"ok", "gpu_ms", "samples", "frame_ms" (the sampled frames' median
## time), "restarts" (compiles that sent SAMPLE back), "size", "scale", "adapter_type", "adapter",
## "elapsed_ms"}. ok is false (gpu_ms 0) headless, when it was aborted, or when the
## driver reports no GPU time; QualityAuto then falls back on the adapter type.

signal measured(result: Dictionary)

enum Phase { BUILD, RAMP, SAMPLE, DONE }

const RAMP_MS := 500
## How long the pipeline compile counters must stand still before sampling starts.
const QUIET_MS := 400
## The ramp also lasts until its GPU times stop falling: the last SETTLE_WINDOW frames' median
## within SETTLE_TOLERANCE of the window's before (settled()).
const SETTLE_WINDOW := 15
const SETTLE_TOLERANCE := 0.05
## When frames are paced well above the GPU's work (a driver-forced vsync: on the dev machine an
## exported game's frames hold 14 ms, two refreshes at 144 Hz, whatever the game asks), the GPU
## idles most of each frame and keeps its idle clocks (200 to 600 MHz measured), reading about
## 35 % slow. After LOAD_PROBE_FRAMES ramp frames the run adds up to LOAD_MAX more viewports
## drawing the same world, so the GPU's work fills the frame and its clocks rise (extra_load()).
const LOAD_PROBE_FRAMES := 20
const LOAD_MAX := 5
const SAMPLE_MS := 800
const MIN_SAMPLES := 30
## The longest a run may take from its first frame (a GPU so slow that 30 frames take longer
## ends with what it has).
const CAP_MS := 8000
## A developer's emulation knob (docs/PERFORMANCE.md "Quality presets"): the viewport is drawn
## at this many times the world render's size per axis, so a fast GPU pays a slow one's frame.
const SCALE_ARG := "--quality-bench-scale="
## The ground's side in metres and the foliage field's.
const GROUND_SIZE := 64.0
const FIELD_SIZE := 52.0
## Foliage cards (three crossed quads each) and taller "trees" (the same, larger).
const CLUMPS := 30000
const TREES := 260
const SEED := 20261110
## The warm-up's home-view camera (graphics_warmup_screen.tscn).
const CAMERA_TRANSFORM := Transform3D(
	Vector3(0.7071068, 0, -0.7071068),
	Vector3(-0.26030335, 0.9297765, -0.26030335),
	Vector3(0.6574513, 0.36812454, 0.6574513),
	Vector3(11.088, 8, 11.088)
)
const CAMERA_SIZE := 13.85

## Per-axis multiple of the world render's size (SCALE_ARG overrides it).
var scale := 1.0
## Whether the run may turn vsync off for itself (only at the title: over a map it would tear).
var may_cover := true

var _phase := Phase.BUILD
var _thread: Thread = null
var _built: Dictionary = {}
var _viewport: SubViewport = null
var _environment: LevelEnvironmentManager = null
var _start_msec := 0
var _phase_msec := 0
var _samples := PackedFloat32Array()
## The sampled frames' own times (the result's frame_ms: a frame-rate cap shows there).
var _frame_samples := PackedFloat32Array()
var _frame_usec := 0
## The pipeline compile count last seen, when it last changed, and how often it did during the run.
var _compiles := -1
var _quiet_msec := 0
var _restarts := 0
## What paces the frames when sampling starts (pacing_state()), for the result.
var _pacing: Dictionary = {}
## Engine.max_fps under the cover, put back by _restore(); -1 when the run did not change it.
var _saved_max_fps := -1
## The ramp's GPU times: sampling waits until they stop falling (settled()).
var _ramp_samples := PackedFloat32Array()
## The ramp's frame times, and the extra viewports drawing the same world (_add_load()).
var _ramp_frames := PackedFloat32Array()
var _load: Array[SubViewport] = []
var _saved_shadow_quality := -1
var _covered := false
var _aborted := false
var _size := Vector2i.ZERO


## The per-axis scale [param args] (OS.get_cmdline_user_args()) ask for, else [param fallback].
## Pure.
static func scale_from_args(args: PackedStringArray, fallback: float) -> float:
	for arg in args:
		if arg.begins_with(SCALE_ARG):
			var value := arg.substr(SCALE_ARG.length()).to_float()
			if value > 0.0:
				return clampf(value, 0.25, 4.0)
	return fallback


## The median of [param values] (0 for none). Pure.
static func median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) * 0.5


## Ends the run now (a door into a map opened): it emits ok false and "aborted" true, and frees
## itself.
func abort() -> void:
	if _phase != Phase.DONE:
		_aborted = true
		_finish(false)


func _ready() -> void:
	_start_msec = Time.get_ticks_msec()
	scale = scale_from_args(OS.get_cmdline_user_args(), scale)
	if DisplayServer.get_name() == "headless":
		_finish.call_deferred(false)
		return
	_thread = Thread.new()
	_thread.start(_build_meshes)


func _exit_tree() -> void:
	if _thread != null:
		# The worker's RenderingServer calls wait for the main thread to flush them.
		while _thread.is_alive():
			RenderingServer.force_sync()
			OS.delay_msec(1)
		_thread.wait_to_finish()
		_thread = null
	_restore()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _phase == Phase.RAMP or _phase == Phase.SAMPLE:
		var compiles := compile_count()
		if compiles != _compiles:
			_compiles = compiles
			_quiet_msec = now
			if _phase == Phase.SAMPLE and now - _start_msec < CAP_MS:
				_restarts += 1
				_samples.clear()
				_frame_samples.clear()
				_ramp_samples.clear()
				_enter(Phase.RAMP)
	match _phase:
		Phase.BUILD:
			if not _thread.is_alive():
				_built = _thread.wait_to_finish()
				_thread = null
				_assemble()
				_enter(Phase.RAMP)
		Phase.RAMP:
			var ramp_gpu := RenderingServer.viewport_get_measured_render_time_gpu(
				_viewport.get_viewport_rid()
			)
			if ramp_gpu > 0.0:
				_ramp_samples.append(ramp_gpu)
			var usec := Time.get_ticks_usec()
			if _frame_usec > 0:
				_ramp_frames.append((usec - _frame_usec) / 1000.0)
			_frame_usec = usec
			if _load.is_empty() and _ramp_samples.size() == LOAD_PROBE_FRAMES:
				# The fastest GPU time so far: early frames read slow while the clocks are low.
				var fastest := _ramp_samples.duplicate()
				fastest.sort()
				_add_load(extra_load(median(_ramp_frames), fastest[0]))
			var ready := now - _quiet_msec >= QUIET_MS and settled(_ramp_samples)
			if (now - _phase_msec >= RAMP_MS and ready) or now - _start_msec >= CAP_MS:
				_enter(Phase.SAMPLE)
				_frame_usec = Time.get_ticks_usec()
				_pacing = pacing_state()
		Phase.SAMPLE:
			var gpu := RenderingServer.viewport_get_measured_render_time_gpu(
				_viewport.get_viewport_rid()
			)
			if gpu > 0.0:
				_samples.append(gpu)
			var usec := Time.get_ticks_usec()
			_frame_samples.append((usec - _frame_usec) / 1000.0)
			_frame_usec = usec
			var enough := now - _phase_msec >= SAMPLE_MS and _samples.size() >= MIN_SAMPLES
			if enough or now - _start_msec >= CAP_MS + SAMPLE_MS:
				_finish(not _samples.is_empty())


## How many extra viewports fill a frame of [param frame_ms] whose measured viewport takes
## [param gpu_ms] of GPU: none when the frame is about the GPU's own work, at most LOAD_MAX. Pure.
static func extra_load(frame_ms: float, gpu_ms: float) -> int:
	if gpu_ms <= 0.0 or frame_ms < gpu_ms * 1.5:
		return 0
	return clampi(int(ceil(frame_ms / gpu_ms)) - 1, 1, LOAD_MAX)


## Whether the ramp's GPU times have stopped falling (the clocks are up): the median of the last
## SETTLE_WINDOW samples is no more than SETTLE_TOLERANCE below the median of the window before.
## Pure.
static func settled(values: PackedFloat32Array) -> bool:
	var n := values.size()
	if n < SETTLE_WINDOW * 2:
		return false
	var last := median(values.slice(n - SETTLE_WINDOW))
	var before := median(values.slice(n - SETTLE_WINDOW * 2, n - SETTLE_WINDOW))
	return last >= before * (1.0 - SETTLE_TOLERANCE)


## What paces the main loop now: the vsync mode, the frame cap, LoadPacing's cover, the idle
## throttle's state and the window's focus (the result's "pacing").
static func pacing_state() -> Dictionary:
	return {
		"vsync": int(DisplayServer.window_get_vsync_mode()),
		"max_fps": Engine.max_fps,
		"covered": LoadPacing.is_covered(),
		"throttle_busy": IdleThrottle.busy,
		"throttle_focused": IdleThrottle.focused,
		"focused": DisplayServer.window_is_focused(),
		"fps": Engine.get_frames_per_second(),
	}


## Every pipeline compile so far (canvas, mesh, surface, draw and specialization): RAMP waits for
## it to stand still.
static func compile_count() -> int:
	var total := 0.0
	for monitor in [
		Performance.PIPELINE_COMPILATIONS_CANVAS,
		Performance.PIPELINE_COMPILATIONS_MESH,
		Performance.PIPELINE_COMPILATIONS_SURFACE,
		Performance.PIPELINE_COMPILATIONS_DRAW,
		Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
	]:
		total += Performance.get_monitor(monitor)
	return int(total)


func _enter(next: Phase) -> void:
	_phase = next
	_phase_msec = Time.get_ticks_msec()


## The worker: every mesh and material, each mesh also created once as a RenderingServer mesh
## with its material so its pipelines compile on this thread. Returns them for _assemble().
func _build_meshes() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ground_mat := _ground_material(rng)
	var card_mat := _card_material(rng)
	var ground := {
		"name": "bench ground",
		"arrays": _ground_arrays(),
		"primitive": Mesh.PRIMITIVE_TRIANGLES,
		"material": ground_mat,
	}
	var card := {
		"name": "bench card",
		"arrays": _card_arrays(),
		"primitive": Mesh.PRIMITIVE_TRIANGLES,
		"material": card_mat,
	}
	var rids: Array[RID] = []
	for sample in [ground, card]:
		rids.append(RenderingServer.mesh_create_from_surfaces([GraphicsWarmup.surface_data(sample)]))
	return {
		"ground": ground,
		"card": card,
		"rids": rids,
		"clumps": _instances(rng, CLUMPS, 0.35, 0.9),
		"trees": _instances(rng, TREES, 2.5, 5.0),
	}


## The viewport, the environment and sun, the camera and the two draws, on the main thread.
func _assemble() -> void:
	var window := get_window()
	var factor := InterfaceSize.world_render_scale(window)
	var base := Vector2(window.content_scale_size)
	if base.x <= 0.0 or base.y <= 0.0:
		base = InterfaceSize.BASE_SIZE
	var full := InterfaceSize.world_pixel_size(Vector2(window.size), factor, base)
	_size = Vector2i(roundi(full.x * scale), roundi(full.y * scale))
	_viewport = SubViewport.new()
	_viewport.name = "QualityBenchViewport"
	_viewport.own_world_3d = true
	_viewport.size = _size
	_viewport.use_debanding = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_environment = LevelEnvironmentManager.new()
	_environment.apply_level_environment(LevelData.new(), _viewport)
	# The shipped defaults, whatever this player has saved: occlusion on, four blended cascades,
	# the Soft High tier (global: put back in _restore()).
	_environment.apply_rendering_toggles(true, false, false)
	ShadowCascades.apply_in(_viewport, ShadowCascades.BLENDED)
	# The engine has no getter for the tier: the one in force is the saved one (Root applied it at
	# startup, and Settings' Apply saves what it applies).
	var config := ConfigFile.new()
	config.load(Paths.SETTINGS_PATH)
	_saved_shadow_quality = int(SettingsMenu.saved_shadow_quality(config))
	RenderingServer.directional_soft_shadow_filter_set_quality(SettingsMenu.DEFAULT_SHADOW_QUALITY)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.near = 0.001
	camera.far = 1000.0
	camera.transform = CAMERA_TRANSFORM
	camera.current = true
	_viewport.add_child(camera)
	_viewport.add_child(_mesh_instance(_built.ground))
	_viewport.add_child(_multimesh_instance(_built.card, _built.clumps))
	_viewport.add_child(_multimesh_instance(_built.card, _built.trees))
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	if may_cover:
		LoadPacing.cover(self)
		_covered = true
		# Uncapped as well: the cover's 240 fps cap sleeps between frames, and on Windows a window
		# that is not in front sleeps in 15.6 ms steps, so the GPU idled at 200 to 600 MHz and read
		# 35 % slow (exported first launch, card autoquality). Put back in _restore().
		_saved_max_fps = Engine.max_fps
		Engine.max_fps = 0


## Adds [param count] viewports drawing the bench's world through their own copy of its camera
## (freed with the bench), and restarts the settle check under the new load.
func _add_load(count: int) -> void:
	for i in count:
		var extra := SubViewport.new()
		extra.name = "QualityBenchLoad%d" % i
		# The bench viewport owns its world (own_world_3d), which only find_world_3d() returns.
		extra.world_3d = _viewport.find_world_3d()
		extra.size = _size
		extra.msaa_3d = Viewport.MSAA_DISABLED
		extra.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = CAMERA_SIZE
		camera.near = 0.001
		camera.far = 1000.0
		camera.transform = CAMERA_TRANSFORM
		camera.current = true
		extra.add_child(camera)
		add_child(extra)
		_load.append(extra)
	if count > 0:
		_ramp_samples.clear()


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	var gpu_ms := median(_samples) if ok else 0.0
	var result := {
		"ok": ok and gpu_ms > 0.0,
		"aborted": _aborted,
		"gpu_ms": gpu_ms,
		"samples": _samples.size(),
		"frame_ms": median(_frame_samples),
		"restarts": _restarts,
		"pacing": _pacing,
		"ramp_frames": _ramp_samples.size(),
		"load": _load.size(),
		"size": _size,
		"scale": scale,
		"adapter_type": int(RenderingServer.get_video_adapter_type()),
		"adapter": RenderingServer.get_video_adapter_name(),
		"elapsed_ms": Time.get_ticks_msec() - _start_msec,
	}
	_restore()
	measured.emit(result)
	queue_free()


## Puts back the frame cap, vsync and the soft-shadow tier and frees the meshes the worker made.
## Safe twice.
func _restore() -> void:
	if _saved_max_fps >= 0:
		# The cover's cap first: its uncover puts the player's own back after it.
		Engine.max_fps = _saved_max_fps
		_saved_max_fps = -1
	if _covered:
		LoadPacing.uncover(self)
		_covered = false
	if _saved_shadow_quality >= 0:
		RenderingServer.directional_soft_shadow_filter_set_quality(_saved_shadow_quality)
		_saved_shadow_quality = -1
	for rid: RID in _built.get("rids", []):
		if rid.is_valid():
			RenderingServer.free_rid(rid)
	_built.erase("rids")
	if _viewport != null:
		RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), false)


static func _mesh_instance(sample: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = GraphicsWarmup.sample_mesh(sample)
	return mi


static func _multimesh_instance(sample: Dictionary, buffer: PackedFloat32Array) -> Node3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = GraphicsWarmup.sample_mesh(sample)
	mm.instance_count = buffer.size() / 12
	mm.buffer = buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## A ground of GROUND_SIZE, 64 x 64 quads with gentle relief, normals up-ish.
static func _ground_arrays() -> Array:
	var n := 64
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	for z in n + 1:
		for x in n + 1:
			var u := float(x) / n
			var v := float(z) / n
			var px := (u - 0.5) * GROUND_SIZE
			var pz := (v - 0.5) * GROUND_SIZE
			verts.append(Vector3(px, 0.6 * sin(px * 0.21) * cos(pz * 0.17), pz))
			normals.append(Vector3.UP)
			uvs.append(Vector2(u, v) * 12.0)
			tangents.append_array([1.0, 0.0, 0.0, 1.0])
	for z in n:
		for x in n:
			var i := z * (n + 1) + x
			indices.append_array([i, i + 1, i + n + 1, i + 1, i + n + 2, i + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Three crossed unit quads (1 wide, 1 tall, base at the origin), a foliage card.
static func _card_arrays() -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in 3:
		var a := PI * k / 3.0
		var side := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var normal := Vector3(-sin(a), 0.35, cos(a)).normalized()
		var at := verts.size()
		verts.append_array([-side, side, side + Vector3.UP, -side + Vector3.UP])
		normals.append_array([normal, normal, normal, normal])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		indices.append_array([at, at + 1, at + 2, at, at + 2, at + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## [param count] instance transforms (MultiMesh TRANSFORM_3D buffer layout) over the field,
## [param low] to [param high] metres tall, a random yaw each.
static func _instances(
	rng: RandomNumberGenerator, count: int, low: float, high: float
) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(count * 12)
	for i in count:
		var s := rng.randf_range(low, high)
		var yaw := rng.randf() * TAU
		var x := rng.randf_range(-0.5, 0.5) * FIELD_SIZE
		var z := rng.randf_range(-0.5, 0.5) * FIELD_SIZE
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s * 0.8, s, s * 0.8))
		var o := i * 12
		buffer[o + 0] = basis.x.x
		buffer[o + 1] = basis.y.x
		buffer[o + 2] = basis.z.x
		buffer[o + 3] = x
		buffer[o + 4] = basis.x.y
		buffer[o + 5] = basis.y.y
		buffer[o + 6] = basis.z.y
		buffer[o + 7] = 0.6 * sin(x * 0.21) * cos(z * 0.17)
		buffer[o + 8] = basis.x.z
		buffer[o + 9] = basis.y.z
		buffer[o + 10] = basis.z.z
		buffer[o + 11] = z
	return buffer


## A lit ground with colour, normal and roughness maps (made here, 256 px, mipmapped).
static func _ground_material(rng: RandomNumberGenerator) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_texture(rng, Color(0.36, 0.5, 0.22), Color(0.55, 0.47, 0.3))
	mat.normal_enabled = true
	mat.normal_texture = _noise_texture(rng, Color(0.45, 0.45, 1.0), Color(0.55, 0.55, 1.0))
	mat.roughness_texture = _noise_texture(rng, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## An alpha-cut, two-sided foliage card with a ragged mask, casting shadows.
static func _card_material(rng: RandomNumberGenerator) -> StandardMaterial3D:
	var size := 64
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var edge := absf(x - size * 0.5) / (size * 0.5)
			var keep := rng.randf() > edge * 1.2 + (1.0 - float(y) / size) * 0.25
			var shade := rng.randf_range(0.7, 1.0)
			img.set_pixel(x, y, Color(0.3 * shade, 0.55 * shade, 0.2 * shade, 1.0 if keep else 0.0))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _noise_texture(rng: RandomNumberGenerator, a: Color, b: Color) -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, a.lerp(b, rng.randf()))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
