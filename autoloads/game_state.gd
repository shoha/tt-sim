extends Node

## Centralized game state manager for network synchronization.
## This autoload maintains the authoritative state of all tokens and game data.
##
## Architecture:
##   - Single source of truth for all synchronized game state
##   - Emits signals when state changes (for UI/visual updates)
##   - Designed to integrate with netfox for network synchronization
##
## Network Model:
##   - Host: Has full authority, makes all state changes
##   - Clients: Receive state updates, cannot modify directly
##   - All state mutations go through this class
##
## Usage:
##   GameState.update_token_position(network_id, new_position)
##   GameState.token_state_changed.connect(_on_token_changed)

## Emitted when any property of a token changes
signal token_state_changed(network_id: String, property: String, old_value: Variant, new_value: Variant)

## Emitted when a new token is added to the game
signal token_added(network_id: String, state: TokenState)

## Emitted when a token is removed from the game
signal token_removed(network_id: String)

## Emitted when the entire game state is reset (e.g., level change)
signal state_reset()

## Emitted when a batch of state changes completes (for network sync optimization)
signal state_batch_complete()

## Emitted when a token permission is granted or revoked
signal permissions_changed(network_id: String, peer_id: int)


## Dictionary of all token states: network_id -> TokenState
var _token_states: Dictionary = {}

## Per-token, per-player permissions: managed by TokenPermissions static class.
## Structure: { network_id -> { peer_id -> Array[TokenPermissions.Permission] } }
## Session-only -- not saved to level files.
var _token_permissions: Dictionary = {}

## Flag indicating if we're currently in a batch update (suppresses individual signals)
var _batch_updating: bool = false

## Pending changes during batch update
var _pending_changes: Array[Dictionary] = []


# =============================================================================
# AUTHORITY CHECKS
# =============================================================================

## Check if this client has authority to modify game state.
## In single-player, always returns true.
## In networked games, returns true only for the host.
func has_authority() -> bool:
	return NetworkManager.is_host() or not NetworkManager.is_networked()


## Check if we're in a networked game
func is_networked() -> bool:
	return NetworkManager.is_networked()


# =============================================================================
# TOKEN STATE MANAGEMENT
# =============================================================================

## Get a token's state by network_id
func get_token_state(network_id: String) -> TokenState:
	return _token_states.get(network_id, null)


## Set a token's state directly (for network sync on clients)
## This bypasses authority checks since it's used for applying received state
func set_token_state(network_id: String, state: TokenState) -> void:
	var is_new = not _token_states.has(network_id)
	_token_states[network_id] = state
	if is_new:
		token_added.emit(network_id, state)
	else:
		token_state_changed.emit(network_id, "_all", null, state)


## Remove a token's state (for network sync on clients)
## This bypasses authority checks since it's used for applying received state
func remove_token_state(network_id: String) -> void:
	if _token_states.has(network_id):
		_token_states.erase(network_id)
		clear_permissions_for_token(network_id)
		token_removed.emit(network_id)


## Get all token states
func get_all_token_states() -> Dictionary:
	return _token_states.duplicate()


## Get token states filtered for a specific client (respects visibility)
func get_visible_token_states(client_id: String, is_gm: bool = false) -> Dictionary:
	var result: Dictionary = {}
	for network_id in _token_states:
		var state: TokenState = _token_states[network_id]
		if state.should_sync_to_client(client_id, is_gm):
			result[network_id] = state
	return result


## Check if a token exists
func has_token(network_id: String) -> bool:
	return _token_states.has(network_id)


## Get the count of tokens
func get_token_count() -> int:
	return _token_states.size()


# =============================================================================
# STATE MUTATIONS (Authority Required)
# =============================================================================

## Register a new token in the game state
## Returns true if successful, false if no authority or ID already exists
func register_token(state: TokenState) -> bool:
	if not has_authority():
		push_warning("GameState: Cannot register token - no authority")
		return false

	if _token_states.has(state.network_id):
		push_warning("GameState: Token already exists: " + state.network_id)
		return false

	_token_states[state.network_id] = state
	token_added.emit(state.network_id, state)
	return true


## Register a token from a BoardToken instance
func register_token_from_board_token(token: BoardToken) -> bool:
	var state = TokenState.from_board_token(token)
	return register_token(state)


