extends SceneTree

## Deterministic camera trace: drives the real GameMap camera rig through a fixed scripted sequence
## through the controller's public API and writes the state after every step, so two trees (or a
## refactor and its parent) can be compared number by number instead of by pixels.
##
## Run with fixed engine frames so every Tween and `_process` sees exactly 1/60 s:
##   godot --headless --path <tree> --fixed-fps 60 --script res://tools/camera_trace.gd -- <out.txt>
## Compare two traces (line count and the largest absolute difference of any number):
##   godot --headless --path <tree> --script res://tools/camera_trace.gd -- --compare A.txt B.txt
##
## Each trace line is `<map> <step> | key=value ...` with the Camera3D's global transform, size,
## near and far, the holder's global transform, the view's yaw and pitch (drawn and target), the
## pivot (ground point under the screen centre), the pan bounds and fit size, and whether the
## camera is at rest. The sequence: home; W then A for 30 frames; zoom in 3 and out 3; snap turns
## Q, E and four more; set pitch 45, 70, 90 and the O toggle from 45 and 70; an Alt + drag free
## yaw of 30 degrees; Home; W and D held into the bounds; edge pan right and up. Run on two maps'
## bounds (square, and narrow and tall) so the clamp and the recentre both act. Everything uses
## names that exist both before and after the ViewMode split (call / get on the controller's old
## private names).

## Loaded at run time and held in untyped Node variables: a --script main loop compiles before the
## autoloads exist, so naming GameMap or CameraController here would fail to compile.
const GAME_MAP_SCENE := "res://scenes/states/playing/game_map.tscn"
const PLAY_CONTROLLER := "res://scenes/states/playing/level_play_controller.gd"
const MAPS := {
	"square": AABB(Vector3(-38.0, 0.0, -38.0), Vector3(76.0, 8.0, 76.0)),
	"narrow": AABB(Vector3(-30.0, 0.0, -14.0), Vector3(60.0, 12.0, 28.0)),
}

var _out: PackedStringArray = PackedStringArray()
var _map_name: String = ""
var _gm: Node = null
var _cc: Node = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 3 and args[0] == "--compare":
		_compare(args[1], args[2])
		quit()
		return
	_run(args[0] if args.size() > 0 else "user://camera_trace.txt")


func _run(path: String) -> void:
	await process_frame
	for map_name in MAPS:
		_map_name = map_name
		await _build(MAPS[map_name])
		await _sequence()
		_gm.queue_free()
		await process_frame
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(_out) + "\n")
	file.close()
	print("camera_trace: %d lines -> %s" % [_out.size(), path])
	quit()


func _build(bounds: AABB) -> void:
	var controller: Node = (load(PLAY_CONTROLLER) as GDScript).new()
	root.add_child(controller)
	_gm = (load(GAME_MAP_SCENE) as PackedScene).instantiate()
	var stand_in := Node.new()
	root.add_child(stand_in)
	current_scene = stand_in
	root.add_child(_gm)
	current_scene = null
	stand_in.free()
	await process_frame
	controller.setup(_gm)
	_gm.setup(controller)
	_cc = _gm.get_camera_controller()
	_cc.set_map_bounds(bounds)
	_cc.record_mouse_position(Vector2(1300.0, 380.0))
	await process_frame


func _sequence() -> void:
	_rec("home")
	await _hold("camera_move_forward", 30, "W")
	await _hold("camera_move_left", 30, "A")
	await _rest("pan_rest")
	for i in 3:
		_cc.zoom_in_step()
	await _rest("zoom_in")
	for i in 3:
		_cc.zoom_out_step()
	await _rest("zoom_out")
	for dir in [-1, 1, 1, 1, 1, 1]:
		_cc.turn_view(dir)
		await _rest("snap %d" % dir)
	for pitch in [45.0, 70.0, 90.0, 21.6]:
		_cc.set_pitch_now(pitch)
		_rec("pitch_now %.1f" % pitch)
	for start in [45.0, 70.0]:
		_cc.set_pitch_now(start)
		_cc.call("_unhandled_key_input", _key(KEY_O))
		await _rest("O from %.0f" % start)
		_cc.call("_unhandled_key_input", _key(KEY_O))
		await _rest("O back from %.0f" % start)
	_gm._input(_button(true))
	_gm._input(_motion(Vector2(-100.0, 0.0)))
	_gm._input(_motion(Vector2(0.0, 40.0)))
	_gm._input(_button(false, false))
	_rec("alt_drag yaw+30 pitch+8")
	var home := InputEventAction.new()
	home.action = "camera_reset"
	home.pressed = true
	_cc.call("_unhandled_key_input", home)
	await _rest("Home")
	await _hold("camera_move_forward", 240, "W into bounds")
	await _rest("W rest")
	await _hold("camera_move_right", 240, "D into bounds")
	await _rest("D rest")
	await _edge_pan(Vector2(1.0, 0.0), 30, "edge right")
	await _edge_pan(Vector2(0.0, -1.0), 30, "edge up")
	await _rest("edge rest")


