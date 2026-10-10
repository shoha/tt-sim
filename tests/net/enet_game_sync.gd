extends "res://tests/net/enet_late_joiner.gd"

## ENet check for NetworkGameSync, the table-play RPCs at /root/NetworkManager/GameSync.
## After a late join (enet_late_joiner.gd's boot, ENet setup and rendezvous, reused here),
## the host gives the client CONTROL of one token; the client moves it (drag-lock claim,
## transform, release) and the host broadcasts the token's resting position (a single
## transform or a batch); then the host renames that token, removes a second one and
## changes a visual setting. Each side logs every message arriving and passes only when all
## of them arrived from the right sender with the expected effect, including the host's own
## copy of the token locking through the merged grant path (grant_drag_lock ->
## drag_lock_granted).
##
## Run through tests/net/net_launcher.gd with --scenario=enet_game_sync (its default
## --timeout-s of 180 is enough). The host waits on the client's ".client.json" stages and
## the client on the host's ".host.json" phase, as in enet_late_joiner.gd.

const MOVE_TARGET := Vector3(1.5, 0.25, -2.0)
const NEW_NAME := "Moved Hero"
const LIGHT := 0.42
const RESEND_MS := 200

var _removable_id := ""
var _client_peer := 0
## What each side has seen arrive: event name -> sender, value or count
var _seen: Dictionary = {}
var _last_send_ms := 0


func _set_phase(phase: String) -> void:
	_phase = phase
	_log("phase " + phase)
	if _role == "host":
		_write_json(
			_rv + ".host.json", {"phase": phase, "avatar": _avatar_id, "removable": _removable_id}
		)


# =============================================================================
# HOST
# =============================================================================


func _process_host() -> void:
	match _phase:
		"table":
			var client := _read_json(_rv + ".client.json")
			if client.get("stage", "") == "ready":
				_grant_control(int(client.get("peer_id", 0)))
		"granted":
			if _seen.has("claim") and _seen.has("transform"):
				_check_host_move()
		"moved_seen":
			if _seen.has("release"):
				_host_changes()
		"host_changes":
			var client := _read_json(_rv + ".client.json")
			if client.get("stage", "") == "done":
				_result["client"] = client
				var ok := bool(client.get("pass", false)) and _host_checks_pass()
				_finish(ok, "client reported")
		_:
			super._process_host()


func _host_place_avatar() -> void:
	var lpc := _lpc()
	var movable := lpc.spawn_avatar({"format": 1}, "Late Hero", Vector3.UP * 30, true)
	var removable := lpc.spawn_avatar({"format": 1}, "Doomed Hero", Vector3(3, 30, 0), true)
	if movable == null or removable == null:
		_finish(false, "avatar spawn failed")
		return
	_avatar_id = movable.network_id
	_removable_id = removable.network_id
	_result["avatar_id"] = _avatar_id
	_result["removable_id"] = _removable_id
	var game_sync := NetworkManager.game_sync
	game_sync.client_drag_lock_claimed.connect(_on_host_claim)
	game_sync.drag_lock_granted.connect(_on_host_granted)
	game_sync.client_token_transform_received.connect(_on_host_transform)
	game_sync.client_drag_lock_released.connect(_on_host_release)
	_log("tokens %s (to move) and %s (to remove) placed" % [_avatar_id, _removable_id])
	_set_phase("table")


func _on_host_claim(sender_id: int, network_id: String) -> void:
	_log("host: drag lock claim from peer %d for %s" % [sender_id, network_id])
	_seen["claim"] = sender_id


func _on_host_granted(network_id: String, locker_peer_id: int) -> void:
	_log("host: drag_lock_granted %s to peer %d (host-local emit)" % [network_id, locker_peer_id])
	_seen["granted"] = locker_peer_id


func _on_host_transform(
	sender_id: int, network_id: String, pos: Vector3, _rot: Vector3, _scl: Vector3
) -> void:
	_log("host: transform from peer %d for %s at %s" % [sender_id, network_id, str(pos)])
	_seen["transform"] = sender_id


func _on_host_release(sender_id: int, network_id: String) -> void:
	_log("host: drag lock release from peer %d for %s" % [sender_id, network_id])
	_seen["release"] = sender_id


