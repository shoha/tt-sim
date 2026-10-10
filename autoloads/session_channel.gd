class_name SessionChannel
extends Node

## Session sub-component of NetworkManager: who is in the session, the maps the GM has set
## out, and whether one is on the table now.
##
## A session is a room of connected people that can exist with no map (Room first, user
## decision 2026-10-09). It begins when hosting starts and ends when the host leaves; nobody
## reconnects in between, so the connection, the players and the Steam lobby outlive every
## map. The host's session is in one of two phases:
##
## - Room (open, no table): open() clears the late-joiner level snapshot, so nothing is
##   served or synced, and tells every client to leave the table for the room (room_opened).
##   Hosting starts here.
## - Table (one map out): close() comes just before game_starting; the level broadcast that
##   follows records the map on the shelf and points the table at it (note_table_out(),
##   called from NetworkManager.broadcast_level_data, so a map change in play moves the
##   pointer too).
##
## Late joiners are phase-aware. admit_peer() runs once for each peer whose player info has
## passed the version gate: in the room the joiner gets room_opened and lands in ROOM; at a
## table it gets game_starting, the level, and the full state once it reports its table
## loaded (LateJoinerSync).
##
## The shelf is the session's maps, each a MapRef {"folder", "map_path", "hashes"}: the level
## folder (or, for a level without one, its res:// map path) and the content hashes the
## clients checked. The table pointer is the ref_key() of the map on the table, "" in the
## room. Players are keyed by session id, the Steam id as a decimal string, each with a name
## and the peer id it has now (0 once it left), so the party and its grants (`party`,
## SessionParty) outlive a peer id: a player who rejoins gets a new peer id and the same
## session id. A transport without Steam ids (the ENet scenarios, GUT) has no identity of its
## own, so there the session id is TEST_ID_PREFIX plus the SESSION_KEY the joiner reports in
## its player info, or plus its peer id when it reports none. The host owns all of it and
## sends clients a summary on every change; clients read their copy through the same getters.
##
## Accessed via NetworkManager.session; do not add as a standalone autoload. Its RPCs live at
## /root/NetworkManager/Session on every peer.

## Emitted on a client when the host opened the room (from the table, or on joining it).
signal room_opened
## Emitted on every peer when the shelf, the table pointer or the players changed.
signal session_changed

## Session id prefix for a peer on a transport without Steam ids (ENet scenarios, tests).
const TEST_ID_PREFIX := "enet-"
## Player info key a joiner on a transport without Steam ids reports as its identity, so a
## rejoin keeps its session id there. Ignored over Steam, where the transport's Steam id is
## the identity and a client cannot claim another's.
const SESSION_KEY := "session_key"
const MAX_SESSION_KEY := 32
const SESSION_KEY_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
## Bounds on a summary from the host (it is untrusted input like any RPC payload).
const MAX_SHELF := 64
const MAX_SESSION_PLAYERS := 64
const MAX_TEXT := 256

## The players' avatars and their grants by session id (host; see SessionParty).
var party: SessionParty

var _open := false
var _shelf: Array[Dictionary] = []
var _table := ""
## session id -> {"name": String, "peer_id": int}
var _players: Dictionary = {}


func _ready() -> void:
	# The parent is NetworkManager; its autoload name may not resolve during its own _ready.
	var manager := get_parent()
	manager.connection_state_changed.connect(_on_connection_state_changed)
	manager.player_left.connect(_on_player_left)
	party = SessionParty.new()
	party.name = "Party"
	add_child(party)


# =============================================================================
# READ (host and clients)
# =============================================================================


## True while the session is in the room (no table out).
func is_open() -> bool:
	return _open


## The ref_key() of the map on the table, or "" in the room.
func get_table() -> String:
	return _table


## The maps set out this session, oldest first (MapRef copies).
func get_shelf() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for ref in _shelf:
		copy.append(ref.duplicate(true))
	return copy


## session id -> {"name", "peer_id"} (a copy). peer_id is 0 for a player who left.
func get_players() -> Dictionary:
	return _players.duplicate(true)


## The peer id the player with `session_id` has now, or 0 when absent.
func peer_for(session_id: String) -> int:
	return int(_players.get(session_id, {}).get("peer_id", 0))


## The session id of the player on `peer_id`, or "" when none is.
func session_id_of(peer_id: int) -> String:
	if peer_id <= 0:
		return ""
	for session_id in _players:
		if int(_players[session_id].get("peer_id", 0)) == peer_id:
			return session_id
	return ""


