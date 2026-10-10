class_name SessionParty
extends Node

## The party: the players' avatars, which belong to the session rather than to a map, and
## the CONTROL grants that make them a player's, kept by session id. Host only; a child of
## SessionChannel (NetworkManager.session.party), node /root/NetworkManager/Session/Party.
##
## Grants. GameState keeps CONTROL grants by the peer ids at the table: a leave clears the
## leaver's (TokenPermissionHandler) and a level change clears them all. The party keeps every
## deliberate grant (GameState.token_permission_granted and _revoked) by session id in
## `_grants` (session id -> Array of network ids), and drops a token's when the token goes
## (GameState.token_removed, which a table's teardown emits for every token). A player who
## rejoins, with a new peer id and the same session id, gets its grants back on the tokens
## still out (restore_grants(), from SessionChannel.admit_peer before any table state is sent).
##
## Members. A member is an avatar token (TokenState.avatar_recipe set) that a session player
## controls. When a player is granted an avatar at a table it leaves the map's placements
## (adopted: saving the map no longer writes it); when its last owner loses it, it is the
## map's again. Before a table goes (Return everyone to the room, or a map change in play)
## Root calls take(): each member as a TokenState dict and its owners' session ids, plain data
## a session file can write. Once the next map has loaded Root calls set_out(): each member is
## rebuilt under its own network id outside that map's placements, set down around the map's
## spawn point (LevelData.spawn_point) or, without one, the camera's ground point, grounded
## (TokenGrounding), granted again to each owner connected now (an owner who is away gets it
## on rejoining), and sent to every peer in one full state. A client that was already
## connected gets that full state again once it reports its table loaded: a state that lands
## before its loader's clear is wiped (see LateJoinerSync).

## Members land on a square-ish block this far apart (one 5 ft square).
const SPACING_M := 1.524

## session id -> Array[String] of the network ids that player controls
var _grants: Dictionary = {}
## The party between tables: {"state": TokenState dict, "owners": Array[String]} each
var _members: Array[Dictionary] = []
## Clients that get the full state again on their table-loaded report (see the class doc)
var _awaiting: Array[int] = []
## Root's LevelPlayController, the table the party lands on (attach())
var _controller: LevelPlayController = null


func _ready() -> void:
	GameState.token_permission_granted.connect(_on_permission_granted)
	GameState.token_permission_revoked.connect(_on_permission_revoked)
	GameState.token_removed.connect(_on_token_removed)


## Give the party the table it lands on: Root's LevelPlayController, which lives as long as
## Root does.
func attach(controller: LevelPlayController) -> void:
	_controller = controller
	if not NetworkManager.table_loaded.is_connected(_on_table_loaded):
		NetworkManager.table_loaded.connect(_on_table_loaded)


# =============================================================================
# READ
# =============================================================================


## session id -> the network ids that player controls (a copy).
func get_grants() -> Dictionary:
	return _grants.duplicate(true)


## The session ids that control `network_id`.
func owners_of(network_id: String) -> Array[String]:
	return owners(_grants, network_id)


## The party as taken, between tables (a copy): {"state", "owners"} each.
func get_members() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for member in _members:
		copy.append(member.duplicate(true))
	return copy


## True when there is no party waiting for a table.
func is_empty() -> bool:
	return _members.is_empty()


# =============================================================================
# HOST
# =============================================================================


## Forget the party and its grants (a session began or ended).
func reset() -> void:
	_grants.clear()
	_members.clear()
	_awaiting.clear()


## Host: take the party before the table is cleared. Members not yet set out (a map change
## while one was loading) stay. Returns how many members there are.
func take() -> int:
	if not NetworkManager.is_host():
		return 0
	var taken := members_of(GameState.get_all_token_states(), _grants)
	var ids := taken.map(func(m: Dictionary) -> String: return str(m.state.get("network_id")))
	for member in _members:
		if str(member.state.get("network_id")) not in ids:
			taken.append(member)
	_members = taken
	_awaiting.clear()
	return _members.size()


