extends GutTest

## ScrollFade never dims a row in full view: its ramp starts at the top of the row the bottom
## edge cuts, or the bottom of the last whole row when the edge falls between rows, and is
## never taller than HEIGHT (a half-faded whole row read as a disabled one in Settings >
## Controls).


func test_the_ramp_starts_at_the_cut_row() -> void:
	# Rows 40 tall with 8 between: the edge at 200 cuts the row at 192-232.
	var spans: Array[Vector2] = [Vector2(0, 40), Vector2(48, 88), Vector2(144, 184), Vector2(192, 232)]
	assert_eq(ScrollFade.fade_top(spans, 200.0), 192.0)


func test_an_edge_between_rows_fades_only_the_gap() -> void:
	var spans: Array[Vector2] = [Vector2(144, 184), Vector2(192, 232)]
	assert_eq(ScrollFade.fade_top(spans, 188.0), 184.0, "the last whole row stays whole")


func test_a_tall_cut_row_fades_over_height_at_most() -> void:
	var spans: Array[Vector2] = [Vector2(100, 300)]
	assert_eq(ScrollFade.fade_top(spans, 200.0), 200.0 - ScrollFade.HEIGHT)


func test_a_section_around_its_rows_gives_way_to_the_innermost_row() -> void:
	# A section box spans the edge from far above; its own row is the one cut.
	var spans: Array[Vector2] = [Vector2(20, 400), Vector2(150, 190), Vector2(196, 236)]
	assert_eq(ScrollFade.fade_top(spans, 210.0), 196.0)
