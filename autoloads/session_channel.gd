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
## The shelf is the session's maps, each a MapRef {"folder", "map_path", "hashes", "name"}:
## the level folder (or, for a level without one, its res:// map path), the content hashes the
## clients checked and the map's name for the room's shelf. A map reaches the shelf when the
## GM adds it in the room (shelve()) or sets it out. The table pointer is the ref_key() of the
## map on the table, "" in the room. Players are keyed by session id, the Steam id as a decimal
## string, each with a name and the peer id it has now (0 once it left), so the party and its
## grants (`party`, SessionParty) outlive a peer id: a player who rejoins gets a new peer id
## and the same session id. A transport without Steam ids (the ENet scenarios, GUT) has no
## identity of its own, so there the session id is TEST_ID_PREFIX plus the SESSION_KEY the
## joiner reports in its player info, or plus its peer id when it reports none. The host owns
## all of it and sends clients a summary on every change; clients read their copy through the
## same getters.
##
## Holdings are readiness as download state (there is no manual Ready): each client reports
## which shelf maps it already holds at the host's content (holds_map(): its own level folder
## or the download cache), after every summary, on returning to the room and when a fetch
## finishes, and the host counts itself as holding every shelf map. Clients fetch the shelf
## maps they lack in the background (`prefetch`, SessionPrefetch: the table's map, the GM's
## selected map (select_map()), then shelf order) and report their progress, so the room shows
## "Getting it · 40%" and "3 of 4 have it"; Set out never waits for them. The host serves map
## files only for the map on the table and the shelf maps (servable_folders(), the whitelist
## AssetStreamer checks); unshelve() takes a map off the shelf and stops its transfers.
##
## A table move is announced before it happens: the host's TableMover counts it down on
## every peer (announce_move(), cancel_move()), and the move itself is the level broadcast or
## open() that follows.
##
## Accessed via NetworkManager.session; do not add as a standalone autoload. Its RPCs live at
## /root/NetworkManager/Session on every peer.

## Emitted on a client when the host opened the room (from the table, or on joining it).
signal room_opened
## Emitted on every peer when the shelf, the table pointer or the players changed.
signal session_changed
## Emitted on a client when the host announced a table move (TableMover's notice): `kind` what
## it does (a TableMoveNotice.Kind, unchecked), `map_name` where the table goes, `seconds`
## until it does. The client words it in its own language.
signal table_moving(kind: int, map_name: String, seconds: float)
## Emitted on a client when the host called that move off.
signal table_move_cancelled

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
## The longest table-move notice a client shows, in seconds (untrusted input).
const MAX_NOTICE_S := 10.0

## The players' avatars and their grants by session id (host; see SessionParty).
var party: SessionParty
## The background fetch of shelf maps and every player's progress (see SessionPrefetch).
var prefetch: SessionPrefetch

var _open := false
var _shelf: Array[Dictionary] = []
var _table := ""
## The GM's selected shelf map (its ref key), which clients fetch right after the table's
var _selected := ""
## session id -> {"name": String, "peer_id": int}
var _players: Dictionary = {}
## session id -> Array of the ref_key()s that client holds (host: as reported; clients: the
## host's copy, the host's own entry included)
var _holdings: Dictionary = {}
## Client: the keys this peer last reported, so an unchanged report is not sent again
var _reported: Array = []


func _ready() -> void:
	# The parent is NetworkManager; its autoload name may not resolve during its own _ready.
	var manager := get_parent()
	manager.connection_state_changed.connect(_on_connection_state_changed)
	manager.player_left.connect(_on_player_left)
	party = SessionParty.new()
	party.name = "Party"
	add_child(party)
	prefetch = SessionPrefetch.new()
	prefetch.name = "Prefetch"
	add_child(prefetch)


# =============================================================================
# READ (host and clients)
# =============================================================================


## True while the session is in the room (no table out).
func is_open() -> bool:
	return _open


## The ref_key() of the map on the table, or "" in the room.
func get_table() -> String:
	return _table


## The ref_key() of the GM's selected shelf map, or "".
func get_selected() -> String:
	return _selected


## The maps set out this session, oldest first (MapRef copies).
func get_shelf() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for ref in _shelf:
		copy.append(ref.duplicate(true))
	return copy


## session id -> {"name", "peer_id"} (a copy). peer_id is 0 for a player who left.
func get_players() -> Dictionary:
	return _players.duplicate(true)


## session id -> the ref_key()s of the shelf maps that player holds (a copy). On the host its
## own entry holds every shelf map.
func get_holdings() -> Dictionary:
	var out := _holdings.duplicate(true)
	if NetworkManager.is_host():
		var host_id := session_id_of(1)
		if host_id != "":
			out[host_id] = _shelf_keys()
	return out


func _shelf_keys() -> Array:
	return _shelf.map(func(ref: Dictionary) -> String: return ref_key(ref))


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


## Host: tell every client the table moves in `seconds` (`kind` a TableMoveNotice.Kind,
## `map_name` where it goes), so each shows the notice the GM sees (TableMover).
func announce_move(kind: int, map_name: String, seconds: float) -> void:
	if _can_send():
		_rpc_table_moving.rpc(kind, _clip(map_name), seconds)


