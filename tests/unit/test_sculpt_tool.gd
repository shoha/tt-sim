extends GutTest

## The Sculpt tool (phase 3, P3-5): the tier profile (HeightBrush.tier_goal: face, rounded
## lip, flat top exactly on a whole tier), how a Tier press picks its tier (up, down,
## continue, extend), tier strokes through HeightStroke and AuthoringEditor (exact tops, no
## climbing, undo and redo), the face being steep enough for the automatic cliff rule at the
## default sample spacing, the tool's pure input rules (tiles, Ctrl and Shift, readout), the
## Sculpt rail item disabled on a dressed map, and the brush ring's fill that never needs
## triangulating.

const GRASS := "grass"
const EPSILON := 1e-5


## A 150 ft map at the default 0.25 m spacing.
func _doc() -> MapDocument:
	return MapDocument.create_flat(Vector2i(30, 30), GRASS, "test", 5)


## `value` as the document stores it (float32).
func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


func _index(doc: MapDocument, p: Vector2) -> int:
	var s := doc.world_to_sample(p).round()
	return doc.sample_index(int(s.x), int(s.y))


func _height(doc: MapDocument, p: Vector2) -> float:
	return doc.heights[_index(doc, p)]


## A tier stroke along `points` (document XZ), `frames` frames of 1/20 s each, completed.
func _tier(
	doc: MapDocument, op: int, target: float, points: Array, radius: float, frames: int = 4
) -> HeightStroke:
	var stroke := HeightStroke.begin(doc, op, target)
	for _frame in frames:
		if points.size() == 1:
			stroke.dab(points[0], points[0], radius, 0.05)
		for k in range(1, points.size()):
			stroke.dab(points[k - 1], points[k], radius, 0.05)
	stroke.complete()
	return stroke


func _max_height(doc: MapDocument) -> float:
	var top := -INF
	for h in doc.heights:
		top = maxf(top, h)
	return top


func _min_height(doc: MapDocument) -> float:
	var bottom := INF
	for h in doc.heights:
		bottom = minf(bottom, h)
	return bottom


# --- The tier profile ----------------------------------------------------------------


## Steepest slope (degrees) of tier_goal(start, target, inset) over insets 0..`span` in
## 1 cm steps.
func _steepest(start: float, target: float, span: float) -> float:
	var steepest := 0.0
	var last := start
	for i in range(1, int(span * 100.0) + 1):
		var h := HeightBrush.tier_goal(start, target, i * 0.01)
		steepest = maxf(steepest, absf(h - last) / 0.01)
		last = h
	return rad_to_deg(atan(steepest))


func test_tier_goal_raises_a_face_a_rounded_lip_then_a_flat_top() -> void:
	var tier_m := 1.524
	var span := HeightBrush.tier_span(tier_m)
	assert_eq(HeightBrush.tier_goal(0.0, tier_m, 0.0), 0.0, "the ring's edge is the foot")
	assert_eq(HeightBrush.tier_goal(0.0, tier_m, -1.0), 0.0, "outside the ring")
	assert_eq(HeightBrush.tier_goal(0.0, tier_m, span), tier_m, "the top, exactly")
	assert_eq(HeightBrush.tier_goal(0.0, tier_m, 10.0), tier_m)
	assert_lt(HeightBrush.tier_goal(0.0, tier_m, span - 0.05), tier_m, "the lip rounds up to it")
	assert_lt(HeightBrush.tier_goal(0.0, tier_m, 0.05), 0.01, "the foot eases out of the ground")
	# Monotonic and smooth (no kink: neighbouring 1 cm slopes differ little), rising steeply
	# in the middle, and a convex shoulder at the top: the slope falls toward the top.
	var last := 0.0
	var last_slope := 0.0
	var steepest_at := 0.0
	var steepest := 0.0
	var step := 0.01
	for i in range(1, int(span / step) + 10):
		var inset := i * step
		var h := HeightBrush.tier_goal(0.0, tier_m, inset)
		assert_true(h >= last - 1e-9, "never falls inward")
		var slope := (h - last) / step
		assert_lt(absf(slope - last_slope), 0.2, "no kink at %.2f m" % inset)
		if slope > steepest:
			steepest = slope
			steepest_at = inset
		elif inset > steepest_at + 0.3 and inset < span:
			assert_true(slope <= last_slope + 1e-6, "the lip rounds over at %.2f m" % inset)
		last = h
		last_slope = slope
	assert_between(rad_to_deg(atan(steepest)), 62.0, 70.0, "a steep face")


