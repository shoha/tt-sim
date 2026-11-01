class_name VillageFieldGround
extends RefCounted

## What a village's fields do to the map round them (topic fields, round 3; docs/systems/villages.md
## section 11). Two rules, both pure:
##
## - Plants. A field's surfaces are ground paint (earth, crop rows, meadow), not `built`, so the
##   scatter would keep growing the map's wild grass, flowers, shrubs and trees through them and
##   hide the field (the round 3 probe: paint under the ring at full weight, plants open 1.0 over
##   it). Each field instead clears the scatter under it as a structure's footprint does: strips
##   across the disc as plank-like Crossings (clearance_crossings), the shape ScatterGround and the
##   native scatter already clear by, so the native library needs nothing new. The strips stop a
##   little inside the rim (CLEAR_INSET_M) and the clearance's own soft edge does the rest, so the
##   wild cover thins out over the field's painted fringe rather than stopping at a line. The
##   field's own plants (AuthoredFieldPlants: orchard trees, garden flowers) are not scatter and
##   stay. The strips run east-west whatever the seed, so a re-dress moves no clearance.
## - Buildings. A field may not cover a building: a structure's footprint or a street's house
##   (WallGeometry.row_lots). covers_building() is the test SettlementEditor refuses a field by and
##   the Village tool's ghost shows a refusal by; a field may brush a wall by BUILDING_GRACE_M.

## The strips' spacing across the disc and how far inside the rim they stop (metres).
const CLEAR_PITCH_M := 2.0
const CLEAR_INSET_M := 0.5
## A field's rim may reach this far over a building's wall before the field is refused.
const BUILDING_GRACE_M := 0.75
## How far past a field's rim the scatter's clearance reaches (margin, soft edge and the tree
## keep-back of CrossingGeometry): what an edit asks the scatter to regrow.
const REGROW_M := (
	CrossingGeometry.CLEAR_MARGIN_M
	+ CrossingGeometry.CLEAR_SOFT_M
	+ CrossingGeometry.CLEAR_ANCHOR_M
	+ CrossingGeometry.CLEAR_TREE_M
)


## The plant clearance of every field of every settlement of `doc`, and of every village boundary
## (VillageBoundary.clearance_crossings: the strip under its wall or hedge), as Crossings.
static func clearance_crossings(doc: MapDocument) -> Array[Crossing]:
	var out: Array[Crossing] = []
	for settlement in doc.settlements:
		for field in settlement.fields:
			out.append_array(strips_of(field))
	out.append_array(VillageBoundary.clearance_crossings(doc))
	return out


## The clearance strips of one field disc ({"at", "radius"}): rows across the disc CLEAR_PITCH_M
## apart, each as long as the disc's chord there less the clearance's rounded ends.
static func strips_of(field: Dictionary) -> Array[Crossing]:
	var out: Array[Crossing] = []
	var at: Vector2 = field["at"]
	var reach := float(field["radius"]) - CLEAR_INSET_M
	if reach <= 0.0:
		return out
	var count := maxi(ceili(2.0 * reach / CLEAR_PITCH_M), 1)
	var width := 2.0 * reach / count
	for row in count:
		var t := -reach + (row + 0.5) * width
		var chord := sqrt(maxf(reach * reach - t * t, 0.0))
		var half := maxf(chord - CrossingGeometry.CLEAR_ANCHOR_M, 0.05)
		out.append(
			Crossing.make(
				0,
				Crossing.Kind.PLANK,
				at + Vector2(-half, t),
				at + Vector2(half, t),
				Vector3.ZERO,
				width
			)
		)
	return out


## The map area whose plants a change of the settlement list from `before` to `after` regrows:
## every field (grown by REGROW_M) of each settlement whose fields differ, both versions. An
## empty Rect2 when no field changed.
static func area_of(before: Array[Settlement], after: Array[Settlement]) -> Rect2:
	var old := {}
	for settlement in before:
		old[settlement.id] = settlement
	var area := Rect2()
	var seen := {}
	for settlement in after:
		seen[settlement.id] = true
		var was: Settlement = old.get(settlement.id)
		var then: Array[Dictionary] = []
		if was != null:
			then = was.fields
		if str(then) != str(settlement.fields):
			area = _merge(area, _bounds(then))
			area = _merge(area, _bounds(settlement.fields))
	for id: int in old:
		if not seen.has(id):
			area = _merge(area, _bounds((old[id] as Settlement).fields))
	return area


## The building footprints of `doc` (map XZ polygons): every structure's, and every house of every
## street (WallGeometry.row_lots).
static func footprints(doc: MapDocument) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for structure in doc.structures:
		if structure.footprint.size() >= 3:
			out.append(structure.footprint)
	for wall in doc.walls:
		if not wall.is_row():
			continue
		for lot in WallGeometry.row_lots(doc, wall):
			var corners: PackedVector3Array = lot["points"]
			var plan := PackedVector2Array()
			for corner in corners:
				plan.append(Vector2(corner.x, corner.z))
			if plan.size() >= 3:
				out.append(plan)
	return out


## True when a field disc at `at` of `radius` covers one of `plans` (footprints()) by more than
## BUILDING_GRACE_M.
static func covers_building(plans: Array[PackedVector2Array], at: Vector2, radius: float) -> bool:
	var reach := radius - BUILDING_GRACE_M
	for plan in plans:
		if Geometry2D.is_point_in_polygon(at, plan):
			return true
		if reach <= 0.0:
			continue
		for k in plan.size():
			var a := plan[k]
			var b := plan[(k + 1) % plan.size()]
			if Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < reach:
				return true
	return false


static func _bounds(fields: Array[Dictionary]) -> Rect2:
	var area := Rect2()
	for field in fields:
		var at: Vector2 = field["at"]
		var r := float(field["radius"]) + REGROW_M
		area = _merge(area, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0))
	return area


static func _merge(area: Rect2, more: Rect2) -> Rect2:
	if not more.has_area():
		return area
	return more if not area.has_area() else area.merge(more)