## Holds an action for `frames` frames (a record every 10), then releases it.
func _hold(action: String, frames: int, label: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	_cc.call("_unhandled_key_input", press)
	for i in frames:
		await process_frame
		if (i + 1) % 10 == 0:
			_rec("hold %s %d" % [label, i + 1])
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	_cc.call("_unhandled_key_input", release)


func _edge_pan(direction: Vector2, frames: int, label: String) -> void:
	var dnd: Object = _gm.get("drag_and_drop_node")
	var subject := Node.new()
	var state: Object = dnd.get("_state")
	state.begin(subject)
	dnd.edge_pan_direction = direction
	for i in frames:
		await process_frame
		if (i + 1) % 10 == 0:
			_rec("%s %d" % [label, i + 1])
	state.finish()
	subject.free()


## Frames until the camera is at rest (at most 400), then a record that includes the count.
func _rest(label: String) -> void:
	var frames := 0
	while not _cc.is_at_rest() and frames < 400:
		await process_frame
		frames += 1
	_rec("%s rest_frames %d" % [label, frames])


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _button(pressed: bool, alt: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.alt_pressed = alt
	return event


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


func _tf(t: Transform3D) -> String:
	return "o=%s bx=%s by=%s bz=%s" % [_v3(t.origin), _v3(t.basis.x), _v3(t.basis.y), _v3(t.basis.z)]


func _v3(v: Vector3) -> String:
	return "%.9f,%.9f,%.9f" % [v.x, v.y, v.z]


func _rec(step: String) -> void:
	var cam: Camera3D = _gm.get("camera_node")
	var holder: Node3D = _gm.get("cameraholder_node")
	var off: Vector2 = _cc.call("_get_view_center_ground_offset")
	var bounds: AABB = _cc.get("_map_bounds")
	var line := "%s %s | cam %s size=%.9f near=%.9f far=%.9f" % [
		_map_name, step, _tf(cam.global_transform), cam.size, cam.near, cam.far
	]
	line += " | holder %s" % _tf(holder.global_transform)
	var view: Object = _cc.view()
	line += " | yaw=%.9f yaw_target=%.9f pitch=%.9f pitch_target=%.9f" % [
		_cc.current_yaw(), view.yaw.target, _cc.current_pitch(), view.pitch.target
	]
	line += " | pivot=%.9f,%.9f" % [holder.global_position.x + off.x, holder.global_position.z + off.y]
	line += " | bounds=%s,%s fit=%.9f rest=%s" % [
		_v3(bounds.position), _v3(bounds.size), float(_cc.get("_fit_size")), str(_cc.is_at_rest())
	]
	_out.append(line)


func _numbers(line: String) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var regex := RegEx.new()
	regex.compile("-?\\d+\\.?\\d*(?:e-?\\d+)?|inf")
	for m in regex.search_all(line):
		var s := m.get_string()
		found.append(INF if s == "inf" else s.to_float())
	return found


func _compare(path_a: String, path_b: String) -> void:
	var a := FileAccess.get_file_as_string(path_a).strip_edges().split("\n")
	var b := FileAccess.get_file_as_string(path_b).strip_edges().split("\n")
	var worst := 0.0
	var bad := 0
	var count := mini(a.size(), b.size())
	if a.size() != b.size():
		print("LINE COUNT DIFFERS: %d vs %d" % [a.size(), b.size()])
		bad += 1
	for i in count:
		var na := _numbers(a[i])
		var nb := _numbers(b[i])
		var text_a := a[i].get_slice("|", 0)
		var text_b := b[i].get_slice("|", 0)
		if na.size() != nb.size() or text_a != text_b or a[i].contains("rest=") != b[i].contains("rest="):
			print("line %d STRUCTURE DIFFERS:\n  %s\n  %s" % [i + 1, a[i], b[i]])
			bad += 1
			continue
		var worst_line := 0.0
		for k in na.size():
			if is_inf(na[k]) and is_inf(nb[k]):
				continue
			worst_line = maxf(worst_line, absf(na[k] - nb[k]))
		if worst_line > 1e-6:
			print("line %d differs by %.9f: %s" % [i + 1, worst_line, a[i].left(60)])
			bad += 1
		worst = maxf(worst, worst_line)
	print("compared %d lines, max abs diff %.12f, %d differing lines" % [count, worst, bad])
