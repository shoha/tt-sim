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
## Never blocking (card terraform-p2-noblock). Nothing a press, an undo or a redo calls waits for a
## derive: prepare_gesture() finishes nothing while active(), a gesture opened while landings are
## pending first applies the queued undos and redos to the document (it is built on the document
## as it stands), and each landing's edits go behind a TerraSession.cut(), so the landings queue
## (_landings) and each lands on its own settled stage, in order, its heights before being the
## ones the landing before it left. Only finish_work() waits (op_of, a save, a peer's catch-up),
## and counts it (waits).
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
## Times finish_work() had to wait for a derive (tests: a press, undo or redo never does).
var waits := 0
## The Sculpt tool's strokes (card terraform-p2-sculpt): the sculpt ops below forward to it.
var sculpt: TerraSculpt = null
## The Water tool's ops (card terraform-p2-water): river, pond and erase gestures.
var water_tools := TerraWaterTools.new()

var _owner: WeakRef = null
## The open gesture (begin_gesture), or {}: {"edits", "inverse", "restored": id -> true, "before":
## heights, "digest_before", "digests_before"}.
var _open: Dictionary = {}
## The landings waiting for their stage to settle, oldest first: {"before" (heights, or null: the
## ones the landing before it leaves), "ground", "redo", "spread", "check", "gesture", "land",
## "stage" (TerraSession.stage() of its newest edit)}.
var _landings: Array[Dictionary] = []
## Applies that arrived while a landing was pending, in order: [edits, ground, redo, spread, check,
## gesture].
var _waiting: Array[Array] = []
var _warned := false
## TerraBridge.water_landings when the last landing ran: a landing that moved it gives its gesture
## the bridge's water record (the gesture's water side, `g.water`; _land()).
var _water_seen := 0


static func create(editor: AuthoringEditor) -> TerraEditor:
	var terra := TerraEditor.new()
	terra._owner = weakref(editor)
	terra.sculpt = TerraSculpt.create(editor, terra)
	terra.water_tools = TerraWaterTools.new(terra)
	var s := terra.session()
	if s != null:
		s.settled.connect(terra._on_settled)
		if s.bridge != null:
			s.bridge.call("set_editor", editor)
			terra._water_seen = int(s.bridge.get("water_landings"))
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


## Before a ground tool's edit begins (WallEditor's edits, the Paint press; the sculpt, river and
## pond presses once their cards land): today's editors edit the ground as it has landed, so the
## height work is finished first (AuthoringEditor.finish_height_work); while active() nothing
## waits, since the derives and landings in flight stay queued and this gesture's edits derive and
## land after them, in order (see the header).
func prepare_gesture() -> void:
	var e := _editor()
	if e != null and not active():
		e.finish_height_work()


# ============================================================================
# Tool routes (each tool's card fills its op)
# ============================================================================


## True while a dab stroke of a primitive tool is in progress (AuthoringEditor's routes).
func is_stroking() -> bool:
	return sculpt.is_stroking() or water_tools.is_stroking()


## One frame's exposure of the stroke in progress (world points and radius).
func dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if water_tools.is_stroking():
		water_tools.dab(from, to, radius)
	else:
		sculpt.dab(from, to, radius, seconds)


## Pushes this frame's held edits to the ground (TerraBridge.held).
func flush() -> void:
	sculpt.flush()


## Ends the stroke in progress and records its gesture. True when it changed anything.
func end_stroke() -> bool:
	if water_tools.is_stroking():
		return water_tools.end_stroke()
	return sculpt.end_stroke()


## Abandons the stroke in progress.
func cancel_stroke() -> void:
	water_tools.cancel_stroke()
	sculpt.cancel_stroke()


## Sculpt (card terraform-p2-sculpt, TerraSculpt): a stroke of Sculpt op `op` (HeightBrush's, or
## TerraSculpt.TERRACE / SOFTEN) toward world height `target_y`. False with last_refusal set when
## refused.
func begin_sculpt(op: int, target_y: float) -> bool:
	last_refusal = ""
	return sculpt.begin(op, target_y)


## Paint (card terraform-p2-paint-path): why `surface` cannot be painted now, or "".
func paint_refusal(_surface: String) -> String:
	return NOT_YET % "Paint"


## Paint (card terraform-p2-paint-path): a coat of `surface`, or with `erase` an erase coat.
func begin_paint(_surface: String, _erase: bool) -> bool:
	return _not_yet("Paint")


## River (card terraform-p2-water): the drawn line (world XZ, as WaterEditor.carve_river takes
## it) as one river primitive (TerraWaterTools.add_river; a primitive river has no speed). Its
## id, or -1 with last_refusal set when refused ("" for a line too short to carve).
func river(
	line: PackedVector2Array, widths: PackedFloat32Array, depth: int, _speed: float
) -> int:
	var id := water_tools.add_river(line, widths, depth)
	last_refusal = water_tools.last_refusal
	return id


