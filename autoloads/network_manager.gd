extends Node

## Centralized network manager for multiplayer functionality.
## Handles Noray connection, ENet game server/client, and player tracking.
##
## Usage:
##   NetworkManager.host_game("noray.example.com")
##   NetworkManager.join_game("ABC123", "noray.example.com")
##   NetworkManager.disconnect_game()

## Connection states
enum ConnectionState {
	OFFLINE,  ## Not connected to any network
	CONNECTING,  ## Connecting to noray or game server
	HOSTING,  ## Hosting a game, waiting for players or playing
	JOINED,  ## Joined a game as client
	RECONNECTING,  ## Attempting to reconnect after disconnection
}

## Signals
signal connection_state_changed(old_state: ConnectionState, new_state: ConnectionState)
signal room_code_received(code: String)
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal connection_failed(reason: String)
signal connection_timeout
signal reconnecting(attempt: int, max_attempts: int)
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

## Current connection state
var _connection_state: ConnectionState = ConnectionState.OFFLINE

## Room code (OID from Noray) when hosting
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

## Default noray server (can be overridden via settings)
const DEFAULT_NORAY_SERVER := "192.168.0.244"
const DEFAULT_NORAY_PORT := 8890
const SETTINGS_PATH := "user://settings.cfg"

## Configurable noray settings (loaded from settings file)
var noray_server: String = DEFAULT_NORAY_SERVER
var noray_port: int = DEFAULT_NORAY_PORT

## ENet configuration
const MAX_PLAYERS := 8
const DEFAULT_PORT := 7777

## Connection timeout (seconds)
const CONNECTION_TIMEOUT := 15.0
const LATE_JOINER_SYNC_TIMEOUT := 5.0
var _connection_timer: Timer = null

## Reconnection settings
const MAX_RECONNECT_ATTEMPTS := 5
const RECONNECT_BASE_DELAY := 1.0
const RECONNECT_MAX_DELAY := 16.0

## Game state tracking (for late joiner detection)
var _game_in_progress: bool = false

## Reconnection tracking
var _reconnect_attempts: int = 0
var _stored_room_code: String = ""
var _reconnect_timer: Timer = null

## Debug logging
var debug_logging: bool = false

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


## Check if we're the host/server
func is_host() -> bool:
	return _connection_state == ConnectionState.HOSTING


## Check if we're a client
func is_client() -> bool:
	return _connection_state == ConnectionState.JOINED


## Check if we're in a networked game (host or client)
func is_networked() -> bool:
	return (
		_connection_state == ConnectionState.HOSTING or _connection_state == ConnectionState.JOINED
	)


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

	# Setup reconnection timer
	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_on_reconnect_timeout)
	add_child(_reconnect_timer)

	# Load network settings
	_load_network_settings()


func _on_connection_timeout() -> void:
	if _connection_state == ConnectionState.CONNECTING:
		_log("Connection timed out after %d seconds" % CONNECTION_TIMEOUT)
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


## Start hosting a game
## Connects to noray, gets a room code, and starts the ENet server
## If no server specified, uses the configured noray_server/noray_port
func host_game(server_override: String = "", port_override: int = 0) -> void:
	var target_server = server_override if server_override != "" else noray_server
	var target_port = port_override if port_override > 0 else noray_port
	if _connection_state != ConnectionState.OFFLINE:
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	_set_connection_state(ConnectionState.CONNECTING)
	_start_connection_timeout()

	# Host is always GM
	_local_player_info["role"] = PlayerRole.GM

	# Connect to noray server
	_log("Connecting to noray server at %s:%d" % [target_server, target_port])
	var err = await Noray.connect_to_host(target_server, target_port)
	if err != OK:
		_handle_connection_error("Failed to connect to noray server")
		return

	# Register as host to get OID
	Noray.on_oid.connect(_on_host_oid_received, CONNECT_ONE_SHOT)
	err = Noray.register_host()
	if err != OK:
		_handle_connection_error("Failed to register as host")
		return


func _on_host_oid_received(oid: String) -> void:
	_room_code = oid
	room_code_received.emit(oid)

	# Wait for PID before registering remote (register_remote requires PID)
	if not Noray.pid:
		await Noray.on_pid

	# Register remote address for NAT punchthrough
	var err = await Noray.register_remote()
	if err != OK:
		_handle_connection_error("Failed to register remote address")
		return

	# Start ENet server on the registered port
	_start_enet_server()


