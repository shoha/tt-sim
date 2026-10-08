extends RefCounted

## Render-job probe (`call` op) for the avatar kit consumer (AvatarKit, 2026-10-06): places
## figures assembled from figurine's kit (res://assets/avatar_kit) on the open map, for the
## look and perf runs of jobs/avatar_kit_look.json. Positions are map XZ metres; figures
## stand on the layer-1 ground under them. `action`:
## - `place` (`at` [x, z], `spacing` default 0.95): clears the figures and stands figurine's
##   three judging recipes (RECIPES, from figurine/scripts/render_figures.py) in a row along
##   the screen's right axis centred on `at`, turned 8, -14 and 4 degrees from facing +Z as
##   figurine's renders are (the camera sees them three-quarter), each with its shade ray;
##   `builds` [b0, b1, b2] overrides each recipe's build (the plus-size range).
## - `canopy` (`points` [[x, z], ...], `recipe` index): adds one figure at the first point
##   whose shade ray meets a canopy (or the last point), and logs every point's shade.
## - `spawn` (`config` "<anything>_<count>", `at`, `spacing`): clears and places `count`
##   figures in a staggered grid cycling the three recipes, for frame times; logs the time
##   and the triangles per figure. `extra` [part id, ...] adds a copy of each named part's
##   mesh to every figure, bound to its skeleton: the triangle-budget multiplier.
## - `shade`: re-takes every figure's shade ray and logs the values.
## - `look` (`index`, -1 the last figure; `height` default 0.78): pans so the screen centre
##   looks at that figure `height` metres above its feet.
## - `hidden` (`index`, `fade` default 0.5): the figure's hidden_fade (the GM's view).
## - `params` (`params` {uniform: value}): sets material uniforms on every figure part;
##   arrays of three become colours. Logs the old values.
## - `variant` (`name`): sets one of the VARIANTS look sets (laid over the shipped values)
##   on every figure part, for the figure lighting comparisons.
## - `near` (`points`, `recipe`, `yaw`): adds one figure at the first point in sun (the
##   figure in open sun beside foliage), and logs every point's shade.
## - `add` (`at`, `recipe`, `yaw`): adds one figure there, keeping the others.
## - `info`: triangles per part and figure, and the kit's load errors.
## - `env` (`ambient` [r, g, b] optional, sets figure_ambient directly): the live
##   environment's ambient colour and energy (figure_ambient), tonemap and sun.
## - `sun` (`visible`): shows or hides the level sun (a dungeon-like light: ambient only).
## - `mipmaps` (`on`): AvatarKit.detail_mipmaps for figures placed after it (an A/B of the
##   detail textures with and without the mipmaps AvatarKit builds).
## - `clear`: removes the figures.
## - `save` (`folder`, `replace`): writes the open authoring map as an `_avatarkit_` level.
## - `cleanup` (`folder` optional): deletes every `_avatarkit_*` level folder, or only that one.

const HOLDER := "AvatarKitProbe"
const PREFIX := "_avatarkit_"
const YAWS_DEG := [8.0, -14.0, 4.0]
## As figurine's wardrobe home render (card B2b): the first in the skater skirt, the second in
## the long-sleeved top, the third in the whole outfit (top, skirt and witch hat).
const RECIPES := [
	{
		"format": 1,
		"parts":
		{"body": "body_a", "head": "head_round", "hair": "hair_bun", "bottom": "skirt_skater"},
		"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
		"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
		"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
		"stance": "stance_ready",
	},
	{
		"format": 1,
		"parts":
		{"body": "body_a", "head": "head_round", "hair": "hair_bun", "top": "top_longsleeve"},
		"colours": {"skin": 0, "hair": 2, "eyes": 1, "primary": 3, "secondary": 5, "accent": 4},
		"face": {"eyes": 3, "brows": 2, "mouths": 1, "marks": 1},
		"proportions": {"height": 0.15, "build": 0.3, "head": 0.85},
		"stance": "stance_relaxed",
	},
	{
		"format": 1,
		"parts":
		{
			"body": "body_a",
			"head": "head_round",
			"hair": "hair_bun",
			"top": "top_longsleeve",
			"bottom": "skirt_skater",
			"hat": "hat_witch",
		},
		"colours": {"skin": 3, "hair": 3, "eyes": 2, "primary": 10, "secondary": 6, "accent": 0},
		"face": {"eyes": 4, "brows": 0, "mouths": 4, "marks": 2},
		"proportions": {"height": 0.9, "build": 0.75, "head": 0.3},
		"stance": "stance_heroic",
	},
]

