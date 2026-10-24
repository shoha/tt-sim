extends RefCounted

## Render-job probe (`call` op) for the token ghost and the see-through settings (docs/
## PERFORMANCE.md "Token ghost", jobs/token_ghost.json). Positions are map XZ metres. `action`:
## - `spawn` (`at` [x, z], `preset` default 0, `yaw` degrees, `select` default false): one
##   avatar token dropped on the terrain at the point (selected = hover glow layer added).
## - `look` (`at` [x, z], `height` default 0.8, `shift` [dx, dy] default [0, 0]): pans so the
##   point stands at the screen centre moved by `shift` (screen fractions, +x right, +y down),
##   so a token can be put away from the centre the canopy window sits on.
## - `spawn_screen` (`fracs` [[fx, fy], ...], `preset`, `select`): avatars under screen points.
## - `mode`: `reset` (the shipped state), `ghost` (bool), `ghost_params` ({uniform: value},
##   set on every overlay, for tuning), `occlusion` (bool, the per-token fade), `canopy` (bool,
##   the close-zoom window).
## - `info`: draw calls, primitives and token meshes of the last frame.
## - `report`: tokens and their screen positions.

const AVATAR_PROBE := "res://tools/render_jobs/probes/avatar_token.gd"


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var lpc: LevelPlayController = base.get("_level_play_controller")
	match String(step.get("action", "report")):
		"spawn":
			return _spawn(gm, lpc, step)
		"look":
			return _look(gm, step)
		"spawn_screen":
			return _spawn_screen(gm, lpc, step)
		"clear":
			return _clear(gm)
		"mode":
			return _mode(gm, step)
		"lofi":
			# The lo-fi pass with its pixelation (the dither grid of the occlusion fade aligns
			# to it), as a map's own lo-fi settings can ask for.
			var px := float(step.get("pixelation", 0.0))
			gm.get("_visual_effects").call("apply_lofi_overrides", {"pixelation": px})
			return "lofi pixelation %.4f" % px
		"spawn_big":
			return _spawn_big(gm, lpc, step)
		"bounds":
			var out := PackedStringArray()
			for node in gm.get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
				var token := node as BoardToken
				var mi := TokenGhost.meshes_of(token.rigid_body)[0]
				var ghost := TokenGhost.overlay_of(mi)
				(
					out
					. append(
						(
							"%s: %s"
							% [
								token.token_name,
								(
									"none"
									if ghost == null
									else (
										"extent %s centre %s up %s"
										% [
											ghost.get_shader_parameter("bound_extent"),
											ghost.get_shader_parameter("bound_center"),
											ghost.get_shader_parameter("bound_up"),
										]
									)
								),
							]
						)
					)
				)
			return " | ".join(out)
		"spawn_box":
			# A pack-style token (a box model with a collision shape and a StandardMaterial3D),
			# for the ghost's albedo path; there is no cached asset pack in a topic's own user
			# folder.
			if lpc == null:
				return "not playing"
			var model := Node3D.new()
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.6, 1.4, 0.6)
			mesh.mesh = box
			mesh.position = Vector3(0, 0.7, 0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.75, 0.2, 0.15)
			mesh.material_override = mat
			model.add_child(mesh)
			var body := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			body.shape = shape
			body.position = Vector3(0, 0.7, 0)
			model.add_child(body)
			var token := BoardTokenFactory.create_from_scene(model)
			if token == null:
				return "box token failed"
			var at := _ground(gm, _vec2(step.get("at", [0, 0])))
			lpc.get("_token_spawner").call(
				"_place_new_token", token, "test", "box", "default", at, false
			)
			return "box token at %s" % str(at)
		"info":
			var vp := gm.world_viewport.get_viewport_rid()
			var meshes := 0
			for node in gm.drag_and_drop_node.get_children():
				if node is BoardToken:
					var body := (node as BoardToken).rigid_body
					meshes += body.find_children("*", "MeshInstance3D", true, false).size()
			return (
				"draw calls %d, primitives %d, token meshes %d"
				% [
					RenderingServer.viewport_get_render_info(
						vp,
						RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
						RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
					),
					RenderingServer.viewport_get_render_info(
						vp,
						RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
						RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
					),
					meshes,
				]
			)
		"aa":
			# The foliage antialiasing level (0 swaps every tree to the plain-cutout wind shader).
			gm.set_foliage_antialiasing_level(int(step.get("level", 0)))
			return "foliage antialiasing level %d" % int(step.get("level", 0))
		"msaa":
			gm.world_viewport.msaa_3d = int(step.get("level", 0)) as Viewport.MSAA
			return "msaa_3d %d" % gm.world_viewport.msaa_3d
		"report":
			return _report(gm)
	return "unknown action %s" % step.get("action", "")


