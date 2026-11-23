class_name TerraSession
extends Node
## The terraforming core attached to a loaded map (docs/systems/terraform.md "The session"): one
## TerraDerive holding the map's terrain document (MapDocument.terra) and every array derived from
## it, kept current as the document is edited, answering height and water queries, and handing the
## save its derived record. Phase 1: it exists only behind the switch (TerraCore.enabled(), the
## project setting tt_sim/terrain/core, default off) and only on a map with a terrain section
## (MapSourceLoader.add_terra_session). Phase 2: its TerraBridge (`bridge`) writes the derived
## ground into MapDocument.heights on every landing (take_changed() says where), so today's
## consumers build from it; apply_held() is a gesture's held frame, derived synchronously.
##
## Attach. attach() starts the load-time check (TerraCache.derive_and_check: a full derive of a
## copy of the document and the comparison with its derived record) on a WorkerThreadPool task and
## keeps the derive it returns. A full derive at 320 ft is about 33 ms plus 5 ms of digests, so it
## never runs on the main thread; the map's chunks build meanwhile.
##
## Edits. apply() changes the document at once and tells the derive the same change (set_prim,
## append_dabs, remove_prim; a muted primitive is left out, since the derive has no flags), then
## starts derive_async(), the incremental derive on the derive's own thread. An edit that arrives
## while a derive runs (the attach task or an async derive) is queued, in order, and told to the
## derive when it lands, followed by the next derive_async(). A splice (undo's op: ids, order and
## next_id put back exactly) re-sets the primitives from its insertion on, as unmute and move do;
## the primitives it re-sets are read from the document when the edit is applied, so a queued
## change tells the derive what that edit left, never what later edits did. The derive is never
## touched while it runs: queries, digests and the record wait for is_ready() (the plan's
## ready(): a Node already has a member of that name, its signal).
##
## Stages (card terraform-p2-noblock). cut() ends a stage while a derive is in flight: the edits
## after it are held back until the session has settled on the ones before, so `settled` is
## emitted once per stage, with is_ready() true and the derive answering exactly for the edits up
## to that cut (the document itself is already ahead). TerraEditor cuts before each gesture, undo
## and redo, so a gesture pressed while the one before still derives never waits for it: each
## lands on its own settled derive, in order. stage() is the stage the newest edit was told in,
## settled_stage() the one the derive answers for.
##
## Polling. _process runs only while a derive is in flight (set_process), and it never waits: a
## task or derive is landed only once it has completed (is_task_completed, is_busy).
##
## Closing. A session freed with a derive in flight never waits for it (TerraDerive's destructor
## joins its thread, and a WorkerThreadPool task must be waited for once): the task or the busy
## derive is parked in a process-wide list and let go once it has completed, polled once a frame
## while any is left (_reap(), PainterZoneMaps' pattern).
##
## Saving. attach() sets the document's before_save callable to capture_for_save(), which
## MapDocumentSnapshot.capture() calls on the main thread: when the session is ready and its record
## is not current, it refreshes TerraDoc.derived from the settled derive (TerraCache.make_record),
## so the save writes the record of what this machine derived. While a derive runs the record is
## left as it is, and the writer drops it if its key no longer matches.

## Emitted when a derive lands and no edit waits (is_ready() turned true).
signal settled

const NODE_NAME := "TerraSession"

## Attach tasks and busy derives of sessions freed before they completed (see the header):
## [{"task": task id}, or {"derive": TerraDerive}], process wide, since the session is gone.
static var _parked: Array[Dictionary] = []

## The map document attached (null before attach()), and its terrain document.
var doc: MapDocument = null
var terra: TerraDoc = null
## The load-time check (TerraCache.check's keys: status, reason, arrays), {} until it lands.
var check: Dictionary = {}
## Derives landed since attach, the attach's full derive included (tests and probes).
var derives_landed := 0
## The TerraBridge writing this session's ground into the document (MapSourceLoader sets it), or
## null.
var bridge: RefCounted = null