func test_tier_goal_cuts_with_the_lip_on_the_rim() -> void:
	var tier_m := 1.524
	var span := HeightBrush.tier_span(tier_m)
	assert_eq(HeightBrush.tier_goal(0.0, -tier_m, 0.0), 0.0)
	assert_eq(HeightBrush.tier_goal(0.0, -tier_m, span), -tier_m, "the floor, exactly")
	# The mirror of the raise: the rim rounds down where the raise's top rounds up.
	for i in range(0, int(span * 100.0) + 1):
		var inset := i * 0.01
		assert_almost_eq(
			HeightBrush.tier_goal(0.0, -tier_m, inset),
			HeightBrush.tier_goal(0.0, tier_m, span - inset) - tier_m,
			1e-9,
			"mirrored at %.2f m" % inset
		)
	var last := 0.0
	for i in range(1, 300):
		var h := HeightBrush.tier_goal(0.0, -tier_m, i * 0.01)
		assert_true(h <= last + 1e-9, "never rises inward")
		last = h


func test_a_small_rise_keeps_its_lip_in_proportion() -> void:
	# Extending over an old lip: the new lip is at most TIER_LIP_SHARE of the rise, and the
	# small step still ends exactly on the tier.
	var start := 1.4
	var span := HeightBrush.tier_span(1.524 - start)
	assert_eq(HeightBrush.tier_goal(start, 1.524, span), 1.524)
	assert_lt(_steepest(start, 1.524, span), 30.0, "a gentle step, not a wall")
	var last := start
	for i in range(1, int(span * 100.0)):
		var h := HeightBrush.tier_goal(start, 1.524, i * 0.01)
		assert_true(h >= last - 1e-9 and h <= 1.524, "between the two levels")
		last = h


func test_tier_face_is_steeper_than_the_full_rock_slope() -> void:
	var tier_m := 1.524
	var angle := _steepest(0.0, tier_m, HeightBrush.tier_span(tier_m))
	assert_gt(angle, TerrainRules.CLIFF_END_DEG + 3.0, "a cliff face")


func test_diagonal_tier_faces_do_not_saw() -> void:
	# The sample grid draws each quad as two triangles on a fixed diagonal. A straight tier
	# face at any angle must come out as a straight face on that mesh: along every line
	# parallel to it, the drawn height may vary by only a few centimetres (the sharp profile
	# left teeth up to 0.25 m deep; see HeightBrush's header).
	for degrees in [0.0, 10.0, 22.5, 30.0, 45.0, 60.0, -15.0, -30.0, -45.0, -60.0]:
		var doc := _doc()
		var t := doc.tier_height_m
		var along := Vector2.from_angle(deg_to_rad(degrees))
		var across := Vector2(-along.y, along.x)
		var stroke := HeightStroke.begin(doc, HeightBrush.TIER, t)
		stroke.dab(-along * 12.0, along * 12.0, 3.0, 0.05)
		stroke.complete()
		var worst := 0.0
		var edge := 3.0 + HeightBrush.TIER_SOFTEN_M
		var offset := edge - HeightBrush.tier_span(t) - 0.2
		while offset < edge + 0.2:
			var low := INF
			var high := -INF
			for k in 121:
				var p := across * offset + along * (-3.0 + k * 0.05)
				var h := ScatterGenerator.triangle_height(
					doc.heights, doc.samples_x(), doc.samples_z(), doc.world_to_sample(p)
				)
				low = minf(low, h)
				high = maxf(high, h)
			worst = maxf(worst, high - low)
			offset += 0.05
		assert_lt(worst, 0.08, "face at %s deg: teeth %.3f m" % [degrees, worst])


