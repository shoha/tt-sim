extends RefCounted

## Render-job probe (`call` op) for avatar tokens (AvatarTokenFactory, the avatar token
## card): spawns preset avatars (AvatarPresets) as real board tokens through
## LevelPlayController.spawn_avatar in play, for jobs/avatar_token_look.json. Positions are
## map XZ metres. `action`:
## - `pair` (`points` [[x, z], ...], `open_points` [[x, z], ...], `presets` [canopy, open]):
##   spawns one avatar at the first of `points` whose shade ray meets a canopy and a second,
##   selected, at the first of `open_points` in sun (turned 30 degrees, to show the figure
##   turns with the token); logs both tokens' capsule (radius, height), shade and blocker.
## - `look` (`index`, -1 the last token; `height` default 0.8; `between` true: the midpoint
##   of the first two): pans the screen centre onto that point.
## - `hide` (`index`, `hidden` default true): set_visible_to_players; logs the figure's
##   hidden_fade.
## - `spawn_at` (`at`, `preset`): one avatar dropped onto whatever is under `at` (the
##   browser's settle), for the submerged cue; `report` then says what it shows.
## - `report`: every avatar token's base, capsule, shade, submerged cue and float state, and
##   the occlusion fade's published entries (centre, radius) for them.
## - `timing` (`count` default 15, `at`): times `count` avatar spawns (AvatarTokenFactory
##   .create plus adding to the board) and, for each, the shade ray walking the map
##   (AvatarShade without a cache, the old path) and through the map's AvatarShadeCache;
##   logs the medians, the cache's build time and crown count, then removes those tokens.
## - `save` (`folder`, `replace`): writes the open authoring map as an `_avatartoken_` level.
## - `cleanup`: deletes every `_avatartoken_*` level folder.

const PREFIX := "_avatartoken_"
const SUN_NAME := "LevelSunLight"


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var lpc: LevelPlayController = base.get("_level_play_controller")
	match String(step.get("action", "report")):
		"pair":
			return _pair(gm, lpc, step)
		"look":
			return _look(gm, step)
		"hide":
			return _hide(gm, int(step.get("index", 0)), bool(step.get("hidden", true)))
		"spawn_at":
			return _spawn_at(gm, lpc, step)
		"report":
			return _report(gm)
		"timing":
			return _timing(gm, lpc, step)
		"save":
			return _save(base, step)
		"cleanup":
			return _cleanup()
	return "unknown action %s" % step.get("action", "")


static func _avatars(gm: GameMap) -> Array[BoardToken]:
	var out: Array[BoardToken] = []
	for node in gm.drag_and_drop_node.get_children():
		if node is BoardToken and (node as BoardToken).is_avatar():
			if not (node as BoardToken).is_queued_for_deletion():
				out.append(node as BoardToken)
	return out


static func _ground(gm: GameMap, xz: Vector2) -> Vector3:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0, xz.y))
	return Vector3(xz.x, hit.y if hit != Vector3.INF else 0.0, xz.y)


static func _sun(gm: GameMap) -> DirectionalLight3D:
	return gm.world_viewport.get_node_or_null(SUN_NAME) as DirectionalLight3D


static func _blocker(gm: GameMap, at: Vector3) -> String:
	var sun := _sun(gm)
	if sun == null:
		return "no sun"
	var hit := AvatarShade.blocker(gm.map_container, at, sun.global_basis.z)
	return "sun" if hit.is_empty() else hit


static func _spawn(
	_gm: GameMap, lpc: LevelPlayController, preset: int, at: Vector3, yaw_deg: float
) -> BoardToken:
	var index := preset % AvatarPresets.PRESETS.size()
	var token := lpc.spawn_avatar(
		AvatarPresets.recipe(index), String(AvatarPresets.PRESETS[index].name), at
	)
	if token != null and yaw_deg != 0.0:
		token.set_transform_immediate(at, Vector3(0, deg_to_rad(yaw_deg), 0), Vector3.ONE)
		token.transform_changed.emit()
	return token


