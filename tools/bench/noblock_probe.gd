extends RefCounted
## The press bench (cards noblock2 to noblock4; docs/systems/terraform.md "Never blocking"): how
## long a press made right after a river release or a held raise holds the frame, the core off and
## on. Driven by `tools/bench/noblock_bench.json` through the render-job runner (a real window,
## vsync off; README.md beside this file). One `call` step per action:
##
##   switch {core}       TerraCore.switch_override for the next new map (before `new_map`).
##   ground              on the open map: a standing river, a pond, a ROW street and a standing
##                       fire, so a crossing, a settlement and a put-out have something to act
##                       on; points the level at the bench's test folder for the save press.
##   trial {after, press}  in one frame: the release (`river`: a river carved on the tool's path,
##                       `raise`: the end of a 20-frame held Raise), then the press (`none`,
##                       structure, crossing, settlement, fire, putout, save, table, undo, redo).
##                       Then frames until the map is idle; one row to ROWS. The map is put back
##                       (the trial's entries undone) before the next trial, outside the window.
##   report              the rows of every run so far, grouped by core, release and press.
##   cleanup             deletes the bench's test level (the rows stay, one line per trial of
##                       every run, until deleted by hand).
##
## A row: call_ms (the press call), delay_ms and delay_frames (press to its result: a queued press
## running, a save or settle finishing; the call itself otherwise), worst_ms, over33_n and
## over33_ms (whole frames, post-draw to post-draw, from the press frame until idle), idle_frames.

const SELF := "res://tools/bench/noblock_probe.gd"
const ROWS := "user://noblock_bench.jsonl"
const LEVEL := "_noblock4_bench"
const BENCH := "NoblockBench"
const SLOW_MS := 33.0
const MAX_FRAMES := 900
const HELD_FRAMES := 20

## The landform's own river and pond stand; `ground` picks the press's river line among radial
## lines down from the summit (the first one the carve takes) and the crossing over the landform's
## longest river, and keeps them on the tree root's META.
const META := &"noblock_bench"
## Fractions of the document's extent (document-local x, z).
const STREET := [Vector2(0.20, 0.20), Vector2(0.40, 0.20)]
## Where a cottage may stand: `ground` keeps the first the structure writer takes.
const LOTS := [
	Vector2(0.56, 0.18), Vector2(0.30, 0.30), Vector2(0.60, 0.30), Vector2(0.35, 0.65),
	Vector2(0.70, 0.70), Vector2(0.50, 0.50)
]
const FIRE := Vector2(0.30, 0.45)
const STANDING_FIRE := Vector2(0.36, 0.52)
const RAISE := [Vector2(0.62, 0.68), Vector2(0.68, 0.72)]


static func run(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) == "switch":
		# An `expand` value arrives as a string.
		TerraCore.switch_override = str(step.get("core", false)) == "true"
		return "core %s" % TerraCore.enabled()
	if String(step.get("action", "")) == "report":
		return report()
	if String(step.get("action", "")) == "cleanup":
		return cleanup()
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	match String(step.get("action", "")):
		"ground":
			return _ground(ctrl)
		"trial":
			var bench := Bench.new()
			bench.name = BENCH
			bench.ctrl = ctrl
			bench.step = step
			bench.probe = load(SELF)
			base.get_tree().root.add_child(bench)
			return "trial %s after %s" % [step.get("press", ""), step.get("after", "")]
	return "unknown action"


## Holds a step while a trial still runs or the map is busy.
static func blocker(base: Node, _step: Dictionary) -> String:
	if base.get_tree().root.get_node_or_null(BENCH) != null:
		return "a trial runs"
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl != null and ctrl.editor != null and busy(ctrl):
		return "the map is busy"
	return ""


## True while any of the map's work runs (the editor's height work, waiting presses, the water,
## structure builds, the core's derive, a scatter regeneration). Plants growing in are not work.
static func busy(ctrl: AuthoringController) -> bool:
	var e := ctrl.editor
	var root := e.map_root
	var water := root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	var structures := AuthoredStructures.of_map(root)
	var session := root.get_node_or_null(TerraSession.NODE_NAME) as TerraSession
	return (
		e.has_height_work()
		or e.water.is_working()
		or (structures != null and structures.pending_count() > 0)
		or (water != null and water.is_refreshing())
		or (session != null and not session.is_ready())
		or (is_instance_valid(e.scatter) and e.scatter.is_regenerating())
	)


