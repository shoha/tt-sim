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
	RECONNECTING, ## Attempting to reconnect after disconnection
}

## Signals
signal connection_state_changed(old_state: ConnectionState, new_state: ConnectionState)
signal room_code_received(code: String)
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int, player_info: Dictionary)
signal connection_failed(reason: String)
signal connection_timeout
signal reconnecting(attempt: int, max_attempts: int)
signal game_starting
signal level_data_received(level_dict: Dictionary)
signal late_joiner_connected(peer_id: int) ## Emitted when a player joins mid-game
signal game_state_received(state_dict: Dictionary)
signal level_sync_complete(peer_id: int) ## Emitted when level sync ACK received from client
signal state_sync_complete(peer_id: int) ## Emitted when state sync ACK received from client
signal token_transform_received(
	network_id: String, position: Vector3, rotation: Vector3, scale: Vector3
)
signal token_state_received(network_id: String, token_dict: Dictionary)
signal token_removed_received(network_id: String)
signal transform_batch_received(batch: Dictionary)
signal visual_settings_received(settings: Dictionary)
signal token_permission_requested(network_id: String, peer_id: int, permission_type: int)
signal token_permission_response_received(network_id: String, permission_type: int, approved: bool)
signal token_permissions_received(permissions_dict: Dictionary)
signal client_token_transform_received(
	sender_id: int, network_id: String, position: Vector3, rotation: Vector3, scale: Vector3
)

## Current connection state
var _connection_state: ConnectionState = ConnectionState.OFFLINE

## Room code (OID from Noray) when hosting
var _room_code: String = ""

## Room code used to join (stored for reconnection)
var _joined_room_code: String = ""

## Connected players: peer_id -> player_info dictionary
var _players: Dictionary = {}

