extends RefCounted

## Render-job probe (`call` op) for the grid on a Blender (GLB) map's ground (P3-3c).
##
## step.action:
## - "survey": samples the loaded map's layer-1 collision on regular grids over its mesh
##   bounds at each spacing in step.spacings (default [0.25, 0.5, 1.0] m) and logs, per
##   spacing, the ray time, misses, and how far the sampled surface (the grid shader's
##   triangle interpolation) is from the real collision at step.n (default 4000) random
##   points: mean, p95, p99, worst, and the share over 0.1 m and 0.2 m, on ground the grid
##   draws on (normal Y >= 0.7). Also the share of hits within 0.2 m and
##   GroundHeightField.FLAT_BAND_M of Y = 0.
## - "play_res": plays a built-in level resource, step.path (a res:// LevelData).
## - "grid": logs the grid overlay's ground state (follows_ground, provider size, step).
## - "measure": toggles the measure tool through GameMap (step.on, default true).
## - "drag": starts (step.on true, default) or stops a token drag's grid auto-show through
##   the handlers the drag signals call, with the first token as the dragged object; logs
##   the token's position.
## - "token_at": logs every token's name and world position.
## - "key_g": presses and releases G through Input (the explicit grid toggle).
## - "fit": logs the last grid ground fit of a play-time load
##   (LevelPlayLoader.grid_ground_fit) and of an authoring dressing (ground_fit).

const TRUTH_TOP := 200.0


static func run(base: Node, step: Dictionary) -> String:
	var gm := base.get("_game_map") as GameMap
	match String(step.get("action", "survey")):
		"play_res":
			var level := ResourceLoader.load(String(step.path)) as LevelData
			if level == null:
				return "no level at %s" % step.path
			base.call("_on_play_level_requested", level)
			return "playing %s" % step.path
		"grid":
			return _grid_state(gm)
		"measure":
			var on := bool(step.get("on", true))
			var tool := gm.get_measure_tool()
			if tool == null:
				return "no measure tool"
			if tool.is_active() != on:
				tool.toggle()
			return "measure active %s" % str(tool.is_active())
		"drag":
			return _drag(gm, bool(step.get("on", true)))
		"token_at":
			return _tokens(base)
		"fit":
			var lpc: Node = base.get("_level_play_controller")
			var loader: Variant = lpc.get("_level_loader") if lpc else null
			var ac := base.get("_authoring_controller") as AuthoringController
			return (
				"play fit %s | authoring fit %s"
				% [
					str(loader.get("grid_ground_fit")) if loader else "-",
					str(ac.ground_fit) if ac else "-",
				]
			)
		"key_g":
			for pressed in [true, false]:
				var key := InputEventKey.new()
				key.keycode = KEY_G
				key.physical_keycode = KEY_G
				key.pressed = pressed
				Input.parse_input_event(key)
			return "G sent"
	return _survey(gm, step)


static func _map_root(gm: GameMap) -> Node3D:
	if gm == null or gm.map_container == null:
		return null
	return gm.map_container.get_node_or_null(^"LevelMap") as Node3D


static func _grid_state(gm: GameMap) -> String:
	var grid := gm.get_grid_overlay()
	if grid == null:
		return "no grid overlay"
	var mat := grid.material_override as ShaderMaterial
	var tex := mat.get_shader_parameter("ground_heights") as Texture2D
	return (
		"follows_ground %s enabled %s tex %s origin %s step %s tol %s band y %s +- %s visible %s"
		% [
			str(grid.follows_ground()),
			str(mat.get_shader_parameter("ground_heights_enabled")),
			str(tex.get_size()) if tex else "none",
			str(mat.get_shader_parameter("ground_grid_origin")),
			str(mat.get_shader_parameter("ground_grid_step")),
			str(mat.get_shader_parameter("ground_tolerance")),
			str(mat.get_shader_parameter("grid_y_level")),
			str(mat.get_shader_parameter("grid_y_tolerance")),
			str(grid.is_grid_visible()),
		]
	)


static func _tokens(base: Node) -> String:
	var out := PackedStringArray()
	for node in base.get_tree().get_nodes_in_group("board_tokens"):
		if node is Node3D:
			out.append("%s %s" % [node.name, str((node as Node3D).global_position)])
	return "tokens: " + ("; ".join(out) if not out.is_empty() else "none")


