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
## inside, as the editor. Summary: docs/ARCHITECTURE.md "Crossings".
##
## A dressed Blender map keeps its own Blender scatter under a crossing (the erase mask is the
## author's; only the authored scatter clears).

## Why the last plan() or place() made nothing (last_refusal): CrossingPlacement's reasons,
## or one of these.
const REFUSED_FULL := &"full"
const REFUSED_INVALID := &"invalid"

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
	return "bridge" if crossing.is_plank() else "stepping stones"