static func _describe(token: BoardToken) -> String:
	var view := AvatarTokenFactory.view_of(token)
	var box := AABB()
	for child in token.rigid_body.get_children():
		if child is CollisionShape3D:
			box = (child as CollisionShape3D).shape.get_debug_mesh().get_aabb()
	return (
		"%s at %s: capsule radius %.3f height %.3f, shade %.1f, yaw %.0f"
		% [
			token.token_name,
			str(token.rigid_body.global_position.snapped(Vector3.ONE * 0.01)),
			maxf(box.size.x, box.size.z) * 0.5,
			box.size.y,
			view.shade if view else -1.0,
			rad_to_deg(token.rigid_body.global_rotation.y),
		]
	)


static func _pair(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var presets: Array = step.get("presets", [1, 0])
	var points: Array = step.get("points", [[0, 0]])
	var tried := PackedStringArray()
	var shaded := Vector3.INF
	for p in points:
		var at := _ground(gm, _vec2(p))
		var why := _blocker(gm, at)
		tried.append("%s %s" % [str(Vector2(at.x, at.z)), why])
		if why != "sun" and why != "no sun" and why != "ground":
			shaded = at
			break
	if shaded == Vector3.INF:
		return "no canopy point among %s" % ", ".join(tried)
	var under := _spawn(gm, lpc, int(presets[0]), shaded, 8.0)
	var open: BoardToken = null
	for p in step.get("open_points", []):
		var at := _ground(gm, _vec2(p))
		var why := _blocker(gm, at)
		tried.append("open %s %s" % [str(_vec2(p)), why])
		if why == "sun":
			open = _spawn(gm, lpc, int(presets[1]), at, 30.0)
			break
	if open == null:
		return (
			"canopy token only: %s (no sunny open point: %s)" % [_describe(under), ", ".join(tried)]
		)
	open.set_highlighted(true)
	return (
		"under canopy: %s (blocker %s); selected, in sun: %s (tried %s)"
		% [_describe(under), _blocker(gm, shaded), _describe(open), ", ".join(tried)]
	)


## Pans so the screen centre looks at a token (or the first two's midpoint) `height` above
## its feet, as the driver's look_at does for a ground point.
static func _look(gm: GameMap, step: Dictionary) -> String:
	var tokens := _avatars(gm)
	if tokens.is_empty():
		return "no avatar tokens"
	var height := float(step.get("height", 0.8))
	var q: Vector3
	if bool(step.get("between", false)) and tokens.size() >= 2:
		q = (tokens[0].rigid_body.global_position + tokens[1].rigid_body.global_position) * 0.5
	else:
		var index := int(step.get("index", -1))
		q = tokens[index if index >= 0 else tokens.size() + index].rigid_body.global_position
	q += Vector3.UP * height
	var z := gm.camera_node.global_basis.z
	var g := q - z * (q.y / z.y)
	var off: Vector2 = gm.get_camera_controller().call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(g.x - off.x, holder.global_position.y, g.z - off.y)
	return "look at %s" % str(Vector2(g.x, g.z))


static func _hide(gm: GameMap, index: int, hidden: bool) -> String:
	var tokens := _avatars(gm)
	if index >= tokens.size():
		return "no avatar %d" % index
	var token := tokens[index]
	token.set_visible_to_players(not hidden)
	var figure := AvatarTokenFactory.view_of(token).figure
	var fades := PackedStringArray()
	for mi in AvatarKit.figure_parts(figure):
		fades.append("%s %s" % [mi.name, str(mi.get_instance_shader_parameter("hidden_fade"))])
	return (
		"%s visible_to_players %s: hidden_fade %s"
		% [token.token_name, str(not hidden), ", ".join(fades)]
	)


static func _spawn_at(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var xz := _vec2(step.get("at", [0, 0]))
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var surface := WaterSurface.surface_below(space, Vector3(xz.x, 0, xz.y), 50.0)
	var at := surface + Vector3(0, DragPlaceController.PLACE_CLEARANCE, 0)
	var index := int(step.get("preset", 2)) % AvatarPresets.PRESETS.size()
	var token := lpc.spawn_avatar(
		AvatarPresets.recipe(index), String(AvatarPresets.PRESETS[index].name), at, true
	)
	return "spawned %s over %s" % [token.token_name if token else "nothing", str(surface)]


static func _report(gm: GameMap) -> String:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var out := PackedStringArray()
	for token in _avatars(gm):
		var drag := token.get_dragging_object()
		var base_at: Vector3 = drag.call("_base_position")
		(
			out
			. append(
				(
					"%s (%s); base %s, floats %s, submerged cue %s"
					% [
						_describe(token),
						_blocker(gm, token.rigid_body.global_position),
						str(base_at.snapped(Vector3.ONE * 0.01)),
						str(WaterSurface.floats_at(space, base_at)),
						str(drag.is_submerged_cue_shown()),
					]
				)
			)
		)
	var fade := gm.occlusion_fade
	var entries: Variant = fade.get("_last_entries") if fade else null
	return "%s | occlusion entries %s" % [" | ".join(out), str(entries)]


static func _median(values: Array) -> float:
	if values.is_empty():
		return NAN
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


static func _timing(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var count := int(step.get("count", 15))
	var at := _vec2(step.get("at", [0, 0]))
	var sun := _sun(gm)
	AvatarShadeCache.clear()
	var cache := AvatarShadeCache.for_map(gm.map_container)
	var builds := []
	var walks := []
	var cached := []
	var spawned: Array[BoardToken] = []
	var agree := 0
	for k in count:
		var xz := at + Vector2((k % 5) * 1.5, (k / 5) * 1.5)
		var t0 := Time.get_ticks_usec()
		var token := _spawn(gm, lpc, k, _ground(gm, xz), 0.0)
		var t1 := Time.get_ticks_usec()
		var figure := AvatarTokenFactory.view_of(token).figure
		var a := AvatarKit.update_shade(figure, gm.map_container, sun)
		var t2 := Time.get_ticks_usec()
		var b := AvatarKit.update_shade(figure, gm.map_container, sun, cache)
		var t3 := Time.get_ticks_usec()
		builds.append((t1 - t0) / 1000.0)
		walks.append((t2 - t1) / 1000.0)
		cached.append((t3 - t2) / 1000.0)
		agree += 1 if a == b else 0
		spawned.append(token)
	for token in spawned:
		lpc.remove_token(token)
	# The token build's parts, apart: the figure alone, its capsule, and the BoardToken.
	var kit := AvatarTokenFactory.kit()
	var figures := []
	var capsules := []
	var tokens := []
	for k in count:
		var recipe := AvatarPresets.recipe(k % AvatarPresets.PRESETS.size())
		var t0 := Time.get_ticks_usec()
		var figure := kit.build_figure(recipe)
		var t1 := Time.get_ticks_usec()
		AvatarExtent.capsule(kit, figure)
		var t2 := Time.get_ticks_usec()
		var token := AvatarTokenFactory.create(recipe)
		var t3 := Time.get_ticks_usec()
		figures.append((t1 - t0) / 1000.0)
		capsules.append((t2 - t1) / 1000.0)
		tokens.append((t3 - t2) / 1000.0)
		figure.free()
		token.free()
	var build := _median(builds)
	return (
		(
			"timing %d spawns: token build median %.2f ms; shade walk median %.3f ms, cached %.3f"
			+ " ms (agree %d/%d); spawn before %.2f ms, after %.2f ms; cache build %.1f ms,"
			+ " %d crowns; parts: build_figure %.2f ms, capsule %.2f ms, create (off the"
			+ " board) %.2f ms"
		)
		% [
			count,
			build,
			_median(walks),
			_median(cached),
			agree,
			count,
			build + _median(walks),
			build + _median(cached),
			cache.build_ms,
			cache.crown_count,
			_median(figures),
			_median(capsules),
			_median(tokens),
		]
	)


static func _vec2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


# --- test level ------------------------------------------------------------------------------


static func _save(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var folder := String(step.get("folder", PREFIX + "forest"))
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path) and not bool(step.get("replace", false)):
		return "folder %s exists; not touching it (replace: true overwrites)" % folder
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [folder, str(ok)]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