## Host: the move announced is off; every client drops its notice.
func cancel_move() -> void:
	if _can_send():
		_rpc_table_move_cancelled.rpc()


## Host: put a map on the shelf without setting it out (the GM adds it from the room), with
## the host's map hashes; one already there keeps its place. Returns its ref_key(), or "" on a
## client or for a level with neither a folder nor a map path.
func shelve(level_dict: Dictionary) -> String:
	if not NetworkManager.is_host():
		return ""
	var ref := map_ref(NetworkManager.with_map_hashes(level_dict))
	var key := ref_key(ref)
	if key == "":
		return ""
	if not _shelf_keys().has(key):
		_shelf.append(ref)
		_publish()
	return key


## Host: the GM selected the shelf map `key` ("" for none) in the room or the drawer; clients
## fetch it right after the map on the table. A key not on the shelf selects nothing.
func select_map(key: String) -> void:
	if not NetworkManager.is_host():
		return
	var selected := key if _shelf_keys().has(key) else ""
	if selected != _selected:
		_selected = selected
		_publish()


## Host: take the map `key` off the shelf. The map on the table stays. Its holdings,
## progress and selection go, the host stops sending its files to anyone (it is no longer
## served), and each client drops its fetch of it on the summary. Returns whether it was
## taken off.
func unshelve(key: String) -> bool:
	if not NetworkManager.is_host() or key == "" or key == _table:
		return false
	var index := _shelf.find_custom(func(r: Dictionary) -> bool: return ref_key(r) == key)
	if index < 0:
		return false
	var folder := str(_shelf[index].get("folder", ""))
	_shelf.remove_at(index)
	for id: String in _holdings:
		(_holdings[id] as Array).erase(key)
	if _selected == key:
		_selected = ""
	prefetch.forget_map(key)
	if folder != "" and AssetManager.streamer:
		AssetManager.streamer.drop_level_transfers(folder)
	_publish()
	return true


## Host: the level folders whose map files the host serves (the whitelist AssetStreamer
## checks every level map request against): the map on the table and every shelf map.
func servable_folders() -> Array:
	return servable(NetworkManager.get_current_level_folder(), _shelf)


## The folders `table_folder` and the folder maps of `shelf` (MapRefs), each once. Pure.
static func servable(table_folder: String, shelf: Array) -> Array:
	var out: Array = []
	if table_folder != "":
		out.append(table_folder)
	for ref: Dictionary in shelf:
		var folder := str(ref.get("folder", ""))
		if folder != "" and not out.has(folder):
			out.append(folder)
	return out


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


## The MapRef of a level dictionary: its folder, its map path when it has no folder, its
## sanitized map hashes and its name. Pure.
static func map_ref(level_dict: Dictionary) -> Dictionary:
	var folder := str(level_dict.get("level_folder", ""))
	return {
		"folder": folder,
		"map_path": str(level_dict.get("map_path", "")) if folder == "" else "",
		"hashes": MapFileHash.sanitize(level_dict.get(MapFileHash.HASHES_KEY, {})),
		"name": _clip(level_dict.get("level_name", "")),
	}


## Whether this peer holds the map `ref` names at the host's content: a map that ships with
## the game (no folder), or every hashed file found in its own level folder with the same
## hash or in the download cache (`cached_file`, AssetStreamer.get_cached_map_file's
## signature). A folder map the host sent no hashes for is not counted as held.
static func holds_map(ref: Dictionary, cached_file: Callable) -> bool:
	if str(ref.get("folder", "")) == "":
		return true
	if (ref.get("hashes", {}) as Dictionary).is_empty():
		return false
	return missing_variants(ref, cached_file).is_empty()


## The map files (variant ids) of `ref` this peer lacks at the host's content: each hashed
## file not in its own level folder with the same hash nor in the download cache
## (`cached_file`, as for holds_map()). None for a map that ships with the game or one the
## host sent no hashes for (nothing to fetch).
static func missing_variants(ref: Dictionary, cached_file: Callable) -> Array:
	var folder := str(ref.get("folder", ""))
	var missing: Array = []
	if folder == "":
		return missing
	var hashes: Dictionary = ref.get("hashes", {})
	for variant: String in hashes:
		var expected := str(hashes[variant])
		var local := Paths.get_level_map_file_for_variant(folder, variant)
		if local != "" and FileAccess.file_exists(local):
			if MapFileHash.hash_file_cached(local) == expected:
				continue
		if str(cached_file.call(folder, variant, expected)) == "":
			missing.append(variant)
	return missing


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
	_selected = ""
	_players.clear()
	_holdings.clear()
	_reported = []
	if party:
		party.reset()
	if prefetch:
		prefetch.reset()


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
	prefetch.forget_player(session_id_value)
	_publish()


func _can_send() -> bool:
	return multiplayer.multiplayer_peer != null and NetworkManager.is_host()