static func _drag(gm: GameMap, on: bool) -> String:
	var ctrl := gm.get("_grid_visibility") as GridVisibilityController
	if not on:
		ctrl._on_drag_stopped_grid(null)
		return "drag stopped"
	var tokens := gm.get_tree().get_nodes_in_group("board_tokens")
	var obj: DraggingObject3D = null
	for node in tokens:
		var found := (node as Node).find_children("*", "DraggingObject3D", true, false)
		if not found.is_empty():
			obj = found[0] as DraggingObject3D
			break
	ctrl._on_drag_started_grid(obj)
	return "drag started with %s" % (str(obj.objectBody.global_position) if obj else "no token")


static func _survey(gm: GameMap, step: Dictionary) -> String:
	var root := _map_root(gm)
	if root == null:
		return "no map"
	var space := root.get_world_3d().direct_space_state
	var bounds := LevelEnvironmentManager.compute_map_bounds(root)
	var lines := PackedStringArray()
	lines.append("bounds %s..%s" % [str(bounds.position), str(bounds.end)])
	# Truth points.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var truth: Array[Vector3] = []
	var n := int(step.get("n", 4000))
	var near0 := 0
	var near_band := 0
	var hits := 0
	var tries := 0
	while truth.size() < n and tries < n * 4:
		tries += 1
		var x := rng.randf_range(bounds.position.x, bounds.end.x)
		var z := rng.randf_range(bounds.position.z, bounds.end.z)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, TRUTH_TOP, z), Vector3(x, -TRUTH_TOP, z)
		)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		hits += 1
		var p: Vector3 = hit.position
		if absf(p.y) <= 0.2:
			near0 += 1
		if absf(p.y) <= GroundHeightField.FLAT_BAND_M:
			near_band += 1
		if (hit.normal as Vector3).y >= 0.7:
			truth.append(p)
	lines.append(
		(
			(
				"truth: %d tries, %d hits, %d flat-enough; hits within 0.2 m of Y0 %.1f%%,"
				+ " within 0.5 m %.1f%%"
			)
			% [
				tries,
				hits,
				truth.size(),
				100.0 * near0 / maxi(hits, 1),
				100.0 * near_band / maxi(hits, 1)
			]
		)
	)
	var top := bounds.end.y + DragPlaceController.TERRAIN_DOWNCAST_HEIGHT
	for spacing in step.get("spacings", [0.25, 0.5, 1.0]):
		var s := float(spacing)
		var columns := int(ceil(bounds.size.x / s)) + 1
		var rows := int(ceil(bounds.size.z / s)) + 1
		var origin := Vector2(bounds.position.x, bounds.position.z)
		var heights := PackedFloat32Array()
		heights.resize(columns * rows)
		var hit_mask := PackedByteArray()
		hit_mask.resize(columns * rows)
		var started := Time.get_ticks_usec()
		for z in rows:
			for x in columns:
				var hit := DragPlaceController.raycast_terrain_down(
					space, Vector3(origin.x + x * s, 0.0, origin.y + z * s), top
				)
				if hit != Vector3.INF:
					heights[z * columns + x] = hit.y
					hit_mask[z * columns + x] = 1
		var ray_ms := (Time.get_ticks_usec() - started) / 1000.0
		var filled := DressingGround.fill_misses(heights, hit_mask, columns, rows)
		var errs := PackedFloat32Array()
		for p in truth:
			var at := (Vector2(p.x, p.z) - origin) / s
			var h := ScatterGenerator.triangle_height(filled, columns, rows, at)
			errs.append(absf(h - p.y))
		errs.sort()
		var sum := 0.0
		var over1 := 0
		var over2 := 0
		for e in errs:
			sum += e
			if e > 0.1:
				over1 += 1
			if e > 0.2:
				over2 += 1
		var m := maxi(errs.size(), 1)
		(
			lines
			. append(
				(
					(
						"spacing %.2f: %dx%d = %d rays in %.1f ms, misses %d; err mean %.4f"
						+ " p95 %.4f p99 %.4f max %.3f; >0.1 %.2f%% >0.2 %.2f%%"
					)
					% [
						s,
						columns,
						rows,
						columns * rows,
						ray_ms,
						hit_mask.count(0),
						sum / m,
						errs[int(errs.size() * 0.95)] if not errs.is_empty() else 0.0,
						errs[int(errs.size() * 0.99)] if not errs.is_empty() else 0.0,
						errs[errs.size() - 1] if not errs.is_empty() else 0.0,
						100.0 * over1 / m,
						100.0 * over2 / m,
					]
				)
			)
		)
	var bodies := PackedStringArray()
	for node in root.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body.collision_layer & 1:
			bodies.append(String(body.name))
	lines.append("layer-1 bodies (%d): %s" % [bodies.size(), ",".join(bodies.slice(0, 20))])
	return " | ".join(lines)
