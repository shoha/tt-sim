@tool
extends ProgrammaticTheme

## The pieces the Painted Table themes are built from: size tokens, fonts, StyleBoxFlat
## helpers and the small icons drawn from role colours. painted_theme_controls.gd and
## painted_theme_base.gd define the controls with these; the two leaves (paper_theme.gd,
## glass_theme.gd) only pick a role map from ThemeColors and a save path. Sizes are 1080p
## virtual px (docs/UI_TASTE.md T1, S1, S6).
##
## Fraunces is a variable font with custom axes SOFT (0-100) and WONK (0-1) beside opsz
## (9-144) and wght. FontVariation only honours a custom axis keyed by its int tag
## (TextServer.name_to_tag), and there is no automatic optical size: every Fraunces role sets
## opsz to its own size, or it renders at opsz 9, heavier and wider.

const INTER := preload("res://assets/fonts/Inter-VariableFont_opsz,wght.ttf")
const FRAUNCES := preload("res://assets/fonts/fraunces/Fraunces-Variable.ttf")
const FRAUNCES_ITALIC := preload("res://assets/fonts/fraunces/Fraunces-Italic-Variable.ttf")

# Spacing scale (S1)
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 24
const SPACE_6 := 32
const SHEET_PADDING := 24
const GLASS_PADDING := 16
const ROW_HEIGHT := 44
const CONTROL_HEIGHT := 40

# Radii
const RADIUS_CHIP := 6
const RADIUS_CONTROL := 10
const RADIUS_CARD := 16
const RADIUS_SHEET := 20
## StyleBoxFlat clamps a radius to half the box, so this draws a pill at any height.
const RADIUS_PILL := 64

# Type scale (T1)
const SIZE_WORDMARK := 56
const SIZE_TITLE := 26
const SIZE_HEADING := 19
const SIZE_BODY := 16
const SIZE_LABEL := 15
const SIZE_CAPTION := 14

## Button and field padding: a 15 px label line plus these is CONTROL_HEIGHT tall.
const CONTROL_PAD_H := 16
const CONTROL_PAD_V := 10

## The role map in use (ThemeColors.PAPER_ROLES or GLASS_ROLES), set by the leaf.
var roles: Dictionary = ThemeColors.PAPER_ROLES
## Light text on glass gets a little more weight (T5).
var on_glass := false

var font_body: FontVariation
var font_label: FontVariation
var font_strong: FontVariation
var font_wordmark: FontVariation
var font_title: FontVariation
var font_heading: FontVariation
var font_eyebrow: FontVariation
## Codes read aloud (the room code): Inter with tabular figures, a slashed zero and the
## disambiguation set (a tailed l, a flagged 1), so 0/o and 1/l/i never pass for each other.
var font_code: FontVariation


## Picks the role map and weights for the theme about to be generated.
func use_roles(role_map: Dictionary, glass: bool) -> void:
	roles = role_map
	on_glass = glass


## The colour `role` maps to in this theme.
func c(role: StringName) -> Color:
	return roles[role]


## Builds this theme's fonts once, so every item shares one FontVariation per role.
func build_fonts() -> void:
	var lift := 50.0 if on_glass else 0.0
	font_body = inter(400.0 + lift)
	font_label = inter(500.0 + lift)
	font_strong = inter(600.0 + lift)
	font_wordmark = fraunces(650.0, 144.0)
	font_title = fraunces(600.0, SIZE_TITLE)
	font_heading = fraunces(600.0, SIZE_HEADING)
	font_eyebrow = fraunces(500.0 + lift, SIZE_HEADING, true)
	font_code = inter(600.0 + lift, ["tnum", "zero", "ss02", "cv05"])
	font_code.spacing_glyph = 1


## Inter at a weight, with OpenType `features` (four-letter tags) switched on.
func inter(wght: float, features: Array[String] = []) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = INTER
	font.variation_opentype = {_tag("wght"): wght}
	var switched := {}
	for feature in features:
		switched[_tag(feature)] = 1
	font.opentype_features = switched
	return font


