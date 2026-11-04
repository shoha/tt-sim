extends RefCounted

## Render-job probe for the propstand card (docs/systems/villages.md 3f): a token dropped on a hay
## stack or a crate stack stands on it. Steps (`op: call`, script this file):
##   {action: "scan"}
##       One line per bulky prop the settlements stand (name, position, yaw, scale, boxes).
##   {action: "shoot", dir, prop, stands, tokens_view, views}
##       Takes the first placed `prop` (a name), drops one avatar on its middle and one beside it
##       (along the view's right) the way a drop lands (TokenWater.landing_position), then saves
##       the composited window per view. `stands` false frees the Stand_ bodies first, which is
##       the behaviour before the card (the landing finds the ground). Each view is {name, mode
##       ("eye" or "home"), yaw, pitch, back (eye: metres in front of the prop), size (home),
##       scale (image scale, default 0.5)}.
##   {action: "sheet", dir, names, cols, out}
##       Joins dir/<name>.png into a grid and saves it to `out`.
##   {action: "await"}
##       Holds the job while the rig runs.

const GROUP := "propstand_rig"
const SIDE_GAP_M := 0.6


static func blocker(base: Node, _step: Dictionary) -> String:
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the propstand rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var gm: GameMap = base.get("_game_map")
	if action == "scan":
		return _scan(gm)
	if action == "sheet":
		return _sheet(step)
	var rig := Rig.new()
	rig.gm = gm
	rig.lpc = base.get("_level_play_controller")
	rig.step = step
	base.get_tree().root.add_child(rig)
	return "%s started" % action


static func _scan(gm: GameMap) -> String:
	var layer := Find.layer_of(gm)
	if layer == null:
		return "no AuthoredSettlements layer"
	var count := 0
	for id in range(1, 9):
		for row in layer.standing(id):
			var item: Dictionary = row["item"]
			var prop := String(item["prop"])
			if PropStand.kind_of(prop) != PropStand.STAND:
				continue
			count += 1
			var boxes := AuthoredSettlements.stand_boxes(String(row["ref"]), prop)
			var tops := PackedStringArray()
			for box in boxes:
				tops.append("%.2f" % float(box["top"]))
			print(
				"RJ| propstand prop %s at %s yaw %.2f scale %.2f y %.2f boxes %d tops %s"
				% [prop, item["position"], item["yaw"], item["scale"], row["y"], boxes.size(), ",".join(tops)]
			)
	return "%d standing props" % count


static func _sheet(step: Dictionary) -> String:
	var dir := ProjectSettings.globalize_path(String(step.get("dir", "")))
	var names: Array = step.get("names", [])
	var cols := int(step.get("cols", 2))
	var images: Array[Image] = []
	for name in names:
		# A name with a scheme (user://render_jobs/x/y) is its own path; else it is under `dir`.
		var file := (
			ProjectSettings.globalize_path(String(name))
			if String(name).contains("://")
			else dir.path_join(String(name))
		)
		var image := Image.load_from_file(file + ".png")
		if image == null:
			return "missing %s" % name
		images.append(image)
	if images.is_empty():
		return "no images"
	var cell := images[0].get_size()
	var rows := ceili(float(images.size()) / cols)
	var width := cell.x * cols + (cols - 1) * 4
	var height := cell.y * rows + (rows - 1) * 4
	var sheet := Image.create(width, height, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.05))
	for k in images.size():
		var at := Vector2i((k % cols) * (cell.x + 4), (k / cols) * (cell.y + 4))
		sheet.blit_rect(images[k], Rect2i(Vector2i.ZERO, cell), at)
	var out := ProjectSettings.globalize_path(String(step.get("out", "")))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("RJ| propstand sheet %s %s" % [out, str(sheet.get_size())])
	return "sheet saved"


