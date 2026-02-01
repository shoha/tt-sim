extends Node

## Manages discovery and loading of user asset packs.
## Scans the user_assets/ directory for packs containing manifest.json files.
## Provides API for accessing assets across all loaded packs.

const AssetPackClass = preload("res://resources/asset_pack.gd")
const USER_ASSETS_DIR: String = "res://user_assets/"

## Dictionary of pack_id -> AssetPack
var _packs: Dictionary = {}

## Signal emitted when all packs have been loaded
signal packs_loaded


func _ready() -> void:
	_discover_packs()


## Discover and load all asset packs from the user_assets directory
func _discover_packs() -> void:
	_packs.clear()
	
	var dir = DirAccess.open(USER_ASSETS_DIR)
	if dir == null:
		push_warning("AssetPackManager: Could not open user_assets directory: " + USER_ASSETS_DIR)
		packs_loaded.emit()
		return
	
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var pack_path = USER_ASSETS_DIR + folder_name + "/"
			var manifest_path = pack_path + "manifest.json"
			
			if FileAccess.file_exists(manifest_path):
				var pack = _load_pack(manifest_path, pack_path)
				if pack:
					_packs[pack.pack_id] = pack
					print("AssetPackManager: Loaded pack '" + pack.display_name + "' with " + str(pack.assets.size()) + " assets")
		
		folder_name = dir.get_next()
	
	dir.list_dir_end()
	packs_loaded.emit()


## Load a single pack from its manifest file
func _load_pack(manifest_path: String, pack_path: String):
	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("AssetPackManager: Failed to open manifest: " + manifest_path)
		return null
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("AssetPackManager: Failed to parse manifest JSON: " + json.get_error_message())
		return null
	
	return AssetPackClass.from_manifest(json.data, pack_path)


## Get all loaded packs
func get_packs() -> Array:
	var result: Array = []
	for pack in _packs.values():
		result.append(pack)
	return result


## Get a pack by ID
func get_pack(pack_id: String):
	return _packs.get(pack_id)


## Check if a pack exists
func has_pack(pack_id: String) -> bool:
	return _packs.has(pack_id)


## Get all assets from a specific pack
func get_assets(pack_id: String) -> Array:
	var pack = get_pack(pack_id)
	if not pack:
		return []
	return pack.get_all_assets()


## Get a specific asset from a pack
func get_asset(pack_id: String, asset_id: String):
	var pack = get_pack(pack_id)
	if not pack:
		return null
	return pack.get_asset(asset_id)


## Get the model path for a specific asset and variant
func get_model_path(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	var pack = get_pack(pack_id)
	if not pack:
		push_error("AssetPackManager: Pack not found: " + pack_id)
		return ""
	return pack.get_model_path(asset_id, variant_id)


## Get the icon path for a specific asset and variant
func get_icon_path(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	var pack = get_pack(pack_id)
	if not pack:
		push_error("AssetPackManager: Pack not found: " + pack_id)
		return ""
	return pack.get_icon_path(asset_id, variant_id)


## Get all variant IDs for a specific asset
func get_variants(pack_id: String, asset_id: String) -> Array[String]:
	var asset = get_asset(pack_id, asset_id)
	if not asset:
		return []
	return asset.get_variant_ids()


## Get the display name for an asset
func get_asset_display_name(pack_id: String, asset_id: String) -> String:
	var asset = get_asset(pack_id, asset_id)
	if not asset:
		return "Unknown"
	return asset.display_name


## Get all assets across all packs as a flat list
## Returns array of dictionaries with pack_id, asset_id, and asset reference
func get_all_assets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pack in _packs.values():
		for asset in pack.get_all_assets():
			result.append({
				"pack_id": pack.pack_id,
				"pack_name": pack.display_name,
				"asset_id": asset.asset_id,
				"asset": asset
			})
	return result


## Reload all packs (useful for hot-reloading during development)
func reload_packs() -> void:
	_discover_packs()
