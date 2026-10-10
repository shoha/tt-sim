class_name LateJoinerSync

## Host side of a late joiner's sync: move the peer into PLAYING, send it the level, and
## hold its full table state (tokens, avatars, permissions, drag locks) until the peer
## reports its table loaded.
##
## The hold is what keeps the state. A client's LevelPlayLoader yields three frames and
## then clear_level() resets GameState, so a state that lands inside that yield is wiped.
## The client used to ACK on mere receipt of the level data and the host sent the state on
## that ACK, about two frames later: every late joiner lost the table, and reconciliation
## (token positions only) never brought it back. The client now reports when its load
## completes (Root._on_level_loading_completed -> NetworkManager.report_table_loaded),
## after the clear; a state that lands then fills GameState, and the client applies it to
## its tokens on arrival.
##
## The wait tolerates a slow join: the load completes only after the client has fetched
## the token models it lacks, and a 20 MB map alone takes about 13 s per peer at Steam's
## 1 MB/s, shared by every peer joining at once. The hold ends on the report; early, with
## nothing sent, when the peer leaves or the host stops hosting; and after
## TABLE_LOADED_TIMEOUT with the state sent anyway, since by then the client is long past
## its clear.
##
## Static helpers in the RootNetworkHandler style; the RPCs stay on NetworkManager.

## How long the host holds a late joiner's state waiting for its table-loaded report
## (seconds). Generous on purpose: see the class comment.
const TABLE_LOADED_TIMEOUT := 300.0


## Host: sync a late joiner whose player info has passed the version gate.
static func sync_peer(peer_id: int) -> void:
	NetworkManager._rpc_game_starting.rpc_id(peer_id)
	NetworkManager._rpc_receive_level_data.rpc_id(peer_id, NetworkManager._current_level_dict)
	await send_state_once_table_loaded(peer_id, NetworkStateSync.send_full_state_to_peer)


## Host: wait for `peer_id`'s table-loaded report, then call `send_state` with the peer id
## and emit NetworkManager.late_joiner_connected. Returns true once sent; false, sending
## nothing, when the peer leaves or this host stops hosting first. A report from any other
## peer releases nothing. `send_state` is NetworkStateSync.send_full_state_to_peer outside
## tests.
static func send_state_once_table_loaded(
	peer_id: int, send_state: Callable, timeout_seconds: float = TABLE_LOADED_TIMEOUT
) -> bool:
	var reported := await _await_table_loaded(peer_id, timeout_seconds)
	if not _is_joining(peer_id):
		return false
	if not reported:
		push_warning(
			(
				"LateJoinerSync: peer %d did not report its table loaded in %d s; sending its state"
				% [peer_id, int(timeout_seconds)]
			)
		)
	send_state.call(peer_id)
	NetworkManager.late_joiner_connected.emit(peer_id)
	return true


## True when `peer_id` reports its table loaded within `timeout_seconds`; false when the
## time runs out or the peer stops joining first (it left, or this host stopped hosting).
static func _await_table_loaded(peer_id: int, timeout_seconds: float) -> bool:
	var result := {"reported": false}
	var on_report := func(reporting_peer_id: int) -> void:
		if reporting_peer_id == peer_id:
			result.reported = true
	NetworkManager.table_loaded.connect(on_report)
	var tree := NetworkManager.get_tree()
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not result.reported and _is_joining(peer_id) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	NetworkManager.table_loaded.disconnect(on_report)
	return result.reported


## True while `peer_id` is still a player of the game this host is serving.
static func _is_joining(peer_id: int) -> bool:
	return NetworkManager.is_host() and NetworkManager._players.has(peer_id)
