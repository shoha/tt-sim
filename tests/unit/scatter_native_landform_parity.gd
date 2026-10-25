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
## With `curved`, every rule of the biome carries terrain response (curved_species) and the run
## must reach the native path: a library without the "curves" capability FAILS here (jobs refused
## as "curves"), it does not pend.
static func check(test: GutTest, landform: String, curved: bool = false) -> void:
	if not ScatterNative.available():
		test.pending("the native library is not built (AGENTS.md Testing): GDScript path only")
		return
	var result := compare(landform, curved)
	test.gut.p(result.summary)
	test.assert_gt(result.rows, 0)
	test.assert_false((result.fallbacks as Dictionary).has("missing"))
	test.assert_false((result.fallbacks as Dictionary).has("curves"), "curved jobs run natively")
	test.assert_false((result.fallbacks as Dictionary).has("water"), "water_dist jobs run natively")
	test.assert_eq(result.differing, [], "%s: every job equal" % landform)


## `species` with terrain response on every rule, a different mix by index: a slope minimum, a
## slope curve, a height curve (metres), a wet curve, a water_dist curve (metres to water), and
## all of them together. Placement still varies (no curve zeroes a rule on every map), and a
## stale library that ignores the keys places different rows than GDScript.
static func curved_species(species: Array[Dictionary]) -> Array[Dictionary]:
	var variants: Array[Dictionary] = [
		{"slope_min_deg": 3.0},
		{"response": {"slope": [[0, 1], [8, 1], [25, 0.35], [50, 0.0]]}},
		{"response": {"height": [[-500, 0.45], [-1, 0.45], [0.5, 1.0], [2.5, 1.0], [6, 0.55]]}},
		{"response": {"wet": [[0, 1], [0.2, 0.6], [0.7, 0.15], [1, 0.0]]}},
		{
			"slope_min_deg": 1.5,
			"response":
			{
				"slope": [[0, 0.6], [12, 1], [40, 0.5]],
				"height": [[-500, 1], [3, 0.8], [5000, 0.3]],
				"wet": [[0, 1], [1, 0.4]],
				"water_dist": [[0, 1], [25, 0.5]],
			},
		},
		{"response": {"water_dist": [[0, 1], [3, 0.7], [10, 0.25], [40, 0.05]]}},
		{"response": {"water_dist": [[0, 0.3], [12, 1.0]], "slope": [[0, 1], [30, 0.6]]}},
	]
	var out: Array[Dictionary] = []
	for i in species.size():
		out.append(species[i].merged(variants[i % variants.size()].duplicate(true), true))
	return out


## Every regen job of `landform`'s new map run native and forced to GDScript: {"rows" (GDScript's
## row count), "differing" (the cells of each job whose rows or anchors differ), "fallbacks"
## (ScatterNative.fallbacks() after the run), "summary" (a line for the log)}.
@warning_ignore("integer_division")
static func compare(landform: String, curved: bool = false) -> Dictionary:
	var doc := NewMap.create(SIZE_FT, BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, landform)
	if landform == "valley":
		var crossing := Crossing.new()
		crossing.start = Vector2(-6.0, 2.0)
		crossing.end = Vector2(5.0, -3.0)
		crossing.width_m = 1.8
		doc.crossings.append(crossing)
	var regen := ScatterRegen.for_document(doc)
	var species := PaletteLibrary.species(BIOME)
	regen.set_biome(BIOME, curved_species(species) if curved else species)
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
