class_name CrossingEditor
extends RefCounted

## AuthoringEditor's crossing edits (phase 4b, P4b-1; the Bridge tool, P4b-2, calls them
## through `AuthoringEditor.crossings`): planning a crossing from a line drawn across water
## (CrossingPlacement snaps it to the banks), adding, replacing and removing crossings, and
## finding the one under a point. Every change is one history entry holding the crossing list
## before and after (crossings are small values, replaced whole, never edited in place), and
## refreshes the same consumers: the map's AuthoredCrossings (meshes, collision, the deck the
## grid lies on) and the scatter over the crossing's footprint (plants clear under a deck and
## at its bank landings, and grow back when it goes: ScatterGround). Frames: world in, document
## inside, as the editor. Summary: docs/systems/crossings.md.
##
## A dressed Blender map keeps its own Blender scatter under a crossing (the erase mask is the
## author's; only the authored scatter clears).
##
## Following edits (P4b-2). A crossing is data anchored to the ground and water it was snapped
## to, so an edit that changes either under it (a sculpt stroke, a tier, a river carved, a pond
## painted or extended, water erased) makes it follow: follow() snaps every crossing near the
## edit again from its own two anchors, as if the author had drawn that line again
## (CrossingPlacement.place, same kind, width and style). When the snap still makes a crossing
## it replaces the old one keeping its id (a bank moved, the river widened, the arch rises
## with the ground); when it makes none (the water under it is gone, a bank sank under water,
## the span grew too long) the crossing is removed. It is never left standing on nothing. The
## change joins the history entry of the edit that caused it (the caller stores
## record_follow()'s lists and calls restore() from its undo and redo), so one undo puts the
## ground, the water and the crossing back together. `followed` says what happened, for a
## toast when something vanished.

## Crossings followed an edit: `moved` re-anchored, `removed` removed.
signal followed(moved: int, removed: int)

## Why the last plan() or place() made nothing (last_refusal): CrossingPlacement's reasons,
## or one of these.
const REFUSED_FULL := &"full"
const REFUSED_INVALID := &"invalid"
## follow() keeps a crossing as it is when a new snap moves no anchor more than this and no
## level more than FOLLOW_LEVEL_M (metres, map frame): the snap is only as exact as its
## waterline search, and an edit beside a crossing should not nudge it.
const FOLLOW_MOVE_M := 0.03
const FOLLOW_LEVEL_M := 0.02
## An edit reaches crossings whose footprint (CrossingGeometry.clear_bounds) comes within this
## of its area (map metres): a bank a little past the landing still changes the snap.
const FOLLOW_REACH_M := 1.0

## Why the last plan(), place() or add() made nothing, or &"".
var last_refusal: StringName = &""
## Microseconds of the last change's refresh (geometry and nodes), for measurement.
var last_refresh_usec: int = 0
## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> CrossingEditor:
	var crossings := CrossingEditor.new()
	crossings._owner = weakref(editor)
	return crossings


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


## Every crossing of the document, as copies (in document order).
func list() -> Array[Crossing]:
	var out: Array[Crossing] = []
	for crossing in _editor().document.crossings:
		out.append(crossing.copy())
	return out


## A copy of crossing `crossing_id`, or null.
func get_crossing(crossing_id: int) -> Crossing:
	var crossing := _editor().document.crossing(crossing_id)
	return crossing.copy() if crossing != null else null


## The crossing a line drawn from world point `from` to `to` would make over the water, of
## kind `kind` (`width` <= 0: the kind's default), styled by the biome under its middle; null
## with last_refusal set when the line makes none (CrossingPlacement.REFUSED_*, or
## REFUSED_FULL). Changes nothing: the tool's live preview, and what place() adds.
func plan(kind: Crossing.Kind, from: Vector3, to: Vector3, width: float = -1.0) -> Crossing:
	var e := _editor()
	var doc := e.document
	last_refusal = &""
	if doc.next_crossing_id() < 0:
		last_refusal = REFUSED_FULL
		return null
	var a := e.to_map_xz(from)
	var b := e.to_map_xz(to)
	var style := CrossingPlacement.style_at(doc, (a + b) * 0.5)
	var placed := CrossingPlacement.place(doc, a, b, kind, width / e.map_scale(), style)
	last_refusal = placed.refusal
	return placed.crossing


