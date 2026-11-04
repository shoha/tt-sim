extends RefCounted

## Render-job probe for the eyepin round (docs/plans/2026-11-02-camera, card eyepin): two
## questions about tokens at the street-level eye view, a token standing on or against hay and
## crates, and a far token with nothing marking it. Steps (`op: call`, script this file):
##   {action: "scan", pattern}
##       One line per node under the map whose name matches the regex `pattern`: its class, path
##       and world position (to find the hay and crates).
##   {action: "shoot", dir, at, tokens, hints, views}
##       Enters the eye at `at` (world XZ). `tokens` is [{x, z, drop}] (drop true lands the token
##       the way a drop does: TokenWater.landing_position onto the terrain layer; false stands it
##       at the height function's ground). Each view is {name, mode ("eye" or "home"), yaw,
##       pitch, size and look [x, z] (home), pins (bool: the eye pins option), arrows (bool: the
##       edge arrows option)}. Saves the composited window per view.
##   await
##       Holds the job while the rig runs.

const GROUP := "eyepin_rig"


static func blocker(base: Node, _step: Dictionary) -> String:
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the eyepin rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var gm: GameMap = base.get("_game_map")
	if action == "scan":
		return _scan(gm, String(step.get("pattern", "hay|crate")))
	var rig := PinRig.new()
	rig.gm = gm
	rig.lpc = base.get("_level_play_controller")
	rig.step = step
	base.get_tree().root.add_child(rig)
	return "%s started" % action


static func _scan(gm: GameMap, pattern: String) -> String:
	if pattern == "@props":
		return _scan_props(gm)
	var re := RegEx.create_from_string("(?i)" + pattern)
	var lines := PackedStringArray()
	var stack: Array[Node] = [gm]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Node3D and re.search(String(node.name)) != null:
			lines.append(
				"%s %s at %s" % [node.get_class(), gm.get_path_to(node), str((node as Node3D).global_position)]
			)
	for line in lines.slice(0, 60):
		print("RJ| eyepin scan %s" % line)
	return "%d nodes match %s" % [lines.size(), pattern]


## The placed furnishings of every settlement (prop name, map XZ, yaw, scale), by the bulky ones first.
static func _scan_props(gm: GameMap) -> String:
	var layers := gm.find_children("*", "AuthoredSettlements", true, false)
	if layers.is_empty():
		return "no AuthoredSettlements layer"
	var layer := layers[0] as AuthoredSettlements
	var count := 0
	for id in range(1, 9):
		for row in layer.standing(id):
			var item: Dictionary = row["item"]
			if not PropFootprints.SIZES.has(String(item["prop"])):
				continue
			count += 1
			print(
				"RJ| eyepin prop %s at %s yaw %.2f scale %.2f y %.2f"
				% [item["prop"], item["position"], item["yaw"], item["scale"], row["y"]]
			)
	return "%d bulky props; footprints %d" % [count, PropFootprints.active.size()]


class PinRig:
	extends Node

	var gm: GameMap = null
	var lpc: LevelPlayController = null
	var step: Dictionary = {}

	func _ready() -> void:
		add_to_group(GROUP)
		_main()

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _ground(x: float, z: float) -> Vector3:
		var height := ViewGround.height_function(gm)
		return Vector3(x, float(height.call(Vector2(x, z))) if height.is_valid() else 0.0, z)

	func _main() -> void:
		var dir := ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/eyepin")))
		DirAccess.make_dir_recursive_absolute(dir)
		var cc := gm.get_camera_controller()
		PropFootprints.enabled = bool(step.get("step_off", false))
		cc.set_view_mode(cc.eye)
		var at: Array = step.get("at", [0, 0])
		cc.eye.frame_ground(Vector2(float(at[0]), float(at[1])), 0.0)
		cc.finish_zoom()
		await _frames(40)
		var tokens: Array[BoardToken] = []
		for t in step.get("tokens", []):
			var p := _ground(float(t.x), float(t.z))
			var drop := bool(t.get("drop", false))
			var recipe := AvatarPresets.recipe(int(t.get("preset", 0)))
			var above := Vector3.UP * 1.5 if drop else Vector3.ZERO
			var token := lpc.spawn_avatar(recipe, "eyepin", p + above, drop)
			tokens.append(token)
		await _frames(150)
		for token in tokens:
			var rb := token.rigid_body
			print("RJ| eyepin token at %s" % str(rb.global_position))
		for h in step.get("hints", []):
			UIManager.add_hint(String(h[0]), String(h[1]))
		await _frames(10)
		var markers := gm.world_viewport.get_node_or_null("TokenMarkers")
		for view in step.get("views", []):
			var home: bool = String(view.get("mode", "eye")) == "home"
			if home:
				cc.set_view_mode(cc.orbit_view())
				var look: Array = view.get("look", at)
				cc.focus_camera_on(_ground(float(look[0]), float(look[1])))
				(cc.view_mode() as OrbitView).target_zoom = float(view.get("size", 18.0))
				cc.finish_zoom()
				cc.set_yaw_now(float(view.get("yaw", 0.0)))
				cc.set_pitch_now(float(view.get("pitch", 62.0)))
			else:
				if cc.view_mode() != cc.eye:
					cc.set_view_mode(cc.eye)
					cc.eye.frame_ground(Vector2(float(at[0]), float(at[1])), 0.0)
					cc.finish_zoom()
				var yaw := float(view.get("yaw", 0.0))
				if view.has("face"):
					# Forward at yaw y is (-sin y, -cos y) on the map's XZ (measured: yaw 90 looks
					# west, 180 looks +z, 270 east).
					var to := Vector2(float(view.face[0]) - float(at[0]), float(view.face[1]) - float(at[1]))
					yaw = rad_to_deg(atan2(-to.x, -to.y))
				cc.set_yaw_now(yaw)
				cc.set_pitch_now(float(view.pitch))
			if markers != null:
				markers.set("eye_pins", bool(view.get("pins", false)))
				markers.set("eye_arrows", bool(view.get("arrows", false)))
			await _frames(30)
			await RenderingServer.frame_post_draw
			var camera := gm.camera_node
			var report := PackedStringArray()
			for token in tokens:
				var head := token.rigid_body.global_position + Vector3.UP * 0.9
				report.append(
					"%s%s" % [str(camera.unproject_position(head).round()), " behind" if camera.is_position_behind(head) else ""]
				)
			print("RJ| eyepin view %s forward %s tokens %s" % [view.name, str(-camera.global_basis.z), report])
			var path := dir.path_join(String(view.name) + ".png")
			get_tree().root.get_texture().get_image().save_png(path)
			print("RJ| eyepin window %s" % path)
		UIManager.clear_hints()
		PropFootprints.enabled = false
		print("RJ| eyepin shoot done")
		queue_free()
