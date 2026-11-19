extends GutTest

## Streets whose houses would stand in each other's (StreetCrowding, card painter-roof-round4;
## docs/systems/walls.md): two lots of different rows that overlap crowd each other; a new row
## drawn that close is nudged clear (StreetCrowding.nudge, card painter-roof-round5: square to the
## other street, away from it, no further than it must, the same every time), and refused with the
## Street tool's words where the nudge would meet another street, leave the map or carry it too far.


func _row(id: int, x: float) -> Wall:
	var wall := Wall.make(
		id, Wall.Kind.ROW, PackedVector2Array([Vector2(x, -12), Vector2(x, 12)]), false, 3.0
	)
	wall.preset = 3
	wall.seed_value = 5
	return wall


func _doc() -> MapDocument:
	StructureRecipes.ensure_served()
	return MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 1234)


func test_quads_overlap_by_more_than_the_margin() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var b := PackedVector2Array([Vector2(3, 1), Vector2(7, 1), Vector2(7, 5), Vector2(3, 5)])
	var touching := PackedVector2Array([Vector2(4, 0), Vector2(8, 0), Vector2(8, 4), Vector2(4, 4)])
	assert_true(StreetCrowding.quads_overlap(a, b, 0.1), "a metre deep")
	assert_false(StreetCrowding.quads_overlap(a, touching, 0.1), "backyards that only touch")
	assert_false(StreetCrowding.quads_overlap(a, b, 1.5), "less than the margin")


func test_a_street_drawn_into_anothers_houses_is_crowded() -> void:
	var doc := _doc()
	doc.walls.append(_row(1, -20.0))
	assert_false(StreetCrowding.quads(doc, doc.walls[0]).is_empty(), "the row stands lots")
	assert_eq(StreetCrowding.crowded_by(doc, _row(2, -12.0)), 1, "8 m away: houses in houses")
	assert_eq(StreetCrowding.crowded_by(doc, _row(2, 20.0)), -1, "40 m away: clear")
	assert_eq(StreetCrowding.crowded_by(doc, doc.walls[0]), -1, "a row never crowds itself")
	var across := Wall.make(
		4, Wall.Kind.ROW, PackedVector2Array([Vector2(-32, 0), Vector2(-8, 0)]), false, 3.0
	)
	assert_eq(StreetCrowding.crowded_by(doc, across), -1, "a crossroads is drawn on purpose")
	var fence := Wall.make(
		3, Wall.Kind.FENCE, PackedVector2Array([Vector2(4, -12), Vector2(4, 12)]), false, 1.0
	)
	assert_eq(StreetCrowding.crowded_by(doc, fence), -1, "only streets are asked")


func test_the_street_tool_says_why() -> void:
	var words := {
		WallEditor.REFUSED_CROWDED: WallBrush.CROWDED,
		WallEditor.REFUSED_CROWDED_EDGE: WallBrush.CROWDED_EDGE,
		WallEditor.REFUSED_CROWDED_WATER: WallBrush.CROWDED_WATER,
	}
	for reason: StringName in words:
		assert_eq(WallBrush.refusal_text(reason), words[reason], "the readout's words: %s" % reason)
		assert_true(String(words[reason]).contains(":"), "what is wrong: what to do")
	assert_eq(
		WallEditor.crowded_refusal(StreetCrowding.BLOCKED_EDGE), WallEditor.REFUSED_CROWDED_EDGE
	)
	assert_eq(
		WallEditor.crowded_refusal(StreetCrowding.BLOCKED_WATER), WallEditor.REFUSED_CROWDED_WATER
	)
	assert_eq(WallEditor.crowded_refusal(StreetCrowding.BLOCKED_STREET), WallEditor.REFUSED_CROWDED)


# --- the nudge (card painter-roof-round5) ------------------------------------------------


func test_a_crowded_street_is_nudged_just_clear_and_away() -> void:
	var doc := _doc()
	doc.walls.append(_row(1, -20.0))
	var drawn := _row(2, -8.0)
	assert_eq(StreetCrowding.crowded_by(doc, drawn), 1, "12 m away: houses in houses")
	var got := StreetCrowding.nudge(doc, drawn, doc.extent_m())
	assert_not_null(got["wall"], "nudged, not refused")
	assert_eq(got["from"], 1, "away from the street it crowded")
	var moved: Wall = got["wall"]
	var by: float = got["moved_m"]
	assert_gt(by, 0.0, "it moved")
	assert_lte(by, StreetCrowding.MAX_NUDGE_M, "a little")
	for k in moved.points.size():
		var shift := moved.points[k] - drawn.points[k]
		assert_almost_eq(shift.x, by, 1e-3, "square to the other street, away from it")
		assert_almost_eq(shift.y, 0.0, 1e-3, "the whole line, not a corner")
	assert_eq(StreetCrowding.crowded_by(doc, moved), -1, "clear where it lands")
	var short := StreetCrowding.shifted(drawn, Vector2(by - 0.3, 0.0))
	assert_eq(StreetCrowding.crowded_by(doc, short), 1, "no further than it must")
	assert_eq(drawn.points[0].x, -8.0, "the drawn line itself is unchanged")


