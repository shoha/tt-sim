class_name GraphicsWarmupScreen
extends Node

## The first-launch graphics warm-up (GraphicsWarmup has the why). Root runs it behind the title
## with its "Preparing graphics" bar hidden (`background`) and shows the bar (show_progress) when a
## door into a map has to wait for it. Each phase keeps the main thread's frames short:
##   COMPILE  one covered shader per frame: load, hold, get_rid(), which starts its compile on
##            the WorkerThreadPool (starting all of them in one frame cost a 510 ms frame).
##            Shaders that compile on the calling thread instead
##            (GraphicsWarmup.compiles_on_worker) are only loaded here and left to BUILD's
##            worker.
##   BUILD    one coordinating Thread, which first runs those compiles and every sample source
##            at once (a thread each: asset loads and material builds included), then starts
##            build_workers threads that take the samples from one queue and create a
##            RenderingServer mesh for each. mesh_create_from_surfaces waits for the mesh's
##            pipelines on the calling thread, so the compile waits happen there, several at
##            a time (one thread doing them in turn took 15 s of the 17 s).
##   DRAW     each built sample drawn invisibly in %WarmupViewport through PipelineWarmer (the
##            draw-time variants), until none is pending. Nothing draws headless. Then it waits
##            for the engine's background compiles to drain (_drained): the specialized
##            pipelines those draws ask for compile on the WorkerThreadPool afterwards, and a map
##            opened before they are done froze for 3.8 to 4.1 s (card firstlaunch2).
## The bar is weighted by phase (PHASE_WEIGHTS) and the line under it says what is going on
## (status_for): shaders started, then the group of samples (the ground, water, plants,
## buildings) being gathered and compiled with a count, then the first frame.
## Then it writes the marker, frees the meshes, keeps the samples' materials for the session
## (GraphicsWarmup.keep_materials) and emits `finished`. %WarmupViewport is set up
## like the game world (camera, light, environment, MSAA, debanding) because a pipeline is
## keyed by the framebuffer format as well as the shader and vertex layout.

signal finished

enum Phase { COMPILE, BUILD, DRAW, DONE }

const TITLE := "Preparing graphics"
## The status line while DRAW waits for the drain.
const DRAINING := "Finishing shaders"
## Progress share of COMPILE, BUILD and DRAW: their measured time shares on a true first launch
## (Godot's and the driver's caches empty: 1.8 s, 11 s and 3.9 s of 16.7 s with DRAW's drain, RTX
## 3080, 8 build threads, docs/PERFORMANCE.md "First launch behind the title"), so the bar moves
## at an even pace.
const PHASE_WEIGHTS: Array[float] = [0.11, 0.66, 0.23]
## DRAW's share of the bar is the draws' first tenth, then the drain's by time: elapsed / (elapsed
## + DRAIN_HALF_MS), half of it at DRAIN_HALF_MS, so it keeps moving through a wait whose length
## is not known.
const DRAIN_HALF_MS := 1500.0
## The longest DRAW waits for the drain before it gives up and finishes (a probe that never runs
## must not hold the doors shut).
const DRAIN_CAP_MS := 20000
## Once the first probe has run, the compiles the pool had already started are still running: the
## drain waits this long more and posts a second probe (compiles queued meanwhile go ahead of it).
const DRAIN_SETTLE_MS := 400
## The part of BUILD's share given to collecting the samples (one step per source); the rest
## is building them (one step per sample; the build threads take samples from one queue, so the
## count tracks the time). A fixed split, so the bar never steps back when the sample count
## becomes known. Collecting took 1.4 s of BUILD's 4.6, almost all of it the plants source,
## so the bar waits at the sources' share for that one.
const COLLECT_SHARE := 0.3
const LONG_FRAME_MS := 100.0
## The most build threads (a thread per two logical processors, at least two): at 8, the
## main thread's worst BUILD frame stayed 87 to 110 ms; at 16 it was 211.
const MAX_BUILD_WORKERS := 8