static func world(e: AuthoringEditor, f: Vector2) -> Vector3:
	var ext := e.document.extent_m()
	return e.to_world(Vector3(f.x * ext.x, 0.0, f.y * ext.y))


static func line(e: AuthoringEditor, fs: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for f: Vector2 in fs:
		var w := world(e, f)
		out.append(Vector2(w.x, w.z))
	return out


static func fire(e: AuthoringEditor, f: Vector2, put_out: bool) -> bool:
	var p := world(e, f)
	if not e.begin_fire_stroke(0.0 if put_out else 0.8, put_out):
		return false
	e.stroke_dab(p, p, 3.0, 0.5)
	e.flush()
	return e.end_stroke()


## The river line a trial releases: the first radial line down from the middle that carves
## (carved, landed and undone here), as fractions of the extent; [] when none does.
static func _press_river(ctrl: AuthoringController) -> Array:
	var e := ctrl.editor
	for k in 8:
		var dir := Vector2.from_angle(TAU * k / 8.0)
		var fs := [Vector2.ONE * 0.5 + dir * 0.14, Vector2.ONE * 0.5 + dir * 0.44]
		var entries := ctrl.history.undo_count()
		var id := e.terra.carve_river(line(e, fs), PackedFloat32Array([1.2]), WaterBody.Depth.WAIST)
		e.finish_height_work()
		if id < 0:
			continue
		while ctrl.history.undo_count() > entries:
			ctrl.history.undo()
			e.finish_height_work()
		return fs
	return []


## A plank line across the landform's longest river at its middle (world points), or [].
static func _crossing(e: AuthoringEditor) -> Array:
	var best: WaterBody = null
	for body in e.document.water_bodies:
		if body.is_river() and body.points.size() >= 2:
			if best == null or body.points.size() > best.points.size():
				best = body
	if best == null:
		return []
	var k := best.points.size() / 2
	var a := best.points[k - 1] if k > 0 else best.points[0]
	var b := best.points[k]
	var mid := (a + b) * 0.5
	var half := best.half_widths[mini(k, best.half_widths.size() - 1)]
	var side := (b - a).normalized().orthogonal() * (half + 2.5)
	return [
		e.to_world(Vector3(mid.x - side.x, 0.0, mid.y - side.y)),
		e.to_world(Vector3(mid.x + side.x, 0.0, mid.y + side.y)),
	]


## A 4 m cottage lot centred on fraction `f` of the extent, or null (refused).
static func lot_at(e: AuthoringEditor, f: Vector2) -> Structure:
	var ext := e.document.extent_m()
	var c := Vector2(f.x * ext.x, f.y * ext.y)
	var plan := PackedVector2Array(
		[c + Vector2(-2, -2), c + Vector2(2, -2), c + Vector2(2, 2), c + Vector2(-2, 2)]
	)
	return e.structures.lot("core:cottage", plan, 100)


static func _ground(ctrl: AuthoringController) -> String:
	var e := ctrl.editor
	var river := _press_river(ctrl)
	var crossing := _crossing(e)
	var lot: Variant = null
	for f: Vector2 in LOTS:
		if lot_at(e, f) != null:
			lot = f
			break
	ctrl.get_tree().root.set_meta(META, {"river": river, "crossing": crossing, "lot": lot})
	var street := e.walls.place(
		Wall.Kind.ROW, world(e, STREET[0]), world(e, STREET[1]), -1.0, {"seed": 5, "side": 2}
	)
	e.finish_height_work()
	var burnt := fire(e, STANDING_FIRE, false)
	e.finish_height_work()
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(LEVEL))
	ctrl.level.level_folder = LEVEL
	return (
		"ground: core %s river %s crossing %s lot %s street %d fire %s bodies %d history %d"
		% [
			e.terra.active(),
			river,
			crossing,
			lot,
			street,
			burnt,
			e.document.water_bodies.size(),
			ctrl.history.undo_count()
		]
	)