# --- Choosing the tier ---------------------------------------------------------------


func test_tier_target_steps_up_from_ground_and_between_tiers() -> void:
	var t := 1.524
	assert_eq(HeightBrush.tier_target_level(0.0, t, false, false, false), 1, "flat ground: up one")
	assert_eq(HeightBrush.tier_target_level(0.7, t, false, false, false), 1, "a slope: next up")
	assert_eq(HeightBrush.tier_target_level(1.4, t, false, false, false), 1, "a lip: that tier")
	assert_eq(HeightBrush.tier_target_level(2.0, t, false, false, true), 2)


func test_tier_target_continues_a_top_toward_lower_ground_and_steps_up_inside_it() -> void:
	var t := 1.524
	assert_eq(HeightBrush.tier_target_level(t, t, false, true, false), 1, "extend from the edge")
	assert_eq(HeightBrush.tier_target_level(t, t, false, false, false), 2, "step up inside")
	assert_eq(
		HeightBrush.tier_target_level(t + 0.03, t, false, false, false), 2, "within tolerance"
	)
	assert_eq(HeightBrush.tier_target_level(0.0, t, false, false, true), 1, "beside a tier: raise")


func test_tier_target_down_steps_down_and_cuts_higher_ground_to_the_press_level() -> void:
	var t := 1.524
	assert_eq(HeightBrush.tier_target_level(0.0, t, true, false, false), -1, "sink a level")
	assert_eq(HeightBrush.tier_target_level(t, t, true, false, false), 0, "a top steps down one")
	assert_eq(HeightBrush.tier_target_level(0.0, t, true, false, true), 0, "cut a tier to here")
	assert_eq(HeightBrush.tier_target_level(0.7, t, true, false, false), 0, "a slope: tier below")
	assert_eq(HeightBrush.tier_target_level(-t, t, true, true, false), -2)


func test_tier_neighbours_see_clearly_lower_or_higher_ground_only() -> void:
	var doc := _doc()
	var t := doc.tier_height_m
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x > 0.0:
				doc.heights[doc.sample_index(x, z)] = t
	assert_eq(HeightBrush.tier_neighbours(doc, Vector2(-1, 0), 2.0, 0.0, t), Vector2i(0, 1))
	assert_eq(HeightBrush.tier_neighbours(doc, Vector2(-4, 0), 2.0, 0.0, t), Vector2i.ZERO)
	assert_eq(HeightBrush.tier_neighbours(doc, Vector2(4, 0), 2.0, t, t), Vector2i.ZERO)
	assert_eq(HeightBrush.tier_neighbours(doc, Vector2(1, 0), 2.0, t, t), Vector2i(1, 0))
	# A lip a little below the top does not count as lower ground.
	doc.heights[_index(doc, Vector2(3, 0))] = t - HeightBrush.TIER_LIP_M
	assert_eq(HeightBrush.tier_neighbours(doc, Vector2(4, 0), 2.0, t, t), Vector2i.ZERO)


# --- Tier strokes --------------------------------------------------------------------


