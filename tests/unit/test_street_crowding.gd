extends GutTest

## Streets whose houses would stand in each other's (StreetCrowding, card painter-roof-round4;
## docs/systems/walls.md): two lots of different rows that overlap crowd each other, a row drawn
## that close is refused by WallEditor.plan (REFUSED_CROWDED) with the Street tool's words, and a
## row drawn clear is not.


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
	assert_eq(
		WallBrush.refusal_text(WallEditor.REFUSED_CROWDED),
		WallBrush.CROWDED,
		"the readout's words for a crowded street"
	)
	assert_true(WallBrush.CROWDED.contains(":"), "what is wrong: what to do")
