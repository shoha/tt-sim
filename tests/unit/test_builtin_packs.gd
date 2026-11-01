extends GutTest

## The built-in token pack route (BuiltinPacks, docs/ASSET_MANAGEMENT.md "Built-in packs"):
## discovery from a res-like scratch root beside the user packs, the marker, picker order, the
## guards that make a built-in pack not removable and not shadowable, the provenance fields
## (back-compatible when absent), the tab tooltip and the Licences page entries generated from
## the manifests. The scratch root stands in for res://builtin_packs/
## (AssetManager.builtin_packs_dir); the user packs go to the run's own Paths.USER_ASSETS_DIR.

const ScratchDir := preload("res://tests/unit/scratch_dir.gd")
const ROOT := "user://test_builtin_packs/"
const BUILTIN := ROOT + "builtin/"
const USER_FOLDERS: Array[String] = ["alpha_beasts", "test_tp_mine"]

var _saved_dir: String = ""


func before_each() -> void:
	ScratchDir.clear(ROOT.trim_suffix("/"))
	_saved_dir = AssetManager.builtin_packs_dir
	AssetManager.builtin_packs_dir = BUILTIN
	_write_manifest(
		BUILTIN + "zeta_folk/",
		{
			"pack_id": "zeta_folk",
			"display_name": "Zeta Folk",
			"author": "Someone",
			"license": "CC-BY-4.0",
			"assets": {"smith": _asset("Smith", "smith.glb")},
		}
	)
	_write_manifest(
		BUILTIN + "alpha_beasts/",
		{
			"pack_id": "alpha_beasts",
			"display_name": "Alpha Beasts",
			"author": "Quaternius",
			"license": "CC0-1.0",
			"license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
			"source_url": "https://example.com/animals",
			"credit": "Animals by Quaternius (CC0)",
			"obtained": "2026-11-01",
			"assets": {"wolf": _asset("Wolf", "wolf.glb"), "bear": _asset("Bear", "bear.glb")},
		}
	)
	# No models yet: a manifest with no assets must not make a tab or a credit.
	_write_manifest(
		BUILTIN + "empty_pack/", {"pack_id": "empty_pack", "display_name": "Empty", "assets": {}}
	)
	# A folder without a manifest is not a built-in pack.
	_write_file(BUILTIN + "loose_folder/models/x.glb", "")


func after_each() -> void:
	for folder in USER_FOLDERS:
		_remove_user_pack(folder)
	AssetManager.builtin_packs_dir = _saved_dir
	AssetManager.reload_packs()
	ScratchDir.clear(ROOT.trim_suffix("/"))


func test_discovery_reads_manifest_packs_and_skips_empty_and_manifestless() -> void:
	var packs := BuiltinPacks.load_all(BUILTIN)
	var ids: Array[String] = []
	for pack in packs:
		ids.append(pack.pack_id)
		assert_true(pack.is_builtin, "%s is flagged built-in" % pack.pack_id)
		assert_false(pack.is_remote)
	assert_eq(ids, ["alpha_beasts", "zeta_folk"], "by display name; empty, manifestless skipped")
	assert_eq(packs[0].assets.size(), 2)
	assert_eq(packs[0].base_path, BUILTIN + "alpha_beasts/")


func test_a_missing_root_gives_no_packs() -> void:
	assert_eq(BuiltinPacks.load_all(ROOT + "nowhere/").size(), 0)


func test_the_manifest_never_decides_is_builtin() -> void:
	var pack := AssetPack.from_manifest({"pack_id": "x", "is_builtin": true}, "user://x/")
	assert_false(pack.is_builtin, "only discovery sets it")


func test_asset_manager_lists_builtin_packs_first_then_user_packs() -> void:
	_write_user_pack("test_tp_mine", "Aardvark Minis")
	AssetManager.reload_packs()
	var order: Array[String] = []
	for pack in AssetManager.get_packs():
		if pack.pack_id in ["alpha_beasts", "zeta_folk", "test_tp_mine"]:
			order.append(pack.pack_id)
	var expected := ["alpha_beasts", "zeta_folk", "test_tp_mine"]
	assert_eq(order, expected, "built-in first, though 'Aardvark' sorts earlier")
	assert_true(AssetManager.is_builtin_pack("alpha_beasts"))
	assert_false(AssetManager.is_builtin_pack("test_tp_mine"))
	assert_false(AssetManager.is_builtin_pack("no_such_pack"))


