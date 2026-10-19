extends GutTest

## The Fire tool's Line shape (FireBrush, card F5): a drawn line laid on release as even capsule
## dabs through AuthoringEditor.begin_fire_stroke. The same line captured at two spacings (a
## slow hand and a fast one) lays the same mask along its centre; a Ctrl line puts fire out
## along it and keeps the ash; a lay is one "Lay fire" entry whose one undo puts every layer
## back byte for byte; a release under 2 m lays nothing; and the brush's own press, frames and
## release draw and lay a line, Esc dropping it. Card F5b: a Ctrl line's chip names its length;
## the Line's ring and ribbon are the band its fire stands in (line_reach). The ribbon and the
## gesture the Line shares with the river are test_line_tool.gd's (card F5e).

const MEADOW := "grassland_meadow_summer_s1"
const RADIUS := 2.0
## The arc every test draws: a circle's top, about 15 m long across the map's middle.
const ARC_CENTRE := Vector2(0.0, -10.0)
const ARC_RADIUS := 12.0
const ARC_FROM := deg_to_rad(130.0)
const ARC_TO := deg_to_rad(50.0)


func _editor(meadow := false) -> AuthoringEditor:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_birch", "v", 11)
	var root := MapSourceLoader.create_authored_root(doc)
	MapSourceLoader.add_fire_field(root, doc)
	add_child_autofree(root)
	var editor := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	if meadow:
		assert_true(editor.begin_stroke(MaskBrush.PAINT, MEADOW))
		for z in range(-8, 9):
			editor.stroke_dab(Vector3(-9, 0, z), Vector3(9, 0, z), 2.0, 3.0)
		editor.end_stroke()
	return editor


## The arc at arc length `s` from its start.
func _arc_at(s: float) -> Vector2:
	var angle := ARC_FROM - s / ARC_RADIUS
	return ARC_CENTRE + Vector2(cos(angle), sin(angle)) * ARC_RADIUS


func _arc_length() -> float:
	return (ARC_FROM - ARC_TO) * ARC_RADIUS


## The arc as a hand draws it: the pointer's ground point every `frame_m` metres (a frame's
## travel), decimated as a line is, ended at the release point and smoothed.
func _captured(frame_m: float) -> PackedVector2Array:
	var line := PackedVector2Array()
	var s := 0.0
	while s < _arc_length():
		line = StrokePath.decimate(line, _arc_at(s), StrokePath.DECIMATE_M)
		s += frame_m
	var tip := _arc_at(_arc_length())
	return StrokePath.smooth_line(StrokePath.with_tip(line, tip, StrokePath.DECIMATE_M))


func _fire_at(editor: AuthoringEditor, xz: Vector2) -> int:
	var doc := editor.document
	if doc.fire_mask.size() != doc.sample_count():
		return 0
	var s := Vector2i(doc.world_to_sample(editor.to_map_xz(Vector3(xz.x, 0, xz.y))).round())
	return doc.fire_mask[doc.sample_index(s.x, s.y)]


## The mask along the arc's centre, every half metre over its middle (the ends taper).
func _centre(editor: AuthoringEditor) -> PackedInt32Array:
	var out := PackedInt32Array()
	var s := _arc_length() * 0.2
	while s <= _arc_length() * 0.8:
		out.append(_fire_at(editor, _arc_at(s)))
		s += 0.5
	return out


func _layers(doc: MapDocument) -> Array:
	return [
		doc.fire_mask.duplicate(),
		doc.biome_slots.duplicate(),
		doc.biome_density.duplicate(),
		doc.surface_ids.duplicate(),
		doc.surface_weights.duplicate(),
		doc.erase_mask.duplicate(),
	]


