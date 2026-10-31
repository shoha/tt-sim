extends Node

## Render-job probe (`call` op) for token dragging through real injected input (the drag
## controller's whole path: physics pick on the token, the threshold, the ground ray, the
## smoothing, release, cancel). It uses only what the controller and the old addon share
## (signals, `is_dragging()`, `grid_snap_enabled`, `dragging_enabled`, `edge_pan_enabled`), so
## the same job runs on either and the logs can be diffed. `action`:
##   start {out}   in play on a level with a flat walkable map: spawns two avatars and runs the
##                 scenarios on a helper node over the next seconds (about 25 s). `out` is the
##                 folder (absolute) for the contact sheet.
##   result        the scenario log so far (one line per fact), "running" until it is done.
## Scenarios: click without moving, drag and drop, cancel by right click, cancel by Escape,
## drop onto a grid snap, the wheel height step, drags disabled, and a six-frame contact sheet
## of the first drag.

const THIS := "res://tools/render_jobs/probes/drag_check.gd"
const MOVE_STEPS := 12
const HOLD_FRAMES := 45
const SHEET_FRAMES: Array[int] = [1, 4, 8, 12, 17, 23]

static var _lines: PackedStringArray = PackedStringArray()
static var _done: bool = false

var _gm: GameMap
var _dnd: Node3D
var _cursor: Vector2 = Vector2.ZERO
var _events: PackedStringArray = PackedStringArray()
var _out: String = ""


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "result")):
		"start":
			var gm: GameMap = base.get("_game_map")
			var lpc: LevelPlayController = base.get("_level_play_controller")
			_lines = PackedStringArray()
			_done = false
			var runner := (load(THIS) as GDScript).new() as Node
			base.get_tree().root.add_child(runner)
			runner.call("_scenarios", gm, lpc, String(step.get("out", "user://render_jobs/drag_check")))
			return "started"
		"result":
			if not _done:
				return "running (%d lines)" % _lines.size()
			return "\n" + "\n".join(_lines)
	return "unknown action"


func _say(text: String) -> void:
	_lines.append("[f%d] %s" % [Engine.get_process_frames(), text])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _tokens() -> Array[BoardToken]:
	var out: Array[BoardToken] = []
	for node in get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
		out.append(node as BoardToken)
	return out


func _screen_of(token: BoardToken) -> Vector2:
	var shape: Node3D = token.get_dragging_object().collision_shape
	return _gm.camera_node.unproject_position(shape.global_position)


func _mask() -> int:
	var value: Variant = _dnd.get("collisionMask")
	if value == null:
		value = _dnd.get("collision_mask")
	return int(value)


## The ground point under a screen point, the way the controller's ray finds it.
func _ground_at(screen: Vector2, token: BoardToken) -> Vector3:
	var cam := _gm.camera_node
	var query := PhysicsRayQueryParameters3D.create(
		cam.project_ray_origin(screen), cam.project_position(screen, 100.0), _mask()
	)
	query.collide_with_areas = true
	query.exclude = [token.rigid_body.get_rid()]
	var hit := _gm.world_viewport.find_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## What the controller thinks the target is (the old addon's privates, or the controller's getters).
func _target_info() -> String:
	var has: Variant = _dnd.get("_has_target_position")
	var target: Variant = _dnd.get("_target_drag_position")
	if has == null:
		has = _dnd.call("has_target")
		target = _dnd.call("get_target_position")
	var vp := _dnd.get_viewport()
	var camera := vp.get_camera_3d()
	return "has_target %s target %s viewport %s camera %s mouse %s" % [str(has), str(target), str(vp.get_visible_rect().size), str(camera != null), str(vp.get_mouse_position())]