static func _vec2(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _ground(gm: GameMap, xz: Vector2) -> Vector3:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0, xz.y))
	return Vector3(xz.x, hit.y if hit != Vector3.INF else 0.0, xz.y)


static func _spawn(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var at := _ground(gm, _vec2(step.get("at", [0, 0])))
	var index := int(step.get("preset", 0)) % AvatarPresets.PRESETS.size()
	var token := lpc.spawn_avatar(
		AvatarPresets.recipe(index), String(AvatarPresets.PRESETS[index].name), at
	)
	if token == null:
		return "spawn failed"
	var yaw := float(step.get("yaw", 0.0))
	if yaw != 0.0:
		token.set_transform_immediate(at, Vector3(0, deg_to_rad(yaw), 0), Vector3.ONE)
		token.transform_changed.emit()
	if bool(step.get("select", false)):
		token.set_highlighted(true)
	return "spawned %s at %s" % [token.token_name, str(at.snapped(Vector3.ONE * 0.01))]


## A large multi-part pack-style token (a quadruped: body, four legs, head, back bloom, each
## its own mesh and material), `scale` times 1.6 m long, for the ghost's self-occlusion check.
static func _spawn_big(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var model := Node3D.new()
	var parts := [
		[
			"body",
			SphereMesh.new(),
			Vector3(0, 1.0, 0),
			Vector3(1.0, 0.8, 1.5),
			Color(0.2, 0.6, 0.55)
		],
		[
			"head",
			SphereMesh.new(),
			Vector3(0, 1.1, 0.95),
			Vector3(0.6, 0.6, 0.6),
			Color(0.25, 0.65, 0.5)
		],
		[
			"bloom",
			SphereMesh.new(),
			Vector3(0, 1.75, -0.1),
			Vector3(0.9, 0.6, 0.9),
			Color(0.85, 0.3, 0.45)
		],
	]
	for corner in [
		Vector2(-0.5, 0.55), Vector2(0.5, 0.55), Vector2(-0.5, -0.55), Vector2(0.5, -0.55)
	]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.22
		cyl.height = 0.8
		parts.append(
			["leg", cyl, Vector3(corner.x, 0.4, corner.y), Vector3.ONE, Color(0.15, 0.45, 0.4)]
		)
	for p in parts:
		var mesh := MeshInstance3D.new()
		mesh.name = p[0]
		mesh.mesh = p[1]
		mesh.position = p[2]
		mesh.scale = p[3]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p[4]
		mesh.material_override = mat
		model.add_child(mesh)
	var body := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 2.0, 1.8)
	body.shape = shape
	body.position = Vector3(0, 1.0, 0)
	model.add_child(body)
	var token := BoardTokenFactory.create_from_scene(model)
	if token == null:
		return "big token failed"
	var at := _ground(gm, _vec2(step.get("at", [0, 0])))
	lpc.get("_token_spawner").call("_place_new_token", token, "test", "big", "default", at, false)
	var s := float(step.get("scale", 1.0))
	token.set_transform_immediate(
		at, Vector3(0, deg_to_rad(float(step.get("yaw", 0.0))), 0), Vector3.ONE * s
	)
	token.transform_changed.emit()
	if bool(step.get("select", false)):
		token.set_highlighted(true)
	return "big token at %s scale %.2f" % [str(at.snapped(Vector3.ONE * 0.01)), s]


## Spawns an avatar on the terrain under each screen fraction of `fracs` ([[fx, fy], ...],
## 0..1 of the window), presets cycling from `preset`; the first `select` ones are selected.
static func _spawn_screen(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var cam := gm.camera_node
	var size := Vector2(gm.world_viewport.size)
	var out := PackedStringArray()
	var k := 0
	for f in step.get("fracs", []):
		var px := Vector2(float(f[0]) * size.x, float(f[1]) * size.y)
		var origin := cam.project_ray_origin(px)
		var dir := cam.project_ray_normal(px)
		var space := gm.world_viewport.find_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 400.0)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		var at: Vector3 = hit.position if not hit.is_empty() else origin
		var index := (int(step.get("preset", 0)) + k) % AvatarPresets.PRESETS.size()
		var token := lpc.spawn_avatar(
			AvatarPresets.recipe(index), String(AvatarPresets.PRESETS[index].name), at
		)
		if token != null:
			if k < int(step.get("select", 0)):
				token.set_highlighted(true)
			out.append(
				"%s %s" % [token.token_name, str(Vector2(at.x, at.z).snapped(Vector2.ONE * 0.1))]
			)
		k += 1
	return "spawned " + ", ".join(out)


static func _clear(gm: GameMap) -> String:
	var n := 0
	for node in gm.drag_and_drop_node.get_children():
		if node is BoardToken:
			node.queue_free()
			n += 1
	return "cleared %d tokens" % n


static func _look(gm: GameMap, step: Dictionary) -> String:
	var xz := _vec2(step.get("at", [0, 0]))
	var q := _ground(gm, xz) + Vector3.UP * float(step.get("height", 0.8))
	var z := gm.camera_node.global_basis.z
	var g := q - z * (q.y / z.y)
	var off: Vector2 = gm.get_camera_controller().call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	var shift := _vec2(step.get("shift", [0, 0]))
	var cam := gm.camera_node
	# Screen shift in metres on the ground plane: the camera's right axis and its up axis
	# flattened onto the ground (the view is orthographic, so the screen is linear).
	var half_h := cam.size * 0.5
	var half_w := half_h * float(gm.world_viewport.size.x) / float(gm.world_viewport.size.y)
	var right := cam.global_basis.x
	var up_screen := cam.global_basis.y
	var delta_world := right * (-shift.x * 2.0 * half_w) + up_screen * (shift.y * 2.0 * half_h)
	var gd := delta_world - z * (delta_world.y / z.y)
	holder.global_position = Vector3(
		g.x - off.x + gd.x, holder.global_position.y, g.z - off.y + gd.z
	)
	return "look at %s shift %s" % [str(Vector2(g.x, g.z)), str(shift)]


static func _mode(gm: GameMap, step: Dictionary) -> String:
	var out := PackedStringArray()
	if bool(step.get("reset", false)):
		gm.set_occlusion_fade_enabled(true)
		CanopyFade.enabled = CanopyFade.DEFAULT_ENABLED
		TokenGhost.set_enabled(TokenGhost.DEFAULT_ENABLED, gm.get_tree())
		TokenGhost.budget = TokenGhost.BUDGET_TOKENS
		out.append("reset")
	if step.has("occlusion"):
		gm.set_occlusion_fade_enabled(bool(step.occlusion))
		out.append("occlusion %s" % str(step.occlusion))
	if step.has("canopy"):
		CanopyFade.enabled = bool(step.canopy)
		out.append("canopy %s" % str(step.canopy))
	if step.has("budget"):
		TokenGhost.budget = int(step.budget)
		out.append("budget %d" % TokenGhost.budget)
	if step.has("ghost"):
		TokenGhost.set_enabled(bool(step.ghost), gm.get_tree())
		out.append("ghost %s" % str(step.ghost))
	var params: Dictionary = step.get("ghost_params", {})
	if not params.is_empty():
		var n := 0
		for node in gm.get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
			var token := node as BoardToken
			for mi in TokenGhost.meshes_of(token.rigid_body):
				var ghost := TokenGhost.overlay_of(mi)
				if ghost == null:
					continue
				n += 1
				for key in params:
					var value: Variant = params[key]
					if value is Array and (value as Array).size() == 2:
						value = Vector2(float(value[0]), float(value[1]))
					ghost.set_shader_parameter(String(key), value)
		out.append("ghost_params on %d overlays" % n)
	return ", ".join(out)


static func _report(gm: GameMap) -> String:
	var out := PackedStringArray()
	var cam := gm.camera_node
	for node in gm.drag_and_drop_node.get_children():
		if node is BoardToken:
			var token := node as BoardToken
			var p := token.rigid_body.global_position + Vector3.UP * 0.8
			(
				out
				. append(
					(
						"%s world %s screen %s"
						% [
							token.token_name,
							str(p.snapped(Vector3.ONE * 0.01)),
							str(cam.unproject_position(p).snapped(Vector2.ONE)),
						]
					)
				)
			)
	return "cam size %.2f | %s" % [cam.size, " | ".join(out)]
