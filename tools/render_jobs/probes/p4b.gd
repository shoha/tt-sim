extends RefCounted

## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
##                                `from` to `to` (map XZ): ground, water level, depth, the wet
##                                dressing's bed / shore / wet line, and the painted weight of
##                                `surface` at the nearest sample. For the path-meets-water fix.
##   cues                         in play: every token's height, base, the water surface over
##                                it and whether its submerged cue (SubmergedMarker) shows.
##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
##                                over map XZ `to` (the drag stays active, the token eases
##                                there over the next frames), for a capture mid-drag.
##   drop                         ends a held drag as a release does.
##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
##                                with water, each run `n` times (default 5) on the calling
##                                frame and logged as median / min ms: the terrain (with and
##                                without its water), the wet dressing, the water mesh build,
##                                the water nodes, the flow texture, process_water_meshes and
##                                the grid's ground field. Call it from the title.


static func run(root: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"line":
			return _line(root, step)
		"load_profile":
			return _load_profile(String(step.get("folder", "")), int(step.get("n", 5)))
		"cues":
			return _cues(root.get("_game_map") as GameMap)
		"hold":
			return _hold(
				root.get("_game_map") as GameMap, int(step.get("token", 0)), _vec(step.get("to"))
			)
		"drop":
			var dnd := (root.get("_game_map") as GameMap).drag_and_drop_node as DragAndDrop3D
			dnd.stop_drag()
			dnd.edge_pan_enabled = true
			return "dropped"
	return "unknown action %s" % step.get("action", "")


static func _tokens(gm: GameMap) -> Array[DraggableToken]:
	var out: Array[DraggableToken] = []
	for node in gm.get_tree().get_nodes_in_group("board_tokens"):
		var found := (node as Node).find_children("*", "DraggableToken", true, false)
		if not found.is_empty():
			out.append(found[0] as DraggableToken)
	return out


static func _cues(gm: GameMap) -> String:
	if gm == null:
		return "no game map"
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var out := PackedStringArray()
	for token in _tokens(gm):
		var base: Vector3 = token.water.base_position()
		var height: float = token.cue_box().size.y
		var water := WaterSurface.water_below(space, base, base.y + height + 3.0)
		(
			out
			. append(
				(
					"%s height %.2f base %.2f surface %s cue %s"
					% [
						token.get_parent().name,
						height,
						base.y,
						("%.2f" % water.y) if not water.is_empty() else "-",
						str(token.is_submerged_cue_shown()),
					]
				)
			)
		)
	return " | ".join(out)


static func _hold(gm: GameMap, index: int, to: Vector2) -> String:
	var tokens := _tokens(gm)
	if index >= tokens.size():
		return "no token %d" % index
	var token := tokens[index]
	var dnd := gm.drag_and_drop_node as DragAndDrop3D
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var surface := WaterSurface.surface_below(space, Vector3(to.x, 0, to.y), 50.0)
	var screen := gm.camera_node.unproject_position(surface)
	# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.
	dnd.edge_pan_enabled = false
	dnd.call("_begin_drag", token)
	dnd.call("_update_target_position", screen)
	return "holding %s over %s (screen %s)" % [token.get_parent().name, str(to), str(screen)]


static func _vec(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").
static func _timed(part: Callable, runs: int) -> String:
	var times := PackedFloat64Array()
	for _i in runs:
		var started := Time.get_ticks_usec()
		part.call()
		times.append((Time.get_ticks_usec() - started) / 1000.0)
	times.sort()
	return "%.1f / %.1f ms" % [times[times.size() / 2], times[0]]


static func _load_profile(folder: String, runs: int) -> String:
	var path := LevelManager.folder_path(folder).path_join(Paths.LEVEL_MAP_DOCUMENT_NAME)
	var started := Time.get_ticks_usec()
	var read := MapDocumentIO.read(path)
	var read_ms := (Time.get_ticks_usec() - started) / 1000.0
	var doc: MapDocument = read["document"]
	if doc == null:
		return "cannot read %s" % path
	var out := PackedStringArray(
		["%s: %d bodies, read %.0f ms (worker)" % [folder, doc.water_bodies.size(), read_ms]]
	)
	var root_path := PaletteLibrary.DEFAULT_ROOT
	out.append(
		(
			"terrain %s"
			% _timed(func() -> void: AuthoredTerrain.create(doc, root_path, false).free(), runs)
		)
	)
	out.append("dressing %s" % _timed(func() -> void: WaterDressing.refresh(doc), runs))
	var bodies := doc.water_bodies.duplicate()
	doc.water_bodies.clear()
	out.append(
		(
			"terrain dry %s"
			% _timed(func() -> void: AuthoredTerrain.create(doc, root_path, false).free(), runs)
		)
	)
	doc.water_bodies.assign(bodies)
	WaterDressing.refresh(doc)
	# P4b-0: the workers' share, and the main thread's with their output.
	var prepared := {}
	out.append(
		(
			"workers (AuthoredLoadPrep, wall) %s"
			% _timed(
				func() -> void: prepared.merge(AuthoredLoadPrep.start(doc).finish(), true), runs
			)
		)
	)
	out.append(
		(
			"terrain from prep %s"
			% _timed(
				func() -> void: AuthoredTerrain.create(doc, root_path, false, prepared).free(), runs
			)
		)
	)
	out.append(
		(
			"terrain from prep + chunks %s"
			% _timed(
				func() -> void: AuthoredTerrain.create(doc, root_path, true, prepared).free(), runs
			)
		)
	)
	out.append(
		(
			"terrain + chunks, no prep %s"
			% _timed(func() -> void: AuthoredTerrain.create(doc, root_path, true).free(), runs)
		)
	)
	var water_built: Dictionary = prepared.get(AuthoredLoadPrep.WATER, {})
	out.append(
		(
			"water from prep %s"
			% _timed(func() -> void: AuthoredWater.create(doc, water_built).free(), runs)
		)
	)
	var built := {}
	out.append(
		(
			"mesh build %s"
			% _timed(func() -> void: built.merge(WaterMeshBuilder.build(doc), true), runs)
		)
	)
	var arrays: Array = built.get("arrays", [])
	out.append(
		(
			"mesh arrays %d vertices, %d bodies"
			% [
				(
					(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					if not arrays.is_empty()
					else 0
				),
				(built.get("bodies", []) as Array).size()
			]
		)
	)
	out.append(
		(
			"water nodes %s"
			% _timed(
				func() -> void:
					var water := AuthoredWater.new()
					water.apply(built, doc.water_flow, doc.water_flow_size)
					water.free(),
				runs
			)
		)
	)
	out.append(
		(
			"flow texture %s"
			% _timed(
				func() -> void:
					ImageTexture.create_from_image(
						WaterFlowBaker.to_image(doc.water_flow, doc.water_flow_size)
					),
				runs
			)
		)
	)
	out.append("water create %s" % _timed(func() -> void: AuthoredWater.create(doc).free(), runs))
	out.append(
		(
			"water create + process %s"
			% _timed(
				func() -> void:
					var holder := Node3D.new()
					holder.add_child(AuthoredWater.create(doc))
					WaterGlbUtils.process_water_meshes(holder)
					holder.free(),
				runs
			)
		)
	)
	var root := Node3D.new()
	var terrain := AuthoredTerrain.create(doc, root_path, false)
	root.add_child(terrain)
	root.add_child(AuthoredWater.create(doc))
	out.append(
		(
			"height field %s"
			% _timed(func() -> void: GroundHeightField.from_terrain(terrain).get_texture(), runs)
		)
	)
	# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.
	var whole := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	var parts := {
		"weight planes": func() -> void: terrain.call("_weight_planes", whole),
		"grid fields": func() -> void: TerrainMeshBuilder.grid_fields(doc),
		"collision heights": func() -> void: TerrainMeshBuilder.collision_heights(doc),
		"skirt arrays":
		## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
		##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
		##                                `from` to `to` (map XZ): ground, water level, depth, the wet
		##                                dressing's bed / shore / wet line, and the painted weight of
		##                                `surface` at the nearest sample. For the path-meets-water fix.
		##   cues                         in play: every token's height, base, the water surface over
		##                                it and whether its submerged cue (SubmergedMarker) shows.
		##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
		##                                over map XZ `to` (the drag stays active, the token eases
		##                                there over the next frames), for a capture mid-drag.
		##   drop                         ends a held drag as a release does.
		##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
		##                                with water, each run `n` times (default 5) on the calling
		##                                frame and logged as median / min ms: the terrain (with and
		##                                without its water), the wet dressing, the water mesh build,
		##                                the water nodes, the flow texture, process_water_meshes and
		##                                the grid's ground field. Call it from the title.
		# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.
		## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").
		# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.
		func() -> void:
## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
##                                `from` to `to` (map XZ): ground, water level, depth, the wet
##                                dressing's bed / shore / wet line, and the painted weight of
##                                `surface` at the nearest sample. For the path-meets-water fix.
##   cues                         in play: every token's height, base, the water surface over
##                                it and whether its submerged cue (SubmergedMarker) shows.
##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
##                                over map XZ `to` (the drag stays active, the token eases
##                                there over the next frames), for a capture mid-drag.
##   drop                         ends a held drag as a release does.
##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
##                                with water, each run `n` times (default 5) on the calling
##                                frame and logged as median / min ms: the terrain (with and
##                                without its water), the wet dressing, the water mesh build,
##                                the water nodes, the flow texture, process_water_meshes and
##                                the grid's ground field. Call it from the title.

			# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.

## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").

			# P4b-0: the workers' share, and the main thread's with their output.

			# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.

## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
##                                `from` to `to` (map XZ): ground, water level, depth, the wet
##                                dressing's bed / shore / wet line, and the painted weight of
##                                `surface` at the nearest sample. For the path-meets-water fix.
##   cues                         in play: every token's height, base, the water surface over
##                                it and whether its submerged cue (SubmergedMarker) shows.
##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
##                                over map XZ `to` (the drag stays active, the token eases
##                                there over the next frames), for a capture mid-drag.
##   drop                         ends a held drag as a release does.
##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
##                                with water, each run `n` times (default 5) on the calling
##                                frame and logged as median / min ms: the terrain (with and
##                                without its water), the wet dressing, the water mesh build,
##                                the water nodes, the flow texture, process_water_meshes and
##                                the grid's ground field. Call it from the title.

			# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.

## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").

			# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.

			TerrainMeshBuilder.build_skirt_arrays(
				doc, AuthoredTerrain.skirt_width_m(), AuthoredTerrain.SKIRT_FADE_M
			),
		"height image": func() -> void: TerrainMeshBuilder.height_image(doc),
		"material":
		## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
		##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
		##                                `from` to `to` (map XZ): ground, water level, depth, the wet
		##                                dressing's bed / shore / wet line, and the painted weight of
		##                                `surface` at the nearest sample. For the path-meets-water fix.
		##   cues                         in play: every token's height, base, the water surface over
		##                                it and whether its submerged cue (SubmergedMarker) shows.
		##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
		##                                over map XZ `to` (the drag stays active, the token eases
		##                                there over the next frames), for a capture mid-drag.
		##   drop                         ends a held drag as a release does.
		##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
		##                                with water, each run `n` times (default 5) on the calling
		##                                frame and logged as median / min ms: the terrain (with and
		##                                without its water), the wet dressing, the water mesh build,
		##                                the water nodes, the flow texture, process_water_meshes and
		##                                the grid's ground field. Call it from the title.
		# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.
		## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").
		# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.
		func() -> void:
## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
##                                `from` to `to` (map XZ): ground, water level, depth, the wet
##                                dressing's bed / shore / wet line, and the painted weight of
##                                `surface` at the nearest sample. For the path-meets-water fix.
##   cues                         in play: every token's height, base, the water surface over
##                                it and whether its submerged cue (SubmergedMarker) shows.
##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
##                                over map XZ `to` (the drag stays active, the token eases
##                                there over the next frames), for a capture mid-drag.
##   drop                         ends a held drag as a release does.
##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
##                                with water, each run `n` times (default 5) on the calling
##                                frame and logged as median / min ms: the terrain (with and
##                                without its water), the wet dressing, the water mesh build,
##                                the water nodes, the flow texture, process_water_meshes and
##                                the grid's ground field. Call it from the title.

			# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.

## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").

			# P4b-0: the workers' share, and the main thread's with their output.

			# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.

## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
##                                `from` to `to` (map XZ): ground, water level, depth, the wet
##                                dressing's bed / shore / wet line, and the painted weight of
##                                `surface` at the nearest sample. For the path-meets-water fix.
##   cues                         in play: every token's height, base, the water surface over
##                                it and whether its submerged cue (SubmergedMarker) shows.
##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
##                                over map XZ `to` (the drag stays active, the token eases
##                                there over the next frames), for a capture mid-drag.
##   drop                         ends a held drag as a release does.
##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
##                                with water, each run `n` times (default 5) on the calling
##                                frame and logged as median / min ms: the terrain (with and
##                                without its water), the wet dressing, the water mesh build,
##                                the water nodes, the flow texture, process_water_meshes and
##                                the grid's ground field. Call it from the title.

			# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.

## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").

			# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.

## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
##                                `from` to `to` (map XZ): ground, water level, depth, the wet
##                                dressing's bed / shore / wet line, and the painted weight of
##                                `surface` at the nearest sample. For the path-meets-water fix.
##   cues                         in play: every token's height, base, the water surface over
##                                it and whether its submerged cue (SubmergedMarker) shows.
##   hold {token, to}             in play: picks token i up through DragAndDrop3D and holds it
##                                over map XZ `to` (the drag stays active, the token eases
##                                there over the next frames), for a capture mid-drag.
##   drop                         ends a held drag as a release does.
##   load_profile {folder, n}     the main-thread parts of loading the level's map.ttmap
##                                with water, each run `n` times (default 5) on the calling
##                                frame and logged as median / min ms: the terrain (with and
##                                without its water), the wet dressing, the water mesh build,
##                                the water nodes, the flow texture, process_water_meshes and
##                                the grid's ground field. Call it from the title.

			# Edge pan reads the real OS cursor, which may sit outside the window: off until `drop`.

## Median and minimum of `runs` calls of `part` (usec -> "median / min ms").

			# The dry terrain's own parts (AuthoredTerrain.build), pure ones first.

			GroundPalette.build_ground_material(doc.base_surface, doc.map_seed, root_path),
		"layers (plan, planes, textures)": func() -> void: terrain.call("_build_ground_layers"),
		"collision": func() -> void: terrain.call("update_collision"),
		"skirt": func() -> void: terrain.call("_build_skirt"),
	}
	for part_name: String in parts:
		out.append("  %s %s" % [part_name, _timed(parts[part_name], runs)])
	root.free()
	return "\n".join(out)


static func _line(root: Node, step: Dictionary) -> String:
	var ctrl := root.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.document == null:
		return "no authoring map"
	var doc := ctrl.document
	var from := _vec(step.get("from"))
	var to := _vec(step.get("to"))
	var n := maxi(2, int(step.get("n", 21)))
	var surface := String(step.get("surface", ""))
	var slot := doc.surface_ids.find(surface)
	var levels := WaterGeometry.levels(doc)
	var field := doc.water_dressing
	var lines := PackedStringArray()
	for i in n:
		var p := from.lerp(to, float(i) / float(n - 1))
		var s := doc.world_to_sample(p)
		var near := s.round()
		var at := doc.sample_index(int(near.x), int(near.y))
		var h := WaterGeometry.ground_at(doc, p)
		var level := levels[at]
		var dressing := WaterDressing.sample(field, doc.samples_x(), doc.samples_z(), s)
		var wet_line := 0.0
		if field.size() == doc.sample_count() * WaterDressing.CHANNELS:
			wet_line = field[at * WaterDressing.CHANNELS + 3] / 255.0
		var paint := doc.surface_weight(at, slot) if slot >= 0 else -1
		lines.append(
			(
				"(%.2f, %.2f) h %.3f level %s depth %s bed %.2f shore %.2f wet %.2f %s %d"
				% [
					p.x,
					p.y,
					h,
					"dry" if level == WaterGeometry.DRY else "%.3f" % level,
					"-" if level == WaterGeometry.DRY else "%.3f" % (level - h),
					dressing.x,
					dressing.y,
					wet_line,
					surface,
					paint
				]
			)
		)
	return "\n".join(lines)
