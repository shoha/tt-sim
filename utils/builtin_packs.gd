class_name BuiltinPacks
extends RefCounted

## The token packs that ship inside the game: `res://builtin_packs/<pack_id>/` with a
## `manifest.json`, `models/*.glb` and `icons/*.png` in the user pack layout, read in place and
## never copied to the user data folder (docs/ASSET_MANAGEMENT.md "Built-in packs").
##
## Read-only and always the shipped version: a game update replaces a pack, a user cannot edit,
## delete or shadow it, and every peer on the same version already holds the same files, so a
## token of a built-in pack needs no download. Every GLB and PNG there carries a constant
## `<file>.import` sidecar holding `importer="keep"` (the library Route K, docs/systems/library.md)
## so an export stores the raw bytes that the loader path (`FileAccess`, `GLTFDocument`,
## `Image.load`) reads; `.gitattributes` keeps them in Git LFS.
##
## A pack needs a manifest (its credit lives there) and at least one asset: a folder with no
## models yet is skipped, so it adds neither an empty picker tab nor a credit line. This class is
## the one reader of the folder, shared by AssetManager (the picker) and LicenceCatalog (the
## Licences page), so the credit a player reads is the manifest that ships.

const ROOT := "res://builtin_packs/"
const MANIFEST := "manifest.json"


## Every shippable pack under `root`, flagged is_builtin, sorted by display name.
static func load_all(root: String = ROOT) -> Array[AssetPack]:
	var out: Array[AssetPack] = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for folder in DirAccess.get_directories_at(root):
		if folder.begins_with("."):
			continue
		var pack := load_pack(root + folder + "/", folder)
		if pack != null:
			out.append(pack)
	out.sort_custom(
		func(a: AssetPack, b: AssetPack) -> bool:
			return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return out


## One pack from its folder (`pack_path` ends in "/"), or null when it has no readable manifest
## or no assets. The folder name is the pack id when the manifest does not name one.
static func load_pack(pack_path: String, folder: String) -> AssetPack:
	var manifest := _read_manifest(pack_path + MANIFEST)
	if manifest.is_empty():
		return null
	if str(manifest.get("pack_id", "")) == "":
		manifest["pack_id"] = folder
	var pack := AssetPack.from_manifest(manifest, pack_path)
	pack.is_builtin = true
	pack.is_remote = false
	if pack.assets.is_empty():
		return null
	return pack


## What is wrong with a built-in pack's provenance, as messages (empty when fine): a shipped
## pack must declare a licence and a credit line, and name its folder as its id.
static func problems(pack: AssetPack, folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	if pack.pack_id != folder:
		out.append("pack_id '%s' is not its folder name '%s'" % [pack.pack_id, folder])
	if pack.license == "":
		out.append("%s: no license" % folder)
	if pack.credit_line() == "":
		out.append("%s: no credit line (credit, or author and license)" % folder)
	return out


static func _read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("BuiltinPacks: cannot parse %s" % path)
	return {}
