extends RefCounted

## Render-job probe for the eyelook round (card SR10, docs/plans/2026-11-02-camera):
## the eye view with avatar tokens in the scene and the hint bar filled, as a player sees them.
##   tokens {dir, at, tokens, hints, views}
##       `tokens` is [[x, z], ...], `hints` [[key, action], ...], `views` [{name, yaw, pitch}].
##       Enters the eye at `at`, spawns an avatar token at each ground point, adds the hints
##       to the bar, then for each view sets the pose and saves the composited window (full
##       size) as <dir>/<name>.png.
##   await                 holds the job while the rig runs.

const GROUP := "eye_look_rig"


static func blocker(base: Node, _step: Dictionary) -> String:
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the eye look rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var rig := LookRig.new()
	rig.gm = base.get("_game_map")
	rig.lpc = base.get("_level_play_controller")
	rig.step = step
	base.get_tree().root.add_child(rig)
	return "%s started" % action


class LookRig:
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
		var dir := ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/eye_look")))
		DirAccess.make_dir_recursive_absolute(dir)
		var cc := gm.get_camera_controller()
		cc.set_view_mode(cc.eye)
		var at: Array = step.get("at", [0, 0])
		cc.eye.frame_ground(Vector2(float(at[0]), float(at[1])), 0.0)
		cc.finish_zoom()
		await _frames(40)
		for p in step.get("tokens", []):
			lpc.spawn_avatar(AvatarPresets.recipe(0), "eyelook", _ground(float(p[0]), float(p[1])))
		await _frames(150)
		for h in step.get("hints", []):
			UIManager.add_hint(String(h[0]), String(h[1]))
		await _frames(10)
		for view in step.get("views", []):
			cc.set_yaw_now(float(view.yaw))
			cc.set_pitch_now(float(view.pitch))
			await _frames(30)
			await RenderingServer.frame_post_draw
			var path := dir.path_join(String(view.name) + ".png")
			get_tree().root.get_texture().get_image().save_png(path)
			print("RJ| eye_look window %s" % path)
		UIManager.clear_hints()
		print("RJ| eye_look tokens done")
		queue_free()