## Host: set the party out on the map that has just loaded (Root, on level_loaded). Returns
## how many members were placed; grounding and the full state follow a physics frame later,
## once the map's collision is in the physics space.
func set_out() -> int:
	if _members.is_empty() or not NetworkManager.is_host() or not is_instance_valid(_controller):
		return 0
	var game_map := _controller.get_game_map()
	if game_map == null:
		return 0
	var spots := landing_spots(landing_point(_controller.active_level_data, game_map), _members.size())
	var placed: Array[BoardToken] = []
	var claimed := 0
	for member in _members:
		var state := TokenState.from_dict(member.state)
		var owners_now: Array = member.owners
		if GameState.has_token(state.network_id):
			# The map brought it back itself (a placement saved before it was adopted).
			_claim(state.network_id, owners_now)
			claimed += 1
			continue
		state.position = spots[placed.size()]
		var token := _controller.place_session_token(state)
		if token == null:
			continue
		token.hide()
		_claim(state.network_id, owners_now)
		placed.append(token)
	_members.clear()
	if not placed.is_empty() or claimed > 0:
		_ground_and_send(placed, game_map)
	return placed.size()


## Host: drop every session grant on `network_id`, of players here and away (the GM took its
## control back from everyone). Its peer grants are revoked by the caller.
func revoke_all(network_id: String) -> void:
	if not NetworkManager.is_host():
		return
	for session_id in _grants.keys():
		_remove_grant(session_id, network_id)
	_return_to_map(network_id)


## Host: the player `session_id`, now on `peer_id`, gets its grants back on the tokens out at
## the table, and every peer hears of it. Returns how many it got back.
func restore_grants(session_id: String, peer_id: int) -> int:
	if not NetworkManager.is_host() or peer_id <= 0:
		return 0
	var restored := 0
	for network_id: String in _grants.get(session_id, []).duplicate():
		if GameState.has_token(network_id):
			restored += int(
				GameState.grant_token_permission(
					network_id, peer_id, TokenPermissions.Permission.CONTROL
				)
			)
	if restored > 0 and _can_send():
		NetworkManager.permissions.broadcast_token_permissions(
			TokenPermissions.to_dict(GameState.get_token_permissions())
		)
	return restored


# =============================================================================
# PURE
# =============================================================================


## The party at a table: every avatar in `states` (network id -> TokenState) that a session
## id in `grants` controls, as {"state": TokenState dict, "owners": session ids}. Pure.
static func members_of(states: Dictionary, grants: Dictionary) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	for network_id: String in states:
		var state: TokenState = states[network_id]
		var owned_by := owners(grants, network_id)
		if state.avatar_recipe.is_empty() or owned_by.is_empty():
			continue
		members.append({"state": state.to_dict(), "owners": owned_by})
	return members


## The session ids in `grants` that control `network_id`, sorted. Pure.
static func owners(grants: Dictionary, network_id: String) -> Array[String]:
	var found: Array[String] = []
	for session_id: String in grants:
		if network_id in grants[session_id]:
			found.append(session_id)
	found.sort()
	return found


## `count` spots on a square-ish block centred on `centre`, `spacing` apart in X and Z, row
## by row. Pure.
static func landing_spots(
	centre: Vector3, count: int, spacing: float = SPACING_M
) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	if count <= 0:
		return spots
	var columns := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / columns)
	for i in count:
		var column := i % columns
		var row := floori(float(i) / columns)
		spots.append(
			(
				centre
				+ Vector3(
					(column - (columns - 1) / 2.0) * spacing, 0.0, (row - (rows - 1) / 2.0) * spacing
				)
			)
		)
	return spots


## Where the party lands on `level`: its spawn point, else the camera's ground point.
static func landing_point(level: LevelData, game_map: GameMap) -> Vector3:
	if level != null and level.has_spawn_point:
		return level.spawn_point
	return camera_ground_point(game_map)