## Figure lighting look sets (`variant`): "before" restores the shader's values before the
## world-lighting pass (2026-10-07), "after" the shipped ones. That pass also probed the sun's
## shadow map per pixel (its dot pattern on sunlit paint ruled it out; avatar_figure.gdshader).
const NEUTRAL := "after"
const VARIANTS := {
	"after":
	{
		"emission_drop": 0.8,
		"light_strength": 1.0,
		"light_wrap": 0.25,
		"ambient_fill": 0.0,
		"ambient_mix": 0.8,
		"ambient_hue_mix": 0.35,
		"ambient_floor": 0.2,
		"shadow_strength": 1.0,
		"shade_drop": 0.35,
		"paint_contrast": 1.15,
		"paint_saturation": 1.1,
		"light_floor": 1.0,
		"face_light": 0.5,
		"scene_ambient": 1.0,
	},
	"before":
	{
		"emission_drop": 0.55,
		"light_strength": 0.9,
		"light_wrap": 0.3,
		"ambient_fill": 0.4,
		"ambient_mix": 0.8,
		"ambient_hue_mix": 0.35,
		"ambient_floor": 0.2,
		"shadow_strength": 0.85,
		"shade_drop": 0.35,
		"paint_contrast": 1.25,
		"paint_saturation": 1.1,
		"light_floor": 0.0,
		"face_light": 0.0,
		"scene_ambient": 0.0,
	},
}

static var _kit: AvatarKit = null


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	match String(step.get("action", "info")):
		"place":
			return _place(
				base,
				gm,
				_vec2(step.get("at", [0, 0])),
				float(step.get("spacing", 0.95)),
				step.get("builds", [])
			)
		"canopy":
			return _canopy(base, gm, step)
		"spawn":
			var parts := String(step.get("config", "x_8")).split("_")
			var count := int(parts[parts.size() - 1])
			var at := _vec2(step.get("at", [0, 0]))
			return _spawn(
				base, gm, count, at, float(step.get("spacing", 1.5)), step.get("extra", [])
			)
		"shade":
			return _shade_all(base, gm)
		"look":
			return _look(gm, int(step.get("index", -1)), float(step.get("height", 0.78)))
		"hidden":
			return _hidden(gm, int(step.get("index", 0)), float(step.get("fade", 0.5)))
		"params":
			return _params(gm, step.get("params", {}))
		"variant":
			var variant := String(step.get("name", NEUTRAL))
			var values: Dictionary = (VARIANTS[NEUTRAL] as Dictionary).duplicate()
			values.merge(VARIANTS.get(variant, {}), true)
			return "%s: %s" % [variant, _params(gm, values)]
		"near":
			return _near(base, gm, step)
		"add":
			var fig := _add(
				base,
				gm,
				_holder(gm, false),
				int(step.get("recipe", 0)),
				_vec2(step.get("at", [0, 0])),
				deg_to_rad(float(step.get("yaw", 8.0)))
			)
			return (
				"added at %s: %s" % [str(fig.global_position), _why(base, gm, fig.global_position)]
			)
		"info":
			return _info()
		"sun":
			var sun := _sun(base)
			if sun == null:
				return "no sun"
			sun.visible = bool(step.get("visible", true))
			return "sun visible %s" % str(sun.visible)
		"env":
			if step.has("ambient"):
				var a: Array = step.ambient
				RenderingServer.global_shader_parameter_set(
					"figure_ambient", Vector3(float(a[0]), float(a[1]), float(a[2]))
				)
			return _env(base)
		"mipmaps":
			AvatarKit.detail_mipmaps = bool(step.get("on", true))
			_kit = null
			return (
				"detail mipmaps %s (kit reloads on the next placement)"
				% str(AvatarKit.detail_mipmaps)
			)
		"clear":
			_clear(gm)
			return "cleared"
		"save":
			return _save(base, step)
		"cleanup":
			return _cleanup(step)
	return "unknown action %s" % step.get("action", "")


static func _ensure() -> AvatarKit:
	if _kit == null:
		_kit = AvatarKit.load_kit()
	return _kit


static func _sun(base: Node) -> DirectionalLight3D:
	var found := base.get_tree().root.find_children(
		"LevelSunLight", "DirectionalLight3D", true, false
	)
	return found[0] as DirectionalLight3D if not found.is_empty() else null


static func _ground(gm: GameMap, xz: Vector2) -> Vector3:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0, xz.y))
	return Vector3(xz.x, hit.y if hit != Vector3.INF else 0.0, xz.y)


static func _clear(gm: GameMap) -> void:
	var old := gm.map_container.get_node_or_null(HOLDER)
	if old:
		old.name = HOLDER + "_old"
		old.queue_free()


static func _holder(gm: GameMap, fresh: bool) -> Node3D:
	if fresh:
		_clear(gm)
	var holder := gm.map_container.get_node_or_null(HOLDER) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = HOLDER
		gm.map_container.add_child(holder)
	return holder


