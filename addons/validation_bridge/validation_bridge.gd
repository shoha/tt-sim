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


func _ready() -> void:
	if not "--validation-bridge" in OS.get_cmdline_user_args():
		return
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
		"scene_tree": _get_scene_tree(get_tree().current_scene, 0, SCENE_TREE_MAX_DEPTH),
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

	var nodes := _find_nodes_of_class(root_scene, "DrawerContainer")
	for node in nodes:
		if "is_open" in node:
			result[str(node.name)] = {"open": node.is_open}

	var pause_overlay := root_scene.find_child("PauseOverlay", true, false)
	if pause_overlay:
		result["PauseOverlay"] = {"visible": pause_overlay.visible}

	return result


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


func _find_nodes_of_class(root: Node, class_name_str: String) -> Array[Node]:
	var found: Array[Node] = []
	_find_nodes_of_class_recursive(root, class_name_str, found)
	return found


func _find_nodes_of_class_recursive(node: Node, class_name_str: String, found: Array[Node]) -> void:
	if node.get_class() == class_name_str or (node.get_script() and node is DrawerContainer):
		found.append(node)
	for child in node.get_children():
		_find_nodes_of_class_recursive(child, class_name_str, found)


# ---------------------------------------------------------------------------
# Input injection
# ---------------------------------------------------------------------------


func _cmd_input(cmd: Dictionary) -> Dictionary:
	var input_type: String = cmd.get("type", "")
	match input_type:
		"click":
			var button_str: String = cmd.get("button", "left")
			var button := _parse_mouse_button(button_str)
			_inject_click(cmd.get("x", 0.0), cmd.get("y", 0.0), button)
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
	await get_tree().process_frame
	await get_tree().process_frame
	return {"ok": true}


func _inject_click(x: float, y: float, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var pos := Vector2(x, y)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = pos
	press.global_position = pos
	Input.parse_input_event(press)

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = pos
	release.global_position = pos
	Input.parse_input_event(release)


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

	await get_tree().process_frame

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
		if i < steps:
			await get_tree().process_frame

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	Input.parse_input_event(release)


func _cmd_wait(cmd: Dictionary) -> Dictionary:
	var seconds: float = cmd.get("seconds", 0.5)
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
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
