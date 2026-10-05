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
##                               ground within a third of the half extent of the centre) or
##                               "crossing" (the first crossing's middle, else the water).

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
			holder.global_position = Vector3(at.x - off.x, holder.global_position.y, at.y - off.y)
			return "look at %s (%s)" % [str(at), str(step.get("at", ""))]
	return "unknown action %s" % step.get("action", "")


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
	var reach := StartingLandform.half_extent(doc) / 3.0
	var best := Vector2.ZERO
	var lowest := INF
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.length() > reach:
				continue
			var h := doc.heights[doc.sample_index(x, z)]
			if h < lowest:
				lowest = h
				best = p
	return best
