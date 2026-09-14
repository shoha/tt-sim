extends Node

## Validation bridge for AI agent self-evaluation.
## Listens on TCP localhost and accepts commands for screenshot capture,
## game state queries, and input injection.
## Only activates when launched with: godot --path . -- --validation-bridge

const PORT: int = 7777
const HOST: String = "127.0.0.1"
const SCENE_TREE_MAX_DEPTH: int = 3
const SCENE_TREE_MAX_CHILDREN: int = 20

var _server: TCPServer = null
var _client: StreamPeerTCP = null
var _buffer: String = ""
var _processing: bool = false
var _active: bool = false
var _frozen: bool = false
var _prefreeze_time_scale: float = 1.0


func _ready() -> void:
	if not "--validation-bridge" in OS.get_cmdline_user_args():
		return
	# Keep polling while the SceneTree is paused. Entering the pause overlay sets
	# get_tree().paused = true (scenes/root.gd), which stops _process on every node using
	# the default inherited process mode -- including this one. The bridge would then stop
	# servicing its socket for as long as the game was paused, so every command after an
	# Escape keypress timed out and the bridge looked hung. That made the entire pause menu,
	# and the settings screen behind it, untestable through this harness.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_active = true
	_server = TCPServer.new()
	var err := _server.listen(PORT, HOST)
	if err != OK:
		push_error(
			"ValidationBridge: Failed to listen on %s:%d: %s" % [HOST, PORT, error_string(err)]
		)
		return
	print("ValidationBridge: Listening on %s:%d" % [HOST, PORT])


func _process(_delta: float) -> void:
	if not _active or _processing:
		return
	_poll_server()


# ---------------------------------------------------------------------------
# TCP server
# ---------------------------------------------------------------------------


func _poll_server() -> void:
	if _server.is_connection_available():
		var new_client := _server.take_connection()
		if _client != null:
			_client.disconnect_from_host()
		_client = new_client
		_buffer = ""
		print("ValidationBridge: Client connected")

	if _client == null:
		return

	_client.poll()
	if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_client = null
		_buffer = ""
		return

	var available := _client.get_available_bytes()
	if available <= 0:
		return

	var result := _client.get_data(available)
	if result[0] != OK:
		return

	_buffer += (result[1] as PackedByteArray).get_string_from_utf8()
	_try_process_command()


func _try_process_command() -> void:
	var newline_idx := _buffer.find("\n")
	if newline_idx == -1:
		return

	var line := _buffer.substr(0, newline_idx)
	_buffer = _buffer.substr(newline_idx + 1)

	var json := JSON.new()
	if json.parse(line) != OK:
		_send_response({"ok": false, "error": "Invalid JSON: %s" % json.get_error_message()})
		return

	var cmd: Dictionary = json.data
	_processing = true
	# _handle_command is async but called without await intentionally.
	# The coroutine starts, suspends at its first await, and resumes on a later frame.
	# The _processing flag (checked in _process) prevents re-entry while the command
	# is in flight. _handle_command sets _processing = false when it completes.
	_handle_command(cmd)


func _handle_command(cmd: Dictionary) -> void:
	var response: Dictionary
	match cmd.get("cmd", ""):
		"screenshot":
			await RenderingServer.frame_post_draw
			response = _cmd_screenshot()
		"state":
			response = _cmd_state()
		"input":
			response = await _cmd_input(cmd)
		"wait":
			response = await _cmd_wait(cmd)
		"freeze":
			response = _cmd_freeze()
		"resume":
			response = _cmd_resume()
		"step":
			response = await _cmd_step(cmd)
		_:
			response = {"ok": false, "error": "Unknown command: %s" % cmd.get("cmd", "")}
	_send_response(response)
	_processing = false


func _send_response(response: Dictionary) -> void:
	if _client == null or _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var json_str := JSON.stringify(response) + "\n"
	_client.put_data(json_str.to_utf8_buffer())


# ---------------------------------------------------------------------------
# Screenshot
# ---------------------------------------------------------------------------


