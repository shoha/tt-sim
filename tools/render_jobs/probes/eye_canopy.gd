extends RefCounted

## Render-job probe for the eye view's foliage fade (card eyecanopy). It stands the real EyeView
## where a still needs it; the job takes the capture. Steps (`op: call`, script this file);
## `fade` (default true) is CanopyFade.eye_fade_enabled for that still, so a before and an after
## come from one run. `at` ([x, z]) is the eye spot of the map, given with the first step:
##   {action: "tree", d, pitch, fade}   the tree nearest `at`: the eye `d` metres from its trunk
##                                      (diagonal), looking at it, at `pitch`
##   {action: "forest", yaw, pitch, fade}  the spot of the map with the most tall trees within
##                                      7 m, looking along `yaw` (the camera controller's)
##   {action: "ghost", ahead, behind, width, toward, off, occl, fade}  a plank `width` metres wide
##                                      and 14 m tall stands `ahead` metres from `at` (toward the
##                                      world point `toward`, default the map centre), a token
##                                      `behind` it; the eye looks `off` degrees to the side of the
##                                      token. `occl` registers the plank with the occlusion fade
##                                      (a map surface); otherwise only the token ghost shows the
##                                      token through it.
##   {action: "report"}                 one line: camera, canopy_eye global state
## The eye view is entered on the first action (CameraController.set_view_mode). Run the job's
## `leave` with eye_view.gd.

static var _spot := Vector2.ZERO
static var _tree := {}
static var _token: Node = null
static var _blocker: Node3D = null


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc := gm.get_camera_controller()
	CanopyFade.eye_fade_enabled = bool(step.get("fade", true))
	if cc.view_mode() != cc.eye:
		cc.set_view_mode(cc.eye)
	var at: Array = step.get("at", [])
	if at.size() == 2:
		_spot = Vector2(float(at[0]), float(at[1]))
	match String(step.get("action", "")):
		"tree":
			return _tree_still(gm, cc, step)
		"forest":
			return _forest_still(gm, cc, step)
		"ghost":
			return _ghost_still(base, gm, cc, step)
		"report":
			return _report(gm)
		"clear":
			for node: Node in [_token, _blocker]:
				if node != null and is_instance_valid(node):
					node.queue_free()
			_token = null
			_blocker = null
			return "cleared"
	return "unknown action"