## Each returns some samples (GraphicsWarmup.collect_samples()'s shape). Each is called on a
## thread of its own, at the same time as the others, so they must share no mutable state.
var sample_sources: Array[Callable] = GraphicsWarmup.sample_sources()
## What the status line calls each source's samples (GraphicsWarmup.sample_labels()).
var source_labels: PackedStringArray = GraphicsWarmup.sample_labels()
var marker_path: String = Paths.GRAPHICS_WARMUP_PATH
var shader_paths: Array = GraphicsWarmup.COVERED_SHADERS
var phase: Phase = Phase.COMPILE
## How many threads build samples at once.
var build_workers: int = clampi(OS.get_processor_count() / 2, 2, MAX_BUILD_WORKERS)
## Runs behind the title with the bar hidden until show_progress() (Root, on a first launch).
var background := false
## Whether BUILD's gathering and building run on several threads at once.
var concurrent: bool = DisplayServer.get_name() != "headless"

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
## What the workers are on: the label of the first source still being gathered, then of the
## latest sample taken (also under _mutex), and how long collecting and building took.
var _label := ""
var _collect_ms := 0
var _build_ms := 0
## Written by the coordinating thread only; read on the main thread only after wait_to_finish().
var _results: Array[Dictionary] = []
var _skipped := PackedStringArray()
var _rids: Array[RID] = []
## The names of _results, set on the main thread when DRAW starts (built_names()).
var _built_names := PackedStringArray()
## The samples in source order and the label of each, set before the build threads start (they
## only read them); the mesh each built into (a RID, or null for a skipped sample, under
## _mutex); and the next sample index to take (under _mutex).
var _samples: Array = []
var _labels := PackedStringArray()
var _built_rids: Array = []
var _next_sample := 0
var _warmer: PipelineWarmer = null
## The drain probe (_drained): when the wait began, and the WorkerThreadPool task posted behind
## the compiles (-1 before).
var _drain_start_msec := -1
var _drain_task := -1
## When the first probe was seen done (-1 before), and whether the second one is out.
var _drain_first_msec := -1
var _start_msec := 0
var _phase_start_msec := -1
var _phase_worst_ms := 0.0
var _long_frames := 0
var _last_usec := 0
var _status := ""

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


## The status line under the bar, plain words for what the phase is doing: COMPILE counts
## shaders started (`done` of `total`), BUILD names the group of samples being gathered
## (`total` 0) and then compiled (`done` of `total`), DRAW says so. Pure.
static func status_for(at: Phase, done: int, total: int, label: String) -> String:
	match at:
		Phase.COMPILE:
			return "Starting shaders: %d of %d" % [done, total]
		Phase.BUILD:
			var group := label if label != "" else "graphics"
			if total <= 0:
				return "Gathering %s" % group
			return "Compiling %s: %d of %d" % [group, mini(done + 1, total), total]
		Phase.DRAW:
			return "Drawing a first frame"
	return ""


## The overall progress in DRAW, `drawn` of `total` samples drawn and the drain waited for
## `drain_ms` (see DRAIN_HALF_MS). Pure.
static func draw_progress(drawn: int, total: int, drain_ms: float) -> float:
	var drain := drain_ms / (drain_ms + DRAIN_HALF_MS) if drain_ms > 0.0 else 0.0
	return _progress_at(Phase.DRAW, 0.1 * _ratio(drawn, total) + 0.9 * drain)


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
	BootTrace.mark("warm-up: environment applied")
	if not background:
		show_progress()
	_start_msec = Time.get_ticks_msec()
	_enter_phase(Phase.COMPILE)


## Shows the bar and the status line over whatever is on screen (a background warm-up runs
## without them until something has to wait for it).
func show_progress() -> void:
	if _overlay.visible:
		return
	_overlay.show_loading(TITLE)
	_status = _status_now()
	_overlay.set_progress(progress(), _status)


func _exit_tree() -> void:
	BootTrace.mark("warm-up: screen leaves the tree")
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
	if _drain_task >= 0:
		GraphicsWarmup.wait_later(_drain_task)
		_drain_task = -1
	_free_meshes()
	BootTrace.mark("warm-up: screen left the tree")


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
		Phase.DRAW:
			var drawn := _built_names.size() - (_warmer.pending_count() if _warmer else 0)
			var waited := 0 if _drain_start_msec < 0 else Time.get_ticks_msec() - _drain_start_msec
			return draw_progress(drawn, _built_names.size(), waited)
	return progress_for(phase, 0, 1)


## The names of the samples the worker built, in order. Valid once BUILD is over.
func built_names() -> PackedStringArray:
	assert(phase >= Phase.DRAW, "GraphicsWarmupScreen: built_names() before BUILD is over")
	return _built_names


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
			if _warmer.pending_count() == 0 and _drained():
				_finish()
	var status := _status_now()
	# Only a changed line goes to the label (an empty one leaves it as it is).
	_overlay.set_progress(progress(), status if status != _status else "")
	_status = status


