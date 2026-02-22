extends Node
class_name TokenPermissionHandler

## Manages all token permission request/response logic for a level session.
##
## Handles the full request-approval-denial-sync flow between clients and host.
## Connects to NetworkManager signals during setup() and disconnects in _exit_tree().
##
## Usage:
##   var handler = TokenPermissionHandler.new()
##   add_child(handler)
##   handler.setup()

## Pending requests: "network_id:peer_id" -> true (host-side, deduplication)
var _pending_permission_requests: Dictionary = {}


func setup() -> void:
	if not NetworkManager.token_permission_requested.is_connected(_on_token_permission_requested):
		NetworkManager.token_permission_requested.connect(_on_token_permission_requested)
	if not NetworkManager.token_permission_response_received.is_connected(
		_on_permission_response_received
	):
		NetworkManager.token_permission_response_received.connect(_on_permission_response_received)
	if not NetworkManager.token_permissions_received.is_connected(_on_permissions_received):
		NetworkManager.token_permissions_received.connect(_on_permissions_received)
	if not NetworkManager.player_left.is_connected(_on_player_left_permissions):
		NetworkManager.player_left.connect(_on_player_left_permissions)


func _exit_tree() -> void:
	if NetworkManager.token_permission_requested.is_connected(_on_token_permission_requested):
		NetworkManager.token_permission_requested.disconnect(_on_token_permission_requested)
	if NetworkManager.token_permission_response_received.is_connected(
		_on_permission_response_received
	):
		NetworkManager.token_permission_response_received.disconnect(
			_on_permission_response_received
		)
	if NetworkManager.token_permissions_received.is_connected(_on_permissions_received):
		NetworkManager.token_permissions_received.disconnect(_on_permissions_received)
	if NetworkManager.player_left.is_connected(_on_player_left_permissions):
		NetworkManager.player_left.disconnect(_on_player_left_permissions)


## Host-side: handle a permission request from a player.
## Shows a confirmation dialog to the DM.
func _on_token_permission_requested(network_id: String, peer_id: int, permission_type: int) -> void:
	if not NetworkManager.is_host():
		return

	# Prevent duplicate requests
	var request_key = "%s:%d" % [network_id, peer_id]
	if _pending_permission_requests.has(request_key):
		return
	_pending_permission_requests[request_key] = true

	# Look up names for the dialog
	var player_name = "Player"
	var players = NetworkManager.get_players()
	if players.has(peer_id):
		player_name = players[peer_id].get("name", "Player")

	var token_name = "Unknown Token"
	var token_state = GameState.get_token_state(network_id)
	if token_state:
		token_name = token_state.token_name

	var permission_name = "Control"
	if permission_type == TokenPermissions.Permission.CONTROL:
		permission_name = "Control (move/rotate/scale)"

	# Show confirmation dialog to DM
	var dialog = UIManager.show_confirmation(
		"Token Control Request",
		'%s wants to control "%s".\n\nPermission: %s' % [player_name, token_name, permission_name],
		"Approve",
		"Deny",
		func(): _approve_permission_request(network_id, peer_id, permission_type, request_key),
		func(): _deny_permission_request(network_id, peer_id, permission_type, request_key),
	)
	# Clean up pending state if dialog is dismissed or destroyed (e.g., scene change)
	if dialog:
		if dialog.has_signal("closed"):
			dialog.closed.connect(
				func(_confirmed: bool): _pending_permission_requests.erase(request_key),
				CONNECT_ONE_SHOT,
			)
		dialog.tree_exiting.connect(
			func(): _pending_permission_requests.erase(request_key),
			CONNECT_ONE_SHOT,
		)


## Host-side: approve a permission request.
func _approve_permission_request(
	network_id: String, peer_id: int, permission_type: int, request_key: String
) -> void:
	_pending_permission_requests.erase(request_key)

	# Guard: peer may have disconnected while DM was deciding
	if not NetworkManager.get_players().has(peer_id):
		UIManager.show_warning("Player disconnected before approval could be sent")
		return

	GameState.grant_token_permission(network_id, peer_id, permission_type)

	# Send response to the requesting client
	NetworkManager.send_permission_response(peer_id, network_id, permission_type, true)

	# Broadcast updated permissions to all clients
	NetworkManager.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)

	# Show toast on host
	var token_state = GameState.get_token_state(network_id)
	var token_name = token_state.token_name if token_state else "token"
	var players = NetworkManager.get_players()
	var player_name = players[peer_id].get("name", "Player") if players.has(peer_id) else "Player"
	UIManager.show_success('%s can now control "%s"' % [player_name, token_name])


## Host-side: deny a permission request.
func _deny_permission_request(
	network_id: String, peer_id: int, permission_type: int, request_key: String
) -> void:
	_pending_permission_requests.erase(request_key)
	# Only send denial if peer is still connected
	if NetworkManager.get_players().has(peer_id):
		NetworkManager.send_permission_response(peer_id, network_id, permission_type, false)


## Client-side: handle permission response from host.
func _on_permission_response_received(
	network_id: String, _permission_type: int, approved: bool
) -> void:
	if NetworkManager.is_host():
		return

	var token_state = GameState.get_token_state(network_id)
	var token_name = token_state.token_name if token_state else "token"

	if approved:
		UIManager.show_success('Control granted for "%s"!' % token_name)
	else:
		UIManager.show_warning('Control request for "%s" was denied' % token_name)


## Client-side: handle full permission sync from host.
func _on_permissions_received(permissions_dict: Dictionary) -> void:
	if NetworkManager.is_host():
		return
	GameState.apply_token_permissions(permissions_dict)


## Host-side: clean up permissions when a player disconnects.
func _on_player_left_permissions(peer_id: int, _player_info: Dictionary) -> void:
	if not NetworkManager.is_host():
		return

	# Check if the disconnected player had any permissions
	var controlled = GameState.get_controlled_tokens(peer_id, TokenPermissions.Permission.CONTROL)
	if controlled.is_empty():
		return

	# Revoke all permissions for the disconnected player
	GameState.clear_permissions_for_peer(peer_id)

	# Broadcast updated permissions to remaining clients
	NetworkManager.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)

	# Clean up any pending requests from this peer
	var keys_to_remove: Array[String] = []
	for key in _pending_permission_requests:
		if key.ends_with(":%d" % peer_id):
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_pending_permission_requests.erase(key)