func _cmd_screenshot() -> Dictionary:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return {"ok": false, "error": "Failed to capture viewport"}
	var png_buffer := image.save_png_to_buffer()
	var base64_str := Marshalls.raw_to_base64(png_buffer)
	return {
		"ok": true,
		"width": image.get_width(),
		"height": image.get_height(),
		"png_base64": base64_str,
	}


# ---------------------------------------------------------------------------
# State snapshot
# ---------------------------------------------------------------------------


func _cmd_state() -> Dictionary:
	return {
		"ok": true,
		"app_state": _get_app_state(),
		"tokens": _get_tokens(),
		"ui": _get_ui_state(),
		"camera": _get_camera_state(),
		"viewport": _get_viewport_state(),
		"scene_tree": _get_scene_tree(get_tree().current_scene, 0, SCENE_TREE_MAX_DEPTH),
	}


## Window and viewport geometry, plus which Control the GUI currently considers hovered.
##
## Reported because `window/stretch/aspect="expand"` makes the viewport size depend on the
## window's aspect ratio, so viewport coordinates and window pixels are NOT interchangeable
## unless the two happen to agree. Every performance measurement and every injected click
## depends on knowing which space it is working in, and not reporting it has now caused a
## wrong conclusion in three separate sessions. `hovered_control` is the ground truth for
## whether an injected click actually landed on the Control the caller aimed at.
func _get_viewport_state() -> Dictionary:
	var viewport := get_viewport()
	var visible_size := viewport.get_visible_rect().size
	var hovered := viewport.gui_get_hovered_control()
	return {
		"window_size": [get_window().size.x, get_window().size.y],
		"viewport_size": [int(visible_size.x), int(visible_size.y)],
		"mouse_position": [viewport.get_mouse_position().x, viewport.get_mouse_position().y],
		"hovered_control": hovered.get_path() if hovered != null else "",
	}


func _get_app_state() -> String:
	var root_scene := get_tree().current_scene
	if root_scene == null or not root_scene.has_method("get_current_state"):
		return "UNKNOWN"
	var state_value: int = root_scene.get_current_state()
	var state_names := ["TITLE_SCREEN", "LOBBY_HOST", "LOBBY_CLIENT", "PLAYING", "PAUSED"]
	if state_value >= 0 and state_value < state_names.size():
		return state_names[state_value]
	return "UNKNOWN(%d)" % state_value


func _get_tokens() -> Array:
	var tokens := []
	for network_id: String in GameState.get_all_token_states():
		var ts: TokenState = GameState.get_token_state(network_id)
		if ts == null:
			continue
		(
			tokens
			. append(
				{
					"network_id": network_id,
					"name": ts.token_name,
					"position": _vec3_to_dict(ts.position),
					"rotation": _vec3_to_dict(ts.rotation),
					"visible": ts.is_visible_to_players,
					"health": ts.current_health,
					"max_health": ts.max_health,
					"alive": ts.is_alive,
				}
			)
		)
	return tokens


func _get_ui_state() -> Dictionary:
	var result := {}
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return result

	for node in _find_drawers(root_scene):
		result[str(node.name)] = {"open": node.is_open}

	var pause_overlay := root_scene.find_child("PauseOverlay", true, false)
	if pause_overlay:
		result["PauseOverlay"] = {"visible": pause_overlay.visible}

	return result