var _derive: RefCounted = null
## The attach task's id while it runs, else -1, and its job (the task writes "result").
var _task := -1
var _job: Dictionary = {}
## True from derive_async() until its result is taken.
var _running := false
## Changes to tell the derive when it is free, in edit order.
var _queued: Array[Callable] = []
## True while terra.derived is the record of the settled derive.
var _record_current := false
## The union of the H2 rects the landed derives changed since take_changed() (derive samples).
var _changed := Rect2i()
## The same union for the paint planes (take_paint_changed()).
var _paint_changed := Rect2i()
## True while apply_held() runs: a free derive is told and derived synchronously.
var _held := false
## Stages cut() held back, oldest first: [{"id", "changes": Array[Callable]}].
var _stages: Array[Dictionary] = []
## The stage the derive is in (settled_stage()), the newest stage id made, and the stage the
## newest edit was told in (stage()).
var _stage := 0
var _stage_made := 0
var _last_stage := 0
## True while `settled` is being emitted, and while pause() holds the next stage.
var _settling := false
var _paused := false


func _ready() -> void:
	set_process(_in_flight())


func _process(_delta: float) -> void:
	_poll()


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if terra != null and terra.before_save.get_object() == self:
		terra.before_save = Callable()
	if _task >= 0:
		_park({"task": _task})
	elif _running:
		_park({"derive": _derive})
	_task = -1
	_running = false


## Attaches the session to `map_doc`, whose terrain document is not null, and starts the
## load-time derive and check on a worker. False, and nothing started, without a terrain document
## or the native library.
func attach(map_doc: MapDocument) -> bool:
	if map_doc == null or map_doc.terra == null or not TerraCore.native_available():
		return false
	doc = map_doc
	terra = map_doc.terra as TerraDoc
	# A copy: an edit made on the main thread meanwhile never reaches the worker (it is queued).
	_job = {"terra": terra.duplicate(), "doc": doc, "result": {}}
	var run := TerraSession._run_attach.bind(_job)
	_task = WorkerThreadPool.add_task(run, false, "TerraSession.attach")
	terra.before_save = capture_for_save
	set_process(true)
	return true


## True when a derive has landed, none runs and no edit waits: queries, digests() and the record
## answer for the document as it is now.
func is_ready() -> bool:
	return _derive != null and _task < 0 and not _running and _queued.is_empty()


## The derived ground height at world (x, z) (bilinear on H2), or NAN while not is_ready().
func height_at(x: float, z: float) -> float:
	return float(_derive.call("height_at", x, z)) if is_ready() else NAN


## The derived water level at world (x, z) (bilinear on WL), or NAN while not is_ready().
func water_at(x: float, z: float) -> float:
	return float(_derive.call("water_at", x, z)) if is_ready() else NAN


## Every digest of the settled derive (TerraCache.digests_of: name -> int), or {} while not
## is_ready() (TerraDerive.digests() must not run during derive_async).
func digests() -> Dictionary:
	return TerraCache.digests_of(_derive) if is_ready() else {}


