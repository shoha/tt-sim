extends Node

## Centralized network manager for multiplayer functionality.
## Handles Steam lobby creation/joining, SteamMultiplayerPeer, player tracking, the
## level start and the level snapshot served to late joiners.
##
## Usage:
##   NetworkManager.host_game()
##   NetworkManager.join_game("ROOMCODE")
##   NetworkManager.disconnect_game()
##
## Three child nodes carry the rest of the RPCs: token permissions on `permissions`
## (NetworkPermissions), table play -- token transforms, state and removal, drag
## locks, live visual settings -- on `game_sync` (NetworkGameSync), and the session -- the
## room, the shelf of maps, the table pointer, players by Steam id, and where a joiner
## lands -- on `session` (SessionChannel).
##
## The host announces a leave (player_left, then the player list) once the multiplayer poll
## that reported it has drained, every leave of that poll together (_announce_leaves()), so
## nothing a listener sends reaches a peer that has closed but is not reported gone yet.

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
signal table_loaded(peer_id: int)  ## Host: a client's level load completed (LateJoinerSync)

## Connection states
enum ConnectionState {
	OFFLINE,  ## Not connected to any network
	CONNECTING,  ## Connecting to Steam lobby or game server
	HOSTING,  ## Hosting a game, waiting for players or playing
	JOINED,  ## Joined a game as client
}

## Player roles
enum PlayerRole {
	PLAYER,  ## Regular player - can view, limited interaction
	GM,  ## Game Master - full control
}

## Default player name
const DEFAULT_PLAYER_NAME := "Player"

## Maximum players per lobby
const MAX_PLAYERS := 8

## Connection timeout (seconds)
const CONNECTION_TIMEOUT := 15.0

## Grace period between the host telling a client its version was rejected and the
## host dropping that peer (seconds). Disconnecting in the same frame could drop the
## reliable rejection RPC before delivery, leaving the client with a generic "Host
## disconnected". A well-behaved client leaves on its own as soon as the RPC arrives;
## the forced disconnect only matters for one that ignores it.
const VERSION_REJECT_DISCONNECT_DELAY := 1.0

## Permission request/response sub-component
var permissions: NetworkPermissions

## Table-play sub-component: token, drag-lock and live visual RPCs
var game_sync: NetworkGameSync

## Session sub-component: the room, the shelf, the table pointer and late joiners' phase
var session: SessionChannel

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

## Current connection state
var _connection_state: ConnectionState = ConnectionState.OFFLINE

## Room code (base-36 encoded lobby ID) when hosting
var _room_code: String = ""

## Connected players: peer_id -> player_info dictionary
var _players: Dictionary = {}

## Host: the leaves of the current poll not announced yet, in order, each {"peer_id",
## "info"} (see _on_peer_disconnected())
var _leaves: Array[Dictionary] = []

## Local player info. "version" is what the host checks against its own version
## (VersionGate.is_player_info_accepted) when this client's info arrives.
var _local_player_info: Dictionary = {
	"name": "Player",
	"role": PlayerRole.PLAYER,
	VersionGate.PLAYER_INFO_KEY: UpdateVersion.get_current(),
}

## The level snapshot served to late joiners (host side). Opaque here: it is whatever
## broadcast_level_data() was given, changed only through update_level_snapshot().
var _current_level_dict: Dictionary = {}

## Timer tracking CONNECTION_TIMEOUT
var _connection_timer: Timer = null

## Game state tracking (for late joiner detection)
var _game_in_progress: bool = false

## Steam initialization state
var _steam_initialized: bool = false

## Current Steam lobby ID (0 when not in a lobby)
var _lobby_id: int = 0


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

	# Setup table-play sub-component
	game_sync = NetworkGameSync.new()
	game_sync.name = "GameSync"
	add_child(game_sync)

	# Setup session sub-component
	session = SessionChannel.new()
	session.name = "Session"
	add_child(session)

	# Load player name from settings
	_load_player_name()