## plan() and add(): the new crossing's id, or -1 (last_refusal says why).
func place(kind: Crossing.Kind, from: Vector3, to: Vector3, width: float = -1.0) -> int:
	var crossing := plan(kind, from, to, width)
	if crossing == null:
		return -1
	return add(crossing)


## Adds `crossing` (map frame; its id is replaced by a free one) as one history entry.
## Returns its id, or -1 when the document is full or the writer would refuse it
## (MapCrossingIO.crossing_problem; last_refusal REFUSED_INVALID).
func add(crossing: Crossing) -> int:
	var doc := _editor().document
	last_refusal = &""
	var crossing_id := doc.next_crossing_id()
	if crossing_id < 0:
		last_refusal = REFUSED_FULL
		return -1
	var added := crossing.copy()
	added.id = crossing_id
	if MapCrossingIO.crossing_problem(added, doc.extent_m()) != "":
		last_refusal = REFUSED_INVALID
		return -1
	var after := _current()
	after.append(added)
	_change("Place " + _label(added), after, [added])
	return crossing_id


## Replaces crossing `crossing_id` with `crossing` (keeping the id), as one history entry: the
## tool's re-anchoring after a sculpt or water edit. False when there is no such crossing or
## the replacement is invalid.
func replace(crossing_id: int, crossing: Crossing) -> bool:
	var doc := _editor().document
	var old := doc.crossing(crossing_id)
	if old == null:
		return false
	var changed := crossing.copy()
	changed.id = crossing_id
	if MapCrossingIO.crossing_problem(changed, doc.extent_m()) != "":
		last_refusal = REFUSED_INVALID
		return false
	var after: Array[Crossing] = []
	for entry in doc.crossings:
		after.append(changed if entry.id == crossing_id else entry)
	_change("Move " + _label(changed), after, [old, changed])
	return true


## Removes crossing `crossing_id` as one history entry. False when there is none.
func remove(crossing_id: int) -> bool:
	var doc := _editor().document
	var old := doc.crossing(crossing_id)
	if old == null:
		return false
	var after: Array[Crossing] = []
	for entry in doc.crossings:
		if entry.id != crossing_id:
			after.append(entry)
	_change("Remove " + _label(old), after, [old])
	return true


## The id of the crossing whose footprint holds world point `point` (within `margin` world
## metres of its deck or stones, anchors included), the nearest one when several do, or -1:
## what a Ctrl press over a crossing erases.
func crossing_at(point: Vector3, margin: float = 0.3) -> int:
	var e := _editor()
	var p := e.to_map_xz(point)
	var reach := margin / e.map_scale()
	var best := -1
	var best_distance := INF
	for crossing in e.document.crossings:
		var span := crossing.span_m()
		if span <= 0.0:
			continue
		var uv := CrossingGeometry.local_of(crossing, p)
		var du := maxf(maxf(-uv.x, uv.x - span), 0.0)
		var dv := maxf(absf(uv.y) - crossing.width_m * 0.5, 0.0)
		var distance := Vector2(du, dv).length()
		if distance <= reach and distance < best_distance:
			best = crossing.id
			best_distance = distance
	return best


## The crossings of `doc` after an edit changed its ground or water over `area` (map XZ; an
## empty rectangle: everywhere), by the rule in the header: {"crossings": the whole list
## after (untouched and unmoved crossings are the same objects), "moved": how many were
## re-anchored, "removed": how many went}. Pure.
static func followed_list(doc: MapDocument, area: Rect2) -> Dictionary:
	var out: Array[Crossing] = []
	var moved := 0
	var removed := 0
	for crossing in doc.crossings:
		var bounds := CrossingGeometry.clear_bounds(crossing).grow(FOLLOW_REACH_M)
		if area.has_area() and not bounds.intersects(area):
			out.append(crossing)
			continue
		var snapped := CrossingPlacement.anchor(
			doc, crossing.start, crossing.end, crossing.kind, crossing.width_m, crossing.style
		)
		if snapped != null:
			snapped.id = crossing.id
		if snapped == null or MapCrossingIO.crossing_problem(snapped, doc.extent_m()) != "":
			removed += 1
		elif _near(snapped, crossing):
			out.append(crossing)
		else:
			out.append(snapped)
			moved += 1
	return {"crossings": out, "moved": moved, "removed": removed}