## Pond (card terraform-p2-water): a pond stroke of depth class `depth` pressed at `hit`
## (TerraWaterTools.begin_pond; inside a pond it extends it).
func begin_pond(depth: int, hit: Vector3) -> bool:
	var ok := water_tools.begin_pond(depth, hit)
	last_refusal = water_tools.last_refusal
	return ok


## Water erase (card terraform-p2-water): the rivers a stroke touches go whole with their
## tributaries, the ponds it covers shrink (TerraWaterTools.begin_erase).
func begin_water_erase() -> bool:
	var ok := water_tools.begin_erase()
	last_refusal = water_tools.last_refusal
	return ok


## Wall (card terraform-p2-walls): a Wall press may go on. Its WallEditor edit and the wall sync's
## splice (sync_walls()) then make one AuthoringHistory group.
func begin_wall() -> bool:
	last_refusal = ""
	return true


## The wall sync of a WallEditor edit labelled `label` (card terraform-p2-walls): while active(),
## TerraWallSync.sync's splice as one gesture whose ground record refreshes the walls once the
## pads land (on do, undo and redo; `area` is the edit's map rect). WallEditor calls it after
## recording the list change, inside the same history group. Returns the gesture, or {} when the
## wall primitives already mirror the list (a street row) or the core is not active.
func sync_walls(label: String, area: Rect2) -> Dictionary:
	if not active():
		return {}
	# Opened first: an undo still queued reaches the document before the sync reads it.
	begin_gesture()
	var change := TerraWallSync.sync(_editor().document)
	if change.is_empty():
		_open = {}
		return {}
	if edit(change) < 0:
		_open = {}
		push_warning("TerraEditor: the session refused the wall sync")
		return {}
	return end_gesture(label, {"walls": {"area": area}})


func _not_yet(tool: String) -> bool:
	last_refusal = NOT_YET % tool
	return false


# ============================================================================
# Gestures and history
# ============================================================================


## Opens a gesture: edit() collects its edits until end_gesture(). Never waits: undos and redos
## still queued are applied first (the gesture is built on the document as it stands), and its
## edits go behind a cut, so it lands after everything pending (see the header).
func begin_gesture() -> void:
	var e := _editor()
	var s := session()
	while not _waiting.is_empty():
		var next: Array = _waiting.pop_front()
		_apply_now(next[0], next[1], next[2], next[3], next[4], next[5])
	if s != null:
		s.cut()
	_open = {
		"edits": [],
		"inverse": [],
		"restored": {},
		"before": null if not _landings.is_empty() else e.document.heights.duplicate(),
		"digest_before": (e.document.terra as TerraDoc).digest_for(e.document),
		"digests_before": checked_digests(s) if s != null and s.is_ready() else {},
	}


## True between begin_gesture() and end_gesture().
func is_open() -> bool:
	return not _open.is_empty()


## Closes the open gesture without recording it (a cancelled stroke) and returns the edits that
## take it back (its inverse, newest first; [] when none), for apply_edits() as an undo.
func abandon_gesture() -> Array:
	var inverse: Array = _open.get("inverse", [])
	_open = {}
	return inverse


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
			"doc_digest": g.doc_digest,
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
	apply_edits(g.inverse, ground_of(g), false, false, {}, g)


## Redo of gesture `g` (the history entry's redo): its edits through apply_edits().
func redo_gesture(g: Dictionary) -> void:
	apply_edits(g.edits, ground_of(g), true, false, {}, g)


## The ground record gesture `g`'s undo and redo land: its own, with the props rows, kept rocks
## and followers of its water side (`g.water`, the bridge's record of the do's water landing, once
## landed: the wet rocks it dropped come back on undo) where its own has none.
static func ground_of(g: Dictionary) -> Dictionary:
	var water: Dictionary = g.get("water", {})
	if not bool(water.get("landed", false)):
		return g.ground
	var out: Dictionary = (g.ground as Dictionary).duplicate()
	for key in ["props_before", "props_after", "kept", "crossings", "walls", "structures"]:
		if not out.has(key) and water.has(key):
			out[key] = water[key]
	return out


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
	return not _landings.is_empty() or not _waiting.is_empty()


## One frame: lands the pending landings whose stage the session has settled (its own settled
## normally does it first).
func step() -> void:
	_land_due()