static func _trees(gm: GameMap, min_height: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for node in gm.get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or mm.mesh == null:
			continue
		var h := mm.mesh.get_aabb().size.y
		for i in mm.instance_count:
			var xf := mmi.global_transform * mm.get_instance_transform(i)
			if h * xf.basis.get_scale().y >= min_height:
				out.append(xf.origin)
	return out


static func _nearest(trees: Array[Vector3], xz: Vector2, min_d: float = 0.0) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for t in trees:
		var d := Vector2(t.x, t.z).distance_to(xz)
		if d >= min_d and d < best_d:
			best_d = d
			best = t
	return best


## The camera controller's yaw that faces world direction `dir` (xz), by search.
static func _yaw_for(dir: Vector2) -> float:
	var best := 0.0
	var best_err := INF
	for deg in range(0, 360):
		var up := CameraRig.screen_up(float(deg))
		var err := Vector2(up.x, up.z).distance_to(dir.normalized())
		if err < best_err:
			best_err = err
			best = float(deg)
	return best


static func _stand(cc: CameraController, xz: Vector2, yaw: float, pitch: float) -> void:
	cc.eye.frame_ground(xz, 0.0)
	cc.set_yaw_now(yaw)
	cc.set_pitch_now(pitch)
	cc.finish_zoom()


static func _tree_still(gm: GameMap, cc: CameraController, step: Dictionary) -> String:
	if _tree.is_empty():
		var tp := _nearest(_trees(gm, float(step.get("min_h", 5.0))), _spot)
		_tree = {"pos": tp}
	var tp: Vector3 = _tree.pos
	var d := float(step.get("d", 1.5))
	var side := Vector2(1, 1).normalized()
	var xz := Vector2(tp.x, tp.z) + side * d
	_stand(cc, xz, _yaw_for(-side), float(step.get("pitch", 0.0)))
	return "tree %s eye %s d %.2f fade %s" % [str(tp), str(xz), d, str(CanopyFade.eye_fade_enabled)]


static func _forest_still(gm: GameMap, cc: CameraController, step: Dictionary) -> String:
	if not _tree.has("forest"):
		var trees := _trees(gm, float(step.get("min_h", 5.0)))
		var best := Vector2.ZERO
		var best_n := -1
		for t in trees:
			var n := 0
			for u in trees:
				if Vector2(t.x - u.x, t.z - u.z).length() < 7.0:
					n += 1
			if n > best_n:
				best_n = n
				best = Vector2(t.x, t.z) + Vector2(1.7, 0.9)
		_tree["forest"] = best
		_tree["forest_n"] = best_n
	var xz: Vector2 = _tree.forest
	_stand(cc, xz, float(step.get("yaw", 0.0)), float(step.get("pitch", 3.0)))
	return (
		"forest eye %s trees within 7 m %d fade %s"
		% [str(xz), _tree.forest_n, str(CanopyFade.eye_fade_enabled)]
	)


static func _ghost_still(base: Node, gm: GameMap, cc: CameraController, step: Dictionary) -> String:
	var ahead := float(step.get("ahead", 6.0))
	var behind := float(step.get("behind", 3.0))
	var toward_a: Array = step.get("toward", [0.0, 0.0])
	var toward := Vector2(float(toward_a[0]), float(toward_a[1]))
	var dir := (toward - _spot).normalized()
	var tree_xz := _spot + dir * ahead
	var token_xz := tree_xz + dir * behind
	if _token != null and is_instance_valid(_token):
		_token.queue_free()
		_token = null
	if _blocker != null and is_instance_valid(_blocker):
		_blocker.queue_free()
		_blocker = null
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var base_hit := DragPlaceController.raycast_terrain_down(
		space, Vector3(tree_xz.x, 0.0, tree_xz.y)
	)
	_blocker = _plank(gm, tree_xz, base_hit.y if base_hit != Vector3.INF else 0.0, dir, step)
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(token_xz.x, 0.0, token_xz.y))
	var gp := Vector3(token_xz.x, hit.y if hit != Vector3.INF else 0.0, token_xz.y)
	var lpc: LevelPlayController = base.get("_level_play_controller")
	_token = lpc.spawn_avatar(AvatarPresets.recipe(0), "eyecanopy", gp)
	if _token == null:
		return "ghost: spawn failed"
	var aim := Vector3(token_xz.x, gp.y + 0.9, token_xz.y)
	_stand(cc, _spot, _yaw_for(dir) + float(step.get("off", 0.0)), 0.0)
	var flat := Vector2(aim.x, aim.z).distance_to(_spot)
	var under := DragPlaceController.raycast_terrain_down(space, Vector3(_spot.x, 0.0, _spot.y))
	var eye_y := (under.y if under != Vector3.INF else 0.0) + 1.6
	cc.set_pitch_now(rad_to_deg(atan2(eye_y - aim.y, flat)))
	cc.finish_zoom()
	return (
		"ghost: eye %s plank %s (%.1f m) token %s (%.1f m from the eye) off %.0f occl %s fade %s"
		% [str(_spot), str(tree_xz), tree_xz.distance_to(_spot), str(token_xz),
			token_xz.distance_to(_spot), float(step.get("off", 0.0)),
			str(bool(step.get("occl", false))), str(CanopyFade.eye_fade_enabled)]
	)


## A plank 14 m tall (from 2 m below `ground_y`, to cover a slope), `width` wide and 0.5 m thick
## across `dir`, standing at `xz` in the map container; with `occl` the occlusion fade takes its material as a map surface.
static func _plank(
	gm: GameMap, xz: Vector2, ground_y: float, dir: Vector2, step: Dictionary
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(step.get("width", 6.0)), 14.0, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.42, 0.3)
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.name = "EyeCanopyPlank"
	mi.mesh = mesh
	gm.map_container.add_child(mi)
	mi.global_position = Vector3(xz.x, ground_y + 5.0, xz.y)
	mi.look_at(mi.global_position + Vector3(dir.x, 0.0, dir.y), Vector3.UP)
	if bool(step.get("occl", false)) and gm.occlusion_fade != null:
		gm.occlusion_fade._convert_mesh_materials(mi)
	return mi


static func _report(gm: GameMap) -> String:
	var cam := gm.camera_node
	return (
		"report: camera %s fov %.1f eye global %s near_fade %s"
		% [str(cam.global_position.snapped(Vector3.ONE * 0.01)), cam.fov,
			str(CanopyFade._last_eye), str(CanopyFade.eye_fade_enabled)]
	)
