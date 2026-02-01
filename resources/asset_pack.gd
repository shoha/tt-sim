extends Resource
class_name AssetPack

## Represents a user-loadable asset pack containing models and icons for tokens.
## Packs are discovered automatically from the user_assets/ directory.

## Unique identifier for this pack (folder name)
@export var pack_id: String = ""

## Human-readable display name
@export var display_name: String = ""

## Version string for the pack
@export var version: String = "1.0"

## Base path to the pack directory (e.g., "res://user_assets/pokemon/")
@export var base_path: String = ""

## Dictionary of asset_id -> AssetEntry
var assets: Dictionary = {}


## Get an asset entry by ID
func get_asset(asset_id: String) -> AssetEntry:
	return assets.get(asset_id)


## Get all asset entries as an array
func get_all_assets() -> Array[AssetEntry]:
	var result: Array[AssetEntry] = []
	for asset in assets.values():
		result.append(asset)
	return result


## Get the model path for a specific asset and variant
func get_model_path(asset_id: String, variant_id: String = "default") -> String:
	var asset = get_asset(asset_id)
	if not asset:
		return ""
	var variant = asset.get_variant(variant_id)
	if not variant:
		return ""
	return base_path + "models/" + variant.model_file


## Get the icon path for a specific asset and variant
func get_icon_path(asset_id: String, variant_id: String = "default") -> String:
	var asset = get_asset(asset_id)
	if not asset:
		return ""
	var variant = asset.get_variant(variant_id)
	if not variant:
		return ""
	return base_path + "icons/" + variant.icon_file


## Parse an AssetPack from a manifest dictionary
static func from_manifest(manifest: Dictionary, pack_path: String) -> AssetPack:
	var pack = AssetPack.new()
	pack.pack_id = manifest.get("pack_id", "")
	pack.display_name = manifest.get("display_name", pack.pack_id.capitalize())
	pack.version = manifest.get("version", "1.0")
	pack.base_path = pack_path
	
	var assets_data = manifest.get("assets", {})
	for asset_id in assets_data:
		var asset_data = assets_data[asset_id]
		var asset = AssetEntry.from_dict(asset_id, asset_data)
		pack.assets[asset_id] = asset
	
	return pack


## Represents a single asset within a pack (e.g., one Pokemon, one miniature)
class AssetEntry:
	## Unique identifier within the pack
	var asset_id: String = ""
	
	## Human-readable display name
	var display_name: String = ""
	
	## Dictionary of variant_id -> AssetVariant
	var variants: Dictionary = {}
	
	
	## Get a variant by ID, returns null if not found
	func get_variant(variant_id: String = "default") -> AssetVariant:
		return variants.get(variant_id)
	
	
	## Get all variant IDs
	func get_variant_ids() -> Array[String]:
		var result: Array[String] = []
		for key in variants.keys():
			result.append(key)
		return result
	
	
	## Check if this asset has multiple variants
	func has_variants() -> bool:
		return variants.size() > 1
	
	
	## Parse an AssetEntry from a dictionary
	static func from_dict(id: String, data: Dictionary) -> AssetEntry:
		var entry = AssetEntry.new()
		entry.asset_id = id
		entry.display_name = data.get("display_name", id.capitalize())
		
		var variants_data = data.get("variants", {})
		for variant_id in variants_data:
			var variant_data = variants_data[variant_id]
			var variant = AssetVariant.from_dict(variant_id, variant_data)
			entry.variants[variant_id] = variant
		
		return entry


## Represents a specific variant of an asset (e.g., shiny, fire, ice)
class AssetVariant:
	## Variant identifier (e.g., "default", "shiny", "fire")
	var variant_id: String = ""
	
	## Model filename (relative to pack's models/ folder)
	var model_file: String = ""
	
	## Icon filename (relative to pack's icons/ folder)
	var icon_file: String = ""
	
	
	## Parse an AssetVariant from a dictionary
	static func from_dict(id: String, data: Dictionary) -> AssetVariant:
		var variant = AssetVariant.new()
		variant.variant_id = id
		variant.model_file = data.get("model", "")
		variant.icon_file = data.get("icon", "")
		return variant
