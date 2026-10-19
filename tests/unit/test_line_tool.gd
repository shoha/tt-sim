extends GutTest

## The line tool Water's River and Fire's Line share (card F5e): one ribbon (LineRibbon) built
## from a style, and one gesture (LineGesture). The styles change only shared keys, and the
## river's and the fire line's differ only in their tint and fill; the builder makes both
## ribbons with the same caps, edge, outline and chevrons, a chevron keeping its glyph at any
## zoom and never growing past its look at the reference zoom; the fire's rails fall to clear in
## a thin seam; the two erase ribbons share one structure with no wash, their chevrons the lay's
## with only the colour salmon (card F5g); every ribbon takes
## the scene's light; and both brushes record at one spacing, drop their line on Esc and stay
## armed, make nothing of a line under the minimum length, and read their chips alike (card F5f:
## "<shape>  <setting>  <length>", "<erase>  <length>").

## Published suns (FoliageLight.last_sun: xyz toward the sun, w its weight): the game's day
## (48 degrees up), outdoor_sunset's dusk (2.5 up) and outdoor_night (7.5 under the horizon).
const DAY := Vector4(0.0, 0.75, 0.66, 0.9)
const DUSK := Vector4(0.0, 0.044, 0.999, 0.0)
const NIGHT := Vector4(0.0, -0.13, 0.99, 0.0)
const RADIUS := 2.0
## The keys by which the river's style and the fire line's may differ: their meaning (the tint
## and its glow, the fill's coverage and light). Every other key is the line tool's.
const MEANING_KEYS := ["alpha_down", "alpha_up", "fill_gain", "fill_profile", "glow", "tint"]


func _ground() -> Callable:
	return func(p: Vector2) -> Vector2: return p * 10.0


func _line() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(8, 1)])


func _styles() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		WaterBrush.RIBBON_STYLE,
		FireBrush.LAY_STYLE,
		LineRibbon.erase_style(WaterBrush.ERASE_INTERIOR),
		FireBrush.new().put_out_style(),
	]
	return out


## Every key a tool's style sets is one of STYLE's, and the river's and the fire line's differ
## only where their meaning does.
func test_the_style_tables_differ_only_by_meaning() -> void:
	for style in _styles():
		for key: String in style:
			assert_true(LineRibbon.STYLE.has(key), "%s is a line tool key" % key)
	var river := LineRibbon.STYLE.merged(WaterBrush.RIBBON_STYLE, true)
	var fire := LineRibbon.STYLE.merged(FireBrush.LAY_STYLE, true)
	var differs: Array = []
	for key: String in LineRibbon.STYLE:
		if typeof(river[key]) != typeof(fire[key]) or river[key] != fire[key]:
			differs.append(key)
	differs.sort()
	assert_eq(differs, MEANING_KEYS)
	assert_true(river.fill_profile.is_empty(), "the river keeps its even fill")
	assert_true(LineRibbon.STYLE.caps, "round ends for every line")


