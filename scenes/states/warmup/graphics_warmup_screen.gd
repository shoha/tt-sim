class_name GraphicsWarmupScreen
extends Node

## The first-launch "Preparing graphics" screen (Root.State.WARMING_UP; GraphicsWarmup has
## the why). Each phase keeps the main thread's frames short, so the window stays responsive:
##   COMPILE  one covered shader per frame: load, hold, get_rid(), which starts its compile on
##            the WorkerThreadPool (starting all of them in one frame cost a 510 ms frame).
##            Shaders that compile on the calling thread instead
##            (GraphicsWarmup.compiles_on_worker) are only loaded here and left to BUILD's
##            worker.
##   BUILD    one Thread compiles those, collects the samples (asset loads and material builds
##            included) and creates a RenderingServer mesh for each; mesh_create_from_surfaces
##            waits for the mesh's pipelines on the calling thread, so the compile waits happen
##            there.
##   DRAW     each built sample drawn invisibly in %WarmupViewport through PipelineWarmer (the
##            draw-time variants), until none is pending. Nothing draws headless.
## Then it writes the marker, frees the meshes and emits `finished`. %WarmupViewport is set up
## like the game world (camera, light, environment, MSAA, debanding) because a pipeline is
## keyed by the framebuffer format as well as the shader and vertex layout.

signal finished

enum Phase { COMPILE, BUILD, DRAW, DONE }

const TITLE := "Preparing graphics"
const STATUS := "Preparing graphics for this version. This can take a few seconds."
## Progress share of COMPILE, BUILD and DRAW.
const PHASE_WEIGHTS: Array[float] = [0.2, 0.7, 0.1]
## The part of BUILD's share given to collecting the samples (one step per source); the rest
## is building them. A fixed split, so the bar never steps back when the sample count becomes
## known. Even because the real split is unmeasured.
const COLLECT_SHARE := 0.5
const LONG_FRAME_MS := 100.0

## Each returns some samples (GraphicsWarmup.collect_samples()'s shape). Called in order on the
## worker thread.
var sample_sources: Array[Callable] = GraphicsWarmup.sample_sources()
var marker_path: String = Paths.GRAPHICS_WARMUP_PATH
var shader_paths: Array = GraphicsWarmup.COVERED_SHADERS
var phase: Phase = Phase.COMPILE

var _environment := LevelEnvironmentManager.new()
var _next_shader := 0
## Filled by COMPILE before the worker starts; the worker only reads it.
var _worker_shaders: Array[Shader] = []
var _thread: Thread = null
var _mutex := Mutex.new()
## Shared with the worker; read and written under _mutex. _collected counts sample_sources
## called, _built and _total the samples.
var _collected := 0
var _built := 0
var _total := 0
var _cancel := false
## Written by the worker only; read on the main thread only after wait_to_finish().
var _results: Array[Dictionary] = []
var _skipped := PackedStringArray()
var _rids: Array[RID] = []
var _warmer: PipelineWarmer = null
var _start_msec := 0
var _phase_start_msec := -1
var _phase_worst_ms := 0.0
var _long_frames := 0
var _last_usec := 0

@onready var _viewport: SubViewport = %WarmupViewport
@onready var _overlay: LoadingOverlay = %LoadingOverlay


## Where the overall progress is at `done` of `total` steps into phase `at`. Pure.
static func progress_for(at: Phase, done: int, total: int) -> float:
	return _progress_at(at, _ratio(done, total))


## The overall progress in BUILD, `collected` of `sources` sample sources called and `built`
## of `total` samples built. Pure.
static func build_progress(collected: int, sources: int, built: int, total: int) -> float:
	return _progress_at(
		Phase.BUILD,
		COLLECT_SHARE * _ratio(collected, sources) + (1.0 - COLLECT_SHARE) * _ratio(built, total)
	)


static func _progress_at(at: Phase, fraction: float) -> float:
	if at == Phase.DONE:
		return 1.0
	var before := 0.0
	for i in int(at):
		before += PHASE_WEIGHTS[i]
	return clampf(before + PHASE_WEIGHTS[at] * fraction, 0.0, 1.0)


static func _ratio(done: int, total: int) -> float:
	return float(done) / total if total > 0 else 0.0


func _ready() -> void:
	_viewport.msaa_3d = VisualEffectsController.saved_antialiasing_level() as Viewport.MSAA
	_environment.apply_level_environment(LevelData.new(), _viewport)
	_overlay.show_loading(TITLE)
	_overlay.set_progress(0.0, STATUS)
	_start_msec = Time.get_ticks_msec()
	_enter_phase(Phase.COMPILE)


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_cancel = true
		_mutex.unlock()
		# The worker's RenderingServer calls wait for the main thread to flush them, so a bare
		# wait_to_finish() deadlocked a quit during BUILD. Keep flushing until it returns.
		while _thread.is_alive():
			RenderingServer.force_sync()
			OS.delay_msec(1)
		_thread.wait_to_finish()
		_thread = null
	_free_meshes()


