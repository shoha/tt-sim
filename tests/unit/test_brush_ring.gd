extends GutTest

## Every brush's ring is one stroke (card F5h): its tint over the ink on a glow of the tint, at
## the same weights at rest and in erase, the stroke every line tool's edge takes; and the one
## erase salmon (BrushCursor.CLEAR_TINT) holds 3:1 with that ink over every ground an erase is
## drawn on, by day and in a ribbon's night light. The lay ring at rest was a 2 px hairline on a
## faint shadow (persimmon over bright grass about 2.4:1), and the old salmon read brown over
## flames and brick over ash.

## The grounds an erase is drawn on, as read off the captures (card F5h): flame yellow, a flame's
## core, ash, the river at night and bright grass.
const GROUNDS := {
	"flame": Color8(255, 220, 116),
	"core": Color8(255, 244, 216),
	"ash": Color8(90, 62, 42),
	"water at night": Color8(66, 84, 102),
	"bright grass": Color8(159, 192, 46),
}


## Every ring tint a brush draws, at rest and with Ctrl: Biome's and Paint's defaults, Thin's,
## Sculpt's three, Place's, Water's, Fire's, and the erase salmon.
func _tints() -> Array[Color]:
	var out: Array[Color] = [
		BiomeBrush.new().tint,
		PaintBrush.new().tint,
		ThinBrush.THIN_TINT,
		SculptBrush.RAISE_TINT,
		SculptBrush.LOWER_TINT,
		SculptBrush.SMOOTH_TINT,
		BrushCursor.PLACE_TINT,
		WaterBrush.TINT,
		FireBrush.TINT,
		BrushCursor.CLEAR_TINT,
	]
	return out


## One stroke for every ring, lay and erase alike: the glow, the ink and the line at the same
## widths, the ink the same, the glow and the line the ring's tint.
func test_every_ring_is_one_stroke() -> void:
	var ink := Color(ThemeColors.INK, BrushCursor.INK_ALPHA)
	for tint in _tints():
		var strokes := BrushCursor.ring_strokes(tint)
		assert_eq(strokes.size(), 3, "glow, ink, line")
		assert_eq(strokes[0], [Color(tint, BrushCursor.GLOW_ALPHA), BrushCursor.GLOW_WIDTH])
		assert_eq(strokes[1], [ink, BrushCursor.INK_WIDTH], "the erase ring's ink for every ring")
		assert_eq(strokes[2], [tint, BrushCursor.LINE_WIDTH], "one weight at rest and in erase")
	var faint := BrushCursor.ring_strokes(Color(BrushCursor.CLEAR_TINT, 0.5))
	assert_almost_eq(float(faint[1][0].a), BrushCursor.INK_ALPHA * 0.5, 1e-5, "a faint tint")
	assert_gt(BrushCursor.INK_WIDTH - BrushCursor.LINE_WIDTH, 2.5, "over a pixel of ink a side")


## The line tool's edges are the ring's stroke: a ribbon's glow, ink and edge at the ring's
## widths and alphas, so the ring and the line it draws read as one.
func test_the_line_tool_edge_is_the_ring_stroke() -> void:
	var style := LineRibbon.STYLE
	assert_eq(style.edge_width, BrushCursor.LINE_WIDTH)
	assert_eq(style.shadow_alpha, BrushCursor.INK_ALPHA)
	assert_eq(style.shadow_width, BrushCursor.INK_WIDTH)
	assert_eq(style.glow_alpha, BrushCursor.GLOW_ALPHA)
	assert_eq(style.glow_width, BrushCursor.GLOW_WIDTH)
	assert_eq(style.chevron_width, BrushCursor.LINE_WIDTH, "the chevrons at the ring's weight")
	assert_eq(style.chevron_shadow_alpha, BrushCursor.INK_ALPHA, "on the ring's ink")
	assert_eq(style.chevron_shadow_width, BrushCursor.INK_WIDTH)


## Every lay ring holds 3:1 on its ink over bright grass, and the ink against the grass.
func test_a_lay_ring_reads_on_bright_grass() -> void:
	var grass: Color = GROUNDS["bright grass"]
	var outline := _outline(grass)
	assert_gte(BackdropPaint.contrast(outline, grass), 3.0, "the ink against the grass")
	for tint in _tints():
		assert_gte(BackdropPaint.contrast(tint, outline), 3.0, "%s on its ink" % tint.to_html())


## The one erase salmon: every erase reads it (the rings, the line tool's erase, the bridge's
## erase), never dimmed at night (the ring is not, and the erase ribbon keeps its full colour),
## and with the ink outline it holds 3:1 over every ground: on its ink, and either it or its
## ink against the ground. It stays a salmon, apart from the cream and tan lay rings.
func test_the_erase_salmon_holds_over_every_ground() -> void:
	assert_eq(LineRibbon.ERASE_STYLE.tint, BrushCursor.CLEAR_TINT)
	assert_eq(LineRibbon.ERASE_STYLE.chevron, BrushCursor.CLEAR_TINT)
	assert_eq(LineRibbon.ERASE_STYLE.night_light, 1.0, "full colour at night")
	assert_eq(BridgeBrush.ERASE_TINT, BrushCursor.CLEAR_TINT, "the bridge's erase")
	var salmon := BrushCursor.CLEAR_TINT
	assert_gt(salmon.r, salmon.g, "still a salmon: warm")
	assert_gt(salmon.g, salmon.b * 0.98, "toward chalk-pink, not rose")
	for lay: Color in [ThinBrush.THIN_TINT, PaintBrush.new().tint]:
		assert_gt(lay.g - salmon.g, 0.08, "apart from the cream and tan lay rings")
	for key: String in GROUNDS:
		var ground: Color = GROUNDS[key]
		var outline := _outline(ground)
		var on_ink := BackdropPaint.contrast(salmon, outline)
		var apart := maxf(BackdropPaint.contrast(salmon, ground), BackdropPaint.contrast(outline, ground))
		assert_gte(on_ink, 3.0, "on its ink over %s" % key)
		assert_gte(apart, 3.0, "apart from %s" % key)


## The ink outline over `ground`: INK at INK_ALPHA blended over it.
func _outline(ground: Color) -> Color:
	var out := ground.lerp(ThemeColors.INK, BrushCursor.INK_ALPHA)
	out.a = 1.0
	return out