## Remove a token from the game state
func remove_token(network_id: String) -> bool:
	if not has_authority():
		push_warning("GameState: Cannot remove token - no authority")
		return false

	if not _token_states.has(network_id):
		return false

	_token_states.erase(network_id)
	clear_permissions_for_token(network_id)
	token_removed.emit(network_id)
	return true


## Update a specific property of a token
func update_token_property(network_id: String, property: String, value: Variant) -> bool:
	if not has_authority():
		push_warning("GameState: Cannot update token - no authority")
		return false

	var state: TokenState = _token_states.get(network_id, null)
	if not state:
		push_warning("GameState: Token not found: " + network_id)
		return false

	var old_value = state.get(property)
	if old_value == value:
		return true # No change needed

	state.set(property, value)

	if _batch_updating:
		_pending_changes.append({
			"network_id": network_id,
			"property": property,
			"old_value": old_value,
			"new_value": value
		})
	else:
		token_state_changed.emit(network_id, property, old_value, value)

	return true


## Convenience methods for common property updates

func update_token_position(network_id: String, position: Vector3) -> bool:
	return update_token_property(network_id, "position", position)


func update_token_rotation(network_id: String, rotation: Vector3) -> bool:
	return update_token_property(network_id, "rotation", rotation)


func update_token_scale(network_id: String, scale: Vector3) -> bool:
	return update_token_property(network_id, "scale", scale)


func update_token_health(network_id: String, current: int, max_hp: int = -1) -> bool:
	var success = update_token_property(network_id, "current_health", current)
	if max_hp >= 0:
		success = success and update_token_property(network_id, "max_health", max_hp)
	return success


func update_token_visibility(network_id: String, visible: bool) -> bool:
	return update_token_property(network_id, "is_visible_to_players", visible)


func update_token_alive(network_id: String, alive: bool) -> bool:
	return update_token_property(network_id, "is_alive", alive)


## Update multiple properties at once (more efficient for network)
func update_token_properties(network_id: String, properties: Dictionary) -> bool:
	if not has_authority():
		push_warning("GameState: Cannot update token - no authority")
		return false

	begin_batch_update()
	var success = true
	for property in properties:
		if not update_token_property(network_id, property, properties[property]):
			success = false
	end_batch_update()
	return success


## Apply a full TokenState (replaces all properties)
func apply_token_state(state: TokenState) -> bool:
	if not has_authority():
		push_warning("GameState: Cannot apply state - no authority")
		return false

	if not _token_states.has(state.network_id):
		return register_token(state)

	# Replace the existing state
	_token_states[state.network_id] = state
	# Emit a generic "replaced" signal
	token_state_changed.emit(state.network_id, "_all", null, state)
	return true


# =============================================================================
# TOKEN PERMISSIONS
# =============================================================================


## Grant a permission to a peer for a specific token.
## Returns true if newly granted, false if already present.
func grant_token_permission(
	network_id: String, peer_id: int, permission: TokenPermissions.Permission
) -> bool:
	var changed = TokenPermissions.grant(_token_permissions, network_id, peer_id, permission)
	if changed:
		permissions_changed.emit(network_id, peer_id)
	return changed


## Revoke a permission from a peer for a specific token.
## Returns true if removed, false if it wasn't present.
func revoke_token_permission(
	network_id: String, peer_id: int, permission: TokenPermissions.Permission
) -> bool:
	var changed = TokenPermissions.revoke(_token_permissions, network_id, peer_id, permission)
	if changed:
		permissions_changed.emit(network_id, peer_id)
	return changed


## Check if a peer has a specific permission for a token.
func has_token_permission(
	network_id: String, peer_id: int, permission: TokenPermissions.Permission
) -> bool:
	return TokenPermissions.has_permission(_token_permissions, network_id, peer_id, permission)


## Get all token network_ids that a peer has a specific permission for.
func get_controlled_tokens(
	peer_id: int, permission: TokenPermissions.Permission
) -> Array[String]:
	return TokenPermissions.get_controlled_tokens(_token_permissions, peer_id, permission)


## Get all peer_ids that have a specific permission for a token.
func get_peers_with_permission(
	network_id: String, permission: TokenPermissions.Permission
) -> Array[int]:
	return TokenPermissions.get_peers_with_permission(_token_permissions, network_id, permission)


