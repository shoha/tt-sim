extends Node

## Centralized network manager for multiplayer functionality.
## Handles Steam lobby creation/joining, SteamMultiplayerPeer, and player tracking.
##
## Usage:
##   NetworkManager.host_game()
##   NetworkManager.join_game("ROOMCODE")
##   NetworkManager.disconnect_game()

## Connection states
enum ConnectionState {
	OFFLINE,  ## Not connected to any network
	CONNECTING,  ## Connecting to Steam lobby or game server
	HOSTING,  ## Hosting a game, waiting for players or playing
	JOINED,  ## Joined a game as client
}

## Signals
signal connection_state_changed(old_state: ConnectionState, new_state: ConnectionState)
signal room_code_received(code: String)
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int, player_info: Dictionary)
signal connection_failed(reason: String)
signal connection_timeout
signal game_starting
signal level_data_received(level_dict: Dictionary)
signal late_joiner_connected(peer_id: int)  ## Emitted when a player joins mid-game
signal game_state_received(state_dict: Dictionary)
signal level_sync_complete(peer_id: int)  ## Emitted when level sync ACK received from client
signal state_sync_complete(peer_id: int)  ## Emitted when state sync ACK received from client
signal token_transform_received(
	network_id: String, position: Vector3, rotation: Vector3, scale: Vector3
)
signal token_state_received(network_id: String, token_dict: Dictionary)
signal token_removed_received(network_id: String)
signal transform_batch_received(batch: Dictionary)
signal visual_settings_received(settings: Dictionary)
## Emitted on clients when a drag lock is granted (another peer is now dragging)
signal drag_lock_granted(network_id: String, locker_peer_id: int)
## Emitted on the denied client when its lock claim was rejected
signal drag_lock_denied(network_id: String)
## Emitted on clients when a drag lock is released (token is free again)
signal drag_lock_released(network_id: String)
signal client_token_transform_received(
	sender_id: int, network_id: String, position: Vector3, rotation: Vector3, scale: Vector3
)
signal client_drag_lock_claimed(sender_id: int, network_id: String)
signal client_drag_lock_released(sender_id: int, network_id: String)

## Current connection state
var _connection_state: ConnectionState = ConnectionState.OFFLINE

## Room code (base-36 encoded lobby ID) when hosting
var _room_code: String = ""

## Connected players: peer_id -> player_info dictionary
var _players: Dictionary = {}

## Player roles
enum PlayerRole {
	PLAYER,  ## Regular player - can view, limited interaction
	GM,  ## Game Master - full control
}

## Local player info
var _local_player_info: Dictionary = {
	"name": "Player",
	"role": PlayerRole.PLAYER,
}

## Default player name
const DEFAULT_PLAYER_NAME := "Player"

## Current level data (for late joiners)
var _current_level_dict: Dictionary = {}

## Maximum players per lobby
const MAX_PLAYERS := 8

## Connection timeout (seconds)
const CONNECTION_TIMEOUT := 15.0
const LATE_JOINER_SYNC_TIMEOUT := 5.0
var _connection_timer: Timer = null

## Game state tracking (for late joiner detection)
var _game_in_progress: bool = false

## Permission request/response sub-component
var permissions: NetworkPermissions

## Steam initialization state
var _steam_initialized: bool = false

## Current Steam lobby ID (0 when not in a lobby)
var _lobby_id: int = 0

# =============================================================================
# PUBLIC PROPERTIES
# =============================================================================

## Get current connection state
var connection_state: ConnectionState:
	get:
		return _connection_state

## Get room code (only valid when hosting)
var room_code: String:
	get:
		return _room_code


## Open the Steam overlay invite dialog for the current lobby.
func open_invite_overlay() -> void:
	if _lobby_id > 0:
		Steam.activateGameOverlayInviteDialog(_lobby_id)


## Check if we're the host/server
func is_host() -> bool:
	return _connection_state == ConnectionState.HOSTING


## Check if we're a client
func is_client() -> bool:
	return _connection_state == ConnectionState.JOINED


## Check if we're in a networked game (host or client).
func is_networked() -> bool:
	return (
		_connection_state == ConnectionState.HOSTING or _connection_state == ConnectionState.JOINED
	)


## Check if the local player has GM-level access (is GM or not in a networked game).
## Useful for gating actions that should be available to the GM or in solo play.
func has_gm_access() -> bool:
	return is_gm() or not is_networked()


## Check if the local player is a non-GM in a networked game.
## Convenience inverse of has_gm_access() for guard clauses.
func is_restricted_client() -> bool:
	return not is_gm() and is_networked()


