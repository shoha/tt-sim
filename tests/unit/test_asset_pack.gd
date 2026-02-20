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
