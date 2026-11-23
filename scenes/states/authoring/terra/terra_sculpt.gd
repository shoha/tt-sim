class_name TerraSculpt
extends RefCounted

## The Sculpt tool on terrain primitives (card terraform-p2-sculpt; docs/systems/terraform.md
## "Tools"): TerraEditor's sculpt ops while active(). One stroke is one TerraEditor gesture and
## one history entry, whose undo and redo are exact.
##
## Ops. Raise, Lower and Smooth are one stroke primitive (kind 3, modes 0 / 1 / 2); Flatten, Tier
## and Tier cut one level primitive (kind 17, edges 0 / 1 / 2: a run of tier dabs at one target is
## one completed tier); Terrace one terrace primitive (kind 16, TerraceTool). The first frame with
## dabs adds the primitive, every later frame appends that frame's: a raise frame's capsule as
## point dabs at most radius / 4 apart (StrokeKind.capsule_dabs), a level frame's as one capsule
## dab (LevelKind), a terrace's along the path travelled (TerraceTool.frame_dabs). Soften (the
## erase, TerraSoften) edits what is there instead: one replace, or a remove, per sculpt primitive
## the ring touches, and over a landform, water or path it must not edit a smooth stroke along the
## ring (only the ground under the ring changes).
##
## Ground. Every frame goes through TerraEditor.edit(change, true) (TerraBridge.held: derived at
## once when the session is free, the heights written in place) inside HeightEditor's external
## stroke, which snaps plants and props to the new ground, keeps rocks as props, re-anchors
## crossings, walls and structures, sets tokens back down and dresses the water; its record is the
## gesture's ground side. Never blocking: the external stroke begins without waiting
## (HeightEditor.begin_external(false)); while the edit before still has the water's or the rock
## keeper's worker running it cannot, so the frames' dabs wait here and go in, together, on the
## first frame it can (the ground catches up). Only a release before that waits (counted in waits).
##
## Folding (board item 38). At a stroke's end, when the session is idle (TerraDerive.consolidate
## returns nothing during an async derive), fold_run() finds the oldest maximal run of consecutive
## compose primitives that are strokes, levels or terraces, leaving the newest KEEP_LIVE of them
## live; past CONSOLIDATE_DABS dabs, consolidate turns the run into sculpt rasters (kind 9) and
## fold_edit()'s one splice puts them in its place, inside this stroke's gesture, so its undo puts
## the run back. A new map's landform levels (hundreds of dabs each) fold as part of such a run.

## The Sculpt ops past HeightBrush's (RAISE 0 to TIER_CUT 5): the tiles only the core has.
const TERRACE := 6
const SOFTEN := 7
## Folding: the newest foldable primitives kept live, and the dabs past which a run folds.
const KEEP_LIVE := 8
const CONSOLIDATE_DABS := 4096
## The kinds a fold takes (stroke, terrace, level) and their dab strides.
const FOLDABLE := {TerraCore.STROKE: 5, 16: 5, 17: 8}
const LEVEL := 17
const TERRACE_KIND := 16
## History labels.
const LABELS := {
	HeightBrush.RAISE: "Raise",
	HeightBrush.LOWER: "Lower",
	HeightBrush.SMOOTH: "Smooth",
	HeightBrush.FLATTEN: "Flatten",
	HeightBrush.TIER: "Tier",
	HeightBrush.TIER_CUT: "Cut tier",
	TERRACE: "Terrace",
	SOFTEN: "Soften",
}

const TerraceTool := preload("res://utils/terraform/kinds/terrace/terrace_tool.gd")
const StrokeKind := preload("res://utils/terraform/kinds/stroke/stroke_kind.gd")
const LevelKind := preload("res://utils/terraform/kinds/level/level_kind.gd")

## Folds so far, and the last one: {"run": primitives, "dabs", "rasters", "usec"} (tests, bench).
var folds := 0
var last_fold: Dictionary = {}
## Releases that had to wait for the ground machinery (see the header).
var waits := 0
## Microseconds of the last frame's edits (the held derives and the bridge's writes included).
var last_frame_usec := 0

var _editor_ref: WeakRef = null
var _terra_ref: WeakRef = null
## The stroke: its op (-1: none), the map-frame target of a level, the primitive it added (-1:
## not yet), dabs waiting for the ground (see the header), the newest terrace dab, and Soften's
## share left per primitive (id -> PackedFloat32Array, one per dab).
var _op := -1
var _target := 0.0
var _id := -1
var _pending := PackedFloat32Array()
var _soften_frames: Array[Array] = []
var _last := Vector2.INF
var _factors: Dictionary = {}


static func create(editor: AuthoringEditor, terra: TerraEditor) -> TerraSculpt:
	var s := TerraSculpt.new()
	s._editor_ref = weakref(editor)
	s._terra_ref = weakref(terra)
	return s


