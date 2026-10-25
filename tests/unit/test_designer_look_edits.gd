extends GutTest

## The ground look editor's model (step S9): DesignerLookFields (the rows the editor builds, each
## inside the contract's ranges), DesignerLookEdits (reading and writing a field of the biome's
## look or of one season's override, the library's value of a field, reset, zone colours in
## linear light, the words about a field and the draft) and the session's look refresh through
## the palette. The library is the designer fixture; its biome gets a look in the tests that
## need one.

const Fixture := preload("res://tests/unit/designer_fixture.gd")
const FOLDER := "user://test_designer_look_edits/mini"
const COLOURS := [[0.1, 0.2, 0.1], [0.2, 0.3, 0.1], [0.3, 0.3, 0.1]]

var _model: BiomeDesignerModel = null


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER + "/biomes")
	var made := Fixture.context(FOLDER, true)
	var def: Dictionary = made["read"]["biomes"][0]["def"]
	def["ground_look"] = {"zones": {"colors_linear": COLOURS.duplicate(true), "strength": 0.8}}
	_model = BiomeDesignerModel.from_context(made, "meadow")
	assert_eq(_model.error, "")


# ---- the fields ----


func test_every_field_of_the_editor_is_a_contract_key_inside_its_range() -> void:
	for entry in DesignerLookFields.GROUPS:
		var group := String(entry["id"])
		assert_true(GroundLook.BASE.has(group), group)
		for field: Dictionary in entry["fields"]:
			var key := String(field["key"])
			assert_true((GroundLook.BASE[group] as Dictionary).has(key), "%s.%s" % [group, key])
			if field["kind"] == "colors" or field["kind"] == "color":
				continue
			var limits: Array = GroundLook.RANGES.get("%s.%s" % [group, key], [-INF, INF])
			assert_true(float(field["low"]) >= float(limits[0]), "%s.%s low" % [group, key])
			assert_true(float(field["high"]) <= float(limits[1]), "%s.%s high" % [group, key])
			assert_true(float(field["low"]) < float(field["high"]))
			assert_true(float(field["step"]) > 0.0)
			if field["kind"] == "triple":
				assert_eq((field["labels"] as Array).size(), 3, "%s.%s" % [group, key])
				assert_eq(((GroundLook.BASE[group] as Dictionary)[key] as Array).size(), 3)
	assert_eq(DesignerLookFields.spec("zones", "strength")["label"], "Strength")
	assert_eq(DesignerLookFields.spec("zones", "nope"), {})
	assert_true("zones.cover" in DesignerLookFields.names())


# ---- reading and writing ----


func test_values_read_the_look_over_the_base() -> void:
	assert_true(DesignerLookEdits.has_look(_model, ""))
	assert_eq(DesignerLookEdits.value(_model, "", "zones", "strength"), 0.8)
	assert_eq(DesignerLookEdits.value(_model, "", "zones", "warp"), GroundLook.BASE.zones.warp)
	assert_false(DesignerLookEdits.is_set(_model, "", "zones", "warp"))
	assert_true(DesignerLookEdits.is_set(_model, "", "zones", "strength"))
	assert_false(DesignerLookEdits.is_changed(_model, "", "zones", "strength"))


func test_a_field_edit_is_one_undo_step_and_marks_the_field_changed() -> void:
	assert_true(DesignerLookEdits.set_value(_model, "", "light", "shade", 0.7))
	assert_eq(_model.def["ground_look"]["light"], {"shade": 0.7})
	assert_true(DesignerLookEdits.is_changed(_model, "", "light", "shade"))
	var library: Variant = DesignerLookEdits.library_value(_model, "", "light", "shade")
	assert_eq(library, GroundLook.BASE.light.shade)
	assert_false(DesignerLookEdits.set_value(_model, "", "light", "shade", 0.7), "no change")
	assert_true(_model.undo())
	assert_false(_model.def["ground_look"].has("light"))
	assert_false(DesignerLookEdits.set_value(_model, "", "light", "nope", 1), "not a contract key")
	assert_false(DesignerLookEdits.set_value(_model, "", "nope", "shade", 1))


func test_a_drag_folds_into_one_step() -> void:
	DesignerLookEdits.set_value(_model, "", "light", "shade", 0.5, true)
	DesignerLookEdits.set_value(_model, "", "light", "shade", 0.6, true)
	DesignerLookEdits.set_value(_model, "", "light", "shade", 0.7, true)
	assert_true(_model.undo())
	assert_false(_model.can_undo())


func test_reset_puts_the_librarys_value_back() -> void:
	DesignerLookEdits.set_value(_model, "", "zones", "strength", 0.3)
	DesignerLookEdits.set_value(_model, "", "light", "shade", 0.7)
	assert_true(DesignerLookEdits.reset_value(_model, "", "zones", "strength"))
	assert_eq(DesignerLookEdits.value(_model, "", "zones", "strength"), 0.8, "the saved value")
	assert_true(DesignerLookEdits.reset_value(_model, "", "light", "shade"))
	assert_false(_model.def["ground_look"].has("light"), "the base shows through again")
	assert_false(DesignerLookEdits.reset_value(_model, "", "light", "shade"), "nothing to reset")
	DesignerLookEdits.set_value(_model, "", "mass", "step", 1.5)
	DesignerLookEdits.set_value(_model, "", "zones", "strength", 0.1)
	assert_true(DesignerLookEdits.reset_all(_model, ""))
	assert_eq(_model.def["ground_look"], _model.saved_def()["ground_look"])
	assert_false(DesignerLookEdits.reset_all(_model, ""))