## The river's ribbon and the fire line's are one shape: round caps, a closed edge over the
## same ink outline on a glow, the same chalk chevrons at the same places; the river's fill
## even and faint upstream, the fire's rails at the edges, lit, nearly clear down the middle.
func test_the_river_and_the_fire_line_build_one_shape() -> void:
	var ground := _ground()
	var line := _line()
	var river := LineRibbon.ribbon(ground, line, 1.0, WaterBrush.RIBBON_STYLE)
	var fire := LineRibbon.ribbon(ground, line, 1.0, FireBrush.LAY_STYLE)
	var arc := LineRibbon.CAP_SEGMENTS - 1
	for shape: Dictionary in [river, fire]:
		assert_eq(shape.lines.size(), 3 + 2 * 3, "glow, outline and edge; three chevrons")
		var outline: PackedVector2Array = shape.lines[0][0]
		assert_eq(outline[0], outline[-1], "round ends: one closed outline")
		assert_eq(shape.lines[1][1], Color(ThemeColors.INK, 0.55), "the edge on ink")
		assert_eq(shape.lines[1][2], 4.5, "a pixel of ink either side of the edge")
		assert_eq(shape.lines[2][2], 2.5, "the edge's weight")
		assert_eq(shape.lines[-2][1], Color(ThemeColors.INK, 0.6), "each chevron on ink")
		assert_eq(shape.lines[-1][1], Color(ThemeColors.CHALK, 0.95), "chalk chevrons")
	for k in 3:
		assert_eq(river.lines[4 + 2 * k][0], fire.lines[4 + 2 * k][0], "the same chevron %d" % k)
	assert_eq(river.lines[2][1], WaterBrush.TINT, "the river's edge in its blue")
	assert_eq(river.lines[0][1], Color(WaterBrush.TINT, 0.3), "on a glow of it")
	assert_eq(fire.lines[2][1], ThemeColors.PERSIMMON, "the fire's in persimmon")
	assert_eq(fire.lines[0][1], Color(ThemeColors.EMBER, 0.3), "on an ember glow")
	assert_eq(river.points.size(), 2 * line.size() + 2 * (1 + arc), "a fan round each end")
	assert_eq(river.indices.size(), 6 * (line.size() - 1) + 2 * 3 * (arc + 1))
	var up: Color = river.colors[0]
	assert_true(up.is_equal_approx(Color(WaterBrush.TINT * 0.12, 0.12)), "a plain blend")
	assert_almost_eq(float(river.colors[2 * line.size() - 1].a), 0.34, 0.001, "stronger down")
	assert_eq(river.points[0], Vector2(0, 10), "on the ground")
	var width := LineRibbon.fill_row(FireBrush.LAY_STYLE.fill_profile).size()
	assert_eq(width, 7, "the fire's row: edge to edge through the centre line")
	assert_eq(fire.points.size(), width * line.size() + 2 * 3 * arc, "three rings each end")
	assert_eq(fire.points[3], Vector2(0, 0), "the centre line runs down the middle")
	var rail: Color = fire.colors[0]
	assert_lt(float(fire.colors[3].a), 0.1 * rail.a, "nearly clear at the centre")
	assert_gt(rail.r, ThemeColors.PERSIMMON.r * rail.a, "lit: brighter than a plain fill")


## A cap bulges a radius past each end, and its outline keeps to the band's rim.
func test_the_ends_are_round() -> void:
	var ground := func(p: Vector2) -> Vector2: return p
	var line := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(8, 0)])
	var shape := LineRibbon.ribbon(ground, line, 1.5, WaterBrush.RIBBON_STYLE)
	var arc := LineRibbon.CAP_SEGMENTS - 1
	var tip: Vector2 = shape.points[2 * line.size() + 1 + floori(arc * 0.5)]
	assert_almost_eq(tip.x, 9.5, 0.2, "the end bulges a radius past the pointer")
	var outline: PackedVector2Array = shape.lines[0][0]
	for p in outline:
		var nearest := clampf(p.x, 0.0, 8.0)
		assert_almost_eq(p.distance_to(Vector2(nearest, 0.0)), 1.5, 0.01, "on the band's rim")


## The two erase ribbons are one structure: the lay's lines, the salmon edge and glow over the
## erase's ink (the erase ring's, BrushCursor.ring_strokes), the chevrons the lay's exactly
## (glyph, places, weights and ink) with only their colour salmon, and no wash: what an erase
## covers shows through untouched (any wash shifted the water's blue or the flames', F5f, F5g).
func test_the_erase_ribbons_share_one_structure() -> void:
	var ground := _ground()
	var line := _line()
	var lay := LineRibbon.ribbon(ground, line, 1.5, FireBrush.LAY_STYLE)
	var put_out := LineRibbon.ribbon(ground, line, 1.5, FireBrush.new().put_out_style())
	var erase := LineRibbon.ribbon(
		ground, line, 1.5, LineRibbon.erase_style(WaterBrush.ERASE_INTERIOR)
	)
	var ring := BrushCursor.ring_strokes(BrushCursor.CLEAR_TINT, 2.0)
	for shape: Dictionary in [put_out, erase]:
		assert_eq(shape.lines.size(), lay.lines.size(), "the lay's lines")
		assert_eq(shape.lines[0][1], Color(BrushCursor.CLEAR_TINT, 0.3), "a salmon glow")
		assert_eq([shape.lines[1][1], shape.lines[1][2]], ring[0], "the erase ring's ink")
		assert_eq([shape.lines[2][1], shape.lines[2][2]], ring[1], "and its salmon line")
		assert_eq(shape.lines[2][2], lay.lines[2][2], "as heavy as the lay's edge")
		for k in range(3, lay.lines.size()):
			assert_eq(shape.lines[k][0], lay.lines[k][0], "the lay's chevron glyph %d" % k)
			assert_eq(shape.lines[k][2], lay.lines[k][2], "at the lay's weight %d" % k)
		for k in range(3, lay.lines.size(), 2):
			assert_eq(shape.lines[k][1], lay.lines[k][1], "on the lay's ink %d" % k)
			var salmon := Color(BrushCursor.CLEAR_TINT, float(lay.lines[k + 1][1].a))
			assert_eq(shape.lines[k + 1][1], salmon, "only the chevron's colour salmon %d" % k)
		for c: Color in shape.colors:
			assert_eq(c.a, 0.0, "no wash: what goes shows through untouched")
	var ink: Color = ring[0][0]
	assert_true(ink.is_equal_approx(Color(ThemeColors.INK, ink.a)), "ink")
	assert_gte(ink.a, 0.8, "strong enough for 3:1 over flames and pale water")
	var plain := BrushCursor.ring_strokes(WaterBrush.TINT, 2.0)
	assert_eq(plain[1], [WaterBrush.TINT, 2.0], "a lay's ring keeps its own line")