## Player roles
enum PlayerRole {
	PLAYER, ## Regular player - can view, limited interaction
	GM, ## Game Master - full control
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
const SETTINGS_PATH := "user://settings.cfg"

## Noray relay port range — the host pre-punches NAT holes for these ports
## so relay traffic can reach the ENet server. Must match the noray server's
## udpRelay.ports configuration.
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
## How long to wait for NAT punchthrough before falling back to relay
const NAT_PUNCHTHROUGH_TIMEOUT := 5.0
var _connection_timer: Timer = null
var _nat_timer: Timer = null

## Tracks whether relay fallback has been attempted for the current join
var _relay_attempted: bool = false

## Cached relay address from the initial noray response.
## The noray server sends both NAT and relay info for every `connect` command,
## so we capture the relay address here and use it directly when NAT fails —
## avoiding a second round trip.
var _cached_relay_address: String = ""
var _cached_relay_port: int = 0

## Game state tracking (for late joiner detection)
var _game_in_progress: bool = false

## Delegated reconnection state machine
var _reconnection: NetworkReconnection

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
## Returns true during reconnection — the game is still networked, just temporarily disconnected.
func is_networked() -> bool:
	return (
		_connection_state == ConnectionState.HOSTING
		or _connection_state == ConnectionState.JOINED
		or _reconnection.is_reconnecting()
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

	# Setup NAT punchthrough timeout timer (triggers relay fallback)
	_nat_timer = Timer.new()
	_nat_timer.one_shot = true
	_nat_timer.timeout.connect(_on_nat_punchthrough_timeout)
	add_child(_nat_timer)

	# Setup reconnection handler
	_reconnection = NetworkReconnection.new(
		self,
		func(code: String) -> void:
			# Clean up peer before attempting rejoin
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.close()
				multiplayer.multiplayer_peer = null
			join_game(code),
		func(state: int) -> void: _set_connection_state(state as ConnectionState),
		ConnectionState.RECONNECTING,
	)
	_reconnection.reconnecting.connect(
		func(attempt: int, max_attempts: int) -> void:
			reconnecting.emit(attempt, max_attempts)
	)
	_reconnection.reconnection_failed.connect(
		func(reason: String) -> void: _handle_connection_error(reason)
	)

	# Load network settings
	_load_network_settings()

	# DEBUG: Hook into all Noray commands for verbose logging
	Noray.on_command.connect(_on_noray_command_debug)
	Noray.on_connect_to_host.connect(func(): _log("[NORAY EVENT] on_connect_to_host fired"))
	Noray.on_disconnect_from_host.connect(func(): _log("[NORAY EVENT] on_disconnect_from_host fired"))
	_log("=== NetworkManager ready — debug logging ENABLED ===")
	_log("Target noray server: %s:%d" % [noray_server, noray_port])


func _on_connection_timeout() -> void:
	if _connection_state == ConnectionState.CONNECTING:
		_nat_timer.stop()
		_log("!!! CONNECTION TIMEOUT after %d seconds (relay_attempted=%s)" % [CONNECTION_TIMEOUT, _relay_attempted])
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
		_log("!!! host_game() aborted: state is %s, expected OFFLINE" % ConnectionState.keys()[_connection_state])
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
	if err != OK:
		_handle_connection_error("Failed to connect to noray server (err=%d: %s)" % [err, error_string(err)])
		return

	# Step 2: Register as host to get OID
	_log("[HOST STEP 2] Registering as host ...")
	Noray.on_oid.connect(_on_host_oid_received, CONNECT_ONE_SHOT)
	err = Noray.register_host()
	_log("[HOST STEP 2] register_host returned err=%d (%s)" % [err, error_string(err)])
	if err != OK:
		_handle_connection_error("Failed to register as host (err=%d: %s)" % [err, error_string(err)])
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
	_log("[HOST STEP 3] PID received: '%s'" % Noray.pid)
	_dump_noray_state("before register_remote")

	# Step 4: Register remote address for NAT punchthrough
	_log("[HOST STEP 4] Registering remote address ...")
	var err = await Noray.register_remote()
	_log("[HOST STEP 4] register_remote returned err=%d (%s)" % [err, error_string(err)])
	_dump_noray_state("after register_remote")
	if err != OK:
		_handle_connection_error("Failed to register remote address (err=%d: %s)" % [err, error_string(err)])
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
		_handle_connection_error("Failed to create ENet server on port %d (err=%d: %s)" % [port, err, error_string(err)])
		return

	multiplayer.multiplayer_peer = peer

	# Add self to players list
	_players[1] = _local_player_info.duplicate()

	_stop_connection_timeout()
	_set_connection_state(ConnectionState.HOSTING)

	# Listen for incoming NAT connections
	Noray.on_connect_nat.connect(_on_client_nat_connect)
	Noray.on_connect_relay.connect(_on_client_relay_connect)

	_log("=== HOST READY === room_code='%s', listening on port %d" % [_room_code, port])
	_dump_noray_state("host ready")


func _on_client_nat_connect(address: String, port: int) -> void:
	_log("Client connecting via NAT from %s:%d" % [address, port])
	# The client will connect via ENet, we just need to be ready


func _on_client_relay_connect(address: String, port: int) -> void:
	_log("Client connecting via relay through %s:%d — NAT holes were pre-punched at server start" % [address, port])


## Pre-punch NAT holes for every noray relay port.
## Called just before `create_server` while the registered local port is still
## free (register_remote has already closed its socket).  Each outbound UDP
## packet creates a NAT mapping from our ENet port to the relay port on the
## noray server, so that relay traffic can reach us later.
func _prepunch_relay_nat(local_port: int) -> void:
	var udp = PacketPeerUDP.new()
	var err = udp.bind(local_port)
	if err != OK:
		_log("[HOST] Failed to bind UDP port %d for relay NAT pre-punch (err=%d: %s)" % [local_port, err, error_string(err)])
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
	_log("[HOST] Pre-punched NAT for %d relay ports (%d-%d) + registrar on %s from local port %d" % [
		count, NORAY_RELAY_PORT_START, NORAY_RELAY_PORT_END, server_ip, local_port
	])


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
	_log(">>> join_game() called — room='%s', server=%s, port=%d" % [room_code_input, target_server, target_port])

	# Allow joining when offline or reconnecting
	if (
		_connection_state != ConnectionState.OFFLINE
		and _connection_state != ConnectionState.RECONNECTING
	):
		_log("!!! join_game() aborted: state is %s, expected OFFLINE or RECONNECTING" % ConnectionState.keys()[_connection_state])
		push_warning("NetworkManager: Already connected, disconnect first")
		return

	# Store room code for potential reconnection (used by _reconnection handler)
	_joined_room_code = room_code_input
	_relay_attempted = false
	_cached_relay_address = ""
	_cached_relay_port = 0

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
	if err != OK:
		_handle_connection_error("Failed to connect to noray server (err=%d: %s)" % [err, error_string(err)])
		return

	# Step 2: Register as host to get PID (even as "client" we need this)
	_log("[JOIN STEP 2] Registering host (for PID) ...")
	Noray.on_pid.connect(func(_pid): pass , CONNECT_ONE_SHOT) # Need PID for register_remote
	Noray.register_host() # This gets us a PID even as a "client"

	# Wait for PID
	_log("[JOIN STEP 2] Waiting for PID ...")
	await Noray.on_pid
	_log("[JOIN STEP 2] PID received: '%s'" % Noray.pid)
	_dump_noray_state("after PID received")

	# Step 3: Register remote address
	_log("[JOIN STEP 3] Registering remote address ...")
	err = await Noray.register_remote()
	_log("[JOIN STEP 3] register_remote returned err=%d (%s)" % [err, error_string(err)])
	_dump_noray_state("after register_remote")
	if err != OK:
		_handle_connection_error("Failed to register remote address (err=%d: %s)" % [err, error_string(err)])
		return

	# Step 4: Request connection to host via NAT
	_log("[JOIN STEP 4] Requesting NAT connection to room '%s' ..." % room_code_input)
	# Disconnect any leftover handlers first (e.g. only one of NAT/relay fires
	# per attempt, so the other ONE_SHOT handler may still be connected)
	_disconnect_join_signals()
	Noray.on_connect_nat.connect(_on_join_nat_received, CONNECT_ONE_SHOT)
	Noray.on_connect_relay.connect(_on_join_relay_received, CONNECT_ONE_SHOT)
	Noray.on_command.connect(_on_noray_command_during_join)

	err = Noray.connect_nat(room_code_input)
	_log("[JOIN STEP 4] connect_nat returned err=%d (%s)" % [err, error_string(err)])
	if err != OK:
		_handle_connection_error("Failed to request NAT connection (err=%d: %s)" % [err, error_string(err)])
		return

	_log("[JOIN STEP 4] Waiting for NAT/relay response from noray ...")


func _on_join_nat_received(address: String, port: int) -> void:
	_log("[JOIN STEP 5] NAT connection info received: %s:%d" % [address, port])
	_disconnect_join_signals()
	_connect_enet_client(address, port)


func _on_join_relay_received(address: String, port: int) -> void:
	# The noray server sends both NAT and relay info for every `connect`
	# command.  If we already started a NAT attempt, just cache the relay
	# address for later use instead of connecting immediately.
	if multiplayer.multiplayer_peer and not _relay_attempted:
		_log("[JOIN] Caching relay address %s:%d for fallback" % [address, port])
		_cached_relay_address = address
		_cached_relay_port = port
		return

	# If no NAT attempt in progress, use relay directly
	_log("[JOIN STEP 5] Relay connection info received: %s:%d" % [address, port])
	_disconnect_join_signals()
	_relay_attempted = true
	_connect_enet_client(address, port, true)


## Detect invalid connect responses from noray (e.g. host OID no longer exists).
## The noray server sends a bare "connect" with empty data when the host is gone.
func _on_noray_command_during_join(command: String, data: String) -> void:
	_log("[JOIN] Noray command during join: cmd='%s', data='%s'" % [command, data])
	if command == "connect" and not data.contains(":"):
		_log("!!! Host not found — noray returned bare 'connect' (no address:port). Room code may be invalid or host disconnected.")
		push_warning("NetworkManager: Host not found (room code may be invalid or expired)")
		_disconnect_join_signals()
		if _reconnection.is_reconnecting():
			# During reconnection: route through retry logic
			_on_connection_failed()
		else:
			# Initial join attempt: give a descriptive error
			_handle_connection_error("Host not found (room code may be invalid or expired)")


## NAT punchthrough timed out — fall back to relay connection through the noray server.
func _on_nat_punchthrough_timeout() -> void:
	if _connection_state != ConnectionState.CONNECTING:
		return
	if _relay_attempted:
		return # Already tried relay; let the overall connection timeout handle it

	_relay_attempted = true
	_log("[RELAY FALLBACK] NAT punchthrough timed out after %ds, falling back to relay ..." % NAT_PUNCHTHROUGH_TIMEOUT)

	# Tear down the failed NAT ENet peer
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Clean up old join signal handlers
	_disconnect_join_signals()

	# Use the cached relay address if available (noray sends both NAT and relay
	# info for every `connect` command, so we usually already have it).
	if _cached_relay_address != "":
		_log("[RELAY FALLBACK] Using cached relay address: %s:%d" % [_cached_relay_address, _cached_relay_port])
		_connect_enet_client(_cached_relay_address, _cached_relay_port, true)
		return

	# No cached address — request relay explicitly (adds a round trip)
	_log("[RELAY FALLBACK] No cached relay address, requesting via connect-relay ...")
	Noray.on_connect_relay.connect(_on_relay_fallback_received, CONNECT_ONE_SHOT)
	Noray.on_command.connect(_on_noray_command_during_join)

	var err = Noray.connect_relay(_joined_room_code)
	_log("[RELAY FALLBACK] connect_relay('%s') returned err=%d (%s)" % [_joined_room_code, err, error_string(err)])
	if err != OK:
		_handle_connection_error("Failed to request relay connection (err=%d: %s)" % [err, error_string(err)])


## Received relay address from noray after explicit relay request.
func _on_relay_fallback_received(address: String, port: int) -> void:
	_log("[RELAY FALLBACK] Relay address received: %s:%d" % [address, port])
	_disconnect_join_signals()
	_connect_enet_client(address, port, true)


## Disconnect all client-side join signal handlers from Noray.
func _disconnect_join_signals() -> void:
	if Noray.on_connect_nat.is_connected(_on_join_nat_received):
		Noray.on_connect_nat.disconnect(_on_join_nat_received)
	if Noray.on_connect_relay.is_connected(_on_join_relay_received):
		Noray.on_connect_relay.disconnect(_on_join_relay_received)
	if Noray.on_command.is_connected(_on_noray_command_during_join):
		Noray.on_command.disconnect(_on_noray_command_during_join)


func _connect_enet_client(address: String, port: int, is_relay: bool = false) -> void:
	var peer = ENetMultiplayerPeer.new()

	# Bind to our registered local port for NAT punchthrough.
	# For relay connections, still bind so the relay can match us to our registration.
	var local_port = Noray.local_port if Noray.local_port > 0 else 0
	var mode_label = "RELAY" if is_relay else "NAT"
	_log("[JOIN %s] Creating ENet client — remote=%s:%d, local_port=%d" % [mode_label, address, port, local_port])

	var err = peer.create_client(address, port, 0, 0, 0, local_port)
	_log("[JOIN %s] create_client returned err=%d (%s)" % [mode_label, err, error_string(err)])
	if err != OK:
		_handle_connection_error("Failed to create ENet client (err=%d: %s)" % [err, error_string(err)])
		return

	multiplayer.multiplayer_peer = peer

	# Start NAT punchthrough timer — if this is a direct NAT attempt and we
	# haven't tried relay yet, give it NAT_PUNCHTHROUGH_TIMEOUT seconds before
	# falling back to relay.
	if not is_relay and not _relay_attempted:
		_nat_timer.wait_time = NAT_PUNCHTHROUGH_TIMEOUT
		_nat_timer.start()
		_log("[JOIN NAT] Started NAT punchthrough timer (%ds), will fall back to relay if needed" % NAT_PUNCHTHROUGH_TIMEOUT)
	else:
		_log("[JOIN %s] ENet peer assigned, waiting for connected_to_server signal ..." % mode_label)


# =============================================================================
# DISCONNECT
# =============================================================================


## Disconnect from the current game
func disconnect_game() -> void:
	_log(">>> disconnect_game() called — state=%s" % ConnectionState.keys()[_connection_state])
	if _connection_state == ConnectionState.OFFLINE:
		_log("Already offline, nothing to disconnect")
		return

	# Stop any pending reconnection attempts
	_reconnection.stop()

	# Set state to OFFLINE *before* closing connections so that any signals
	# triggered by the teardown (e.g. server_disconnected from peer.close())
	# see OFFLINE and short-circuit instead of starting a reconnection cycle.
	_set_connection_state(ConnectionState.OFFLINE)

	# Disconnect Noray signals (host-side)
	if Noray.on_connect_nat.is_connected(_on_client_nat_connect):
		Noray.on_connect_nat.disconnect(_on_client_nat_connect)
	if Noray.on_connect_relay.is_connected(_on_client_relay_connect):
		Noray.on_connect_relay.disconnect(_on_client_relay_connect)
	# Disconnect Noray signals (client-side join + relay fallback)
	_disconnect_join_signals()
	if Noray.on_connect_relay.is_connected(_on_relay_fallback_received):
		Noray.on_connect_relay.disconnect(_on_relay_fallback_received)

	# Stop timers
	_nat_timer.stop()

	# Stop netfox time sync before closing the peer — our manual disconnect
	# bypasses NetworkEvents' automatic NetworkTime.stop() call.
	NetworkTime.stop()

	# Disconnect from noray
	Noray.disconnect_from_host()

	# Close ENet connection
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Clear state
	_players.clear()
	_room_code = ""
	_joined_room_code = ""
	_game_in_progress = false
	_relay_attempted = false
	_cached_relay_address = ""
	_cached_relay_port = 0
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
	_log("=== CONNECTED TO SERVER === peer_id=%d (relay=%s)" % [multiplayer.get_unique_id(), _relay_attempted])
	_dump_noray_state("connected to server")
	_stop_connection_timeout()
	_nat_timer.stop()
	_players[multiplayer.get_unique_id()] = _local_player_info.duplicate()

	# If we were reconnecting, reset reconnection state
	if _connection_state == ConnectionState.RECONNECTING or _reconnection.is_reconnecting():
		_log("Reconnection successful, resetting reconnection state")
		_reconnection.stop()

	_set_connection_state(ConnectionState.JOINED)


func _on_connection_failed() -> void:
	# Ignore stale signals from a peer we already closed (e.g. during relay
	# fallback — we manually close the NAT peer, which can emit this signal
	# after the peer is gone).
	if not multiplayer.multiplayer_peer:
		_log("Ignoring stale connection_failed (peer already closed)")
		return

	_log("!!! CONNECTION FAILED — state=%s, reconnecting=%s, relay_attempted=%s" % [
		ConnectionState.keys()[_connection_state], _reconnection.is_reconnecting(), _relay_attempted
	])
	_dump_noray_state("connection failed")
	_nat_timer.stop()

	# If we're reconnecting, delegate retry/give-up logic to the handler
	if _reconnection.is_reconnecting():
		_reconnection.on_attempt_failed()
	# If NAT failed and we haven't tried relay yet, fall back now
	elif not _relay_attempted and _connection_state == ConnectionState.CONNECTING:
		_on_nat_punchthrough_timeout()
	else:
		_handle_connection_error("Failed to connect to game server")


func _on_server_disconnected() -> void:
	_log("!!! SERVER DISCONNECTED — state=%s" % ConnectionState.keys()[_connection_state])
	_dump_noray_state("server disconnected")
	# Only attempt reconnection if we were previously joined as a client
	if _connection_state == ConnectionState.JOINED:
		# Partial cleanup: close ENet connection but preserve room code for reconnection
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null

		# Clear players but keep room code
		_players.clear()
		_stop_connection_timeout()

		# Start reconnection process via handler — use the room code the client
		# originally joined with (for clients _room_code is empty since it's the
		# host OID; for hosts _joined_room_code is empty so fall back to _room_code)
		var code_for_reconnect = _joined_room_code if _joined_room_code != "" else _room_code
		_reconnection.start(code_for_reconnect)
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


@rpc("authority", "reliable")
func _rpc_receive_visual_settings(settings: Dictionary) -> void:
	# Deserialize environment overrides (Color from hex)
	if settings.has("environment_overrides"):
		settings["environment_overrides"] = EnvironmentPresets.overrides_from_json(
			settings["environment_overrides"]
		)
	visual_settings_received.emit(settings)


## RPC: Player requests permission for a token (client -> host)
@rpc("any_peer", "reliable")
func _rpc_request_token_permission(network_id: String, permission_type: int) -> void:
	if not is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	_log("Permission request from peer %d for token %s (type %d)" % [sender_id, network_id, permission_type])
	token_permission_requested.emit(network_id, sender_id, permission_type)


## RPC: Host sends permission response to a specific client (host -> client)
@rpc("authority", "reliable")
func _rpc_token_permission_response(
	network_id: String, permission_type: int, approved: bool
) -> void:
	token_permission_response_received.emit(network_id, permission_type, approved)


## RPC: Host broadcasts full permissions state to all clients (host -> all)
@rpc("authority", "reliable")
func _rpc_sync_token_permissions(permissions_dict: Dictionary) -> void:
	token_permissions_received.emit(permissions_dict)


## RPC: Player sends token transform to host for validation (client -> host)
@rpc("any_peer", "unreliable")
func _rpc_client_token_transform(
	network_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array
) -> void:
	if not is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	var rot = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])
	var scl = Vector3(scale_arr[0], scale_arr[1], scale_arr[2])
	client_token_transform_received.emit(sender_id, network_id, pos, rot, scl)


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