## Applies one edit to the document and the derive (see the header). `edit` is {"op": one of
## "add", "replace", "append", "remove", "mute", "unmute", "move", "splice", "id", "kind", "data",
## "flags", "to", "remove", "insert", "at", "next_id"} as the op needs: add takes kind, data and
## flags; replace and append id and data; remove, mute and unmute id; move id and to (a document
## position); splice remove (ids), insert ([{id, kind, flags, data}]), at (a position after the
## removal) and optionally next_id (TerraDoc.splice: ids, order and next_id restored exactly, for
## undo, folding and the wall sync); surfaces names (a PackedStringArray: the whole surface table,
## TerraDoc.surfaces, nothing derived). Returns the primitive's id (add: the new one; splice and
## surfaces: 0), or
## -1 when refused (no such primitive, a cap, or data its kind refuses), with nothing changed.
func apply(edit: Dictionary) -> int:
	if terra == null:
		return -1
	var id := int(edit.get("id", -1))
	var data: PackedFloat32Array = edit.get("data", PackedFloat32Array())
	var p := terra.find(id)
	match String(edit.get("op", "")):
		"add":
			var kind := int(edit.get("kind", -1))
			if TerraKinds.problem(kind, data) != "":
				return -1
			id = terra.add(kind, data, int(edit.get("flags", 0)) & TerraDoc.KNOWN_FLAGS)
			if id < 0:
				return -1
			if not TerraDoc.is_muted(terra.find(id)):
				# A copy: the document holds `data` itself, and a later append grows it in place
				# (a tell held by a stage or a derive in flight would send those floats twice).
				_tell(_set_prim.bind(id, kind, data.duplicate()))
		"replace":
			if p.is_empty() or TerraKinds.problem(int(p["kind"]), data) != "":
				return -1
			if not terra.replace(id, data):
				return -1
			if not TerraDoc.is_muted(p):
				_tell(_set_prim.bind(id, int(p["kind"]), data.duplicate()))
		"append":
			var whole: PackedFloat32Array = p.get("data", PackedFloat32Array()) + data
			if p.is_empty() or TerraKinds.problem(int(p["kind"]), whole) != "":
				return -1
			if not terra.append(id, data):
				return -1
			if not TerraDoc.is_muted(p):
				_tell(func() -> void: _derive.call("append_dabs", id, data))
		"remove", "mute":
			if p.is_empty():
				return -1
			if edit["op"] == "remove":
				terra.remove(id)
			else:
				terra.set_muted(id, true)
			_tell(func() -> void: _derive.call("remove_prim", id))
		"unmute":
			if p.is_empty():
				return -1
			terra.set_muted(id, false)
			_tell(_reset.bind(_rows_from(terra.index_of(id))))
		"move":
			if p.is_empty():
				return -1
			terra.move(id, int(edit.get("to", 0)))
			_tell(_reset.bind(_rows_from(0)))
		"splice":
			var removed: Array = edit.get("remove", [])
			var inserted: Array = edit.get("insert", [])
			for q: Variant in inserted:
				if not q is Dictionary or not q.get("data") is PackedFloat32Array:
					return -1
				if TerraKinds.problem(int(q.get("kind", -1)), q["data"]) != "":
					return -1
			var at := int(edit.get("at", terra.prims.size()))
			if not terra.splice(removed, inserted, at, int(edit.get("next_id", -1))):
				return -1
			# The derive has no insert: every primitive from the first inserted one's position on
			# is re-set in document order (set_prim appends a new id at the end).
			var from := terra.prims.size()
			for q: Dictionary in inserted:
				var index := terra.index_of(int(q["id"]))
				if index >= 0:
					from = mini(from, index)
			_tell(_splice_derive.bind(removed.duplicate(), _rows_from(from)))
			id = 0
		"surfaces":
			# The surface table (card terraform-p2-paint-path): names only, so nothing is derived.
			var names: Variant = edit.get("names")
			if not names is PackedStringArray or TerraDoc.surfaces_problem(names) != "":
				return -1
			terra.surfaces = (names as PackedStringArray).duplicate()
			id = 0
		_:
			return -1
	_record_current = false
	return id


## apply() of a splice edit (see apply()): `remove` ids go, `insert` ([{id, kind, flags, data}])
## goes in at position `at`, and next_id becomes `next_id` when 1 or more. True when applied.
func splice(remove: Array, insert: Array, at: int, next_id := -1) -> bool:
	var edit := {"op": "splice", "remove": remove, "insert": insert, "at": at, "next_id": next_id}
	return apply(edit) >= 0


## apply() for a held frame of a gesture (the bridge's held path): when no derive is in flight the
## derive is told and runs derive() synchronously on the calling thread (0.4 to 2 ms for a held
## brush at 320 ft, design.md 6), so is_ready() holds on return and the bridge can write at once;
## else the edit queues exactly as apply() does and lands with the next async derive. Returns as
## apply().
func apply_held(edit: Dictionary) -> int:
	_held = true
	var id := apply(edit)
	_held = false
	return id


## The union of the H2 sample rects (derive samples) every derive landed since the last call
## changed, then forgets it: the whole grid after the attach, empty when nothing changed. The
## bridge halves it to document samples and diffs only there.
func take_changed() -> Rect2i:
	var out := _changed
	_changed = Rect2i()
	return out


## As take_changed(), for the paint planes (PI, PW; card terraform-p2-paint-path).
func take_paint_changed() -> Rect2i:
	var out := _paint_changed
	_paint_changed = Rect2i()
	return out