func _start_enet_server() -> void:
	var peer = ENetMultiplayerPeer.new()
	var port = Noray.local_port if Noray.local_port > 0 else DEFAULT_PORT

	var err = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_handle_connection_error("Failed to create ENet server on port %d" % port)
		return

	multiplayer.multiplayer_peer = peer

	# Add self to players list
	_players[1] = _local_player_info.duplicate()

	_stop_connection_timeout()
	_set_connection_state(ConnectionState.HOSTING)

	# Listen for incoming NAT connections
	Noray.on_connect_nat.connect(_on_client_nat_connect)
	Noray.on_connect_relay.connect(_on_client_relay_connect)

	_log("Hosting game with room code: %s" % _room_code)


func _on_client_nat_connect(address: String, port: int) -> void:
	_log("Client connecting via NAT from %s:%d" % [address, port])
	# The client will connect via ENet, we just need to be ready


func _on_client_relay_connect(address: String, port: int) -> void:
	_log("Client connecting via relay from %s:%d" % [address, port])


# =============================================================================
# JOIN GAME
# =============================================================================


## Join a game using a room code
## If no server specified, uses the configured noray_server/noray_port
func join_game(
	room_code_input: String, server_override: String = "", port_override: int = 0
) -> void:
	var target_server = server_override if server_override != "" else noray_server
	var target_port = port_override if port_override > 0 else noray_port

	# Allow joining when offline or reconnecting
	if (
		_connection_state != ConnectionState.OFFLINE
		and _connection_state != ConnectionState.RECONNECTING
	):
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	# Store room code for potential reconnection
	_stored_room_code = room_code_input

	_set_connection_state(ConnectionState.CONNECTING)
	_start_connection_timeout()

	# Clients are players by default
	_local_player_info["role"] = PlayerRole.PLAYER

	# Connect to noray server
	_log("Connecting to noray server at %s:%d" % [target_server, target_port])
	var err = await Noray.connect_to_host(target_server, target_port)
	if err != OK:
		_handle_connection_error("Failed to connect to noray server")
		return

	# Register remote to get a local port
	Noray.on_pid.connect(func(_pid): pass, CONNECT_ONE_SHOT)  # Need PID for register_remote
	Noray.register_host()  # This gets us a PID even as a "client"

	# Wait for PID
	await Noray.on_pid

	err = await Noray.register_remote()
	if err != OK:
		_handle_connection_error("Failed to register remote address")
		return

	# Request connection to host via NAT
	Noray.on_connect_nat.connect(_on_join_nat_received, CONNECT_ONE_SHOT)
	Noray.on_connect_relay.connect(_on_join_relay_received, CONNECT_ONE_SHOT)

	err = Noray.connect_nat(room_code_input)
	if err != OK:
		_handle_connection_error("Failed to request NAT connection")
		return

	_log("Requesting connection to room: %s" % room_code_input)


func _on_join_nat_received(address: String, port: int) -> void:
	_log("Received NAT connection info: %s:%d" % [address, port])
	_connect_enet_client(address, port)


func _on_join_relay_received(address: String, port: int) -> void:
	_log("Received relay connection info: %s:%d" % [address, port])
	_connect_enet_client(address, port)


func _connect_enet_client(address: String, port: int) -> void:
	var peer = ENetMultiplayerPeer.new()

	# Bind to our registered local port for NAT punchthrough
	var local_port = Noray.local_port if Noray.local_port > 0 else 0

	var err = peer.create_client(address, port, 0, 0, 0, local_port)
	if err != OK:
		_handle_connection_error("Failed to create ENet client")
		return

	multiplayer.multiplayer_peer = peer
	_log("Connecting to game server at %s:%d" % [address, port])


# =============================================================================
# DISCONNECT
# =============================================================================


## Disconnect from the current game
func disconnect_game() -> void:
	if _connection_state == ConnectionState.OFFLINE:
		return

	# Stop any pending reconnection attempts
	_stop_reconnection()

	# Disconnect Noray signals
	if Noray.on_connect_nat.is_connected(_on_client_nat_connect):
		Noray.on_connect_nat.disconnect(_on_client_nat_connect)
	if Noray.on_connect_relay.is_connected(_on_client_relay_connect):
		Noray.on_connect_relay.disconnect(_on_client_relay_connect)

	# Disconnect from noray
	Noray.disconnect_from_host()

	# Close ENet connection
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Clear state
	_players.clear()
	_room_code = ""
	_game_in_progress = false
	_current_level_dict.clear()
	_stop_connection_timeout()

	_set_connection_state(ConnectionState.OFFLINE)
	_log("Disconnected")


