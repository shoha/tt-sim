class_name TerraEditor
extends RefCounted

## AuthoringEditor's edits of the terrain document (`AuthoringEditor.terra`; card
## terraform-p2-editor, docs/systems/terraform.md "The editor"): with the terraforming core on, on a
## map with a terrain section, every gesture that shapes the ground is a list of edits of the map's
## TerraSession, and one gesture is one AuthoringHistory entry. Part of the editor like
## HeightEditor, split out to keep one class a readable size.
##
## Gestures. begin_gesture(), then edit() per change (applied at once; its inverse is built from
## the document as it stood, inverse_of()), then end_gesture(); a caller that applied its own edits
## calls record_gesture(label, edits, inverse, ground). The entry is {"label", "undo":
## undo_gesture.bind(g), "redo": redo_gesture.bind(g), "bytes"}, where the gesture g is {"label",
## "edits", "inverse", "ground" (HeightEditor's ground record, heights left out), "doc_digest"
## (TerraDoc.digest after), "digest_before", "digests_after", "digests_before" (CHECKED of the
## settled derive, filled when each side lands)}. Consecutive appends to one primitive are folded
## into the edit before them (compact()), and an append or replace of a primitive the gesture
## already added or restored records no inverse, so a held stroke of thousands of dabs keeps one
## edit each way.
##
## Landing. Do, undo, redo and a peer's live op share one landing: the edits go through
## TerraSession.apply (async), and when the session settles, after the bridge has written the
## heights (TerraBridge connects first), the document rect that changed is found against the
## heights before the apply (TerraDerive.doc_heights_diff) and HeightEditor.apply_ground lands the
## gesture's ground record over it. An apply that arrives while a landing is pending waits for it
## and runs on that landing: a redo pressed before its undo lands queues, it never interleaves.
##
## Routes. AuthoringEditor asks refusal() before every ground tool's press and routes here while
## active(). Each tool's op below refuses with NOT_YET until its card puts the tool on primitives
## (Sculpt: begin_sculpt; Paint: paint_refusal, begin_paint; Water: river, begin_pond,
## begin_water_erase; Wall: begin_wall), so those cards edit this file's ops, not AuthoringEditor.
##
## Peers. LiveEditCodec's "terra" op carries one side's edits, its ground side, the document digest
## and the settled digests of that side; a peer applies it through apply_edits(), the method the
## host's redo calls, and compares its own once landed (last_check; a mismatch warns once, naming
## the arrays). "terra_check" carries the digests alone (apply_check()).

## Emitted after each landing (do and redo: `redo` true; undo false), once its ground is applied.
signal landed(redo: bool)

## The toast of a ground tool on a map whose ground is primitives while the core is off.
const SWITCH_OFF := (
	"This map's ground is made of terrain primitives: turn on the terrain core"
	+ " (project setting tt_sim/terrain/core) to edit it"
)
## The toast while the core is on but its native library is not built.
const NO_CORE := (
	"The terrain core's native library is not built: this map's ground cannot be edited"
)
## A tool whose card has not put it on primitives yet (the tool's name goes in).
const NOT_YET := "%s is not on terrain primitives yet"
## The settled digests a gesture side carries and a peer compares (TerraCache.DIGESTS subset).
const CHECKED: Array[String] = ["H2", "WL", "CT", "falls", "walls", "water"]
## Longest finish_work() waits for a derive (microseconds) before it gives up and warns.
const FINISH_TIMEOUT_USEC := 10000000

## Why the last refused route refused, or "".
var last_refusal := ""
## The last peer check: {"ok": bool, "arrays": names that differ ("document" for the digest)}.
var last_check: Dictionary = {}
## Landings so far (tests).
var landings := 0

var _owner: WeakRef = null
## The open gesture (begin_gesture), or {}: {"edits", "inverse", "restored": id -> true, "before":
## heights, "digest_before", "digests_before"}.
var _open: Dictionary = {}
## The landing waiting for the session to settle, or {}: {"before", "ground", "redo", "spread",
## "check", "gesture", "land"}.
var _landing: Dictionary = {}
## Applies that arrived while a landing was pending, in order: [edits, ground, redo, spread, check,
## gesture].
var _waiting: Array[Array] = []
var _warned := false