func _find_drawers(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	_find_drawers_recursive(node, found)
	return found


func _find_drawers_recursive(node: Node, found: Array[Node]) -> void:
	if node is DrawerContainer:
		found.append(node)
	for child in node.get_children():
		_find_drawers_recursive(child, found)


func _get_camera_state() -> Dictionary:
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return {}
	var game_map := root_scene.find_child("GameMap", true, false)
	if game_map == null:
		return {}
	var camera: Camera3D = game_map.get("camera_node")
	var holder: Node3D = game_map.get("cameraholder_node")
	if camera == null:
		return {}
	var pos: Vector3 = holder.global_position if holder else camera.global_position
	return {
		"position": _vec3_to_dict(pos),
		"zoom": camera.size,
	}


func _get_scene_tree(node: Node, depth: int, max_depth: int) -> Dictionary:
	if node == null:
		return {}
	var result := {
		"name": str(node.name),
		"type": node.get_class(),
	}
	if depth < max_depth:
		var children := []
		var child_nodes := node.get_children()
		var limit := mini(child_nodes.size(), SCENE_TREE_MAX_CHILDREN)
		for i in range(limit):
			children.append(_get_scene_tree(child_nodes[i], depth + 1, max_depth))
		if child_nodes.size() > SCENE_TREE_MAX_CHILDREN:
			(
				children
				. append(
					{
						"name": "... (%d more)" % (child_nodes.size() - SCENE_TREE_MAX_CHILDREN),
						"type": "truncated",
					}
				)
			)
		result["children"] = children
	elif node.get_child_count() > 0:
		result["child_count"] = node.get_child_count()
	return result


# ---------------------------------------------------------------------------
# Input injection
# ---------------------------------------------------------------------------


func _cmd_input(cmd: Dictionary) -> Dictionary:
	var input_type: String = cmd.get("type", "")
	match input_type:
		"click":
			var button_str: String = cmd.get("button", "left")
			var button := _parse_mouse_button(button_str)
			await _inject_click(cmd.get("x", 0.0), cmd.get("y", 0.0), button)
		"drag":
			await _inject_drag(
				cmd.get("x1", 0.0),
				cmd.get("y1", 0.0),
				cmd.get("x2", 0.0),
				cmd.get("y2", 0.0),
			)
		"key":
			_inject_key(cmd.get("key", ""))
		"scroll":
			_inject_scroll(cmd.get("x", 0.0), cmd.get("y", 0.0), cmd.get("delta", 1.0))
		_:
			return {"ok": false, "error": "Unknown input type: %s" % input_type}
	await _advance_one_step()
	await _advance_one_step()
	return {"ok": true}


## Injects a click at a viewport position.
##
## Sends a mouse-motion event first and puts a frame boundary between press and release,
## rather than firing press+release back to back. Both matter for Control nodes: Godot's GUI
## dispatch establishes which control is hovered from mouse motion, and BaseButton only
## emits `pressed` when it saw the press and the release as distinct events. Without them,
## events injected here still reach `_input`/`_unhandled_input` -- so key shortcuts and
## 3D-world clicks worked -- while buttons, checkboxes and other Controls silently ignored
## every click. That cost three separate measurement sessions before it was tracked down.
##
## _inject_drag already had the frame boundary, which is why drags sometimes worked where
## clicks never did.
##
## _inject_drag's own asymmetry was different: unlike _inject_click above, it never called
## flush_buffered_events at all, so its events were left to agile input flushing's own
## delivery point instead of the frame boundaries awaited here. The hypothesis was that this
## explained drags succeeding only intermittently; a 10-iteration before/after measurement in
## this environment did not bear that out (0/10 both ways), so a second cause is still open.
## The flush call stays regardless -- unflushed injected events are nondeterministic on their
## own terms, independent of whether they were the drag's actual failure mode.
func _inject_click(x: float, y: float, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var pos := Vector2(x, y)

	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _advance_one_step()

	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = pos
	press.global_position = pos
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _advance_one_step()

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = pos
	release.global_position = pos
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func _inject_key(key_string: String) -> void:
	var keycode := OS.find_keycode_from_string(key_string)
	if keycode == KEY_NONE:
		push_warning("ValidationBridge: Unknown key: %s" % key_string)
		return
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)

	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)


func _inject_scroll(x: float, y: float, delta: float) -> void:
	var pos := Vector2(x, y)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if delta > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = pos
	event.global_position = pos
	event.factor = absf(delta)
	Input.parse_input_event(event)


func _inject_drag(x1: float, y1: float, x2: float, y2: float) -> void:
	var from := Vector2(x1, y1)
	var to := Vector2(x2, y2)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	Input.parse_input_event(press)
	Input.flush_buffered_events()

	await _advance_one_step()

	var steps := 10
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var pos := from.lerp(to, t)
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.relative = (to - from) / float(steps)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		if i < steps:
			await _advance_one_step()

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	Input.parse_input_event(release)
	Input.flush_buffered_events()


