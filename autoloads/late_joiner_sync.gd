class_name LateJoinerSync

## Host side of a late joiner's sync at a table: move the peer into PLAYING, send it the
## level, and hold its full table state (tokens, avatars, permissions, drag locks) until the
## peer reports its table loaded. SessionChannel.admit_peer() calls sync_peer() for a peer
## that joins while a map is out; a peer joining while the room is open gets room_opened
## instead and never comes here.
##
## The hold is what keeps the state. A client's LevelPlayLoader yields three frames and
## then clear_level() resets GameState, so a state that lands inside that yield is wiped.
## The client used to ACK on mere receipt of the level data and the host sent the state on
## that ACK, about two frames later: every late joiner lost the table, and reconciliation
## (token positions only) never brought it back. The client now reports when its load
## completes (LevelFlow._on_level_loading_completed -> NetworkManager.report_table_loaded),
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
## Live edits. A table changed during play (LiveEdits) is the map file plus its op log. The
## joiner's live edits ask for the log as its map is installed, before its load completes and
## it reports; the host queues the catch-up then, and the full state goes behind it through
## the same outbox (NetworkGameSync.after_live_edits), so the joiner applies the log before the
## state places its tokens, and they land on the edited ground.
##
## Static helpers in the RootNetworkHandler style; the RPCs stay on NetworkManager.

## How long the host holds a late joiner's state waiting for its table-loaded report
## (seconds). Generous on purpose: see the class comment.
const TABLE_LOADED_TIMEOUT := 300.0


## Host: sync a late joiner whose player info has passed the version gate.
static func sync_peer(peer_id: int) -> void:
	NetworkManager.send_game_starting_to_peer(peer_id)
	NetworkManager.send_level_snapshot_to_peer(peer_id)
	await send_state_once_table_loaded(peer_id, send_state_after_live_edits)


## Host: `peer_id`'s full state, sent once every live edit message queued before it has left
## (the table's op log its live edits asked for; see the class doc), unless it left meanwhile.
static func send_state_after_live_edits(peer_id: int) -> void:
	NetworkManager.game_sync.after_live_edits(
		func() -> void:
			if _is_joining(peer_id):
				NetworkStateSync.send_full_state_to_peer(peer_id)
	)


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