## Called by host to send permission response to a specific client
func send_permission_response(
	peer_id: int, network_id: String, permission_type: int, approved: bool
) -> void:
	if not is_host() or not multiplayer.multiplayer_peer:
		return
	_rpc_token_permission_response.rpc_id(peer_id, network_id, permission_type, approved)


## Called by host to broadcast permissions to all clients
func broadcast_token_permissions(permissions_dict: Dictionary) -> void:
	if not is_host() or not multiplayer.multiplayer_peer:
		return
	_rpc_sync_token_permissions.rpc(permissions_dict)


## Called by client to request permission for a token
func request_token_permission(network_id: String, permission_type: int) -> void:
	if not is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_request_token_permission.rpc_id(1, network_id, permission_type)


## Called by client to send a token transform to the host
func send_client_token_transform(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	if not is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_client_token_transform.rpc_id(
		1, network_id, [pos.x, pos.y, pos.z], [rot.x, rot.y, rot.z], [scl.x, scl.y, scl.z]
	)


# =============================================================================
# HELPERS
# =============================================================================


func _set_connection_state(new_state: ConnectionState) -> void:
	var old_state = _connection_state
	_connection_state = new_state
	_log("[STATE] %s -> %s" % [ConnectionState.keys()[old_state], ConnectionState.keys()[new_state]])
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
	_log("PRODUCTION_NORAY_SERVER=%s, LOCAL_NORAY_SERVER=%s" % [PRODUCTION_NORAY_SERVER, LOCAL_NORAY_SERVER])


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
		"[NORAY STATE @ %s] connected=%s, oid='%s', pid='%s', local_port=%d"
		% [label, connected, oid_val, pid_val, lport]
	)


## Global handler that logs every command received from the Noray server
func _on_noray_command_debug(command: String, data: String) -> void:
	_log("[NORAY CMD] << %s %s" % [command, data])
