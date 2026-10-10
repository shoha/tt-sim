extends GutTest

## The Painted Table themes (themes/painted_theme_base.gd) against docs/UI_TASTE.md: every role
## on both leaves, contrast for every text pair at the sizes used (C6: 4.5:1 for text, 3:1 for
## focus rings), glass checked composited over white and over black (C2), the quiet default
## Button with the fill only on Primary (C5, G2), the type scale (T1-T4) and tinted neutrals
## (C3).

const TEXT := 4.5
const GLYPH := 3.0
const WHITE := Color(1, 1, 1)
const BLACK := Color(0, 0, 0)

var paper: Theme
var glass: Theme


func before_all() -> void:
	paper = ThemeColors.paper_theme()
	glass = ThemeColors.glass_theme()


func test_both_leaves_carry_every_role() -> void:
	for role: StringName in ThemeColors.PAPER_ROLES:
		assert_true(ThemeColors.GLASS_ROLES.has(role), "glass maps %s" % role)
		assert_eq(paper.get_color(role, ThemeColors.TYPE), ThemeColors.PAPER_ROLES[role])
		assert_eq(glass.get_color(role, ThemeColors.TYPE), ThemeColors.GLASS_ROLES[role])


func test_no_token_is_a_pure_grey() -> void:
	for roles: Dictionary in [ThemeColors.PAPER_ROLES, ThemeColors.GLASS_ROLES]:
		for role: StringName in roles:
			var color: Color = roles[role]
			var grey := is_equal_approx(color.r, color.g) and is_equal_approx(color.g, color.b)
			assert_false(grey, "%s is tinted" % role)


func test_paper_text_pairs_hold_contrast() -> void:
	_check_pairs(ThemeColors.PAPER_ROLES, [WHITE])
	var tooltip := _contrast(ThemeColors.CHALK, ThemeColors.INK)
	assert_gt(tooltip, TEXT, "tooltip chalk on ink")


func test_glass_text_pairs_hold_contrast_over_white_and_black() -> void:
	_check_pairs(ThemeColors.GLASS_ROLES, [WHITE, BLACK])


func test_the_default_button_is_quiet_and_primary_is_the_fill() -> void:
	for theme: Theme in [paper, glass]:
		var roles := ThemeColors.PAPER_ROLES if theme == paper else ThemeColors.GLASS_ROLES
		var accent: Color = roles[ThemeColors.ACCENT]
		var normal := theme.get_stylebox("normal", "Button") as StyleBoxFlat
		var primary := theme.get_stylebox("normal", "Primary") as StyleBoxFlat
		assert_ne(normal.bg_color, accent, "an unthemed Button never takes the fill")
		assert_eq(primary.bg_color, accent, "Primary is the accent fill")
		assert_eq(theme.get_type_variation_base("Primary"), &"Button")
		for variation in ["Ghost", "Danger", "Secondary"]:
			assert_eq(theme.get_type_variation_base(variation), &"Button", variation)
		for variation in ["Sheet", "Inset"]:
			assert_eq(theme.get_type_variation_base(variation), &"PanelContainer", variation)
		var option := theme.get_stylebox("normal", "OptionButton") as StyleBoxFlat
		assert_ne(option.bg_color, accent, "a dropdown is a field, not a fill (G2)")


func test_every_interactive_type_has_a_drawn_focus_ring() -> void:
	for type in ["Button", "LineEdit", "OptionButton", "CheckBox", "CheckButton", "Card", "Tile"]:
		var focus := paper.get_stylebox("focus", type) as StyleBoxFlat
		assert_not_null(focus, "%s focus is a drawn ring, not StyleBoxEmpty (I1)" % type)


func test_type_scale() -> void:
	assert_eq(paper.default_font_size, 16, "the default Label is body 16 (T4)")
	assert_eq(paper.get_font_size("font_size", "Label"), 16)
	var sizes := {Wordmark = 56, Title = 26, Heading = 19, Caption = 14}
	for type: String in sizes:
		assert_eq(paper.get_font_size("font_size", type), sizes[type], type)
	assert_eq(paper.get_font_size("font_size", "Button"), 15, "buttons take the label size")
	var title := paper.get_font("font", "Title") as FontVariation
	var ts := TextServerManager.get_primary_interface()
	assert_eq(title.variation_opentype.get(ts.name_to_tag("SOFT")), 100.0, "Fraunces SOFT 100")
	assert_eq(title.variation_opentype.get(ts.name_to_tag("opsz")), 26.0, "opsz set per role")


func _check_pairs(roles: Dictionary, grounds: Array) -> void:
	# Text, captions and the focus ring sit on every surface; state, danger and success text
	# on sheets, raised controls and hovered rows (not inside field wells).
	var everywhere := [[ThemeColors.TEXT, TEXT], [ThemeColors.TEXT_SOFT, TEXT]]
	everywhere.append([ThemeColors.FOCUS, GLYPH])
	var on_sheets := [[ThemeColors.STATE, TEXT], [ThemeColors.DANGER, TEXT]]
	on_sheets.append([ThemeColors.SUCCESS, TEXT])
	var pairs_by_surface := {
		ThemeColors.SURFACE: everywhere + on_sheets,
		ThemeColors.SURFACE_RAISED: everywhere + on_sheets,
		ThemeColors.SURFACE_HOVER: everywhere + on_sheets,
		ThemeColors.SURFACE_PRESS: everywhere,
		ThemeColors.SURFACE_INSET: everywhere,
	}
	for ground: Color in grounds:
		for surface: StringName in pairs_by_surface:
			var back := _over(roles[surface], ground)
			for pair: Array in pairs_by_surface[surface]:
				var ratio := _contrast(roles[pair[0]], back)
				assert_gt(ratio, pair[1], "%s on %s: %.2f" % [pair[0], surface, ratio])
	var fills := [
		[ThemeColors.ON_ACCENT, ThemeColors.ACCENT],
		[ThemeColors.ON_ACCENT, ThemeColors.ACCENT_HOVER],
		[ThemeColors.ON_ACCENT, ThemeColors.ACCENT_PRESS],
		[ThemeColors.ON_STATE, ThemeColors.STATE],
		[ThemeColors.ON_STATE, ThemeColors.STATE_HOVER],
		[ThemeColors.ON_STATE, ThemeColors.STATE_PRESS],
		[ThemeColors.ON_DANGER, ThemeColors.DANGER_FILL],
	]
	for pair: Array in fills:
		var ratio := _contrast(roles[pair[0]], roles[pair[1]])
		assert_gt(ratio, TEXT, "%s on %s: %.2f" % [pair[0], pair[1], ratio])
	var ink_on_warning := _contrast(ThemeColors.INK, roles[ThemeColors.WARNING])
	assert_gt(ink_on_warning, TEXT, "ink on the warning chip: %.2f" % ink_on_warning)


## `color` composited over an opaque `ground`.
func _over(color: Color, ground: Color) -> Color:
	return Color(
		lerpf(ground.r, color.r, color.a),
		lerpf(ground.g, color.g, color.a),
		lerpf(ground.b, color.b, color.a),
		1.0
	)


## WCAG 2.x contrast ratio of two opaque colours.
func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