static func create(editor: AuthoringEditor) -> TerraEditor:
	var terra := TerraEditor.new()
	terra._owner = weakref(editor)
	var s := terra.session()
	if s != null:
		s.settled.connect(terra._on_settled)
		if s.bridge != null:
			s.bridge.call("set_editor", editor)
	return terra


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor if _owner != null else null


## The map's TerraSession (the child MapSourceLoader.add_terra_session made), or null.
func session() -> TerraSession:
	var e := _editor()
	if e == null or not is_instance_valid(e.map_root):
		return null
	return e.map_root.get_node_or_null(TerraSession.NODE_NAME) as TerraSession


## True when the ground is the core's: the switch is on, the document has a terrain section and
## the map has a session. The ground tools route here then.
func active() -> bool:
	var e := _editor()
	return e != null and e.document.terra != null and TerraCore.enabled() and session() != null


## Why a ground tool (Sculpt, River, Pond, Paint, Wall) cannot take a press on this map whatever
## its route, or "": the map's ground is primitives but the core is off (SWITCH_OFF) or not built
## (NO_CORE). A map without a terrain section always edits today's way.
func refusal() -> String:
	var e := _editor()
	if e == null or e.document.terra == null:
		return ""
	if not TerraCore.enabled():
		return SWITCH_OFF
	return "" if session() != null else NO_CORE


## Sets last_refusal to refusal(): true when a ground tool's press may go on.
func allows() -> bool:
	last_refusal = refusal()
	return last_refusal == ""


# ============================================================================
# Water and wall hooks (the brushes call these; today's editors when not active)
# ============================================================================


## The Water tool's river release (WaterBrush.carve): the line as a river primitive while active,
## else WaterEditor.carve_river. The new body's id, or -1 (last_refusal says why when the core
## refused; else WaterEditor.last_refusal).
func carve_river(
	line: PackedVector2Array,
	widths: PackedFloat32Array,
	depth: int,
	speed: float = WaterBody.DEFAULT_SPEED
) -> int:
	if not allows():
		return -1
	if active():
		return river(line, widths, depth, speed)
	return _editor().water.carve_river(line, widths, depth as WaterBody.Depth, speed)


## The Water tool's pond press (WaterBrush.begin), routed as carve_river(). True when a pond stroke
## began.
func paint_pond_begin(depth: int, hit: Vector3) -> bool:
	if not allows():
		return false
	if active():
		return begin_pond(depth, hit)
	return _editor().water.paint_pond_begin(depth as WaterBody.Depth, hit)


## The Water tool's erase press (WaterBrush.begin), routed as carve_river(). True when an erase
## stroke began.
func erase_water_begin() -> bool:
	if not allows():
		return false
	if active():
		return begin_water_erase()
	return _editor().water.erase_water_begin()


## The Wall tool's press (WallBrush.press): true when the press may go on to today's WallEditor
## edit; false, with last_refusal saying why, when refused.
func begin_wall_edit() -> bool:
	if not allows():
		return false
	return begin_wall() if active() else true


# ============================================================================
# Tool routes (each tool's card fills its op)
# ============================================================================


## True while a dab stroke of a primitive tool is in progress (AuthoringEditor's routes).
func is_stroking() -> bool:
	return false


## One frame's exposure of the stroke in progress (world points and radius).
func dab(_from: Vector3, _to: Vector3, _radius: float, _seconds: float) -> void:
	pass


## Pushes this frame's held edits to the ground (TerraBridge.held).
func flush() -> void:
	pass


## Ends the stroke in progress and records its gesture. True when it changed anything.
func end_stroke() -> bool:
	return false


## Abandons the stroke in progress.
func cancel_stroke() -> void:
	pass


## Sculpt (card terraform-p2-sculpt): a stroke of HeightBrush operation `op` toward world height
## `target_y`. False with last_refusal set when refused.
func begin_sculpt(_op: int, _target_y: float) -> bool:
	return _not_yet("Sculpt")


## Paint (card terraform-p2-paint-path): why `surface` cannot be painted now, or "".
func paint_refusal(_surface: String) -> String:
	return NOT_YET % "Paint"


## Paint (card terraform-p2-paint-path): a coat of `surface`, or with `erase` an erase coat.
func begin_paint(_surface: String, _erase: bool) -> bool:
	return _not_yet("Paint")


