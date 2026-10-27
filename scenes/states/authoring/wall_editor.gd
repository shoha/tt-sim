class_name WallEditor
extends RefCounted

## AuthoringEditor's wall edits (the Wall tool calls them through `AuthoringEditor.walls`):
## planning a wall from a line drawn on the ground, laying it as a new wall or as the next
## side of an existing one, removing walls, and finding the one under a point. Every change is
## one history entry holding the wall list before and after (walls are small values, replaced
## whole, never edited in place), and refreshes the map's AuthoredWalls (meshes and collision).
## Frames: world in, document inside, as the editor. Summary: docs/systems/walls.md.
##
## Drawing. A drag lays one straight side. When it starts within SNAP_M of the free end of an
## open wall of the same kind, the side extends that wall (from either end); when it also ends
## within SNAP_M of the wall's other end, the wall closes. A drag anywhere else starts a new
## wall. So a polyline is a chain of drags, each beginning where the last one ended.
##
## A wall follows the ground it stands on without an anchor: AuthoredWalls rebuilds the walls
## whose ground changed (WallGeometry.key_of), and follow() asks for that after a sculpt or
## water edit; the record puts the refresh in the undo too.

## Why the last plan() or add() made nothing (last_refusal).
const REFUSED_SHORT := &"short"
const REFUSED_FULL := &"full"
const REFUSED_LONG := &"long"
const REFUSED_POINTS := &"points"
const REFUSED_INVALID := &"invalid"
## A drag begins or ends on a wall's free end within this of it (world metres).
const SNAP_M := 0.6
## An edit reaches walls whose footprint (WallGeometry.clear_bounds) comes within this of its
## area (map metres).
const FOLLOW_REACH_M := 1.0

## Why the last plan() or add() made nothing, or &"".
var last_refusal: StringName = &""
## Microseconds of the last change's refresh, for measurement.
var last_refresh_usec: int = 0
## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> WallEditor:
	var walls := WallEditor.new()
	walls._owner = weakref(editor)
	return walls


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


## Every wall of the document, as copies (in document order).
func list() -> Array[Wall]:
	var out: Array[Wall] = []
	for wall in _editor().document.walls:
		out.append(wall.copy())
	return out


## A copy of wall `wall_id`, or null.
func get_wall(wall_id: int) -> Wall:
	var wall := _editor().document.wall(wall_id)
	return wall.copy() if wall != null else null


## The wall a drag from world point `from` to `to` would make or extend, of kind `kind` and
## (for a new wall) `height` world metres (<= 0: the kind's default); the whole wall as it
## would stand, with `closed` set when the drag closes it. Null with last_refusal set when the
## drag makes none. Changes nothing: the tool's live preview, and what add() lays.
func plan(kind: Wall.Kind, from: Vector3, to: Vector3, height: float = -1.0) -> Wall:
	var e := _editor()
	var doc := e.document
	last_refusal = &""
	var a := e.to_map_xz(from)
	var b := e.to_map_xz(to)
	if a.distance_to(b) < Wall.MIN_SEGMENT_M:
		last_refusal = REFUSED_SHORT
		return null
	var snap := SNAP_M / e.map_scale()
	var target := _free_end_near(doc, a, kind, snap)
	var wall: Wall
	if target != null:
		wall = target.copy()
		var last := wall.points[wall.points.size() - 1]
		var at_front := wall.points[0].distance_to(a) < last.distance_to(a)
		var other: Vector2 = last if at_front else wall.points[0]
		if other.distance_to(b) <= snap and wall.points.size() >= 3:
			wall.closed = true
		elif at_front:
			wall.points.insert(0, b)
		else:
			wall.points.append(b)
	else:
		if doc.next_wall_id() < 0:
			last_refusal = REFUSED_FULL
			return null
		var base := height if height > 0.0 else Wall.DEFAULT_HEIGHT_M[kind]
		var line := PackedVector2Array([a, b])
		wall = Wall.make(
			doc.next_wall_id(),
			kind,
			line,
			false,
			clampf(base / e.map_scale(), Wall.MIN_HEIGHT_M[kind], Wall.MAX_HEIGHT_M[kind]),
			CrossingPlacement.style_at(doc, (a + b) * 0.5)
		)
	var problem := MapWallIO.wall_problem(wall, doc.extent_m())
	if problem != "":
		last_refusal = _refusal_for(wall)
		return null
	return wall


## plan() and add(): the wall's id, or -1 (last_refusal says why).
func place(kind: Wall.Kind, from: Vector3, to: Vector3, height: float = -1.0) -> int:
	var wall := plan(kind, from, to, height)
	if wall == null:
		return -1
	return add(wall)


## Lays `wall` (map frame) as one history entry: a wall whose id the document holds replaces
## it (an extension), any other is added under a free id. Returns its id, or -1 when the
## document is full or the writer would refuse it (last_refusal).
func add(wall: Wall) -> int:
	var doc := _editor().document
	last_refusal = &""
	var existing := doc.wall(wall.id)
	var laid := wall.copy()
	if existing == null:
		var wall_id := doc.next_wall_id()
		if wall_id < 0:
			last_refusal = REFUSED_FULL
			return -1
		laid.id = wall_id
	if MapWallIO.wall_problem(laid, doc.extent_m()) != "":
		last_refusal = _refusal_for(laid)
		return -1
	var after: Array[Wall] = []
	for entry in doc.walls:
		after.append(laid if entry.id == laid.id else entry)
	if existing == null:
		after.append(laid)
	var touched: Array[Wall] = [laid]
	if existing != null:
		touched.append(existing)
	_change(("Extend " if existing != null else "Place ") + _label(laid), after, touched)
	return laid.id