class Find:
	extends RefCounted

	static func layer_of(gm: GameMap) -> AuthoredSettlements:
		var layers := gm.find_children("*", "AuthoredSettlements", true, false)
		return layers[0] as AuthoredSettlements if not layers.is_empty() else null

	## The `index`th placed prop `prop` as {"item", "y", "ref"}, or {}.
	static func find_prop(gm: GameMap, prop: String, index: int = 0) -> Dictionary:
		var layer := layer_of(gm)
		if layer == null:
			return {}
		var seen := 0
		for id in range(1, 9):
			for row in layer.standing(id):
				if String(row["item"]["prop"]) == prop:
					if seen == index:
						return row
					seen += 1
		return {}


class Rig:
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
		var dir := ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/propstand")))
		DirAccess.make_dir_recursive_absolute(dir)
		var prop := String(step.get("prop", "haystack"))
		var row := Find.find_prop(gm, prop, int(step.get("index", 0)))
		if row.is_empty():
			print("RJ| propstand no %s placed" % prop)
			queue_free()
			return
		var layer := Find.layer_of(gm)
		if not bool(step.get("stands", true)):
			for child in layer.get_children():
				if child is StaticBody3D:
					child.free()
			await get_tree().physics_frame
			print("RJ| propstand stands removed (the behaviour before the card)")
		var item: Dictionary = row["item"]
		var centre: Vector2 = item["position"]
		var scale := SettlementBake.visual_scale(item)
		var radius := ProcgenPropStyles.radius_of(prop) * scale
		var cc := gm.get_camera_controller()
		var tokens: Array[BoardToken] = []
		var eye_yaw := float(step.get("eye_yaw", 0.0))
		var right := Vector2(cos(deg_to_rad(eye_yaw)), -sin(deg_to_rad(eye_yaw)))
		var forward := Vector2(-sin(deg_to_rad(eye_yaw)), -cos(deg_to_rad(eye_yaw)))
		var side := centre + right * float(step.get("side", 1.0)) * (radius + SIDE_GAP_M)
		var back := float(step.get("back", 6.0))
		cc.set_view_mode(cc.eye)
		cc.eye.frame_ground(centre - forward * back, 0.0)
		cc.finish_zoom()
		await _frames(40)
		for at: Vector2 in [centre, side]:
			var p := _ground(at.x, at.y)
			var recipe := AvatarPresets.recipe(1 if at == side else 0)
			tokens.append(lpc.spawn_avatar(recipe, "propstand", p + Vector3.UP * 1.5, true))
		await _frames(150)
		var report := PackedStringArray()
		for token in tokens:
			report.append(str(token.rigid_body.global_position))
		print(
			"RJ| propstand %s at %s radius %.2f token_on_top %s token_beside %s ground %.3f"
			% [prop, str(centre), radius, report[0], report[1], _ground(centre.x, centre.y).y]
		)
		UIManager.clear_hints()
		for view in step.get("views", []):
			var home: bool = String(view.get("mode", "eye")) == "home"
			if home:
				cc.set_view_mode(cc.orbit_view())
				var mid := (centre + side) * 0.5
				cc.set_yaw_now(float(view.get("yaw", 0.0)))
				cc.set_pitch_now(float(view.get("pitch", 62.0)))
				cc.frame_ground(mid, float(view.get("size", 9.0)))
			else:
				if cc.view_mode() != cc.eye:
					cc.set_view_mode(cc.eye)
				var view_yaw := float(view.get("yaw", eye_yaw))
				var view_forward := Vector2(-sin(deg_to_rad(view_yaw)), -cos(deg_to_rad(view_yaw)))
				var mid := (centre + side) * 0.5
				cc.eye.frame_ground(mid - view_forward * float(view.get("back", back)), 0.0)
				cc.finish_zoom()
				cc.set_yaw_now(view_yaw)
				cc.set_pitch_now(float(view.get("pitch", 3.0)))
			await _frames(40)
			await RenderingServer.frame_post_draw
			var image := get_tree().root.get_texture().get_image()
			var scale_factor := float(view.get("scale", 0.5))
			if scale_factor != 1.0:
				image.resize(int(image.get_width() * scale_factor), int(image.get_height() * scale_factor))
			var path := dir.path_join(String(view.name) + ".png")
			image.save_png(path)
			print("RJ| propstand window %s" % path)
		print("RJ| propstand shoot done")
		queue_free()