## The status line for now (see status_for).
func _status_now() -> String:
	_mutex.lock()
	var label := _label
	var built := _built
	var total := _total
	_mutex.unlock()
	match phase:
		Phase.COMPILE:
			return status_for(phase, _next_shader, shader_paths.size(), "")
		Phase.BUILD:
			return status_for(phase, built, total, label)
		Phase.DRAW:
			if _drain_start_msec >= 0:
				return DRAINING
	return status_for(phase, 0, 1, "")


func _start_build() -> void:
	_enter_phase(Phase.BUILD)
	# Lazily created statics the worker's material builds read: create them here so the
	# worker never races a main-thread first use.
	WindFoliage.wind_shaders()
	BootTrace.mark("warm-up: wind shaders ready")
	_thread = Thread.new()
	var err := _thread.start(_build)
	assert(err == OK, "GraphicsWarmupScreen: could not start the worker: %s" % error_string(err))
	BootTrace.mark("warm-up: worker started")


## The coordinating thread (the Thread _start_build starts). It runs the texture_blit compile
## and every sample source at once, each on a thread of its own, and when all are back it starts
## build_workers threads that take the samples one by one. The pipelines of different samples
## compile in the driver side by side; one thread doing them in turn took 15 s.
func _build() -> void:
	var began := Time.get_ticks_msec()
	var made: Array = []
	made.resize(sample_sources.size())
	_mutex.lock()
	_label = source_labels[0] if not source_labels.is_empty() else ""
	_mutex.unlock()
	var jobs: Array[Callable] = []
	if not _worker_shaders.is_empty():
		jobs.append(_compile_worker_shaders)
	for k in sample_sources.size():
		jobs.append(_collect.bind(k, made))
	_run_all(jobs)
	if _cancelled():
		return
	var samples: Array = []
	var labels := PackedStringArray()
	for k in made.size():
		var label := source_labels[k] if k < source_labels.size() else ""
		samples.append_array(made[k])
		for i in (made[k] as Array).size():
			labels.append(label)
	_samples = samples
	_labels = labels
	_built_rids.resize(samples.size())
	var gathered := Time.get_ticks_msec()
	_mutex.lock()
	_total = samples.size()
	_collect_ms = gathered - began
	_mutex.unlock()
	var builders: Array[Callable] = []
	for w in build_workers:
		builders.append(_build_samples)
	_run_all(builders)
	_build_ms = Time.get_ticks_msec() - gathered
	for index in samples.size():
		if _built_rids[index] is RID:
			_rids.append(_built_rids[index])
			_results.append(samples[index])
		else:
			_skipped.append(String((samples[index] as Dictionary).name))


## Runs `jobs` at once, a thread each, and returns when all are done. With `concurrent` false
## (headless: the dummy renderer's storage is not safe to allocate in from several threads, which
## the tests hit as "Initializing already initialized RID") one after another on this thread.
func _run_all(jobs: Array[Callable]) -> void:
	if not concurrent:
		for job in jobs:
			job.call()
		return
	var threads: Array[Thread] = []
	for job in jobs:
		var thread := Thread.new()
		var err := thread.start(job)
		assert(err == OK, "GraphicsWarmupScreen: could not start a thread: %s" % error_string(err))
		threads.append(thread)
	for thread in threads:
		thread.wait_to_finish()


func _compile_worker_shaders() -> void:
	for shader in _worker_shaders:
		shader.get_rid()


## Gather thread: the samples of source `k` into made[k], then _collected counts it and the
## status label moves to the first source still out.
func _collect(k: int, made: Array) -> void:
	var result: Array = sample_sources[k].call()
	_mutex.lock()
	made[k] = result
	_collected += 1
	for j in made.size():
		if made[j] == null:
			_label = source_labels[j] if j < source_labels.size() else ""
			break
	_mutex.unlock()


## A build thread: takes the next unbuilt sample until none is left.
func _build_samples() -> void:
	while not _cancelled():
		_mutex.lock()
		var index := _next_sample
		_next_sample += 1
		if index < _samples.size():
			_label = _labels[index]
		_mutex.unlock()
		if index >= _samples.size():
			return
		var sample: Dictionary = _samples[index]
		assert(
			GraphicsWarmup.valid_sample(sample), "GraphicsWarmup: malformed sample %s" % [sample]
		)
		var rid := RID()
		if not (sample.arrays as Array).is_empty():
			rid = RenderingServer.mesh_create_from_surfaces([GraphicsWarmup.surface_data(sample)])
		_mutex.lock()
		_built_rids[index] = rid if rid.is_valid() else null
		_built += 1
		_mutex.unlock()