## Remove all permissions for a specific peer (e.g., on disconnect).
func clear_permissions_for_peer(peer_id: int) -> void:
	var controlled = TokenPermissions.get_controlled_tokens(
		_token_permissions, peer_id, TokenPermissions.Permission.CONTROL
	)
	TokenPermissions.clear_for_peer(_token_permissions, peer_id)
	for network_id in controlled:
		permissions_changed.emit(network_id, peer_id)


## Remove all permissions for a specific token (e.g., on token removal).
func clear_permissions_for_token(network_id: String) -> void:
	var peers = TokenPermissions.get_peers_with_permission(
		_token_permissions, network_id, TokenPermissions.Permission.CONTROL
	)
	TokenPermissions.clear_for_token(_token_permissions, network_id)
	for peer_id in peers:
		permissions_changed.emit(network_id, peer_id)


## Clear all permissions (e.g., on level change).
func clear_all_permissions() -> void:
	_token_permissions.clear()


## Get the raw permissions dictionary (for serialization/sync).
func get_token_permissions() -> Dictionary:
	return _token_permissions


## Apply a full permissions dictionary (for network reception on clients).
func apply_token_permissions(permissions_dict: Dictionary) -> void:
	_token_permissions = TokenPermissions.from_dict(permissions_dict)
	permissions_changed.emit("", 0)  # Generic "everything changed" signal


# =============================================================================
# BATCH UPDATES
# =============================================================================

## Begin a batch update (suppresses individual signals until end_batch_update)
func begin_batch_update() -> void:
	_batch_updating = true
	_pending_changes.clear()


## End a batch update and emit accumulated signals
func end_batch_update() -> void:
	_batch_updating = false

	# Emit all pending changes
	for change in _pending_changes:
		token_state_changed.emit(
			change["network_id"],
			change["property"],
			change["old_value"],
			change["new_value"]
		)

	_pending_changes.clear()
	state_batch_complete.emit()


# =============================================================================
# STATE SYNCHRONIZATION
# =============================================================================

## Sync state from a BoardToken (call after token moves, etc.)
func sync_from_board_token(token: BoardToken) -> bool:
	if not has_authority():
		return false

	var network_id = token.network_id
	if not _token_states.has(network_id):
		return register_token_from_board_token(token)

	var old_state: TokenState = _token_states[network_id]
	var new_state := TokenState.from_board_token(token)
	var changes := old_state.diff(new_state)

	if changes.is_empty():
		return true

	begin_batch_update()
	for prop in changes:
		update_token_property(network_id, prop, changes[prop])
	end_batch_update()
	return true


## Apply state to a BoardToken (call when receiving network updates)
func apply_to_board_token(network_id: String, token: BoardToken) -> bool:
	var state: TokenState = _token_states.get(network_id, null)
	if not state:
		return false

	state.apply_to_token(token)
	return true


# =============================================================================
# LEVEL/STATE RESET
# =============================================================================

## Clear all token states and permissions (call when changing levels)
func clear_all_tokens() -> void:
	var ids = _token_states.keys()
	for network_id in ids:
		_token_states.erase(network_id)
		token_removed.emit(network_id)

	clear_all_permissions()
	state_reset.emit()


## Get the full state as a dictionary (for network transmission)
func get_full_state_dict() -> Dictionary:
	var result: Dictionary = {}
	var tokens: Dictionary = {}
	for network_id in _token_states:
		tokens[network_id] = _token_states[network_id].to_dict()
	result["tokens"] = tokens
	result["permissions"] = TokenPermissions.to_dict(_token_permissions)
	return result


## Apply a full state dictionary (for network reception on clients)
func apply_full_state_dict(data: Dictionary) -> void:
	# Support both new format (with "tokens" key) and legacy format (flat token dict)
	var token_data: Dictionary
	if data.has("tokens"):
		token_data = data["tokens"]
	else:
		token_data = data

	clear_all_tokens()
	for network_id in token_data:
		var state = TokenState.from_dict(token_data[network_id])
		_token_states[network_id] = state
		token_added.emit(network_id, state)

	# Apply permissions if present
	if data.has("permissions"):
		apply_token_permissions(data["permissions"])
