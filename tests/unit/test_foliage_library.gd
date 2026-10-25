extends GutTest

## FoliageLibrary (utils/foliage_library.gd) since step S10: it serves the content libraries into
## the palette (the treecube palette and the plantgen-package switch are gone) and keeps a map in
## step with them. apply() clears the palette and wind caches and serves the libraries again,
## refresh_libraries() announces it, a developer override that cannot be served is reported while
## the others stay served, the retired `[foliage]` settings are ignored, and a map saved under
## another asset set has its scatter regenerated from the biome painting.
##
## Fixture: tests/unit/library_world.gd (a palette root `base` with a forest and a meadow, an
## official root holding the miniature `core` with biome `forest` and assets Tree_Oak_v0 and
## Tree_Oak_v1, a user root holding `alienworld`).

const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_foliage_library"
const FOREST := World.CORE_RUNTIME
const OAK := FOREST + "/Tree_Oak_v0"
## An asset of the retired treecube palette: no served library has it.
const OLD := FOREST + "/Tree_Oak_summer_01"

var _paths: Dictionary = {}
var _saved: Dictionary = {}


func before_all() -> void:
	_saved = {
		"settings": LibraryRegistry.settings_path,
		"official": LibraryRegistry.official_root,
		"user": LibraryRegistry.user_root,
	}


func after_all() -> void:
	LibraryRegistry.settings_path = _saved["settings"]
	LibraryRegistry.official_root = _saved["official"]
	LibraryRegistry.user_root = _saved["user"]
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = World.build(ROOT)
	LibraryRegistry.clear()
	LibraryRegistry.settings_path = ROOT + "/settings.cfg"
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	FoliageLibrary.apply(_paths["base"])


## A document painted all with the forest, whose scatter holds one row of each of `asset_ids`.
func _document(asset_ids: Array) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "", "", 7)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(1)
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	density.fill(255)
	doc.biome_slots = slots
	doc.biome_density = density
	for asset_id: String in asset_ids:
		doc.scatter[asset_id] = PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	return doc


func _asset_ids() -> Array:
	return (PaletteLibrary.get_palette(_paths["base"])["assets"] as Dictionary).keys()


func test_apply_serves_every_installed_library_over_the_base() -> void:
	var result := FoliageLibrary.apply(_paths["base"])
	assert_true(result["ok"], str(result["error"]))
	var ids := _asset_ids()
	assert_has(ids, OAK, "core's asset")
	assert_has(ids, World.ALIEN_RUNTIME + "/Crystal_Spire_v0", "the user's library")
	assert_does_not_have(ids, FOREST + "/Oak", "the base's own forest asset went with its biome")
	assert_eq(LibraryRegistry.served().keys().size(), 2)


func test_apply_drops_what_a_removed_library_laid() -> void:
	assert_has(_asset_ids(), World.ALIEN_RUNTIME + "/Crystal_Spire_v0")
	World.remove_tree(_paths["alien"])
	FoliageLibrary.apply(_paths["base"])
	assert_does_not_have(_asset_ids(), World.ALIEN_RUNTIME + "/Crystal_Spire_v0")
	assert_has(_asset_ids(), OAK, "core stays")


func test_apply_drops_the_cached_meshes() -> void:
	var before: int = AssetStore.stats["parses"]
	assert_not_null(PaletteLibrary.resolve(OAK, _paths["base"]).get("mesh"))
	assert_eq(AssetStore.stats["parses"], before + 1)
	PaletteLibrary.resolve(OAK, _paths["base"])
	assert_eq(AssetStore.stats["parses"], before + 1, "served from the cache")
	FoliageLibrary.apply(_paths["base"])
	PaletteLibrary.resolve(OAK, _paths["base"])
	assert_eq(AssetStore.stats["parses"], before + 2, "parsed again after apply")


func test_apply_resets_the_wind_representatives() -> void:
	FoliageLibrary.apply()  # the default root: the one the representatives are picked from
	WindFoliage.representative_assets()
	assert_false(WindFoliage._representative_ids.is_empty(), "primed from the served palette")
	FoliageLibrary.apply()
	assert_true(WindFoliage._representative_ids.is_empty(), "forgotten on apply")
	assert_true(WindFoliage._representative_formats.is_empty())


func test_a_developer_override_that_cannot_be_served_is_reported_and_the_rest_stays() -> void:
	LibraryRegistry.set_dev_override(ROOT + "/nowhere")
	var result := FoliageLibrary.apply(_paths["base"])
	assert_false(result["ok"])
	assert_ne(String(result["error"]), "")
	assert_engine_error(2, "the override's problem, and the library's reason")
	assert_has(_asset_ids(), OAK, "core is still served")


