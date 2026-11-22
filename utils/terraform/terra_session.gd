class_name TerraSession
extends Node
## The terraforming core attached to a loaded map (docs/systems/terraform.md "The session"): one
## TerraDerive holding the map's terrain document (MapDocument.terra) and every array derived from
## it, kept current as the document is edited, answering height and water queries, and handing the
## save its derived record. Phase 1: it exists only behind the switch (TerraCore.enabled(), the
## project setting tt_sim/terrain/core, default off) and only on a map with a terrain section
## (MapSourceLoader.add_terra_session); nothing reads it yet. Phase 2 moves the tools and the
## consumers onto it.
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
## derive when it lands, followed by the next derive_async(). The derive is never touched while it
## runs: queries, digests and the record wait for is_ready() (the plan's ready(): a Node already
## has a member of that name, its signal).
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
## "add", "replace", "append", "remove", "mute", "unmute", "move", "id", "kind", "data", "flags",
## "to"} as the op needs: add takes kind, data and flags; replace and append id and data; remove,
## mute and unmute id; move id and to (a document position). Returns the primitive's id (add: the
## new one), or -1 when refused (no such primitive, a cap, or data its kind refuses), with nothing
## changed.
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
				_tell(_set_prim.bind(id, kind, data))
		"replace":
			if p.is_empty() or TerraKinds.problem(int(p["kind"]), data) != "":
				return -1
			if not terra.replace(id, data):
				return -1
			if not TerraDoc.is_muted(p):
				_tell(_set_prim.bind(id, int(p["kind"]), data))
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
			_tell(_resync_from.bind(id))
		"move":
			if p.is_empty():
				return -1
			terra.move(id, int(edit.get("to", 0)))
			_tell(_resync_from.bind(-1))
		_:
			return -1
	_record_current = false
	return id


## Refreshes the document's derived record from the settled derive when it is not current (see
## the header); MapDocumentSnapshot.capture() calls it through TerraDoc.before_save. True when
## terra.derived is the record of the derive this session holds.
func capture_for_save() -> bool:
	if not is_ready():
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
	elif _running:
		if _derive.call("is_busy"):
			return
		_derive.call("take_result")
		_running = false
		derives_landed += 1
	if _derive != null and not _queued.is_empty():
		for change in _queued:
			change.call()
		_queued.clear()
		_start()
		return
	set_process(false)
	if _derive != null:
		settled.emit()


## Tells the derive one change now when it is free, else queues it for the landing.
func _tell(change: Callable) -> void:
	if _derive == null or _in_flight():
		_queued.append(change)
		return
	change.call()
	_start()


func _start() -> void:
	_derive.call("derive_async")
	_running = true
	set_process(true)


## set_prim, checked: a kind the native registry refuses is reported (test_terra_kinds keeps the
## two registries equal, so this means a stale library).
func _set_prim(id: int, kind: int, data: PackedFloat32Array) -> void:
	if not _derive.call("set_prim", id, kind, data):
		push_warning("TerraSession: the core refused primitive %d of kind %d" % [id, kind])


## Re-tells the derive the document's order from primitive `id` on (from the start for -1): the
## derive has no move, and set_prim appends a new id at the end, so every primitive from there is
## removed and set again in document order (muted ones left out).
func _resync_from(id: int) -> void:
	var from := 0 if id < 0 else terra.index_of(id)
	if from < 0:
		return
	for i in range(from, terra.prims.size()):
		_derive.call("remove_prim", terra.prims[i]["id"])
	for i in range(from, terra.prims.size()):
		var p := terra.prims[i]
		if not TerraDoc.is_muted(p):
			_set_prim(int(p["id"]), int(p["kind"]), p["data"])


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
