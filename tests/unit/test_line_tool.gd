extends GutTest

## The line tool Water's River and Fire's Line share (card F5e): one ribbon (LineRibbon) built
## from a style, and one gesture (LineGesture). The river and the fire line are one look in two
## hues (card F5h; user, 2026-10-18): their styles are equal key for key but the tint keys,
## under either fill (LineRibbon.FILLS), the rails by default; every line is the ring's stroke
## (BrushCursor.ring_strokes); a chevron keeps its glyph at any zoom and never grows past its
## look at the reference zoom, lay and erase alike; the rails fall to clear in a thin seam; both
## erases are one style with no wash, their lines the lay's at the lay's weights with only the
## colour salmon (cards F5g, F5h); every ribbon takes the scene's light; and both brushes record
## at one spacing, drop their line on Esc and stay armed, make nothing of a line under the
## minimum length, and read their chips alike (card F5f: "<shape>  <setting>  <length>",
## "<erase>  <length>").

## Published suns (FoliageLight.last_sun: xyz toward the sun, w its weight): the game's day
## (48 degrees up), outdoor_sunset's dusk (2.5 up) and outdoor_night (7.5 under the horizon).
const DAY := Vector4(0.0, 0.75, 0.66, 0.9)
const DUSK := Vector4(0.0, 0.044, 0.999, 0.0)
const NIGHT := Vector4(0.0, -0.13, 0.99, 0.0)
const RADIUS := 2.0


func _ground() -> Callable:
	return func(p: Vector2) -> Vector2: return p * 10.0


func _line() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(8, 1)])


func _styles() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		WaterBrush.new().ribbon_style(),
		FireBrush.new().lay_style(),
		LineRibbon.lay_style(WaterBrush.RIBBON_HUE, "even"),
		LineRibbon.lay_style(FireBrush.LAY_HUE, "even"),
		LineRibbon.ERASE_STYLE,
	]
	return out


## The keys of `style` over STYLE where `other` over STYLE differs, sorted.
func _differing(style: Dictionary, other: Dictionary) -> Array:
	var a := LineRibbon.STYLE.merged(style, true)
	var b := LineRibbon.STYLE.merged(other, true)
	var differs: Array = []
	for key: String in LineRibbon.STYLE:
		if typeof(a[key]) != typeof(b[key]) or a[key] != b[key]:
			differs.append(key)
	differs.sort()
	return differs


## Every key a tool's style sets is one of STYLE's, and the river's and the fire line's are
## equal key for key but the tint keys, under either fill: every width, alpha, edge, glow, ink,
## cap, chevron and fill profile one, only the hue differing (lake and persimmon, the theme's
## paired ramps, at about one lightness). Both tools take the rails unless told otherwise.
func test_the_river_and_the_fire_line_are_one_look_in_two_hues() -> void:
	for style in _styles():
		for key: String in style:
			assert_true(LineRibbon.STYLE.has(key), "%s is a line tool key" % key)
	var tint_keys: Array = []
	tint_keys.append_array(LineRibbon.TINT_KEYS)
	tint_keys.sort()
	for fill: String in LineRibbon.FILLS:
		var water := WaterBrush.new()
		var fire := FireBrush.new()
		water.fill = fill
		fire.fill = fill
		var river := water.ribbon_style()
		var line := fire.lay_style()
		assert_eq(_differing(river, line), tint_keys, "only the hue differs (%s)" % fill)
		for key: String in LineRibbon.TINT_KEYS:
			var blue: Color = river[key]
			var orange: Color = line[key]
			assert_almost_eq(blue.ok_hsl_l, orange.ok_hsl_l, 0.1, "%s: one lightness" % key)
	assert_eq(LineRibbon.FILL, "rails", "the rails by default (option R)")
	assert_eq(WaterBrush.new().fill, LineRibbon.FILL)
	assert_eq(FireBrush.new().fill, LineRibbon.FILL)
	assert_eq(WaterBrush.RIBBON_HUE, {"tint": ThemeColors.LAKE, "glow": ThemeColors.LAKE_LIGHT})
	assert_eq(FireBrush.LAY_HUE, {"tint": ThemeColors.PERSIMMON, "glow": ThemeColors.EMBER})
	assert_eq(WaterBrush.TINT, WaterBrush.RIBBON_HUE.glow, "each ring in its line's glow")
	assert_eq(FireBrush.TINT, FireBrush.LAY_HUE.glow, "each ring in its line's glow")
	assert_true(LineRibbon.STYLE.caps, "round ends for every line")


