extends RefCounted

## Render-job probe (`call` op) for the avatar builder (AvatarBuilder, the builder polish
## card), for jobs/avatar_builder_look.json. In play, `action`:
## - `window` (`size` [w, h]): resizes the game window (the builder fits itself to it).
## - `open` (`preset`, default 1): opens the builder for a new avatar on that AvatarPresets
##   recipe, as the Add Token browser's Avatar tab does.
## - `pane` (`id`): selects a rail pane (pose, face, colours, shape, parts).
## - `report`: the panel, preview and pane sizes, the preview's measured bounds and view, the
##   stance tiles' sizes.
## - `timing` (`count`, default 30): medians of the preview's set_recipe for a colour, a face
##   and a stance change (the stance one includes the framing measure), and of the face
##   icons' repaint for a skin and a face change.
## - `close`: cancels the builder.
## - `spawn` (`at` [x, z], `preset`): stands that preset as a board token at `at` turned to
##   face the camera, for an in-game close capture of the same recipe (avatar_token.gd
##   `look` pans to it).

const BUILDER_NAME := "AvatarBuilder"


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "report")):
		"window":
			var s: Array = step.get("size", [1438, 1221])
			base.get_window().size = Vector2i(int(s[0]), int(s[1]))
			return "window %s" % str(base.get_window().size)
		"open":
			var index := int(step.get("preset", 1)) % AvatarPresets.PRESETS.size()
			var builder := AvatarBuilder.open_for_new(
				base.get_tree().root,
				AvatarPresets.recipe(index),
				String(AvatarPresets.PRESETS[index].name)
			)
			return "opened %s on %s" % [builder.name, AvatarPresets.PRESETS[index].name]
		"pane":
			var builder := _builder(base)
			if builder == null:
				return "no builder"
			builder._rail.select(StringName(String(step.get("id", "pose"))))
			return "pane %s" % step.get("id", "pose")
		"report":
			return _report(base)
		"timing":
			return _timing(base, int(step.get("count", 30)))
		"close":
			var builder := _builder(base)
			if builder == null:
				return "no builder"
			builder.cancel()
			return "closed"
		"spawn":
			return _spawn(base, step)
	return "unknown action %s" % step.get("action", "")


static func _builder(base: Node) -> AvatarBuilder:
	for node in base.get_tree().root.get_children():
		if node is AvatarBuilder and not node.is_queued_for_deletion():
			return node as AvatarBuilder
	return null


static func _report(base: Node) -> String:
	var builder := _builder(base)
	if builder == null:
		return "no builder"
	var preview := builder._preview
	var view := preview.view_at(1.0 if preview.face_view else 0.0)
	var b := preview.bounds
	var tiles := PackedStringArray()
	if builder._stance_tiles != null:
		for id in builder._stance_tiles._tiles:
			var tile: Button = builder._stance_tiles._tiles[id]
			tiles.append(
				"%s %s icon %d" % [id, str(tile.size), tile.get_theme_constant("icon_max_width")]
			)
	return (
		(
			"window %s; panel %s; preview %s; pane %s; bounds bottom %.3f top %.3f reach %.3f"
			+ " head %s; view size %.3f focus %s pitch %.1f; stance tiles %s"
		)
		% [
			str(base.get_window().size),
			str(builder.panel.size),
			str(preview.size),
			str(builder.pane_slot.size),
			float(b.get("bottom", 0.0)),
			float(b.get("top", 0.0)),
			float(b.get("reach", 0.0)),
			str(b.get("head", AABB())),
			float(view.size),
			str(view.focus),
			float(view.pitch),
			", ".join(tiles),
		]
	)


static func _median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2] if not values.is_empty() else 0.0


static func _timing(base: Node, count: int) -> String:
	var builder := _builder(base)
	if builder == null:
		return "no builder"
	var preview := builder._preview
	var kit := AvatarTokenFactory.kit()
	var start := builder.recipe.duplicate(true)
	var stances := kit.stance_names()
	var times := {"colour": [], "face": [], "stance": [], "icons_skin": [], "icons_face": []}
	for i in count:
		var next := start.duplicate(true)
		next.colours["primary"] = i % 6
		var t0 := Time.get_ticks_usec()
		preview.set_recipe(next)
		times.colour.append((Time.get_ticks_usec() - t0) / 1000.0)
		next.face["eyes"] = i % 5
		t0 = Time.get_ticks_usec()
		preview.set_recipe(next)
		times.face.append((Time.get_ticks_usec() - t0) / 1000.0)
		next.stance = stances[i % stances.size()]
		t0 = Time.get_ticks_usec()
		preview.set_recipe(next)
		times.stance.append((Time.get_ticks_usec() - t0) / 1000.0)
		var skin := AvatarFaceIcons.skin_colour(kit, {"colours": {"skin": i % 4}})
		t0 = Time.get_ticks_usec()
		builder._face_icons.update(skin, next.face)
		times.icons_skin.append((Time.get_ticks_usec() - t0) / 1000.0)
		var face: Dictionary = next.face.duplicate()
		face["mouths"] = (i + 1) % 4
		t0 = Time.get_ticks_usec()
		builder._face_icons.update(skin, face)
		times.icons_face.append((Time.get_ticks_usec() - t0) / 1000.0)
	preview.set_recipe(builder.recipe)
	builder._face_icons.update(
		AvatarFaceIcons.skin_colour(kit, builder.recipe), builder.recipe.face
	)
	return (
		"medians over %d (ms): colour %.3f, face %.3f, stance %.3f, icons skin %.3f, icons face %.3f"
		% [
			count,
			_median(times.colour),
			_median(times.face),
			_median(times.stance),
			_median(times.icons_skin),
			_median(times.icons_face),
		]
	)


static func _spawn(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var lpc: LevelPlayController = base.get("_level_play_controller")
	if lpc == null:
		return "not playing"
	var a: Array = step.get("at", [0, 0])
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(float(a[0]), 0, float(a[1])))
	var at := Vector3(float(a[0]), hit.y if hit != Vector3.INF else 0.0, float(a[1]))
	var index := int(step.get("preset", 1)) % AvatarPresets.PRESETS.size()
	var token := lpc.spawn_avatar(
		AvatarPresets.recipe(index), String(AvatarPresets.PRESETS[index].name), at
	)
	if token == null:
		return "spawn failed"
	var yaw := AvatarBuilderPreview.FACING_RAD
	token.set_transform_immediate(at, Vector3(0, yaw, 0), Vector3.ONE)
	token.transform_changed.emit()
	return "spawned %s at %s facing the camera" % [token.token_name, str(at)]