func test_a_season_target_edits_only_its_override() -> void:
	DesignerSeasonEdits.add_season(_model, "winter")
	assert_true(DesignerLookEdits.set_value(_model, "winter", "zones", "strength", 0.2))
	assert_eq(
		_model.def["seasons"][2]["overrides"]["ground_look"], {"zones": {"strength": 0.2}}
	)
	assert_eq(_model.def["ground_look"]["zones"]["strength"], 0.8, "the biome's look is untouched")
	assert_eq(DesignerLookEdits.value(_model, "winter", "zones", "strength"), 0.2)
	assert_eq(DesignerLookEdits.value(_model, "", "zones", "strength"), 0.8)
	assert_eq(DesignerLookEdits.value(_model, "winter", "zones", "rag"), GroundLook.BASE.zones.rag)
	assert_true(DesignerLookEdits.is_changed(_model, "winter", "zones", "strength"))
	assert_true(DesignerLookEdits.reset_value(_model, "winter", "zones", "strength"))
	assert_false(_model.def["seasons"][2].has("overrides"), "reset leaves no empty override")


# ---- colours ----


func test_zone_colours_are_stored_in_linear_light() -> void:
	var picked := Color("#d0402a")
	assert_true(DesignerLookEdits.set_zone_color(_model, "", 0, picked))
	var stored: Array = _model.def["ground_look"]["zones"]["colors_linear"][0]
	var linear := picked.srgb_to_linear()
	assert_almost_eq(float(stored[0]), linear.r, 0.0002)
	assert_almost_eq(float(stored[1]), linear.g, 0.0002)
	assert_almost_eq(float(stored[2]), linear.b, 0.0002)
	var shown := DesignerLookEdits.display_color(stored)
	assert_almost_eq(shown.r, picked.r, 0.01, "the picker shows what was picked")
	assert_almost_eq(shown.b, picked.b, 0.01)
	assert_eq(DesignerLookEdits.display_color("x"), Color.BLACK, "not a colour")


func test_zone_colours_come_and_go_between_three_and_four() -> void:
	assert_false(DesignerLookEdits.remove_zone_color(_model, "", 0), "three stay")
	assert_true(DesignerLookEdits.set_zone_color(_model, "", 3, Color.RED), "a fourth")
	assert_eq(_model.def["ground_look"]["zones"]["colors_linear"].size(), 4)
	assert_false(DesignerLookEdits.set_zone_color(_model, "", 4, Color.RED), "at most four")
	assert_true(DesignerLookEdits.remove_zone_color(_model, "", 1))
	assert_eq(_model.def["ground_look"]["zones"]["colors_linear"].size(), 3)


func test_a_biome_without_a_look_can_be_given_one() -> void:
	_model.def.erase("ground_look")
	_model.context["surfaces"] = {"grass": {"role": "ground"}}
	assert_false(DesignerLookEdits.has_look(_model, ""))
	assert_true(DesignerLookEdits.add_look(_model))
	assert_eq(_model.def["ground_look"]["ref_surface"], "grass", "measured against the ground")
	assert_true(DesignerLookEdits.has_look(_model, ""))
	assert_eq(DesignerLookEdits.value(_model, "", "zones", "colors_linear").size(), 4)
	assert_false(DesignerLookEdits.add_look(_model), "it has one now")
	var verdict := _model.validation()
	assert_eq(verdict["errors"], [])
	assert_eq(DesignerLookEdits.warnings(_model, ""), [], "the default look is clean")


# ---- the words ----


func test_a_value_outside_its_range_is_named() -> void:
	assert_eq(DesignerLookEdits.field_problem(_model, "", "zones", "strength"), "")
	_model.def["ground_look"]["zones"]["strength"] = 1.7
	assert_true("over 1" in DesignerLookEdits.field_problem(_model, "", "zones", "strength"))
	_model.def["ground_look"]["zones"]["cover"] = [0.1, 0.2]
	assert_true("3 numbers" in DesignerLookEdits.field_problem(_model, "", "zones", "cover"))
	_model.def["ground_look"]["zones"]["colors_linear"] = [[0.1, 0.1, 0.1]]
	assert_true("colours" in DesignerLookEdits.field_problem(_model, "", "zones", "colors_linear"))
	assert_true(DesignerLookEdits.warnings(_model, "").size() > 0, "the consumer would ignore it")


func test_the_look_slots_of_a_map_are_counted() -> void:
	var none := PackedStringArray(["no_such_biome"])
	assert_eq(DesignerLookEdits.looked_biomes(none), 0)
	assert_eq(GroundLookUniforms.SLOTS, 4)