func _process(_delta: float) -> void:
	if _steam_initialized:
		Steam.run_callbacks()


## Lazily initialize Steam on first multiplayer attempt.
## Retries once on IPC failure (Steam's pipe can go stale).
## Returns true if Steam is ready, false if initialization failed.
func _ensure_steam_initialized() -> bool:
	if _steam_initialized:
		return true

	var init_result: Dictionary = _try_steam_init()

	# Retry once on IPC pipe failure — Steam's named pipe can go stale
	if init_result.status == 2:
		push_warning("NetworkManager: Steam IPC failed, retrying in 1s...")
		await get_tree().create_timer(1.0).timeout
		init_result = _try_steam_init()

	if init_result.status == 0:
		_steam_initialized = true
		# Raise Steam's 256 KB/s default send cap before any connection (map downloads)
		if not SteamNetConfig.apply_defaults():
			push_warning("NetworkManager: Steam refused the send rate settings")
		return true

	var reason: String
	if init_result.status == 2:
		reason = "Steam is not running. Please start Steam and try again."
	else:
		reason = "Steam error (status %d): %s" % [init_result.status, init_result.verbal]

	push_warning("NetworkManager: ", reason)
	connection_failed.emit(reason)
	return false


func _try_steam_init() -> Dictionary:
	var result: Dictionary = Steam.steamInitEx()
	print("NetworkManager: steamInitEx() returned: ", result)
	return result


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

	if not await _ensure_steam_initialized():
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
		# Hosting was cancelled while Steam made the lobby: leave it rather than strand it.
		if result == Steam.RESULT_OK:
			Steam.leaveLobby(lobby_id)
		return

	if result != Steam.RESULT_OK:
		_handle_connection_error("Failed to create Steam lobby (result=%d)" % result)
		return

	_lobby_id = lobby_id

	# Publish our version so a joining client can refuse a mismatch before it connects
	# (see VersionGate). The host still re-checks each client's reported version.
	Steam.setLobbyData(lobby_id, VersionGate.LOBBY_DATA_KEY, UpdateVersion.get_current())

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

	if not await _ensure_steam_initialized():
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

	# Refuse a host on a different version before connecting at all. A host from before
	# the version gate publishes no version and reads as "", which is a mismatch.
	# _handle_connection_error() leaves the lobby through disconnect_game().
	var host_version: String = Steam.getLobbyData(lobby_id, VersionGate.LOBBY_DATA_KEY)
	var mismatch := VersionGate.mismatch_message(host_version, UpdateVersion.get_current())
	if not mismatch.is_empty():
		_handle_connection_error(mismatch)
		return

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

	# Set state to OFFLINE before closing connections to prevent signal cascades. When the
	# host ended the session the transport is already closed here, so listeners of this
	# change ask NetPeers (is_live(), local_id()) rather than the peer itself.
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
	game_sync.reset()
	_stop_connection_timeout()


# =============================================================================
# MULTIPLAYER CALLBACKS
# =============================================================================


func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		# Send current player list to new peer
		_rpc_sync_player_list.rpc_id(peer_id, _players)
		# A joiner's room or table sync waits for its player info, so a client on the
		# wrong version is rejected on the join screen instead of being pushed into the
		# room or PLAYING first -- see _rpc_send_player_info().

	# Request player info from the new peer
	_rpc_send_player_info.rpc_id(peer_id, _local_player_info)


