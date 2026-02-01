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
	OFFLINE, ## Not connected to any network
	CONNECTING, ## Connecting to noray or game server
	HOSTING, ## Hosting a game, waiting for players or playing
	JOINED, ## Joined a game as client
}

## Signals
signal connection_state_changed(old_state: ConnectionState, new_state: ConnectionState)
signal room_code_received(code: String)
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal connection_failed(reason: String)
signal connection_timeout()
signal game_starting()
signal level_data_received(level_dict: Dictionary)
signal late_joiner_connected(peer_id: int)  ## Emitted when a player joins mid-game
signal game_state_received(state_dict: Dictionary)
signal token_transform_received(network_id: String, position: Vector3, rotation: Vector3, scale: Vector3)
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
	GM,      ## Game Master - full control
}

## Local player info
var _local_player_info: Dictionary = {
	"name": "Player",
	"role": PlayerRole.PLAYER,
}

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
var _connection_timer: Timer = null

## Game state tracking (for late joiner detection)
var _game_in_progress: bool = false

## Debug logging
var debug_logging: bool = false


# =============================================================================
# PUBLIC PROPERTIES
# =============================================================================

## Get current connection state
var connection_state: ConnectionState:
	get: return _connection_state

## Get room code (only valid when hosting)
var room_code: String:
	get: return _room_code

## Check if we're the host/server
func is_host() -> bool:
	return _connection_state == ConnectionState.HOSTING

## Check if we're a client
func is_client() -> bool:
	return _connection_state == ConnectionState.JOINED

## Check if we're in a networked game (host or client)
func is_networked() -> bool:
	return _connection_state == ConnectionState.HOSTING or _connection_state == ConnectionState.JOINED

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
func join_game(room_code_input: String, server_override: String = "", port_override: int = 0) -> void:
	var target_server = server_override if server_override != "" else noray_server
	var target_port = port_override if port_override > 0 else noray_port
	
	if _connection_state != ConnectionState.OFFLINE:
		push_warning("NetworkManager: Already connected, disconnect first")
		return

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
	Noray.on_pid.connect(func(_pid): pass , CONNECT_ONE_SHOT) # Need PID for register_remote
	Noray.register_host() # This gets us a PID even as a "client"

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
			# Small delay to ensure peer is ready
			await get_tree().create_timer(0.1).timeout
			_rpc_receive_level_data.rpc_id(peer_id, _current_level_dict)
			# Send game state after level data
			await get_tree().create_timer(0.1).timeout
			NetworkStateSync.send_full_state_to_peer(peer_id)
			late_joiner_connected.emit(peer_id)

	# Request player info from the new peer
	_rpc_send_player_info.rpc_id(peer_id, _local_player_info)


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
	_set_connection_state(ConnectionState.JOINED)


func _on_connection_failed() -> void:
	_log("Connection failed")
	_handle_connection_error("Failed to connect to game server")


func _on_server_disconnected() -> void:
	_log("Server disconnected")
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


@rpc("authority", "reliable", "call_local")
func _rpc_game_starting() -> void:
	game_starting.emit()


@rpc("authority", "reliable")
func _rpc_receive_level_data(level_dict: Dictionary) -> void:
	level_data_received.emit(level_dict)


@rpc("authority", "reliable")
func _rpc_receive_game_state(state_dict: Dictionary) -> void:
	game_state_received.emit(state_dict)


@rpc("authority", "unreliable")
func _rpc_receive_token_transform(network_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array) -> void:
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
	_rpc_game_starting.rpc()


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
	
	_log("Loaded network settings: noray=%s:%d" % [noray_server, noray_port])


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

## Log a message if debug logging is enabled
func _log(message: String) -> void:
	if debug_logging:
		print("NetworkManager: ", message)