func test_a_line_lays_the_same_whatever_the_drawing_speed() -> void:
	var slow := _editor()
	var fast := _editor()
	var fine := _captured(0.05)
	var coarse := _captured(2.0)
	assert_gt(fine.size(), coarse.size() * 2, "the slow hand recorded many more points")
	assert_true(FireBrush.lay_line(slow, fine, RADIUS, 1.0, false))
	assert_true(FireBrush.lay_line(fast, coarse, RADIUS, 1.0, false))
	var a := _centre(slow)
	var b := _centre(fast)
	assert_gt(a.size(), 10)
	for i in a.size():
		assert_almost_eq(a[i], b[i], 2, "centre point %d: the same mask at either speed" % i)
		assert_gt(a[i], 230, "the centre burns close to the intensity")
	assert_lte(_spread(a), 3, "and evenly along the line")


func test_a_ctrl_line_puts_fire_out_along_it_and_keeps_the_ash() -> void:
	var editor := _editor()
	var doc := editor.document
	assert_true(FireBrush.lay_line(editor, _captured(0.3), RADIUS, 1.0, false))
	var weights := doc.surface_weights.duplicate()
	var middle := _arc_length() * 0.5
	var part := PackedVector2Array()
	for k in 6:
		part.append(_arc_at(middle - 2.5 + k))
	assert_true(FireBrush.lay_line(editor, part, RADIUS, 0.0, true))
	var entry: Dictionary = editor.history.get("_undo").back()
	assert_eq(entry.label, FireEditor.PUT_OUT_LABEL, "one plain entry")
	assert_lt(_fire_at(editor, _arc_at(middle)), 10, "out along the erased part")
	assert_gt(_fire_at(editor, _arc_at(_arc_length() * 0.15)), 200, "the rest still burns")
	assert_eq(doc.surface_weights, weights, "the ash stays")


func test_one_undo_takes_a_line_back_byte_for_byte() -> void:
	var editor := _editor(true)
	var doc := editor.document
	var before := _layers(doc)
	var count := editor.history.undo_count()
	assert_true(FireBrush.lay_line(editor, _captured(0.3), RADIUS, FireBrush.BLAZE / 255.0, false))
	assert_eq(editor.history.undo_count(), count + 1, "one entry")
	var entry: Dictionary = editor.history.get("_undo").back()
	assert_eq(entry.label, FireEditor.LAY_LABEL)
	assert_gt(doc.surface_ids.find("ash"), -1, "ash laid with it")
	var after := _layers(doc)
	assert_eq(editor.history.undo(), FireEditor.LAY_LABEL)
	assert_eq(_layers(doc), before, "one undo restores every layer")
	editor.history.redo()
	assert_eq(_layers(doc), after, "redo lays it all again")


func test_a_release_under_two_metres_lays_nothing() -> void:
	var editor := _editor()
	var count := editor.history.undo_count()
	var short := PackedVector2Array([Vector2(0, 0), Vector2(1.9, 0)])
	assert_false(FireBrush.lay_line(editor, short, RADIUS, 1.0, false))
	assert_eq(editor.history.undo_count(), count)
	assert_true(editor.document.fire_mask.is_empty(), "no mask allocated")


func test_the_brush_draws_a_line_and_lays_it_on_release() -> void:
	var editor := _editor()
	var brush := BrushTool.new()
	add_child_autofree(brush)
	var radius_was := BrushTool.session_radius
	brush.editor = editor
	brush.use_tool(ToolRegistry.find(FireTool.ID))
	brush.set_radius(RADIUS)
	var fire := FireTool.of(brush)
	fire.shape = FireBrush.Shape.LINE
	brush.pressed = true
	brush.hit = Vector3(-6, 0, 0)
	assert_false(fire.press(brush), "the line is the mode's own, not a dab stroke")
	assert_true(fire.drawing)
	for k in 13:
		brush.hit = Vector3(-6 + k, 0, 0)
		fire.frame(brush)
	assert_eq(fire.cursor_text(brush).get_slice("  ", 0), FireBrush.LINE_TEXT)
	brush.cancel_gesture()
	assert_false(fire.drawing, "Esc drops the line")
	assert_true(editor.document.fire_mask.is_empty(), "and lays nothing")
	brush.pressed = true
	brush.hit = Vector3(-6, 0, 0)
	fire.press(brush)
	for k in 13:
		brush.hit = Vector3(-6 + k, 0, 0)
		fire.frame(brush)
	brush.finish_gesture()
	assert_false(fire.drawing)
	assert_gt(_fire_at(editor, Vector2(0, 0)), 150, "the release laid it")
	assert_eq(_fire_at(editor, Vector2(0, 6)), 0, "only along the line")
	assert_eq(editor.history.get("_undo").back().label, FireEditor.LAY_LABEL)
	BrushTool.session_radius = radius_was