## Get all connected players
func get_players() -> Dictionary:
	return _players.duplicate()


## Get player count (including self)
func get_player_count() -> int:
	return _players.size()


# =============================================================================
# LIFECYCLE
# =============================================================================


func _ready() -> void:
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Setup connection timeout timer
	_connection_timer = Timer.new()
	_connection_timer.one_shot = true
	_connection_timer.timeout.connect(_on_connection_timeout)
	add_child(_connection_timer)

	# Setup permissions sub-component
	permissions = NetworkPermissions.new()
	permissions.name = "Permissions"
	add_child(permissions)

	# Load player name from settings
	_load_player_name()


func _process(_delta: float) -> void:
	if _steam_initialized:
		Steam.run_callbacks()


## Lazily initialize Steam on first multiplayer attempt.
## Returns true if Steam is ready, false if initialization failed.
func _ensure_steam_initialized() -> bool:
	if _steam_initialized:
		return true

	var init_result: Dictionary = Steam.steamInitEx()
	if init_result.status == 0:
		_steam_initialized = true
		return true

	# Status 2 = Steam client not running
	if init_result.status == 2:
		UIManager.show_confirmation(
			"Steam Required",
			"Steam is not running.\nPlease start Steam and relaunch tt-sim.",
			"Launch Steam & Quit",
			"",
			func():
				OS.shell_open("steam://")
				get_tree().quit(),
		)
	else:
		UIManager.show_confirmation(
			"Steam Error",
			(
				"Failed to initialize Steam (status %d).\n%s"
				% [init_result.status, init_result.verbal]
			),
			"Quit",
			"",
			func(): get_tree().quit(),
		)
	return false


func _on_connection_timeout() -> void:
	if _connection_state == ConnectionState.CONNECTING:
		connection_timeout.emit()
		_handle_connection_error("Connection timed out")


## Start connection timeout timer
func _start_connection_timeout() -> void:
	_connection_timer.wait_time = CONNECTION_TIMEOUT
	_connection_timer.start()


## Stop connection timeout timer
func _stop_connection_timeout() -> void:
	_connection_timer.stop()


# =============================================================================
# HOST GAME
# =============================================================================


## Start hosting a game.
## Creates a Steam lobby and starts a SteamMultiplayerPeer host.
func host_game() -> void:
	if _connection_state != ConnectionState.OFFLINE:
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	if not _ensure_steam_initialized():
		return

	_set_connection_state(ConnectionState.CONNECTING)
	_start_connection_timeout()

	# Host is always GM
	_local_player_info["role"] = PlayerRole.GM

	# Create Steam lobby
	Steam.lobby_created.connect(_on_lobby_created, CONNECT_ONE_SHOT)
	Steam.createLobby(Steam.LOBBY_TYPE_PRIVATE, MAX_PLAYERS)


func _on_lobby_created(result: int, lobby_id: int) -> void:
	if _connection_state != ConnectionState.CONNECTING:
		return

	if result != Steam.RESULT_OK:
		_handle_connection_error("Failed to create Steam lobby (result=%d)" % result)
		return

	_lobby_id = lobby_id

	# Create SteamMultiplayerPeer as host
	var peer := SteamMultiplayerPeer.new()
	peer.create_host(0)
	multiplayer.multiplayer_peer = peer

	# Add self to players list
	_players[1] = _local_player_info.duplicate()

	_stop_connection_timeout()

	# Emit room code as base-36 encoded lobby ID
	_room_code = LobbyCode.encode(_lobby_id)
	room_code_received.emit(_room_code)

	_set_connection_state(ConnectionState.HOSTING)


# =============================================================================
# JOIN GAME
# =============================================================================


## Join a game using a room code (base-36 encoded Steam lobby ID).
func join_game(room_code_input: String) -> void:
	if _connection_state != ConnectionState.OFFLINE:
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	if not _ensure_steam_initialized():
		return

	# Decode base-36 room code to lobby ID
	var decoded_id := LobbyCode.decode(room_code_input)
	if decoded_id < 0:
		_handle_connection_error("Invalid room code")
		return

	_set_connection_state(ConnectionState.CONNECTING)
	_start_connection_timeout()

	# Clients are players by default
	_local_player_info["role"] = PlayerRole.PLAYER

	_lobby_id = decoded_id
	Steam.lobby_joined.connect(_on_lobby_joined, CONNECT_ONE_SHOT)
	Steam.joinLobby(_lobby_id)