func test_a_street_on_the_other_side_moves_the_other_way() -> void:
	var doc := _doc()
	doc.walls.append(_row(1, -4.0))
	var got := StreetCrowding.nudge(doc, _row(2, -16.0), doc.extent_m())
	assert_not_null(got["wall"])
	assert_lt((got["wall"] as Wall).points[0].x, -16.0, "west of the street, it moves west")


func test_the_nudge_is_deterministic() -> void:
	var doc := _doc()
	doc.walls.append(_row(1, -20.0))
	var a := StreetCrowding.nudge(doc, _row(2, -8.0), doc.extent_m())
	var b := StreetCrowding.nudge(doc, _row(2, -8.0), doc.extent_m())
	assert_eq(a["moved_m"], b["moved_m"], "the same distance")
	assert_eq((a["wall"] as Wall).points, (b["wall"] as Wall).points, "the same line")


func test_a_clear_or_crossing_street_is_not_moved() -> void:
	var doc := _doc()
	doc.walls.append(_row(1, -20.0))
	var clear := _row(2, 20.0)
	var got := StreetCrowding.nudge(doc, clear, doc.extent_m())
	assert_eq(got["wall"], clear, "clear: laid as drawn")
	assert_eq(got["moved_m"], 0.0)
	var across := Wall.make(
		2, Wall.Kind.ROW, PackedVector2Array([Vector2(-30, 0), Vector2(-8, 0)]), false, 3.0
	)
	assert_eq(StreetCrowding.nudge(doc, across, doc.extent_m())["wall"], across, "a crossroads")


func test_a_nudge_that_would_meet_another_street_is_refused() -> void:
	var doc := _doc()
	doc.walls.append(_row(1, -20.0))
	doc.walls.append(_row(3, 0.0))
	var got := StreetCrowding.nudge(doc, _row(2, -10.0), doc.extent_m())
	assert_null(got["wall"], "no room between them")
	assert_eq(got["blocked"], StreetCrowding.BLOCKED_STREET)


func test_a_nudge_off_the_map_is_refused() -> void:
	var doc := _doc()
	var edge := -doc.extent_m().x * 0.5
	doc.walls.append(_row(1, edge + 13.0))
	var got := StreetCrowding.nudge(doc, _row(2, edge + 1.0), doc.extent_m())
	assert_null(got["wall"], "the map ends there")
	assert_eq(got["blocked"], StreetCrowding.BLOCKED_EDGE)


func test_a_street_drawn_onto_another_is_refused_not_carried_off() -> void:
	var doc := _doc()
	doc.walls.append(_row(1, -20.0))
	var got := StreetCrowding.nudge(doc, _row(2, -19.0), doc.extent_m())
	assert_null(got["wall"], "a metre away is not a nudge")
	assert_eq(got["blocked"], StreetCrowding.BLOCKED_STREET)


func test_separation_is_the_least_shift_along_the_direction() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var b := PackedVector2Array([Vector2(3, 1), Vector2(7, 1), Vector2(7, 5), Vector2(3, 5)])
	assert_almost_eq(StreetCrowding.separation(a, b, Vector2.LEFT), 1.0, 1e-4, "1 m west")
	assert_almost_eq(StreetCrowding.separation(a, b, Vector2.UP), 3.0, 1e-4, "3 m north")
	assert_almost_eq(StreetCrowding.separation(b, a, Vector2.RIGHT), 1.0, 1e-4, "b 1 m east")
	var apart := PackedVector2Array([Vector2(9, 0), Vector2(10, 0), Vector2(10, 1), Vector2(9, 1)])
	assert_eq(StreetCrowding.separation(a, apart, Vector2.RIGHT), 0.0, "already apart")


func test_away_from_points_from_the_nearest_side() -> void:
	var bent := Wall.make(
		1,
		Wall.Kind.ROW,
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]),
		false,
		3.0
	)
	assert_eq(StreetCrowding.away_from(bent, Vector2(4, 3)), Vector2(0, 1), "above the first side")
	assert_eq(StreetCrowding.away_from(bent, Vector2(14, 8)), Vector2(1, 0), "beside the second")
