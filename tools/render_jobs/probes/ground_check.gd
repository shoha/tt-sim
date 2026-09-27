extends RefCounted

## Render-job probe (`call` op) for scatter against the ground of an opened map in
## authoring (a dressed GLB above all). Every ray is a layer-1 downcast
## (DragPlaceController.raycast_terrain_down), the ground tokens and props land on.
##
## step.action:
## - "survey": casts one ray per document sample and logs how long that took, hits and
##   misses, the ground's lowest and highest Y, the document heights' range, the 10 m cell
##   with the most relief (its centre, for placing a stroke), and every StaticBody3D on
##   layer 1 under the map root.
## - "rows" (default): compares each authored scatter row's Y with the ground under it
##   (world frame): row count, mean and worst |dY|, rows off by more than 0.1 m, a few
##   examples, and the mean angle between each row's up axis and the ground normal for
##   the normal-aligned assets and the upright ones. step.near = [x, z, r] limits it to
##   rows within r metres of (x, z).


static func run(base: Node, step: Dictionary) -> String:
	var c := base.get("_authoring_controller") as AuthoringController
	if c == null or c.document == null or not is_instance_valid(c.map_root):
		return "no authoring map"
	var space := c.map_root.get_world_3d().direct_space_state
	if String(step.get("action", "rows")) == "survey":
		return _survey(c, space)
	return _rows(c, space, step)


static func _survey(c: AuthoringController, space: PhysicsDirectSpaceState3D) -> String:
	var doc := c.document
	var xf := c.map_root.global_transform
	var started := Time.get_ticks_usec()
	var ys := PackedFloat32Array()
	ys.resize(doc.sample_count())
	var misses := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			var hit := DragPlaceController.raycast_terrain_down(space, xf * Vector3(p.x, 0, p.y))
			if hit == Vector3.INF:
				misses += 1
				ys[doc.sample_index(x, z)] = NAN
			else:
				ys[doc.sample_index(x, z)] = hit.y
	var usec := Time.get_ticks_usec() - started
	var low := INF
	var high := -INF
	for y in ys:
		if not is_nan(y):
			low = minf(low, y)
			high = maxf(high, y)
	var doc_low := INF
	var doc_high := -INF
	for h in doc.heights:
		doc_low = minf(doc_low, h)
		doc_high = maxf(doc_high, h)
	# Relief per 10 m cell, to find the slope to paint on.
	var cells := {}
	for z in doc.samples_z():
		for x in doc.samples_x():
			var y := ys[doc.sample_index(x, z)]
			if is_nan(y):
				continue
			var p := doc.sample_to_world(Vector2(x, z))
			var cell := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
			var range_now: Vector2 = cells.get(cell, Vector2(INF, -INF))
			cells[cell] = Vector2(minf(range_now.x, y), maxf(range_now.y, y))
	var best := Vector2i.ZERO
	var best_relief := -1.0
	for cell in cells:
		var r: Vector2 = cells[cell]
		if r.y - r.x > best_relief:
			best_relief = r.y - r.x
			best = cell
	var bodies := PackedStringArray()
	for node in c.map_root.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body.collision_layer & 1:
			bodies.append(String(body.name))
	return (
		(
			"survey: %d samples (%dx%d, step %s) in %.1f ms, misses %d; ground Y %.3f..%.3f;"
			+ " doc heights %.3f..%.3f; steepest cell %s centre (%.1f, %.1f) relief %.2f m;"
			+ " layer-1 bodies %s; root xf %s"
		)
		% [
			doc.sample_count(),
			doc.samples_x(),
			doc.samples_z(),
			str(doc.sample_step()),
			usec / 1000.0,
			misses,
			low,
			high,
			doc_low,
			doc_high,
			str(best),
			best.x * 10.0 + 5.0,
			best.y * 10.0 + 5.0,
			best_relief,
			",".join(bodies),
			str(xf),
		]
	)


static func _rows(
	c: AuthoringController, space: PhysicsDirectSpaceState3D, step: Dictionary
) -> String:
	if not is_instance_valid(c.scatter):
		return "no scatter"
	var xf := c.map_root.global_transform
	var near: Array = step.get("near", [])
	var aligned := {}
	for biome_id in c.document.biome_ids:
		for rule in PaletteLibrary.species(biome_id):
			if rule.get("align", "upright") == "normal":
				for asset_id in rule.get("assets", []):
					aligned[asset_id] = true
	var stride := MapDocument.ROW_STRIDE
	var count := 0
	var sum := 0.0
	var worst := 0.0
	var off := 0
	var missed := 0
	var examples := PackedStringArray()
	var angle_sum := {true: 0.0, false: 0.0}
	var angle_n := {true: 0, false: 0}
	var rows_by_asset := c.scatter.rows_by_asset()
	for asset_id in rows_by_asset:
		var rows: PackedFloat32Array = rows_by_asset[asset_id]
		for r in rows.size() / stride:
			var b := r * stride
			var world := xf * Vector3(rows[b], rows[b + 1], rows[b + 2])
			if near.size() == 3:
				var d := Vector2(world.x, world.z).distance_to(Vector2(near[0], near[1]))
				if d > float(near[2]):
					continue
			var origin := Vector3(world.x, 100.0, world.z)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 1000.0)
			query.collision_mask = 1
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				missed += 1
				continue
			var dy: float = world.y - (hit.position as Vector3).y
			count += 1
			sum += absf(dy)
			worst = maxf(worst, absf(dy))
			if absf(dy) > 0.1:
				off += 1
			if examples.size() < 6 and count % 97 == 1:
				examples.append(
					(
						"(%.2f, %.2f) row Y %.3f ground %.3f"
						% [world.x, world.z, world.y, hit.position.y]
					)
				)
			var q := Quaternion(rows[b + 3], rows[b + 4], rows[b + 5], rows[b + 6])
			var up := (q.normalized() * Vector3.UP) if q.length_squared() > 0.0 else Vector3.UP
			var is_aligned: bool = aligned.has(asset_id)
			angle_sum[is_aligned] += rad_to_deg(up.angle_to(hit.normal as Vector3))
			angle_n[is_aligned] += 1
	return (
		(
			"rows: %d checked (%d missed ground), mean |dY| %.3f m, worst %.3f m, %d off by"
			+ " > 0.1 m; up-to-ground-normal mean angle: aligned %.2f deg (n %d), upright"
			+ " %.2f deg (n %d); e.g. %s"
		)
		% [
			count,
			missed,
			sum / maxi(count, 1),
			worst,
			off,
			angle_sum[true] / maxi(angle_n[true], 1),
			angle_n[true],
			angle_sum[false] / maxi(angle_n[false], 1),
			angle_n[false],
			"; ".join(examples),
		]
	)