## The river's ribbon and the fire line's are one shape: round caps, a closed edge over the
## ring's ink on a glow at the ring's weights, the same chalk chevrons at the same places; under
## the rails both lit at the edges and nearly clear down the middle, under the even fill both
## faint upstream and stronger down.
func test_the_river_and_the_fire_line_build_one_shape() -> void:
	var ground := _ground()
	var line := _line()
	var river := LineRibbon.ribbon(ground, line, 1.0, WaterBrush.new().ribbon_style())
	var fire := LineRibbon.ribbon(ground, line, 1.0, FireBrush.new().lay_style())
	var arc := LineRibbon.CAP_SEGMENTS - 1
	var ring := BrushCursor.ring_strokes(ThemeColors.EMBER)
	var width := LineRibbon.fill_row(LineRibbon.FILLS.rails.fill_profile).size()
	assert_eq(width, 7, "the rails' row: edge to edge through the centre line")
	for shape: Dictionary in [river, fire]:
		assert_eq(shape.lines.size(), 3 + 2 * 3, "glow, outline and edge; three chevrons")
		var outline: PackedVector2Array = shape.lines[0][0]
		assert_eq(outline[0], outline[-1], "round ends: one closed outline")
		assert_eq(shape.lines[0][2], ring[0][1], "the ring's glow width")
		assert_eq(float(shape.lines[0][1].a), float(ring[0][0].a), "at the ring's glow alpha")
		assert_eq([shape.lines[1][1], shape.lines[1][2]], ring[1], "the ring's ink")
		assert_eq(shape.lines[2][2], ring[2][1], "the ring's weight")
		assert_eq(shape.lines[-2][1], Color(ThemeColors.INK, BrushCursor.INK_ALPHA), "on ink")
		assert_eq(shape.lines[-2][2], BrushCursor.INK_WIDTH, "at the ring's ink width")
		assert_eq(shape.lines[-1][1], Color(ThemeColors.CHALK, 0.95), "chalk chevrons")
		assert_eq(shape.lines[-1][2], BrushCursor.LINE_WIDTH, "at the ring's weight")
		assert_eq(shape.points.size(), width * line.size() + 2 * 3 * arc, "three rings each end")
		assert_eq(shape.points[3], Vector2(0, 0), "the centre line runs down the middle")
		var rail: Color = shape.colors[0]
		assert_lt(float(shape.colors[3].a), 0.1 * rail.a, "nearly clear at the centre")
	for k in 3:
		assert_eq(river.lines[4 + 2 * k][0], fire.lines[4 + 2 * k][0], "the same chevron %d" % k)
	assert_eq(river.lines[2][1], ThemeColors.LAKE, "the river's edge in lake")
	assert_eq(river.lines[0][1], Color(ThemeColors.LAKE_LIGHT, 0.3), "on a light lake glow")
	assert_eq(fire.lines[2][1], ThemeColors.PERSIMMON, "the fire's in persimmon")
	assert_eq(fire.lines[0][1], Color(ThemeColors.EMBER, 0.3), "on an ember glow")
	var lit: Color = fire.colors[0]
	assert_gt(lit.r, ThemeColors.PERSIMMON.r * lit.a, "lit: brighter than a plain fill")
	var even_style := LineRibbon.lay_style(WaterBrush.RIBBON_HUE, "even")
	var even := LineRibbon.ribbon(ground, line, 1.0, even_style)
	assert_eq(even.points.size(), 2 * line.size() + 2 * (1 + arc), "a fan round each end")
	assert_eq(even.indices.size(), 6 * (line.size() - 1) + 2 * 3 * (arc + 1))
	var up: Color = even.colors[0]
	assert_true(up.is_equal_approx(Color(ThemeColors.LAKE * 0.12, 0.12)), "a plain blend")
	assert_almost_eq(float(even.colors[2 * line.size() - 1].a), 0.34, 0.001, "stronger down")
	assert_eq(even.points[0], Vector2(0, 10), "on the ground")