## Lands everything pending now, waiting for the session's derives (they run on their own thread;
## at most FINISH_TIMEOUT_USEC): op_of() and a peer's catch-up need the side whole. The one call
## here that waits (waits counts each wait); a press, undo or redo never calls it while active().
func finish_work() -> void:
	var s := session()
	if s == null:
		_landings.clear()
		_waiting.clear()
		return
	var deadline := Time.get_ticks_usec() + FINISH_TIMEOUT_USEC
	var waited := false
	while has_work():
		s.poll()
		_land_due()
		if not has_work():
			return
		if Time.get_ticks_usec() > deadline:
			push_warning("TerraEditor: a derive did not land in time; its landing is dropped")
			_landings.clear()
			_waiting.clear()
			return
		if not waited:
			waited = true
			waits += 1
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
## appends the same primitive, and each replace taking the place of the add or replace of the same
## primitive before it when only replaces and appends of other primitives lie between (Soften's
## frames; the document and the derive end the same: update equals build).
static func compact(edits: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for change: Dictionary in edits:
		var last: Dictionary = out.back() if not out.is_empty() else {}
		var same := not last.is_empty() and int(last.get("id", -2)) == int(change.get("id", -1))
		var grows := String(last.get("op", "")) in ["add", "replace", "append"]
		if change.get("op") == "append" and same and grows:
			last.data = (last.data as PackedFloat32Array) + (change.data as PackedFloat32Array)
			continue
		if change.get("op") == "replace":
			var k := _replaced(out, int(change.get("id", -1)))
			if k >= 0:
				out[k].data = (change.data as PackedFloat32Array).duplicate()
				continue
		out.append(_copy(change))
	return out


## The index in `out` of the add or replace of primitive `id` a later replace takes the place of
## (compact()), or -1: searching back, only replaces and appends of other primitives may lie
## between.
static func _replaced(out: Array[Dictionary], id: int) -> int:
	for k in range(out.size() - 1, -1, -1):
		var op := String(out[k].get("op", ""))
		var mine := int(out[k].get("id", -2)) == id
		if mine and op in ["add", "replace"]:
			return k
		if mine or not op in ["replace", "append"]:
			return -1
	return -1


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
	# Behind a landing still pending, its heights before are the ones that landing leaves.
	var before: Variant = null if not _landings.is_empty() else e.document.heights.duplicate()
	s.cut()
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
		"doc_digest": (e.document.terra as TerraDoc).digest_for(e.document),
	}
	_arm(landing)
	return ok


## Queues `landing` for its stage (the session's stage() now, its edits told), landing it at once
## when nothing is ahead of it and the session has settled there.
func _arm(landing: Dictionary) -> void:
	var s := session()
	landing["stage"] = s.stage() if s != null else 0
	_landings.append(landing)
	_land_due()


func _on_settled() -> void:
	_land_due()


## Lands, oldest first, every pending landing whose stage the session has settled (each sees the
## derive of exactly its own edits and those before), then starts a waiting apply once none is left.
func _land_due() -> void:
	var s := session()
	while not _landings.is_empty():
		if s == null or not s.is_ready() or int(_landings[0].stage) > s.settled_stage():
			return
		if _editor().water.is_working():
			# HeightEditor.apply_ground would finish the water's work at once: wait for its worker
			# (a wet dressing refresh takes 400+ ms at 200 ft) and for the bridge's water landing
			# to spread its three frames (card terraform-p2-water: landed at once it made an 80 to
			# 100 ms frame). The session holds its next stage, and step() lands this one after.
			s.pause()
			return
		_land(_landings.pop_front())
		s.resume()
		# The next one's heights before are the ones this landing left (an open gesture's too).
		var next := _landings[0] if not _landings.is_empty() else _open
		if not next.is_empty() and next.before == null:
			next.before = _editor().document.heights.duplicate()
	if not _waiting.is_empty():
		var next: Array = _waiting.pop_front()
		_apply_now(next[0], next[1], next[2], next[3], next[4], next[5])


## Lands `l` (see the header).
func _land(l: Dictionary) -> void:
	var e := _editor()
	var s := session()
	var derive := s.settled_derive() if s != null else null
	if e != null and derive != null:
		var doc := e.document
		var rect := Rect2i()
		var before: PackedFloat32Array = (
			l.before if l.before is PackedFloat32Array else doc.heights
		)
		if before.size() == doc.heights.size():
			var whole := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
			var diff: Dictionary = derive.call("doc_heights_diff", before, doc.samples_x(), whole)
			rect = diff.get("rect", Rect2i())
		var g: Dictionary = l.gesture
		var bridge: Object = s.bridge
		var water_moved := bridge != null and int(bridge.get("water_landings")) != _water_seen
		if bridge != null:
			_water_seen = int(bridge.get("water_landings"))
		if water_moved and l.redo and not g.is_empty() and not g.has("water"):
			# The bridge landed this stage's water before this landing (it connects first).
			g["water"] = bridge.get("last_water_record")
		var ground: Dictionary = l.ground
		if water_moved:
			# The bridge's water landing dressed this ground already: no second dressing refresh.
			ground = ground.duplicate()
			ground["water_landed"] = true
		if l.land and (rect.has_area() or not ground.is_empty()):
			e.heights.apply_ground(rect, before, ground, l.redo, l.spread)
		if not g.is_empty():
			var side := "digests_after" if l.redo else "digests_before"
			g[side] = checked_digests(s)
			# The document as this side's edits left it (it may be ahead by now).
			g["doc_digest" if l.redo else "digest_before"] = l.doc_digest
		if not (l.check as Dictionary).is_empty():
			_compare(l.check, String(l.doc_digest), s)
	landings += 1
	landed.emit(bool(l.redo))


## A peer's check of its landed side (`doc_digest` the document as its edits left it) against
## the host's (see the header).
func _compare(check: Dictionary, doc_digest: String, s: TerraSession) -> void:
	var arrays: Array[String] = []
	var want := String(check.get("doc_digest", ""))
	if want != "" and doc_digest != want:
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
