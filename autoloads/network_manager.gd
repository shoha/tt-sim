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

## Noray server addresses
## Local server is used when running in the editor; production is used in exports.
const LOCAL_NORAY_SERVER := "192.168.0.244"
const PRODUCTION_NORAY_SERVER := "134.209.44.68"
const DEFAULT_NORAY_PORT := 8890

## Noray relay port range — the host pre-punches these ports so relay traffic
## can reach the ENet server through the host's NAT. Must match the noray
## server's udpRelay.ports configuration.
const NORAY_RELAY_PORT_START := 49152
const NORAY_RELAY_PORT_END := 49201


## Returns the default noray server for the current build context.
static func _get_default_noray_server() -> String:
	if OS.has_feature("editor"):
		return LOCAL_NORAY_SERVER
	return PRODUCTION_NORAY_SERVER


## Configurable noray settings (loaded from settings file)
var noray_server: String
var noray_port: int = DEFAULT_NORAY_PORT

## ENet configuration
const MAX_PLAYERS := 8
const DEFAULT_PORT := 7777

## Connection timeout (seconds)
const CONNECTION_TIMEOUT := 15.0
const LATE_JOINER_SYNC_TIMEOUT := 5.0
var _connection_timer: Timer = null

## Game state tracking (for late joiner detection)
var _game_in_progress: bool = false

## Permission request/response sub-component
var permissions: NetworkPermissions

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

	# Load network settings
	_load_network_settings()

	# DEBUG: Hook into all Noray commands for verbose logging
	Noray.on_command.connect(_on_noray_command_debug)
	Noray.on_connect_to_host.connect(func(): _log("[NORAY EVENT] on_connect_to_host fired"))
	Noray.on_disconnect_from_host.connect(
		func(): _log("[NORAY EVENT] on_disconnect_from_host fired")
	)
	_log("=== NetworkManager ready — debug logging ENABLED ===")
	_log("Target noray server: %s:%d" % [noray_server, noray_port])


func _on_connection_timeout() -> void:
	if _connection_state == ConnectionState.CONNECTING:
		_log("!!! CONNECTION TIMEOUT after %d seconds" % CONNECTION_TIMEOUT)
		_dump_noray_state("timeout")
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
	_log(">>> host_game() called — server=%s, port=%d" % [target_server, target_port])

	if _connection_state != ConnectionState.OFFLINE:
		_log(
			(
				"!!! host_game() aborted: state is %s, expected OFFLINE"
				% ConnectionState.keys()[_connection_state]
			)
		)
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	_set_connection_state(ConnectionState.CONNECTING)
	_start_connection_timeout()

	# Host is always GM
	_local_player_info["role"] = PlayerRole.GM

	# Step 1: Connect to noray server
	_log("[HOST STEP 1] Connecting to noray at %s:%d ..." % [target_server, target_port])
	_dump_noray_state("before connect_to_host")
	var err = await Noray.connect_to_host(target_server, target_port)
	_log("[HOST STEP 1] connect_to_host returned err=%d (%s)" % [err, error_string(err)])
	_dump_noray_state("after connect_to_host")
	if _connection_state != ConnectionState.CONNECTING:
		return
	if err != OK:
		_handle_connection_error(
			"Failed to connect to noray server (err=%d: %s)" % [err, error_string(err)]
		)
		return

	# Step 2: Register as host to get OID
	_log("[HOST STEP 2] Registering as host ...")
	Noray.on_oid.connect(_on_host_oid_received, CONNECT_ONE_SHOT)
	err = Noray.register_host()
	_log("[HOST STEP 2] register_host returned err=%d (%s)" % [err, error_string(err)])
	if err != OK:
		_handle_connection_error(
			"Failed to register as host (err=%d: %s)" % [err, error_string(err)]
		)
		return
	_log("[HOST STEP 2] Waiting for OID from noray ...")


func _on_host_oid_received(oid: String) -> void:
	_log("[HOST STEP 3] OID received: '%s'" % oid)
	_room_code = oid
	room_code_received.emit(oid)

	# Wait for PID before registering remote (register_remote requires PID)
	if not Noray.pid:
		_log("[HOST STEP 3] PID not yet received, waiting for on_pid ...")
		await Noray.on_pid
	if _connection_state != ConnectionState.CONNECTING:
		return
	_log("[HOST STEP 3] PID received: '%s'" % Noray.pid)
	_dump_noray_state("before register_remote")

	# Step 4: Register remote address for relay port binding
	_log("[HOST STEP 4] Registering remote address ...")
	var err = await Noray.register_remote()
	_log("[HOST STEP 4] register_remote returned err=%d (%s)" % [err, error_string(err)])
	_dump_noray_state("after register_remote")
	if _connection_state != ConnectionState.CONNECTING:
		return
	if err != OK:
		_handle_connection_error(
			"Failed to register remote address (err=%d: %s)" % [err, error_string(err)]
		)
		return

	# Step 5: Start ENet server on the registered port
	_log("[HOST STEP 5] Starting ENet server ...")
	_start_enet_server()