func _on_lobby_joined(lobby_id: int, _lobby_permissions: int, _locked: bool, result: int) -> void:
	if _connection_state != ConnectionState.CONNECTING:
		return

	if result != Steam.RESULT_OK:
		_handle_connection_error("Failed to join Steam lobby (result=%d)" % result)
		return

	_lobby_id = lobby_id

	# Get host's Steam ID and connect as client
	var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
	var peer := SteamMultiplayerPeer.new()
	peer.create_client(host_steam_id, 0)
	multiplayer.multiplayer_peer = peer


# =============================================================================
# DISCONNECT
# =============================================================================


## Disconnect from the current game
func disconnect_game() -> void:
	if _connection_state == ConnectionState.OFFLINE:
		return

	# Set state to OFFLINE before closing connections to prevent signal cascades
	_set_connection_state(ConnectionState.OFFLINE)

	# Leave Steam lobby
	if _lobby_id > 0:
		Steam.leaveLobby(_lobby_id)

	# Close multiplayer peer
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Clear state
	_players.clear()
	_room_code = ""
	_lobby_id = 0
	_game_in_progress = false
	_current_level_dict.clear()
	_stop_connection_timeout()


# =============================================================================
# MULTIPLAYER CALLBACKS
# =============================================================================


func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		# Send current player list to new peer
		_rpc_sync_player_list.rpc_id(peer_id, _players)

		# Handle late joiner - send current level and game state
		if _game_in_progress and not _current_level_dict.is_empty():
			# Use event-driven sync instead of hardcoded delays
			_sync_late_joiner(peer_id)

	# Request player info from the new peer
	_rpc_send_player_info.rpc_id(peer_id, _local_player_info)


## Event-driven late joiner synchronization.
## Uses a signal race (ACK vs timeout) instead of a busy-wait loop.
func _sync_late_joiner(peer_id: int) -> void:
	# Tell the late joiner to transition from lobby to playing state
	_rpc_game_starting.rpc_id(peer_id)

	# Send level data
	_rpc_receive_level_data.rpc_id(peer_id, _current_level_dict)

	# Wait for client ACK with timeout — signal-driven, no polling
	var ack_received := await _await_signal_or_timeout(
		level_sync_complete, peer_id, LATE_JOINER_SYNC_TIMEOUT
	)

	# Send game state
	NetworkStateSync.send_full_state_to_peer(peer_id)

	late_joiner_connected.emit(peer_id)


## Race a peer-specific signal against a timeout timer.
## Returns true if the signal fired for the given peer_id before the timeout.
func _await_signal_or_timeout(sig: Signal, peer_id: int, timeout_seconds: float) -> bool:
	var result := {"resolved": false, "success": false}

	# Timeout timer
	var timer := get_tree().create_timer(timeout_seconds)
	timer.timeout.connect(
		func():
			if not result.resolved:
				result.resolved = true
				result.success = false,
		CONNECT_ONE_SHOT,
	)

	# Signal handler — filters by peer_id
	var handler := func(acking_peer_id: int) -> void:
		if acking_peer_id == peer_id and not result.resolved:
			result.resolved = true
			result.success = true

	sig.connect(handler, CONNECT_ONE_SHOT)

	# Wait until one of them fires
	while not result.resolved:
		await get_tree().process_frame

	# Clean up signal if the timeout won
	if sig.is_connected(handler):
		sig.disconnect(handler)

	return result.success


func _on_peer_disconnected(peer_id: int) -> void:
	if _players.has(peer_id):
		var player_info: Dictionary = _players[peer_id].duplicate()
		_players.erase(peer_id)
		# Emit after erasing so get_players() returns consistent state
		player_left.emit(peer_id, player_info)

		# Notify all clients of updated player list
		if is_host():
			_rpc_sync_player_list.rpc(_players)


func _on_connected_to_server() -> void:
	_stop_connection_timeout()
	_players[multiplayer.get_unique_id()] = _local_player_info.duplicate()
	_set_connection_state(ConnectionState.JOINED)


func _on_connection_failed() -> void:
	if not multiplayer.multiplayer_peer:
		return
	_handle_connection_error("Failed to connect to game server")


func _on_server_disconnected() -> void:
	if _connection_state == ConnectionState.JOINED:
		_handle_connection_error("Host disconnected")
	else:
		disconnect_game()


# =============================================================================
# RPC METHODS
# =============================================================================