## River (card terraform-p2-water): the drawn line (document XZ, as WaterEditor.carve_river takes
## it) carved as one river primitive. Its id, or -1.
func river(
	_line: PackedVector2Array, _widths: PackedFloat32Array, _depth: int, _speed: float
) -> int:
	_not_yet("River")
	return -1


## Pond (card terraform-p2-water): a pond stroke of depth class `depth` pressed at `hit`.
func begin_pond(_depth: int, _hit: Vector3) -> bool:
	return _not_yet("Pond")


## Water erase (card terraform-p2-water).
func begin_water_erase() -> bool:
	return _not_yet("Water erase")


## Wall (card terraform-p2-walls): a Wall press may go on (its WallEditor edit and the wall sync's
## splice then make one group).
func begin_wall() -> bool:
	return _not_yet("Wall")


func _not_yet(tool: String) -> bool:
	last_refusal = NOT_YET % tool
	return false


# ============================================================================
# Gestures and history
# ============================================================================


## Opens a gesture: edit() collects its edits until end_gesture().
func begin_gesture() -> void:
	var e := _editor()
	var s := session()
	_open = {
		"edits": [],
		"inverse": [],
		"restored": {},
		"before": e.document.heights.duplicate(),
		"digest_before": (e.document.terra as TerraDoc).digest_for(e.document),
		"digests_before": checked_digests(s) if s != null and s.is_ready() else {},
	}


## True between begin_gesture() and end_gesture().
func is_open() -> bool:
	return not _open.is_empty()


## Applies one session edit now (TerraSession.apply, or with `held` TerraBridge.held: derived at
## once when the session is free) and, inside a gesture, records it and its inverse. Returns the
## primitive's id (splice: 0), or -1 when refused.
func edit(change: Dictionary, held := false) -> int:
	var s := session()
	if s == null:
		return -1
	var terra := s.terra
	var inverse: Array[Dictionary] = []
	if is_open():
		var id := int(change.get("id", -1))
		var op := String(change.get("op", ""))
		if not ((op == "append" or op == "replace") and _open.restored.has(id)):
			inverse = inverse_of(terra, change)
		if op == "add":
			_open.restored[terra.next_id] = true
		elif op == "append" or op == "replace":
			_open.restored[id] = true
	var out: int = s.bridge.call("held", change) if held and s.bridge != null else s.apply(change)
	if out < 0 or not is_open():
		return out
	var done := _copy(change)
	if done.get("op") == "add":
		# The id the add took (the redo's add takes it again: undo puts next_id back), so the
		# appends that follow fold into it (compact()).
		done["id"] = out
	(_open.edits as Array).append(done)
	_open.inverse = inverse + (_open.inverse as Array)
	return out


## Closes the gesture and records it (record_gesture()); with `land` its do side lands as an undo
## or redo does (a tool whose own machinery landed the ground passes false). Returns the gesture,
## or {} when it changed nothing.
func end_gesture(label: String, ground := {}, land := true) -> Dictionary:
	var open := _open
	_open = {}
	if open.is_empty() or (open.edits as Array).is_empty():
		return {}
	var g := record_gesture(label, compact(open.edits), open.inverse, ground)
	g.digest_before = open.digest_before
	g.digests_before = open.digests_before
	_arm(
		{
			"before": open.before,
			"ground": ground,
			"redo": true,
			"spread": false,
			"check": {},
			"gesture": g,
			"land": land,
		}
	)
	return g


## Records an applied gesture as one history entry (see the header): `edits` the session edits in
## order, `inverse` the edits that take them back (inverse_of(), last edit's first), `ground` the
## ground record. Returns the gesture.
func record_gesture(label: String, edits: Array, inverse: Array, ground: Dictionary) -> Dictionary:
	var e := _editor()
	var g := {
		"label": label,
		"edits": edits,
		"inverse": inverse,
		"ground": ground,
		"doc_digest": (e.document.terra as TerraDoc).digest_for(e.document),
		"digest_before": "",
		"digests_after": {},
		"digests_before": {},
	}
	var floats := 0
	for list: Array in [edits, inverse]:
		for change: Dictionary in list:
			floats += (change.get("data", PackedFloat32Array()) as PackedFloat32Array).size()
	var history_entry := {
		"label": label,
		"undo": undo_gesture.bind(g),
		"redo": redo_gesture.bind(g),
		"bytes": floats * 4 + int(ground.get("props_bytes", 0)),
	}
	e.history.record(history_entry)
	e.edited.emit()
	return g