func test_tier_tops_end_exactly_on_whole_tiers() -> void:
	var doc := _doc()
	var t := doc.tier_height_m
	_tier(doc, HeightBrush.TIER, t, [Vector2(-3, 0), Vector2(3, 0)], 4.0, 2)
	assert_eq(_height(doc, Vector2.ZERO), _f32(t), "a quick stroke still ends on the tier")
	assert_eq(_max_height(doc), _f32(t), "nothing above it")
	assert_eq(_height(doc, Vector2(0, 5)), 0.0, "outside the ring untouched")
	_tier(doc, HeightBrush.TIER, 2.0 * t, [Vector2(0, 0)], 1.8)
	assert_eq(_height(doc, Vector2.ZERO), _f32(2.0 * t), "the second tier")
	var cut := _doc()
	_tier(cut, HeightBrush.TIER_CUT, -t, [Vector2(0, 0), Vector2(0, 4)], 3.0)
	assert_eq(_height(cut, Vector2(0, 2)), _f32(-t), "a sunken tier")
	assert_eq(_min_height(cut), _f32(-t))


func test_repeated_strokes_extend_the_level_without_climbing() -> void:
	var doc := _doc()
	var t := doc.tier_height_m
	_tier(doc, HeightBrush.TIER, t, [Vector2(-6, 0), Vector2(0, 0)], 3.0)
	# The same target again (a stroke from the ground next to it, or from its edge).
	_tier(doc, HeightBrush.TIER, t, [Vector2(-2, 0), Vector2(6, 0)], 3.0, 20)
	assert_eq(_max_height(doc), _f32(t), "the target stays the tier")
	for x in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		assert_eq(_height(doc, Vector2(x, 0)), _f32(t), "flat along the whole top at %s" % x)


func test_a_raising_tier_never_cuts_and_a_cut_never_raises() -> void:
	var doc := _doc()
	var t := doc.tier_height_m
	_tier(doc, HeightBrush.TIER, 2.0 * t, [Vector2(0, 0)], 2.0)
	_tier(doc, HeightBrush.TIER, t, [Vector2(-3, 0), Vector2(3, 0)], 4.0)
	assert_eq(_height(doc, Vector2.ZERO), _f32(2.0 * t), "higher ground left standing")
	_tier(doc, HeightBrush.TIER_CUT, 0.0, [Vector2(8, 8)], 2.0)
	assert_eq(_height(doc, Vector2(8, 8)), 0.0, "ground at the target is not raised")


func test_tier_stroke_matches_tier_goal() -> void:
	# The dab inlines tier_goal(); run a held stroke to rest and compare every sample.
	for op in [HeightBrush.TIER, HeightBrush.TIER_CUT]:
		var doc := _doc()
		var t := doc.tier_height_m * (1.0 if op == HeightBrush.TIER else -1.0)
		var centre := Vector2(0.3, -0.2)
		var radius := 3.3
		var stroke := HeightStroke.begin(doc, op, t)
		for _frame in 200:
			stroke.dab(centre, centre, radius, 0.05)
		var at_rest := doc.heights.duplicate()
		var worst := 0.0
		for z in doc.samples_z():
			for x in doc.samples_x():
				var d := doc.sample_to_world(Vector2(x, z)).distance_to(centre)
				var expected := HeightBrush.tier_goal(
					0.0, t, radius + HeightBrush.TIER_SOFTEN_M - d
				)
				worst = maxf(worst, absf(doc.heights[doc.sample_index(x, z)] - expected))
		assert_lt(worst, 1e-5, "op %d at rest on the profile" % op)
		stroke.complete()
		assert_true(doc.heights == at_rest, "complete() has nothing left to do")