# =============================================================================
# MULTIPLAYER CALLBACKS
# =============================================================================


func _on_peer_connected(peer_id: int) -> void:
	_log("Peer connected: %d" % peer_id)

	if is_host():
		# Send current player list to new peer
		_rpc_sync_player_list.rpc_id(peer_id, _players)

		# Handle late joiner - send current level and game state
		if _game_in_progress and not _current_level_dict.is_empty():
			_log("Late joiner detected, sending current level and state to peer %d" % peer_id)
			# Use event-driven sync instead of hardcoded delays
			_sync_late_joiner(peer_id)

	# Request player info from the new peer
	_rpc_send_player_info.rpc_id(peer_id, _local_player_info)


## Event-driven late joiner synchronization.
## Uses a signal race (ACK vs timeout) instead of a busy-wait loop.
func _sync_late_joiner(peer_id: int) -> void:
	# Send level data first
	_rpc_receive_level_data.rpc_id(peer_id, _current_level_dict)

	# Wait for client ACK with timeout — signal-driven, no polling
	var ack_received := await _await_signal_or_timeout(
		level_sync_complete, peer_id, LATE_JOINER_SYNC_TIMEOUT
	)

	if not ack_received:
		_log("Level sync timeout for peer %d, proceeding anyway" % peer_id)

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
	_log("Peer disconnected: %d" % peer_id)
	if _players.has(peer_id):
		_players.erase(peer_id)
		player_left.emit(peer_id)

		# Notify all clients of updated player list
		if is_host():
			_rpc_sync_player_list.rpc(_players)


func _on_connected_to_server() -> void:
	_log("Connected to server")
	_stop_connection_timeout()
	_players[multiplayer.get_unique_id()] = _local_player_info.duplicate()

	# If we were reconnecting, reset reconnection state
	if _connection_state == ConnectionState.RECONNECTING:
		_stop_reconnection()
		_reconnect_attempts = 0
		_stored_room_code = ""

	_set_connection_state(ConnectionState.JOINED)


func _on_connection_failed() -> void:
	_log("Connection failed")
	# If we're reconnecting, handle retry logic
	if _connection_state == ConnectionState.RECONNECTING:
		_reconnect_attempts += 1
		if _reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
			_log("Reconnection failed after %d attempts" % MAX_RECONNECT_ATTEMPTS)
			_stop_reconnection()
			_handle_connection_error(
				"Reconnection failed after %d attempts" % MAX_RECONNECT_ATTEMPTS
			)
		else:
			# Try again with exponential backoff
			_start_reconnection()
	else:
		_handle_connection_error("Failed to connect to game server")


func _on_server_disconnected() -> void:
	_log("Server disconnected")
	# Only attempt reconnection if we were previously joined as a client
	if _connection_state == ConnectionState.JOINED:
		# Partial cleanup: close ENet connection but preserve room code for reconnection
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null

		# Clear players but keep room code
		_players.clear()
		_stop_connection_timeout()

		# Start reconnection process
		_start_reconnection()
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
	_players = players
	# Emit signals for UI updates
	for peer_id in players:
		if peer_id != multiplayer.get_unique_id():
			player_joined.emit(peer_id, players[peer_id])


@rpc("authority", "reliable")
func _rpc_game_starting() -> void:
	_log("Received game_starting RPC")
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
	_log("Received level sync ACK from peer %d" % peer_id)
	level_sync_complete.emit(peer_id)


## RPC: Client acknowledges state sync complete
@rpc("any_peer", "reliable")
func _rpc_state_sync_ack() -> void:
	if not is_host():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	_log("Received state sync ACK from peer %d" % peer_id)
	state_sync_complete.emit(peer_id)


@rpc("authority", "reliable")
func _rpc_receive_game_state(state_dict: Dictionary) -> void:
	game_state_received.emit(state_dict)


@rpc("authority", "unreliable")
func _rpc_receive_token_transform(
	network_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array
) -> void:
	var pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	var rot = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])
	var scl = Vector3(scale_arr[0], scale_arr[1], scale_arr[2])
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