static func _figures(gm: GameMap) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var holder := gm.map_container.get_node_or_null(HOLDER)
	if holder != null:
		for child in holder.get_children():
			out.append(child as Node3D)
	return out


## One figure of recipe `index` at a ground point, turned `yaw` radians, with its shade ray.
static func _add(
	base: Node,
	gm: GameMap,
	holder: Node3D,
	index: int,
	xz: Vector2,
	yaw: float,
	build: float = -1.0,
	extra: Array = []
) -> Node3D:
	var recipe: Dictionary = (RECIPES[index % RECIPES.size()] as Dictionary).duplicate(true)
	if build >= 0.0:
		recipe.proportions.build = build
	var fig := _ensure().build_figure(recipe)
	_add_copies(fig, extra)
	holder.add_child(fig)
	fig.global_position = _ground(gm, xz)
	fig.rotation.y = yaw
	AvatarKit.update_shade(fig, gm.map_container, _sun(base))
	return fig


## The budget multiplier: extra copies of the named parts' meshes bound to the figure's own
## skeleton and skin, so a figure costs what a figure of that many triangles would.
static func _add_copies(fig: Node3D, extra: Array) -> void:
	for id in extra:
		var source := fig.find_child(String(id), true, false) as MeshInstance3D
		if source == null:
			continue
		var copy := source.duplicate() as MeshInstance3D
		copy.name = "%s_copy" % id
		source.get_parent().add_child(copy)
		copy.skeleton = NodePath("..")


static func _place(
	base: Node, gm: GameMap, at: Vector2, spacing: float, builds: Array = []
) -> String:
	var holder := _holder(gm, true)
	var right := gm.camera_node.global_basis.x
	var r := Vector2(right.x, right.z).normalized()
	var t0 := Time.get_ticks_usec()
	var shades := PackedStringArray()
	for i in RECIPES.size():
		var xz := at + r * spacing * (i - 1)
		var build := float(builds[i]) if i < builds.size() else -1.0
		var fig := _add(base, gm, holder, i, xz, deg_to_rad(YAWS_DEG[i]), build)
		shades.append("%s %s" % [str(fig.global_position), _why(base, gm, fig.global_position)])
	return (
		"placed 3 figures in %.1f ms: %s"
		% [(Time.get_ticks_usec() - t0) / 1000.0, "; ".join(shades)]
	)


static func _canopy(base: Node, gm: GameMap, step: Dictionary) -> String:
	var holder := _holder(gm, false)
	var points: Array = step.get("points", [[0, 0]])
	var sun := _sun(base)
	var tried := PackedStringArray()
	var chosen := _vec2(points[points.size() - 1])
	for p in points:
		var xz := _vec2(p)
		var why := _why(base, gm, _ground(gm, xz)) if sun != null else "no sun"
		tried.append("%s: %s" % [str(xz), why])
		if why != "sun" and why != "no sun":
			chosen = xz
			break
	var fig := _add(base, gm, holder, int(step.get("recipe", 0)), chosen, deg_to_rad(8.0))
	var shade: Variant = fig.get_child(0).get_child(0).get_instance_shader_parameter("shade")
	return (
		"canopy figure at %s shade %s (tried %s)"
		% [str(fig.global_position), str(shade), ", ".join(tried)]
	)


## Adds one figure of `recipe` at the first of `points` whose shade ray is in sun (the
## figure in open sun beside foliage), or the last point.
static func _near(base: Node, gm: GameMap, step: Dictionary) -> String:
	var holder := _holder(gm, false)
	var points: Array = step.get("points", [[0, 0]])
	var chosen := _vec2(points[points.size() - 1])
	var tried := PackedStringArray()
	for p in points:
		var why := _why(base, gm, _ground(gm, _vec2(p)))
		tried.append("%s: %s" % [str(_vec2(p)), why])
		if why == "sun":
			chosen = _vec2(p)
			break
	var yaw := deg_to_rad(float(step.get("yaw", 8.0)))
	var fig := _add(base, gm, holder, int(step.get("recipe", 0)), chosen, yaw)
	return "sun figure at %s (tried %s)" % [str(fig.global_position), ", ".join(tried)]


## Pans so the screen centre looks at figure `index` (-1: the last one) at `height` metres
## above its feet, as the driver's look_at does for a ground point.
static func _look(gm: GameMap, index: int, height: float) -> String:
	var figs := _figures(gm)
	if figs.is_empty():
		return "no figures"
	var fig := figs[index if index >= 0 else figs.size() + index]
	var q := fig.global_position + Vector3.UP * height
	var z := gm.camera_node.global_basis.z
	var g := q - z * (q.y / z.y)
	var off: Vector2 = gm.get_camera_controller().call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(g.x - off.x, holder.global_position.y, g.z - off.y)
	return "look at %s (%s at %.2f m)" % [str(Vector2(g.x, g.z)), fig.name, height]


