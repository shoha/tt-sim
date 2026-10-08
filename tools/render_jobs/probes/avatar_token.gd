extends RefCounted

## Render-job probe (`call` op) for avatar tokens (AvatarTokenFactory, the avatar token
## card): spawns preset avatars (AvatarPresets) as real board tokens through
## LevelPlayController.spawn_avatar in play, for jobs/avatar_token_look.json. Positions are
## map XZ metres. `action`:
## - `pair` (`points` [[x, z], ...], `open_points` [[x, z], ...], `presets` [canopy, open]):
##   spawns one avatar at the first of `points` whose shade ray meets a canopy and a second,
##   selected, at the first of `open_points` in sun (turned 30 degrees, to show the figure
##   turns with the token), or when none is in sun (the scatter there changed) at the nearest
##   dry sunny point on rings around the first; logs both tokens' capsule (radius, height),
##   shade and blocker.
## - `look` (`name` a token name, or `names` [a, b] for their midpoint, with `at` [x, z] framed
##   when one is missing; else `index`, -1 the last token, or `between` true, the first two;
##   `height` default 0.8): pans the screen centre onto that point.
## - `hide` (`name`, else `index`; `hidden` default true): set_visible_to_players; logs the
##   figure's hidden_fade.
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
## `pair`'s fallback search for a sunny spot around the canopy token: ring radii (metres) and
## directions (degrees either side of the screen's left and right).
const SUN_RING_MIN_M := 1.5
const SUN_RING_MAX_M := 8.0
const SUN_RING_STEP_M := 0.5
const SUN_RING_STEP_DEG := 15.0
const SUN_RING_SPREAD_STEPS := 4  # so 60 degrees either side


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var lpc: LevelPlayController = base.get("_level_play_controller")
	match String(step.get("action", "report")):
		"pair":
			return _pair(gm, lpc, step)
		"look":
			return _look(gm, step)
		"hide":
			return _hide(gm, step, bool(step.get("hidden", true)))
		"spawn_at":
			return _spawn_at(gm, lpc, step)
		"report":
			return _report(gm)
		"timing":
			return _timing(gm, lpc, step)
		"profile":
			return _profile(int(step.get("count", 30)))
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
		# The scatter under the listed points changes with the palette (a bush or the oak's
		# shadow over all of them), so search rings around the canopy token for sun instead.
		var sunny := _sunny_near(gm, shaded)
		tried.append("ring search %s" % (str(sunny) if sunny != Vector3.INF else "found none"))
		if sunny != Vector3.INF:
			open = _spawn(gm, lpc, int(presets[1]), sunny, 30.0)
	if open == null:
		return (
			"canopy token only: %s (no sunny open point: %s)" % [_describe(under), ", ".join(tried)]
		)
	open.set_highlighted(true)
	return (
		"under canopy: %s (blocker %s); selected, in sun: %s (tried %s)"
		% [_describe(under), _blocker(gm, shaded), _describe(open), ", ".join(tried)]
	)


## The nearest dry ground point in sun on rings (SUN_RING_STEP_M apart, out to
## SUN_RING_MAX_M) around `centre`, or Vector3.INF. Only directions within 60 degrees of the
## screen's left or right are tried, nearest to them first, so the two figures stand
## side by side in the capture rather than one behind the other.
static func _sunny_near(gm: GameMap, centre: Vector3) -> Vector3:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var right := gm.camera_node.global_basis.x
	var right_angle := Vector2(right.x, right.z).angle()
	var offsets: Array[float] = [0.0]
	for k in range(1, SUN_RING_SPREAD_STEPS + 1):
		offsets.append(deg_to_rad(k * SUN_RING_STEP_DEG))
		offsets.append(-deg_to_rad(k * SUN_RING_STEP_DEG))
	var radius := SUN_RING_MIN_M
	while radius <= SUN_RING_MAX_M:
		for offset in offsets:
			for side in [0.0, PI]:
				var angle: float = right_angle + side + offset
				var xz := Vector2(centre.x, centre.z) + Vector2.from_angle(angle) * radius
				var at := _ground(gm, xz)
				if not WaterSurface.water_below(space, at, at.y + 3.0).is_empty():
					continue
				if _blocker(gm, at) == "sun":
					return at
		radius += SUN_RING_STEP_M
	return Vector3.INF