func _editor() -> AuthoringEditor:
	return _editor_ref.get_ref() as AuthoringEditor if _editor_ref != null else null


func _terra() -> TerraEditor:
	return _terra_ref.get_ref() as TerraEditor if _terra_ref != null else null


## True while a stroke is in progress.
func is_stroking() -> bool:
	return _op >= 0


## Starts a stroke of Sculpt op `op` (HeightBrush's, TERRACE or SOFTEN) toward world height
## `target_y` (Flatten, Tier). Never waits (see the header). False when the map cannot be sculpted.
func begin(op: int, target_y: float) -> bool:
	var e := _editor()
	if e == null or not e.can_sculpt() or not LABELS.has(op):
		return false
	_op = op
	_target = e.to_map(Vector3(0.0, target_y, 0.0)).y
	_id = -1
	_pending = PackedFloat32Array()
	_soften_frames.clear()
	_last = Vector2.INF
	_factors.clear()
	_terra().begin_gesture()
	e.heights.begin_external(false)
	return true


## One frame's exposure (world points and radius): the frame's dabs, applied at flush().
func dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if _op < 0:
		return
	var e := _editor()
	var a := e.to_map_xz(from)
	var b := e.to_map_xz(to)
	var r := radius / e.map_scale()
	if _op == SOFTEN:
		_soften_frames.append([a, b, r, seconds])
		return
	_pending.append_array(_frame_dabs(a, b, r, seconds))


## The dabs of one frame of the stroke (map frame).
func _frame_dabs(a: Vector2, b: Vector2, r: float, seconds: float) -> PackedFloat32Array:
	match _op:
		HeightBrush.RAISE, HeightBrush.LOWER, HeightBrush.SMOOTH:
			return StrokeKind.capsule_dabs(a, b, r, seconds, _op)
		HeightBrush.FLATTEN:
			return LevelKind.flatten_dab(a, b, r, seconds, _target)
		HeightBrush.TIER, HeightBrush.TIER_CUT:
			return LevelKind.tier_dab(a, b, r, _target, _op == HeightBrush.TIER_CUT)
		TERRACE:
			var tread := TerraceTool.tread_m(_editor().document.tier_height_m)
			var made := TerraceTool.frame_dabs(a, b, r, tread, _last)
			_last = made["last"]
			return made["data"]
	return PackedFloat32Array()


## Pushes this frame's dabs to the ground (TerraBridge.held), once the ground machinery is ready.
func flush() -> void:
	if _op < 0:
		return
	var e := _editor()
	if not e.heights.is_external() and not e.heights.begin_external(false):
		return
	var started := Time.get_ticks_usec()
	_apply_pending()
	last_frame_usec = Time.get_ticks_usec() - started
	e.last_flush_usec = last_frame_usec


func _apply_pending() -> void:
	if _op == SOFTEN:
		for f: Array in _soften_frames:
			_soften(f[0], f[1], f[2], f[3])
		_soften_frames.clear()
		return
	if _pending.is_empty():
		return
	var data := _pending
	_pending = PackedFloat32Array()
	if _id < 0:
		var kind := _kind()
		_id = _terra().edit({"op": "add", "kind": kind, "data": data, "flags": 0}, true)
	else:
		_terra().edit({"op": "append", "id": _id, "data": data}, true)


## The primitive kind of the stroke's op.
func _kind() -> int:
	match _op:
		HeightBrush.FLATTEN, HeightBrush.TIER, HeightBrush.TIER_CUT:
			return LEVEL
		TERRACE:
			return TERRACE_KIND
	return TerraCore.STROKE


## One Soften frame (map frame): a replace or remove per sculpt primitive the ring touches, and,
## where the ring lies over ground Soften must not edit (TerraSoften.smooths: a landform hill, a
## river, a path ...), this frame's capsule of smooth dabs on the gesture's own smooth stroke.
func _soften(a: Vector2, b: Vector2, r: float, seconds: float) -> void:
	var terra := _terra()
	var doc := terra.session().terra
	var ring := Rect2(a.min(b), (a - b).abs()).grow(r)
	var edits: Array[Dictionary] = []
	var smooth := false
	for p in doc.prims:
		var kind := int(p["kind"])
		if int(p["id"]) == _id:
			# The smooth stroke this gesture lays is never softened by it.
			continue
		smooth = smooth or TerraSoften.smooths(p, ring, a, b, r)
		if not kind in TerraSoften.KINDS or TerraDoc.is_muted(p):
			continue
		var data: PackedFloat32Array = p["data"]
		var reach: Rect2 = TerraKinds.script_for(kind).bounds(data)
		if not reach.grow(r).intersects(ring, true):
			continue
		var id := int(p["id"])
		var out := TerraSoften.frame(
			kind, data, _factors.get(id, PackedFloat32Array()), a, b, r, seconds
		)
		if out.is_empty():
			continue
		var left: PackedFloat32Array = out["data"]
		_factors[id] = out["factors"]
		if left.is_empty():
			edits.append({"op": "remove", "id": id})
		else:
			edits.append({"op": "replace", "id": id, "data": left})
	for change in edits:
		terra.edit(change, true)
	if not smooth:
		return
	var dabs := StrokeKind.capsule_dabs(a, b, r, seconds, StrokeKind.SMOOTH)
	if _id < 0:
		_id = terra.edit({"op": "add", "kind": TerraCore.STROKE, "data": dabs, "flags": 0}, true)
	else:
		terra.edit({"op": "append", "id": _id, "data": dabs}, true)