## Every row so far, grouped by core / release / press: min-max over the runs.
static func report() -> String:
	var file := FileAccess.open(ROWS, FileAccess.READ)
	if file == null:
		return "no rows"
	var groups := {}
	var order: Array[String] = []
	while not file.eof_reached():
		var text := file.get_line().strip_edges()
		if text == "":
			continue
		var row: Dictionary = JSON.parse_string(text)
		var key := "%s %s %s" % ["on " if row.core else "off", row.after, row.press]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(row)
	var lines := PackedStringArray(
		["core after press | n | call ms | delay ms (frames) | worst ms | over33 n | over33 ms"]
	)
	for key in order:
		var rows: Array = groups[key]
		lines.append(
			(
				"%s | %d | %s | %s (%s) | %s | %s | %s"
				% [
					key,
					rows.size(),
					_span(rows, "call_ms"),
					_span(rows, "delay_ms"),
					_span(rows, "delay_frames"),
					_span(rows, "worst_ms"),
					_span(rows, "over33_n"),
					_span(rows, "over33_ms")
				]
			)
		)
	return "\n".join(lines)


static func _span(rows: Array, field: String) -> String:
	var lo := INF
	var hi := -INF
	for row: Dictionary in rows:
		lo = minf(lo, float(row[field]))
		hi = maxf(hi, float(row[field]))
	if is_equal_approx(lo, hi):
		return "%.1f" % lo
	return "%.1f-%.1f" % [lo, hi]


## Deletes the bench level's files and folder (flat: level.json, map.ttmap, a thumbnail).
static func cleanup() -> String:
	var path := LevelManager.folder_path(LEVEL)
	var dir := DirAccess.open(path)
	var removed := 0
	if dir != null:
		for file in dir.get_files():
			if dir.remove(file) == OK:
				removed += 1
		DirAccess.remove_absolute(path.trim_suffix("/"))
	var gone := not DirAccess.dir_exists_absolute(path)
	return "removed %d files of %s, folder gone %s" % [removed, LEVEL, gone]