static func _spawn(
	base: Node, gm: GameMap, count: int, at: Vector2, spacing: float, extra: Array = []
) -> String:
	var holder := _holder(gm, true)
	if count <= 0:
		return "spawn none"
	var cols := ceili(sqrt(count * 1.4))
	var rows := ceili(float(count) / cols)
	var t0 := Time.get_ticks_usec()
	var tris := 0
	for k in count:
		var row := k / cols
		var x := at.x + (k % cols - (cols - 1) * 0.5 + (row % 2) * 0.5) * spacing
		var z := at.y + (row - (rows - 1) * 0.5) * spacing
		var yaw := deg_to_rad(YAWS_DEG[k % 3]) + sin(k * 2.39) * 0.4
		var fig := _add(base, gm, holder, k, Vector2(x, z), yaw, -1.0, extra)
		for mi in AvatarKit.figure_parts(fig):
			for s in mi.mesh.get_surface_count():
				tris += (mi.mesh as ArrayMesh).surface_get_array_index_len(s) / 3
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	return (
		"spawn %d figures (%d triangles each) in %.1f ms (%.2f ms each)"
		% [count, tris / count, ms, ms / count]
	)


static func _shade_all(base: Node, gm: GameMap) -> String:
	var out := PackedStringArray()
	for fig in _figures(gm):
		AvatarKit.update_shade(fig, gm.map_container, _sun(base))
		out.append(_why(base, gm, fig.global_position))
	return "shade: %s" % "; ".join(out)


## "sun", or what shades a ground point (AvatarShade.blocker), with the sun's direction.
static func _why(base: Node, gm: GameMap, at: Vector3) -> String:
	var sun := _sun(base)
	if sun == null:
		return "no sun"
	var hit := AvatarShade.blocker(gm.map_container, at, sun.global_basis.z)
	return "sun" if hit.is_empty() else "shade (%s, sun dir %s)" % [hit, str(sun.global_basis.z)]


static func _hidden(gm: GameMap, index: int, fade: float) -> String:
	var figs := _figures(gm)
	if index >= figs.size():
		return "no figure %d" % index
	AvatarKit.set_hidden_fade(figs[index], fade)
	return "figure %d hidden_fade %.2f" % [index, fade]


static func _params(gm: GameMap, params: Dictionary) -> String:
	var out := PackedStringArray()
	var first := true
	for fig in _figures(gm):
		for mi in AvatarKit.figure_parts(fig):
			var mat := mi.material_override as ShaderMaterial
			for key in params:
				var value: Variant = params[key]
				if value is Array and (value as Array).size() == 3:
					value = Color(float(value[0]), float(value[1]), float(value[2]))
				if first:
					out.append(
						"%s %s -> %s" % [key, str(mat.get_shader_parameter(key)), str(value)]
					)
				mat.set_shader_parameter(key, value)
			first = false
	return "params: %s" % "; ".join(out)


static func _info() -> String:
	var kit := _ensure()
	var out := PackedStringArray()
	var total := 0
	for id in kit.parts_by_id:
		var mesh: ArrayMesh = kit.load_part(id).mesh
		var tris := 0
		if mesh != null:
			for s in mesh.get_surface_count():
				tris += (
					(mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				)
		total += tris
		out.append("%s %d" % [id, tris])
	return (
		"kit %s: %s; figure %d triangles; errors %s"
		% [kit.manifest.get("kit_version", "?"), ", ".join(out), total, str(kit.errors)]
	)


## The live environment's ambient (what LevelEnvironmentManager pushes as figure_ambient),
## its tonemap, and the sun's colour, energy and direction.
static func _env(base: Node) -> String:
	var found := base.get_tree().root.find_children(
		"LevelEnvironment", "WorldEnvironment", true, false
	)
	if found.is_empty():
		return "no LevelEnvironment"
	var env := (found[0] as WorldEnvironment).environment
	var sun := _sun(base)
	return (
		"ambient %s x %.2f (source %d), tonemap %d exposure %.2f white %.2f; sun %s"
		% [
			str(env.ambient_light_color),
			env.ambient_light_energy,
			env.ambient_light_source,
			env.tonemap_mode,
			env.tonemap_exposure,
			env.tonemap_white,
			(
				(
					"%s x %.2f dir %s visible %s"
					% [
						str(sun.light_color),
						sun.light_energy,
						str(sun.global_basis.z),
						str(sun.visible)
					]
				)
				if sun != null
				else "none"
			),
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


static func _cleanup(step: Dictionary) -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	var only := String(step.get("folder", ""))
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX) and (only.is_empty() or folder == only):
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