# =============================================================================
# HOST
# =============================================================================


## Host: open the room. The table goes away for everyone: the late-joiner snapshot is
## cleared (nothing is served or synced) and every client is sent to the room.
func open() -> void:
	if not NetworkManager.is_host():
		return
	_open = true
	_table = ""
	NetworkManager.clear_level_data()
	_publish()
	if _can_send():
		_rpc_room_opened.rpc()


## Host: close the room, just before the next map is set out.
func close() -> void:
	if NetworkManager.is_host():
		_open = false


## Host: a level went out to the table (NetworkManager.broadcast_level_data, with the map
## hashes already added). Puts its MapRef on the shelf (refreshing the hashes of one already
## there) and points the table at it.
func note_table_out(level_dict: Dictionary) -> void:
	if not NetworkManager.is_host():
		return
	var ref := map_ref(level_dict)
	var key := ref_key(ref)
	var index := _shelf.find_custom(func(r: Dictionary) -> bool: return ref_key(r) == key)
	if index < 0:
		_shelf.append(ref)
	else:
		_shelf[index] = ref
	_open = false
	_table = key
	_publish()


## Host: a new peer passed the version gate (NetworkManager._rpc_send_player_info, with the
## player info it reported). Records it under its session id, gives a returning player its
## grants back (SessionParty.restore_grants, before any table state goes out) and sends it
## to the session's phase, the room or the table; returns that phase (join_phase()).
func admit_peer(peer_id: int, reported: Dictionary = {}) -> StringName:
	if not NetworkManager.is_host():
		return &""
	var info: Dictionary = NetworkManager.get_players().get(peer_id, {})
	var id := session_id_for_peer(peer_id, clean_key(reported.get(SESSION_KEY)))
	# A reported key (no Steam) that a player still connected holds is not this joiner's. A
	# Steam id is the transport's own: a stale connection of the same player gives way to it.
	var holder := peer_for(id)
	if (
		not multiplayer.multiplayer_peer is SteamMultiplayerPeer
		and holder > 0
		and holder != peer_id
		and NetworkManager.get_players().has(holder)
	):
		id = session_id(0, peer_id)
	_add_player(id, str(info.get("name", "")), peer_id)
	party.restore_grants(id, peer_id)
	_publish()
	var phase := join_phase(_open, _table)
	# Only a connected remote peer is sent anywhere: a direct call outside a real RPC (peer
	# 0, as in tests) or a peer that has already gone would make rpc_id fail, and an
	# rpc_id(0) would reach everyone.
	if not _can_send() or peer_id not in multiplayer.get_peers():
		return phase
	match phase:
		&"room":
			_rpc_room_opened.rpc_id(peer_id)
		&"table":
			LateJoinerSync.sync_peer(peer_id)
	return phase


## Where a joiner goes: &"room" while the room is open, &"table" while a map is out, &""
## otherwise (between close() and the level broadcast, which run in one frame). Pure.
static func join_phase(room_open: bool, table: String) -> StringName:
	if room_open:
		return &"room"
	if table != "":
		return &"table"
	return &""


## The session id of `peer_id`: its Steam id when the transport is Steam, else
## TEST_ID_PREFIX plus `key` (a clean_key() the joiner reported) or, without one, the peer id.
func session_id_for_peer(peer_id: int, key: String = "") -> String:
	var steam_id := 0
	var transport := multiplayer.multiplayer_peer
	if transport is SteamMultiplayerPeer:
		if peer_id == multiplayer.get_unique_id():
			steam_id = Steam.getSteamID()
		else:
			steam_id = (transport as SteamMultiplayerPeer).get_steam_id_for_peer_id(peer_id)
	return session_id(steam_id, peer_id, key)


## A player's session id from its Steam id (0 when there is none), peer id and reported key
## (used only without a Steam id). Pure.
static func session_id(steam_id: int, peer_id: int, key: String = "") -> String:
	if steam_id > 0:
		return str(steam_id)
	return TEST_ID_PREFIX + (key if key != "" else str(peer_id))


## A reported SESSION_KEY as the session may use it: 1 to MAX_SESSION_KEY letters, digits,
## "-" or "_", else "" (untrusted player info). Pure.
static func clean_key(raw: Variant) -> String:
	if not raw is String:
		return ""
	var key := raw as String
	if key.is_empty() or key.length() > MAX_SESSION_KEY:
		return ""
	for character in key:
		if not SESSION_KEY_CHARS.contains(character):
			return ""
	return key