## A cap bulges a radius past each end, and its outline keeps to the band's rim.
func test_the_ends_are_round() -> void:
	var ground := func(p: Vector2) -> Vector2: return p
	var line := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(8, 0)])
	var even_style := LineRibbon.lay_style(WaterBrush.RIBBON_HUE, "even")
	var shape := LineRibbon.ribbon(ground, line, 1.5, even_style)
	var arc := LineRibbon.CAP_SEGMENTS - 1
	var tip: Vector2 = shape.points[2 * line.size() + 1 + floori(arc * 0.5)]
	assert_almost_eq(tip.x, 9.5, 0.2, "the end bulges a radius past the pointer")
	var outline: PackedVector2Array = shape.lines[0][0]
	for p in outline:
		var nearest := clampf(p.x, 0.0, 8.0)
		assert_almost_eq(p.distance_to(Vector2(nearest, 0.0)), 1.5, 0.01, "on the band's rim")


## The erase is one style for both tools (the river's erase and the fire's put-out preview
## alike): the lay's lines at the lay's weights (the put-out's edge as heavy as the fire line's,
## its ink the ring's), the edge and glow salmon, the chevrons the lay's exactly (glyph, places,
## weights and ink) with only their colour salmon, and no wash: what an erase covers shows
## through untouched (any wash shifted the water's blue or the flames', F5f, F5g).
func test_the_erase_ribbons_share_one_structure() -> void:
	var ground := _ground()
	var line := _line()
	var erase := LineRibbon.ribbon(ground, line, 1.5, LineRibbon.ERASE_STYLE)
	var salmon := BrushCursor.CLEAR_TINT
	var ring := BrushCursor.ring_strokes(salmon)
	assert_eq(erase.lines[0][1], ring[0][0], "the erase ring's salmon glow")
	assert_eq([erase.lines[1][1], erase.lines[1][2]], ring[1], "the erase ring's ink")
	assert_eq([erase.lines[2][1], erase.lines[2][2]], ring[2], "and its salmon line")
	for c: Color in erase.colors:
		assert_eq(c.a, 0.0, "no wash: what goes shows through untouched")
	for style in [WaterBrush.new().ribbon_style(), FireBrush.new().lay_style()]:
		var lay := LineRibbon.ribbon(ground, line, 1.5, style)
		assert_eq(erase.lines.size(), lay.lines.size(), "the lay's lines")
		for k in lay.lines.size():
			assert_eq(erase.lines[k][0], lay.lines[k][0], "the lay's line %d" % k)
			assert_eq(erase.lines[k][2], lay.lines[k][2], "at the lay's weight %d" % k)
			var colour: Color = lay.lines[k][1]
			var is_ink := colour.is_equal_approx(Color(ThemeColors.INK, colour.a))
			var expected := colour if is_ink else Color(salmon, colour.a)
			assert_eq(erase.lines[k][1], expected, "only the colour salmon %d" % k)