## A chevron is one glyph at any zoom and never grows past its look at the reference zoom: a
## close one is drawn CHEVRON_PX across (scaled to the view's height) at the weights that size
## takes, so a close erase's chevrons are neither thin hollow outlines nor road markings, and an
## erase's are the lay's at every zoom (F5g).
func test_a_chevron_never_grows_past_its_reference_look() -> void:
	var line := _line()
	var far := LineRibbon.ribbon(_ground(), line, 1.0, FireBrush.LAY_STYLE)
	var near_ground := func(p: Vector2) -> Vector2: return p * 100.0
	var near := LineRibbon.ribbon(near_ground, line, 1.0, FireBrush.LAY_STYLE)
	var view := LineRibbon.CHEVRON_VIEW_H * 1.5
	var tall := LineRibbon.ribbon(near_ground, line, 1.0, FireBrush.LAY_STYLE, 1.0, 1.0, view)
	var erase := LineRibbon.ribbon(near_ground, line, 1.0, FireBrush.new().put_out_style())
	assert_lt(_across(far), LineRibbon.CHEVRON_PX, "a far chevron")
	assert_eq(far.lines[-1][2], LineRibbon.STYLE.chevron_width, "at the style's weight")
	assert_eq(far.lines[-2][2], LineRibbon.STYLE.chevron_shadow_width)
	assert_almost_eq(_across(near), LineRibbon.CHEVRON_PX, 0.01, "a near one at the reference")
	assert_almost_eq(float(near.lines[-1][2]), LineRibbon.STYLE.chevron_width, 1e-4)
	assert_almost_eq(float(near.lines[-2][2]), LineRibbon.STYLE.chevron_shadow_width, 1e-4)
	assert_almost_eq(_across(tall), LineRibbon.CHEVRON_PX * 1.5, 0.01, "a taller view's")
	assert_almost_eq(float(tall.lines[-1][2]), LineRibbon.STYLE.chevron_width * 1.5, 1e-4)
	for k in range(3, near.lines.size()):
		assert_eq(erase.lines[k][0], near.lines[k][0], "the erase's glyph the lay's %d" % k)
		assert_eq(erase.lines[k][2], near.lines[k][2], "at its weight %d" % k)


## The last chevron's width across on screen in a ribbon() `shape`.
func _across(shape: Dictionary) -> float:
	var glyph: PackedVector2Array = shape.lines[-1][0]
	return glyph[0].distance_to(glyph[2])


## The fire line's rails keep their weight out at the edges and fall to nearly clear in a thin
## seam: the half-covered olive band the old fall left inside them is gone (F5f).
func test_the_rails_fall_in_a_thin_seam() -> void:
	var profile: Array = FireBrush.LAY_STYLE.fill_profile
	assert_gte(_coverage(profile, 0.62), 0.75, "the rail holds its weight to 0.62 radii")
	assert_gte(_coverage(profile, 0.9), 0.9, "and is full at the edge")
	var held := 0.0
	var clear := 1.0
	for k in 101:
		var t := 1.0 - k * 0.01
		if _coverage(profile, t) >= 0.7:
			held = t
		elif _coverage(profile, t) <= 0.05 and clear >= 1.0:
			clear = t
	assert_lte(held - clear, 0.11, "the fall: a seam about a tenth of a radius wide")
	for t in [0.5, 0.3, 0.0]:
		assert_lte(_coverage(profile, t), 0.03, "nearly clear inside at %s" % t)


