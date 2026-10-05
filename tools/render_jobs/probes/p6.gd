extends RefCounted

## Render-job probe (`call` op) for rivers past the map edge (phase 6, P6-1). Works on the open
## authored map (authoring, or play). Positions are map XZ metres. step.action:
##   bodies                  every river body's ends: id, depth class, level, each end's point
##                           and its distance inside the map edge, the drawn course sizes.
##   info                    the river exits of the open map (the skirt's
##                           AuthoredTerrain.river_exits(): each mouth, direction, level and
##                           course, drawn or derived), the skirt's vertex counts and backdrop
##                           uniforms, and the environment's background and fog.
##   look {exit, out}        pans the camera so the screen centre looks at the mouth of exit
##                           `exit` (index in info's list), `out` metres on along its course
##                           direction (default 0).
##   preset {name}           applies environment preset `name` (EnvironmentPresets) with no
##                           overrides, as choosing it in the Sky pane does.
##   show {part, visible}    shows or hides one part of the skirt (diagnostics): "ribbon",
##                           "channel" (the patch) or "main" (the skirt without the patch; drawn
##                           with an invisible override material while hidden).
##   probe {grow, blend}     grows the level's reflection probe by `grow` metres either side
##                           in X and Z and sets its blend distance (diagnostics).
##   shadow {part, on}       whether "channel" (the patch) or "main" (the skirt) casts shadows
##                           (diagnostics).
##   param {target, name, value}  sets a skirt material uniform (target "skirt"; an int
##                           uniform stays an int) or a ribbon instance uniform ("ribbon").
## Fog on and off is probes/skirt.gd `fog` (the skirt's SkirtBackdrop follows the environment).


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"info":
			return _info(base)
		"bodies":
			return _bodies(base)
		"look":
			return _look(base, int(step.get("exit", 0)), float(step.get("out", 0.0)))
		"preset":
			return _preset(base, String(step.get("name", "")))
		"show":
			return _show(base, String(step.get("part", "")), bool(step.get("visible", true)))
		"param":
			return _param(base, step)
		"probe":
			return _probe(base, float(step.get("grow", 0.0)), float(step.get("blend", 1.0)))
		"shadow":
			return _shadow(base, String(step.get("part", "channel")), bool(step.get("on", true)))
	return "unknown action %s" % step.get("action", "")


static func _probe(base: Node, grow: float, blend: float) -> String:
	var found := base.get_tree().root.find_children(
		"LevelReflectionProbe", "ReflectionProbe", true, false
	)
	if found.is_empty():
		return "no reflection probe"
	var probe := found[0] as ReflectionProbe
	probe.size += Vector3(grow, 0.0, grow) * 2.0
	probe.blend_distance = blend
	return "reflection probe size %s blend %.1f" % [str(probe.size), probe.blend_distance]


static func _shadow(base: Node, part: String, on: bool) -> String:
	var terrain := _terrain(base)
	var skirt := terrain.get_skirt() if terrain != null else null
	if skirt == null:
		return "no skirt"
	var node := (
		skirt if part == "main" else skirt.get_node_or_null(NodePath(SkirtExits.CHANNEL_NAME))
	)
	if not node is GeometryInstance3D:
		return "no %s" % part
	(node as GeometryInstance3D).cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if on
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return "%s casts shadows %s" % [part, str(on)]


static func _param(base: Node, step: Dictionary) -> String:
	var terrain := _terrain(base)
	var skirt := terrain.get_skirt() if terrain != null else null
	if skirt == null:
		return "no skirt"
	var key := String(step.get("name", ""))
	var value: Variant = step.get("value")
	if String(step.get("target", "skirt")) == "ribbon":
		var ribbon := skirt.get_node_or_null(NodePath(SkirtExits.RIBBON_NAME)) as MeshInstance3D
		if ribbon == null:
			return "no ribbon"
		ribbon.set_instance_shader_parameter(key, value)
		return "ribbon %s = %s" % [key, str(value)]
	var material := skirt.mesh.surface_get_material(0) as ShaderMaterial
	var before: Variant = material.get_shader_parameter(key)
	material.set_shader_parameter(key, int(value) if before is int else value)
	return "skirt %s = %s (was %s)" % [key, str(value), str(before)]


static func _show(base: Node, part: String, visible: bool) -> String:
	var terrain := _terrain(base)
	var skirt := terrain.get_skirt() if terrain != null else null
	if skirt == null:
		return "no skirt"
	if part == "main":
		var hidden: Material = null
		if not visible:
			var invisible := StandardMaterial3D.new()
			invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			invisible.albedo_color = Color(0, 0, 0, 0)
			hidden = invisible
		skirt.set_surface_override_material(0, hidden)
		return "main skirt visible %s" % str(visible)
	var names := {"ribbon": SkirtExits.RIBBON_NAME, "channel": SkirtExits.CHANNEL_NAME}
	var node := skirt.get_node_or_null(NodePath(String(names.get(part, part)))) as Node3D
	if node == null:
		return "no %s" % part
	node.visible = visible
	return "%s visible %s" % [part, str(visible)]