## A chevron is one glyph at any zoom and never grows past its look at the reference zoom, lay
## and erase alike: a close one is drawn CHEVRON_PX across (scaled to the view's height) at the
## weights that size takes, so a close erase's chevrons are neither thin hollow outlines nor
## road markings, and an erase's are the lay's glyph, weight and ink at every zoom, salmon (F5g).
func test_a_chevron_never_grows_past_its_reference_look() -> void:
	var line := _line()
	var lay_style := FireBrush.new().lay_style()
	var far := LineRibbon.ribbon(_ground(), line, 1.0, lay_style)
	var near_ground := func(p: Vector2) -> Vector2: return p * 100.0
	var near := LineRibbon.ribbon(near_ground, line, 1.0, lay_style)
	var view := LineRibbon.CHEVRON_VIEW_H * 1.5
	var tall := LineRibbon.ribbon(near_ground, line, 1.0, lay_style, 1.0, 1.0, view)
	var erase := LineRibbon.ribbon(near_ground, line, 1.0, LineRibbon.ERASE_STYLE)
	assert_almost_eq(_across(erase), LineRibbon.CHEVRON_PX, 0.01, "the erase's clamped too")
	assert_eq(erase.lines[-1][1], Color(BrushCursor.CLEAR_TINT, 0.95), "a salmon chevron")
	assert_eq(erase.lines[-2][1], near.lines[-2][1], "on the lay's ink")
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


## The rails keep their weight out at the edges and fall to nearly clear in a thin seam: the
## half-covered olive band the old fall left inside the fire's is gone (F5f).
func test_the_rails_fall_in_a_thin_seam() -> void:
	var profile: Array = LineRibbon.FILLS.rails.fill_profile
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
	var ignite: String = EventsPane.TOOL_HINTS[EventPresets.IGNITE]
	for hint: String in [WaterToolPane.HINT, FireToolPane.HINT, ignite]:
		assert_true(hint.ends_with(" Tab switches the shape."), "each pane names Tab alike")
	# Start a fire's help names its shapes in its tiles' order, Path then Circle (card F6b).
	assert_true(ignite.begins_with("Path: "), "the first tile first")
	assert_gt(ignite.find("Circle: "), 0, "then the second")


## Every lay ribbon takes the scene's light: full by day and at dusk, NIGHT_LIGHT of its colour
## under a sun well below the horizon, the alpha kept. An erase keeps its full colour, as the
## erase ring does (dimmed, its salmon fell to about 2:1 over the river at night, F5h).
func test_every_ribbon_takes_the_scene_light() -> void:
	var least := LineRibbon.NIGHT_LIGHT
	assert_eq(LineRibbon.scene_light(DAY, least), 1.0, "full by day")
	assert_eq(LineRibbon.scene_light(DUSK, least), 1.0, "and at dusk, the sun just up")
	assert_eq(LineRibbon.scene_light(NIGHT, least), least, "the floor at night")
	assert_eq(LineRibbon.scene_light(FoliageLight.NO_SUN, least), 1.0, "full with no sun")
	assert_eq(LineRibbon.light_of(LineRibbon.ERASE_STYLE, NIGHT), 1.0, "an erase: full")
	var ground := _ground()
	var line := _line()
	for style in _styles():
		if style == LineRibbon.ERASE_STYLE:
			continue
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