func test_tier_face_is_rock_at_the_default_spacing() -> void:
	var doc := _doc()
	var t := doc.tier_height_m
	_tier(doc, HeightBrush.TIER, t, [Vector2.ZERO], 4.0)
	assert_almost_eq(doc.sample_step().x, MapDocument.DEFAULT_SAMPLE_SPACING_M, 0.01)
	# Across the face in several directions (on and off the grid axes): the shading normal
	# (central differences, what the ground shader and TerrainRules read) makes the face full
	# rock even where the edge noise pulls hardest the other way (noise 0), and the top and
	# the ground beyond are flat.
	for degrees in [0.0, 22.5, 45.0, 60.0, 90.0]:
		var direction := Vector2.from_angle(deg_to_rad(degrees))
		var lowest_ny := 1.0
		var r := 2.5
		while r < 5.0:
			var s := doc.world_to_sample(direction * r).round()
			var normal := TerrainMeshBuilder.sample_normal(doc, int(s.x), int(s.y))
			lowest_ny = minf(lowest_ny, normal.y)
			r += 0.05
		assert_gt(TerrainRules.cliff_from(lowest_ny, 0.0, 0.0), 0.999, "face at %s deg" % degrees)
	var centre := doc.world_to_sample(Vector2(0.5, 0.5)).round()
	var top := TerrainMeshBuilder.sample_normal(doc, int(centre.x), int(centre.y))
	assert_almost_eq(top.y, 1.0, EPSILON, "a flat top")


func test_an_editor_tier_stroke_is_one_undoable_step_on_a_whole_tier() -> void:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	var doc := _doc()
	map.add_child(AuthoredTerrain.create(doc))
	var history := AuthoringHistory.new()
	var editor := AuthoringEditor.create(doc, map, history)
	var start := doc.heights.duplicate()
	var target := editor.tier_target(Vector3.ZERO, 4.0, false)
	assert_eq(int(target.level), 1, "the first stroke on flat ground is tier 1")
	assert_true(editor.begin_height_stroke(HeightBrush.TIER, float(target.y)))
	editor.stroke_dab(Vector3(-3, 0, 0), Vector3(3, 0, 0), 4.0, 0.05)
	editor.flush()
	assert_true(editor.end_stroke())
	var built := doc.heights.duplicate()
	assert_eq(_height(doc, Vector2.ZERO), _f32(doc.tier_height_m))
	assert_eq(history.undo_count(), 1)
	# On the new top, a small brush steps up; at its edge it extends the level.
	assert_eq(int(editor.tier_target(Vector3(0, 0, 0), 1.0, false).level), 2)
	assert_eq(int(editor.tier_target(Vector3(5, 0, 0), 2.5, false).level), 1, "extend")
	assert_eq(int(editor.tier_target(Vector3(0, 0, 0), 1.0, true).level), 0, "Ctrl steps down")
	history.undo()
	assert_true(doc.heights == start, "undo")
	history.redo()
	assert_true(doc.heights == built, "redo")


# --- The tool's input rules ----------------------------------------------------------


func test_sculpt_op_follows_the_tile_and_the_press_modifiers() -> void:
	var raise := HeightBrush.RAISE
	assert_eq(BrushTool.sculpt_op(raise, false, false), HeightBrush.RAISE)
	assert_eq(BrushTool.sculpt_op(raise, true, false), HeightBrush.LOWER, "Ctrl lowers")
	assert_eq(BrushTool.sculpt_op(HeightBrush.TIER, false, false), HeightBrush.TIER)
	assert_eq(BrushTool.sculpt_op(HeightBrush.TIER, true, false), HeightBrush.TIER_CUT)
	assert_eq(BrushTool.sculpt_op(HeightBrush.FLATTEN, true, false), HeightBrush.FLATTEN)
	assert_eq(BrushTool.sculpt_op(HeightBrush.SMOOTH, true, false), HeightBrush.SMOOTH)
	for tile in [raise, HeightBrush.FLATTEN, HeightBrush.TIER]:
		for ctrl in [false, true]:
			assert_eq(BrushTool.sculpt_op(tile, ctrl, true), HeightBrush.SMOOTH, "Shift smooths")


