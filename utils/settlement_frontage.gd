class_name SettlementFrontage
extends RefCounted

## Pure: the frontage records (procgen's ProcgenFrontage, one per street side) of a street, from
## the lots the Street tool builds it with (WallGeometry.row_lots, ProcgenRow.plan). The kit that
## dresses a street reads only this record, so a generated street and (later) hand-placed houses
## are dressed by the same code. Plan coordinates are the document's map XZ, in document metres.
##
## The facade line of a side is the street's centre line pushed out by the setback towards that
## side, with mitred corners; a lot is the range of arc length its front edge covers on it, its
## door the middle of the front (the street_row recipe puts the door in the middle of the front
## side), the street the strip between that line and the kerb. Lots are named "l<index>" (the
## index along the side, which counts empty plots, so a lot keeps its name when others change).
## The side key is "w<street id>l" or "w<street id>r".

## The share of the setback that is the strip between facade and kerb.
const STRIP_SHARE := 0.75
const STRIP_MIN_M := 1.0
const STRIP_MAX_M := 4.0
const DOOR_WIDTH_M := 1.1
const MIN_LOT_M := 1.0
## The widest a mitred corner may push out, in setbacks.
const MITRE_LIMIT := 1.6
## A building outside this of the street is no neighbour (map metres).
const NEIGHBOUR_REACH_M := 14.0


## The frontages of street `wall` (a row of `doc`), one for each side it has lots on, left first.
static func of_street(doc: MapDocument, wall: Wall) -> Array[ProcgenFrontage]:
	var out: Array[ProcgenFrontage] = []
	if wall == null or not wall.is_row():
		return out
	return from_lots(wall, WallGeometry.row_lots(doc, wall), _neighbours(doc, wall))


## The frontages of `wall` from its `lots`; `obstacles` are {"at", "radius"} discs kept clear.
static func from_lots(
	wall: Wall, lots: Array[Dictionary], obstacles: Array[Dictionary] = []
) -> Array[ProcgenFrontage]:
	var out: Array[ProcgenFrontage] = []
	for side in [1, -1]:
		var on_side: Array[Dictionary] = []
		for lot in lots:
			if int(lot["side"]) == side:
				on_side.append(lot)
		if on_side.is_empty():
			continue
		var frontage := _side_frontage(wall, on_side, side)
		frontage.obstacles = obstacles.duplicate()
		if frontage.problems().is_empty():
			out.append(frontage)
	return out


static func _side_frontage(wall: Wall, lots: Array[Dictionary], side: int) -> ProcgenFrontage:
	var frontage := ProcgenFrontage.new()
	frontage.key = "w%d%s" % [wall.id, "l" if side > 0 else "r"]
	frontage.line = facade_line(wall.points, wall.height_m, side)
	# Walking with the street's centre line, the buildings on `side` lie to its `side` and the
	# kerb to the other: ProcgenFrontage counts +1 for a street to the right of travel.
	frontage.street_side = -side
	frontage.gap_m = clampf(wall.height_m * STRIP_SHARE, STRIP_MIN_M, STRIP_MAX_M)
	frontage.open_start = true
	frontage.open_end = true
	var line := frontage.line
	var end := 0.0
	for lot in lots:
		var corners: PackedVector3Array = lot["points"]
		var a := _arc_of(line, Vector2(corners[0].x, corners[0].z))
		var b := _arc_of(line, Vector2(corners[1].x, corners[1].z))
		var s0 := maxf(minf(a, b), end + 0.05)
		var s1 := maxf(a, b)
		if s1 - s0 < MIN_LOT_M:
			continue
		var depth := Vector2(corners[0].x, corners[0].z).distance_to(
			Vector2(corners[3].x, corners[3].z)
		)
		var yard := 4.0
		var plot: PackedVector3Array = lot.get("plot", PackedVector3Array())
		if plot.size() == 4:
			yard = maxf(
				Vector2(plot[0].x, plot[0].z).distance_to(Vector2(plot[3].x, plot[3].z)) - depth,
				1.0
			)
		(
			frontage
			. lots
			. append(
				{
					"id": "l%d" % int(lot["index"]),
					"s0": snappedf(s0, ProcgenFrontage.STEP_M),
					"s1": snappedf(s1, ProcgenFrontage.STEP_M),
					"depth_m": snappedf(depth, ProcgenFrontage.STEP_M),
					"yard_m": snappedf(yard, ProcgenFrontage.STEP_M),
					"doors":
					[
						{
							"s": snappedf((s0 + s1) * 0.5, ProcgenFrontage.STEP_M),
							"width": DOOR_WIDTH_M
						}
					],
				}
			)
		)
		end = s1
	return frontage


## The centre line `points` pushed `offset` metres to its `side` (+1 left of travel as the Street
## tool counts, which is the +across of ProcgenRow), corners mitred and clamped.
static func facade_line(points: PackedVector2Array, offset: float, side: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := points.size()
	if count < 2:
		return out
	var normals: Array[Vector2] = []
	for k in range(1, count):
		var t := (points[k] - points[k - 1]).normalized()
		normals.append(Vector2(-t.y, t.x) * float(side))
	for k in count:
		var n: Vector2
		var scale := 1.0
		if k == 0:
			n = normals[0]
		elif k == count - 1:
			n = normals[count - 2]
		else:
			var sum := normals[k - 1] + normals[k]
			n = sum.normalized() if sum.length() > 0.001 else normals[k]
			scale = clampf(1.0 / maxf(n.dot(normals[k]), 0.01), 1.0, MITRE_LIMIT)
		out.append(points[k] + n * offset * scale)
	return out


## The arc length of the point of `line` nearest `p`.
static func _arc_of(line: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var best_arc := 0.0
	var walked := 0.0
	for k in range(1, line.size()):
		var near := Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k])
		var d := near.distance_squared_to(p)
		if d < best:
			best = d
			best_arc = walked + line[k - 1].distance_to(near)
		walked += line[k - 1].distance_to(line[k])
	return best_arc


## Buildings of the document near the street, as clearance discs.
static func _neighbours(doc: MapDocument, wall: Wall) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for structure in doc.structures:
		var box := Rect2(structure.footprint[0], Vector2.ZERO)
		for p in structure.footprint:
			box = box.expand(p)
		var centre := box.get_center()
		var radius := box.size.length() * 0.5
		var near := INF
		for k in range(1, wall.points.size()):
			var closest := Geometry2D.get_closest_point_to_segment(
				centre, wall.points[k - 1], wall.points[k]
			)
			near = minf(near, closest.distance_to(centre))
		if near - radius < NEIGHBOUR_REACH_M:
			out.append({"at": centre, "radius": radius})
	return out
