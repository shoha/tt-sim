extends RefCounted

## Render-job probe (`call` op) for the authoring tools' sounds (StrokeSound, card
## brushland-sound): what AudioManager plays while a job paints, places and undoes in the real
## game, and whether the SFX bus carries it. Three actions:
##
## - "listen": adds a monitor node under the root (once) that records every sound AudioManager
##   plays (its sound_played signal: the name, the take the queue picked and the time), every
##   sound the game asked for (sound_requested, heard or not: a cooldown or a louder sound on
##   the same bus in that frame drops a request) and the SFX bus's peak, left and right, every
##   frame. One peak reading holds only the last mixed block, so a short tick needs the
##   per-frame reads.
## - "mark": one line for the window since the last mark (or the listen), then the window
##   restarts: `step.label`, the brush's radius and tick spacing, the sounds played in order
##   with their take and time into the window, the requests by name and count, the loudest SFX
##   peak L/R and how many frames read above SILENT_DB, and the loudest peak over the window's
##   last `step.tail_s` seconds (default 0.5), which reads -200 once the bus is quiet again.
## - "stop": frees the monitor.

const MONITOR_NAME := "AuthoringSoundMonitor"
## Godot reports a silent bus as -200 dB; anything above this is sound.
const SILENT_DB := -199.0


static func run(base: Node, step: Dictionary) -> String:
	var root := base.get_tree().root
	var monitor := root.get_node_or_null(MONITOR_NAME) as Monitor
	match String(step.get("action", "mark")):
		"listen":
			if monitor == null:
				monitor = Monitor.new()
				monitor.name = MONITOR_NAME
				root.add_child(monitor)
			monitor.restart()
			return "listening on the SFX bus"
		"stop":
			if monitor != null:
				monitor.queue_free()
			return "stopped"
	if monitor == null:
		return "mark: no monitor (run the listen action first)"
	var line := "%s: %s%s" % [
		String(step.get("label", "window")), _brush(base), monitor.report(float(step.get("tail_s", 0.5)))
	]
	monitor.restart()
	return line


## The brush's radius and StrokeSound's tick spacing for it, when authoring.
static func _brush(base: Node) -> String:
	var ctrl := base.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.brush == null:
		return ""
	var radius := ctrl.brush.get_radius()
	return "brush %.2f m, spacing %.2f m; " % [radius, StrokeSound.spacing_m(radius)]


## Records sounds and SFX bus peaks between marks (see the header).
class Monitor:
	extends Node

	## {t, name, take, takes} per sound played, in order.
	var played: Array = []
	## name -> how many times the game asked for it.
	var requested: Dictionary = {}
	## [t, left_db, right_db] per frame.
	var peaks: Array = []
	var _started_ms: int = 0
	var _bus: int = -1

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_bus = AudioServer.get_bus_index(AudioManager.BUS_SFX)
		AudioManager.sound_played.connect(_on_played)
		AudioManager.sound_requested.connect(_on_requested)

	func _exit_tree() -> void:
		if AudioManager.sound_played.is_connected(_on_played):
			AudioManager.sound_played.disconnect(_on_played)
		if AudioManager.sound_requested.is_connected(_on_requested):
			AudioManager.sound_requested.disconnect(_on_requested)

	## Starts a new window.
	func restart() -> void:
		played = []
		requested = {}
		peaks = []
		_started_ms = Time.get_ticks_msec()

	func _process(_delta: float) -> void:
		peaks.append(
			[
				_now_s(),
				AudioServer.get_bus_peak_volume_left_db(_bus, 0),
				AudioServer.get_bus_peak_volume_right_db(_bus, 0)
			]
		)

	## The window as one line: sounds played, requests, the bus's loudest peak and its tail.
	func report(tail_s: float) -> String:
		var sounds := PackedStringArray()
		for event in played:
			sounds.append(
				(
					"%s take %d/%d +%.2f s"
					% [event["name"], event["take"], event["takes"], event["t"]]
				)
			)
		var asked := PackedStringArray()
		for sound in requested:
			asked.append("%s x%d" % [sound, requested[sound]])
		var loudest := Vector2(-200.0, -200.0)
		var tail := Vector2(-200.0, -200.0)
		var loud_frames := 0
		var end_s := _now_s()
		for sample in peaks:
			var lr := Vector2(sample[1], sample[2])
			loudest = loudest.max(lr)
			if maxf(lr.x, lr.y) > SILENT_DB:
				loud_frames += 1
			if sample[0] >= end_s - tail_s:
				tail = tail.max(lr)
		var bus := (
			"SFX peak max L/R %.1f/%.1f dB, %d of %d frames above -200"
			% [loudest.x, loudest.y, loud_frames, peaks.size()]
		)
		return (
			"played %d [%s]; requested [%s]; %s; last %.1f s max %.1f/%.1f dB"
			% [played.size(), ", ".join(sounds), ", ".join(asked), bus, tail_s, tail.x, tail.y]
		)

	func _on_played(sound: StringName) -> void:
		# The queue names the take it picked before AudioManager emits (SoundRequestQueue.flush).
		var queue: SoundRequestQueue = AudioManager.get("_queue")
		var last_take: Dictionary = queue.get("_last_take")
		var takes: Array = AudioManager.sound_entry(sound).get("takes", [])
		played.append(
			{
				"t": _now_s(),
				"name": String(sound),
				"take": int(last_take.get(sound, 0)),
				"takes": maxi(takes.size(), 1)
			}
		)

	func _on_requested(sound: StringName) -> void:
		requested[String(sound)] = int(requested.get(String(sound), 0)) + 1

	func _now_s() -> float:
		return (Time.get_ticks_msec() - _started_ms) / 1000.0
