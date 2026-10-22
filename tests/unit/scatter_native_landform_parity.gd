extends RefCounted

## The landform recipes' whole maps through the native scatter and GDScript's, job by job (card
## native-scatter): each recipe's own starting cover reaches water, steep faces and, on the
## valley, a crossing. Shared by test_scatter_native_landforms_dry.gd and _wet.gd, which split
## the five recipes so a sharded run (tools/gut_shards.gd) can run them at once: comparing a
## whole map runs every job in GDScript too, about 14 s per recipe.

const SIZE_FT := 200
const SEED := 1234
const BIOME := "grassland_meadow_summer_s1"


## `test`'s asserts on compare(`landform`): rows placed, no job sent to GDScript for a missing
## library, every job equal. Pending, with the reason, where the library is not built.
static func check(test: GutTest, landform: String) -> void:
	if not ScatterNative.available():
		test.pending("the native library is not built (AGENTS.md Testing): GDScript path only")
		return
	var result := compare(landform)
	test.gut.p(result.summary)
	test.assert_gt(result.rows, 0)
	test.assert_false((result.fallbacks as Dictionary).has("missing"))
	test.assert_eq(result.differing, [], "%s: every job equal" % landform)


## Every regen job of `landform`'s new map run native and forced to GDScript: {"rows" (GDScript's
## row count), "differing" (the cells of each job whose rows or anchors differ), "fallbacks"
## (ScatterNative.fallbacks() after the run), "summary" (a line for the log)}.
@warning_ignore("integer_division")
static func compare(landform: String) -> Dictionary:
	var doc := NewMap.create(SIZE_FT, BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, landform)
	if landform == "valley":
		var crossing := Crossing.new()
		crossing.start = Vector2(-6.0, 2.0)
		crossing.end = Vector2(5.0, -3.0)
		crossing.width_m = 1.8
		doc.crossings.append(crossing)
	var regen := ScatterRegen.for_document(doc)
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	regen.built_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("built"))
	regen.cliff_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	regen.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	ScatterNative.reset_counts()
	var rows := 0
	var differing := []
	var job := regen.take_job()
	while not job.is_empty():
		ScatterNative.force_gdscript = false
		var native := ScatterRegen.run(doc, job.work)
		ScatterNative.force_gdscript = true
		var gdscript := ScatterRegen.run(doc, job.work)
		for cell in gdscript.rows_by_cell:
			for asset_id in gdscript.rows_by_cell[cell]:
				rows += gdscript.rows_by_cell[cell][asset_id].size() / MapDocument.ROW_STRIDE
		if native.rows_by_cell != gdscript.rows_by_cell or native.anchors != gdscript.anchors:
			differing.append(job.cells)
		job = regen.take_job()
	ScatterNative.force_gdscript = false
	var wet := doc.water_dressing.size() == doc.sample_count() * WaterDressing.CHANNELS
	var fallbacks := ScatterNative.fallbacks()
	return {
		"rows": rows,
		"differing": differing,
		"fallbacks": fallbacks,
		"summary":
		(
			"%s: wet %s, crossings %d, %d rows, %s, differing jobs %s"
			% [landform, wet, doc.crossings.size(), rows, fallbacks, differing]
		),
	}
