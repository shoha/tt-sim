extends RefCounted

## Render-job probe (`call` op). Sets the live environment's background to a flat colour
## (step.color = [r, g, b]); the cursor position zoom-toward-cursor uses (step.mouse = [x, y]);
## whether the camera is clamped to the fitted map bounds (step.recentre); and the terrain
## skirt's visibility (step.skirt).


static func run(base: Node, step: Dictionary) -> String:
	var out := ""
	if step.has("color"):
		var c: Array = step.color
		for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var env: Environment = (node as WorldEnvironment).environment
			if env == null:
				continue
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(float(c[0]), float(c[1]), float(c[2]))
			out += "bg %s " % str(env.background_color)
	var gm: GameMap = base.get("_game_map")
	var cc: CameraController = gm.get_camera_controller()
	if step.has("mouse"):
		var m: Array = step.mouse
		cc.set("_last_mouse_position", Vector2(float(m[0]), float(m[1])))
		out += "mouse %s " % str(m)
	if step.has("recentre"):
		if bool(step.recentre):
			cc.set("_fit_size", cc.call("_fit_size_for_bounds", cc.get("_map_bounds")))
		else:
			cc.set("_fit_size", INF)
		cc.call("_clamp_camera_to_bounds")
		out += "fit %s " % str(cc.get("_fit_size"))
	if step.has("skirt"):
		for node in base.get_tree().root.find_children(
			"TerrainSkirt", "MeshInstance3D", true, false
		):
			(node as MeshInstance3D).visible = bool(step.skirt)
			out += "skirt %s " % str(step.skirt)
	return out
