extends RefCounted

## Render-job probe (`call` op) for the starting landforms (phase 5, P5-1). Positions are
## map XZ metres. step.action:
##   new {biome, size, seed, landform}  opens a new map through the controller as the
##                               driver's `new_map` op does, with the landform in the spec
##                               (AuthoringController passes it to NewMap.create). Logs the
##                               recipe's report.
##   report {landform}           the recipe's report for the open map (recomputed on a
##                               scratch document from the open one's seed and size, so a
##                               saved level answers too).
##   look {at, landform}         pans the camera so the screen centre looks at `at`: a point
##                               [x, z], or "stage" (the recipe's stage), "water" (the middle
##                               of the longest river, else the floor), "floor" (the lowest
##                               ground within a third of the half extent of the centre),
##                               "summit" (the highest ground within half the half extent),
##                               "steepest" (the biggest height step between neighbours),
##                               "fall" (the first fall's lip, else the water) or "crossing"
##                               (the first crossing's middle, else the water).

## Recipe results by seed, size and kind (see `report`).
static var _shaped: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"new":
			var biome := String(step.get("biome", ""))
			var landform := String(step.get("landform", StartingLandform.VALLEY))
			(
				base
				. call(
					"_begin_authoring",
					{
						"level": null,
						"new_map":
						{
							"size_ft": int(step.get("size", 150)),
							"biome_id": biome,
							"seed": int(step.get("seed", 1234)),
							"landform": landform,
						},
						"return_to": &"title"
					}
				)
			)
			var scratch := NewMap.create(int(step.get("size", 150)), NewMap.BARE_BIOME, 0)
			var shaped := StartingLandform.apply(
				scratch, landform, int(step.get("seed", 1234)), biome
			)
			return "new %s %s: %s" % [landform, biome, shaped.report]
		"report":
			var shaped := _shape(base, step)
			return String(shaped.get("report", "no open map"))
		"look":
			var at := _resolve(base, step)
			var gm := base.get("_game_map") as GameMap
			var cc := gm.get_camera_controller()
			var off: Vector2 = cc.call("_get_view_center_ground_offset")
			var holder := gm.cameraholder_node
			# The offset centres a point on the y = 0 plane; ground below it projects nearer
			# the camera by its depth over the pitch's tangent (a 4.5 m valley floor by 11 m),
			# so the holder slides along the view by that much to centre the real ground.
			var target := at + _parallax(gm, at)
			holder.global_position = Vector3(
				target.x - off.x, holder.global_position.y, target.y - off.y
			)
			return "look at %s (%s)" % [str(at), str(step.get("at", ""))]
	return "unknown action %s" % step.get("action", "")


## How far along the camera's horizontal look direction the ground point `at` (map XZ)
## appears displaced on screen for its height: a point `h` above the y = 0 plane projects
## like the plane point `h` / tan(pitch) further from the camera. Zero when no terrain lies
## under `at`.
static func _parallax(gm: GameMap, at: Vector2) -> Vector2:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(at.x, 0.0, at.y))
	if hit == Vector3.INF:
		return Vector2.ZERO
	var forward: Vector3 = -gm.camera_node.global_transform.basis.z
	var flat := Vector2(forward.x, forward.z)
	if flat.length() < 1e-3 or absf(forward.y) < 1e-3:
		return Vector2.ZERO
	return flat.normalized() * (hit.y * flat.length() / -forward.y)


## The recipe rerun on a flat document of the open map's size with its seed (the stage is
## not stored in the document). {} without an open authoring document.
static func _shape(base: Node, step: Dictionary) -> Dictionary:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.document == null:
		return {}
	var doc := ctrl.document
	var landform := String(step.get("landform", StartingLandform.VALLEY))
	var biome := doc.biome_ids[0] if not doc.biome_ids.is_empty() else ""
	var key := "%d_%d_%s_%s" % [doc.map_seed, doc.size_cells.x, landform, biome]
	if not _shaped.has(key):
		var scratch := MapDocument.create_flat(doc.size_cells, "", "", doc.map_seed)
		_shaped[key] = StartingLandform.apply(scratch, landform, doc.map_seed, biome)
	return _shaped[key]


static func _resolve(base: Node, step: Dictionary) -> Vector2:
	var at: Variant = step.get("at", [0, 0])
	if at is Array and (at as Array).size() >= 2:
		return Vector2(float(at[0]), float(at[1]))
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.document == null:
		return Vector2.ZERO
	var doc := ctrl.document
	match String(at):
		"stage":
			return _shape(base, step).get("stage", Vector2.ZERO)
		"crossing":
			if not doc.crossings.is_empty():
				return (doc.crossings[0].start + doc.crossings[0].end) * 0.5
			return _water_middle(doc)
		"water":
			return _water_middle(doc)
		"floor":
			return _floor(doc)
		"summit":
			return _extreme(doc, StartingLandform.half_extent(doc) * 0.5, false)
		"steepest":
			return _steepest(doc)
		"fall":
			var falls := WaterFalls.falls(doc)
			return falls[0].lip if not falls.is_empty() else _water_middle(doc)
	return Vector2.ZERO


## The middle point of the longest river chain, else the floor.
static func _water_middle(doc: MapDocument) -> Vector2:
	var longest: Array[WaterBody] = []
	var longest_m := 0.0
	var seen := {}
	for body in doc.water_bodies:
		if not body.is_river() or seen.has(body.id):
			continue
		var chain: Array[WaterBody] = []
		for id in WaterEdit.river_chain(doc.water_bodies, body.id):
			seen[id] = true
			chain.append(doc.water_body(id))
		var joined := WaterCarve.joined_course(chain)
		var arc: PackedFloat32Array = joined.arc
		if not arc.is_empty() and arc[-1] > longest_m:
			longest_m = arc[-1]
			longest = chain
	if longest.is_empty():
		return _floor(doc)
	var points: PackedVector2Array = WaterCarve.joined_course(longest).points
	return points[points.size() >> 1]


## The lowest sample within a third of the half extent of the centre.
static func _floor(doc: MapDocument) -> Vector2:
	return _extreme(doc, StartingLandform.half_extent(doc) / 3.0, true)


## The sample with the biggest height step to its +x neighbour, at least 2 m inside the map
## edge (a bluff's face, a ravine's wall, a crown's face).
static func _steepest(doc: MapDocument) -> Vector2:
	var best := Vector2.ZERO
	var biggest := -INF
	for z in doc.samples_z():
		for x in doc.samples_x() - 1:
			var p := doc.sample_to_world(Vector2(x, z))
			if not StartingLandform.inside(doc, p, 2.0):
				continue
			var i := doc.sample_index(x, z)
			var step := absf(doc.heights[i + 1] - doc.heights[i])
			if step > biggest:
				biggest = step
				best = p
	return best


## The lowest (`low`) or highest sample within `reach` of the centre.
static func _extreme(doc: MapDocument, reach: float, low: bool) -> Vector2:
	var best := Vector2.ZERO
	var extreme := INF if low else -INF
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.length() > reach:
				continue
			var h := doc.heights[doc.sample_index(x, z)]
			if (h < extreme) if low else (h > extreme):
				extreme = h
				best = p
	return best