func _start_enet_server() -> void:
	var port = Noray.local_port if Noray.local_port > 0 else DEFAULT_PORT
	_log("[HOST STEP 5] ENet server port=%d (Noray.local_port=%d)" % [port, Noray.local_port])

	# Pre-punch NAT holes for the noray relay port range BEFORE ENet binds.
	# At this point the UDP socket from register_remote is closed so the port
	# is free.  By sending from the ENet port to every relay port on the noray
	# server, we create NAT mappings that allow the relay to reach us later —
	# even through port-restricted NATs.
	if Noray.local_port > 0:
		_prepunch_relay_nat(port)

	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, MAX_PLAYERS)
	_log("[HOST STEP 5] create_server returned err=%d (%s)" % [err, error_string(err)])
	if err != OK:
		_handle_connection_error(
			"Failed to create ENet server on port %d (err=%d: %s)" % [port, err, error_string(err)]
		)
		return

	multiplayer.multiplayer_peer = peer

	# Add self to players list
	_players[1] = _local_player_info.duplicate()

	_stop_connection_timeout()
	_set_connection_state(ConnectionState.HOSTING)

	# Listen for incoming relay connections
	Noray.on_connect_relay.connect(_on_client_relay_connect)

	_log("=== HOST READY === room_code='%s', listening on port %d" % [_room_code, port])
	_dump_noray_state("host ready")


func _on_client_relay_connect(address: String, port: int) -> void:
	_log(
		(
			"Client connecting via relay through %s:%d — NAT holes were pre-punched at server start"
			% [address, port]
		)
	)


## Pre-punch NAT holes for every noray relay port.
## Called just before `create_server` while the registered local port is still
## free (register_remote has already closed its socket).  Each outbound UDP
## packet creates a NAT mapping from our ENet port to the relay port on the
## noray server, so that relay traffic can reach us later.
func _prepunch_relay_nat(local_port: int) -> void:
	var udp = PacketPeerUDP.new()
	var err = udp.bind(local_port)
	if err != OK:
		_log(
			(
				"[HOST] Failed to bind UDP port %d for relay NAT pre-punch (err=%d: %s)"
				% [local_port, err, error_string(err)]
			)
		)
		return

	var server_ip = noray_server
	var count := 0
	for p in range(NORAY_RELAY_PORT_START, NORAY_RELAY_PORT_END + 1):
		udp.set_dest_address(server_ip, p)
		udp.put_packet("punch".to_utf8_buffer())
		count += 1

	# Also punch the registrar port (8809) as a safety net — register_remote
	# already did this, but repeating from the same local port reinforces the
	# NAT mapping.
	udp.set_dest_address(server_ip, 8809)
	udp.put_packet("punch".to_utf8_buffer())

	udp.close()
	_log(
		(
			"[HOST] Pre-punched NAT for %d relay ports (%d-%d) + registrar on %s from local port %d"
			% [count, NORAY_RELAY_PORT_START, NORAY_RELAY_PORT_END, server_ip, local_port]
		)
	)


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
	_log(
		(
			">>> join_game() called — room='%s', server=%s, port=%d"
			% [room_code_input, target_server, target_port]
		)
	)

	if _connection_state != ConnectionState.OFFLINE:
		_log(
			(
				"!!! join_game() aborted: state is %s, expected OFFLINE"
				% ConnectionState.keys()[_connection_state]
			)
		)
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	_set_connection_state(ConnectionState.CONNECTING)
	_start_connection_timeout()

	# Clients are players by default
	_local_player_info["role"] = PlayerRole.PLAYER

	# Step 1: Connect to noray server
	_log("[JOIN STEP 1] Connecting to noray at %s:%d ..." % [target_server, target_port])
	_dump_noray_state("before connect_to_host")
	var err = await Noray.connect_to_host(target_server, target_port)
	_log("[JOIN STEP 1] connect_to_host returned err=%d (%s)" % [err, error_string(err)])
	_dump_noray_state("after connect_to_host")
	if _connection_state != ConnectionState.CONNECTING:
		return
	if err != OK:
		_handle_connection_error(
			"Failed to connect to noray server (err=%d: %s)" % [err, error_string(err)]
		)
		return

	# Step 2: Register as host to get PID (even as "client" we need this)
	_log("[JOIN STEP 2] Registering host (for PID) ...")
	Noray.register_host()  # This gets us a PID even as a "client"

	# Wait for PID (guard mirrors the host path in _on_host_oid_received)
	if not Noray.pid:
		_log("[JOIN STEP 2] PID not yet received, waiting for on_pid ...")
		await Noray.on_pid
	if _connection_state != ConnectionState.CONNECTING:
		return
	_log("[JOIN STEP 2] PID received: '%s'" % Noray.pid)
	_dump_noray_state("after PID received")

	# Step 3: Register remote address
	_log("[JOIN STEP 3] Registering remote address ...")
	err = await Noray.register_remote()
	_log("[JOIN STEP 3] register_remote returned err=%d (%s)" % [err, error_string(err)])
	_dump_noray_state("after register_remote")
	if _connection_state != ConnectionState.CONNECTING:
		return
	if err != OK:
		_handle_connection_error(
			"Failed to register remote address (err=%d: %s)" % [err, error_string(err)]
		)
		return

	# Step 4: Request relay connection via noray
	_log("[JOIN STEP 4] Requesting relay connection to room '%s' ..." % room_code_input)
	_disconnect_join_signals()
	Noray.on_connect_relay.connect(_on_join_relay_received, CONNECT_ONE_SHOT)
	Noray.on_command.connect(_on_noray_command_during_join)

	err = Noray.connect_relay(room_code_input)
	_log("[JOIN STEP 4] connect_relay returned err=%d (%s)" % [err, error_string(err)])
	if err != OK:
		_handle_connection_error(
			"Failed to request relay connection (err=%d: %s)" % [err, error_string(err)]
		)
		return

	_log("[JOIN STEP 4] Waiting for relay response from noray ...")