@rpc("any_peer", "reliable")
func _rpc_send_player_info(info: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	_players[sender_id] = info
	player_joined.emit(sender_id, info)

	# If we're the host, broadcast updated player list
	if is_host():
		_rpc_sync_player_list.rpc(_players)


@rpc("authority", "reliable")
func _rpc_sync_player_list(players: Dictionary) -> void:
	var old_players := _players.duplicate()

	# Preserve local player info when the host's sync doesn't include us yet.
	# This happens because the host sends the player list immediately on
	# peer_connected, before our _rpc_send_player_info RPC has arrived.
	var my_id := multiplayer.get_unique_id()
	if _players.has(my_id) and not players.has(my_id):
		players[my_id] = _players[my_id]

	_players = players

	# Emit player_left for removed players
	for peer_id in old_players:
		if not players.has(peer_id):
			player_left.emit(peer_id, old_players[peer_id])

	# Emit player_joined for genuinely new players
	for peer_id in players:
		if peer_id != multiplayer.get_unique_id() and not old_players.has(peer_id):
			player_joined.emit(peer_id, players[peer_id])


@rpc("authority", "reliable")
func _rpc_game_starting() -> void:
	game_starting.emit()


@rpc("authority", "reliable")
func _rpc_receive_level_data(level_dict: Dictionary) -> void:
	level_data_received.emit(level_dict)
	# Send ACK back to host
	_rpc_level_sync_ack.rpc_id(1)


## RPC: Client acknowledges level sync complete
@rpc("any_peer", "reliable")
func _rpc_level_sync_ack() -> void:
	if not is_host():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	level_sync_complete.emit(peer_id)


## RPC: Client acknowledges state sync complete
@rpc("any_peer", "reliable")
func _rpc_state_sync_ack() -> void:
	if not is_host():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	state_sync_complete.emit(peer_id)


@rpc("authority", "reliable")
func _rpc_receive_game_state(state_dict: Dictionary) -> void:
	game_state_received.emit(state_dict)


@rpc("authority", "unreliable")
func _rpc_receive_token_transform(
	network_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array
) -> void:
	var pos := SerializationUtils.array_to_vec3(pos_arr)
	var rot := SerializationUtils.array_to_vec3(rot_arr)
	var scl := SerializationUtils.array_to_vec3(scale_arr, Vector3.ONE)
	token_transform_received.emit(network_id, pos, rot, scl)


@rpc("authority", "unreliable")
func _rpc_receive_transform_batch(batch: Dictionary) -> void:
	transform_batch_received.emit(batch)


@rpc("authority", "reliable")
func _rpc_receive_token_state(network_id: String, token_dict: Dictionary) -> void:
	token_state_received.emit(network_id, token_dict)


@rpc("authority", "reliable")
func _rpc_receive_token_removed(network_id: String) -> void:
	token_removed_received.emit(network_id)


@rpc("authority", "reliable")
func _rpc_receive_visual_settings(settings: Dictionary) -> void:
	# Deserialize environment overrides (Color from hex)
	if settings.has("environment_overrides"):
		settings["environment_overrides"] = EnvironmentPresets.overrides_from_json(
			settings["environment_overrides"]
		)
	visual_settings_received.emit(settings)


## RPC: Player sends token transform to host for validation (client -> host)
@rpc("any_peer", "unreliable")
func _rpc_client_token_transform(
	network_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array
) -> void:
	if not is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var pos := SerializationUtils.array_to_vec3(pos_arr)
	var rot := SerializationUtils.array_to_vec3(rot_arr)
	var scl := SerializationUtils.array_to_vec3(scale_arr, Vector3.ONE)
	client_token_transform_received.emit(sender_id, network_id, pos, rot, scl)


## RPC: Client claims a drag lock for a token (client -> host)
@rpc("any_peer", "reliable")
func _rpc_client_claim_drag_lock(network_id: String) -> void:
	if not is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	client_drag_lock_claimed.emit(sender_id, network_id)


## RPC: Client releases a drag lock (client -> host)
@rpc("any_peer", "reliable")
func _rpc_client_release_drag_lock(network_id: String) -> void:
	if not is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	client_drag_lock_released.emit(sender_id, network_id)


## RPC: Host broadcasts that a token is now locked by a peer (host -> all clients)
@rpc("authority", "reliable")
func _rpc_drag_lock_granted(network_id: String, locker_peer_id: int) -> void:
	drag_lock_granted.emit(network_id, locker_peer_id)


## RPC: Host tells a specific client its claim was denied (host -> requester)
@rpc("authority", "reliable")
func _rpc_drag_lock_denied(network_id: String) -> void:
	drag_lock_denied.emit(network_id)


## RPC: Host broadcasts that a token's lock has been released (host -> all clients)
@rpc("authority", "reliable")
func _rpc_drag_lock_released(network_id: String) -> void:
	drag_lock_released.emit(network_id)


# =============================================================================
# HOST GAME CONTROL
# =============================================================================


## Called by host to start the game (notify all clients)
func notify_game_starting() -> void:
	if not is_host():
		push_warning("NetworkManager: Only host can start the game")
		return

	_game_in_progress = true

	# Send to all connected clients (not to self - peer 1)
	for peer_id in _players:
		if peer_id != 1:
			_rpc_game_starting.rpc_id(peer_id)


## Called by host to send level data to all clients
func broadcast_level_data(level_dict: Dictionary) -> void:
	if not is_host():
		return

	# Store for late joiners
	_current_level_dict = level_dict.duplicate(true)
	_game_in_progress = true

	_rpc_receive_level_data.rpc(level_dict)


## Called by host to send full game state to all clients
func broadcast_game_state(state_dict: Dictionary) -> void:
	if not is_host():
		return

	_rpc_receive_game_state.rpc(state_dict)


## Called by host to send game state to a specific client
func send_game_state_to_peer(peer_id: int, state_dict: Dictionary) -> void:
	if not is_host():
		return

	_rpc_receive_game_state.rpc_id(peer_id, state_dict)


## Called by host to broadcast visual settings to all clients.
## Accepts a dictionary with any subset of keys: "map_scale", "light_intensity",
## "environment_preset", "environment_overrides", "lofi_overrides".
func broadcast_visual_settings(settings: Dictionary) -> void:
	if not is_host():
		return
	# Serialize environment overrides (Color to hex) for network transmission
	var net_settings = settings.duplicate()
	if net_settings.has("environment_overrides"):
		net_settings["environment_overrides"] = EnvironmentPresets.overrides_to_json(
			net_settings["environment_overrides"]
		)
	_rpc_receive_visual_settings.rpc(net_settings)


## Called by client to send a token transform to the host
func send_client_token_transform(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	if not is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_client_token_transform.rpc_id(
		1, network_id, [pos.x, pos.y, pos.z], [rot.x, rot.y, rot.z], [scl.x, scl.y, scl.z]
	)


## Client sends a drag lock claim to the host.
func send_drag_lock_claim(network_id: String) -> void:
	if not is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_client_claim_drag_lock.rpc_id(1, network_id)


## Client sends a drag lock release to the host.
func send_drag_lock_release(network_id: String) -> void:
	if not is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_client_release_drag_lock.rpc_id(1, network_id)


# =============================================================================
# HELPERS
# =============================================================================


func _set_connection_state(new_state: ConnectionState) -> void:
	var old_state = _connection_state
	_connection_state = new_state
	connection_state_changed.emit(old_state, new_state)


func _handle_connection_error(reason: String) -> void:
	push_warning("NetworkManager: ", reason)
	connection_failed.emit(reason)
	disconnect_game()


## Set the local player's display name
func set_player_name(player_name: String) -> void:
	_local_player_info["name"] = player_name


## Get the local player's display name
func get_player_name() -> String:
	return _local_player_info.get("name", DEFAULT_PLAYER_NAME)


## Save the player name to settings
func save_player_name(player_name: String) -> void:
	_local_player_info["name"] = player_name

	# Update local player entry if we're in a game
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0
	if my_id > 0 and _players.has(my_id):
		_players[my_id]["name"] = player_name

	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning(
			"NetworkManager: Failed to load settings (err=%d), writing player section only" % err
		)
	config.set_value("player", "name", player_name)
	config.save(Paths.SETTINGS_PATH)


## Set the local player's role
func set_player_role(role: PlayerRole) -> void:
	_local_player_info["role"] = role


## Get the local player's role
func get_local_role() -> PlayerRole:
	return _local_player_info.get("role", PlayerRole.PLAYER)


## Check if the local player is the GM
func is_gm() -> bool:
	return get_local_role() == PlayerRole.GM


## Get a player's role by peer ID
func get_player_role(peer_id: int) -> PlayerRole:
	if _players.has(peer_id):
		return _players[peer_id].get("role", PlayerRole.PLAYER)
	return PlayerRole.PLAYER


## Check if game is currently in progress (for late joiner detection)
func is_game_in_progress() -> bool:
	return _game_in_progress


## Clear level data (call when returning to lobby/title)
func clear_level_data() -> void:
	_current_level_dict.clear()
	_game_in_progress = false


# =============================================================================
# SETTINGS
# =============================================================================


## Load player name from config file
func _load_player_name() -> void:
	var config := ConfigFile.new()
	var err := config.load(Paths.SETTINGS_PATH)
	if err == OK:
		_local_player_info["name"] = config.get_value("player", "name", DEFAULT_PLAYER_NAME)
