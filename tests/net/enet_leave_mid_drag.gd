extends "res://tests/net/enet_late_joiner.gd"

## ENet check that a client who leaves mid-drag frees its drag lock everywhere, the host's
## own copy of the token included. After a late join (enet_late_joiner.gd's boot, ENet setup
## and rendezvous, reused here), the host gives the client CONTROL of the avatar; the client
## claims the drag lock and keeps sending transforms (a drag in progress), then leaves
## without releasing it, through NetworkManager.disconnect_game() as quitting the game does.
##
## The host passes when, after the client's player_left: the lock is free in GameState,
## drag_lock_released fired on the host itself (NetworkGameSync.release_drag_lock()), its
## copy of the token is no longer locked to the departed peer and allows dragging again,
## and a GM drag of that token claims and releases the lock (DraggableToken's own claim
## and release, what a mouse drag sends). Before release_drag_lock() the host's copy stayed
## locked to the departed peer and the GM could not pick the token up.
##
## Run through the launcher (tests/net/net_launcher.gd) with --scenario=enet_leave_mid_drag.

const MOVE_TARGET := Vector3(-1.0, 0.25, 1.5)
const RESEND_MS := 200

var _client_peer := 0
## What each side has seen arrive: event name -> sender, value or count
var _seen: Dictionary = {}
var _last_send_ms := 0


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
				_check_mid_drag()
		"mid_drag":
			if _seen.has("left"):
				_check_after_leave()
		_:
			super._process_host()


func _host_place_avatar() -> void:
	var game_sync := NetworkManager.game_sync
	game_sync.client_drag_lock_claimed.connect(
		func(sender_id: int, network_id: String):
			_log("host: drag lock claim from peer %d for %s" % [sender_id, network_id])
			_seen["claim"] = sender_id
	)
	game_sync.client_token_transform_received.connect(
		func(sender_id: int, network_id: String, pos: Vector3, _rot: Vector3, _scl: Vector3):
			if not _seen.has("transform"):
				_log("host: transform from peer %d for %s at %s" % [sender_id, network_id, pos])
			_seen["transform"] = sender_id
	)
	game_sync.drag_lock_released.connect(
		func(network_id: String):
			_log("host: drag_lock_released %s (host-local emit)" % network_id)
			_seen["released_here"] = network_id
	)
	NetworkManager.player_left.connect(_on_host_player_left)
	super._host_place_avatar()


func _on_host_player_left(peer_id: int, _info: Dictionary) -> void:
	_log("host: peer %d left in phase %s" % [peer_id, _phase])
	if peer_id == _client_peer:
		_seen["left"] = peer_id


func _grant_control(peer_id: int) -> void:
	_client_peer = peer_id
	GameState.grant_token_permission(_avatar_id, peer_id, TokenPermissions.Permission.CONTROL)
	NetworkManager.permissions.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)
	_log("host: CONTROL on %s granted to peer %d" % [_avatar_id, peer_id])
	_set_phase("granted")


## The client holds the lock and is moving the token: the host's copy must be locked to it.
func _check_mid_drag() -> void:
	var token := _lpc().find_token_by_network_id(_avatar_id)
	if token == null or token._dragging_object == null:
		_finish(false, "avatar or its DraggableToken missing on the host mid-drag")
		return
	_result["host_locked_mid_drag_ok"] = (
		GameState.get_drag_lock(_avatar_id) == _client_peer
		and token._drag_locked_by == _client_peer
	)
	_result["host_drag_blocked_mid_drag_ok"] = not token._dragging_object.dragging_allowed
	_log("host: mid-drag checks %s" % str(_result))
	_set_phase("mid_drag")


func _check_after_leave() -> void:
	var token := _lpc().find_token_by_network_id(_avatar_id)
	if token == null or token._dragging_object == null:
		_finish(false, "avatar or its DraggableToken missing on the host after the leave")
		return
	var draggable := token._dragging_object
	_result["host_lock_freed_ok"] = GameState.get_drag_lock(_avatar_id) == 0
	_result["host_release_emitted_ok"] = _seen.get("released_here", "") == _avatar_id
	_result["host_token_unlocked_ok"] = token._drag_locked_by == 0
	_result["host_drag_allowed_ok"] = draggable.dragging_allowed
	# The GM picks the token up and puts it down: the claim and release a mouse drag sends.
	draggable._send_drag_lock_claim(_avatar_id)
	_result["host_gm_claim_ok"] = (
		GameState.get_drag_lock(_avatar_id) == 1 and token._drag_locked_by == 1
	)
	draggable._send_drag_lock_release(_avatar_id)
	_result["host_gm_release_ok"] = (
		GameState.get_drag_lock(_avatar_id) == 0 and token._drag_locked_by == 0
	)
	_result["client"] = _read_json(_rv + ".client.json")
	var ok := bool(_result["client"].get("pass", false))
	for key in _result:
		if str(key).begins_with("host_"):
			ok = ok and bool(_result[key])
	_log("host: after-leave checks %s" % str(_result))
	_finish(ok, "client left mid-drag")


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
				_set_phase("dragging")
		"dragging":
			if _read_json(_rv + ".host.json").get("phase", "") == "mid_drag":
				_leave_mid_drag()
			elif Time.get_ticks_msec() - _last_send_ms >= RESEND_MS:
				_send_move()
		_:
			super._process_client()


func _my_peer() -> int:
	return multiplayer.get_unique_id()


func _client_ready_check() -> void:
	_avatar_id = str(_read_json(_rv + ".host.json").get("avatar", ""))
	if _avatar_id == "" or not _table_ready():
		return
	if _lpc().find_token_by_network_id(_avatar_id) == null:
		return
	var game_sync := NetworkManager.game_sync
	game_sync.drag_lock_granted.connect(
		func(network_id: String, locker_peer_id: int):
			_log("client: drag_lock_granted %s to peer %d" % [network_id, locker_peer_id])
			if network_id == _avatar_id:
				_seen["granted"] = locker_peer_id
	)
	game_sync.drag_lock_denied.connect(
		func(network_id: String):
			_log("client: drag lock DENIED for %s" % network_id)
			_seen["denied"] = network_id
	)
	_log("client: avatar on the board; peer id %d" % _my_peer())
	_write_json(_rv + ".client.json", {"stage": "ready", "peer_id": _my_peer()})
	_set_phase("ready")


func _send_move() -> void:
	var state := TokenState.from_board_token(_lpc().find_token_by_network_id(_avatar_id))
	NetworkManager.game_sync.send_client_token_transform(
		_avatar_id, MOVE_TARGET, state.rotation, state.scale
	)
	_last_send_ms = Time.get_ticks_msec()
	_seen["sent"] = int(_seen.get("sent", 0)) + 1


## Leave while still holding the lock: no release goes out, as when a player quits mid-drag.
func _leave_mid_drag() -> void:
	_result["granted_to_me"] = _seen.get("granted", 0) == _my_peer()
	_result["never_denied"] = not _seen.has("denied")
	_result["transforms_sent"] = int(_seen.get("sent", 0))
	var ok: bool = _result["granted_to_me"] and _result["never_denied"]
	_result["pass"] = ok
	_result["stage"] = "left"
	_write_json(_rv + ".client.json", _result)
	_log("client: leaving mid-drag, still holding the lock on %s" % _avatar_id)
	_finish(ok, "left mid-drag")
