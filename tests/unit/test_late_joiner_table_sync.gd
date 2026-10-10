extends GutTest

## Host side of the late-joiner sync (LateJoinerSync): the full state is held until the
## peer reports its table loaded, never sent before, and sent once after. Until 2026-10-09
## the host sent it on the client's receipt ACK, which landed inside the client loader's
## pre-clear yield and was wiped (test_late_joiner_state_survives_load.gd shows the client
## half).
##
## send_state_once_table_loaded() takes the send as a Callable, so a spy stands in for
## NetworkStateSync.send_full_state_to_peer (whose RPC needs a real peer). NetworkManager is
## the live autoload (see test_network_manager_security.gd), so the tests set its state
## directly and restore it. table_loaded is emitted directly in place of the transport;
## _rpc_table_loaded is what emits it in a game, with the sender id the transport reports.

const PEER := 7
const OTHER_PEER := 9

var _sent: Array = []
var _joined: Array = []


func before_each() -> void:
	_sent.clear()
	_joined.clear()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._players[PEER] = {"name": "Late", "role": NetworkManager.PlayerRole.PLAYER}
	NetworkManager.late_joiner_connected.connect(_on_late_joiner_connected)


func after_each() -> void:
	NetworkManager.late_joiner_connected.disconnect(_on_late_joiner_connected)
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._players.clear()


func _send_spy(peer_id: int) -> void:
	_sent.append(peer_id)


func _on_late_joiner_connected(peer_id: int) -> void:
	_joined.append(peer_id)


func test_state_is_held_until_the_table_loaded_report_then_sent_once() -> void:
	LateJoinerSync.send_state_once_table_loaded(PEER, _send_spy)
	# Well past the old receipt ACK's two frames: a client still loading reports nothing.
	await wait_process_frames(10)
	assert_eq(_sent, [], "no state before the peer reports its table loaded")
	assert_eq(_joined, [], "late_joiner_connected waits for the send")

	NetworkManager.table_loaded.emit(PEER)
	await wait_process_frames(2)
	assert_eq(_sent, [PEER], "the state goes to the reporting peer right after its report")
	assert_eq(_joined, [PEER])

	NetworkManager.table_loaded.emit(PEER)
	await wait_process_frames(2)
	assert_eq(_sent, [PEER], "a repeat report sends nothing more")


func test_another_peers_report_releases_nothing() -> void:
	NetworkManager._players[OTHER_PEER] = {"name": "Other", "role": NetworkManager.PlayerRole.PLAYER}
	LateJoinerSync.send_state_once_table_loaded(PEER, _send_spy)
	NetworkManager.table_loaded.emit(OTHER_PEER)
	await wait_process_frames(4)
	assert_eq(_sent, [], "a report only releases the reporting peer's own state")
	NetworkManager.table_loaded.emit(PEER)
	await wait_process_frames(2)
	assert_eq(_sent, [PEER])


func test_nothing_is_sent_to_a_peer_that_leaves_while_loading() -> void:
	var outcome := [null]
	var run := func() -> void:
		outcome[0] = await LateJoinerSync.send_state_once_table_loaded(PEER, _send_spy)
	run.call()
	await wait_process_frames(2)
	NetworkManager._players.erase(PEER)
	await wait_process_frames(2)
	assert_eq(outcome[0], false, "the wait ends as soon as the peer is gone")
	NetworkManager.table_loaded.emit(PEER)
	await wait_process_frames(2)
	assert_eq(_sent, [], "nothing is sent to a peer that left")
	assert_eq(_joined, [])


func test_nothing_is_sent_once_the_host_stops_hosting() -> void:
	var outcome := [null]
	var run := func() -> void:
		outcome[0] = await LateJoinerSync.send_state_once_table_loaded(PEER, _send_spy)
	run.call()
	await wait_process_frames(2)
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	await wait_process_frames(2)
	assert_eq(outcome[0], false)
	assert_eq(_sent, [])


func test_a_peer_that_never_reports_gets_the_state_after_the_timeout() -> void:
	var sent := await LateJoinerSync.send_state_once_table_loaded(PEER, _send_spy, 0.05)
	assert_true(sent)
	assert_eq(_sent, [PEER], "past the cap the state goes anyway; the client is past its clear")
	assert_engine_error("did not report its table loaded")


func test_the_timeout_tolerates_a_slow_download() -> void:
	# A 20 MB map takes about 13 s per peer at Steam's 1 MB/s, and peers joining together
	# share the host's upload; the old 5 s ACK timeout would have sent mid-load.
	assert_gte(LateJoinerSync.TABLE_LOADED_TIMEOUT, 120.0)


func test_table_loaded_rpc_is_ignored_unless_hosting() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	watch_signals(NetworkManager)
	NetworkManager._rpc_table_loaded()
	assert_signal_not_emitted(NetworkManager, "table_loaded")


func test_table_loaded_rpc_takes_no_peer_id() -> void:
	# The host reads the reporting peer from the transport (get_remote_sender_id), so a
	# client cannot name another peer and release a state the host holds for it.
	for method in NetworkManager.get_method_list():
		if method["name"] == "_rpc_table_loaded":
			assert_eq(method["args"].size(), 0)
			return
	fail_test("NetworkManager has no _rpc_table_loaded")