func test_a_builtin_pack_is_not_removable_but_a_user_pack_is() -> void:
	_write_user_pack("test_tp_mine", "Mine")
	AssetManager.reload_packs()
	assert_false(AssetManager.is_pack_removable("alpha_beasts"))
	assert_true(AssetManager.is_pack_removable("test_tp_mine"))
	assert_false(AssetManager.is_pack_removable("no_such_pack"), "an unknown pack is not")


func test_a_user_pack_with_a_builtin_id_does_not_shadow_it() -> void:
	_write_user_pack("alpha_beasts", "Impostor")
	AssetManager.reload_packs()
	assert_engine_error("already registered", "the impostor is reported and skipped")
	var pack: AssetPack = AssetManager.get_pack("alpha_beasts")
	assert_eq(pack.display_name, "Alpha Beasts")
	assert_true(pack.is_builtin)


func test_a_remote_or_downloaded_pack_cannot_replace_a_builtin_pack() -> void:
	AssetManager.reload_packs()
	var replaced: bool = AssetManager.register_remote_pack(
		{"pack_id": "alpha_beasts", "display_name": "Hijack", "assets": {}}
	)
	assert_false(replaced)
	assert_engine_error("built-in pack", "the refusal is reported")
	assert_eq(AssetManager.get_pack("alpha_beasts").display_name, "Alpha Beasts")
	assert_false(AssetManager._finalize_pack_download("alpha_beasts", {"pack_id": "alpha_beasts"}))
	assert_false(
		FileAccess.file_exists(Paths.USER_ASSETS_DIR + "alpha_beasts/manifest.json"),
		"nothing was written into the user packs"
	)


func test_a_builtin_models_resolve_through_the_same_loader_path() -> void:
	_write_file(BUILTIN + "alpha_beasts/models/wolf.glb", "glb")
	AssetManager.reload_packs()
	assert_true(AssetManager.is_asset_available("alpha_beasts", "wolf"))
	assert_false(AssetManager.is_asset_available("alpha_beasts", "bear"), "no file for the bear")
	var path: String = AssetManager.resolver.resolve_model_sync("alpha_beasts", "wolf", "default")
	assert_eq(path, BUILTIN + "alpha_beasts/models/wolf.glb")


func test_a_packs_provenance_fields_read_and_default_to_empty() -> void:
	var pack := BuiltinPacks.load_pack(BUILTIN + "alpha_beasts/", "alpha_beasts")
	assert_eq(pack.author, "Quaternius")
	assert_eq(pack.license, "CC0-1.0")
	assert_eq(pack.license_url, "https://creativecommons.org/publicdomain/zero/1.0/")
	assert_eq(pack.source_url, "https://example.com/animals")
	assert_eq(pack.obtained, "2026-11-01")
	var plain := AssetPack.from_manifest({"pack_id": "old", "display_name": "Old"}, "user://old/")
	var fields := [plain.author, plain.license, plain.license_url]
	fields.append_array([plain.source_url, plain.credit, plain.obtained])
	for value in fields:
		assert_eq(value, "", "a manifest without the new fields still loads")
	assert_eq(plain.credit_line(), "")
	assert_false(plain.is_builtin)


func test_credit_line_prefers_credit_then_derives_from_author_and_licence() -> void:
	var packs := BuiltinPacks.load_all(BUILTIN)
	assert_eq(packs[0].credit_line(), "Animals by Quaternius (CC0)")
	assert_eq(packs[1].credit_line(), "Zeta Folk by Someone (CC-BY-4.0)")
	var only_author := AssetPack.from_manifest({"display_name": "P", "author": "A"})
	assert_eq(only_author.credit_line(), "P by A")


func test_tab_tooltip_says_built_in_and_the_credit() -> void:
	var packs := BuiltinPacks.load_all(BUILTIN)
	var expected := "%s\nAnimals by Quaternius (CC0)" % LibraryNames.BUILT_IN
	assert_eq(AssetBrowser.pack_tooltip(packs[0]), expected)
	var user_pack := AssetPack.from_manifest({"pack_id": "u", "credit": "Minis by Me"}, "user://u/")
	assert_eq(AssetBrowser.pack_tooltip(user_pack), "Minis by Me", "a user pack's credit shows")
	var plain := AssetPack.from_manifest({"pack_id": "p"}, "user://p/")
	assert_eq(AssetBrowser.pack_tooltip(plain), "", "no fields, no tooltip")