## Fraunces at a weight and optical size, SOFT 100 (the storybook terminals), WONK left at
## its default.
func fraunces(wght: float, opsz: float, italic := false) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = FRAUNCES_ITALIC if italic else FRAUNCES
	font.variation_opentype = {_tag("SOFT"): 100.0, _tag("wght"): wght, _tag("opsz"): opsz}
	return font


## A StyleBoxFlat item: `bg` fill, `radius` corners, content margins `pad_h` and `pad_v`,
## then `extra` on top (edge(), lift(), ring() and plain keys).
func box(bg: Color, radius: int, pad_h := 0, pad_v := 0, extra := {}) -> Dictionary:
	var style := {
		type = "stylebox_flat",
		bg_color = bg,
		corner_radius_top_left = radius,
		corner_radius_top_right = radius,
		corner_radius_bottom_right = radius,
		corner_radius_bottom_left = radius,
		content_margin_left = pad_h,
		content_margin_right = pad_h,
		content_margin_top = pad_v,
		content_margin_bottom = pad_v,
		anti_aliasing_size = 0.7,
	}
	style.merge(extra, true)
	return style


## A border of `width` px in `color` on every side.
func edge(width: int, color: Color) -> Dictionary:
	return {
		border_color = color,
		border_width_left = width,
		border_width_top = width,
		border_width_right = width,
		border_width_bottom = width,
	}


## The glass top rim: one line of the edge role along the top only.
func rim() -> Dictionary:
	return {border_color = c(ThemeColors.EDGE), border_width_top = 1}


## The rest shadow (cards and sheets at rest), or the lifted one (hovered cards). Glass has
## one shadow, from its role.
func lift(lifted := false) -> Dictionary:
	if on_glass:
		return {shadow_color = c(ThemeColors.SHADOW), shadow_size = 12}
	if lifted:
		return {
			shadow_color = ThemeColors.SHADOW_LIFTED,
			shadow_size = 18,
			shadow_offset = Vector2(0, 8),
		}
	return {shadow_color = ThemeColors.SHADOW_REST, shadow_size = 10, shadow_offset = Vector2(0, 4)}


## The focus ring (I1): 2 px in the focus role, 2 px outside a control of `radius`. A glass
## control can sit straight on the board (the HUD's Add Token), where lake_light alone falls
## under 3:1 on bright grass, so the glass ring carries a soft plum-black halo outside it.
## With draw_center off, StyleBoxFlat draws only the outer falloff of a shadow, never a fill
## over the control.
func ring(radius: int = RADIUS_CONTROL) -> Dictionary:
	var halo := {}
	if on_glass:
		halo = {shadow_color = Color(ThemeColors.SHADOW_GLASS, 0.8), shadow_size = 4}
	return box(
		Color(c(ThemeColors.FOCUS), 0.0),
		radius + 4,
		0,
		0,
		inherit(
			edge(2, c(ThemeColors.FOCUS)),
			{
				draw_center = false,
				expand_margin_left = 4,
				expand_margin_top = 4,
				expand_margin_right = 4,
				expand_margin_bottom = 4,
			},
			halo
		)
	)


## An icon `width` x `height` px drawn from SVG `body` markup at 1x. Colours come in through
## paint(), so each theme draws its own switch, check and knob from its roles.
func svg_icon(width: int, height: int, body: String) -> ImageTexture:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">%s</svg>'
	var image := Image.new()
	var err := image.load_svg_from_string(svg % [width, height, body], 1.0)
	if err != OK:
		push_error("painted theme: icon SVG did not parse")
		return null
	return ImageTexture.create_from_image(image)


## `role` as an SVG paint and opacity pair: `fill="#rrggbb" fill-opacity="a"` style text
## for attribute `attr` ("fill" or "stroke").
func paint(attr: String, role: StringName, alpha := 1.0) -> String:
	var color := c(role)
	return '%s="#%s" %s-opacity="%.3f"' % [attr, color.to_html(false), attr, color.a * alpha]


func _tag(axis: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(axis)