## Undo of gesture `g` (the history entry's undo): its inverse through apply_edits().
func undo_gesture(g: Dictionary) -> void:
	apply_edits(g.inverse, g.ground, false, false, {}, g)


## Redo of gesture `g` (the history entry's redo): its edits through apply_edits().
func redo_gesture(g: Dictionary) -> void:
	apply_edits(g.edits, g.ground, true, false, {}, g)


## Applies one side of a gesture (`edits`, and the ground record `ground` for side `redo`) and
## lands it (see the header): the host's undo and redo, and a peer's live op (`spread`: the ground
## work drains over frames; `check`: {"doc_digest", "digests"} compared once landed). Queued
## behind a pending landing. False when refused (not active, or an edit the session refused; the
## edits before it stay applied and land).
func apply_edits(
	edits: Array,
	ground: Dictionary,
	redo: bool,
	spread := false,
	check := {},
	gesture := {},
) -> bool:
	if not active():
		push_warning("TerraEditor: a terrain edit arrived while the core is not active")
		return false
	if has_work():
		_waiting.append([edits, ground, redo, spread, check, gesture])
		return true
	return _apply_now(edits, ground, redo, spread, check, gesture)


## A "terra_check" op: `check` ({"doc_digest", "digests"}) compared once everything before it has
## landed.
func apply_check(check: Dictionary) -> void:
	apply_edits([], {}, true, true, check)


## True while a landing is pending or an apply waits for one (AuthoringEditor.has_height_work).
func has_work() -> bool:
	return not _landing.is_empty() or not _waiting.is_empty()


## One frame: lands a pending landing whose session is ready (the session's own settled normally
## does it first).
func step() -> void:
	var s := session()
	if not _landing.is_empty() and s != null and s.is_ready():
		_land()


## Lands everything pending now, waiting for the session's derives (they run on their own thread;
## at most FINISH_TIMEOUT_USEC): op_of() and a peer's catch-up need the side whole.
func finish_work() -> void:
	var s := session()
	if s == null:
		_landing = {}
		_waiting.clear()
		return
	var deadline := Time.get_ticks_usec() + FINISH_TIMEOUT_USEC
	while has_work():
		s.poll()
		if not _landing.is_empty() and s.is_ready():
			_land()
		if not has_work():
			return
		if Time.get_ticks_usec() > deadline:
			push_warning("TerraEditor: a derive did not land in time; its landing is dropped")
			_landing = {}
			_waiting.clear()
			return
		OS.delay_usec(200)


## The CHECKED digests of `s`'s settled derive ({} while it is not ready).
static func checked_digests(s: TerraSession) -> Dictionary:
	var all := s.digests()
	var out := {}
	for key in CHECKED:
		if all.has(key):
			out[key] = all[key]
	return out


# ============================================================================
# The inverse builder
# ============================================================================


## The edits that take `change` back, built from `terra` as it stands before `change` is applied
## (docs/systems/terraform.md "The editor"): add gives a splice removing the new id and putting
## next_id back; append and replace a replace with the floats before; remove a splice inserting the
## primitive back at its position with its id; mute and unmute the other one; move a move back; a
## splice the splice removing what it inserted and putting next_id back, then one splice per removed
## primitive, at its old position, in ascending order. [] for an edit that would be refused.
static func inverse_of(terra: TerraDoc, change: Dictionary) -> Array[Dictionary]:
	var id := int(change.get("id", -1))
	var p := terra.find(id)
	var out: Array[Dictionary] = []
	match String(change.get("op", "")):
		"add":
			out.append(_splice([terra.next_id], [], 0, terra.next_id))
		"append", "replace":
			if not p.is_empty():
				out.append({"op": "replace", "id": id, "data": (p.data as PackedFloat32Array).duplicate()})
		"remove":
			if not p.is_empty():
				out.append(_splice([], [_copy(p)], terra.index_of(id), -1))
		"mute", "unmute":
			if not p.is_empty():
				out.append({"op": "mute" if TerraDoc.is_muted(p) else "unmute", "id": id})
		"move":
			if not p.is_empty():
				out.append({"op": "move", "id": id, "to": terra.index_of(id)})
		"splice":
			var inserted: Array = []
			for q: Dictionary in change.get("insert", []):
				inserted.append(int(q.get("id", -1)))
			out.append(_splice(inserted, [], 0, terra.next_id))
			var back: Array = []
			for removed: Variant in change.get("remove", []):
				var at := terra.index_of(int(removed))
				if at >= 0:
					back.append(at)
			back.sort()
			for at: int in back:
				out.append(_splice([], [_copy(terra.prims[at])], at, -1))
	return out


