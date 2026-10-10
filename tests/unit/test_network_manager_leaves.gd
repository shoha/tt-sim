extends GutTest

## How NetworkManager announces a leave. Over ENet a closing peer's channels are freed when its
## disconnect arrives, before Godot reports the leave, so a host that broadcast from inside the
## poll reporting several leaves sent to clients that had already closed. The host now
## announces every leave of a poll together once the poll has drained (player_left for each,
## then the player list once); a client still announces at once.

const HOST_INFO := {"name": "host"}
const ANNA := {"name": "Anna"}
const BRAM := {"name": "Bram"}


func before_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._players = {1: HOST_INFO.duplicate(), 5: ANNA.duplicate(), 6: BRAM.duplicate()}


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._players.clear()
	NetworkManager._leaves.clear()


func test_host_announces_the_leaves_of_one_poll_after_it_in_order() -> void:
	watch_signals(NetworkManager)
	NetworkManager._on_peer_disconnected(5)
	NetworkManager._on_peer_disconnected(6)
	assert_eq(NetworkManager.get_players().keys(), [1], "both are out of the players at once")
	assert_signal_not_emitted(NetworkManager, "player_left", "nothing announced inside the poll")
	assert_eq(NetworkManager._leaves.size(), 2, "one batch for the poll")
	await wait_process_frames(1)
	assert_signal_emit_count(NetworkManager, "player_left", 2)
	assert_signal_emitted_with_parameters(NetworkManager, "player_left", [5, ANNA], 0)
	assert_signal_emitted_with_parameters(NetworkManager, "player_left", [6, BRAM], 1)
	assert_true(NetworkManager._leaves.is_empty(), "the batch is taken")


func test_a_leave_after_the_announcement_starts_a_new_batch() -> void:
	watch_signals(NetworkManager)
	NetworkManager._on_peer_disconnected(5)
	await wait_process_frames(1)
	NetworkManager._on_peer_disconnected(6)
	assert_signal_emit_count(NetworkManager, "player_left", 1, "Bram's leave waits for its poll")
	await wait_process_frames(1)
	assert_signal_emit_count(NetworkManager, "player_left", 2)
	assert_signal_emitted_with_parameters(NetworkManager, "player_left", [6, BRAM], 1)


func test_an_unknown_peer_is_not_announced() -> void:
	watch_signals(NetworkManager)
	NetworkManager._on_peer_disconnected(9)
	assert_true(NetworkManager._leaves.is_empty())
	await wait_process_frames(1)
	assert_signal_not_emitted(NetworkManager, "player_left")


func test_leaves_the_host_went_offline_before_announcing_are_dropped() -> void:
	watch_signals(NetworkManager)
	NetworkManager._on_peer_disconnected(5)
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	await wait_process_frames(1)
	assert_signal_not_emitted(NetworkManager, "player_left")
	assert_true(NetworkManager._leaves.is_empty())


func test_a_client_announces_a_leave_at_once() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	watch_signals(NetworkManager)
	NetworkManager._on_peer_disconnected(6)
	assert_signal_emitted_with_parameters(NetworkManager, "player_left", [6, BRAM])
	assert_false(NetworkManager.get_players().has(6))
	assert_true(NetworkManager._leaves.is_empty())
