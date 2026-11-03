class_name RenderPieceAim
extends RefCounted

## Aims a render job's pointer at a village furnishing by what it is, not by a map coordinate: an
## `input` event's "at" may be {"piece": "bench", "nth": 0, "as": "bench1", "dx": 3, "dz": 2}. The
## piece is the `nth` (default 0) visible standing piece of that prop (or, with "rule": id in place
## of "piece", of that kit rule) in the 3D view, nearest the
## view's centre first (on screen, not behind a building: BrushTool.structure_blocks, the same test
## the Village tool picks by). "as" remembers the choice under that name, so a later event finds
## the same piece after it has been moved; "dx" and "dz" aim that many metres from the piece on the
## ground instead (where a drag should end). Static; the driver's `_screen_of` calls it.

## The 3D view's share of the window (the drawer on the left and the hint bar are outside it).
const VIEW_LEFT := 0.3
const VIEW_TOP := 0.06
const VIEW_WIDTH := 0.68
const VIEW_HEIGHT := 0.86
## The aim stands this share of the piece's radius above its foot (VillageProps.DRAWN_CENTRE).
const AIM_HEIGHT := 0.8

## Remembered choices: name to slot.
static var _chosen: Dictionary = {}


## The window pixel for `spec`, or Vector2.INF when no such piece is in view. `ground_screen` maps a
## map point [x, z] to its screen pixel on the ground (the driver's own aim).
static func screen_of(
	spec: Dictionary, ctrl: AuthoringController, camera: Camera3D, ground_screen: Callable
) -> Vector2:
	var row := _find(spec, ctrl, camera)
	if row.is_empty():
		print("RJ| piece %s: none in view" % str(spec))
		return Vector2.INF
	var at: Vector2 = row["item"]["position"]
	if spec.has("dx") or spec.has("dz"):
		return ground_screen.call([at.x + float(spec.get("dx", 0.0)), at.y + float(spec.get("dz", 0.0))])
	return camera.unproject_position(_centre(row))


## The map point (XZ) of the piece `spec` names, or Vector2.INF when none is in view (a `look_at`
## step aims the camera at a piece by it).
static func map_of(spec: Dictionary, ctrl: AuthoringController, camera: Camera3D) -> Vector2:
	var row := _find(spec, ctrl, camera)
	if row.is_empty():
		return Vector2.INF
	return row["item"]["position"]


static func _centre(row: Dictionary) -> Vector3:
	var at: Vector2 = row["item"]["position"]
	var radius := VillageFurnishings.drawn_radius(row["item"])
	return Vector3(at.x, float(row["y"]) + radius * AIM_HEIGHT, at.y)


static func _find(spec: Dictionary, ctrl: AuthoringController, camera: Camera3D) -> Dictionary:
	var rows: Array[Dictionary] = []
	for settlement in ctrl.editor.document.settlements:
		for row in VillageProps.rows_of(ctrl.editor, settlement.id):
			if not VillageFurnishings.is_centre_piece(settlement.kit, str(row["item"]["slot"])):
				rows.append(row)
	var name := str(spec.get("as", ""))
	if name != "" and _chosen.has(name):
		for row in rows:
			if str(row["item"]["slot"]) == _chosen[name]:
				return row
		return {}
	var eye := camera.global_position
	var size := camera.get_viewport().get_visible_rect().size
	var view := Rect2(
		size * Vector2(VIEW_LEFT, VIEW_TOP), size * Vector2(VIEW_WIDTH, VIEW_HEIGHT)
	)
	var middle := view.get_center()
	var seen: Array[Dictionary] = []
	for row in rows:
		# {"rule": id} takes any piece its kit rule placed (a street's carts or haystacks alike).
		if spec.has("rule"):
			if VillageFurnishings.rule_of(str(row["item"]["slot"])) != str(spec["rule"]):
				continue
		elif str(row["item"]["prop"]) != str(spec.get("piece", "")):
			continue
		var centre := _centre(row)
		if camera.is_position_behind(centre):
			continue
		var screen := camera.unproject_position(centre)
		if not view.has_point(screen) or ctrl.brush.structure_blocks(eye, centre):
			continue
		seen.append({"row": row, "d": screen.distance_to(middle)})
	seen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var nth := int(spec.get("nth", 0))
	if nth >= seen.size():
		return {}
	var row: Dictionary = seen[nth]["row"]
	if name != "":
		_chosen[name] = str(row["item"]["slot"])
		print("RJ| piece %s = %s %s" % [name, str(row["item"]["prop"]), str(row["item"]["slot"])])
	return row
