extends GutTest

## NewMapBuild (P5-8): the new-map document built on a worker is byte for byte the one
## NewMap.from_spec builds on the calling thread (heights, water bodies, crossings, masks,
## all of MapDocumentIO.serialize), for a gorge at 200 ft and a valley at 150 ft; a spec
## without a seed gets one drawn before the build.

const BIOME := "temperate_forest_summer_s1"
const SEEDS: Array[int] = [3, 11]


func _same_both_ways(landform: String, size_ft: int) -> Array[MapDocument]:
	var docs: Array[MapDocument] = []
	for seed_value in SEEDS:
		var spec := {
			"size_ft": size_ft, "biome_id": BIOME, "seed": seed_value, "landform": landform
		}
		var threaded := NewMapBuild.start(spec, PaletteLibrary.DEFAULT_ROOT, true)
		var direct := NewMapBuild.start(spec, PaletteLibrary.DEFAULT_ROOT, false).finish()
		var built := await threaded.wait(get_tree())
		var label := "%s %d ft seed %d" % [landform, size_ft, seed_value]
		assert_not_null(built, label)
		assert_eq(built.heights, direct.heights, label + " heights")
		assert_eq(built.biome_density, direct.biome_density, label + " density")
		assert_eq(built.water_bodies.size(), direct.water_bodies.size(), label + " bodies")
		assert_eq(built.crossings.size(), direct.crossings.size(), label + " crossings")
		var a := MapDocumentIO.serialize(built)
		var b := MapDocumentIO.serialize(direct)
		assert_eq(a.error, "", label)
		assert_eq(a.entries.keys(), b.entries.keys(), label + " entries")
		for entry in a.entries:
			assert_eq(a.entries[entry], b.entries[entry], "%s %s" % [label, entry])
		docs.append(built)
	return docs


func test_gorge_at_200_ft_is_identical_off_the_main_thread() -> void:
	var docs := await _same_both_ways(StartingLandform.GORGE, 200)
	var featured := docs.filter(
		func(doc: MapDocument) -> bool: return not doc.water_bodies.is_empty()
	)
	assert_gt(featured.size(), 0, "a seed draws water, so the bodies are compared")


func test_valley_at_150_ft_is_identical_off_the_main_thread() -> void:
	var docs := await _same_both_ways(StartingLandform.VALLEY, 150)
	var crossed := docs.filter(func(doc: MapDocument) -> bool: return not doc.crossings.is_empty())
	assert_gt(crossed.size(), 0, "a seed draws a crossing, so the crossings are compared")


func test_a_spec_without_a_seed_gets_one() -> void:
	var doc := NewMapBuild.start({"size_ft": 100}, PaletteLibrary.DEFAULT_ROOT, true).finish()
	assert_not_null(doc)
	assert_eq(doc.size_cells, Vector2i(20, 20))