## The chip reads "<shape>  <setting>  <length>" for both line tools and "<erase>  <length>" for
## both erases, the label alone at rest.
func test_the_chips_read_alike() -> void:
	var fire := FireBrush.new()
	fire.intensity = FireBrush.BLAZE
	assert_eq(fire.line_label(), "Line of fire  Blaze")
	fire.intensity = FireBrush.EMBERS
	assert_eq(fire.line_label(), "Line of fire  Embers")
	for tile: Dictionary in FireToolPane.INTENSITY_TILES:
		assert_eq(FireBrush.intensity_label(tile.intensity), tile.label, "the pane's tile name")
	var river := WaterBrush.readout(WaterBrush.Shape.RIVER, 1, 52.0, 1.0, 1.0, "m")
	assert_eq(river, "River  Waist  52 m")
	var water := WaterBrush.new()
	assert_eq(water.readout_text(true, 1.0, 1.0, "m"), WaterBrush.ERASE_TEXT, "at rest")
	assert_eq(water.readout_text(true, 1.0, 1.0, "m", 52.2), "Erase water  52 m", "dragged")
	assert_eq(LineGesture.chip(FireBrush.ERASE_TEXT, 52.2, 1.0, 1.0, "m"), "Put out fire  52 m")


## The coverage a fill_profile gives at offset `t` from the centre line (1 the edge). Pure.
func _coverage(profile: Array, t: float) -> float:
	for k in profile.size() - 1:
		var outer: Array = profile[k]
		var inner: Array = profile[k + 1]
		if t <= float(outer[0]) and t >= float(inner[0]):
			var span := float(outer[0]) - float(inner[0])
			var w := (t - float(inner[0])) / maxf(span, 1e-6)
			return lerpf(float(inner[1]), float(outer[1]), w)
	return float(profile[-1][1])


## The hint bar's keys read alike for the two line tools: "Draw a ...", Tab naming the other
## shape, the size key named Width.
func test_the_hint_bar_reads_alike() -> void:
	var river := PlayEvents.hints_for(WaterTool.ID, HeightBrush.RAISE, WaterBrush.Shape.RIVER)
	var fire := PlayEvents.hints_for(FireTool.ID, HeightBrush.RAISE, FireBrush.Shape.LINE)
	assert_eq(river.size(), fire.size())
	assert_eq(river[0].action, "Draw a river")
	assert_eq(fire[0].action, "Draw a line of fire")
	assert_eq(river[1].key, fire[1].key, "Tab in the same slot")
	assert_eq([river[1].action, fire[1].action], ["Pond", "Area"])
	assert_eq(river[2], fire[2], "the same size key")
	assert_eq(fire[2].action, "Width")
	for hint: String in [WaterToolPane.HINT, FireToolPane.HINT]:
		assert_true(hint.ends_with(" Tab switches the shape."), "each pane names Tab alike")


## Every ribbon takes the scene's light: full by day and at dusk, NIGHT_LIGHT of its colour
## under a sun well below the horizon, the alpha kept.
func test_every_ribbon_takes_the_scene_light() -> void:
	var least := LineRibbon.NIGHT_LIGHT
	assert_eq(LineRibbon.scene_light(DAY, least), 1.0, "full by day")
	assert_eq(LineRibbon.scene_light(DUSK, least), 1.0, "and at dusk, the sun just up")
	assert_eq(LineRibbon.scene_light(NIGHT, least), least, "the floor at night")
	assert_eq(LineRibbon.scene_light(FoliageLight.NO_SUN, least), 1.0, "full with no sun")
	var ground := _ground()
	var line := _line()
	for style in _styles():
		var light := LineRibbon.light_of(style, NIGHT)
		assert_eq(light, least)
		var day := LineRibbon.ribbon(ground, line, 1.0, style)
		var night := LineRibbon.ribbon(ground, line, 1.0, style, 1.0, light)
		assert_almost_eq(float(night.lines[2][1].r), float(day.lines[2][1].r) * least, 0.001)
		assert_eq(float(night.lines[2][1].a), float(day.lines[2][1].a), "alpha kept")
		assert_almost_eq(float(night.colors[0].g), float(day.colors[0].g) * least, 0.001)


