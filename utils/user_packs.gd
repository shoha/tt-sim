class_name UserPacks
extends RefCounted

## Reads the packs a player installed: every folder of `user://user_assets/` (Paths.USER_ASSETS_DIR)
## that has a `manifest.json`, or, without one, a `models/` folder of GLBs
## (AssetPack.from_directory). The reading half of AssetManager's discovery, split out so
## AssetManager stays under the file-size cap; the built-in packs are BuiltinPacks'.


## The packs under `dir_path` (ends in "/"), in folder order. A manifest that cannot be read is
## reported and skipped; a manifest-free folder with no models is not a pack.
static func scan(dir_path: String) -> Array[AssetPack]:
	var out: Array[AssetPack] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var pack_path := dir_path + folder_name + "/"
			var pack: AssetPack = null
			if FileAccess.file_exists(pack_path + "manifest.json"):
				pack = load_manifest_pack(pack_path + "manifest.json", pack_path)
			else:
				pack = AssetPack.from_directory(pack_path, folder_name)
				if pack.assets.is_empty():
					pack = null
			if pack != null:
				out.append(pack)
		folder_name = dir.get_next()
	dir.list_dir_end()
	return out


## One pack from its manifest file, or null (with an error) when it cannot be read or parsed.
static func load_manifest_pack(manifest_path: String, pack_path: String) -> AssetPack:
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("AssetManager: Failed to open manifest: " + manifest_path)
		return null
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("AssetManager: Failed to parse manifest JSON: " + json.get_error_message())
		return null
	if not json.data is Dictionary:
		push_error("AssetManager: Manifest is not an object: " + manifest_path)
		return null
	return AssetPack.from_manifest(json.data, pack_path)