func _on_join_relay_received(address: String, port: int) -> void:
	_log("[JOIN STEP 5] Relay connection info received: %s:%d" % [address, port])
	_disconnect_join_signals()
	_connect_enet_client(address, port)


## Detect invalid connect responses from noray (e.g. host OID no longer exists).
## The noray server sends a bare "connect" with empty data when the host is gone.
func _on_noray_command_during_join(command: String, data: String) -> void:
	_log("[JOIN] Noray command during join: cmd='%s', data='%s'" % [command, data])
	if command == "connect" and not data.contains(":"):
		_log(
			"!!! Host not found — noray returned bare 'connect' (no address:port). Room code may be invalid or host disconnected."
		)
		push_warning("NetworkManager: Host not found (room code may be invalid or expired)")
		_disconnect_join_signals()
		_handle_connection_error("Host not found (room code may be invalid or expired)")


## Disconnect all client-side join signal handlers from Noray.
func _disconnect_join_signals() -> void:
	if Noray.on_connect_relay.is_connected(_on_join_relay_received):
		Noray.on_connect_relay.disconnect(_on_join_relay_received)
	if Noray.on_command.is_connected(_on_noray_command_during_join):
		Noray.on_command.disconnect(_on_noray_command_during_join)


func _connect_enet_client(address: String, port: int) -> void:
	var peer = ENetMultiplayerPeer.new()

	# Bind to our registered local port so the relay can match us to our
	# registration.
	var local_port = Noray.local_port if Noray.local_port > 0 else 0
	_log("[JOIN] Creating ENet client — remote=%s:%d, local_port=%d" % [address, port, local_port])

	var err = peer.create_client(address, port, 0, 0, 0, local_port)
	_log("[JOIN] create_client returned err=%d (%s)" % [err, error_string(err)])
	if err != OK:
		_handle_connection_error(
			"Failed to create ENet client (err=%d: %s)" % [err, error_string(err)]
		)
		return

	multiplayer.multiplayer_peer = peer
	_log("[JOIN] ENet peer assigned, waiting for connected_to_server signal ...")


# =============================================================================
# DISCONNECT
# =============================================================================


