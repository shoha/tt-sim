class_name PainterTreeTables
extends RefCounted
## The painted trees' row map and occluder table (PainterTrees; docs/systems/painter.md "Trees"):
## each tree's line of the row map (its nine roles' style rows and its eight nearest crowns) and its
## column of the occluder table, as the textures the tree materials read.
##
## Built on a worker (card painter-plant-landing, from terraform-s2-cpu round 8). A whole build
## (PainterTreeRows.tables) is GDScript over every drawn tree, 19 to 48 ms a call at 300 trees, and
## the trees asked for one on every landing frame and every install frame. Now update() patches each
## tree installed since the last pass started (note()) with its own role rows (variant 0) and
## occluder and no neighbour crowns (the shader stops at the first -1), uploads that at once, and
## asks for a whole pass on the WorkerThreadPool over a shallow copy of the trees (one pass at a
## time, the latest wins). A pass that lands re-patches the trees installed while it ran, and a
## change meanwhile starts one more, so the tables once settled equal a whole build. A new tree
## draws toned from its first frame and gains its neighbours' shading a few frames later. A change
## of the table's size (more rows than lines) builds whole on the main thread, as does finish().
##
## The main thread never waits for a pass that has not run (the PainterZoneMaps rule, b54cbfbe):
## a pass lands only once is_task_completed says so; finish() builds the same tables here instead,
## and release() lets the pass go. An abandoned task is waited for, as Godot needs once per task,
## only after it has completed (_reap, polled on process_frame until none is left).

## Tasks let go of before they completed, waited for once each has (_reap()); process wide, since
## a tables object may be gone by then.
static var _abandoned := PackedInt64Array()

## The row map (map_w floats a line, FORMAT_RF) and the occluder table (lines x 2, RGBAF).
var row_map: ImageTexture = null
var occ_tex: ImageTexture = null
## The lines of the tables as last built (0: none yet).
var lines := 0

var _map_w := 17
var _near_m := 18.0
var _rows := PackedFloat32Array()
var _occ := PackedFloat32Array()
## The drawn trees (PainterTrees.trees, shared: only read here).
var _trees: Dictionary = {}
## The worker pass in flight (-1: none), its result, whether another is wanted, whether a frame
## callback is queued, and the trees installed since the pass in flight started.
var _task := -1
var _out := {}
var _again := false
var _queued := false
var _since: Dictionary = {}
## Called with (row_map, occ_tex) when the textures are new (the materials bind them).
var _bind := Callable()


func _init(trees: Dictionary, map_w: int, near_m: float, bind: Callable) -> void:
	_trees = trees
	_map_w = map_w
	_near_m = near_m
	_bind = bind


## Notes a tree installed now (update() patches its line).
func note(key: Vector3i) -> void:
	_since[key] = true


## The tables follow the trees over `want_lines` lines: the trees installed since the last pass
## patched in and uploaded now, a whole pass asked for (see the header); a new size builds whole.
func update(want_lines: int) -> void:
	if want_lines != lines:
		_build_now(want_lines)
		return
	if not _since.is_empty():
		_patch_since()
		_upload()
	_again = true
	_pump()


## Whether a pass runs or is wanted (the trees have not settled).
func is_busy() -> bool:
	return _task >= 0 or _again


## Whether a worker pass is in flight now (tests).
func has_task() -> bool:
	return _task >= 0


## The tables whole now (tests and render jobs): a completed pass lands, an unfinished one is let
## go and the same tables are built here.
func finish() -> void:
	if not is_busy():
		return
	_build_now(lines)


## Forgets the trees: a pass in flight is let go (never waited for), the textures dropped.
func release() -> void:
	if _task >= 0:
		_abandon(_task)
	_task = -1
	_out = {}
	_again = false
	_since.clear()
	lines = 0
	row_map = null
	occ_tex = null


## How many abandoned tasks wait to be reaped (tests).
static func abandoned_count() -> int:
	return _abandoned.size()


## A whole build of the tables on this thread over `want_lines` lines.
func _build_now(want_lines: int) -> void:
	if _task >= 0:
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
		else:
			_abandon(_task)
		_task = -1
		_out = {}
	_again = false
	_since.clear()
	var built := PainterTreeRows.tables(_trees, want_lines, _map_w, _near_m)
	_rows = built.rows
	_occ = built.occ
	lines = want_lines
	_upload()


## Each tree installed since the pass started: its own role rows and occluder, no neighbours.
func _patch_since() -> void:
	for key: Vector3i in _since:
		var t: Dictionary = _trees.get(key, {})
		if t.is_empty():
			continue
		var row: int = t["row"]
		var line := PainterTreeTones.role_rows(t["species"], 0)
		for r in _map_w:
			_rows[row * _map_w + r] = float(line[r]) if r < line.size() else -1.0
		PainterTreeRows._occluder(_occ, lines, row, t["pos"], (t["d"] as Dictionary)["forms"])


## Lands a completed pass, then starts the next when one is wanted; follows itself each frame
## while a pass runs.
func _pump() -> void:
	if lines == 0:
		return
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			_queue()
			return
		_land()
	if _again and _task < 0:
		_again = false
		var out := {}
		_out = out
		_since.clear()
		_task = WorkerThreadPool.add_task(
			_run.bind(_trees.duplicate(), lines, _map_w, _near_m, out), false, "PainterTreeTables"
		)
		_queue()


## A worker's whole pass over `snap` (a shallow copy of the trees: their dictionaries are replaced,
## never edited, by the main thread) into `out`.
static func _run(snap: Dictionary, n: int, map_w: int, near_m: float, out: Dictionary) -> void:
	out.merge(PainterTreeRows.tables(snap, n, map_w, near_m))
	out["lines"] = n


## Lands the completed pass (the wait returns at once: _pump checked) and re-patches the trees
## installed while it ran.
func _land() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if int(_out.get("lines", -1)) == lines:
		_rows = _out["rows"]
		_occ = _out["occ"]
		_patch_since()
		_upload()
	_out = {}


func _queue() -> void:
	if _queued:
		return
	_queued = true
	(Engine.get_main_loop() as SceneTree).process_frame.connect(_on_frame, CONNECT_ONE_SHOT)


func _on_frame() -> void:
	_queued = false
	_pump()


func _upload() -> void:
	var map_image := Image.create_from_data(
		_map_w, lines, false, Image.FORMAT_RF, _rows.to_byte_array()
	)
	var occ_image := Image.create_from_data(
		lines, 2, false, Image.FORMAT_RGBAF, _occ.to_byte_array()
	)
	# Updated in place while the size holds (a new texture per landing cost a texture creation).
	if row_map != null and row_map.get_height() == lines:
		row_map.update(map_image)
		occ_tex.update(occ_image)
		return
	row_map = ImageTexture.create_from_image(map_image)
	occ_tex = ImageTexture.create_from_image(occ_image)
	if _bind.is_valid():
		_bind.call(row_map, occ_tex)


static func _abandon(task: int) -> void:
	_abandoned.append(task)
	_reap()
	if _abandoned.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_reap):
		tree.process_frame.connect(_reap)


## Waits for each abandoned task that has completed (at once: it has), keeps the rest, and stops
## polling when none is left.
static func _reap() -> void:
	var left := PackedInt64Array()
	for task in _abandoned:
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			left.append(task)
	_abandoned = left
	if not left.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_reap):
		tree.process_frame.disconnect(_reap)
