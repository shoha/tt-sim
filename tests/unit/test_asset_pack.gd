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


func test_get_all_assets_returns_assets_in_natural_sort_order() -> void:
	var pack := AssetPack.new()
	# Insert in lexicographic order (simulates JSON.stringify sort_keys=true reordering keys)
	for key in ["1", "10", "2"]:
		var entry := AssetPack.AssetEntry.new()
		entry.asset_id = key
		pack.assets[key] = entry

	var assets := pack.get_all_assets()
	var ids: Array = assets.map(func(a: AssetPack.AssetEntry) -> String: return a.asset_id)
	assert_eq(ids, ["1", "2", "10"])


func test_get_all_assets_sorted_after_manifest_with_lexicographic_key_order() -> void:
	# Simulates loading a manifest that was re-saved by JSON.stringify() with sort_keys=true,
	# which turns numeric keys "1","2","10" into lexicographic order "1","10","2".
	var manifest := {
		"pack_id": "pokemon",
		"display_name": "Pokemon",
		"assets": {
			"1": {"display_name": "Bulbasaur", "variants": {"default": {"model": "1.glb"}}},
			"10": {"display_name": "Caterpie", "variants": {"default": {"model": "10.glb"}}},
			"2": {"display_name": "Ivysaur", "variants": {"default": {"model": "2.glb"}}},
		}
	}
	var pack := AssetPack.from_manifest(manifest)
	var assets := pack.get_all_assets()
	var ids: Array = assets.map(func(a: AssetPack.AssetEntry) -> String: return a.asset_id)
	assert_eq(ids, ["1", "2", "10"])
