extends GutTest

## NetworkGameSync, the table-play child of NetworkManager: where it lives (its RPC path
## is part of the wire contract between two peers of one build) and the one drag-lock
## grant and one release every caller shares.
##
## The host grants a drag lock in two places: DraggableToken when the GM starts a drag
## (peer 1) and NetworkTokenSync when a client's claim passes its CONTROL check. Both go
## through grant_drag_lock(), which emits drag_lock_granted on the host as well, so the
## host's own token copy locks through the same listener as every client's. Releases
## mirror that through release_drag_lock(): the GM's drop, a client's release, and the
## host releasing for a client that left mid-drag (which never sends its release).
##
## NetworkManager is a live autoload (see test_network_manager_security.gd's header), so
## these tests set _connection_state directly and restore it in after_each().

const HOST_TOKEN := "gamesync_test_host_token"
const CLIENT_TOKEN := "gamesync_test_client_token"
const LEFT_TOKEN := "gamesync_test_left_token"
const CLIENT_PEER := 7


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager.set_player_role(NetworkManager.PlayerRole.PLAYER)
	GameState.clear_all_drag_locks()
	GameState.clear_permissions_for_peer(CLIENT_PEER)
	GameState.remove_token_state(LEFT_TOKEN)


## The host's copy of a token, tracked the way TokenSpawner tracks a spawned token, with a
## DraggableToken whose dragging_allowed the drag lock gates. The GM may drag it.
func _host_copy(spawner: TokenSpawner, network_id: String) -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	token.network_id = network_id
	token.set_meta("placement_id", network_id)
	add_child_autofree(token)
	token._dragging_object = autofree(DraggableToken.new())
	token.set_interactive(true)
	spawner.track_network_token(token)
	var state := TokenState.new()
	state.network_id = network_id
	GameState.set_token_state(network_id, state)
	return token


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


func test_host_self_release_emits_released() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	var draggable: DraggableToken = autofree(DraggableToken.new())
	draggable._send_drag_lock_claim(HOST_TOKEN)
	watch_signals(NetworkManager.game_sync)

	draggable._send_drag_lock_release(HOST_TOKEN)

	assert_signal_emitted_with_parameters(
		NetworkManager.game_sync, "drag_lock_released", [HOST_TOKEN]
	)
	assert_eq(GameState.get_drag_lock(HOST_TOKEN), 0, "The GM's drop frees its lock")


func test_client_release_emits_released() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	GameState.grant_token_permission(
		CLIENT_TOKEN, CLIENT_PEER, TokenPermissions.Permission.CONTROL
	)
	var token_sync := NetworkTokenSync.new(TokenSpawner.new())
	token_sync._on_client_drag_lock_claimed(CLIENT_PEER, CLIENT_TOKEN)
	watch_signals(NetworkManager.game_sync)

	token_sync._on_client_drag_lock_released(CLIENT_PEER, CLIENT_TOKEN)

	assert_signal_emitted_with_parameters(
		NetworkManager.game_sync, "drag_lock_released", [CLIENT_TOKEN]
	)
	assert_eq(GameState.get_drag_lock(CLIENT_TOKEN), 0)


func test_release_by_a_peer_not_holding_the_lock_emits_nothing() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	assert_true(NetworkManager.game_sync.grant_drag_lock(HOST_TOKEN, CLIENT_PEER))
	watch_signals(NetworkManager.game_sync)

	assert_false(NetworkManager.game_sync.release_drag_lock(HOST_TOKEN, 1))
	assert_false(NetworkManager.game_sync.release_drag_lock(CLIENT_TOKEN, CLIENT_PEER))

	assert_signal_not_emitted(NetworkManager.game_sync, "drag_lock_released")
	assert_eq(GameState.get_drag_lock(HOST_TOKEN), CLIENT_PEER, "The holder keeps the lock")


func test_release_is_refused_unless_hosting() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	assert_true(NetworkManager.game_sync.grant_drag_lock(CLIENT_TOKEN, CLIENT_PEER))
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	watch_signals(NetworkManager.game_sync)

	assert_false(NetworkManager.game_sync.release_drag_lock(CLIENT_TOKEN, CLIENT_PEER))
	assert_signal_not_emitted(NetworkManager.game_sync, "drag_lock_released")
	assert_eq(GameState.get_drag_lock(CLIENT_TOKEN), CLIENT_PEER)


## A client that leaves mid-drag never sends its release. The host frees the lock for it,
## and its own copy of the token must unlock too, so the GM can drag it again.
func test_player_left_mid_drag_unlocks_the_host_copy() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager.set_player_role(NetworkManager.PlayerRole.GM)
	var spawner := TokenSpawner.new()
	var token := _host_copy(spawner, LEFT_TOKEN)
	var token_sync := NetworkTokenSync.new(spawner)
	token_sync.setup(add_child_autofree(Node.new()))
	GameState.grant_token_permission(LEFT_TOKEN, CLIENT_PEER, TokenPermissions.Permission.CONTROL)
	token_sync._on_client_drag_lock_claimed(CLIENT_PEER, LEFT_TOKEN)
	assert_eq(token._drag_locked_by, CLIENT_PEER, "The client's claim locks the host's copy")
	assert_false(token._dragging_object.dragging_allowed, "The GM cannot drag a locked token")

	var handler: TokenPermissionHandler = autofree(TokenPermissionHandler.new())
	handler._on_player_left_permissions(CLIENT_PEER, {})
	token_sync.teardown()

	assert_eq(GameState.get_drag_lock(LEFT_TOKEN), 0, "GameState frees the departed peer's lock")
	assert_eq(token._drag_locked_by, 0, "The host's copy is no longer locked to the departed peer")
	assert_true(token._dragging_object.dragging_allowed, "The GM can drag the token again")
