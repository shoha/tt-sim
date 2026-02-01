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
signal game_starting()
signal level_data_received(level_dict: Dictionary)
signal game_state_received(state_dict: Dictionary)

## Current connection state
var _connection_state: ConnectionState = ConnectionState.OFFLINE

## Room code (OID from Noray) when hosting
var _room_code: String = ""

## Connected players: peer_id -> player_info dictionary
var _players: Dictionary = {}

## Local player info
var _local_player_info: Dictionary = {
	"name": "Player",
}

## Default noray server (can be overridden)
const DEFAULT_NORAY_SERVER := "192.168.0.244"
const DEFAULT_NORAY_PORT := 8890

## ENet configuration
const MAX_PLAYERS := 8
const DEFAULT_PORT := 7777


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


# =============================================================================
# HOST GAME
# =============================================================================

## Start hosting a game
## Connects to noray, gets a room code, and starts the ENet server
func host_game(noray_server: String = DEFAULT_NORAY_SERVER, noray_port: int = DEFAULT_NORAY_PORT) -> void:
	if _connection_state != ConnectionState.OFFLINE:
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	_set_connection_state(ConnectionState.CONNECTING)

	# Connect to noray server
	var err = await Noray.connect_to_host(noray_server, noray_port)
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

	_set_connection_state(ConnectionState.HOSTING)

	# Listen for incoming NAT connections
	Noray.on_connect_nat.connect(_on_client_nat_connect)
	Noray.on_connect_relay.connect(_on_client_relay_connect)

	print("NetworkManager: Hosting game with room code: ", _room_code)


func _on_client_nat_connect(address: String, port: int) -> void:
	print("NetworkManager: Client connecting via NAT from %s:%d" % [address, port])
	# The client will connect via ENet, we just need to be ready


func _on_client_relay_connect(address: String, port: int) -> void:
	print("NetworkManager: Client connecting via relay from %s:%d" % [address, port])


# =============================================================================
# JOIN GAME
# =============================================================================

## Join a game using a room code
func join_game(room_code_input: String, noray_server: String = DEFAULT_NORAY_SERVER, noray_port: int = DEFAULT_NORAY_PORT) -> void:
	if _connection_state != ConnectionState.OFFLINE:
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	_set_connection_state(ConnectionState.CONNECTING)

	# Connect to noray server
	var err = await Noray.connect_to_host(noray_server, noray_port)
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

	print("NetworkManager: Requesting connection to room: ", room_code_input)


func _on_join_nat_received(address: String, port: int) -> void:
	print("NetworkManager: Received NAT connection info: %s:%d" % [address, port])
	_connect_enet_client(address, port)


func _on_join_relay_received(address: String, port: int) -> void:
	print("NetworkManager: Received relay connection info: %s:%d" % [address, port])
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
	print("NetworkManager: Connecting to game server at %s:%d" % [address, port])


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

	_set_connection_state(ConnectionState.OFFLINE)
	print("NetworkManager: Disconnected")


# =============================================================================
# MULTIPLAYER CALLBACKS
# =============================================================================

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected: ", peer_id)

	if is_host():
		# Send current player list to new peer
		_rpc_sync_player_list.rpc_id(peer_id, _players)

	# Request player info from the new peer
	_rpc_send_player_info.rpc_id(peer_id, _local_player_info)


func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer disconnected: ", peer_id)
	if _players.has(peer_id):
		_players.erase(peer_id)
		player_left.emit(peer_id)

		# Notify all clients of updated player list
		if is_host():
			_rpc_sync_player_list.rpc(_players)


func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server")
	_players[multiplayer.get_unique_id()] = _local_player_info.duplicate()
	_set_connection_state(ConnectionState.JOINED)


func _on_connection_failed() -> void:
	print("NetworkManager: Connection failed")
	_handle_connection_error("Failed to connect to game server")


func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected")
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


# =============================================================================
# HOST GAME CONTROL
# =============================================================================

## Called by host to start the game (notify all clients)
func notify_game_starting() -> void:
	if not is_host():
		push_warning("NetworkManager: Only host can start the game")
		return

	_rpc_game_starting.rpc()


## Called by host to send level data to all clients
func broadcast_level_data(level_dict: Dictionary) -> void:
	if not is_host():
		return

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