## Disconnect from the current game
func disconnect_game() -> void:
	_log(">>> disconnect_game() called — state=%s" % ConnectionState.keys()[_connection_state])
	if _connection_state == ConnectionState.OFFLINE:
		_log("Already offline, nothing to disconnect")
		return

	# Set state to OFFLINE *before* closing connections so that any signals
	# triggered by the teardown (e.g. server_disconnected from peer.close())
	# see OFFLINE and short-circuit instead of starting a reconnection cycle.
	_set_connection_state(ConnectionState.OFFLINE)

	# Disconnect Noray signals (host-side)
	if Noray.on_connect_relay.is_connected(_on_client_relay_connect):
		Noray.on_connect_relay.disconnect(_on_client_relay_connect)
	# Disconnect Noray signals (client-side join)
	_disconnect_join_signals()

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
	# Tell the late joiner to transition from lobby to playing state
	_rpc_game_starting.rpc_id(peer_id)

	# Send level data
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
		var player_info: Dictionary = _players[peer_id].duplicate()
		_players.erase(peer_id)
		# Emit after erasing so get_players() returns consistent state
		player_left.emit(peer_id, player_info)

		# Notify all clients of updated player list
		if is_host():
			_rpc_sync_player_list.rpc(_players)


func _on_connected_to_server() -> void:
	_log("=== CONNECTED TO SERVER === peer_id=%d" % multiplayer.get_unique_id())
	_dump_noray_state("connected to server")
	_stop_connection_timeout()
	_players[multiplayer.get_unique_id()] = _local_player_info.duplicate()

	_set_connection_state(ConnectionState.JOINED)


func _on_connection_failed() -> void:
	if not multiplayer.multiplayer_peer:
		_log("Ignoring stale connection_failed (peer already closed)")
		return

	_log("!!! CONNECTION FAILED — state=%s" % [ConnectionState.keys()[_connection_state]])
	_dump_noray_state("connection failed")
	_handle_connection_error("Failed to connect to game server")


func _on_server_disconnected() -> void:
	_log("!!! SERVER DISCONNECTED — state=%s" % ConnectionState.keys()[_connection_state])
	_dump_noray_state("server disconnected")
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
	_log(
		"[STATE] %s -> %s" % [ConnectionState.keys()[old_state], ConnectionState.keys()[new_state]]
	)
	connection_state_changed.emit(old_state, new_state)


func _handle_connection_error(reason: String) -> void:
	_log("!!! CONNECTION ERROR: %s" % reason)
	_dump_noray_state("connection error")
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
	var err = config.load(Paths.SETTINGS_PATH)

	var default_server := _get_default_noray_server()
	noray_server = default_server

	if err == OK:
		noray_server = config.get_value("network", "noray_server", default_server)
		noray_port = config.get_value("network", "noray_port", DEFAULT_NORAY_PORT)
		debug_logging = config.get_value("network", "debug_logging", false)
		_local_player_info["name"] = config.get_value("player", "name", DEFAULT_PLAYER_NAME)
		_log("Settings file loaded OK (err=%d)" % err)
	else:
		_log("Settings file not found or failed to load (err=%d), using defaults" % err)

	_log(
		(
			"Loaded network settings: noray=%s:%d, player=%s, is_editor=%s"
			% [noray_server, noray_port, _local_player_info["name"], OS.has_feature("editor")]
		)
	)
	_log(
		(
			"PRODUCTION_NORAY_SERVER=%s, LOCAL_NORAY_SERVER=%s"
			% [PRODUCTION_NORAY_SERVER, LOCAL_NORAY_SERVER]
		)
	)


## Save network settings to config file
func save_network_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning(
			"NetworkManager: Failed to load settings (err=%d), writing network section only" % err
		)

	config.set_value("network", "noray_server", noray_server)
	config.set_value("network", "noray_port", noray_port)
	config.set_value("network", "debug_logging", debug_logging)

	config.save(Paths.SETTINGS_PATH)
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
		print("[%s] NetworkManager: %s" % [_timestamp(), message])


## Return a human-readable timestamp for debug logs
func _timestamp() -> String:
	var t := Time.get_time_dict_from_system()
	var ms := Time.get_ticks_msec() % 1000
	return "%02d:%02d:%02d.%03d" % [t.hour, t.minute, t.second, ms]


## Dump current Noray state for debugging
func _dump_noray_state(label: String = "snapshot") -> void:
	if not debug_logging:
		return
	var connected := Noray.is_connected_to_host() if Noray else false
	var oid_val: String = Noray.oid if Noray else "<null>"
	var pid_val: String = Noray.pid if Noray else "<null>"
	var lport: int = Noray.local_port if Noray else -1
	_log(
		(
			"[NORAY STATE @ %s] connected=%s, oid='%s', pid='%s', local_port=%d"
			% [label, connected, oid_val, pid_val, lport]
		)
	)


## Global handler that logs every command received from the Noray server
func _on_noray_command_debug(command: String, data: String) -> void:
	_log("[NORAY CMD] << %s %s" % [command, data])