## Ends a stage (see the header): while a derive is in flight or a stage is held back, the edits
## from now on are told to the derive only after the session has settled on the ones before.
## Nothing while is_ready(): the next edit derives at once anyway.
func cut() -> void:
	if _derive == null or (not _in_flight() and _stages.is_empty()):
		return
	if not _stages.is_empty() and (_stages.back().changes as Array).is_empty():
		return
	_stage_made += 1
	_stages.append({"id": _stage_made, "changes": [] as Array[Callable]})


## The stage the newest edit was told in (see the header): its landing is due once
## settled_stage() has reached it.
func stage() -> int:
	return _last_stage


## The stage the derive answers for while is_ready() (inside `settled`, an earlier one than
## stage() when a cut holds edits back).
func settled_stage() -> int:
	return _stage


## The TerraDerive when is_ready(), else null: read only, on the main thread (the bridge's
## strided reads), never kept past the frame.
func settled_derive() -> RefCounted:
	return _derive if is_ready() else null


## True while the attach's load-time derive runs (the loader waits for it).
func attaching() -> bool:
	return _task >= 0


## Lands whatever has completed (see _poll()), for a session that is not in the tree yet (the
## loader waits for the attach before the terrain builds; _process runs only in the tree).
func poll() -> void:
	_poll()


## Refreshes the document's derived record from the settled derive when it is not current (see
## the header); MapDocumentSnapshot.capture() calls it through TerraDoc.before_save. True when
## terra.derived is the record of the derive this session holds.
func capture_for_save() -> bool:
	# Inside a stage's `settled` the derive is behind the document: not its record.
	if not is_ready() or not _stages.is_empty():
		return false
	if not _record_current:
		terra.derived = TerraCache.make_record(terra, doc, _derive)
		_record_current = true
	return true


## How many attach tasks and derives of freed sessions wait to be let go (tests).
static func parked_count() -> int:
	return _parked.size()


## The attach task's body: the load-time check on the job's copy (TerraCache.derive_and_check).
## Static, so the task never calls into a session that was freed meanwhile.
static func _run_attach(job: Dictionary) -> void:
	job["result"] = TerraCache.derive_and_check(job["terra"], job["doc"])


func _in_flight() -> bool:
	return _task >= 0 or _running


## Lands whatever has completed, tells the derive the queued edits and starts the next derive;
## stops polling when nothing is in flight. Never waits on unfinished work.
func _poll() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var result: Dictionary = _job["result"]
		_job = {}
		_derive = result.get("derive")
		result.erase("derive")
		check = result
		derives_landed += 1
		# A record that matched is the record of this derive, unless an edit came meanwhile.
		_record_current = check.get("status") == TerraCache.MATCH and _queued.is_empty()
		if _derive == null:
			_queued.clear()
			_stages.clear()
		else:
			var grid: Dictionary = _derive.call("grid")
			_changed = Rect2i(0, 0, int(grid["w"]), int(grid["h"]))
			_paint_changed = _changed
	elif _running:
		if _derive.call("is_busy"):
			return
		_note(_derive.call("take_result"))
		_running = false
		derives_landed += 1
	if _derive != null and not _queued.is_empty():
		for change in _queued:
			change.call()
		_queued.clear()
		_start()
		return
	set_process(false)
	if _derive == null:
		return
	_settling = true
	settled.emit()
	_settling = false
	_next_stage()


## Holds the next stage back after this settle (TerraEditor, while a landing of this stage waits
## for a worker of its own): the derive keeps answering for this stage until resume().
func pause() -> void:
	_paused = true


## Lets the stages held by pause() go on (at once, unless inside `settled`).
func resume() -> void:
	if not _paused:
		return
	_paused = false
	if not _settling:
		_next_stage()


## Tells the next stage held back by a cut, now that the one before has settled (a listener may
## have started a derive meanwhile; its own landing comes back to _poll()).
func _next_stage() -> void:
	while not _paused and not _stages.is_empty() and not _in_flight():
		var next: Dictionary = _stages.pop_front()
		_stage = int(next.id)
		var changes: Array[Callable] = next.changes
		if changes.is_empty():
			continue
		for change in changes:
			change.call()
		_start()