## A peer left: it is out of get_players() at once. A client announces it here; the host
## after the poll that reported it (_announce_leaves()). Over ENet a closing peer's channels
## are freed as soon as its disconnect arrives, before Godot reports the leave, and clients
## that quit together arrive in one poll, so a send made while that poll is still reporting
## leaves reaches peers that are already closed ("Unable to send packet on channel 0, max
## channels: 0"). Sending to multiplayer.get_peers() alone would not help: a peer whose leave
## is not reported yet is still in it.
func _on_peer_disconnected(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var player_info: Dictionary = _players[peer_id].duplicate()
	_players.erase(peer_id)
	if not is_host():
		# Emit after erasing so get_players() returns consistent state
		player_left.emit(peer_id, player_info)
		return
	_leaves.append({"peer_id": peer_id, "info": player_info})
	if _leaves.size() == 1:
		_announce_leaves.call_deferred()


## Host: announce the leaves of the poll that has just drained: player_left for each, in the
## order they came (whatever its listeners send goes to the peers still connected), then the
## player list once. Leaves the host went offline before announcing are dropped.
func _announce_leaves() -> void:
	var leaves := _leaves
	_leaves = []
	if not is_host():
		return
	for leave in leaves:
		player_left.emit(int(leave.peer_id), leave.info)
	if NetPeers.is_live(multiplayer):
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

	var received_info := info
	var is_new_peer := not _players.has(sender_id)
	if is_host():
		# Same-version gate, authoritative half: the client already checked the lobby's
		# published version, but lobby data is advisory, so the host re-checks the version
		# the client reports and never admits a mismatch (see VersionGate).
		if not VersionGate.is_player_info_accepted(info, UpdateVersion.get_current()):
			_reject_peer_version(sender_id, VersionGate.reported_version(info))
			return
		# Only the host receives this RPC from an untrusted remote peer (when a
		# client receives it, the sender is the host, which is already
		# authoritative about itself). Accept the client's display name, but
		# never its self-reported role -- keep whatever role we already have on
		# record for this peer (or the default PLAYER for a peer we haven't
		# seen yet). Otherwise a client could claim "role": GM and get the GM
		# badge shown host-wide.
		var existing_role = _players.get(sender_id, {}).get("role", PlayerRole.PLAYER)
		received_info = {"name": info.get("name", DEFAULT_PLAYER_NAME), "role": existing_role}

	_players[sender_id] = received_info
	player_joined.emit(sender_id, received_info)

	# If we're the host, broadcast updated player list
	if is_host():
		_rpc_sync_player_list.rpc(_players)

		# A new peer joins the session only once it has passed the version gate above: it
		# lands in the room, or at the table with the level and, after its table-loaded
		# report, the state (SessionChannel.admit_peer, LateJoinerSync). The info it reported
		# carries its session key on a transport without Steam ids.
		if is_new_peer:
			session.admit_peer(sender_id, info)


## Host side of a version rejection: tell the client why, then drop it after
## VERSION_REJECT_DISCONNECT_DELAY. The peer is never added to _players, so no
## player_joined/player_left fires for it.
func _reject_peer_version(peer_id: int, reported_version: String) -> void:
	push_warning(
		(
			"NetworkManager: Peer %d reported version '%s', host is '%s' -- rejected"
			% [peer_id, reported_version, UpdateVersion.get_current()]
		)
	)
	# Peer ids 0 (a direct call outside a real RPC, as in tests) and 1 (ourselves) are
	# not remote clients and cannot be sent to or disconnected.
	if peer_id <= 1 or not multiplayer.multiplayer_peer:
		return
	_rpc_version_rejected.rpc_id(peer_id, UpdateVersion.get_current())
	get_tree().create_timer(VERSION_REJECT_DISCONNECT_DELAY).timeout.connect(
		_disconnect_rejected_peer.bind(peer_id), CONNECT_ONE_SHOT
	)


func _disconnect_rejected_peer(peer_id: int) -> void:
	if not is_host() or not multiplayer.multiplayer_peer:
		return
	if peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## RPC: Host tells a client its game version does not match (host -> rejected client).
## The client leaves on its own with the version message, so the player sees that
## rather than the generic "Host disconnected" the host's later forced disconnect would
## produce. Deferred so the multiplayer peer is not closed while it is dispatching
## this RPC.
@rpc("authority", "reliable")
func _rpc_version_rejected(host_version: String) -> void:
	var message := VersionGate.mismatch_message(host_version, UpdateVersion.get_current())
	if message.is_empty():
		# The host only sends this on a mismatch; if the strings somehow agree, still
		# leave with an honest reason rather than an empty one.
		message = "The host rejected this game version."
	_handle_connection_error.call_deferred(message)


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


## Client: tell the host this peer's table is loaded (its level load completed, so its
## loader's clear_level() is behind it). The host holds a late joiner's full state for
## this (LateJoinerSync); after any other load nothing is waiting and the report is a no-op.
func report_table_loaded() -> void:
	if is_client() and multiplayer.multiplayer_peer:
		_rpc_table_loaded.rpc_id(1)


## RPC: client -> host, the sender's table is loaded. It carries no peer id: the host takes
## the sender from the transport, so a client can only report for itself, and a report only
## releases a state the host is already holding for that peer.
@rpc("any_peer", "reliable")
func _rpc_table_loaded() -> void:
	if not is_host():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	table_loaded.emit(peer_id)


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

	_game_in_progress = true

	# Send to all connected clients (not to self - peer 1)
	for peer_id in _players:
		if peer_id != 1:
			_rpc_game_starting.rpc_id(peer_id)


## Host: move one peer (a late joiner) into PLAYING.
func send_game_starting_to_peer(peer_id: int) -> void:
	if not is_host():
		return
	_rpc_game_starting.rpc_id(peer_id)


## Host: send one peer (a late joiner) the level snapshot, as broadcast_level_data() last
## stored it and update_level_snapshot() has kept it since.
func send_level_snapshot_to_peer(peer_id: int) -> void:
	if not is_host():
		return
	_rpc_receive_level_data.rpc_id(peer_id, _current_level_dict)


## Called by host to send level data to all clients. Adds the content hash of each map
## file (MapFileHash, cached per file version) so a client re-downloads a map it cached
## before the host last saved it.
func broadcast_level_data(level_dict: Dictionary) -> void:
	if not is_host():
		return

	var payload := with_map_hashes(level_dict)
	# Store for late joiners
	_current_level_dict = payload.duplicate(true)
	_game_in_progress = true
	session.note_table_out(payload)

	_rpc_receive_level_data.rpc(payload)


## A copy of `level_dict` carrying the host's map file hashes under
## MapFileHash.HASHES_KEY (none for a res:// map, which ships with the game).
static func with_map_hashes(level_dict: Dictionary) -> Dictionary:
	var payload := level_dict.duplicate(true)
	var hashes := MapFileHash.hashes_for_level_dict(payload)
	if hashes.is_empty():
		payload.erase(MapFileHash.HASHES_KEY)
	else:
		payload[MapFileHash.HASHES_KEY] = hashes
	return payload


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


## Host: replace the level snapshot served to late joiners with `patch` applied to it, so
## a live edit (visual settings today) survives into a later join. `patch` takes the
## snapshot and returns the new one; what the keys mean is the caller's business (for
## visual settings, LevelVisualState.patch_level_dict()). No-op while no level is active,
## so a patch never fabricates a snapshot.
func update_level_snapshot(patch: Callable) -> void:
	if _current_level_dict.is_empty():
		return
	_current_level_dict = patch.call(_current_level_dict)


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
	var my_id := NetPeers.local_id(multiplayer)
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


## Clear the late-joiner level snapshot: no table is out (SessionChannel.open() calls this
## when the host returns everyone to the room).
func clear_level_data() -> void:
	_current_level_dict.clear()
	_game_in_progress = false


## Get the level_folder of the level currently being served to peers (host side).
## Returns "" if no level is active. Used by AssetStreamer to restrict map streaming
## to the level the host actually has loaded, rather than any saved level by name.
func get_current_level_folder() -> String:
	return _current_level_dict.get("level_folder", "")


# =============================================================================
# SETTINGS
# =============================================================================


## Load player name from config file
func _load_player_name() -> void:
	var config := ConfigFile.new()
	var err := config.load(Paths.SETTINGS_PATH)
	if err == OK:
		_local_player_info["name"] = config.get_value("player", "name", DEFAULT_PLAYER_NAME)