## The gesture records at the line tool's spacing, ends its line at the pointer, previews the
## line a release there would make, and drops a line under the minimum length.
func test_the_gesture_records_and_ends_at_the_pointer() -> void:
	assert_eq(LineGesture.spacing(0.5), StrokePath.DECIMATE_M)
	assert_almost_eq(LineGesture.spacing(3.0), 1.8, 1e-5, "a wide line: 0.6 half-widths")
	var gesture := LineGesture.new()
	gesture.begin(Vector3(0, 1.5, 0))
	for k in 30:
		gesture.track(Vector3(k * 0.1, 1.5, 0), 0.5)
	gesture.track(Vector3.INF, 0.5)
	for i in gesture.points.size() - 1:
		assert_gte(gesture.points[i].distance_to(gesture.points[i + 1]), 0.6 - 1e-4)
	assert_true(gesture.line()[-1].is_equal_approx(Vector2(2.9, 0)), "ends at the pointer")
	assert_eq(gesture.live(Vector3(3.5, 0, 0))[-1], Vector2(3.5, 0), "previewed to the pointer")
	assert_almost_eq(gesture.height, 1.5, 1e-5, "the last point's height")
	assert_almost_eq(gesture.finish()[-1].x, 2.9, 1e-4, "a release makes the line")
	assert_false(gesture.drawing)
	gesture.begin(Vector3.ZERO)
	gesture.track(Vector3(1.9, 0, 0), 0.5)
	assert_true(gesture.finish().is_empty(), "under 2 m: nothing")
	assert_eq(LineGesture.chip("River  Waist", 12.2, 1.524, 5.0, "ft"), "River  Waist  40 ft")
	assert_eq(LineGesture.chip("Line of fire", 0.0, 1.524, 5.0, "ft"), "Line of fire")


## Both brushes draw their line through one gesture: the chip reads "<label>  N <unit>" while it
## is drawn and the label at rest, Esc drops the line and the tool stays armed, and a release
## under the minimum length makes nothing.
func test_both_line_tools_share_the_gesture() -> void:
	var editor := _editor()
	var radius_was := BrushTool.session_radius
	for tool_id: StringName in [WaterTool.ID, FireTool.ID]:
		var brush := BrushTool.new()
		add_child_autofree(brush)
		brush.editor = editor
		brush.use_tool(ToolRegistry.find(tool_id))
		brush.set_radius(RADIUS)
		brush.unit_cell_m = 1.0
		brush.unit_per_cell = 1.0
		brush.unit_label = "m"
		var mode := brush.mode
		if mode is FireBrush:
			(mode as FireBrush).shape = FireBrush.Shape.LINE
		var label := "Line of fire  Flames" if mode is FireBrush else "River  Waist"
		var gesture: LineGesture = mode.get("gesture")
		assert_eq(mode.cursor_text(brush), label, "%s: the chip at rest" % tool_id)
		_draw(brush, 13)
		assert_true(gesture.drawing)
		assert_eq(mode.cursor_text(brush), "%s  12 m" % label, "%s: the chip" % tool_id)
		brush.cancel_gesture()
		assert_false(gesture.drawing, "%s: Esc drops the line" % tool_id)
		assert_eq(brush.mode, mode, "and the tool stays armed")
		var count := editor.history.undo_count()
		_draw(brush, 2)
		brush.finish_gesture()
		assert_false(gesture.drawing)
		assert_eq(editor.history.undo_count(), count, "%s: a 1 m line makes nothing" % tool_id)
	BrushTool.session_radius = radius_was


func _editor() -> AuthoringEditor:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_birch", "v", 11)
	var root := MapSourceLoader.create_authored_root(doc)
	MapSourceLoader.add_fire_field(root, doc)
	add_child_autofree(root)
	return AuthoringEditor.create(doc, root, AuthoringHistory.new())


## A press at x = -6 and `frames` frames a metre apart along +x.
func _draw(brush: BrushTool, frames: int) -> void:
	brush.pressed = true
	brush.hit = Vector3(-6, 0, 0)
	brush.mode.press(brush)
	for k in frames:
		brush.hit = Vector3(-6 + k, 0, 0)
		brush.mode.frame(brush)