func _cancelled() -> bool:
	_mutex.lock()
	var cancelled := _cancel
	_mutex.unlock()
	return cancelled


func _start_draw() -> void:
	print("GraphicsWarmup: collecting the samples took %d ms of BUILD" % _collect_ms)
	print("GraphicsWarmup: building took %d ms on %d threads" % [_build_ms, build_workers])
	BootTrace.mark("warm-up: collected in %d ms, built in %d ms" % [_collect_ms, _build_ms])
	_enter_phase(Phase.DRAW)
	for sample_name in _skipped:
		push_warning("GraphicsWarmup: sample %s has no geometry; skipped" % sample_name)
	_warmer = PipelineWarmer.new()
	_viewport.add_child(_warmer)
	for sample in _results:
		_built_names.append(String(sample.name))
		var mesh := GraphicsWarmup.sample_mesh(sample)
		if sample.multimesh:
			# No wind category: build_chunk then keeps shadow casting on for every sample, so
			# the shadow-pass variants trees need are warmed too.
			_warmer.warm(mesh, String(sample.name), "")
		else:
			_warmer.warm_mesh(mesh, String(sample.name))


## Whether the engine's background pipeline compiles have drained. The specialized variants of
## the pipelines DRAW drew compile on the WorkerThreadPool after the draw (94 of them on a true
## first launch), and the first thing on the main thread that waits for one of the pool's tasks
## waits behind all of them: a map opened at the hand-over froze for 3.8 to 4.1 s, and freeing
## the samples' materials there did the same (card firstlaunch2). No monitor counts what is still
## queued (the compile counters move when a compile is asked for), so a probe task is posted
## behind them, a frame after the last draw; the pool runs tasks in the order posted, so the
## probe has run once the pool has taken every compile ahead of it; DRAIN_SETTLE_MS later a second
## probe covers what was still running. Never blocks; gives up after DRAIN_CAP_MS.
func _drained() -> bool:
	var now := Time.get_ticks_msec()
	if _drain_start_msec < 0:
		_drain_start_msec = now
		BootTrace.mark("warm-up: drawn, waiting for the background compiles")
		return false
	var waited := now - _drain_start_msec
	if _drain_task < 0:
		if _drain_first_msec >= 0 and now - _drain_first_msec < DRAIN_SETTLE_MS:
			return false
		_drain_task = WorkerThreadPool.add_task(_drain_probe, false, "GraphicsWarmup drain")
		return false
	if WorkerThreadPool.is_task_completed(_drain_task):
		WorkerThreadPool.wait_for_task_completion(_drain_task)
		_drain_task = -1
		if _drain_first_msec < 0:
			_drain_first_msec = now
			BootTrace.mark("warm-up: the pool took the compiles in %d ms" % waited)
			return false
	elif waited < DRAIN_CAP_MS:
		return false
	else:
		GraphicsWarmup.wait_later(_drain_task)
		push_warning("GraphicsWarmup: the background compiles did not drain in %d ms" % waited)
	print("GraphicsWarmup: background compiles drained in %d ms" % waited)
	BootTrace.mark("warm-up: background compiles drained in %d ms" % waited)
	_drain_task = -1
	return true


static func _drain_probe() -> void:
	pass


func _finish() -> void:
	_enter_phase(Phase.DONE)
	# This frame's _process still sets the bar to 1.0 after we return; nothing after that.
	set_process(false)
	GraphicsWarmup.write_marker(GraphicsWarmup.cache_key(), marker_path)
	BootTrace.mark("warm-up: marker written")
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
	# Freeing a sample's material here waited for the pipelines the engine was still
	# specializing in the background: a 3.8 s frozen frame at the hand-over to the title on a
	# cold cache (perf audit S6). The session keeps them (GraphicsWarmup.keep_materials) and
	# Root releases them on its way out; only the geometry goes now.
	GraphicsWarmup.keep_materials(_samples)
	_samples.clear()
	_results.clear()
	var kept := GraphicsWarmup.kept_material_count()
	BootTrace.mark("warm-up: samples dropped, %d materials kept" % kept)
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
	BootTrace.mark("warm-up: " + str(Phase.keys()[next]))


func _track_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		var ms := (now - _last_usec) / 1000.0
		_phase_worst_ms = maxf(_phase_worst_ms, ms)
		if ms > LONG_FRAME_MS:
			_long_frames += 1
			print("GraphicsWarmup: %.0f ms frame in %s" % [ms, Phase.keys()[phase]])
	_last_usec = now
