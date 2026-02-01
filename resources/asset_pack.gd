extends Resource
class_name AssetPack

## Represents a user-loadable asset pack containing models and icons for tokens.
## Packs are discovered automatically from the user_assets/ directory.
## Supports both local packs (with base_path) and remote packs (with base_url).

## Unique identifier for this pack (folder name)
@export var pack_id: String = ""

## Human-readable display name
@export var display_name: String = ""

## Version string for the pack
@export var version: String = "1.0"

## Base path to the pack directory for local assets (e.g., "res://user_assets/pokemon/")
@export var base_path: String = ""

## Base URL for remote assets (e.g., "https://raw.githubusercontent.com/user/repo/main/pokemon/")
## If set, assets will be downloaded from this URL when not available locally
@export var base_url: String = ""

## Whether this pack is remote-only (no local files)
@export var is_remote: bool = false

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


## Get the model URL for a specific asset and variant (for remote downloads)
## Returns empty string if no URL is available
func get_model_url(asset_id: String, variant_id: String = "default") -> String:
	var asset = get_asset(asset_id)
	if not asset:
		return ""
	var variant = asset.get_variant(variant_id)
	if not variant:
		return ""
	
	# Check for variant-specific URL override first
	if variant.model_url != "":
		return variant.model_url
	
	# Fall back to base_url + relative path
	if base_url != "" and variant.model_file != "":
		return base_url + "models/" + variant.model_file
	
	return ""


## Get the icon URL for a specific asset and variant (for remote downloads)
## Returns empty string if no URL is available
func get_icon_url(asset_id: String, variant_id: String = "default") -> String:
	var asset = get_asset(asset_id)
	if not asset:
		return ""
	var variant = asset.get_variant(variant_id)
	if not variant:
		return ""
	
	# Check for variant-specific URL override first
	if variant.icon_url != "":
		return variant.icon_url
	
	# Fall back to base_url + relative path
	if base_url != "" and variant.icon_file != "":
		return base_url + "icons/" + variant.icon_file
	
	return ""


## Check if this pack has remote assets available
func has_remote_assets() -> bool:
	return base_url != "" or _has_variant_urls()


## Check if any variant has direct URLs
func _has_variant_urls() -> bool:
	for asset in assets.values():
		for variant in asset.variants.values():
			if variant.model_url != "" or variant.icon_url != "":
				return true
	return false


## Parse an AssetPack from a manifest dictionary
## pack_path can be empty for remote-only packs
static func from_manifest(manifest: Dictionary, pack_path: String = "") -> AssetPack:
	var pack = AssetPack.new()
	pack.pack_id = manifest.get("pack_id", "")
	pack.display_name = manifest.get("display_name", pack.pack_id.capitalize())
	pack.version = manifest.get("version", "1.0")
	pack.base_path = pack_path
	pack.base_url = manifest.get("base_url", "")
	pack.is_remote = manifest.get("is_remote", pack_path == "")
	
	# Ensure base_url ends with / if provided
	if pack.base_url != "" and not pack.base_url.ends_with("/"):
		pack.base_url += "/"
	
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
	
	## Direct URL for model (overrides base_url + model_file)
	## Use for services like Dropbox that require per-file URLs
	var model_url: String = ""
	
	## Direct URL for icon (overrides base_url + icon_file)
	var icon_url: String = ""
	
	
	## Parse an AssetVariant from a dictionary
	static func from_dict(id: String, data: Dictionary) -> AssetVariant:
		var variant = AssetVariant.new()
		variant.variant_id = id
		variant.model_file = data.get("model", "")
		variant.icon_file = data.get("icon", "")
		variant.model_url = data.get("model_url", "")
		variant.icon_url = data.get("icon_url", "")
		return variant
