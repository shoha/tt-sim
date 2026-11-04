extends RefCounted

## Render-job probe for the hayrope card: why the haystack's dark rope bands did not show.
## Steps (`op: call`, script this file):
##   {action: "report"}
##       One line per surface of every settlement cell mesh (the baked, drawn surfaces): material
##       shader, vertex count, mean vertex colour and how many vertices are rope-dark (luma
##       under 0.3).
##   {action: "frame", index, back, side, yaw, pitch, fov}
##       Puts the eye `back` metres from the `index`th placed haystack (along the view's own
##       forward, `yaw` degrees), `side` metres to its right, at `pitch` and `fov`.

const Propstand := preload("res://tools/render_jobs/probes/propstand.gd")
const DARK_LUMA := 0.3


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	match String(step.get("action", "")):
		"report":
			return _report(gm)
		"frame":
			return _frame(gm, step)
	return "unknown action"


static func _report(gm: GameMap) -> String:
	var layer := Propstand.Find.layer_of(gm)
	if layer == null:
		return "no AuthoredSettlements layer"
	var surfaces := 0
	for child in layer.get_children():
		var node := child as MeshInstance3D
		if node == null or node.mesh == null:
			continue
		for s in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(s)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var dark := 0
			var sum := Vector3.ZERO
			for c in colors:
				sum += Vector3(c.r, c.g, c.b)
				if c.r * 0.299 + c.g * 0.587 + c.b * 0.114 < DARK_LUMA:
					dark += 1
			var mean := sum / maxf(colors.size(), 1)
			var mat := node.mesh.surface_get_material(s) as ShaderMaterial
			print(
				"RJ| hayrope %s surf %d shader %s verts %d mean (%.3f %.3f %.3f) dark %d"
				% [
					node.name,
					s,
					mat.shader.resource_path.get_file() if mat != null else "none",
					colors.size(),
					mean.x,
					mean.y,
					mean.z,
					dark
				]
			)
			surfaces += 1
	return "%d surfaces" % surfaces


static func _frame(gm: GameMap, step: Dictionary) -> String:
	var row := Propstand.Find.find_prop(gm, "haystack", int(step.get("index", 0)))
	if row.is_empty():
		return "no haystack placed"
	var item: Dictionary = row["item"]
	var centre: Vector2 = item["position"]
	var cc := gm.get_camera_controller()
	var yaw := float(step.get("yaw", 0.0))
	var forward := Vector2(-sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw)))
	var right := Vector2(cos(deg_to_rad(yaw)), -sin(deg_to_rad(yaw)))
	var foot := centre - forward * float(step.get("back", 4.0)) + right * float(step.get("side", 0.0))
	cc.set_view_mode(cc.eye)
	cc.eye.frame_ground(foot, 0.0)
	cc.set_yaw_now(yaw)
	cc.set_pitch_now(float(step.get("pitch", 4.0)))
	if step.has("fov"):
		cc.view_mode().zoom_by(float(step.fov) - cc.view_mode().fov_deg())
	cc.finish_zoom()
	print("RJ| hayrope frame hay %s foot %s yaw %.1f" % [centre, foot, yaw])
	return "framed"