func _grant_control(peer_id: int) -> void:
	_client_peer = peer_id
	GameState.grant_token_permission(_avatar_id, peer_id, TokenPermissions.Permission.CONTROL)
	NetworkManager.permissions.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)
	_log("host: CONTROL on %s granted to peer %d" % [_avatar_id, peer_id])
	_set_phase("granted")


func _check_host_move() -> void:
	var token := _lpc().find_token_by_network_id(_avatar_id)
	var state := GameState.get_token_state(_avatar_id)
	_result["host_claim_sender_ok"] = _seen["claim"] == _client_peer
	_result["host_granted_peer_ok"] = _seen.get("granted", 0) == _client_peer
	_result["host_lock_holder_ok"] = GameState.get_drag_lock(_avatar_id) == _client_peer
	_result["host_token_locked_ok"] = token._drag_locked_by == _client_peer
	_result["host_transform_sender_ok"] = _seen["transform"] == _client_peer
	_result["host_position_ok"] = state.position.is_equal_approx(MOVE_TARGET)
	_log("host: move checks %s" % str(_result))
	_set_phase("moved_seen")


func _host_changes() -> void:
	var lpc := _lpc()
	var movable := lpc.find_token_by_network_id(_avatar_id)
	_result["host_release_sender_ok"] = _seen["release"] == _client_peer
	_result["host_lock_released_ok"] = GameState.get_drag_lock(_avatar_id) == 0
	_result["host_token_unlocked_ok"] = movable._drag_locked_by == 0
	lpc.rename_token(movable, NEW_NAME)
	_log("host: renamed %s to %s" % [_avatar_id, NEW_NAME])
	_result["host_removed_ok"] = lpc.remove_token(lpc.find_token_by_network_id(_removable_id))
	_log("host: removed %s" % _removable_id)
	NetworkManager.game_sync.broadcast_visual_settings({"light_intensity": LIGHT})
	var snapshot: Dictionary = NetworkManager.get("_current_level_dict")
	_result["host_snapshot_light_ok"] = is_equal_approx(
		float(snapshot.get("light_intensity_scale", -1.0)), LIGHT
	)
	_log("host: light_intensity %s broadcast" % str(LIGHT))
	_set_phase("host_changes")


func _host_checks_pass() -> bool:
	for key in _result:
		if str(key).begins_with("host_") and not bool(_result[key]):
			return false
	return true


# =============================================================================
# CLIENT
# =============================================================================


func _process_client() -> void:
	match _phase:
		"joined":
			_client_ready_check()
		"ready":
			var control := TokenPermissions.Permission.CONTROL
			if GameState.has_token_permission(_avatar_id, _my_peer(), control):
				_log("client: CONTROL on %s; claiming the drag lock" % _avatar_id)
				NetworkManager.game_sync.send_drag_lock_claim(_avatar_id)
				_set_phase("claiming")
		"claiming":
			if _seen.get("granted", 0) == _my_peer():
				_set_phase("moving")
		"moving":
			if _read_json(_rv + ".host.json").get("phase", "") == "moved_seen":
				_log("client: host saw the move; releasing the drag lock")
				NetworkManager.game_sync.send_drag_lock_release(_avatar_id)
				_set_phase("releasing")
			elif Time.get_ticks_msec() - _last_send_ms >= RESEND_MS:
				_send_move()
		"releasing":
			if _seen.has("released"):
				_set_phase("await_host_changes")
		"await_host_changes":
			_client_final_check()
		_:
			super._process_client()


func _my_peer() -> int:
	return multiplayer.get_unique_id()


func _client_ready_check() -> void:
	var host := _read_json(_rv + ".host.json")
	_avatar_id = str(host.get("avatar", ""))
	_removable_id = str(host.get("removable", ""))
	if _avatar_id == "" or _removable_id == "" or not _table_ready():
		return
	var lpc := _lpc()
	if lpc.find_token_by_network_id(_avatar_id) == null:
		return
	if lpc.find_token_by_network_id(_removable_id) == null:
		return
	var game_sync := NetworkManager.game_sync
	game_sync.drag_lock_granted.connect(_on_client_granted)
	game_sync.drag_lock_denied.connect(_on_client_denied)
	game_sync.drag_lock_released.connect(_on_client_released)
	game_sync.token_state_received.connect(_on_client_token_state)
	game_sync.token_removed_received.connect(_on_client_token_removed)
	game_sync.visual_settings_received.connect(_on_client_visual_settings)
	game_sync.token_transform_received.connect(_on_client_transform)
	game_sync.transform_batch_received.connect(_on_client_batch)
	_log("client: both tokens on the board; peer id %d" % _my_peer())
	_write_json(_rv + ".client.json", {"stage": "ready", "peer_id": _my_peer()})
	_set_phase("ready")