## The avatar token named `name`, or null.
static func _named(gm: GameMap, name: String) -> BoardToken:
	for token in _avatars(gm):
		if token.token_name == name:
			return token
	return null


## Pans so the screen centre looks at a token `height` above its feet, as the driver's
## look_at does for a ground point. The token is the one named `name` (or the midpoint of the
## two in `names`), else `index`; when a named token is missing, `at` (a map XZ ground point,
## say the pond it was dropped into) is framed instead, so the capture still shows the place.
static func _look(gm: GameMap, step: Dictionary) -> String:
	var tokens := _avatars(gm)
	var height := float(step.get("height", 0.8))
	var q: Vector3
	var names: Array = step.get("names", [])
	if step.has("name") or not names.is_empty():
		if names.is_empty():
			names = [step["name"]]
		var sum := Vector3.ZERO
		var found := 0
		for n in names:
			var token := _named(gm, String(n))
			if token != null:
				sum += token.rigid_body.global_position
				found += 1
		if found == names.size():
			q = sum / float(found)
		elif step.has("at"):
			q = _ground(gm, _vec2(step["at"]))
		else:
			return "no avatar named %s" % str(names)
	elif tokens.is_empty():
		return "no avatar tokens"
	elif bool(step.get("between", false)) and tokens.size() >= 2:
		q = (tokens[0].rigid_body.global_position + tokens[1].rigid_body.global_position) * 0.5
	else:
		var index := int(step.get("index", -1))
		if index >= tokens.size():
			return "no avatar %d" % index
		q = tokens[index if index >= 0 else tokens.size() + index].rigid_body.global_position
	q += Vector3.UP * height
	var z := gm.camera_node.global_basis.z
	var g := q - z * (q.y / z.y)
	var off: Vector2 = gm.get_camera_controller().call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(g.x - off.x, holder.global_position.y, g.z - off.y)
	return "look at %s" % str(Vector2(g.x, g.z))


