extends GutTest

## GroundClipmapPlan (card clipmap1): the pure geometry of the ground clipmap's levels, blocks
## and strips. The shader and the bake are checked in a render job (docs/systems/ground_clipmap.md).

const Plan := preload("res://utils/ground_clipmap_plan.gd")


func test_levels_halve_density_and_double_extent() -> void:
	assert_eq(Plan.density(0), 200.0)
	assert_eq(Plan.density(2), 50.0)
	assert_almost_eq(Plan.extent_m(0), 10.24, 1e-4)
	assert_almost_eq(Plan.extent_m(3), 81.92, 1e-4)
	assert_almost_eq(Plan.tile_m(1), 2.56, 1e-4)


func test_top_level_is_the_first_to_hold_the_map_with_a_tile_to_spare() -> void:
	assert_eq(Plan.top_level(30.48), 2, "a 100 ft map: 41 m holds 30.5 + 5.1")
	assert_eq(Plan.top_level(60.96), 3, "a 200 ft map: 82 m")
	assert_eq(Plan.top_level(97.5), 4, "a 320 ft map: 164 m")
	assert_eq(Plan.top_level(400.0), Plan.CLIP_LEVELS - 1, "a huge map keeps the last level")
	assert_true(Plan.is_static(3, 60.96))
	assert_false(Plan.is_static(2, 60.96))


func test_finest_level_follows_the_screen_density() -> void:
	assert_eq(Plan.finest_level(78.0, 3), 1, "home: 78 px/m, level 1 (100 px/m)")
	assert_eq(Plan.finest_level(270.0, 3), 0, "zoom 4")
	assert_eq(Plan.finest_level(135.0, 3), 0, "zoom 8: level 0 still the sharper")
	assert_eq(Plan.finest_level(54.0, 3), 1, "zoom 20 on a 61 m map: level 1 (100 > 54)")
	assert_eq(Plan.finest_level(5.0, 3), 3, "far out: capped at the top")
	assert_eq(Plan.finest_level(0.0, 3), 3)


func test_target_block_centres_on_the_focus_and_holds_still() -> void:
	var block := Plan.target_block(1, Vector2(10.0, -5.0), Rect2i())
	assert_eq(block.size, Vector2i(8, 8))
	var ts := Plan.tile_m(1)
	assert_eq(block.position, Vector2i(int(round(10.0 / ts)) - 4, int(round(-5.0 / ts)) - 4))
	var nudged := Plan.target_block(1, Vector2(10.0 + ts * 0.6, -5.0), block)
	assert_eq(nudged, block, "within the hysteresis the block stays")
	var moved := Plan.target_block(1, Vector2(10.0 + ts * 1.2, -5.0), block)
	assert_eq(moved.position.x, block.position.x + 1)


func test_jobs_fill_the_block_one_strip_at_a_time() -> void:
	var target := Rect2i(10, -3, 8, 8)
	var valid := Rect2i()
	var strips := 0
	while true:
		var job := Plan.next_job(valid, target)
		if job.is_empty():
			break
		strips += 1
		valid = Plan.clip_valid(job.after, target)
		assert_true(strips <= 16, "a block of 8 x 8 fills in 8 columns")
	assert_eq(valid, target)
	assert_eq(strips, 8, "the first column spans the block's height, so 8 columns fill it")