func _fmt(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _move(pos: Vector2, mask: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.relative = pos - _cursor
	motion.button_mask = mask
	_cursor = pos
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func _button(pos: Vector2, index: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _press_on(token: BoardToken) -> Vector2:
	var at := _screen_of(token)
	_say("press: pickable %s busy %s" % [str(token.rigid_body.input_ray_pickable), str(token.get_dragging_object().is_being_dragged())])
	_move(at, 0)
	await _frames(2)
	_button(at, MOUSE_BUTTON_LEFT, true)
	await get_tree().physics_frame
	await _frames(2)
	return at


func _drag_to(from: Vector2, to: Vector2) -> void:
	for i in range(1, MOVE_STEPS + 1):
		_move(from.lerp(to, float(i) / float(MOVE_STEPS)), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)


func _settle(token: BoardToken) -> void:
	await _frames(20)
	var guard := 0
	while token.get_dragging_object().is_being_dragged() and guard < 240:
		await _frames(1)
		guard += 1
	await _frames(10)


func _body(token: BoardToken) -> Vector3:
	return token.rigid_body.global_position


func _scenarios(gm: GameMap, lpc: LevelPlayController, out: String) -> void:
	_gm = gm
	_dnd = gm.drag_and_drop_node
	_out = out
	_dnd.dragging_started.connect(func(_o: Variant) -> void: _events.append("started"))
	_dnd.dragging_stopped.connect(func(_o: Variant) -> void: _events.append("stopped"))
	_dnd.dragging_cancelled.connect(func(_o: Variant) -> void: _events.append("cancelled"))
	_dnd.set("edge_pan_enabled", false)
	var spawn_at := Vector3(0, 0, 0)
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(Vector3(0, 60, 0), Vector3(0, -60, 0), _mask())
	var hit := space.intersect_ray(down)
	if not hit.is_empty():
		spawn_at.y = hit["position"].y
	var token := lpc.spawn_avatar(AvatarPresets.recipe(0), "dragprobe", spawn_at)
	if token == null:
		_say("spawn failed")
		_done = true
		return
	await _frames(150)
	_say("token at %s mask %d grid_snap %s" % [_fmt(_body(token)), _mask(), str(_dnd.get("grid_snap_enabled"))])
	_gm.camera_node.get_viewport().gui_release_focus()

	# 1. A click that never moves is not a drag.
	_events.clear()
	var start := _body(token)
	var at := await _press_on(token)
	_move(at + Vector2(2, 1), MOUSE_BUTTON_MASK_LEFT)
	await _frames(2)
	_button(at + Vector2(2, 1), MOUSE_BUTTON_LEFT, false)
	await _frames(10)
	_say("click: events %s dragging %s moved %.4f" % [str(_events), str(_dnd.call("is_dragging")), start.distance_to(_body(token))])

	# 2. Drag and drop, with the contact sheet.
	_events.clear()
	start = _body(token)
	at = await _press_on(token)
	var target := at + Vector2(240, 130)
	var expected := _ground_at(target, token)
	_say("drag: start %s screen %s target screen %s expected ground %s" % [_fmt(start), str(at), str(target), _fmt(expected)])
	await _drag_to(at, target)
	_say("drag: events %s dragging %s" % [str(_events), str(_dnd.call("is_dragging"))])
	var curve := PackedStringArray()
	for _f in HOLD_FRAMES:
		await _frames(1)
		var d := _body(token)
		curve.append("%.2f" % Vector2(d.x - expected.x, d.z - expected.z).length())
	_say("drag: body-to-target xz distance per frame after the cursor stops: %s" % ", ".join(curve))
	_say("drag: body held at %s (expected ground %s) %s" % [_fmt(_body(token)), _fmt(expected), _target_info()])
	_button(target, MOUSE_BUTTON_LEFT, false)
	await _settle(token)
	var landed := _body(token)
	_say("drag: events %s final %s xz error %.4f" % [str(_events), _fmt(landed), Vector2(landed.x - expected.x, landed.z - expected.z).length()])

	# 3. Cancel by right click: the token returns to where the drag began. The held frames
	# make the contact sheet and the body's path.
	_events.clear()
	start = _body(token)
	at = await _press_on(token)
	target = at + Vector2(-220, 60)
	await _drag_to(at, target)
	var sheet: Array[Image] = []
	var path := PackedStringArray()
	for f in 24:
		await _frames(1)
		var b := _body(token)
		path.append("(%.2f %.2f %.2f)" % [b.x, b.y, b.z])
		if f in SHEET_FRAMES:
			sheet.append(_crop_around(get_viewport().get_texture().get_image(), token))
	_say("cancel-rmb: body path while held, frame by frame: %s" % " ".join(path))
	_save_sheet(sheet)
	_say("cancel-rmb: mid-drag body %s dragging %s" % [_fmt(_body(token)), str(_dnd.call("is_dragging"))])
	_button(target, MOUSE_BUTTON_RIGHT, true)
	await _frames(1)
	_button(target, MOUSE_BUTTON_RIGHT, false)
	_button(target, MOUSE_BUTTON_LEFT, false)
	await _settle(token)
	_say("cancel-rmb: events %s dragging %s final %s start %s error %.4f" % [str(_events), str(_dnd.call("is_dragging")), _fmt(_body(token)), _fmt(start), start.distance_to(_body(token))])

	# 4. Cancel by Escape.
	_events.clear()
	start = _body(token)
	at = await _press_on(token)
	target = at + Vector2(100, -120)
	await _drag_to(at, target)
	await _frames(10)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	Input.flush_buffered_events()
	await _frames(1)
	_button(target, MOUSE_BUTTON_LEFT, false)
	await _settle(token)
	_say("cancel-esc: events %s final %s error %.4f" % [str(_events), _fmt(_body(token)), start.distance_to(_body(token))])

	# 5. Drop onto a grid snap: the token lands on a cell centre.
	_dnd.set("grid_snap_enabled", true)
	_dnd.set("grid_cell_size", 1.524)
	_dnd.set("grid_origin", Vector2.ZERO)
	_events.clear()
	at = await _press_on(token)
	target = at + Vector2(-150, 90)
	expected = _ground_at(target, token)
	var snapped := ScaleUtils.snap_to_grid(expected, 1.524, Vector2.ZERO)
	await _drag_to(at, target)
	await _frames(30)
	_button(target, MOUSE_BUTTON_LEFT, false)
	await _settle(token)
	landed = _body(token)
	_say("snap: raw ground %s snapped cell centre %s final %s xz error %.4f events %s" % [_fmt(expected), _fmt(snapped), _fmt(landed), Vector2(landed.x - snapped.x, landed.z - snapped.z).length(), str(_events)])
	_dnd.set("grid_snap_enabled", false)

	# 6. The wheel raises and lowers the held token by the height step (0.25 per notch).
	_events.clear()
	at = await _press_on(token)
	target = at + Vector2(60, 40)
	await _drag_to(at, target)
	await _frames(40)
	var y0 := _body(token).y
	for _i in 2:
		_wheel(target, MOUSE_BUTTON_WHEEL_UP)
		await _frames(1)
	await _frames(40)
	var y_up := _body(token).y
	for _i in 2:
		_wheel(target, MOUSE_BUTTON_WHEEL_DOWN)
		await _frames(1)
	await _frames(40)
	var y_down := _body(token).y
	_button(target, MOUSE_BUTTON_LEFT, false)
	await _settle(token)
	_say("wheel: y held %.3f, after 2 up %.3f (delta %.3f), after 2 down %.3f (delta %.3f) events %s" % [y0, y_up, y_up - y0, y_down, y_down - y_up, str(_events)])

	# 7. Drags disabled (the measure tool): a press and a move start nothing.
	_dnd.set("dragging_enabled", false)
	_events.clear()
	start = _body(token)
	at = await _press_on(token)
	await _drag_to(at, at + Vector2(90, 40))
	_button(at + Vector2(90, 40), MOUSE_BUTTON_LEFT, false)
	await _frames(20)
	_say("disabled: events %s moved %.4f" % [str(_events), start.distance_to(_body(token))])
	_dnd.set("dragging_enabled", true)

	_say("done")
	_done = true
	queue_free()


## A 480x270 window of the frame centred on the token (clamped to the frame), so the contact
## sheet shows the token's trail at a readable size.
func _crop_around(frame: Image, token: BoardToken) -> Image:
	var centre := _gm.camera_node.unproject_position(_body(token))
	var size := Vector2i(480, 270)
	var corner := Vector2i(int(centre.x) - size.x / 2, int(centre.y) - size.y / 2)
	corner.x = clampi(corner.x, 0, frame.get_width() - size.x)
	corner.y = clampi(corner.y, 0, frame.get_height() - size.y)
	return frame.get_region(Rect2i(corner, size))


func _wheel(pos: Vector2, index: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Six frames of the first drag as one image, three across: the token trailing the cursor.
func _save_sheet(frames: Array[Image]) -> void:
	if frames.is_empty():
		return
	var w := 640
	var h := 360
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var img := frames[i]
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var path := _out.path_join("drag_sheet.png")
	sheet.save_png(path)
	_say("contact sheet saved: %s" % ProjectSettings.globalize_path(path))
