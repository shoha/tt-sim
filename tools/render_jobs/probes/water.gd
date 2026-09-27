extends RefCounted

## Render-job probe (`call` op) for authored water at runtime (phase 4, P4-2). There is no
## Water tool yet (P4-4) nor a channel carve (P4-3), so `build` writes the water straight into
## the open authoring document: a sloped map, a winding river in three flat reaches, a pond
## and a basin, carved crudely by owner (WaterMeshBuilder.sample_owners: each sample's bed is
## its highest body's), then refreshes terrain, plants and water the way an edit does.
## Positions are map XZ metres. step.action:
##   build {slope, depths}       the test map above; depths = the three reaches' classes
##                               (default ["ankle", "waist", "deep"]). Logs bodies, levels,
##                               mesh size and the refresh's worker and swap times.
##   save {folder}               writes the open document and level as user://levels/<folder>
##                               (a test level; the caller deletes it).
##   tokens {points}             in play: spawns one token per point (the first locally cached
##                               asset), each dropped onto the ground as a browser drop does.
##   drag {token, to}            in play: drags token i through DragAndDrop3D to world XZ `to`
##                               (begin, one pointer update at the point's screen position,
##                               stop), then waits for the settle; see `report`.
##   report                      every token: base height, bed, surface, floating, sinking.
##   points {points}             per point: bed (terrain layer), walkable surface, landing, the
##                               grid field's height, the drag resolver's answer.
##   measure {from, to}          camera rays through the two points' screen positions on the
##                               measure tool's mask and on the terrain layer alone, and the
##                               drag ruler's text between them.
##   water {visible}             shows or hides every water mesh (GPU A/B).
##   state                       the water nodes and the grid field.
##   scan {spacing}              over the map's bounds: where a water surface stands over the
##                               bed, its extent, depths, and the points later steps can name
##                               as "found:deep", "found:shallow", "found:dry", "found:across_a"
##                               and "found:across_b" (any point field takes them).
##   look {at}                   pans the camera so the screen centre looks at `at`.

## The `build` map: the river's control line, its reaches' half-widths, the bank width of
## the carve, and the two ponds.
const RIVER := [
	[-28, 3],
	[-22, 8],
	[-15, 9],
	[-8, 4],
	[-2, -1],
	[5, -2],
	[11, 2],
	[17, 5],
	[23, 2],
	[28, -3],
]
const HALF_WIDTHS := [1.8, 2.2, 2.8]
const BANK_M := 1.6
const POND := {"id": 20, "at": [13, -17], "r": 6.0, "depth": "deep"}
const BASIN := {"id": 21, "at": [-17, -14], "r": 4.0, "depth": "waist"}

## Points `scan` found, by name.
static var _found: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	var gm := base.get("_game_map") as GameMap
	match String(step.get("action", "")):
		"scan":
			return _scan(gm, float(step.get("spacing", 1.0)))
		"look":
			var at := _vec(step.get("at"), Vector2.ZERO)
			var cc := gm.get_camera_controller()
			var off: Vector2 = cc.call("_get_view_center_ground_offset")
			var holder := gm.cameraholder_node
			holder.global_position = Vector3(at.x - off.x, holder.global_position.y, at.y - off.y)
			return "look at %s" % str(at)
		"build":
			return _build(base, step)
		"save":
			return _save(base, String(step.get("folder", "_p42_water")))
		"tokens":
			return _spawn(base, step.get("points", []), step.get("assets", []))
		"drag":
			return _drag(gm, int(step.get("token", 0)), _vec(step.get("to"), Vector2.ZERO))
		"report":
			return _report(gm)
		"points":
			return _points(gm, step.get("points", []))
		"measure":
			return _measure(
				gm, _vec(step.get("from"), Vector2.ZERO), _vec(step.get("to"), Vector2.ONE)
			)
		"water":
			return _set_visible(gm, bool(step.get("visible", true)))
		"state":
			return _state(gm)
	return "unknown action %s" % step.get("action", "")