## Where the centre of `game_map`'s view meets the Y=0 plane, as the asset browser places a
## new token; the camera holder's X/Z when the view never meets it, the origin without a
## camera.
static func camera_ground_point(game_map: GameMap) -> Vector3:
	if game_map == null or game_map.camera_node == null or game_map.world_viewport == null:
		return Vector3.ZERO
	var centre := Vector2(game_map.world_viewport.size) / 2.0
	var origin := game_map.camera_node.project_ray_origin(centre)
	var direction := game_map.camera_node.project_ray_normal(centre)
	if absf(direction.y) < 0.0001 or -origin.y / direction.y < 0.0:
		var holder := game_map.cameraholder_node.global_position
		return Vector3(holder.x, 0.0, holder.z)
	var hit := origin - direction * (origin.y / direction.y)
	return Vector3(hit.x, 0.0, hit.z)


# =============================================================================
# INTERNAL
# =============================================================================


## A member on the new table: its owners' session grants come back, and each owner connected
## now is granted it (which adopts it, _on_permission_granted).
func _claim(network_id: String, owners_now: Array) -> void:
	for session_id: String in owners_now:
		_add_grant(session_id, network_id)
		var peer_id := NetworkManager.session.peer_for(session_id)
		if peer_id > 0 and NetworkManager.get_players().has(peer_id):
			GameState.grant_token_permission(
				network_id, peer_id, TokenPermissions.Permission.CONTROL
			)
	_adopt(network_id)


## A physics frame after set_out(): sets each placed member down on the map, shows it with
## its arrival, and sends every peer the table's full state.
func _ground_and_send(tokens: Array[BoardToken], game_map: GameMap) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(game_map) or game_map.is_queued_for_deletion():
		return
	var cast_top := TokenGrounding.cast_top(game_map)
	for token in tokens:
		if not is_instance_valid(token) or not GameState.has_token(token.network_id):
			continue
		TokenGrounding.reground(token, cast_top)
		GameState.sync_from_board_token(token)
		token.show()
		token.play_spawn_animation()
	if _can_send():
		_awaiting.assign(multiplayer.get_peers())
		NetworkStateSync.broadcast_full_state()


func _add_grant(session_id: String, network_id: String) -> void:
	if session_id == "":
		return
	var ids: Array = _grants.get_or_add(session_id, [])
	if network_id not in ids:
		ids.append(network_id)


func _remove_grant(session_id: String, network_id: String) -> void:
	var ids: Array = _grants.get(session_id, [])
	ids.erase(network_id)
	if ids.is_empty():
		_grants.erase(session_id)


## A player's avatar leaves the map's placements.
func _adopt(network_id: String) -> void:
	if _is_avatar(network_id) and is_instance_valid(_controller):
		_controller.release_placement(network_id)


## An avatar no player owns is the map's again.
func _return_to_map(network_id: String) -> void:
	if owners_of(network_id).is_empty() and _is_avatar(network_id):
		if is_instance_valid(_controller):
			_controller.restore_placement(network_id)


func _is_avatar(network_id: String) -> bool:
	var state := GameState.get_token_state(network_id)
	return state != null and not state.avatar_recipe.is_empty()


func _can_send() -> bool:
	return multiplayer.multiplayer_peer != null and NetworkManager.is_host()


func _on_permission_granted(network_id: String, peer_id: int, permission: int) -> void:
	if not NetworkManager.is_host() or permission != TokenPermissions.Permission.CONTROL:
		return
	var session_id := NetworkManager.session.session_id_of(peer_id)
	if session_id == "":
		return
	_add_grant(session_id, network_id)
	_adopt(network_id)


func _on_permission_revoked(network_id: String, peer_id: int, permission: int) -> void:
	if not NetworkManager.is_host() or permission != TokenPermissions.Permission.CONTROL:
		return
	var session_id := NetworkManager.session.session_id_of(peer_id)
	if session_id == "":
		return
	_remove_grant(session_id, network_id)
	_return_to_map(network_id)


func _on_token_removed(network_id: String) -> void:
	if not NetworkManager.is_host():
		return
	for session_id in _grants.keys():
		_remove_grant(session_id, network_id)


## Host: a client that was connected when the party was sent reports its table built; it gets
## the full state again (see the class doc).
func _on_table_loaded(peer_id: int) -> void:
	if peer_id not in _awaiting:
		return
	_awaiting.erase(peer_id)
	if _can_send() and peer_id in multiplayer.get_peers():
		NetworkStateSync.send_full_state_to_peer(peer_id)