## Removes wall `wall_id` as one history entry. False when there is none.
func remove(wall_id: int) -> bool:
	var doc := _editor().document
	var old := doc.wall(wall_id)
	if old == null:
		return false
	var after: Array[Wall] = []
	for entry in doc.walls:
		if entry.id != wall_id:
			after.append(entry)
	_change("Remove " + _label(old), after, [old])
	return true


## The id of the wall nearest world point `point` within `margin` world metres of its line, or -1:
## what a Ctrl press over a wall erases.
func wall_at(point: Vector3, margin: float = 0.5) -> int:
	var e := _editor()
	var p := e.to_map_xz(point)
	var reach := margin / e.map_scale()
	var best := -1
	var best_distance := INF
	for wall in e.document.walls:
		var distance := distance_to_line(wall, p)
		if distance <= reach and distance < best_distance:
			best = wall.id
			best_distance = distance
	return best


## The distance from map point `p` to the line of `wall` (map metres). Pure.
static func distance_to_line(wall: Wall, p: Vector2) -> float:
	var count := wall.points.size()
	var sides := count if wall.closed else count - 1
	var best := INF
	for k in maxi(sides, 0):
		var a := wall.points[k]
		var b := wall.points[(k + 1) % count]
		var nearest := Geometry2D.get_closest_point_to_segment(p, a, b)
		best = minf(best, nearest.distance_to(p))
	return best


## Refreshes the walls near an edit of the ground or water over `area` (map XZ; an empty
## rectangle: everywhere), without a history entry of its own: AuthoredWalls rebuilds the walls
## whose ground changed. Returns what the edit's entry needs to refresh them again on undo and
## redo ({"area": area}), or {} when the edit reached no wall.
func follow(area: Rect2) -> Dictionary:
	var doc := _editor().document
	var reached := false
	for wall in doc.walls:
		if (
			not area.has_area()
			or WallGeometry.clear_bounds(wall).grow(FOLLOW_REACH_M).intersects(area)
		):
			reached = true
			break
	if not reached:
		return {}
	apply_list(_current(), Rect2())
	return {"area": area}


## Refreshes the walls again after an edit's undo or redo put its ground back (a follow()
## record). {} does nothing.
func restore(record: Dictionary, _redo: bool) -> void:
	if record.is_empty():
		return
	apply_list(_current(), Rect2())


## The document's walls as a new list of the same objects.
func _current() -> Array[Wall]:
	var out: Array[Wall] = []
	out.assign(_editor().document.walls)
	return out


## Sets the document's walls to `after`, refreshes around `touched`, and records it.
func _change(label: String, after: Array[Wall], touched: Array[Wall]) -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()
	var before := _current()
	var area := _area_of(touched)
	apply_list(after, area)
	(
		e
		. history
		. record(
			{
				"label": label,
				"undo": apply_list.bind(before, area),
				"redo": apply_list.bind(after, area),
				"bytes": 512 * (before.size() + after.size()),
			}
		)
	)
	e.edited.emit()


## Puts `walls` into the document and refreshes the nodes (and the scatter over `area`, map
## XZ): the undo and redo of a wall edit, and a live walls edit.
func apply_list(walls: Array[Wall], area: Rect2) -> void:
	var e := _editor()
	var copied: Array[Wall] = []
	copied.assign(walls)
	e.document.walls = copied
	var started := Time.get_ticks_usec()
	if is_instance_valid(e.map_root):
		AuthoredWalls.refresh_map(e.map_root, e.document)
	last_refresh_usec = Time.get_ticks_usec() - started
	if is_instance_valid(e.scatter) and area.has_area():
		e.scatter.request_region(area)


## The free end of an open wall of `kind` within `snap` (map metres) of `p`, nearest first, or
## null. A wall with both ends near `p` answers with itself.
static func _free_end_near(doc: MapDocument, p: Vector2, kind: Wall.Kind, snap: float) -> Wall:
	var best: Wall = null
	var best_distance := snap
	for wall in doc.walls:
		if wall.kind != kind or wall.closed:
			continue
		for end in [wall.points[0], wall.points[wall.points.size() - 1]]:
			var distance: float = end.distance_to(p)
			if distance <= best_distance:
				best = wall
				best_distance = distance
	return best


static func _refusal_for(wall: Wall) -> StringName:
	if wall.points.size() > Wall.MAX_POINTS:
		return REFUSED_POINTS
	if wall.length_m() > Wall.MAX_LENGTH_M:
		return REFUSED_LONG
	return REFUSED_INVALID


static func _area_of(touched: Array[Wall]) -> Rect2:
	var area := Rect2()
	for wall in touched:
		var bounds := WallGeometry.clear_bounds(wall)
		area = bounds if not area.has_area() else area.merge(bounds)
	return area


static func _label(wall: Wall) -> String:
	return "fence" if wall.is_fence() else "wall"