## Ends the stroke and records its gesture (with a fold when one is due). True when it changed
## anything.
func end_stroke() -> bool:
	if _op < 0:
		return false
	var e := _editor()
	var terra := _terra()
	if not e.heights.is_external():
		# The ground machinery never freed up during the stroke: the one wait (see the header).
		waits += 1
		e.heights.begin_external(true)
	_apply_pending()
	var label: String = LABELS.get(_op, "Sculpt")
	_op = -1
	var record := e.heights.end_external()
	if not terra.is_open():
		return false
	_fold(terra)
	var g := terra.end_gesture(label, record, false)
	return not g.is_empty()


## Abandons the stroke: its edits are taken back as an undo would, with no history entry.
func cancel_stroke() -> void:
	if _op < 0:
		return
	var e := _editor()
	_op = -1
	_pending = PackedFloat32Array()
	_soften_frames.clear()
	var record := e.heights.end_external()
	var inverse := _terra().abandon_gesture()
	if not inverse.is_empty():
		_terra().apply_edits(inverse, record, false)


## The fold check (see the header), inside the open gesture.
func _fold(terra: TerraEditor) -> void:
	var s := terra.session()
	if s == null or not s.is_ready():
		return
	var run := fold_run(s.terra)
	if run.is_empty():
		return
	var started := Time.get_ticks_usec()
	var rasters: Array = s.settled_derive().call("consolidate", PackedInt32Array(run))
	if rasters.is_empty():
		return
	var usec := Time.get_ticks_usec() - started
	var dabs := dab_count(s.terra, run)
	if terra.edit(fold_edit(s.terra, run, rasters)) < 0:
		push_warning("TerraSculpt: the session refused the fold")
		return
	folds += 1
	last_fold = {"run": run.size(), "dabs": dabs, "rasters": rasters.size(), "usec": usec}


## The ids of the run to fold, oldest first, or [] when none is due (see the header): the oldest
## maximal run of consecutive compose primitives (other stages skipped) that are unmuted strokes,
## levels or terraces, among those older than the newest `keep_live` of them, holding more than
## `limit` dabs. Pure.
static func fold_run(
	terra: TerraDoc, keep_live := KEEP_LIVE, limit := CONSOLIDATE_DABS
) -> Array[int]:
	var foldable: Array[int] = []
	for i in terra.prims.size():
		if FOLDABLE.has(int(terra.prims[i]["kind"])):
			foldable.append(i)
	if foldable.size() <= keep_live:
		return []
	var end: int = foldable[foldable.size() - keep_live]
	var run: Array[int] = []
	var dabs := 0
	for i in end:
		var p := terra.prims[i]
		var kind := int(p["kind"])
		if TerraKinds.script_for(kind).STAGE != "compose":
			continue
		if FOLDABLE.has(kind) and not TerraDoc.is_muted(p):
			run.append(int(p["id"]))
			dabs += (p["data"] as PackedFloat32Array).size() / int(FOLDABLE[kind])
			continue
		if dabs > limit:
			return run
		run.clear()
		dabs = 0
	return run if dabs > limit else ([] as Array[int])


## The dabs of the primitives `ids`. Pure.
static func dab_count(terra: TerraDoc, ids: Array[int]) -> int:
	var n := 0
	for id in ids:
		var p := terra.find(id)
		n += (p["data"] as PackedFloat32Array).size() / int(FOLDABLE.get(int(p["kind"]), 1))
	return n


## The splice that folds run `ids` into `rasters` (TerraDerive.consolidate's) at the run's place,
## the rasters taking ids from next_id. Pure.
static func fold_edit(terra: TerraDoc, ids: Array[int], rasters: Array) -> Dictionary:
	var insert: Array = []
	for k in rasters.size():
		var data: PackedFloat32Array = rasters[k]
		insert.append({"id": terra.next_id + k, "kind": TerraCore.SCULPT, "flags": 0, "data": data})
	return {
		"op": "splice",
		"remove": ids.duplicate(),
		"insert": insert,
		"at": terra.index_of(ids[0]),
		"next_id": terra.next_id + rasters.size(),
	}