## The MapRef of a level dictionary: its folder, its map path when it has no folder, and its
## sanitized map hashes. Pure.
static func map_ref(level_dict: Dictionary) -> Dictionary:
	var folder := str(level_dict.get("level_folder", ""))
	return {
		"folder": folder,
		"map_path": str(level_dict.get("map_path", "")) if folder == "" else "",
		"hashes": MapFileHash.sanitize(level_dict.get(MapFileHash.HASHES_KEY, {})),
	}


## What identifies a MapRef on the shelf and in the table pointer: the folder, else the map
## path. Pure.
static func ref_key(ref: Dictionary) -> String:
	var folder := str(ref.get("folder", ""))
	return folder if folder != "" else str(ref.get("map_path", ""))


## Forget the session, its party included (NetworkManager went offline, or this peer joined
## someone else's).
func reset() -> void:
	_open = false
	_shelf.clear()
	_table = ""
	_players.clear()
	if party:
		party.reset()


func _begin() -> void:
	reset()
	_open = true
	_add_player(session_id_for_peer(1), NetworkManager.get_player_name(), 1)


func _add_player(session_id_value: String, player_name: String, peer_id: int) -> void:
	_players[session_id_value] = {"name": player_name, "peer_id": peer_id}


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	match new_state:
		NetworkManager.ConnectionState.HOSTING:
			_begin()
		NetworkManager.ConnectionState.JOINED, NetworkManager.ConnectionState.OFFLINE:
			reset()


## Host: a player who left keeps its entry with no peer, so a later rejoin under the same
## Steam id maps back to it.
func _on_player_left(peer_id: int, _info: Dictionary) -> void:
	if not NetworkManager.is_host():
		return
	var session_id_value := session_id_of(peer_id)
	if session_id_value == "":
		return
	_players[session_id_value]["peer_id"] = 0
	_publish()


func _can_send() -> bool:
	return multiplayer.multiplayer_peer != null and NetworkManager.is_host()


## The summary clients keep: the phase, the table pointer, the shelf and the players.
func summary() -> Dictionary:
	return {"open": _open, "table": _table, "shelf": get_shelf(), "players": get_players()}


func _publish() -> void:
	if _can_send():
		_rpc_session_summary.rpc(summary())
	session_changed.emit()


## A host's summary as a client may keep it: known keys and types only, bounded sizes,
## hashes through MapFileHash.sanitize. Pure.
static func sanitize_summary(raw: Variant) -> Dictionary:
	var out := {"open": false, "table": "", "shelf": [], "players": {}}
	if not raw is Dictionary:
		return out
	var summary_in: Dictionary = raw
	out.open = summary_in.get("open") is bool and bool(summary_in.open)
	out.table = _clip(summary_in.get("table", ""))
	var shelf: Variant = summary_in.get("shelf", [])
	if shelf is Array:
		for ref: Variant in (shelf as Array).slice(0, MAX_SHELF):
			if ref is Dictionary:
				out.shelf.append(
					{
						"folder": _clip(ref.get("folder", "")),
						"map_path": _clip(ref.get("map_path", "")),
						"hashes": MapFileHash.sanitize(ref.get("hashes", {})),
					}
				)
	var players: Variant = summary_in.get("players", {})
	if players is Dictionary:
		for key: Variant in (players as Dictionary).keys().slice(0, MAX_SESSION_PLAYERS):
			var entry: Variant = players[key]
			if key is String and entry is Dictionary:
				var peer: Variant = entry.get("peer_id", 0)
				out.players[_clip(key)] = {
					"name": _clip(entry.get("name", "")),
					"peer_id": int(peer) if peer is int else 0,
				}
	return out


static func _clip(value: Variant) -> String:
	return (value as String).left(MAX_TEXT) if value is String else ""


## RPC: host -> client, the room is open.
@rpc("authority", "reliable")
func _rpc_room_opened() -> void:
	_open = true
	_table = ""
	room_opened.emit()


## RPC: host -> clients, the session's summary after a change.
@rpc("authority", "reliable")
func _rpc_session_summary(raw: Dictionary) -> void:
	if NetworkManager.is_host():
		return
	var clean := sanitize_summary(raw)
	_open = clean.open
	_table = clean.table
	_shelf.assign(clean.shelf)
	_players = clean.players
	session_changed.emit()