## True when `a` and `b` stand within FOLLOW_MOVE_M and FOLLOW_LEVEL_M of each other.
static func _near(a: Crossing, b: Crossing) -> bool:
	var levels := (a.levels - b.levels).abs()
	return (
		a.start.distance_to(b.start) <= FOLLOW_MOVE_M
		and a.end.distance_to(b.end) <= FOLLOW_MOVE_M
		and maxf(levels.x, maxf(levels.y, levels.z)) <= FOLLOW_LEVEL_M
	)


## Makes the document's crossings follow an edit of its ground or water over `area` (map XZ;
## see the header), refreshing their nodes and the scatter at once, without a history entry of
## its own. Returns what the edit's entry needs to put them back ({"before", "after", "area"},
## for restore()), or {} when nothing changed. Emits followed.
func follow(area: Rect2) -> Dictionary:
	var doc := _editor().document
	if doc.crossings.is_empty():
		return {}
	var result := followed_list(doc, area)
	if int(result.moved) == 0 and int(result.removed) == 0:
		return {}
	var before := _current()
	var after: Array[Crossing] = result.crossings
	var changed: Array[Crossing] = []
	for old in before:
		if not after.has(old):
			changed.append(old)
	for new in after:
		if not before.has(new):
			changed.append(new)
	var bounds := _area_of(changed)
	_apply(after, bounds)
	followed.emit(int(result.moved), int(result.removed))
	return {"before": before, "after": after, "area": bounds}


## Puts back the crossings of a follow() record (`redo`: its after side, else its before
## side), from the undo and redo of the edit that caused it. {} does nothing.
func restore(record: Dictionary, redo: bool) -> void:
	if record.is_empty():
		return
	_apply(record.after if redo else record.before, record.area)


## The document's crossings as a new list of the same objects.
func _current() -> Array[Crossing]:
	var out: Array[Crossing] = []
	out.assign(_editor().document.crossings)
	return out


## Sets the document's crossings to `after`, refreshes around `touched`, and records it.
func _change(label: String, after: Array[Crossing], touched: Array[Crossing]) -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()
	var before := _current()
	var area := _area_of(touched)
	_apply(after, area)
	(
		e
		. history
		. record(
			{
				"label": label,
				"undo": _apply.bind(before, area),
				"redo": _apply.bind(after, area),
				"bytes": 256 * (before.size() + after.size()),
			}
		)
	)
	e.edited.emit()


## Puts `crossings` into the document and refreshes the nodes and the scatter over `area`
## (map XZ).
func _apply(crossings: Array[Crossing], area: Rect2) -> void:
	var e := _editor()
	var list: Array[Crossing] = []
	list.assign(crossings)
	e.document.crossings = list
	var started := Time.get_ticks_usec()
	if is_instance_valid(e.map_root):
		AuthoredCrossings.refresh_map(e.map_root, e.document)
	last_refresh_usec = Time.get_ticks_usec() - started
	if is_instance_valid(e.scatter) and area.has_area():
		e.scatter.request_region(area)


static func _area_of(touched: Array[Crossing]) -> Rect2:
	var area := Rect2()
	for crossing in touched:
		var bounds := CrossingGeometry.clear_bounds(crossing)
		area = bounds if not area.has_area() else area.merge(bounds)
	return area


static func _label(crossing: Crossing) -> String:
	match crossing.kind:
		Crossing.Kind.STONES:
			return "stepping stones"
		Crossing.Kind.ARCH:
			return "stone arch"
	return "bridge"
