class_name TokenPermissions

## Static helper for per-token, per-player permission management.
## Provides the permission enum, pure query/mutation functions, and serialization.
##
## This is a stateless utility class (like Constants, Paths, SerializationUtils).
## The actual permissions dictionary lives in GameState._token_permissions.
##
## Dictionary structure:
##   { network_id: String -> { peer_id: int -> Array[int] (Permission values) } }
##
## Usage:
##   TokenPermissions.grant(perms, network_id, peer_id, Permission.CONTROL)
##   TokenPermissions.has_permission(perms, network_id, peer_id, Permission.CONTROL)


## Permission types that can be granted per-token, per-player.
## Extensible for future types (e.g., VIEW_HIDDEN, MODIFY_HP).
enum Permission {
	CONTROL,  ## Move, rotate, scale
}


## Grant a permission to a peer for a specific token.
## Returns true if the permission was newly granted, false if already present.
static func grant(
	permissions: Dictionary, network_id: String, peer_id: int, permission: Permission
) -> bool:
	if not permissions.has(network_id):
		permissions[network_id] = {}
	if not permissions[network_id].has(peer_id):
		permissions[network_id][peer_id] = []

	var perms: Array = permissions[network_id][peer_id]
	if permission in perms:
		return false

	perms.append(permission)
	return true


## Revoke a permission from a peer for a specific token.
## Returns true if the permission was removed, false if it wasn't present.
static func revoke(
	permissions: Dictionary, network_id: String, peer_id: int, permission: Permission
) -> bool:
	if not permissions.has(network_id):
		return false
	if not permissions[network_id].has(peer_id):
		return false

	var perms: Array = permissions[network_id][peer_id]
	var idx = perms.find(permission)
	if idx < 0:
		return false

	perms.remove_at(idx)

	# Clean up empty entries
	if perms.is_empty():
		permissions[network_id].erase(peer_id)
	if permissions[network_id].is_empty():
		permissions.erase(network_id)

	return true


## Check if a peer has a specific permission for a token.
static func has_permission(
	permissions: Dictionary, network_id: String, peer_id: int, permission: Permission
) -> bool:
	if not permissions.has(network_id):
		return false
	if not permissions[network_id].has(peer_id):
		return false
	return permission in permissions[network_id][peer_id]


## Get all token network_ids that a peer has a specific permission for.
static func get_controlled_tokens(
	permissions: Dictionary, peer_id: int, permission: Permission
) -> Array[String]:
	var result: Array[String] = []
	for network_id in permissions:
		if permissions[network_id].has(peer_id):
			if permission in permissions[network_id][peer_id]:
				result.append(network_id)
	return result


## Get all peer_ids that have a specific permission for a token.
static func get_peers_with_permission(
	permissions: Dictionary, network_id: String, permission: Permission
) -> Array[int]:
	var result: Array[int] = []
	if not permissions.has(network_id):
		return result
	for peer_id in permissions[network_id]:
		if permission in permissions[network_id][peer_id]:
			result.append(peer_id)
	return result


## Remove all permissions for a specific peer (e.g., on disconnect).
static func clear_for_peer(permissions: Dictionary, peer_id: int) -> void:
	var empty_tokens: Array[String] = []
	for network_id in permissions:
		if permissions[network_id].has(peer_id):
			permissions[network_id].erase(peer_id)
		if permissions[network_id].is_empty():
			empty_tokens.append(network_id)

	for network_id in empty_tokens:
		permissions.erase(network_id)


## Remove all permissions for a specific token (e.g., on token removal).
static func clear_for_token(permissions: Dictionary, network_id: String) -> void:
	permissions.erase(network_id)


## Convert permissions dictionary to a serializable format for network transmission.
## Converts int keys to strings for JSON/Dictionary compatibility.
static func to_dict(permissions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for network_id in permissions:
		var peer_dict: Dictionary = {}
		for peer_id in permissions[network_id]:
			peer_dict[str(peer_id)] = permissions[network_id][peer_id].duplicate()
		result[network_id] = peer_dict
	return result


## Restore permissions dictionary from serialized format.
## Converts string peer_id keys back to ints.
static func from_dict(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for network_id in data:
		var peer_dict: Dictionary = {}
		for peer_id_str in data[network_id]:
			var peer_id := int(peer_id_str)
			var perms_raw: Array = data[network_id][peer_id_str]
			var perms: Array = []
			for p in perms_raw:
				perms.append(int(p))
			peer_dict[peer_id] = perms
		result[network_id] = peer_dict
	return result
