extends GutTest

## Unit tests for AssetPack data model.


func test_get_icon_path_returns_empty_when_icon_file_is_empty() -> void:
	var pack := AssetPack.new()
	pack.base_path = "res://user_assets/test_pack/"

	var entry := AssetPack.AssetEntry.new()
	entry.asset_id = "warrior"
	var variant := AssetPack.AssetVariant.new()
	variant.variant_id = "default"
	variant.model_file = "warrior.glb"
	variant.icon_file = ""
	entry.variants["default"] = variant
	pack.assets["warrior"] = entry

	assert_eq(pack.get_icon_path("warrior"), "")


func test_get_icon_path_returns_path_when_icon_file_is_set() -> void:
	var pack := AssetPack.new()
	pack.base_path = "res://user_assets/test_pack/"

	var entry := AssetPack.AssetEntry.new()
	entry.asset_id = "warrior"
	var variant := AssetPack.AssetVariant.new()
	variant.variant_id = "default"
	variant.model_file = "warrior.glb"
	variant.icon_file = "warrior.png"
	entry.variants["default"] = variant
	pack.assets["warrior"] = entry

	assert_eq(pack.get_icon_path("warrior"), "res://user_assets/test_pack/icons/warrior.png")


# ---------------------------------------------------------------------------
# from_directory() tests
# Setup: create a temp pack at user://test_auto_pack/ with two models,
# one matching icon, and one absent icon.
# ---------------------------------------------------------------------------

const _TEMP_PACK := "user://test_auto_pack/"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(_TEMP_PACK + "models/")
	DirAccess.make_dir_recursive_absolute(_TEMP_PACK + "icons/")
	_touch(_TEMP_PACK + "models/warrior.glb")
	_touch(_TEMP_PACK + "models/wizard.glb")
	_touch(_TEMP_PACK + "icons/warrior.png")
	# wizard.png intentionally absent


func after_each() -> void:
	_remove_file(_TEMP_PACK + "models/warrior.glb")
	_remove_file(_TEMP_PACK + "models/wizard.glb")
	_remove_file(_TEMP_PACK + "icons/warrior.png")
	DirAccess.remove_absolute(_TEMP_PACK + "models")
	DirAccess.remove_absolute(_TEMP_PACK + "icons")
	DirAccess.remove_absolute(_TEMP_PACK.trim_suffix("/"))


func _touch(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_from_directory_pack_id_equals_folder_name() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	assert_eq(pack.pack_id, "test_auto_pack")


func test_from_directory_display_name_is_capitalized() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	assert_eq(pack.display_name, "Test Auto Pack")


func test_from_directory_discovers_both_glb_files() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	assert_eq(pack.assets.size(), 2)


func test_from_directory_asset_has_default_variant() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	var asset := pack.get_asset("warrior")
	assert_not_null(asset)
	assert_not_null(asset.get_variant("default"))


func test_from_directory_model_file_is_glb_filename() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	var variant := pack.get_asset("warrior").get_variant("default")
	assert_eq(variant.model_file, "warrior.glb")


func test_from_directory_icon_file_set_when_png_exists() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	var variant := pack.get_asset("warrior").get_variant("default")
	assert_eq(variant.icon_file, "warrior.png")


func test_from_directory_icon_file_empty_when_png_absent() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	var variant := pack.get_asset("wizard").get_variant("default")
	assert_eq(variant.icon_file, "")


func test_from_directory_base_path_is_pack_path() -> void:
	var pack := AssetPack.from_directory(_TEMP_PACK, "test_auto_pack")
	assert_eq(pack.base_path, _TEMP_PACK)


func test_from_directory_returns_empty_pack_when_no_models_dir() -> void:
	var pack := AssetPack.from_directory("user://nonexistent_pack/", "nonexistent_pack")
	assert_eq(pack.assets.size(), 0)