## Start a fire's Path is the third line tool (card F6): where trees catch its ribbon is the
## fire line's key for key but the hue (Start a fire's deep ochre on its ring's light ochre),
## where only the ground burns the same but for its narrower rails (LineRibbon.QUIET_STYLE),
## and a path with no forest anywhere the refused ring's chalk_soft with no fill (card F6b).
## Its rails give back ochre and never pass full value (ochre itself clipped to lemon). Its
## hint keys read as the line tools', and it records through the same gesture: "Fire along a
## path" at rest, Esc drops the line and stays armed, a release under the minimum says "Draw
## the fire's path", one with no forest along it fires nothing.
func test_start_a_fire_path_is_the_third_line_tool() -> void:
	var tint_keys: Array = []
	tint_keys.append_array(LineRibbon.TINT_KEYS)
	tint_keys.sort()
	var refused_keys: Array = ["alpha_up", "alpha_down"]
	refused_keys.append_array(LineRibbon.TINT_KEYS)
	refused_keys.sort()
	for fill: String in LineRibbon.FILLS:
		var fire := FireBrush.new()
		var path := IgniteMode.new()
		fire.fill = fill
		path.fill = fill
		var trees := path.lay_style(IgniteMode.Stretch.TREES)
		assert_eq(_differing(fire.lay_style(), trees), tint_keys, "the hue (%s)" % fill)
		var ground := path.lay_style(IgniteMode.Stretch.GROUND)
		assert_eq(_differing(trees, ground), ["fill_profile"], "only the ground: narrower rails")
		var refused_style := path.lay_style(IgniteMode.Stretch.REFUSED)
		assert_eq(_differing(trees, refused_style), refused_keys, "refused: chalk, no fill")
		assert_eq(float(refused_style.alpha_up) + float(refused_style.alpha_down), 0.0, "lines alone")
	assert_eq(IgniteMode.new().fill, LineRibbon.FILL, "the rails by default")
	assert_eq(IgniteMode.PATH_HUE.glow, ToppleMode.TINT, "on its ring's colour")
	assert_eq(IgniteMode.REFUSED_HUE.tint, CollapseMode.REFUSED_TINT, "the refused ring's chalk")
	var rails: Dictionary = LineRibbon.FILLS.rails
	var tint: Color = IgniteMode.PATH_HUES.A.tint
	var faint := LineRibbon.lit_fill(Color(tint, rails.alpha_up), rails.fill_gain)
	for c in 3:
		assert_almost_eq(faint[c], ThemeColors.OCHRE[c], 0.01, "A's faintest rail is ochre")
	var strong := LineRibbon.lit_fill(
		Color(IgniteMode.PATH_HUE.tint, rails.alpha_down), rails.fill_gain
	)
	for c in 3:
		assert_lt(strong[c], 1.0, "the strongest within full value")
	var quiet := LineRibbon.ribbon(_ground(), _line(), 1.0, LineRibbon.QUIET_STYLE)
	var lay := LineRibbon.ribbon(_ground(), _line(), 1.0, {})
	assert_eq(quiet.lines, lay.lines, "the quiet stretch's lines are the lay's")
	var line := PlayEvents.hints_for(FireTool.ID, HeightBrush.RAISE, FireBrush.Shape.LINE)
	var hints := PlayEvents.hints_for(EventPresets.IGNITE, HeightBrush.RAISE, IgniteMode.Shape.PATH)
	assert_eq(hints.size(), line.size())
	assert_eq(hints[0], {"key": line[0].key, "action": "Draw a fire path"}, "the drag: Draw a ...")
	assert_eq(hints[1], {"key": line[1].key, "action": "Circle"}, "Tab names the other shape")
	assert_eq(hints[2], line[2], "the same size key, Width")
	# Only its two own ends are round: a stretch cut at a span's edge joins with no edge across.
	var open := LineRibbon.ribbon(_ground(), _line(), 1.0, {"cap_end": false})
	var outline: PackedVector2Array = open.lines[0][0]
	assert_ne(outline[0], outline[-1], "open where it is cut")
	var sides := 2 * _line().size()
	assert_eq(outline.size(), sides + LineRibbon.CAP_SEGMENTS - 1, "round only at its start")
	var cut := LineRibbon.ribbon(_ground(), _line(), 1.0, {"cap_start": false, "cap_end": false})
	assert_eq(cut.lines.size(), 3 * 2 + 2 * 3, "both sides apart, uncapped")
	var editor := _editor()
	var radius_was := BrushTool.session_radius
	var brush := BrushTool.new()
	add_child_autofree(brush)
	brush.editor = editor
	brush.use_tool(EventPresets.find(EventPresets.IGNITE))
	brush.set_radius(RADIUS)
	brush.unit_cell_m = 1.0
	brush.unit_per_cell = 1.0
	brush.unit_label = "m"
	var mode := brush.mode as IgniteMode
	assert_eq(mode.shape, IgniteMode.Shape.CIRCLE, "Circle by default")
	assert_true(mode.has_shapes(), "Tab is the brush's")
	assert_true(mode.toggle_shape(brush))
	assert_eq(mode.cursor_text(brush), IgniteMode.PATH_TEXT, "at rest")
	assert_eq(mode.stroke_radius(brush), RADIUS, "the ring at the half-width")
	var refused := []
	brush.refused.connect(func(why: String) -> void: refused.append(why))
	var fired := []
	mode.fired.connect(func(event: TerrainEvent) -> void: fired.append(event))
	_draw(brush, 13)
	assert_true(mode.gesture.drawing)
	assert_eq(mode.cursor_text(brush), IgniteMode.NOT_A_FOREST, "no forest along it")
	brush.cancel_gesture()
	assert_false(mode.gesture.drawing, "Esc drops the line")
	assert_eq(brush.mode, mode, "and the preset stays armed")
	assert_eq(refused, [], "dropping says nothing")
	_draw(brush, 2)
	brush.finish_gesture()
	assert_eq(refused, [IgniteMode.DRAW_PATH], "a 1 m line")
	_draw(brush, 13)
	brush.finish_gesture()
	assert_eq(refused, [IgniteMode.DRAW_PATH, TerrainEvents.NO_FOREST_PATH], "no forest")
	assert_eq(fired.size(), 0, "nothing fired")
	brush.set_radius(10.0)
	assert_eq(mode.path_radius(brush), TerrainEvent.MAX_PATH_RADIUS_M, "at most 6 m either side")
	BrushTool.session_radius = radius_was
	assert_eq(IgniteMode.path_chip(12.2, false, true), "Fire along a path  12 m", "while drawn")
	assert_eq(IgniteMode.path_chip(0.0, false, false), IgniteMode.PATH_TEXT, "at rest")
	assert_eq(IgniteMode.path_chip(64.0, true, true), IgniteMode.LONGEST_TEXT, "at the cap")
	var long := IgniteMode.event_line(PackedVector2Array([Vector2.ZERO, Vector2(100, 0)]))
	assert_almost_eq(StrokePath.line_length(long), TerrainEvent.MAX_PATH_LENGTH_M, 0.01)
	assert_lte(long.size(), TerrainEvent.MAX_PATH_POINTS)
	assert_not_null(TerrainEvent.decode(TerrainEvent.fire_path(long, 2.0, 1).encode()))


