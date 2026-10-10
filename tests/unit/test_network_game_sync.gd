extends GutTest

## NetworkGameSync, the table-play child of NetworkManager: where it lives (its RPC path
## is part of the wire contract between two peers of one build) and the one drag-lock
## grant both callers share.
##
## The host grants a drag lock in two places: DraggableToken when the GM starts a drag
## (peer 1) and NetworkTokenSync when a client's claim passes its CONTROL check. Both go
## through grant_drag_lock(), which emits drag_lock_granted on the host as well, so the
## host's own token copy locks through the same listener as every client's.
##
## NetworkManager is a live autoload (see test_network_manager_security.gd's header), so
## these tests set _connection_state directly and restore it in after_each().

const HOST_TOKEN := "gamesync_test_host_token"
const CLIENT_TOKEN := "gamesync_test_client_token"
const CLIENT_PEER := 7


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	GameState.clear_all_drag_locks()
	GameState.clear_permissions_for_peer(CLIENT_PEER)


func test_game_sync_is_the_game_sync_child_of_network_manager() -> void:
	var game_sync := NetworkManager.game_sync
	assert_not_null(game_sync, "NetworkManager creates its GameSync child in _ready")
	assert_true(game_sync is NetworkGameSync)
	assert_eq(game_sync.get_parent(), NetworkManager)
	assert_eq(
		str(game_sync.get_path()),
		"/root/NetworkManager/GameSync",
		"The RPC path must be the same on every peer"
	)


func test_host_self_grant_emits_granted_for_the_host() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	watch_signals(NetworkManager.game_sync)
	var draggable: DraggableToken = autofree(DraggableToken.new())

	draggable._send_drag_lock_claim(HOST_TOKEN)

	assert_signal_emitted_with_parameters(
		NetworkManager.game_sync, "drag_lock_granted", [HOST_TOKEN, 1]
	)
	assert_eq(GameState.get_drag_lock(HOST_TOKEN), 1, "The host holds its own drag's lock")


func test_client_claim_emits_granted_for_the_claiming_peer() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	GameState.grant_token_permission(
		CLIENT_TOKEN, CLIENT_PEER, TokenPermissions.Permission.CONTROL
	)
	watch_signals(NetworkManager.game_sync)
	var token_sync := NetworkTokenSync.new(null)

	token_sync._on_client_drag_lock_claimed(CLIENT_PEER, CLIENT_TOKEN)

	assert_signal_emitted_with_parameters(
		NetworkManager.game_sync, "drag_lock_granted", [CLIENT_TOKEN, CLIENT_PEER]
	)
	assert_eq(GameState.get_drag_lock(CLIENT_TOKEN), CLIENT_PEER)


func test_grant_on_a_held_lock_emits_nothing() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	assert_true(NetworkManager.game_sync.grant_drag_lock(HOST_TOKEN, 1))
	watch_signals(NetworkManager.game_sync)

	var granted := NetworkManager.game_sync.grant_drag_lock(HOST_TOKEN, CLIENT_PEER)

	assert_false(granted, "Another peer already holds the lock")
	assert_signal_not_emitted(NetworkManager.game_sync, "drag_lock_granted")
	assert_eq(GameState.get_drag_lock(HOST_TOKEN), 1, "The first holder keeps the lock")


func test_grant_is_refused_unless_hosting() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	watch_signals(NetworkManager.game_sync)

	assert_false(NetworkManager.game_sync.grant_drag_lock(CLIENT_TOKEN, CLIENT_PEER))
	assert_signal_not_emitted(NetworkManager.game_sync, "drag_lock_granted")
	assert_eq(GameState.get_drag_lock(CLIENT_TOKEN), 0)