static func _vec(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is String and String(value).begins_with("found:"):
		return _found.get(String(value).trim_prefix("found:"), fallback)
	return fallback


static func _scan(gm: GameMap, spacing: float) -> String:
	var root := _map_root(gm)
	if root == null:
		return "no map"
	var space := root.get_world_3d().direct_space_state
	var bounds := LevelEnvironmentManager.compute_map_bounds(root)
	var top := bounds.end.y + 20.0
	var wet := 0
	var total := 0
	var box := Rect2()
	var deepest := Vector3(0, -INF, 0)
	var shallow := Vector2.INF
	var depths := PackedFloat32Array()
	var x := bounds.position.x + spacing * 0.5
	while x < bounds.end.x:
		var z := bounds.position.z + spacing * 0.5
		while z < bounds.end.z:
			total += 1
			var at := Vector3(x, 0, z)
			var bed := DragPlaceController.raycast_terrain_down(space, at, top)
			var water := WaterSurface.water_below(space, at, top)
			if bed != Vector3.INF and not water.is_empty() and water.y > bed.y:
				var depth: float = water.y - bed.y
				wet += 1
				depths.append(depth)
				box = Rect2(x, z, 0, 0) if wet == 1 else box.expand(Vector2(x, z))
				if depth > deepest.y:
					deepest = Vector3(x, depth, z)
				if depth > 0.3 and depth < 0.6 and shallow == Vector2.INF:
					shallow = Vector2(x, z)
			z += spacing
		x += spacing
	if wet == 0:
		return "no water over %d samples" % total
	depths.sort()
	_found["deep"] = Vector2(deepest.x, deepest.z)
	_found["shallow"] = shallow if shallow != Vector2.INF else Vector2(deepest.x, deepest.z)
	# Across the water at the deepest point, along X or Z, whichever crosses sooner, out to
	# dry ground on both sides.
	var best: Array = []
	for axis in [Vector2(1, 0), Vector2(0, 1)]:
		var ends: Array = []
		for sign_value in [-1.0, 1.0]:
			var d := 0.5
			while d < 30.0:
				var p: Vector2 = Vector2(deepest.x, deepest.z) + axis * d * sign_value
				var at := Vector3(p.x, 0, p.y)
				var bed := DragPlaceController.raycast_terrain_down(space, at, top)
				var water := WaterSurface.water_below(space, at, top)
				if water.is_empty() or bed == Vector3.INF or water.y <= bed.y:
					ends.append(p + axis * 1.5 * sign_value)
					break
				d += 0.5
		if (
			ends.size() == 2
			and (best.is_empty() or (ends[0] as Vector2).distance_to(ends[1]) < best[2])
		):
			best = [ends[0], ends[1], (ends[0] as Vector2).distance_to(ends[1])]
	if not best.is_empty():
		_found["across_a"] = best[0]
		_found["across_b"] = best[1]
		_found["dry"] = (
			(best[0] as Vector2) + ((best[0] as Vector2) - (best[1] as Vector2)).normalized() * 2.0
		)
	return (
		"water over %d of %d samples (%.1f m), extent %s; depth median %.2f p90 %.2f max %.2f | found %s"
		% [
			wet,
			total,
			spacing,
			str(box),
			depths[depths.size() / 2],
			depths[int(depths.size() * 0.9)],
			depths[depths.size() - 1],
			str(_found),
		]
	)


static func _map_root(gm: GameMap) -> Node3D:
	if gm == null or gm.map_container == null:
		return null
	return gm.map_container.get_node_or_null(^"LevelMap") as Node3D


# --- build -----------------------------------------------------------------------------------


static func _depth(name: String) -> WaterBody.Depth:
	var i := WaterBody.DEPTH_NAMES.find(name)
	return (i if i >= 0 else WaterBody.Depth.WAIST) as WaterBody.Depth


static func _build(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var editor := ctrl.editor
	var doc := ctrl.document
	editor.finish_height_work()
	var started := Time.get_ticks_usec()
	var before := doc.heights.duplicate()
	var heights := doc.heights.duplicate()
	var slope := float(step.get("slope", 0.03))
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			heights[doc.sample_index(x, z)] -= slope * p.x
	doc.heights = heights
	# Three reaches of the river over the sloped ground, each flat at its lowest centreline
	# ground less the freeboard (WaterGeometry.reach_level).
	var line := PackedVector2Array()
	for p in RIVER:
		line.append(Vector2(p[0], p[1]))
	var ground := WaterGeometry.ground_along(doc, line)
	var depths: Array = step.get("depths", ["ankle", "waist", "deep"])
	var ranges: Array[Vector2i] = [Vector2i(0, 3), Vector2i(3, 6), Vector2i(6, 9)]
	var bodies: Array[WaterBody] = []
	for r in ranges.size():
		var reach: Vector2i = ranges[r]
		var points := line.slice(reach.x, reach.y + 1)
		var widths := PackedFloat32Array()
		widths.resize(points.size())
		widths.fill(HALF_WIDTHS[r])
		bodies.append(
			WaterBody.river(
				r + 1,
				points,
				widths,
				_depth(String(depths[r])),
				WaterGeometry.reach_level(ground, reach)
			)
		)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for pond in [POND, BASIN]:
		var at := _vec(pond.at, Vector2.ZERO)
		for z in doc.samples_z():
			for x in doc.samples_x():
				if doc.sample_to_world(Vector2(x, z)).distance_to(at) < float(pond.r):
					mask[doc.sample_index(x, z)] = int(pond.id)
	doc.pond_mask = mask
	for pond in [POND, BASIN]:
		var level := WaterGeometry.pond_rim_level(doc, int(pond.id))
		bodies.append(WaterBody.pond(int(pond.id), _depth(String(pond.depth)), level))
	doc.water_bodies = bodies
	# Carve: each sample of a body's area down to its owner's profile.
	var owners := WaterMeshBuilder.sample_owners(doc)
	var courses := {}
	for b in bodies.size():
		if bodies[b].is_river():
			courses[b] = WaterGeometry.river_course(bodies[b])
	heights = doc.heights.duplicate()
	var changed := Rect2i()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			var o := owners[i]
			if o < 0:
				continue
			var body := bodies[o]
			var bed := body.level_m - body.depth_m()
			var top := body.level_m + 0.3
			var p := doc.sample_to_world(Vector2(x, z))
			var t := 0.0
			if body.is_river():
				var course: Array = courses[o]
				var near := WaterGeometry.nearest_on_polyline(course[0], p)
				var half := WaterGeometry.width_at(course[1], int(near.y), near.z)
				t = clampf((near.x - half + 0.6) / BANK_M, 0.0, 1.0)
			else:
				var pond: Dictionary = POND if body.id == int(POND.id) else BASIN
				var r := p.distance_to(_vec(pond.at, Vector2.ZERO))
				t = clampf((r - (float(pond.r) - 2.5)) / 2.5, 0.0, 1.0)
			var target := lerpf(bed, top, t * t * (3.0 - 2.0 * t))
			if target < heights[i]:
				heights[i] = target
				changed = MaskBrush.merge_rect(changed, Rect2i(x, z, 1, 1))
	doc.heights = heights
	var painted := _paint_beds(doc, owners, courses)
	changed = MaskBrush.merge_rect(changed, Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	editor.set("_snap_before", before)
	editor.set("_aligned", DressingGround.aligned_assets(doc.biome_ids, editor.palette_root))
	(editor.get("_snap_start") as Dictionary).clear()
	(editor.get("_prop_start") as Dictionary).clear()
	editor.call("_queue_heights", changed)
	editor.finish_height_work()
	editor.terrain.settle_heights()
	editor.finish_height_work()
	editor.call("_regenerate", changed)
	if painted != "":
		editor.call("_refresh", changed)
	var water := AuthoredWater.refresh_map(editor.map_root, doc)
	water.finish_refresh()
	var mesh := water.get_mesh_instance()
	var arrays := mesh.mesh.surface_get_arrays(0) if mesh else []
	var lines := PackedStringArray()
	for body in bodies:
		lines.append(
			(
				"%s %d %s level %.2f"
				% [
					"river" if body.is_river() else "pond",
					body.id,
					WaterBody.DEPTH_NAMES[body.depth],
					body.level_m
				]
			)
		)
	return (
		(
			"build %.0f ms | %s | mesh %d verts %d tris"
			+ " | worker build %.1f ms bake %.1f ms swap %.1f ms | flow %s | %s"
		)
		% [
			(Time.get_ticks_usec() - started) / 1000.0,
			"; ".join(lines),
			(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if mesh else 0,
			(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if mesh else 0,
			water.last_build_usec / 1000.0,
			water.last_bake_usec / 1000.0,
			water.last_swap_usec / 1000.0,
			str(doc.water_flow_size),
			painted,
		]
	)


## Paints the riverbed surface over the wet beds and mud on the banks just above the water,
## when the palette has them.
static func _paint_beds(doc: MapDocument, owners: PackedInt32Array, _courses: Dictionary) -> String:
	var surfaces := PaletteLibrary.surfaces()
	var out := PackedStringArray()
	var bed_slot := doc.ensure_surface("riverbed") if surfaces.has("riverbed") else -1
	var mud_slot := doc.ensure_surface("mud") if surfaces.has("mud") else -1
	for i in doc.sample_count():
		var o := owners[i]
		if o < 0:
			continue
		var above := doc.heights[i] - doc.water_bodies[o].level_m
		if above < 0.0 and bed_slot >= 0:
			doc.set_surface_weight(i, bed_slot, 255)
		elif above < 0.35 and mud_slot >= 0:
			doc.set_surface_weight(i, mud_slot, roundi(255.0 * (1.0 - above / 0.35)))
	if bed_slot >= 0:
		out.append("riverbed")
	if mud_slot >= 0:
		out.append("mud")
	return ",".join(out)


# --- save --------------------------------------------------------------------------------------


static func _save(base: Node, folder: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not folder.begins_with("_p42_"):
		return "no authoring controller, or not a _p42_ folder"
	var existing := DirAccess.dir_exists_absolute(LevelManager.folder_path(folder))
	if existing:
		return "folder %s exists; not touching it" % folder
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder))
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [folder, str(ok)]


# --- play ----------------------------------------------------------------------------------


static func _asset() -> Array:
	for pack in AssetManager.get_packs():
		var ids: Array = (pack as AssetPack).assets.keys()
		ids.sort()
		for id in ids:
			var path := AssetManager.get_model_path(pack.pack_id, id)
			var local := path != "" and FileAccess.file_exists(path)
			if local or AssetManager.get("cache").has_cached(pack.pack_id, id, "default"):
				return [pack.pack_id, id]
	return []


## One token per point, the assets `assets` ([[pack, id], ...], cycled) or else the first
## locally cached one.
static func _spawn(base: Node, points: Array, assets: Array) -> String:
	var lpc: Node = base.get("_level_play_controller")
	if lpc == null:
		return "not playing"
	if assets.is_empty():
		var found := _asset()
		if found.is_empty():
			return "no cached asset"
		assets = [found]
	var gm := base.get("_game_map") as GameMap
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var out := PackedStringArray()
	for k in points.size():
		var xz := _vec(points[k], Vector2.ZERO)
		var asset: Array = assets[k % assets.size()]
		var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0, xz.y))
		var at := Vector3(xz.x, (hit.y if hit != Vector3.INF else 0.0) + 0.25, xz.y)
		var token: BoardToken = lpc.call(
			"spawn_asset", String(asset[0]), String(asset[1]), "default", at, true
		)
		out.append("%s/%s %s" % [asset[0], asset[1], String(token.name) if token else "failed"])
	return "spawned %s" % ", ".join(out)


static func _tokens(gm: GameMap) -> Array[DraggableToken]:
	var out: Array[DraggableToken] = []
	for node in gm.get_tree().get_nodes_in_group("board_tokens"):
		var found := (node as Node).find_children("*", "DraggableToken", true, false)
		if not found.is_empty():
			out.append(found[0] as DraggableToken)
	return out


static func _drag(gm: GameMap, index: int, to: Vector2) -> String:
	var tokens := _tokens(gm)
	if index >= tokens.size():
		return "no token %d" % index
	var token := tokens[index]
	var dnd := gm.drag_and_drop_node as DragAndDrop3D
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var surface := WaterSurface.surface_below(space, Vector3(to.x, 0, to.y), 50.0)
	var screen := gm.camera_node.unproject_position(surface)
	dnd.call("_begin_drag", token)
	dnd.call("_update_target_position", screen)
	var target: Vector3 = dnd.get("_target_drag_position")
	var ground := dnd.get_target_ground_position()
	token.rigid_body.global_position = target
	dnd.stop_drag()
	return (
		"drag %s to %s: screen %s cursor mask %d, target ground %s, resolver %s"
		% [
			token.get_parent().name,
			str(to),
			str(screen),
			dnd.collisionMask,
			str(ground),
			str(gm.call("_resolve_drag_ground", Vector3(to.x, ground.y, to.y))),
		]
	)


static func _report(gm: GameMap) -> String:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var out := PackedStringArray()
	for token in _tokens(gm):
		var base_at: Vector3 = token.call("_base_position")
		var bed := DragPlaceController.raycast_terrain_down(space, base_at, base_at.y + 3.0)
		var water := WaterSurface.water_below(space, base_at, base_at.y + 3.0)
		(
			out
			. append(
				(
					"%s base %s bed %.2f surface %s floats %s submerged %s bob %s"
					% [
						token.get_parent().name,
						str(base_at.snapped(Vector3.ONE * 0.01)),
						bed.y if bed != Vector3.INF else NAN,
						("%.2f" % water.y) if not water.is_empty() else "-",
						str(WaterSurface.floats_at(space, base_at)),
						str(token.get("_is_submerged")),
						str(token.get("_bob_tween") != null),
					]
				)
			)
		)
	return " | ".join(out)


static func _points(gm: GameMap, points: Array) -> String:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var field := gm.get_grid_ground()
	var out := PackedStringArray()
	for p in points:
		var xz := _vec(p, Vector2.ZERO)
		var at := Vector3(xz.x, 0, xz.y)
		var bed := DragPlaceController.raycast_terrain_down(space, at)
		var surface := WaterSurface.surface_below(space, at, 50.0)
		var landing := WaterSurface.landing_below(space, at, 50.0)
		(
			out
			. append(
				(
					"%s bed %.2f surface %.2f landing %.2f field %s resolver %s"
					% [
						str(xz),
						bed.y,
						surface.y,
						landing.y,
						("%.2f" % field.world_height_at(xz)) if field else "-",
						str(gm.call("_resolve_drag_ground", Vector3(xz.x, surface.y, xz.y))),
					]
				)
			)
		)
	return " | ".join(out)


static func _measure(gm: GameMap, from: Vector2, to: Vector2) -> String:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var cam := gm.camera_node
	var hits := PackedStringArray()
	var surface_y := PackedFloat32Array()
	for xz in [from, to]:
		var surface := WaterSurface.surface_below(space, Vector3(xz.x, 0, xz.y), 50.0)
		var screen := cam.unproject_position(surface)
		var origin := cam.project_ray_origin(screen)
		var end := origin + cam.project_ray_normal(screen) * 200.0
		var ys := PackedStringArray()
		for mask in [MeasureTool.TERRAIN_COLLISION_LAYER, 1]:
			var query := PhysicsRayQueryParameters3D.create(origin, end)
			query.collision_mask = mask
			var hit := space.intersect_ray(query)
			ys.append("%.2f" % (hit.position as Vector3).y if not hit.is_empty() else "miss")
		hits.append("%s: measure %s, terrain only %s" % [str(xz), ys[0], ys[1]])
		surface_y.append(surface.y)
	var text := DragRuler.ruler_text(
		from.distance_to(to), surface_y[1] - surface_y[0], 1.524, 5.0, "ft", true
	)
	return "%s | ruler along the surface: %s" % [" | ".join(hits), text]


static func _set_visible(gm: GameMap, on: bool) -> String:
	var root := _map_root(gm)
	if root == null:
		return "no map"
	var count := 0
	for node in root.find_children("*-water", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = on
		count += 1
	return "%d water meshes visible %s" % [count, str(on)]


static func _state(gm: GameMap) -> String:
	var root := _map_root(gm)
	if root == null:
		return "no map"
	var water := root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	var parts := PackedStringArray()
	if water:
		var zones := 0
		var tiles := 0
		var bodies := 0
		for child in water.get_children():
			if child is WaterZone:
				zones += 1
				tiles += child.get_child_count()
			elif child is StaticBody3D:
				bodies += 1
		parts.append(
			(
				"authored water: mesh %s, %d surface bodies, %d zones (%d tiles), wet samples %d"
				% [str(water.has_water()), bodies, zones, tiles, water.wet.count(1)]
			)
		)
	var meshes := root.find_children("*-water", "MeshInstance3D", true, false)
	for node in meshes:
		var m := node as MeshInstance3D
		(
			parts
			. append(
				(
					"%s flow %s exempt %s aabb %s"
					% [
						m.name,
						str(m.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM)),
						str(m.has_meta(Constants.BOUNDS_EXEMPT_META)),
						str(m.get_aabb()),
					]
				)
			)
		)
	var field := gm.get_grid_ground()
	var tex := field.get_texture() if field else null
	(
		parts
		. append(
			(
				"field %s water %s tex %s format %s | drag mask %d resolver %s"
				% [
					str(field != null),
					str(field.has_water()) if field else "-",
					str(tex.get_size()) if tex else "-",
					str(tex.get_image().get_format()) if tex else "-",
					(gm.drag_and_drop_node as DragAndDrop3D).collisionMask,
					str((gm.drag_and_drop_node as DragAndDrop3D).ground_resolver.is_valid()),
				]
			)
		)
	)
	return " | ".join(parts)