func progress() -> float:
	match phase:
		Phase.COMPILE:
			return progress_for(phase, _next_shader, shader_paths.size())
		Phase.BUILD:
			_mutex.lock()
			var collected := _collected
			var built := _built
			var total := _total
			_mutex.unlock()
			return build_progress(collected, sample_sources.size(), built, total)
	return progress_for(phase, 0, 1)


## The names of the samples the worker built, in order. Valid once BUILD is over.
func built_names() -> PackedStringArray:
	assert(phase >= Phase.DRAW, "GraphicsWarmupScreen: built_names() before BUILD is over")
	var names := PackedStringArray()
	for sample in _results:
		names.append(String(sample.name))
	return names


## The paths of the shaders COMPILE left to the worker.
func worker_shader_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for shader in _worker_shaders:
		paths.append(shader.resource_path)
	return paths


func _process(_delta: float) -> void:
	_track_frame()
	match phase:
		Phase.COMPILE:
			if _next_shader < shader_paths.size():
				var shader := load(shader_paths[_next_shader]) as Shader
				assert(
					shader != null,
					"GraphicsWarmupScreen: no shader at %s" % shader_paths[_next_shader]
				)
				GraphicsWarmup.hold(shader)
				if GraphicsWarmup.compiles_on_worker(shader):
					_worker_shaders.append(shader)
				else:
					shader.get_rid()
				_next_shader += 1
			else:
				_start_build()
		Phase.BUILD:
			if not _thread.is_alive():
				_thread.wait_to_finish()
				_thread = null
				_start_draw()
		Phase.DRAW:
			if _warmer.pending_count() == 0:
				_finish()
	_overlay.set_progress(progress())


func _start_build() -> void:
	_enter_phase(Phase.BUILD)
	# Lazily created statics the worker's material builds read: create them here so the
	# worker never races a main-thread first use.
	WindFoliage.get_shader()
	WindFoliage.get_shader_no_aa()
	_thread = Thread.new()
	var err := _thread.start(_build)
	assert(err == OK, "GraphicsWarmupScreen: could not start the worker: %s" % error_string(err))


## Worker thread.
func _build() -> void:
	for shader in _worker_shaders:
		shader.get_rid()
	var samples: Array = []
	for source in sample_sources:
		if _cancelled():
			return
		samples.append_array(source.call())
		_mutex.lock()
		_collected += 1
		_mutex.unlock()
	_mutex.lock()
	_total = samples.size()
	_mutex.unlock()
	for sample: Dictionary in samples:
		if _cancelled():
			return
		assert(
			GraphicsWarmup.valid_sample(sample), "GraphicsWarmup: malformed sample %s" % [sample]
		)
		if (sample.arrays as Array).is_empty():
			_skipped.append(String(sample.name))
		else:
			var data := GraphicsWarmup.surface_data(sample)
			_rids.append(RenderingServer.mesh_create_from_surfaces([data]))
			_results.append(sample)
		_mutex.lock()
		_built += 1
		_mutex.unlock()


func _cancelled() -> bool:
	_mutex.lock()
	var cancelled := _cancel
	_mutex.unlock()
	return cancelled


func _start_draw() -> void:
	_enter_phase(Phase.DRAW)
	for sample_name in _skipped:
		push_warning("GraphicsWarmup: sample %s has no geometry; skipped" % sample_name)
	_warmer = PipelineWarmer.new()
	_viewport.add_child(_warmer)
	for sample in _results:
		var mesh := GraphicsWarmup.sample_mesh(sample)
		if sample.multimesh:
			# No wind category: build_chunk then keeps shadow casting on for every sample, so
			# the shadow-pass variants trees need are warmed too.
			_warmer.warm(mesh, String(sample.name), "")
		else:
			_warmer.warm_mesh(mesh, String(sample.name))


func _finish() -> void:
	_enter_phase(Phase.DONE)
	# This frame's _process still sets the bar to 1.0 after we return; nothing after that.
	set_process(false)
	GraphicsWarmup.write_marker(GraphicsWarmup.cache_key(), marker_path)
	_free_meshes()
	print(
		(
			"GraphicsWarmup: done in %d ms, %d samples built, %d skipped, %d frames over %.0f ms"
			% [
				Time.get_ticks_msec() - _start_msec,
				_results.size(),
				_skipped.size(),
				_long_frames,
				LONG_FRAME_MS
			]
		)
	)
	finished.emit()


func _free_meshes() -> void:
	for rid in _rids:
		RenderingServer.free_rid(rid)
	_rids.clear()


func _enter_phase(next: Phase) -> void:
	if _phase_start_msec >= 0:
		print(
			(
				"GraphicsWarmup: %s took %d ms, worst frame %.0f ms"
				% [Phase.keys()[phase], Time.get_ticks_msec() - _phase_start_msec, _phase_worst_ms]
			)
		)
	phase = next
	_phase_start_msec = Time.get_ticks_msec()
	_phase_worst_ms = 0.0


func _track_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		var ms := (now - _last_usec) / 1000.0
		_phase_worst_ms = maxf(_phase_worst_ms, ms)
		if ms > LONG_FRAME_MS:
			_long_frames += 1
			print("GraphicsWarmup: %.0f ms frame in %s" % [ms, Phase.keys()[phase]])
	_last_usec = now
