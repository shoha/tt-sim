extends GutTest

## A street's cross-section (StreetProfile, docs/systems/settlements.md "Street profile"): every
## lane species keeps the strip and road it had, the modern row is a two-lane road between pavements
## whose road half and strip add up to its setback, and the frontage strip, the painted road, its
## pavements and a bridge's width all read the one profile.

const SETBACKS: Array[float] = [1.5, 2.0, 3.0, 3.6, 4.5, 5.5, 7.0, 8.4, 10.0]

var _modern := -1


func before_all() -> void:
	_modern = ProcgenStreetSpecies.NAMES.find("modern_row")
	StructureRecipes.ensure_served()


func _doc_with_street(preset: int, setback_m: float) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var line := PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)])
	var wall := Wall.make(1, Wall.Kind.ROW, line, false, setback_m)
	wall.preset = preset
	wall.side = 2
	wall.seed_value = 5
	doc.walls.append(wall)
	return doc


func _strokes(result: Dictionary, role: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stroke: Dictionary in result["strokes"]:
		if stroke["role"] == role:
			out.append(stroke)
	return out


func _plan(doc: MapDocument, kit: String) -> Dictionary:
	var ground := ProcgenSettlement.ground_of(ProcgenSettlement.kit_named(kit))
	return SettlementGround.plan(
		doc,
		Settlement.make(1, kit, 1, 77),
		ground,
		PaletteLibrary.surfaces(PaletteLibrary.DEFAULT_ROOT)
	)


func test_only_the_modern_row_is_a_wide_street() -> void:
	assert_gt(_modern, -1, "procgen names the modern row")
	for preset in StreetSpeciesInfo.count():
		assert_eq(StreetSpeciesInfo.is_wide(preset), preset == _modern, "preset %d" % preset)
	assert_false(StreetSpeciesInfo.is_wide(-1))
	assert_false(StreetSpeciesInfo.is_wide(99), "an unknown preset is a lane street")


func test_every_lane_species_keeps_the_strip_and_road_it_had() -> void:
	# The formulas before the profile (SettlementFrontage 0.75 of the setback in 1..4 m,
	# SettlementGround 0.77 of it in 1.2..3.2 m), written out so a change to them shows here.
	for preset in StreetSpeciesInfo.count():
		if preset == _modern:
			continue
		for setback in SETBACKS:
			var profile := StreetProfile.of(preset, setback)
			var label := "preset %d at %.1f m" % [preset, setback]
			assert_eq(float(profile["strip"]), clampf(setback * 0.75, 1.0, 4.0), label)
			assert_eq(float(profile["road_half"]), clampf(setback * 0.77, 1.2, 3.2), label)
			assert_false(bool(profile["pavement"]), label + ": no pavement band")
			assert_eq(float(profile["setback"]), setback)


func test_the_modern_row_is_a_two_lane_road_between_ample_pavements() -> void:
	var setback := StreetSpeciesInfo.setback_m(_modern)
	var profile := StreetProfile.of(_modern, setback)
	assert_almost_eq(setback, 8.4, 1e-6)
	assert_almost_eq(float(profile["road_half"]), 4.3, 0.001, "an 8.6 m road of two lanes")
	assert_almost_eq(float(profile["strip"]), 4.1, 0.001, "a 4.1 m pavement each side")
	assert_true(bool(profile["pavement"]))
	assert_gte(float(profile["strip"]), 3.75, "wide enough for the kit's parked cars and tree tubs")


func test_a_modern_road_half_and_strip_add_up_to_its_setback() -> void:
	var previous := {"road_half": 0.0, "strip": 0.0}
	for setback in SETBACKS:
		if setback < 2.5:
			continue
		var profile := StreetProfile.of(_modern, setback)
		var label := "modern at %.1f m" % setback
		assert_almost_eq(
			float(profile["road_half"]) + float(profile["strip"]), setback, 1e-5, label
		)
		assert_gte(float(profile["road_half"]), float(previous["road_half"]), label + ": road grows")
		assert_gt(float(profile["strip"]), float(previous["strip"]), label + ": pavement grows")
		assert_lte(float(profile["road_half"]), StreetProfile.WIDE_ROAD_HALF_MAX_M)
		previous = profile
	var narrow := StreetProfile.of(_modern, Wall.MIN_HEIGHT_M[Wall.Kind.ROW])
	assert_gte(float(narrow["strip"]), StreetProfile.WIDE_STRIP_MIN_M, "the narrowest keeps a strip")


func test_frontage_gap_road_paint_and_bridge_width_agree_with_the_profile() -> void:
	for preset in [3, _modern]:
		for setback in [3.0, 8.4]:
			var doc := _doc_with_street(preset, setback)
			var wall := doc.walls[0]
			var profile := StreetProfile.of_wall(wall)
			var label := "preset %d at %.1f m" % [preset, setback]
			for frontage in SettlementFrontage.of_street(doc, wall):
				assert_almost_eq(frontage.gap_m, float(profile["strip"]), 1e-6, label + ": frontage")
			var road := _strokes(_plan(doc, "modern_town"), "road")
			assert_gt(road.size(), 0, label + ": a road is laid")
			for stroke in road:
				assert_almost_eq(
					float(stroke["radius"]),
					float(profile["road_half"]) * SettlementGround.EDGE_REACH,
					0.006,
					label + ": road paint"
				)
			assert_almost_eq(
				SettlementGround.road_half_width(setback, preset), float(profile["road_half"]), 1e-6
			)
			var plank := VillageBridges.width_for(Crossing.Kind.PLANK, setback, preset)
			assert_almost_eq(
				plank,
				clampf(
					2.0 * float(profile["road_half"]),
					Crossing.MIN_WIDTH_M[Crossing.Kind.PLANK],
					Crossing.MAX_WIDTH_M[Crossing.Kind.PLANK]
				),
				1e-6,
				label + ": bridge"
			)


func test_a_modern_street_paves_both_pavements_from_kerb_to_facade() -> void:
	var doc := _doc_with_street(_modern, 8.4)
	var plan := _plan(doc, "modern_town")
	var ground := ProcgenSettlement.ground_of(ProcgenSettlement.kit_named("modern_town"))
	var pavement := _strokes(plan, "pavement")
	assert_eq(pavement.size(), 2, "one band each side of a straight street")
	var sides := {}
	for stroke in pavement:
		assert_eq(stroke["surface"], ground["door_path"], "the kit's kerb paving, no new slot")
		var from: Vector2 = stroke["from"]
		var to: Vector2 = stroke["to"]
		assert_almost_eq(from.y, to.y, 0.01, "along the street")
		var inner := absf(from.y) - float(stroke["radius"])
		var cover := absf(from.y) + float(stroke["radius"]) / SettlementGround.EDGE_REACH
		assert_almost_eq(inner, 4.3, 0.15, "its soft edge reaches the kerb")
		assert_gte(cover, 8.3, "its full cover reaches the facade")
		sides[signf(from.y)] = true
	assert_eq(sides.size(), 2, "both sides")
	var roles: Array[String] = plan["roles"]
	assert_lt(roles.find("road"), roles.find("pavement"), "the pavement paints over the road's edge")
	assert_eq(_strokes(plan, "door_path").size(), 0, "the pavement joins the doors; no road path")
	assert_false(plan["surfaces"].size() > 3, "still at most the kit's three surfaces")
	var lane := _plan(_doc_with_street(3, 3.0), "modern_town")
	assert_eq(_strokes(lane, "pavement").size(), 0, "a lane street gets no pavement band")
	assert_gt(_strokes(lane, "door_path").size(), 0, "and keeps its door paths")