## Where a Path's stretch turns from trees to ground only, its rails narrow along the arc over
## about one half-width (LineRibbon's quiet_spans, card F6c), never in a square notch: from one
## sample to the next the rails' inner edge moves at most 0.09 half-widths and no faster than
## 0.4 m across per metre along, the forest stretch keeps its whole rails, and the band stays
## one outline with the lay's chevrons. The Path draws its line as that one ribbon.
func test_a_quiet_stretch_narrows_along_the_arc() -> void:
	var radius := 2.0
	var line := PackedVector2Array()
	for k in 11:
		line.append(Vector2(2.0 * k, 0.0))
	var lay := LineRibbon.lay_style(IgniteMode.PATH_HUE)
	var look := LineRibbon.STYLE.merged(lay, true)
	look.quiet_spans = PackedVector2Array([Vector2(6.0, 14.0)])
	var band := LineRibbon.rows_along(line, radius, look)
	var stopped: PackedVector2Array = band.line
	var rows: Array = band.rows
	var full: Array = LineRibbon.fill_row(LineRibbon.FILLS.rails.fill_profile)
	var quiet: Array = LineRibbon.fill_row(LineRibbon.QUIET_PROFILE)
	assert_gt(stopped.size(), line.size(), "the tapers take points of their own")
	var most_step := 0.0
	var most_slope := 0.0
	for i in stopped.size():
		var x := stopped[i].x
		var inner := float(rows[i][2][0])
		if x <= 6.0 or x >= 14.0:
			assert_almost_eq(inner, float(full[2][0]), 0.001, "whole rails at %.2f m" % x)
		elif x >= 6.0 + radius and x <= 14.0 - radius:
			assert_almost_eq(inner, float(quiet[2][0]), 0.001, "narrowed at %.2f m" % x)
		if i > 0:
			var step := absf(inner - float(rows[i - 1][2][0]))
			most_step = maxf(most_step, step)
			most_slope = maxf(most_slope, step * radius / (x - stopped[i - 1].x))
	assert_lte(most_step, 0.09, "no step in the rails' width over 0.09 half-widths per sample")
	assert_lte(most_slope, 0.4, "nor steeper than 0.4 m across per metre along")
	var plain := LineRibbon.ribbon(_ground(), line, radius, lay)
	var eased := LineRibbon.ribbon(_ground(), line, radius, look)
	assert_eq(eased.lines.size(), plain.lines.size(), "one outline, the lay's chevrons")
	var ends := PackedVector2Array([Vector2(0.0, 5.0), Vector2(14.0, 20.0)])
	assert_eq(LineRibbon.quiet_at(0.0, ends, 20.0, radius), 1.0, "no taper at the line's start")
	assert_eq(LineRibbon.quiet_at(20.0, ends, 20.0, radius), 1.0, "nor at its end")
	assert_eq(LineRibbon.quiet_at(14.0, ends, 20.0, radius), 0.0, "whole where the trees end")
	var path := IgniteMode.new()
	var style := path.path_style(PackedVector2Array([Vector2(0.0, 5.0), Vector2(9.0, 12.0)]), 20.0)
	assert_eq(style.quiet_spans, PackedVector2Array([Vector2(5, 9), Vector2(12, 20)]), "between")
	assert_eq(style.quiet_profile, path.lay_style(IgniteMode.Stretch.GROUND).fill_profile)
	assert_eq(_differing(path.lay_style(), style), ["quiet_spans"], "else the forest's look")
	var refused := path.lay_style(IgniteMode.Stretch.REFUSED)
	assert_eq(path.path_style(PackedVector2Array(), 20.0), refused, "no forest: refused whole")