# =============================================================================
# HOST GAME CONTROL
# =============================================================================


## Called by host to start the game (notify all clients)
func notify_game_starting() -> void:
	if not is_host():
		push_warning("NetworkManager: Only host can start the game")
		return

	_game_in_progress = true
	_log("Notifying all clients that game is starting (players: %s)" % str(_players.keys()))

	# Send to all connected clients (not to self - peer 1)
	for peer_id in _players:
		if peer_id != 1:
			_log("Sending game_starting RPC to peer %d" % peer_id)
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


# =============================================================================
# HELPERS
# =============================================================================


func _set_connection_state(new_state: ConnectionState) -> void:
	var old_state = _connection_state
	_connection_state = new_state
	connection_state_changed.emit(old_state, new_state)


func _handle_connection_error(reason: String) -> void:
	push_error("NetworkManager: ", reason)
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
	# Load existing settings first to preserve other sections
	config.load(SETTINGS_PATH)
	config.set_value("player", "name", player_name)
	config.save(SETTINGS_PATH)
	_log("Saved player name: %s" % player_name)


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


## Load network settings from config file
func _load_network_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)

	if err == OK:
		noray_server = config.get_value("network", "noray_server", DEFAULT_NORAY_SERVER)
		noray_port = config.get_value("network", "noray_port", DEFAULT_NORAY_PORT)
		debug_logging = config.get_value("network", "debug_logging", false)
		_local_player_info["name"] = config.get_value("player", "name", DEFAULT_PLAYER_NAME)

	_log(
		(
			"Loaded network settings: noray=%s:%d, player=%s"
			% [noray_server, noray_port, _local_player_info["name"]]
		)
	)


## Save network settings to config file
func save_network_settings() -> void:
	var config = ConfigFile.new()
	# Load existing settings first to preserve other sections
	config.load(SETTINGS_PATH)

	config.set_value("network", "noray_server", noray_server)
	config.set_value("network", "noray_port", noray_port)
	config.set_value("network", "debug_logging", debug_logging)

	config.save(SETTINGS_PATH)
	_log("Saved network settings")


## Set the Noray server address
func set_noray_server(server: String, port: int = DEFAULT_NORAY_PORT) -> void:
	noray_server = server
	noray_port = port
	save_network_settings()


# =============================================================================
# DEBUG LOGGING
# =============================================================================


## Start reconnection process with exponential backoff
func _start_reconnection() -> void:
	# Store room code before it's cleared (if not already stored)
	if _stored_room_code.is_empty() and not _room_code.is_empty():
		_stored_room_code = _room_code

	# If we don't have a stored room code, can't reconnect
	if _stored_room_code.is_empty():
		_log("Cannot reconnect: no room code stored")
		_handle_connection_error("Cannot reconnect: no room code available")
		return

	# Increment attempt counter (first attempt is 0, so this becomes 1)
	_reconnect_attempts += 1

	_log("Starting reconnection attempt %d/%d" % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])

	# Set state to RECONNECTING
	_set_connection_state(ConnectionState.RECONNECTING)

	# Emit reconnecting signal for UI
	reconnecting.emit(_reconnect_attempts, MAX_RECONNECT_ATTEMPTS)

	# Calculate exponential backoff delay
	var delay = min(RECONNECT_BASE_DELAY * pow(2, _reconnect_attempts - 1), RECONNECT_MAX_DELAY)
	_log("Waiting %.2f seconds before reconnection attempt" % delay)

	# Setup timer for reconnection
	_reconnect_timer.wait_time = delay
	_reconnect_timer.start()


## Handle reconnection timer timeout
func _on_reconnect_timeout() -> void:
	if _connection_state != ConnectionState.RECONNECTING:
		return

	_log("Attempting to rejoin room: %s" % _stored_room_code)

	# Clean up current connection state before attempting rejoin
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Attempt to rejoin
	join_game(_stored_room_code)


## Stop reconnection process and clean up
func _stop_reconnection() -> void:
	if _reconnect_timer:
		_reconnect_timer.stop()

	# Reset reconnection state if we're in RECONNECTING state
	if _connection_state == ConnectionState.RECONNECTING:
		_reconnect_attempts = 0
		_stored_room_code = ""


## Log a message if debug logging is enabled
func _log(message: String) -> void:
	if debug_logging:
		print("NetworkManager: ", message)