func test_the_retired_foliage_settings_are_ignored() -> void:
	var config := ConfigFile.new()
	config.set_value("foliage", "library", "plantgen")
	config.set_value("foliage", "package_path", ROOT + "/nowhere")
	assert_eq(config.save(LibraryRegistry.settings_path), OK)
	FoliageLibrary.apply_saved()
	assert_has(
		(PaletteLibrary.get_palette()["assets"] as Dictionary).keys(),
		OAK,
		"core serves whatever the old setting says"
	)
	var kept := ConfigFile.new()
	kept.load(LibraryRegistry.settings_path)
	assert_eq(kept.get_value("foliage", "library"), "plantgen", "the file is left alone")


func test_refresh_announces_only_a_change_that_worked() -> void:
	watch_signals(EventBus)
	var worked := FoliageLibrary.refresh_libraries()
	assert_true(worked["ok"], str(worked["error"]))
	assert_signal_emit_count(EventBus, "foliage_library_changed", 1)
	LibraryRegistry.set_dev_override(ROOT + "/nowhere")
	var failed := FoliageLibrary.refresh_libraries()
	assert_false(failed["ok"])
	assert_engine_error(2, "the override's problem, and the library's reason")
	assert_signal_emit_count(EventBus, "foliage_library_changed", 1)


func test_analyse_names_the_assets_the_libraries_lack() -> void:
	var doc := _document([OLD, OAK])
	doc.props[OLD] = PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	var report := FoliageLibrary.analyse(doc, _paths["base"])
	assert_eq(report["missing_ids"], PackedStringArray([OLD]))
	assert_eq(report["missing_rows"], 1)
	assert_eq(report["props_missing"], 1)
	assert_eq(FoliageLibrary.describe(report), "", "analysis alone says nothing")


func test_rows_the_libraries_lack_are_regenerated_from_the_biome_painting() -> void:
	var doc := _document([OLD])
	var report: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), _paths["base"])
	assert_true(report["regenerated"])
	assert_gt(report["rows"], 0, "the painted forest grows plants")
	var ids := _asset_ids()
	for asset_id: String in doc.scatter:
		assert_has(ids, asset_id, "every row now names an asset a library has")
	assert_does_not_have(doc.scatter.keys(), OLD)
	assert_string_contains(FoliageLibrary.describe(report), "rebuilt from the biome painting")
	assert_true(FoliageLibrary.analyse(doc, _paths["base"])["missing_ids"].is_empty())
	var rows := _row_count(doc)
	var again: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), _paths["base"])
	assert_false(again["regenerated"], "nothing missing the second time")
	assert_eq(_row_count(doc), rows, "and the rows stay")


func test_regeneration_is_deterministic() -> void:
	var first := _document([OLD])
	var second := _document([OLD])
	await FoliageLibrary.adapt_async(first, get_tree(), _paths["base"])
	await FoliageLibrary.adapt_async(second, get_tree(), _paths["base"])
	assert_eq(first.scatter.keys(), second.scatter.keys())
	for asset_id: String in first.scatter:
		assert_eq(first.scatter[asset_id], second.scatter[asset_id])


func test_a_document_that_resolves_is_left_alone() -> void:
	var doc := _document([OAK])
	var before: PackedFloat32Array = doc.scatter[OAK].duplicate()
	var report: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), _paths["base"])
	assert_false(report["regenerated"], "core has the oak")
	assert_eq(doc.scatter[OAK], before)


## The documented behaviour for a map saved under the retired treecube asset ids (step S10): no
## compatibility work. A painting that names a biome core still serves regenerates; one that names
## a biome no library serves regenerates nothing and the build skips the unknown rows.
func test_rows_with_no_painting_to_regenerate_from_are_left_alone() -> void:
	var doc := _document([OLD])
	doc.biome_ids = PackedStringArray()
	var report: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), _paths["base"])
	assert_false(report["regenerated"])
	assert_eq(report["missing_ids"], PackedStringArray([OLD]))
	assert_has(doc.scatter.keys(), OLD, "the build skips it with its usual warning")


func test_a_painting_of_a_biome_nobody_serves_grows_nothing() -> void:
	var doc := _document([OLD])
	doc.biome_ids = PackedStringArray(["retired_biome_summer_s1"])
	var report: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), _paths["base"])
	assert_true(report["regenerated"], "the rows were derived data, so they are rebuilt")
	assert_eq(report["rows"], 0, "and an unknown biome has no rules to grow")
	assert_true(doc.scatter.is_empty())


func _row_count(doc: MapDocument) -> int:
	var total := 0
	for asset_id: String in doc.scatter:
		total += doc.scatter[asset_id].size() / MapDocument.ROW_STRIDE
	return total