func test_licence_entries_are_generated_from_the_manifests() -> void:
	var entries := LicenceCatalog.pack_entries(BUILTIN)
	assert_eq(entries.size(), 2, "the empty pack adds nothing")
	var alpha := entries[0]
	assert_eq(alpha["id"], "tokens_alpha_beasts")
	assert_eq(alpha["group"], LicenceCatalog.GROUP_TOKENS)
	assert_eq(alpha["name"], "Alpha Beasts")
	assert_eq(alpha["licence"], "CC0-1.0")
	assert_eq(alpha["credit"], "Animals by Quaternius (CC0)")
	assert_string_contains(alpha["text"], "Source: https://example.com/animals")
	assert_string_contains(alpha["text"], "Obtained: 2026-11-01")
	assert_string_contains(alpha["text"], "Licence text: https://creativecommons.org")
	assert_eq(entries[1]["credit"], "Zeta Folk by Someone (CC-BY-4.0)")


func test_the_page_lists_pack_entries_between_the_shipped_items_and_the_engine() -> void:
	var all := LicenceCatalog.entries()
	assert_eq(all[0]["group"], "This game")
	assert_eq(all[all.size() - 1]["group"], LicenceCatalog.GROUP_ENGINE)


func test_every_shipped_builtin_pack_declares_its_provenance_and_keeps_its_files() -> void:
	# BuiltinPacks.ROOT does not exist until the first real pack lands: then nothing to check.
	if not DirAccess.dir_exists_absolute(BuiltinPacks.ROOT):
		pass_test("no built-in packs ship yet")
		return
	for folder in DirAccess.get_directories_at(BuiltinPacks.ROOT):
		var pack := BuiltinPacks.load_pack(BuiltinPacks.ROOT + folder + "/", folder)
		if pack == null:
			continue
		assert_eq(BuiltinPacks.problems(pack, folder), PackedStringArray(), "%s provenance" % folder)
		for path in _files_under(BuiltinPacks.ROOT + folder + "/"):
			if path.get_extension() in ["glb", "png"]:
				var sidecar := FileAccess.get_file_as_string(path + ".import")
				assert_true(sidecar.contains('importer="keep"'), "%s has a keep sidecar" % path)


func test_problems_flags_a_pack_without_a_licence_or_credit() -> void:
	var bare := AssetPack.from_manifest({"pack_id": "bare", "display_name": "Bare"})
	var found := BuiltinPacks.problems(bare, "bare")
	assert_eq(found.size(), 2, "no licence and no credit line")
	var mismatch := AssetPack.from_manifest({"pack_id": "a", "license": "CC0-1.0", "credit": "x"})
	assert_eq(BuiltinPacks.problems(mismatch, "b").size(), 1, "id is not the folder name")


func _asset(display_name: String, model: String) -> Dictionary:
	return {"display_name": display_name, "variants": {"default": {"model": model}}}


func _write_manifest(folder: String, manifest: Dictionary) -> void:
	_write_file(folder + "manifest.json", JSON.stringify(manifest))


func _write_file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var handle := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(handle, "wrote " + path)
	if handle != null:
		handle.store_string(text)
		handle.close()


func _write_user_pack(pack_id: String, display_name: String) -> void:
	_write_manifest(
		Paths.USER_ASSETS_DIR + pack_id + "/",
		{"pack_id": pack_id, "display_name": display_name, "assets": {"a": _asset("A", "a.glb")}}
	)


func _remove_user_pack(pack_id: String) -> void:
	var folder := Paths.USER_ASSETS_DIR + pack_id + "/"
	if FileAccess.file_exists(folder + "manifest.json"):
		DirAccess.remove_absolute(folder + "manifest.json")
	DirAccess.remove_absolute(folder.trim_suffix("/"))


## Every file under `folder`, recursively (read only).
func _files_under(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file_name in DirAccess.get_files_at(folder):
		out.append(folder + file_name)
	for sub in DirAccess.get_directories_at(folder):
		out.append_array(_files_under(folder + sub + "/"))
	return out