func test_a_ctrl_line_names_its_length_in_its_chip() -> void:
	var editor := _editor()
	var brush := BrushTool.new()
	add_child_autofree(brush)
	var radius_was := BrushTool.session_radius
	brush.editor = editor
	brush.use_tool(ToolRegistry.find(FireTool.ID))
	brush.set_radius(RADIUS)
	brush.unit_cell_m = 1.0
	brush.unit_per_cell = 1.0
	brush.unit_label = "m"
	var fire := FireTool.of(brush)
	fire.shape = FireBrush.Shape.LINE
	brush.ctrl = true
	assert_eq(fire.cursor_text(brush), FireBrush.ERASE_TEXT, "Ctrl over the board, no line yet")
	brush.pressed = true
	brush.press_ctrl = true
	brush.hit = Vector3(-6, 0, 0)
	fire.press(brush)
	for k in 13:
		brush.hit = Vector3(-6 + k, 0, 0)
		fire.frame(brush)
	assert_eq(fire.cursor_text(brush), "Put out fire  12 m", "the put-out chip names the length")
	brush.press_ctrl = false
	assert_eq(fire.cursor_text(brush), "Line of fire  Flames  12 m", "as the lay's does")
	brush.cancel_gesture()
	BrushTool.session_radius = radius_was


## The Line's ring and ribbon show where its fire will stand: a straight Blaze line's mask
## falls under the flames band about line_reach() radii out, inside the brush's rim.
func test_the_line_shows_the_band_its_fire_stands_in() -> void:
	var radius := 4.0
	var reach := FireBrush.line_reach(FireBrush.BLAZE, 1.0, false)
	assert_between(reach, 0.6, 0.85, "the band ends inside the rim")
	assert_lt(FireBrush.line_reach(FireBrush.EMBERS, 1.0, false), 1.0)
	assert_gt(FireBrush.line_reach(FireBrush.BLAZE, 2.0, false), reach, "stronger reaches wider")
	var editor := _editor()
	var line := PackedVector2Array([Vector2(-9, 0), Vector2(9, 0)])
	assert_true(FireBrush.lay_line(editor, line, radius, 1.0, false))
	var step := editor.document.sample_step().x / editor.map_scale()
	for side in [1.0, -1.0]:
		var d := 0.0
		while _fire_at(editor, Vector2(0, side * (d + 0.05))) >= FireField.FLAME_MIN:
			d += 0.05
		assert_almost_eq(d, reach * radius, step, "the flames band ends at line_reach (%.2f)" % d)
	var put_out := FireBrush.line_reach(FireBrush.BLAZE, 1.0, true)
	assert_true(FireBrush.lay_line(editor, line, radius, 0.0, true))
	assert_lt(_fire_at(editor, Vector2(0, put_out * radius - step)), FireField.EMBER_MIN)
	var brush := BrushTool.new()
	add_child_autofree(brush)
	var radius_was := BrushTool.session_radius
	brush.editor = editor
	brush.use_tool(ToolRegistry.find(FireTool.ID))
	brush.set_radius(radius)
	var fire := FireTool.of(brush)
	fire.intensity = FireBrush.BLAZE
	assert_eq(fire.stroke_radius(brush), radius, "Area: the brush")
	fire.shape = FireBrush.Shape.LINE
	var expected := radius * FireBrush.line_reach(FireBrush.BLAZE, brush.get_flow(), false)
	assert_almost_eq(fire.stroke_radius(brush), expected, 0.001, "Line: the band")
	BrushTool.session_radius = radius_was


func _spread(values: PackedInt32Array) -> int:
	var low := 255
	var high := 0
	for v in values:
		low = mini(low, v)
		high = maxi(high, v)
	return high - low
