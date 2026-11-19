class_name PainterFootprint
extends RefCounted

## The shapes the painted ground's contact field (PainterOcclusion) draws a structure's pool from
## (card painter-pool-shapes; painter.md "Grounding").
##
## A structure's pool used to be its meshes' bounding box grown 0.9 m, and the box held the yard's
## skirt and path (`dressing_ground`, 10 to 14 m across, 5 m past the door), so the pools of a row
## of houses ran past every footprint and merged into one teal slab. Here the pool is the building's
## own plan: the convex hull of its collision's lowest faces (the walls' and piles' feet, never the
## roof's overhang nor the yard), fitted by the smallest turned rectangle round it with its corners
## rounded so the shape keeps the hull's area. A rectangular house is a rectangle with soft corners,
## a round hut, a tulou or a hexagonal tower comes out round, a castle or a gatehouse the outline of
## its whole mass. Its reach past the walls grows with the plan's size and the building's height,
## and each structure takes its own share of it, so a barn is not a hut and no two read the same.
## Pure but for of_structure, which reads a structure node's collision. No static state.

## Collision vertices this far over the lowest one are the walls' feet (a roof's eave is higher on
## any ground a building stands on).
const FOOT_M := 1.8
## The least a footprint's corner is rounded (metres): a rectangle's pool has soft corners.
const MIN_CORNER_M := 0.4
## A pool's reach past the walls (metres): its least and most, before the structure's own share.
const REACH_MIN_M := 0.4
const REACH_MAX_M := 1.0
## How far one structure's reach may differ from another's of the same plan (a fraction each way).
const REACH_SPREAD := 0.15


## The footprint of structure node `root` (AuthoredStructures' `Structure_<id>`) in world x, z:
## {"centre": Vector2, "yaw": float, "half": Vector2, "corner": float, "height": float}, from its
## collision's lowest faces; from its meshes' bounds without the yard's dressing when it has no
## collision; {} when it has neither.
static func of_structure(root: Node3D) -> Dictionary:
	var shape_node := root.get_node_or_null(^"Collision/CollisionShape3D") as CollisionShape3D
	var shape: ConcavePolygonShape3D = null
	if shape_node != null:
		shape = shape_node.shape as ConcavePolygonShape3D
	var faces := PackedVector3Array()
	if shape != null:
		faces = shape.get_faces()
	if not faces.is_empty():
		var to_world := shape_node.global_transform
		var y0 := INF
		var y1 := -INF
		for v in faces:
			y0 = minf(y0, v.y)
			y1 = maxf(y1, v.y)
		var feet := PackedVector2Array()
		for v in faces:
			if v.y < y0 + FOOT_M:
				var w := to_world * v
				feet.append(Vector2(w.x, w.z))
		var shape_fit := fit(feet)
		if not shape_fit.is_empty():
			shape_fit["height"] = y1 - y0
			return shape_fit
	return _of_meshes(root)


## The footprint of `root`'s meshes' world bounds, the yard's dressing left out; {} with none.
static func _of_meshes(root: Node3D) -> Dictionary:
	var corners := PackedVector2Array()
	var y0 := INF
	var y1 := -INF
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or String(mesh_instance.name).begins_with("dressing"):
			continue
		var box := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		corners.append(Vector2(box.position.x, box.position.z))
		corners.append(Vector2(box.end.x, box.end.z))
		corners.append(Vector2(box.position.x, box.end.z))
		corners.append(Vector2(box.end.x, box.position.z))
		y0 = minf(y0, box.position.y)
		y1 = maxf(y1, box.end.y)
	var out := fit(corners)
	if not out.is_empty():
		out["height"] = y1 - y0
	return out


## The smallest turned rectangle round `points` (world x, z), its corners rounded so the rounded
## shape keeps the area of the points' convex hull: {"centre", "yaw" (its +x axis from world +x
## towards +z), "half", "corner"}. A rectangle's corners are MIN_CORNER_M; a regular polygon of
## six or more sides is about a disc. {} for fewer than three distinct points. Pure.
static func fit(points: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(points)
	var n := hull.size() - 1
	if n < 3:
		return {}
	var area := 0.0
	for i in n:
		area += hull[i].cross(hull[i + 1])
	area = absf(area) * 0.5
	var best := INF
	var axis := Vector2.RIGHT
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for i in n:
		var edge := hull[i + 1] - hull[i]
		if edge.length_squared() < 1e-8:
			continue
		var u := edge.normalized()
		var v := Vector2(-u.y, u.x)
		var a := Vector2(INF, INF)
		var b := Vector2(-INF, -INF)
		for k in n:
			var q := Vector2(hull[k].dot(u), hull[k].dot(v))
			a = a.min(q)
			b = b.max(q)
		var box_area := (b.x - a.x) * (b.y - a.y)
		if box_area < best - 1e-6:
			best = box_area
			axis = u
			lo = a
			hi = b
	var half := (hi - lo) * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return {}
	var mid := (lo + hi) * 0.5
	var centre := axis * mid.x + Vector2(-axis.y, axis.x) * mid.y
	# A rounded rectangle of corner r has the area w h - (4 - PI) r^2.
	var corner := sqrt(maxf(best - area, 0.0) / (4.0 - PI))
	corner = clampf(corner, minf(MIN_CORNER_M, minf(half.x, half.y)), minf(half.x, half.y))
	return {"centre": centre, "yaw": atan2(axis.y, axis.x), "half": half, "corner": corner}


## How far a structure's pool reaches past its walls (metres): more for a larger plan (`half`) and a
## taller building (`height`), within REACH_MIN_M..REACH_MAX_M, then its own share of REACH_SPREAD
## from `key` (the structure's node name), so neighbours of one plan differ. Pure.
static func reach(half: Vector2, height: float, key: String) -> float:
	var size := sqrt(4.0 * half.x * half.y)
	var base := clampf(0.3 + 0.035 * size + 0.02 * height, REACH_MIN_M, REACH_MAX_M)
	var share := float(absi(hash(key)) % 1001) / 1000.0
	return base * (1.0 - REACH_SPREAD + 2.0 * REACH_SPREAD * share)