## `edits` with each append folded into the edit before it when that edit adds, replaces or
## appends the same primitive (the document and the derive end the same: update equals build).
static func compact(edits: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for change: Dictionary in edits:
		var last: Dictionary = out.back() if not out.is_empty() else {}
		var same := not last.is_empty() and int(last.get("id", -2)) == int(change.get("id", -1))
		var grows := String(last.get("op", "")) in ["add", "replace", "append"]
		if change.get("op") == "append" and same and grows:
			last.data = (last.data as PackedFloat32Array) + (change.data as PackedFloat32Array)
			continue
		out.append(_copy(change))
	return out


static func _splice(remove: Array, insert: Array, at: int, next_id: int) -> Dictionary:
	return {"op": "splice", "remove": remove, "insert": insert, "at": at, "next_id": next_id}


## A deep copy of an edit or primitive (its float array copied, so later appends never reach it).
static func _copy(value: Dictionary) -> Dictionary:
	return value.duplicate(true)


# ============================================================================
# Landing
# ============================================================================


func _apply_now(
	edits: Array, ground: Dictionary, redo: bool, spread: bool, check: Dictionary, g: Dictionary
) -> bool:
	var e := _editor()
	var s := session()
	var before := e.document.heights.duplicate()
	var ok := true
	for change: Dictionary in edits:
		if s.apply(change) < 0:
			push_warning("TerraEditor: the session refused a %s edit" % change.get("op", "?"))
			ok = false
			break
	var landing := {
		"before": before,
		"ground": ground,
		"redo": redo,
		"spread": spread,
		"check": check,
		"gesture": g,
		"land": true,
	}
	_arm(landing)
	return ok


## Waits for the session to settle with `landing`, or lands it now when it already has.
func _arm(landing: Dictionary) -> void:
	_landing = landing
	var s := session()
	if s != null and s.is_ready():
		_land()


func _on_settled() -> void:
	if not _landing.is_empty():
		_land()


## Lands the pending landing (see the header), then starts the next waiting apply.
func _land() -> void:
	var l := _landing
	_landing = {}
	var e := _editor()
	var s := session()
	var derive := s.settled_derive() if s != null else null
	if e != null and derive != null:
		var doc := e.document
		var rect := Rect2i()
		var before: PackedFloat32Array = l.before
		if before.size() == doc.heights.size():
			var whole := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
			var diff: Dictionary = derive.call("doc_heights_diff", before, doc.samples_x(), whole)
			rect = diff.get("rect", Rect2i())
		if l.land and (rect.has_area() or not (l.ground as Dictionary).is_empty()):
			e.heights.apply_ground(rect, before, l.ground, l.redo, l.spread)
		var g: Dictionary = l.gesture
		if not g.is_empty():
			var side := "digests_after" if l.redo else "digests_before"
			g[side] = checked_digests(s)
			g["doc_digest" if l.redo else "digest_before"] = (doc.terra as TerraDoc).digest_for(doc)
		if not (l.check as Dictionary).is_empty():
			_compare(l.check, s)
	landings += 1
	landed.emit(bool(l.redo))
	if not _waiting.is_empty():
		var next: Array = _waiting.pop_front()
		_apply_now(next[0], next[1], next[2], next[3], next[4], next[5])


## A peer's check of its landed side against the host's (see the header).
func _compare(check: Dictionary, s: TerraSession) -> void:
	var e := _editor()
	var arrays: Array[String] = []
	var want := String(check.get("doc_digest", ""))
	if want != "" and (e.document.terra as TerraDoc).digest_for(e.document) != want:
		arrays.append("document")
	var mine := checked_digests(s)
	var theirs: Dictionary = check.get("digests", {})
	for key in theirs:
		if mine.get(key) != theirs[key]:
			arrays.append(String(key))
	last_check = {"ok": arrays.is_empty(), "arrays": arrays}
	if not arrays.is_empty() and not _warned:
		_warned = true
		push_warning(
			"TerraEditor: this machine's terrain differs from the host's in " + ", ".join(arrays)
		)
