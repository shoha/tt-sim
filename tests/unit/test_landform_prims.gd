extends GutTest

## LandformPrims (card terraform-p2-landforms): every starting landform on primitives, at seeds
## 1234, 7 and 99 on a 150 ft map, against the switch-off recipe on the same flat document: a
## valid terrain section whose derive wrote the heights, the same shape features (the report's
## bluff, crown, ledge, second hill, islet, knoll, tarn and wash each made as primitives), the
## same stage within a quarter of the map, water only where the recipe drew it, and the
## recipe's crossings placed again on the derived water. Plus a big map's extras and Flat.

const PRIMS := preload("res://utils/terraform/landform_prims.gd")
const BIOME := "temperate_forest_summer_s1"
const SEEDS: Array[int] = [1234, 7, 99]
const SIZE_FT := 150

var _pairs: Array = []


func before_all() -> void:
	if not TerraCore.native_available():
		return
	for kind in StartingLandform.KINDS:
		for seed_value in SEEDS:
			_pairs.append(_pair(kind, seed_value, SIZE_FT))


func _flat(size_ft: int, seed_value: int) -> MapDocument:
	var root := PaletteLibrary.DEFAULT_ROOT
	var surface := String(PaletteLibrary.biome(BIOME, root).get("ground_surface", ""))
	return MapDocument.create_flat(
		NewMap.size_cells(size_ft), surface, PaletteLibrary.palette_version(root), seed_value
	)


func _pair(kind: String, seed_value: int, size_ft: int) -> Dictionary:
	var off := _flat(size_ft, seed_value)
	var on := _flat(size_ft, seed_value)
	var root := PaletteLibrary.DEFAULT_ROOT
	var shaped := StartingLandform.apply(off, kind, seed_value, BIOME, root)
	var made: Dictionary = PRIMS.apply(kind, on, seed_value, BIOME, root)
	return {
		"label": "%s seed %d %d ft" % [kind, seed_value, size_ft],
		"off": off,
		"on": on,
		"shaped": shaped,
		"made": made,
	}


func _water(doc: MapDocument) -> Vector2i:
	var rivers := 0
	var ponds := 0
	for body: WaterBody in doc.water_bodies:
		if body.is_river():
			rivers += 1
		else:
			ponds += 1
	return Vector2i(rivers, ponds)


func _kinds(doc: MapDocument) -> Array:
	var out: Array = []
	for crossing: Crossing in doc.crossings:
		out.append(Crossing.KIND_NAMES[crossing.kind])
	out.sort()
	return out


func test_each_landform_is_a_valid_derived_section() -> void:
	if not TerraCore.native_available():
		pass_test("no terraforming library")
		return
	for pair: Dictionary in _pairs:
		var on: MapDocument = pair.on
		var terra := on.terra as TerraDoc
		assert_not_null(terra, pair.label)
		if terra == null:
			continue
		assert_eq(terra.problem(), "", pair.label + " section")
		assert_false(terra.derived.is_empty(), pair.label + " derived record")
		assert_eq(terra.prims[0].kind, TerraCore.PLANE, pair.label + " a plane first")
		var written := MapDocumentIO.serialize(on)
		assert_eq(written.error, "", pair.label + " writes")
		var derive := TerraCache.derive_for(terra, on)
		assert_eq(on.heights, derive.call("doc_heights"), pair.label + " heights are the derive's")
		gut.p("%s: %s" % [pair.label, pair.made.get("report", "")])


func test_the_features_match_the_recipe() -> void:
	if not TerraCore.native_available():
		pass_test("no terraforming library")
		return
	for pair: Dictionary in _pairs:
		var off_features := PRIMS.report_features(String(pair.shaped.get("report", "")))
		var made: PackedStringArray = pair.made.get("made", PackedStringArray())
		assert_eq(PRIMS.made_features(made), off_features, pair.label + " features")


func test_the_stage_is_the_recipes_within_a_quarter_of_the_map() -> void:
	if not TerraCore.native_available():
		pass_test("no terraforming library")
		return
	for pair: Dictionary in _pairs:
		var stage: Vector2 = pair.made.get("stage", Vector2.INF)
		var half := StartingLandform.half_extent(pair.on)
		assert_eq(stage, pair.shaped.get("stage", Vector2.ZERO), pair.label + " stage")
		assert_lte(stage.length(), half * 0.5 + 1e-3, pair.label + " within a quarter")


func test_water_only_when_drawn_and_crossings_placed_again() -> void:
	if not TerraCore.native_available():
		pass_test("no terraforming library")
		return
	var wet := 0
	var crossed := 0
	for pair: Dictionary in _pairs:
		var off := _water(pair.off)
		var on := _water(pair.on)
		assert_eq(on.x > 0, off.x > 0, pair.label + " rivers")
		assert_eq(on.y, off.y, pair.label + " ponds")
		assert_eq(_kinds(pair.on), _kinds(pair.off), pair.label + " crossings")
		wet += 1 if off.x > 0 else 0
		crossed += 1 if not pair.off.crossings.is_empty() else 0
	assert_gt(wet, 0, "a seed draws a river, so the water is compared")
	assert_gt(crossed, 0, "a seed draws a crossing, so the crossings are compared")


func test_flat_is_one_plane() -> void:
	if not TerraCore.native_available():
		pass_test("no terraforming library")
		return
	var doc := _flat(100, 5)
	var before := doc.heights.duplicate()
	var shaped: Dictionary = PRIMS.apply(StartingLandform.FLAT, doc, 5, BIOME)
	assert_eq((doc.terra as TerraDoc).prims.size(), 1)
	assert_eq(doc.heights, before, "a plane at the flat height")
	assert_eq(shaped.get("stage"), Vector2.ZERO)
	assert_true(doc.water_bodies.is_empty())


func test_a_big_maps_extras_are_primitives() -> void:
	if not TerraCore.native_available():
		pass_test("no terraforming library")
		return
	var extras := 0
	for seed_value in [1, 2, 3, 4]:
		var pair := _pair(StartingLandform.HILLTOP, seed_value, 320)
		var off_features := PRIMS.report_features(String(pair.shaped.get("report", "")))
		var made: PackedStringArray = pair.made.get("made", PackedStringArray())
		assert_eq(PRIMS.made_features(made), off_features, pair.label + " features")
		assert_eq(_water(pair.on).y, _water(pair.off).y, pair.label + " ponds")
		extras += off_features.count("knoll") + off_features.count("tarn")
		gut.p("%s: %s" % [pair.label, pair.made.get("report", "")])
	assert_gt(extras, 0, "a seed draws a knoll or a tarn")
