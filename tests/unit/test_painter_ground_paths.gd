extends GutTest

## The painted ground's path surfaces and cliff stone (PainterGroundPaths, card
## painter-ground-surfaces): every core path surface has a pattern, a map's path surfaces take
## slots with their own tones, the slot map marks where each lies, and the cliff stone is warmer
## than the stone and follows the map's own cliff surface.

const BIOMES_DIR := "res://libraries/core/biomes"


func _doc_with_paths(ids: PackedStringArray) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "grass_meadow", "test", 7)
	var n := doc.samples_x() * doc.samples_z()
	doc.surface_ids = ids
	var weights := PackedByteArray()
	weights.resize(n * MapDocument.SURFACE_BYTES)
	# Left half the first surface, right half the second, at full weight.
	for i in n:
		var x := i % doc.samples_x()
		weights[i * 4] = 0 if x < doc.samples_x() / 2 else mini(1, ids.size() - 1)
		weights[n * 4 + i * 4] = 255
	doc.surface_weights = weights
	return doc


func test_every_core_biome_path_surface_is_a_path_with_its_own_pattern() -> void:
	var kinds := {}
	for file in DirAccess.get_files_at(BIOMES_DIR):
		if not file.ends_with(".json"):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BIOMES_DIR + "/" + file))
		for id: String in (data.get("ground", {}) as Dictionary).get("paths", []):
			assert_eq(PainterGroundRoles.surface_role(id), "path", "%s paints as a path" % id)
			kinds[id] = PainterGroundRoles.PATH_KINDS[PainterGroundRoles.path_kind(id)]
	assert_eq(kinds.get("cobblestone"), "cobble")
	assert_eq(kinds.get("flagstone"), "plates")
	assert_eq(kinds.get("flagstone_sandstone"), "plates")
	assert_eq(kinds.get("stone_tiles"), "tiles")
	assert_eq(kinds.get("planks"), "planks")
	assert_eq(kinds.get("dirt_road_packed"), "dirt")
	assert_eq(PainterGroundRoles.PATH_KINDS[PainterGroundRoles.path_kind("gravel")], "gravel")
	assert_eq(PainterGroundRoles.path_kind("someone_elses_lane"), 0, "unknown: the plain band")


func test_a_maps_path_surfaces_take_slots_in_order_and_a_meadow_none() -> void:
	var doc := _doc_with_paths(PackedStringArray(["grass_meadow", "cobblestone", "flagstone"]))
	assert_eq(PainterGroundPaths.slots(doc), PackedStringArray(["cobblestone", "flagstone"]))
	doc.base_surface = "dirt_road_packed"
	assert_eq(PainterGroundPaths.slots(doc)[0], "dirt_road_packed", "a path base comes first")


func test_the_slot_map_marks_each_path_where_it_lies_and_one_path_needs_none() -> void:
	var ids := PackedStringArray(["cobblestone", "flagstone"])
	var doc := _doc_with_paths(ids)
	var slots := PainterGroundPaths.slots(doc)
	var image := PainterGroundPaths.slot_image(doc, slots)
	assert_not_null(image, "two paths painted: a slot map")
	var row := doc.samples_z() / 2
	assert_eq(image.get_pixel(1, row).r8, slots.find("cobblestone"), "left: cobble")
	assert_eq(image.get_pixel(doc.samples_x() - 2, row).r8, slots.find("flagstone"), "right: flag")
	var one := _doc_with_paths(PackedStringArray(["cobblestone"]))
	var one_slots := PainterGroundPaths.slots(one)
	assert_null(PainterGroundPaths.slot_image(one, one_slots), "one path: no map")
	assert_eq(PainterGroundPaths.only_slot(one, one_slots), 0)
	var none := _doc_with_paths(PackedStringArray(["grass_meadow"]))
	assert_eq(PainterGroundPaths.only_slot(none, PainterGroundPaths.slots(none)), -1)


func test_each_path_surface_paints_its_own_tone_and_the_mood_moves_them() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var ids := PackedStringArray(["dirt_road_packed", "cobblestone", "flagstone_sandstone"])
	var summer := PainterGroundPaths.tones(sheet, "summer", 60.0, ids)
	assert_eq((summer["lit"] as PackedVector3Array).size(), PainterGroundPaths.MAX_SLOTS * 2)
	assert_eq(summer["kind"][1], PainterGroundRoles.PATH_KINDS.find("cobble"))
	var lch := func(c: Vector3) -> Vector3:
		return PainterSheet.lch_of_color(Color(c.x, c.y, c.z).linear_to_srgb())
	var dirt: Vector3 = lch.call(summer["lit"][0])
	var cobble: Vector3 = lch.call(summer["lit"][2])
	var sand: Vector3 = lch.call(summer["lit"][4])
	assert_lt(cobble.y, dirt.y * 0.5, "a grey cobble is far less chromatic than a dirt road")
	assert_lt(cobble.x, dirt.x, "and darker")
	assert_gt(sand.x, cobble.x + 0.05, "a sandstone flag is a pale warm stone")
	var winter := PainterGroundPaths.tones(sheet, "winter", 24.0, ids)
	assert_ne(
		(winter["lit"][2] as Vector3).snappedf(0.01),
		(summer["lit"][2] as Vector3).snappedf(0.01),
		"the mood moves a path's tone"
	)


func test_the_cliff_stone_is_warmer_than_the_stone_and_follows_its_own_surface() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var stone := PainterSheet.tone_lch(sheet, "summer", "stone", 60.0)
	var cliff := PainterGroundPaths.cliff_tone(sheet, "summer", 60.0, "cliff")
	assert_gt(cliff.y, stone.y, "richer than the grey stone")
	assert_lt(cliff.z, stone.z, "turned warmer (toward orange)")
	var sandstone := PainterGroundPaths.cliff_tone(sheet, "summer", 60.0, "cliff_sandstone")
	assert_gt(sandstone.y, cliff.y, "a sandstone cliff is richer still")
	var basalt := PainterGroundPaths.cliff_tone(sheet, "summer", 60.0, "cliff_basalt")
	assert_lt(basalt.x, cliff.x, "a basalt cliff is darker")
	var night := PainterGroundPaths.cliff_tone(sheet, "summer", -8.0, "cliff")
	assert_lt(night.x, cliff.x, "and the night darkens it")


func test_a_cliff_shade_keeps_its_hue_instead_of_swinging_violet() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var base := PainterGroundPaths.cliff_tone(sheet, "summer", 60.0, "cliff")
	var plain := PainterTones.ramp(sheet, "summer", "stone", 60.0, "ground-", base)
	var cliff := PainterTones.ramp(
		sheet,
		"summer",
		"stone",
		60.0,
		"ground-",
		base,
		PainterSheet.number(sheet, "summer", "cliff-pull", 60.0),
		PainterSheet.number(sheet, "summer", "cliff-shade-lift", 60.0)
	)
	var plain_shade := PainterSheet.lch_of_color(plain[0])
	var cliff_shade := PainterSheet.lch_of_color(cliff[0])
	assert_gt(cliff_shade.x, plain_shade.x, "a lighter shade")
	var off := func(h: float) -> float: return absf(fposmod(h - base.z + 180.0, 360.0) - 180.0)
	assert_lt(off.call(cliff_shade.z), off.call(plain_shade.z), "nearer its own hue")