## Hides the token named `name` (else the one at `index`) from players, or shows it again.
static func _hide(gm: GameMap, step: Dictionary, hidden: bool) -> String:
	var token: BoardToken = null
	if step.has("name"):
		token = _named(gm, String(step["name"]))
		if token == null:
			return "no avatar named %s" % step["name"]
	else:
		var tokens := _avatars(gm)
		var index := int(step.get("index", 0))
		if index >= tokens.size():
			return "no avatar %d" % index
		token = tokens[index]
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
		var base_at: Vector3 = drag.water.base_position()
		(
			out
			. append(
				(
					"%s (%s); base %s, floats %s, submerged cue %s"
					% [
						_describe(token),
						_blocker(gm, token.rigid_body.global_position),
						str(base_at.snapped(Vector3.ONE * 0.01)),
						str(WaterSurface.floats_at(space, base_at, 0.05, drag.water_draft())),
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


## Medians over `count` runs, off the board (works from the title screen): a full build
## (AvatarKit.build_figure), the capsule, AvatarTokenFactory.create, and set_recipe on a
## placed token for each kind of change the builder makes (a colour, a face cell, the stance,
## a proportion), each alternating between two values so every call changes something.
static func _profile(count: int) -> String:
	var kit := AvatarTokenFactory.kit()
	var base := AvatarPresets.recipe(0)
	var builds := []
	var capsules := []
	var creates := []
	for k in count:
		var recipe := AvatarPresets.recipe(k % AvatarPresets.PRESETS.size())
		var t0 := Time.get_ticks_usec()
		var figure := kit.build_figure(recipe)
		var t1 := Time.get_ticks_usec()
		AvatarExtent.capsule(kit, figure)
		var t2 := Time.get_ticks_usec()
		var token := AvatarTokenFactory.create(recipe)
		var t3 := Time.get_ticks_usec()
		builds.append((t1 - t0) / 1000.0)
		capsules.append((t2 - t1) / 1000.0)
		creates.append((t3 - t2) / 1000.0)
		figure.free()
		token.free()
	var changes := {
		"colour": func(r: Dictionary, k: int) -> void: r.colours.hair = k % 2 + 3,
		"face": func(r: Dictionary, k: int) -> void: r.face.mouths = k % 2 + 1,
		"stance":
		func(r: Dictionary, k: int) -> void:
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

## Pans so the screen centre looks at a token (or the first two's midpoint) `height` above
## its feet, as the driver's look_at does for a ground point.

			# The token build's parts, apart: the figure alone, its capsule, and the BoardToken.

## Medians over `count` runs, off the board (works from the title screen): a full build
## (AvatarKit.build_figure), the capsule, AvatarTokenFactory.create, and set_recipe on a
## placed token for each kind of change the builder makes (a colour, a face cell, the stance,
## a proportion), each alternating between two values so every call changes something.

			r.stance = "stance_heroic" if k % 2 == 0 else "stance_relaxed",
		"proportion":
		func(r: Dictionary, k: int) -> void: r.proportions.height = 0.3 + 0.4 * (k % 2),
		"colour_new":
		func(r: Dictionary, k: int) -> void:
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

## Pans so the screen centre looks at a token (or the first two's midpoint) `height` above
## its feet, as the driver's look_at does for a ground point.

			# The token build's parts, apart: the figure alone, its capsule, and the BoardToken.

## Medians over `count` runs, off the board (works from the title screen): a full build
## (AvatarKit.build_figure), the capsule, AvatarTokenFactory.create, and set_recipe on a
## placed token for each kind of change the builder makes (a colour, a face cell, the stance,
## a proportion), each alternating between two values so every call changes something.

			# Values not seen before (cache misses): a slider dragged through new colours and
			# new heights.

			r.colours.primary = k % 12
			r.colours.secondary = (k * 5 + 1) % 12
			r.colours.hair = k % 9,
		"face_new":
		func(r: Dictionary, k: int) -> void:
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

## Pans so the screen centre looks at a token (or the first two's midpoint) `height` above
## its feet, as the driver's look_at does for a ground point.

			# The token build's parts, apart: the figure alone, its capsule, and the BoardToken.

## Medians over `count` runs, off the board (works from the title screen): a full build
## (AvatarKit.build_figure), the capsule, AvatarTokenFactory.create, and set_recipe on a
## placed token for each kind of change the builder makes (a colour, a face cell, the stance,
## a proportion), each alternating between two values so every call changes something.

			# Values not seen before (cache misses): a slider dragged through new colours and
			# new heights.

			r.face.mouths = k % 5
			r.face.eyes = k % 7,
		"proportion_new":
		func(r: Dictionary, k: int) -> void: r.proportions.height = 0.2 + 0.015 * k,
	}
	var colds := []
	for k in count:
		kit.cache.clear()
		var t0 := Time.get_ticks_usec()
		kit.build_figure(AvatarPresets.recipe(k % AvatarPresets.PRESETS.size())).free()
		colds.append((Time.get_ticks_usec() - t0) / 1000.0)
	var out := PackedStringArray()
	out.append(
		(
			"build_figure %.3f ms (cold cache %.3f ms), capsule %.3f ms, create %.3f ms"
			% [_median(builds), _median(colds), _median(capsules), _median(creates)]
		)
	)
	# set_recipe's parts on a placed token, apart.
	var probe_token := AvatarTokenFactory.create(base)
	var view := AvatarTokenFactory.view_of(probe_token)
	var parts := {"build": [], "set_figure": [], "capsule_shape": []}
	for k in count:
		var t0 := Time.get_ticks_usec()
		var figure := kit.build_figure(AvatarPresets.recipe(k % 6))
		var t1 := Time.get_ticks_usec()
		view.set_figure(figure)
		var t2 := Time.get_ticks_usec()
		AvatarExtent.capsule_shape(0.3, 1.6)
		var t3 := Time.get_ticks_usec()
		parts.build.append((t1 - t0) / 1000.0)
		parts.set_figure.append((t2 - t1) / 1000.0)
		parts.capsule_shape.append((t3 - t2) / 1000.0)
	probe_token.free()
	for key in parts:
		out.append("%s %.3f ms" % [key, _median(parts[key])])
	for kind in changes:
		var token := AvatarTokenFactory.create(base)
		var times := []
		for k in count:
			var recipe := base.duplicate(true)
			(changes[kind] as Callable).call(recipe, k)
			var t0 := Time.get_ticks_usec()
			AvatarTokenFactory.set_recipe(token, recipe)
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
		token.free()
		out.append("set_recipe %s %.3f ms" % [kind, _median(times)])
	return "profile (%d runs, medians): %s" % [count, "; ".join(out)]


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