## One trial over frames (see the header).
class Bench:
	extends Node
	var ctrl: AuthoringController = null
	var step: Dictionary = {}
	## This script (an inner class cannot call its outer script's statics by name).
	var probe: GDScript = null
	var phase := 0
	var held := 0
	var base_entries := 0
	var queued_before := 0
	var press_us := 0
	var call_ms := 0.0
	var delay_ms := -1.0
	var delay_frames := -1
	var done := [false]
	## Whole frames (this node's first-in-frame process to the next), from the press frame on.
	var frames := PackedFloat64Array()
	var last_us := 0
	var waiting := false
	var meta: Dictionary = {}
	## Why the press made nothing, or "".
	var note := ""

	func _ready() -> void:
		process_priority = -1000
		base_entries = ctrl.history.undo_count()
		meta = get_tree().root.get_meta(META, {})

	func _process(_delta: float) -> void:
		var e := ctrl.editor
		if e == null:
			queue_free()
			return
		var now_us := Time.get_ticks_usec()
		if phase == 2:
			frames.append((now_us - last_us) / 1000.0)
		last_us = now_us
		match phase:
			0:
				if String(step.get("after", "river")) == "raise":
					if held == 0 and not e.begin_height_stroke(HeightBrush.RAISE, 0.0):
						_finish("raise refused")
						return
					var t := float(held) / HELD_FRAMES
					var a: Vector3 = probe.world(e, RAISE[0].lerp(RAISE[1], t))
					var b: Vector3 = probe.world(e, RAISE[0].lerp(RAISE[1], t + 1.0 / HELD_FRAMES))
					e.stroke_dab(a, b, 4.0, 1.0 / 60.0)
					e.flush()
					held += 1
					if held < HELD_FRAMES:
						return
					e.end_stroke()
				else:
					var fs: Array = meta.get("river", [])
					if fs.is_empty():
						_finish("no river line")
						return
					var river := e.terra.carve_river(
						probe.line(e, fs), PackedFloat32Array([1.2]), WaterBody.Depth.WAIST
					)
					if river < 0:
						_finish("river refused: %s %s" % [e.terra.last_refusal, e.water.last_refusal])
						return
				_press(e)
				phase = 2
			2:
				var now := Time.get_ticks_usec()
				if (
					delay_ms < 0.0
					and (done[0] or (waiting and not e.presses.is_waiting()))
				):
					delay_ms = (now - press_us) / 1000.0
					delay_frames = frames.size()
				if frames.size() >= MAX_FRAMES or (
					delay_ms >= 0.0 and frames.size() > 1 and not probe.busy(ctrl)
				):
					_row()
					phase = 3
			3:
				# Put the map back, outside the measured window.
				e.finish_height_work()
				if probe.busy(ctrl):
					return
				while ctrl.history.undo_count() > base_entries:
					ctrl.history.undo()
					e.finish_height_work()
				phase = 4
			4:
				e.finish_height_work()
				if not probe.busy(ctrl):
					queue_free()

	func _press(e: AuthoringEditor) -> void:
		var press := String(step.get("press", "none"))
		# The structure tool's preview (made while hovering, before the press).
		var lot: Structure = null
		if press == "structure":
			lot = probe.lot_at(e, meta.get("lot", LOTS[0]))
			if lot == null:
				note = "lot refused: %s" % e.structures.last_refusal
		queued_before = e.presses.queued_count
		press_us = Time.get_ticks_usec()
		match press:
			"structure":
				if lot != null:
					e.structures.add(lot)
			"crossing":
				var ends: Array = meta.get("crossing", [])
				if ends.size() == 2:
					e.crossings.place(Crossing.Kind.PLANK, ends[0], ends[1])
			"settlement":
				var street := -1
				for wall in e.document.walls:
					if wall.is_row():
						street = wall.id
				e.settlements.dress(street, "farming_hamlet")
			"fire":
				probe.fire(e, FIRE, false)
			"putout":
				probe.fire(e, STANDING_FIRE, true)
			"save":
				_async(func() -> void: await ctrl.save_async())
			"table":
				var tree := get_tree()
				_async(
					func() -> void:
						await e.presses.settle_async(tree)
						TableMover.document_of(e)
				)
			"undo":
				ctrl.undo()
			"redo":
				ctrl.undo()
				ctrl.redo()
		call_ms = (Time.get_ticks_usec() - press_us) / 1000.0
		waiting = e.presses.queued_count > queued_before
		if press not in ["save", "table"] and not waiting:
			delay_ms = call_ms
			delay_frames = 0

	func _async(body: Callable) -> void:
		var flag := done
		var wrapped := func() -> void:
			await body.call()
			flag[0] = true
		wrapped.call()

	func _row() -> void:
		var worst := 0.0
		var over_n := 0
		var over_ms := 0.0
		for ms in frames:
			worst = maxf(worst, ms)
			if ms > SLOW_MS:
				over_n += 1
				over_ms += ms
		var row := {
			"arm": String(step.get("arm", "")),
			"core": ctrl.editor.terra.active(),
			"after": String(step.get("after", "river")),
			"press": String(step.get("press", "none")),
			"call_ms": snappedf(call_ms, 0.01),
			"delay_ms": snappedf(delay_ms, 0.1),
			"delay_frames": delay_frames,
			"queued": waiting,
			"worst_ms": snappedf(worst, 0.1),
			"over33_n": over_n,
			"over33_ms": snappedf(over_ms, 0.1),
			"idle_frames": frames.size(),
			"note": note,
		}
		var fire_parts: Variant = ctrl.editor.fire.get("last_parts")
		if row.press in ["fire", "putout"] and fire_parts is Dictionary:
			row["fire_us"] = fire_parts
		var file := FileAccess.open(
			ROWS, FileAccess.READ_WRITE if FileAccess.file_exists(ROWS) else FileAccess.WRITE
		)
		if file != null:
			file.seek_end()
			file.store_line(JSON.stringify(row))
		_emit("row " + JSON.stringify(row))

	func _finish(why: String) -> void:
		_emit("trial %s: %s" % [step.get("press", ""), why])
		queue_free()

	func _emit(s: String) -> void:
		for node in get_tree().root.get_children():
			if node.has_method("log_line"):
				node.call("log_line", s)
				return
		print("RJ| " + s)
