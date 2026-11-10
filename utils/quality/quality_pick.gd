extends Node

## The first-run quality pick behind the title (QualityAuto has the model). Root adds it through
## OnDemand.quality_pick() once the title is quiet: when a first launch's graphics warm-up is
## done with no door waiting, or on a launch without one once the start-up precompile has left.
## It is loaded by path on first use, never at start-up (tests/unit/test_boot_graph.gd).
##
## It does nothing unless QualityAuto.pending() holds for the settings file. Then it waits for the
## shaders compiling behind the title (GraphicsWarmup.behind_running) and START_DELAY_MS more,
## runs one QualityBench, and with its result decides, records the pick in the settings file and
## applies the preset's rows at once (later maps read them). A door into a map opening meanwhile
## aborts it (abort(), from Root._ensure_table): nothing is written, and the next launch tries
## again. Headless runs never pick.

const START_DELAY_MS := 1500

## The settings file it reads and writes (tests point it elsewhere).
var settings_path: String = Paths.SETTINGS_PATH

var _bench: QualityBench = null
var _since := -1
var _done := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or not QualityAuto.pending(_load()):
		_done = true
		queue_free.call_deferred()


## Stops the pick before it writes anything (Root, when a door into a map opens).
func abort() -> void:
	if _done:
		return
	_done = true
	if _bench != null:
		_bench.measured.disconnect(_on_measured)
		_bench.abort()
		_bench = null
	BootTrace.mark("quality: pick stopped by a door")
	queue_free()


func _process(_delta: float) -> void:
	if _done or _bench != null:
		return
	if GraphicsWarmup.behind_running():
		_since = -1
		return
	if _since < 0:
		_since = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _since < START_DELAY_MS:
		return
	BootTrace.mark("quality: measuring behind the title")
	_bench = QualityBench.new()
	_bench.name = "QualityBench"
	_bench.measured.connect(_on_measured, CONNECT_ONE_SHOT)
	add_child(_bench)


func _on_measured(result: Dictionary) -> void:
	_bench = null
	_done = true
	var config := _load()
	# A player who saved graphics rows while it measured has chosen.
	if bool(result.get("aborted", false)) or not QualityAuto.pending(config):
		queue_free()
		return
	var predicted := QualityAuto.predicted_ms(float(result.gpu_ms)) if result.ok else 0.0
	var preset := QualityAuto.decide(predicted, int(result.adapter_type))
	QualityAuto.record(config, preset, result)
	config.save(settings_path)
	QualityPreset.apply_rows(QualityPreset.rows_for(preset), null, config)
	var line := (
		(
			"quality: picked %s (bench %.2f ms at %s, predicted %.1f ms, %d samples at %.1f ms a"
			+ " frame, %d restarts, %d ms, %s)"
		)
		% [
			QualityPreset.LABELS[preset],
			float(result.gpu_ms),
			str(result.size),
			predicted,
			int(result.samples),
			float(result.get("frame_ms", 0.0)),
			int(result.get("restarts", 0)),
			int(result.elapsed_ms),
			String(result.adapter),
		]
	)
	print(line)
	BootTrace.mark(line)
	BootTrace.mark(
		(
			"quality: pacing %s, %d ramp frames, %d load viewports"
			% [
				JSON.stringify(result.get("pacing", {})),
				int(result.get("ramp_frames", 0)),
				int(result.get("load", 0)),
			]
		)
	)
	queue_free()


func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(settings_path)
	return config
