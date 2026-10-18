extends GutTest

## StrokePath (utils/stroke_path.gd): a drawn line's capture, lifted out of WaterBrush for every
## line shape (the river, Fire's Line, Start a fire's path). Decimation keeps points a spacing
## apart; the tip ends the line where the pointer was let go; smoothing keeps both ends;
## resampling spaces a line evenly within its point and spacing bounds; the cap cuts a line at
## a length; and WaterBrush's own names still answer the same.


func _line(coords: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c: Array in coords:
		out.append(Vector2(c[0], c[1]))
	return out


func test_decimation_keeps_points_a_spacing_apart() -> void:
	var line := PackedVector2Array()
	for k in 60:
		line = StrokePath.decimate(line, Vector2(k * 0.25, 0.0), StrokePath.DECIMATE_M)
	assert_eq(line[0], Vector2.ZERO, "the first point is always kept")
	for i in line.size() - 1:
		assert_gte(line[i].distance_to(line[i + 1]), StrokePath.DECIMATE_M - 1e-4)
	assert_eq(line.size(), 20, "every third quarter metre, the first 0.6 m on")


func test_the_tip_ends_the_line_where_it_was_let_go() -> void:
	var line := _line([[0, 0], [0.6, 0], [1.2, 0]])
	var far := StrokePath.with_tip(line, Vector2(1.7, 0), 0.6)
	assert_eq(far.size(), 4, "a tip past half the spacing is a point of its own")
	assert_eq(far[-1], Vector2(1.7, 0))
	var near := StrokePath.with_tip(line, Vector2(1.4, 0), 0.6)
	assert_eq(near.size(), 3, "a close tip replaces the last point")
	assert_eq(near[-1], Vector2(1.4, 0))
	assert_eq(StrokePath.with_tip(line, Vector2.INF, 0.6), line, "no tip: as recorded")


func test_smoothing_keeps_both_ends_and_shortens_corners() -> void:
	var zigzag := _line([[0, 0], [1, 1], [2, -1], [3, 1], [4, 0]])
	var smooth := StrokePath.smooth_line(zigzag)
	assert_eq(smooth[0], zigzag[0])
	assert_eq(smooth[-1], zigzag[-1])
	assert_gt(smooth.size(), zigzag.size())
	assert_lt(StrokePath.line_length(smooth), StrokePath.line_length(zigzag))
	assert_almost_eq(StrokePath.line_length(_line([[0, 0], [3, 4], [3, 5]])), 6.0, 1e-5)


func test_resampling_spaces_a_line_evenly() -> void:
	var bent := _line([[0, 0], [3, 0], [3, 4], [3.2, 4], [3.2, 9]])
	var total := StrokePath.line_length(bent)
	var even := StrokePath.resample(bent, 64, 1.0)
	assert_eq(even[0], bent[0], "the same start")
	assert_eq(even[-1], bent[-1], "and end")
	assert_eq(even.size(), floori(total / 1.0) + 1, "as many as fit at least 1 m apart")
	var step := total / float(even.size() - 1)
	assert_gte(step, 1.0 - 1e-5)
	# Every point lies `step` further along the line than the last.
	var along := _arc_positions(bent, even)
	for i in even.size():
		assert_almost_eq(along[i], step * i, 1e-3, "point %d evenly along" % i)


func test_resampling_respects_its_bounds() -> void:
	var long := _line([[0, 0], [100, 0]])
	assert_eq(StrokePath.resample(long, 64, 1.0).size(), 64, "at most max_points")
	assert_eq(StrokePath.resample(long, 64, 0.0).size(), 64, "no spacing floor: max_points")
	var short := _line([[0, 0], [0.4, 0]])
	assert_eq(StrokePath.resample(short, 64, 1.0), short, "shorter than a spacing: its two ends")
	var dot := _line([[2, 2]])
	assert_eq(StrokePath.resample(dot, 64, 1.0), dot, "one point comes back as it was")


func test_the_cap_cuts_a_line_at_a_length() -> void:
	var line := _line([[0, 0], [40, 0], [40, 40]])
	var cut := StrokePath.capped(line, StrokePath.MAX_LENGTH_M)
	assert_almost_eq(StrokePath.line_length(cut), StrokePath.MAX_LENGTH_M, 1e-4)
	assert_eq(cut.size(), 3)
	assert_almost_eq(cut[-1].y, 24.0, 1e-4, "the last point moved back onto the line")
	var short := _line([[0, 0], [10, 0]])
	assert_eq(StrokePath.capped(short, StrokePath.MAX_LENGTH_M), short, "a shorter line whole")
	assert_true(StrokePath.capped(PackedVector2Array(), 5.0).is_empty())


func test_water_brush_still_answers_with_the_same_capture() -> void:
	var zigzag := _line([[0, 0], [1, 1], [2, -1], [3, 1], [4, 0]])
	assert_eq(WaterBrush.smooth_line(zigzag), StrokePath.smooth_line(zigzag))
	assert_eq(WaterBrush.RIVER_DECIMATE_M, StrokePath.DECIMATE_M)
	assert_eq(WaterBrush.RIVER_MIN_LENGTH_M, StrokePath.MIN_LENGTH_M)
	var tip := WaterBrush.with_tip(zigzag, Vector2(5, 0), 0.6)
	assert_eq(tip, StrokePath.with_tip(zigzag, Vector2(5, 0), 0.6))


## Each of `points` (on `line`) as its distance along `line` from its start.
func _arc_positions(line: PackedVector2Array, points: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in points:
		var walked := 0.0
		var best := INF
		var at := 0.0
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var length := a.distance_to(b)
			var t := clampf((p - a).dot(b - a) / (length * length), 0.0, 1.0)
			var gap := p.distance_to(a.lerp(b, t))
			if gap < best:
				best = gap
				at = walked + t * length
			walked += length
		out.append(at)
	return out