func test_sculpt_presses_are_brush_strokes() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var mode := BrushTool.Mode.SCULPT
	assert_eq(BrushTool.decide(press, mode, false, false), BrushTool.Action.BEGIN)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	assert_eq(BrushTool.decide(rmb, mode, true, false), BrushTool.Action.CANCEL, "RMB cancels")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.shift_pressed = true
	assert_eq(BrushTool.decide(wheel, mode, false, false), BrushTool.Action.GROW, "size")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	assert_eq(BrushTool.decide(escape, mode, true, false), BrushTool.Action.CANCEL, "held")
	assert_eq(
		BrushTool.decide(escape, mode, false, false), BrushTool.Action.NONE, "idle: the drawer's"
	)


func test_the_readout_names_the_tier_and_its_elevation() -> void:
	var cell := LevelData.DEFAULT_GRID_CELL_SIZE
	var per := LevelData.DEFAULT_DISPLAY_UNIT_PER_CELL
	assert_eq(BrushTool.tier_readout(1, 1.524, cell, per, "ft"), "Tier 1  +5 ft")
	assert_eq(BrushTool.tier_readout(2, 3.048, cell, per, "ft"), "Tier 2  +10 ft")
	assert_eq(BrushTool.tier_readout(-1, -1.524, cell, per, "ft"), "Tier -1  -5 ft")
	assert_eq(BrushTool.tier_readout(0, 0.0, cell, per, "ft"), "Ground  0 ft")
	assert_eq(BrushTool.format_elevation(2.3, cell, per, "ft"), "+8 ft")
	assert_eq(BrushTool.format_elevation(1.524, 1.0, 1.0, "m"), "+2 m")


func test_sculpt_tiles_round_trip_their_operations() -> void:
	assert_eq(AuthoringPanel.SCULPT_TILES.size(), 4)
	for tile in AuthoringPanel.SCULPT_TILES:
		var op := int(tile.op)
		assert_eq(AuthoringPanel.sculpt_tile_op(AuthoringPanel.sculpt_tile_id(op)), op)
	assert_eq(AuthoringPanel.sculpt_tile_id(HeightBrush.TIER), &"sculpt_tier")
	assert_eq(AuthoringPanel.sculpt_tile_op(&"nothing"), -1)


func test_the_sculpt_rail_item_is_disabled_with_a_reason_on_a_dressed_map() -> void:
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	var rail: IconRail = panel.get("_rail")
	var buttons: Dictionary = rail.get("_buttons")
	var item: Button = buttons[AuthoringPanel.TOOL_SCULPT]
	assert_false(item.disabled, "available by default")
	panel.set_sculpt_available(false)
	assert_true(item.disabled)
	assert_eq(item.tooltip_text, AuthoringPanel.SCULPT_UNAVAILABLE_TOOLTIP, "says why")
	panel.set_sculpt_available(true)
	assert_false(item.disabled)
	assert_eq(item.tooltip_text, AuthoringPanel.SCULPT_TOOLTIP)


# --- The ring's fill -----------------------------------------------------------------


func test_the_ring_fill_needs_no_triangulation() -> void:
	# The cause of "Invalid polygon data, triangulation failed": a ring conformed over
	# raised ground projects to an outline that crosses itself, which the canvas's
	# triangulator (draw_colored_polygon) rejects. The fan is drawn with explicit indices.
	var ring := PackedVector2Array()
	for i in BrushTool.RING_SEGMENTS + 1:
		var angle := TAU * float(i % BrushTool.RING_SEGMENTS) / float(BrushTool.RING_SEGMENTS)
		var r := 100.0 if absf(sin(angle * 3.0)) <= 0.8 else -40.0
		ring.append(Vector2(cos(angle), sin(angle) * 0.6) * r)
	assert_true(Geometry2D.triangulate_polygon(ring).is_empty(), "the old fill failed here")
	var indices := BrushTool.fan_indices(ring.size())
	assert_eq(indices.size(), 3 * (ring.size() - 1))
	var centre_uses := 0
	for index in indices:
		assert_between(index, 0, ring.size())
		if index == ring.size():
			centre_uses += 1
	assert_eq(centre_uses, ring.size() - 1, "every triangle meets the centre")