## Start a fire's Path keeps card F6c's three hues to compare, each a theme role on the ring's
## light ochre, so only the tint differs from the default, and none of them lifted by the rails
## past full value; C, the user's pick (2026-10-19), is the default.
func test_the_path_hues_differ_only_in_their_tint() -> void:
	assert_eq(IgniteMode.HUE, "C")
	assert_eq(IgniteMode.PATH_HUES[IgniteMode.HUE], IgniteMode.PATH_HUE, "C is the Path's")
	var rails: Dictionary = LineRibbon.FILLS.rails
	var tints: Array = []
	for hue_name: String in IgniteMode.PATH_HUES:
		var path := IgniteMode.new()
		path.hue = hue_name
		var style := path.lay_style()
		assert_eq(style.glow, ToppleMode.TINT, "%s on the ring's colour" % hue_name)
		var expected: Array = [] if hue_name == IgniteMode.HUE else ["tint"]
		assert_eq(_differing(IgniteMode.new().lay_style(), style), expected, hue_name)
		var strong := LineRibbon.lit_fill(Color(style.tint, rails.alpha_down), rails.fill_gain)
		for c in 3:
			assert_lt(strong[c], 1.01, "%s's strongest rail within full value" % hue_name)
		tints.append(style.tint)
	assert_eq(tints, [ThemeColors.OCHRE_DEEP, ThemeColors.OCHRE_DEEPER, ThemeColors.AMBER_DEEP])


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
