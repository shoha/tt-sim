extends GutTest

## The painted village fields (PainterFields, card painter-fields): the fields the ground paints and
## their map, the soil's and the crops' tones in two moods, the crop plants' entry, the hedges'
## species and the A/B switch.

const HEDGE := "grassland_meadow_summer_s1/Bush_Bush_v0_grassland_meadow"

var _doc: MapDocument
var _sheet: Dictionary


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var record := Settlement.make(1, "farming_hamlet", 1, 5)
	record.fields.append({"at": Vector2(-6, 0), "radius": 6.0, "kind": "crops"})
	record.fields.append({"at": Vector2(8, 0), "radius": 5.0, "kind": "garden"})
	record.fields.append({"at": Vector2(0, 10), "radius": 6.0, "kind": "orchard"})
	_doc.settlements.append(record)
	_sheet = PainterSheet.load_sheet("core")


func after_each() -> void:
	PainterFields.enabled = true


func test_crop_and_garden_fields_are_painted_an_orchard_is_not() -> void:
	var fields := PainterFields.fields_of(_doc)
	assert_eq(fields.size(), 2)
	var crops := fields[0]
	assert_eq(int(crops["style"]), PainterFields.STYLE_CROPS)
	assert_eq(int(crops["crop"]), VillageCrops.tone_of(Vector2(-6, 0), 5))
	assert_eq(int(fields[1]["style"]), PainterFields.STYLE_GARDEN)
	assert_eq(int(fields[1]["crop"]), -1)


func test_the_rows_are_the_plant_rows() -> void:
	var crops := PainterFields.fields_of(_doc)[0]
	var turn := VillageFields.angle_of(_doc.settlements[0].fields[0], 5)
	assert_almost_eq(float(crops["angle"]), turn, 1e-5)
	var across := Vector2.from_angle(turn).orthogonal()
	var pitch := float(crops["pitch"])
	# Every crop plant stands on a painted row: its offset across is start + n * pitch.
	var plants := VillageCrops.plants_of(_doc.settlements[0].fields[0], 5, turn)
	assert_gt(plants.size(), 0)
	for plant in plants:
		var u := ((plant["at"] as Vector2) - Vector2(-6, 0)).dot(-across)
		var k := (u - float(crops["start"])) / pitch
		assert_almost_eq(k, roundf(k), 1e-3)
		assert_between(roundi(k), 0, int(crops["count"]) - 1)


func test_the_field_map_names_each_field_and_none_outside() -> void:
	var fields := PainterFields.fields_of(_doc)
	var image := PainterFields.field_image(_doc, fields)
	assert_not_null(image)
	var at := func(p: Vector2) -> int:
		var s := (p + _doc.extent_m() * 0.5) / _doc.sample_step()
		return image.get_pixel(roundi(s.x), roundi(s.y)).r8
	assert_eq(at.call(Vector2(-6, 0)), 0)
	assert_eq(at.call(Vector2(8, 0)), 1)
	assert_eq(at.call(Vector2(0, 10)), PainterFields.NONE)
	assert_eq(at.call(Vector2(-6, -15)), PainterFields.NONE)
	assert_null(PainterFields.field_image(_doc, []))


func test_bind_sets_the_map_and_off_clears_it() -> void:
	var material := ShaderMaterial.new()
	PainterFields.bind([material], _doc)
	assert_true(material.get_shader_parameter(&"field_present"))
	assert_eq((material.get_shader_parameter(&"f_geo") as PackedVector4Array).size(), 32)
	PainterFields.enabled = false
	PainterFields.bind([material], _doc)
	assert_false(material.get_shader_parameter(&"field_present"))


func test_tones_cover_the_soil_and_every_crop() -> void:
	var tones := PainterFields.tones(_sheet, "summer", 45.0)
	assert_eq((tones[&"f_soil"] as PackedVector3Array).size(), 4)
	assert_eq((tones[&"f_crop_lit"] as PackedVector3Array).size(), VillageCrops.TONES.size() * 2)
	assert_eq(float(tones[&"f_snow"]), 0.0)
	assert_gt(float(PainterFields.tones(_sheet, "winter", 24.0)[&"f_snow"]), 0.0)


func test_the_soil_is_a_warm_earth_darker_than_the_path() -> void:
	for mood in ["summer", "dusk", "autumn"]:
		var soil := PainterFields.soil_lch(_sheet, mood, 45.0)
		var path := PainterSheet.tone_lch(_sheet, mood, "path", 45.0)
		assert_lt(soil.x, path.x, mood)
		assert_eq(soil.z, PainterSheet.number(_sheet, mood, "soil-hue", 45.0), mood)


func test_ripe_wheat_is_gold_in_summer_and_straw_in_winter() -> void:
	var gold := Vector3(0.74, 0.11, 88.0)
	var summer_grass := PainterSheet.tone_lch(_sheet, "summer", "grass", 45.0)
	var ripe := PainterFields.crop_lch(_sheet, "summer", 45.0, gold)
	# Turned from the meadow's green toward gold by most of the way.
	assert_lt(ripe.z, summer_grass.z - 10.0)
	var straw := PainterSheet.tone_lch(_sheet, "winter", "grass", 24.0)
	var winter := PainterFields.crop_lch(_sheet, "winter", 24.0, gold)
	assert_almost_eq(winter.z, straw.z, 8.0)


func test_a_crop_record_carries_its_crop_and_others_do_not() -> void:
	var entry := PainterPlantRoles._entry(PainterPlantRoles.KIND_GRASS, "grass")
	var crop := PainterFields.plant_entry(entry, {"crop": true, "mesh": null})
	assert_true(crop.get("crop", false))
	assert_true(crop.has("own"))
	assert_false(PainterFields.plant_entry(entry, {"crop": false}).has("crop"))
	PainterFields.enabled = false
	assert_false(PainterFields.plant_entry(entry, {"crop": true}).has("crop"))


func test_hedges_and_crops_are_told_apart_by_the_layer() -> void:
	assert_eq(AuthoredFieldPlants.paint_key(HEDGE), AuthoredFieldPlants.HEDGE_KEY + HEDGE)
	assert_eq(PainterTreeSpecies.species_for(AuthoredFieldPlants.paint_key(HEDGE)), "bush_hedge")
	assert_eq(PainterTreeSpecies.species_for(HEDGE), PainterTreeSpecies.BUSH)
	var grass := str(VillageCrops.PLANT_ASSETS["grass"][0])
	assert_eq(AuthoredFieldPlants.paint_key(grass), grass)
	assert_true(AuthoredFieldPlants.is_crop(grass))
	assert_false(AuthoredFieldPlants.is_crop(HEDGE))


func test_the_hedge_is_a_bush_with_its_own_rows() -> void:
	assert_true(PainterTreeSpecies.is_bush("bush_hedge"))
	var rows: Dictionary = PainterTreeTones.row_table()
	assert_true(rows.has("bush_hedge"))
	var count := 0
	for species: String in rows:
		count += (rows[species] as Dictionary).size()
	assert_lt(count + PainterTreeTones.GROUND_ROW + 1, PainterTreeTones.MAX_ROWS)