static func _terrain(base: Node) -> AuthoredTerrain:
	var found := base.get_tree().root.find_children(
		"AuthoredTerrain", "AuthoredTerrain", true, false
	)
	return found[0] as AuthoredTerrain if not found.is_empty() else null


static func _mouths(base: Node) -> Array:
	var terrain := _terrain(base)
	return terrain.river_exits().get("mouths", []) if terrain != null else []


static func _bodies(base: Node) -> String:
	var terrain := _terrain(base)
	if terrain == null:
		return "no authored terrain"
	var doc := terrain.document
	var half := doc.extent_m() * 0.5
	var parts := PackedStringArray(["half %s" % str(half)])
	for body in doc.water_bodies:
		if not body.is_river():
			continue
		var head := body.points[0]
		var tail := body.points[-1]
		(
			parts
			. append(
				(
					(
						"body %d depth %d level %.3f %d points, up %s (%.3f in) "
						+ "down %s (%.3f in), beyond_up %d beyond %d"
					)
					% [
						body.id,
						body.depth,
						body.level_m,
						body.points.size(),
						str(head),
						RiverExits.edge_distance(head, half),
						str(tail),
						RiverExits.edge_distance(tail, half),
						body.beyond_up.size(),
						body.beyond.size(),
					]
				)
			)
		)
	return " | ".join(parts)


static func _info(base: Node) -> String:
	var terrain := _terrain(base)
	if terrain == null:
		return "no authored terrain"
	var parts := PackedStringArray()
	var exits := RiverExits.exits(terrain.document)
	for i in exits.size():
		var e: Dictionary = exits[i]
		var course: PackedVector2Array = e.course
		(
			parts
			. append(
				(
					"exit %d: body %d %s %s level %.3f half-width %.2f, %d points to %s"
					% [
						i,
						e.id,
						"down" if e.end == RiverExits.End.DOWN else "up",
						"drawn" if e.drawn else "derived",
						e.level,
						e.half_width,
						course.size(),
						str(course[-1]),
					]
				)
			)
		)
	var mouths := _mouths(base)
	for i in mouths.size():
		var m: Dictionary = mouths[i]
		parts.append(
			(
				"mouth %d at %s dir %s wet %s ground %.2f reach %.1f"
				% [i, str(m.mouth), str(m.dir), str(m.wet), m.ground, m.reach]
			)
		)
		if m.has(PondExits.WIDTHS):
			parts.append(
				(
					"  pond %d level %.3f lobe %.1f m flare %s"
					% [m.id, m.level, m.length, str(m.flare)]
				)
			)
	var skirt := terrain.get_skirt()
	if skirt != null:
		parts.append("skirt %d vertices" % skirt.mesh.surface_get_array_len(0))
		for child in skirt.get_children():
			var node := child as MeshInstance3D
			if node != null:
				parts.append("%s %d vertices" % [node.name, node.mesh.surface_get_array_len(0)])
		var material := skirt.mesh.surface_get_material(0) as ShaderMaterial
		for key in ["skirt_backdrop_mode", "skirt_backdrop", "skirt_fog", "skirt_channel"]:
			parts.append("%s %s" % [key, str(material.get_shader_parameter(key))])
	var world := base.get_viewport().find_world_3d()
	var env := world.environment if world != null else null
	if env != null:
		(
			parts
			. append(
				(
					"env bg %d colour %s sky %s fog %s density %.4f"
					% [
						env.background_mode,
						str(env.background_color),
						env.sky.sky_material.get_class() if env.sky != null else "none",
						str(env.fog_enabled),
						env.fog_density,
					]
				)
			)
		)
	return " | ".join(parts)


static func _look(base: Node, index: int, out: float) -> String:
	var mouths := _mouths(base)
	if index < 0 or index >= mouths.size():
		return "no exit %d (%d)" % [index, mouths.size()]
	var m: Dictionary = mouths[index]
	var at: Vector2 = (m.mouth as Vector2) + (m.dir as Vector2) * out
	var gm := base.get("_game_map") as GameMap
	var cc := gm.get_camera_controller()
	var off: Vector2 = cc.call("_get_view_center_ground_offset")
	# The offset is to the ground plane y = 0; the river is at its level, so the screen centre
	# ray meets it this much further along the view.
	var forward := -gm.camera_node.global_basis.z
	var level: float = m.level
	if absf(forward.y) > 1e-3:
		off += Vector2(forward.x, forward.z) * (level / forward.y)
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(at.x - off.x, holder.global_position.y, at.y - off.y)
	return "look at exit %d %s" % [index, str(at)]


static func _preset(base: Node, preset: String) -> String:
	var ctrl: Node = base.get("_authoring_controller")
	var manager: LevelEnvironmentManager = ctrl.get("_environment") if ctrl != null else null
	if manager != null:
		manager.apply_environment_settings(preset, {})
		return "preset %s (authoring)" % preset
	var lpc: LevelPlayController = base.get("_level_play_controller")
	if lpc != null:
		lpc.apply_environment_settings(preset, {})
		return "preset %s (play)" % preset
	return "no environment to set"