# ---------------------------------------------------------------------------
# Deterministic time control
# ---------------------------------------------------------------------------


## Stops game time by zeroing Engine.time_scale.
##
## At a time scale of 0.0 no physics ticks accumulate, so _physics_process stops being called
## outright, and _process receives a delta of 0.0. Tweens, SceneTreeTimers and AnimationPlayers all
## run on scaled time and therefore stop with it. Rendering continues, so screenshots still work and
## `await get_tree().process_frame` still resolves -- which is what lets the bridge keep injecting
## input and answering commands while the world is held still.
##
## The pre-freeze scale is remembered rather than assumed to be 1.0, so freezing does not quietly
## discard a time scale the game set for itself.
func _cmd_freeze() -> Dictionary:
	if not _frozen:
		_prefreeze_time_scale = Engine.time_scale
		Engine.time_scale = 0.0
		_frozen = true
	return {"ok": true, "frozen": true, "restored_time_scale": _prefreeze_time_scale}


func _cmd_resume() -> Dictionary:
	if _frozen:
		Engine.time_scale = _prefreeze_time_scale
		_frozen = false
	return {"ok": true, "frozen": false, "time_scale": Engine.time_scale}


## Advances game time by an exact number of physics frames, then restores the freeze.
##
## Accepts either `frames` (exact) or `seconds` (converted at the project's tick rate). Stepping
## while not frozen is allowed and simply advances real time, so a caller does not have to freeze
## first for the command to mean something.
func _cmd_step(cmd: Dictionary) -> Dictionary:
	var ticks := Engine.physics_ticks_per_second
	var frames: int = int(cmd.get("frames", 0))
	if frames <= 0:
		frames = BridgeTimeControl.frames_for_duration(float(cmd.get("seconds", 0.0)), ticks)
	if frames <= 0:
		return {"ok": false, "error": "step requires a positive 'frames' or 'seconds'"}
	frames = mini(frames, BridgeTimeControl.MAX_STEP_FRAMES)
	await _advance_physics_frames(frames)
	return {
		"ok": true,
		"frames": frames,
		"seconds": BridgeTimeControl.duration_for_frames(frames, ticks),
		"frozen": _frozen,
	}


## Runs exactly `frames` physics frames, holding the freeze open around them.
##
## The time scale must be lifted before awaiting: at a scale of 0.0 the physics accumulator never
## fills, so `get_tree().physics_frame` would never fire and the await would hang forever.
func _advance_physics_frames(frames: int) -> void:
	var was_frozen := _frozen
	if was_frozen:
		Engine.time_scale = _prefreeze_time_scale
	for _i in range(frames):
		await get_tree().physics_frame
	if was_frozen:
		Engine.time_scale = 0.0


## One unit of progress between injected input events.
##
## While frozen this is a single physics frame of game time; otherwise it is a rendered frame, which
## is what the injectors did before time control existed. Routing both injectors through here is
## what makes a drag reproducible: the motion sequence advances the world by a fixed amount between
## events instead of by however long the host took to render.
func _advance_one_step() -> void:
	if _frozen:
		await _advance_physics_frames(1)
	else:
		await get_tree().process_frame


func _cmd_wait(cmd: Dictionary) -> Dictionary:
	var seconds: float = cmd.get("seconds", 0.5)
	if seconds > 0.0:
		# ignore_time_scale = true: a frozen clock must not stall the bridge's own waits. Callers
		# wanting game time to pass should use "step", which is the deterministic option anyway.
		await get_tree().create_timer(seconds, true, false, true).timeout
	else:
		await get_tree().process_frame
	return {"ok": true}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _parse_mouse_button(button_name: String) -> MouseButton:
	match button_name:
		"right":
			return MOUSE_BUTTON_RIGHT
		"middle":
			return MOUSE_BUTTON_MIDDLE
		_:
			return MOUSE_BUTTON_LEFT