func test_a_pan_costs_one_strip_per_tile_crossed() -> void:
	var target := Rect2i(10, -3, 8, 8)
	var valid := target
	var moved := Rect2i(11, -3, 8, 8)
	valid = Plan.clip_valid(valid, moved)
	assert_eq(valid, Rect2i(11, -3, 7, 8))
	var job := Plan.next_job(valid, moved)
	assert_eq(job.kind, Plan.Kind.COLUMN)
	assert_eq(job.tile, 18, "the column entering on the right")
	assert_eq(Plan.clip_valid(job.after, moved), moved)
	assert_true(Plan.next_job(job.after, moved).is_empty())
	var diagonal := Rect2i(11, -2, 8, 8)
	valid = Plan.clip_valid(valid, diagonal)
	assert_eq(valid, Rect2i(11, -2, 7, 7))
	var j1 := Plan.next_job(valid, diagonal)
	var j2 := Plan.next_job(j1.after, diagonal)
	assert_eq([j1.kind, j2.kind], [Plan.Kind.COLUMN, Plan.Kind.ROW], "columns, then rows")
	assert_eq(Plan.clip_valid(j2.after, diagonal), diagonal)


func test_a_jump_empties_the_valid_rectangle() -> void:
	var cut := Plan.clip_valid(Rect2i(0, 0, 8, 8), Rect2i(40, 40, 8, 8))
	assert_eq(cut.size, Vector2i.ZERO)
	var job := Plan.next_job(cut, Rect2i(40, 40, 8, 8))
	assert_eq(job.after, Rect2i(44, 40, 1, 8), "restarts from the block's middle column")


func test_blits_split_a_strip_where_it_wraps_the_torus() -> void:
	var whole := Plan.blits(Plan.Kind.COLUMN, 3, 8)
	assert_eq(whole.size(), 1, "span starting on a multiple of 8 does not wrap")
	assert_eq(whole[0].dst, Vector2i(3 * Plan.TILE_PX, 0))
	assert_eq(whole[0].src, Rect2i(0, 0, Plan.TILE_PX, Plan.WINDOW_PX))
	var wrapped := Plan.blits(Plan.Kind.COLUMN, -1, -3)
	assert_eq(wrapped.size(), 2)
	var rows := 0
	for piece: Dictionary in wrapped:
		rows += piece.src.size.y
		assert_eq(piece.dst.x, 7 * Plan.TILE_PX, "tile -1 sits in slot 7")
	assert_eq(rows, Plan.WINDOW_PX, "the pieces cover the whole strip")
	assert_eq(wrapped[0].dst.y, 5 * Plan.TILE_PX, "tile -3 is slot 5")
	assert_eq(wrapped[1].dst.y, 0)
	var row := Plan.blits(Plan.Kind.ROW, 2, 6)
	assert_eq(row.size(), 2)
	assert_eq(row[0].dst, Vector2i(6 * Plan.TILE_PX, 2 * Plan.TILE_PX))
	assert_eq(row[1].dst, Vector2i(0, 2 * Plan.TILE_PX))


func test_strip_rect_is_one_tile_by_eight() -> void:
	var col := Plan.strip_rect(1, Plan.Kind.COLUMN, 3, -2)
	var ts := Plan.tile_m(1)
	assert_eq(col.position, Vector2(3.0, -2.0) * ts)
	assert_eq(col.size, Vector2(1.0, 8.0) * ts)
	var row := Plan.strip_rect(1, Plan.Kind.ROW, 3, -2)
	assert_eq(row.position, Vector2(-2.0, 3.0) * ts)
	assert_eq(row.size, Vector2(8.0, 1.0) * ts)


func test_valid_rect_in_metres_is_cut_to_the_map() -> void:
	var empty := Plan.valid_rect_m(1, Rect2i(), Rect2())
	assert_gt(empty.x, empty.z, "empty: min above max")
	var ts := Plan.tile_m(2)
	var bounds := Rect2(-15.0, -15.0, 30.0, 30.0)
	var v := Plan.valid_rect_m(2, Rect2i(-4, -4, 8, 8), bounds)
	assert_eq(v, Vector4(-15.0, -15.0, 15.0, 15.0), "a static level's block is cut to the map")
	var free := Plan.valid_rect_m(2, Rect2i(-4, -4, 8, 8), Rect2())
	assert_eq(free, Vector4(-4.0 * ts, -4.0 * ts, 4.0 * ts, 4.0 * ts))