func _send_move() -> void:
	var state := TokenState.from_board_token(_lpc().find_token_by_network_id(_avatar_id))
	NetworkManager.game_sync.send_client_token_transform(
		_avatar_id, MOVE_TARGET, state.rotation, state.scale
	)
	_last_send_ms = Time.get_ticks_msec()
	_log("client: sent transform for %s to %s" % [_avatar_id, str(MOVE_TARGET)])


func _on_client_granted(network_id: String, locker_peer_id: int) -> void:
	_log("client: drag_lock_granted %s to peer %d" % [network_id, locker_peer_id])
	if network_id == _avatar_id:
		_seen["granted"] = locker_peer_id


func _on_client_denied(network_id: String) -> void:
	_log("client: drag lock DENIED for %s" % network_id)
	_seen["denied"] = network_id


func _on_client_released(network_id: String) -> void:
	_log("client: drag_lock_released %s" % network_id)
	if network_id == _avatar_id:
		_seen["released"] = true


func _on_client_token_state(network_id: String, token_dict: Dictionary) -> void:
	var token_name := str(token_dict.get("token_name", ""))
	_log("client: token_state_received %s name '%s'" % [network_id, token_name])
	if network_id == _avatar_id and token_name == NEW_NAME:
		_seen["state"] = token_name


func _on_client_token_removed(network_id: String) -> void:
	_log("client: token_removed_received %s" % network_id)
	if network_id == _removable_id:
		_seen["removed"] = true


func _on_client_visual_settings(settings: Dictionary) -> void:
	_log("client: visual_settings_received %s" % str(settings))
	if settings.has("light_intensity"):
		_seen["visual"] = float(settings["light_intensity"])


## Host transforms arrive one by one or batched (NetworkStateSync queues a token sent again
## within its send interval). Either counts once the drag lock is released: the host then
## broadcasts the moved token's resting position to every client.
func _on_client_transform(network_id: String, pos: Vector3, _rot: Vector3, _scl: Vector3) -> void:
	_seen["transforms"] = int(_seen.get("transforms", 0)) + 1
	if network_id == _avatar_id and _seen.has("released"):
		_log("client: token_transform_received %s at %s" % [network_id, str(pos)])
		_seen["host_transform"] = pos


func _on_client_batch(batch: Dictionary) -> void:
	_seen["batches"] = int(_seen.get("batches", 0)) + 1
	if batch.has(_avatar_id) and _seen.has("released"):
		var pos := SerializationUtils.array_to_vec3(batch[_avatar_id].get("position", []))
		_log("client: transform_batch_received with %s at %s" % [_avatar_id, str(pos)])
		_seen["host_transform"] = pos


func _client_final_check() -> void:
	for event in ["state", "removed", "visual", "host_transform"]:
		if not _seen.has(event):
			return
	var lpc := _lpc()
	var movable := lpc.find_token_by_network_id(_avatar_id)
	_result["granted_to_me"] = _seen.get("granted", 0) == _my_peer()
	_result["never_denied"] = not _seen.has("denied")
	_result["released"] = _seen.has("released")
	_result["renamed_on_board"] = movable != null and movable.token_name == NEW_NAME
	_result["removed_from_board"] = lpc.find_token_by_network_id(_removable_id) == null
	_result["light_applied"] = is_equal_approx(lpc.active_level_data.light_intensity_scale, LIGHT)
	_result["host_transforms_received"] = int(_seen.get("transforms", 0))
	_result["host_batches_received"] = int(_seen.get("batches", 0))
	_result["resting_position"] = str(_seen["host_transform"])
	var ok := true
	for key in [
		"granted_to_me",
		"never_denied",
		"released",
		"renamed_on_board",
		"removed_from_board",
		"light_applied"
	]:
		ok = ok and bool(_result[key])
	_result["pass"] = ok
	_result["stage"] = "done"
	_log("client: final checks %s" % str(_result))
	_write_json(_rv + ".client.json", _result)
	_finish(ok, "game sync seen")