## The summary clients keep: the phase, the table pointer, the shelf, the players, what each
## holds of the shelf, the GM's selected map and what each is getting (percent per map).
func summary() -> Dictionary:
	return {
		"open": _open,
		"table": _table,
		"shelf": get_shelf(),
		"players": get_players(),
		"holdings": get_holdings(),
		"selected": _selected,
		"progress": prefetch.get_progress() if prefetch else {},
	}


func _publish() -> void:
	if _can_send():
		_rpc_session_summary.rpc(summary())
	session_changed.emit()


## A host's summary as a client may keep it: known keys and types only, bounded sizes,
## hashes through MapFileHash.sanitize. Pure.
static func sanitize_summary(raw: Variant) -> Dictionary:
	var out := {
		"open": false,
		"table": "",
		"shelf": [],
		"players": {},
		"holdings": {},
		"selected": "",
		"progress": {},
	}
	if not raw is Dictionary:
		return out
	var summary_in: Dictionary = raw
	out.open = summary_in.get("open") is bool and bool(summary_in.open)
	out.table = _clip(summary_in.get("table", ""))
	out.selected = _clip(summary_in.get("selected", ""))
	out.progress = SessionPrefetch.sanitize_progress(summary_in.get("progress", {}))
	var shelf: Variant = summary_in.get("shelf", [])
	if shelf is Array:
		for ref: Variant in (shelf as Array).slice(0, MAX_SHELF):
			if ref is Dictionary:
				out.shelf.append(
					{
						"folder": _clip(ref.get("folder", "")),
						"map_path": _clip(ref.get("map_path", "")),
						"hashes": MapFileHash.sanitize(ref.get("hashes", {})),
						"name": _clip(ref.get("name", "")),
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
	var holdings: Variant = summary_in.get("holdings", {})
	if holdings is Dictionary:
		for key: Variant in (holdings as Dictionary).keys().slice(0, MAX_SESSION_PLAYERS):
			if key is String:
				out.holdings[_clip(key)] = clean_keys(holdings[key])
	return out


## A list of ref keys as the session may keep it: strings only, at most MAX_SHELF, each
## clipped. Pure.
static func clean_keys(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for key: Variant in (raw as Array).slice(0, MAX_SHELF):
			if key is String:
				out.append(_clip(key))
	return out


static func _clip(value: Variant) -> String:
	return (value as String).left(MAX_TEXT) if value is String else ""


## RPC: host -> client, the room is open.
@rpc("authority", "reliable")
func _rpc_room_opened() -> void:
	_open = true
	_table = ""
	# Back in the room the map just left is in the cache: say so even if nothing else changed.
	_reported = []
	report_holdings()
	room_opened.emit()


## RPC: host -> clients, the table moves soon (untrusted: the kind an int or -1, the name
## clipped, the seconds bounded).
@rpc("authority", "reliable")
func _rpc_table_moving(kind: Variant, map_name: Variant, seconds: Variant) -> void:
	if NetworkManager.is_host():
		return
	var left := float(seconds) if seconds is float or seconds is int else 0.0
	var move := int(kind) if kind is int else -1
	table_moving.emit(move, _clip(map_name), clampf(left, 0.0, MAX_NOTICE_S))


## RPC: host -> clients, the move is off.
@rpc("authority", "reliable")
func _rpc_table_move_cancelled() -> void:
	if not NetworkManager.is_host():
		table_move_cancelled.emit()


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
	_holdings = clean.holdings
	_selected = clean.selected
	prefetch.set_progress(clean.progress)
	report_holdings()
	session_changed.emit()


## Client: tell the host which shelf maps this peer holds, when that changed since the last
## report (after a summary, back in the room, and when a fetch finishes).
func report_holdings() -> void:
	if NetworkManager.is_host():
		return
	var streamer: Node = AssetManager.streamer
	var cached := func(folder: String, variant: String, expected: String) -> String:
		return streamer.get_cached_map_file(folder, variant, expected) if streamer else ""
	var held: Array = []
	for ref in _shelf:
		if holds_map(ref, cached):
			held.append(ref_key(ref))
	if held == _reported:
		return
	_reported = held
	# Only a connected client reports: GUT's offline peer is peer 1, the host itself.
	if (
		NetworkManager.is_client()
		and multiplayer.multiplayer_peer != null
		and multiplayer.get_unique_id() != 1
	):
		_rpc_report_holdings.rpc_id(1, held)


## RPC: client -> host, the shelf maps the sender holds (untrusted: only keys on the shelf
## are kept, under the sender's own session id).
@rpc("any_peer", "reliable")
func _rpc_report_holdings(raw: Variant) -> void:
	if not NetworkManager.is_host():
		return
	var session_id_value := session_id_of(multiplayer.get_remote_sender_id())
	if session_id_value == "":
		return
	note_holdings(session_id_value, raw)


## Host: record what `session_id_value` reports it holds, keeping only shelf keys. Publishes
## when that changed.
func note_holdings(session_id_value: String, raw: Variant) -> void:
	var shelf_keys := _shelf_keys()
	var held := clean_keys(raw).filter(func(key: String) -> bool: return shelf_keys.has(key))
	if _holdings.get(session_id_value, []) == held:
		return
	_holdings[session_id_value] = held
	_publish()
