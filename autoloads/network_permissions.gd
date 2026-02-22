extends Node
class_name NetworkPermissions

## Token permission request/response sub-component of NetworkManager.
##
## Handles the three permission RPC channels (request, response, broadcast)
## and re-emits them as typed signals for game-logic consumers.
##
## Accessed via NetworkManager.permissions — do not add as a standalone autoload.

signal token_permission_requested(network_id: String, peer_id: int, permission_type: int)
signal token_permission_response_received(network_id: String, permission_type: int, approved: bool)
signal token_permissions_received(permissions_dict: Dictionary)


## Called by client to request permission for a token
func request_token_permission(network_id: String, permission_type: int) -> void:
	_rpc_request_token_permission.rpc_id(1, network_id, permission_type)


## Called by host to send permission response to a specific client
func send_permission_response(
	peer_id: int, network_id: String, permission_type: int, approved: bool
) -> void:
	_rpc_token_permission_response.rpc_id(peer_id, network_id, permission_type, approved)


## Called by host to broadcast permissions to all clients
func broadcast_token_permissions(permissions_dict: Dictionary) -> void:
	_rpc_sync_token_permissions.rpc(permissions_dict)


## RPC: Player requests permission for a token (client -> host)
@rpc("any_peer", "reliable")
func _rpc_request_token_permission(network_id: String, permission_type: int) -> void:
	if not NetworkManager.is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
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