## Tells the derive one change now when it is free, else queues it for the landing (or, after a
## cut(), holds it in the newest stage).
func _tell(change: Callable) -> void:
	if _paused and _stages.is_empty():
		# The settled stage is held (pause()): this edit starts the next one.
		_stage_made += 1
		_stages.append({"id": _stage_made, "changes": [] as Array[Callable]})
	if not _stages.is_empty():
		var held: Dictionary = _stages.back()
		(held.changes as Array[Callable]).append(change)
		_last_stage = int(held.id)
		return
	_last_stage = _stage
	if _derive == null or _in_flight():
		_queued.append(change)
		return
	change.call()
	if _held:
		_note(_derive.call("derive"))
		derives_landed += 1
		return
	_start()


## Adds a landed derive's changed H2 rect to take_changed()'s union.
func _note(result: Dictionary) -> void:
	var r: Rect2i = result.get("h2_rect", Rect2i())
	if r.has_area():
		_changed = r if not _changed.has_area() else _changed.merge(r)
	var p: Rect2i = result.get("paint_rect", Rect2i())
	if p.has_area():
		_paint_changed = p if not _paint_changed.has_area() else _paint_changed.merge(p)


func _start() -> void:
	_derive.call("derive_async")
	_running = true
	set_process(true)


## set_prim, checked: a kind the native registry refuses is reported (test_terra_kinds keeps the
## two registries equal, so this means a stale library).
func _set_prim(id: int, kind: int, data: PackedFloat32Array) -> void:
	if not _derive.call("set_prim", id, kind, data):
		push_warning("TerraSession: the core refused primitive %d of kind %d" % [id, kind])


## Tells the derive a splice: the removed ids go, then `rows` (_rows_from() of the first inserted
## one's position, read when the splice was applied) are re-set.
func _splice_derive(removed: Array, rows: Array) -> void:
	for id: Variant in removed:
		_derive.call("remove_prim", int(id))
	_reset(rows)


## The document's primitives from position `from` on as they stand now (a negative `from`: none):
## [ids, rows of [id, kind, data] for the unmuted ones], for _reset(). Read when an edit is
## applied, so a queued tell re-sets what that edit left (the floats copied: a later append grows
## the document's array in place).
func _rows_from(from: int) -> Array:
	var ids: Array[int] = []
	var rows: Array[Array] = []
	if from >= 0:
		for i in range(from, terra.prims.size()):
			var p := terra.prims[i]
			ids.append(int(p["id"]))
			if not TerraDoc.is_muted(p):
				var data: PackedFloat32Array = p["data"]
				rows.append([int(p["id"]), int(p["kind"]), data.duplicate()])
	return [ids, rows]


## Re-tells the derive the document's order from a position on (`rows`, _rows_from()): the derive
## has no move, and set_prim appends a new id at the end, so every primitive from there is removed
## and set again in document order (muted ones left out).
func _reset(rows: Array) -> void:
	for id: int in rows[0]:
		_derive.call("remove_prim", id)
	for row: Array in rows[1]:
		_set_prim(int(row[0]), int(row[1]), row[2])


## Hands a worker task whose owner is going away to the reaper (TerraBridge's water conversion):
## it is waited on once it completes, never before.
static func park_task(task: int) -> void:
	_park({"task": task})


static func _park(entry: Dictionary) -> void:
	_parked.append(entry)
	_reap()
	if _parked.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_reap):
		tree.process_frame.connect(_reap)


## Lets go of each parked task or derive that has completed (waiting on a completed task returns
## at once; a derive whose thread finished is joined by take_result at once), keeps the rest, and
## stops polling when none is left.
static func _reap() -> void:
	var left: Array[Dictionary] = []
	for entry in _parked:
		if entry.has("task"):
			if WorkerThreadPool.is_task_completed(entry["task"]):
				WorkerThreadPool.wait_for_task_completion(entry["task"])
				continue
		elif not entry["derive"].call("is_busy"):
			entry["derive"].call("take_result")
			continue
		left.append(entry)
	_parked = left
	if not left.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_reap):
		tree.process_frame.disconnect(_reap)
