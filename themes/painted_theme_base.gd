@tool
extends "res://themes/painted_theme_controls.gd"

## The Painted Table theme (docs/UI_TASTE.md; the 2026-10-09 theme recommendation): menus
## are paper cards on a sunlit table, and in play the table is the picture, so overlays step
## back as dark glass. One rule decides which: if it stops play it is paper, if play continues
## under it it is glass. This script defines every control once from colour roles; the two
## leaves pick the role map (ThemeColors.PAPER_ROLES or GLASS_ROLES) and a save path:
##
## - paper_theme.gd -> generated/paper_theme.tres, the project default (theme/custom).
## - glass_theme.gd -> generated/glass_theme.tres, set on every in-play UI root
##   (ThemeColors.glass_theme(); tests/unit/test_glass_roots.gd walks them).
##
## Saving a leaf regenerates its theme in the editor (UPDATE_ON_SAVE); after editing this
## file, the kit or the controls file, run tools/regen_theme.gd, which rebuilds both.
##
## Buttons: the default Button is the quiet secondary, so an unthemed control can never
## inherit the persimmon fill (C5, G2). `Primary` is the one fill per screen, `Danger` the
## danger-confirm fill, `Ghost` the tertiary with no fill. Panels: the default PanelContainer
## is a `Sheet`; `Inset` is a recessed well.


func define_theme() -> void:
	build_fonts()
	define_default_font(font_body)
	define_default_font_size(SIZE_BODY)
	_define_roles()
	_define_labels()
	_define_buttons()
	_define_flat_buttons()
	_define_panels()
	define_fields()
	define_toggles()
	define_ranges()
	define_tabs()
	define_popups()
	define_lists()
	_define_containers()
	_define_status()


## The role table as colour items of type ThemeColors.TYPE, for ThemeColors.of(), and the
## spacing scale as constants of type "Space" (S1).
func _define_roles() -> void:
	for role: StringName in roles:
		current_theme.set_color(role, ThemeColors.TYPE, roles[role])
	var space := {
		space_1 = SPACE_1,
		space_2 = SPACE_2,
		space_3 = SPACE_3,
		space_4 = SPACE_4,
		space_5 = SPACE_5,
		space_6 = SPACE_6,
		sheet_padding = SHEET_PADDING,
		row = ROW_HEIGHT,
		control = CONTROL_HEIGHT,
	}
	for key: String in space:
		current_theme.set_constant(key, &"Space", space[key])


## Labels: the default is body 16 (T4). Fraunces only for the wordmark, titles, headings and
## eyebrows (T3); captions are their own solid soft role, never a dimmed text colour (C2).
func _define_labels() -> void:
	var text := c(ThemeColors.TEXT)
	var soft := c(ThemeColors.TEXT_SOFT)
	define_style(
		"Label",
		{font = font_body, font_size = SIZE_BODY, font_color = text, line_spacing = 2},
	)
	var title := {font = font_title, font_size = SIZE_TITLE, font_color = text}
	var heading := {font = font_heading, font_size = SIZE_HEADING, font_color = text}
	var caption := {font = font_body, font_size = SIZE_CAPTION, font_color = soft}
	define_variant_style(
		"Wordmark", "Label", {font = font_wordmark, font_size = SIZE_WORDMARK, font_color = text}
	)
	define_variant_style("Title", "Label", title)
	define_variant_style("Heading", "Label", heading)
	define_variant_style(
		"Eyebrow", "Label", {font = font_eyebrow, font_size = SIZE_HEADING, font_color = soft}
	)
	define_variant_style("Body", "Label", {font = font_body, font_size = SIZE_BODY})
	define_variant_style("Caption", "Label", caption)
	# A value that differs from its default reads in the state role (lake: cool means is).
	var in_state := {font_color = c(ThemeColors.STATE)}
	define_variant_style(
		"BodyState", "Label", inherit({font = font_body, font_size = SIZE_BODY}, in_state)
	)
	define_variant_style("CaptionState", "Label", inherit(caption, in_state))
	# A code someone reads aloud (the room code): never Fraunces, whose 0, o, 1 and l blur.
	define_variant_style("Code", "Label", {font = font_code, font_size = SIZE_HEADING})
	# Names the earlier scenes use, kept as aliases of the roles above.
	define_variant_style("H1", "Label", title)
	define_variant_style("H2", "Label", heading)
	define_variant_style("H3", "Label", {font = font_strong, font_size = SIZE_BODY})
	# H3 with tabular figures, for a count that ticks in place: the line around it never moves.
	define_variant_style("Count", "Label", {font = font_count, font_size = SIZE_BODY})
	define_variant_style("SectionHeader", "Label", heading)
	define_variant_style("PanelHeader", "Label", heading)
	define_variant_style("RailLabel", "Label", caption)


## The default Button (the quiet secondary) and its filled and quiet variations. Every fill
## keeps 4.5:1 for its label in every state: hovers only deepen (C6).
func _define_buttons() -> void:
	var raised := box(
		c(ThemeColors.SURFACE_RAISED),
		RADIUS_CONTROL,
		CONTROL_PAD_H,
		CONTROL_PAD_V,
		inherit(edge(1, c(ThemeColors.EDGE)), lift())
	)
	if on_glass:
		raised = box(
			c(ThemeColors.SURFACE_RAISED),
			RADIUS_CONTROL,
			CONTROL_PAD_H,
			CONTROL_PAD_V,
			edge(1, Color(c(ThemeColors.TEXT_SOFT), 0.35))
		)
	var secondary := _button(
		raised,
		inherit(raised, {bg_color = c(ThemeColors.SURFACE_HOVER)}),
		inherit(raised, {bg_color = c(ThemeColors.SURFACE_PRESS), shadow_size = 0}),
		ThemeColors.TEXT
	)
	define_style("Button", inherit(secondary, {icon_max_width = 20, h_separation = SPACE_2}))
	define_variant_style("Secondary", "Button", {})
	# The quiet button framed at 3:1 against what it sits on (the track role) in every state,
	# where the default's edge is a faint rim: a button on a chip of its own colour (the table
	# move's Stay here).
	var frame := edge(1, c(ThemeColors.TRACK))
	define_variant_style(
		"Framed",
		"Button",
		_button(
			inherit(raised, frame),
			inherit(raised, frame, {bg_color = c(ThemeColors.SURFACE_HOVER)}),
			inherit(raised, frame, {bg_color = c(ThemeColors.SURFACE_PRESS), shadow_size = 0}),
			ThemeColors.TEXT
		)
	)
	var primary := _filled(
		ThemeColors.ACCENT, ThemeColors.ACCENT_HOVER, ThemeColors.ACCENT_PRESS, ThemeColors.ON_ACCENT
	)
	define_variant_style("Primary", "Button", primary)
	# Madder has one step: the press reads through the dropped shadow.
	var danger := ThemeColors.DANGER_FILL
	define_variant_style(
		"Danger", "Button", _filled(danger, danger, danger, ThemeColors.ON_DANGER)
	)
	var clear := Color(c(ThemeColors.SURFACE), 0.0)
	var bare := box(clear, RADIUS_CONTROL, CONTROL_PAD_H, CONTROL_PAD_V)
	define_variant_style(
		"Ghost",
		"Button",
		_button(
			bare,
			inherit(bare, {bg_color = c(ThemeColors.SURFACE_HOVER)}),
			inherit(bare, {bg_color = c(ThemeColors.SURFACE_PRESS)}),
			ThemeColors.TEXT_SOFT,
			ThemeColors.TEXT
		)
	)


## Flat icon buttons, tiles, cards and foldout headers (scenes/ui/primitives/). White SVG
## icons take the icon_*_color tints, so no per-instance colour code is needed.
func _define_flat_buttons() -> void:
	var flat := box(Color(c(ThemeColors.SURFACE), 0.0), RADIUS_CONTROL, 6, 6)
	var icon_button := _button(
		flat,
		inherit(flat, {bg_color = c(ThemeColors.SURFACE_HOVER)}),
		inherit(flat, {bg_color = c(ThemeColors.SURFACE_PRESS)}),
		ThemeColors.TEXT
	)
	icon_button.icon_pressed_color = c(ThemeColors.STATE)
	icon_button.icon_hover_pressed_color = c(ThemeColors.STATE)
	define_variant_style("IconButton", "Button", icon_button)
	var active: Dictionary = inherit(flat, {bg_color = c(ThemeColors.SURFACE_INSET)})
	define_variant_style(
		"IconButtonActive",
		"Button",
		inherit(
			icon_button,
			{
				normal = active,
				hover = inherit(active, {bg_color = c(ThemeColors.SURFACE_HOVER)}),
				icon_normal_color = c(ThemeColors.STATE),
				icon_hover_color = c(ThemeColors.STATE),
				icon_focus_color = c(ThemeColors.STATE),
			}
		)
	)
	# On a picture (a level card's overflow menu): the same button on a small raised disc with a
	# pencil edge, so its glyph reads over a dark thumbnail as over a light one.
	var disc := box(
		c(ThemeColors.SURFACE_RAISED), RADIUS_PILL, 4, 4, edge(1, c(ThemeColors.EDGE))
	)
	define_variant_style(
		"IconButtonDisc",
		"Button",
		_button(
			disc,
			inherit(disc, {bg_color = c(ThemeColors.SURFACE_HOVER)}),
			inherit(disc, {bg_color = c(ThemeColors.SURFACE_PRESS)}),
			ThemeColors.TEXT
		)
	)
	# Tiles: a centred label, so 4 px sides leave a long name (Grassland Meadow) its room in
	# a two-column drawer. Picked is the selected fill edge to edge, with no ring of its own:
	# the ring is focus (I1), so a picked tile that also has focus shows both, the fill and the
	# focus ring 4 px outside it.
	var tile := box(
		c(ThemeColors.SURFACE_RAISED), RADIUS_CONTROL, SPACE_1, SPACE_1, edge(1, c(ThemeColors.EDGE))
	)
	var picked: Dictionary = inherit(
		tile, {bg_color = c(ThemeColors.SELECTED), border_color = c(ThemeColors.SELECTED)}
	)
	var tile_style := _button(
		tile, inherit(tile, {bg_color = c(ThemeColors.SURFACE_HOVER)}), picked, ThemeColors.TEXT
	)
	for key: String in ["font_pressed_color", "font_hover_pressed_color"]:
		tile_style[key] = c(ThemeColors.ON_SELECTED)
	for key: String in ["icon_pressed_color", "icon_hover_pressed_color"]:
		tile_style[key] = c(ThemeColors.ON_SELECTED)
	var picked_hover := c(ThemeColors.SELECTED_HOVER)
	tile_style.hover_pressed = inherit(picked, {bg_color = picked_hover, border_color = picked_hover})
	tile_style.font_size = SIZE_CAPTION
	tile_style.icon_max_width = 24
	tile_style.h_separation = SPACE_1
	define_variant_style("Tile", "Button", tile_style)
	# A list row (the room's shelf maps): a row like a player row, not a tile, so no edge at
	# rest; the hover wash, and the selected fill edge to edge when picked.
	var list_row := box(Color(c(ThemeColors.SURFACE), 0.0), RADIUS_CONTROL, SPACE_1, SPACE_1)
	var row_picked: Dictionary = inherit(list_row, {bg_color = c(ThemeColors.SELECTED)})
	var row_style := _button(
		list_row,
		inherit(list_row, {bg_color = c(ThemeColors.SURFACE_HOVER)}),
		row_picked,
		ThemeColors.TEXT
	)
	for key: String in ["font_pressed_color", "font_hover_pressed_color"]:
		row_style[key] = c(ThemeColors.ON_SELECTED)
	row_style.hover_pressed = inherit(row_picked, {bg_color = c(ThemeColors.SELECTED_HOVER)})
	define_variant_style("ListRow", "Button", row_style)
	# Cards: equivalent items (levels, avatars) that lift on hover. A selected card says so in
	# its caption strip (CardStripSelected below), never with a ring: the ring is focus, so
	# a selected card with focus shows both.
	var card := box(
		c(ThemeColors.SURFACE),
		RADIUS_CARD,
		SPACE_1,
		SPACE_1,
		inherit(edge(1, c(ThemeColors.EDGE)), lift())
	)
	define_variant_style(
		"Card",
		"Button",
		{
			normal = card,
			hover = inherit(card, lift(true)),
			pressed = card,
			hover_pressed = inherit(card, lift(true)),
			disabled = inherit(card, {bg_color = c(ThemeColors.SURFACE_INSET), shadow_size = 0}),
			focus = ring(RADIUS_CARD),
		}
	)
	# The caption strip under a card's picture: clear at rest, the selected fill when the card
	# is selected, its top corners the well's bottom ones and its bottom corners concentric
	# with the card's (the card radius less its 4 px inset). The text on it takes ON_SELECTED.
	var strip := box(c(ThemeColors.SELECTED), RADIUS_CHIP)
	strip.corner_radius_bottom_left = RADIUS_CARD - SPACE_1
	strip.corner_radius_bottom_right = RADIUS_CARD - SPACE_1
	var clear_strip: Dictionary = inherit(strip, {bg_color = Color(c(ThemeColors.SELECTED), 0.0)})
	# A picture on its own card (the room's selected map, the title's empty library): a card's
	# paper and trim at rest, so a picture over the painted backdrop reads as a picture on
	# paper, not a hole in the sky.
	define_variant_style("PictureCard", "PanelContainer", {panel = card})
	define_variant_style("CardStrip", "PanelContainer", {panel = clear_strip})
	define_variant_style("CardStripSelected", "PanelContainer", {panel = strip})
	var on_selected := {font_color = c(ThemeColors.ON_SELECTED)}
	define_variant_style(
		"BodyOnSelected", "Label", inherit({font = font_body, font_size = SIZE_BODY}, on_selected)
	)
	define_variant_style(
		"CaptionOnSelected",
		"Label",
		inherit({font = font_body, font_size = SIZE_CAPTION}, on_selected)
	)
	# A card's thumbnail well: the paper-inset wash, its top corners concentric with the
	# card's (the card radius less its 4 px inset). The card clips its picture to this shape;
	# with no picture it holds the map's painted placeholder (MapPlaceholder).
	var well := box(c(ThemeColors.SURFACE_INSET), RADIUS_CARD - SPACE_1)
	well.corner_radius_bottom_left = RADIUS_CHIP
	well.corner_radius_bottom_right = RADIUS_CHIP
	define_variant_style("CardThumb", "Panel", {panel = well})
	define_variant_style(
		"FoldoutHeader",
		"Button",
		inherit(
			_button(flat, flat, flat, ThemeColors.TEXT_SOFT, ThemeColors.TEXT),
			{font = font_label, font_size = SIZE_LABEL, icon_max_width = 16, h_separation = SPACE_1}
		)
	)


## Panels: the default PanelContainer is a sheet (paper: radius 20, padding 24, the rest
## shadow; glass: radius 16, the top rim, padding 16). Sheets hold rows, never sheets (S2).
func _define_panels() -> void:
	var sheet := box(
		c(ThemeColors.SURFACE),
		RADIUS_SHEET,
		SHEET_PADDING,
		SHEET_PADDING,
		inherit(edge(1, c(ThemeColors.EDGE)), lift())
	)
	if on_glass:
		var glass_trim: Dictionary = inherit(rim(), lift())
		sheet = box(c(ThemeColors.SURFACE), RADIUS_CARD, GLASS_PADDING, GLASS_PADDING, glass_trim)
	var inset := box(c(ThemeColors.SURFACE_INSET), RADIUS_CONTROL, SPACE_3, SPACE_3)
	define_style("Panel", {panel = box(c(ThemeColors.SURFACE), RADIUS_CONTROL)})
	define_style("PanelContainer", {panel = sheet})
	define_variant_style("Sheet", "PanelContainer", {panel = sheet})
	# A plaque: a few words that stand on the painted backdrop (the room's heading and code row,
	# the map's name under its picture, the title's "Your maps") on paper of their own, the
	# sheet's surface and trim at a card's radius with a control's padding. Crisp, so the words
	# hold their contrast in every mood without a haze over the painting.
	var paper_trim: Dictionary = inherit(edge(1, c(ThemeColors.EDGE)), lift())
	var plaque := box(c(ThemeColors.SURFACE), RADIUS_CARD, SPACE_4, SPACE_2, paper_trim)
	if on_glass:
		plaque = box(c(ThemeColors.SURFACE), RADIUS_CARD, SPACE_3, SPACE_2, inherit(rim(), lift()))
	define_variant_style("Plaque", "PanelContainer", {panel = plaque})
	define_variant_style("Inset", "PanelContainer", {panel = inset})
	define_variant_style("PanelInset", "PanelContainer", {panel = inset})
	define_variant_style(
		"PanelElevated",
		"PanelContainer",
		{panel = box(c(ThemeColors.SURFACE_RAISED), RADIUS_CONTROL, SPACE_3, SPACE_3)}
	)
	define_variant_style(
		"PanelBordered",
		"PanelContainer",
		{
			panel =
			box(
				Color(c(ThemeColors.SURFACE), 0.0),
				RADIUS_CONTROL,
				SPACE_2,
				SPACE_2,
				edge(1, c(ThemeColors.EDGE))
			)
		}
	)
	define_variant_style(
		"KeyChip",
		"PanelContainer",
		{
			panel =
			box(
				c(ThemeColors.SURFACE_RAISED), RADIUS_CHIP, SPACE_2, 2, edge(1, c(ThemeColors.EDGE))
			)
		}
	)
	# A code someone reads aloud (the room code): a key chip with room around the Code label.
	var pencil := edge(1, c(ThemeColors.EDGE))
	var code_chip := box(c(ThemeColors.SURFACE_RAISED), RADIUS_CHIP, SPACE_3, 6, pencil)
	define_variant_style("CodeChip", "PanelContainer", {panel = code_chip})
	# The unsaved-changes dot: cool, because it says what is (C5: warm means do); the action
	# it points at (Save) keeps the warm fill. Its item's tooltip names the state in words.
	define_variant_style("Badge", "Panel", {panel = box(c(ThemeColors.STATE), RADIUS_PILL)})


func _define_containers() -> void:
	define_style("BoxContainer", {separation = SPACE_1})
	define_variant_style("BoxContainerTight", "BoxContainer", {separation = SPACE_1})
	define_variant_style("BoxContainerSpaced", "BoxContainer", {separation = SPACE_3})
	define_style(
		"MarginContainer",
		{margin_left = SPACE_2, margin_top = SPACE_2, margin_right = SPACE_2, margin_bottom = SPACE_2}
	)
	define_variant_style(
		"TabContentMargin",
		"MarginContainer",
		{margin_left = SPACE_4, margin_top = SPACE_3, margin_right = SPACE_4, margin_bottom = SPACE_3}
	)
	# A card's text block, inside the card's own 4 px inset: 12 px from its sides and bottom.
	define_variant_style(
		"CardText",
		"MarginContainer",
		{margin_left = SPACE_2, margin_top = SPACE_1, margin_right = SPACE_2, margin_bottom = SPACE_2}
	)
	# Dividers are DIVIDER thick: a 1 px line at 1280x720 falls under a physical pixel.
	var line := {type = "stylebox_line", color = c(ThemeColors.EDGE), thickness = DIVIDER}
	define_style("HSeparator", {separator = line, separation = SPACE_3})
	define_style("VSeparator", {separator = inherit(line, {vertical = true}), separation = SPACE_3})
	# A settings row: its label in one fixed column (PropertyRow.fit_sheet_row), 16 px to the
	# control.
	define_variant_style("PropertyRow", "HBoxContainer", {separation = SPACE_4})
	# A card grid scrolls, so it clips: its clear panel's margins keep the cards in from that
	# edge far enough for a focus ring (4 px outside a card) to draw whole.
	var ring_room := box(Color(c(ThemeColors.SURFACE), 0.0), 0, 6, 6)
	define_variant_style("CardGrid", "ScrollContainer", {panel = ring_room})


## Small status surfaces: chips that label the board (a ruler's distance, the input hints),
## the count badge, toasts and progress outcomes. On glass a chip is the glass surface with
## its top rim, never a black box (C4). Every toast is one surface with no side stripe (a
## stripe at rest is decoration); it carries its kind in a tinted icon and its words (C7):
## cool for information (lake, "is"), moss, ochre and madder for the outcomes; never the warm
## accent, which means "do" (C5).
func _define_status() -> void:
	var chip := box(c(ThemeColors.SURFACE), RADIUS_CHIP, SPACE_3, SPACE_1, rim())
	if not on_glass:
		var pencil := edge(1, c(ThemeColors.EDGE))
		chip = box(c(ThemeColors.SURFACE_RAISED), RADIUS_CHIP, SPACE_3, SPACE_1, pencil)
	define_variant_style("Chip", "PanelContainer", {panel = chip})
	define_variant_style(
		"CountBadge", "PanelContainer", {panel = box(c(ThemeColors.ACCENT), RADIUS_PILL, 6, 0)}
	)
	define_variant_style(
		"CountBadgeLabel",
		"Label",
		{font = font_strong, font_size = SIZE_CAPTION, font_color = c(ThemeColors.ON_ACCENT)}
	)
	var toast := box(c(ThemeColors.SURFACE), RADIUS_CONTROL, SPACE_3, SPACE_2, lift())
	define_variant_style("Toast", "PanelContainer", {panel = toast})
	for outcome: String in ["Success", "Danger"]:
		var role := ThemeColors.SUCCESS if outcome == "Success" else ThemeColors.DANGER
		define_variant_style(
			"Progress" + outcome, "ProgressBar", {fill = box(c(role), RADIUS_PILL)}
		)


## A button item set from its normal, hover and pressed boxes and a text role (`hover_text`
## for the hover and pressed text when it differs). Disabled is flat in the inset role with
## the soft text role; focus is the ring.
func _button(
	normal: Dictionary,
	hover: Dictionary,
	pressed: Dictionary,
	text: StringName,
	hover_text: StringName = &""
) -> Dictionary:
	var flat_disabled: Dictionary = inherit(
		normal, edge(0, c(ThemeColors.EDGE)), {bg_color = c(ThemeColors.SURFACE_INSET), shadow_size = 0}
	)
	var style := {
		normal = normal,
		hover = hover,
		pressed = pressed,
		hover_pressed = pressed,
		disabled = flat_disabled,
		focus = ring(),
		font = font_label,
		font_size = SIZE_LABEL,
	}
	style.merge(_on_colours(text), true)
	if hover_text != &"":
		for state: String in ["hover_", "pressed_", "hover_pressed_"]:
			style["font_%scolor" % state] = c(hover_text)
			style["icon_%scolor" % state] = c(hover_text)
	return style


## A filled button in `rest`, `hover` and `press` with `on` text and icons.
func _filled(rest: StringName, hover: StringName, press: StringName, on: StringName) -> Dictionary:
	var fill := box(c(rest), RADIUS_CONTROL, CONTROL_PAD_H, CONTROL_PAD_V, lift())
	if on_glass:
		fill = box(c(rest), RADIUS_CONTROL, CONTROL_PAD_H, CONTROL_PAD_V)
	var style := _button(
		fill,
		inherit(fill, {bg_color = c(hover)}),
		inherit(fill, {bg_color = c(press), shadow_size = 0}),
		on
	)
	style.font = font_strong
	return style


## Font and icon colours in `role` for every state but disabled, which takes the soft text
## role.
func _on_colours(role: StringName) -> Dictionary:
	var color := c(role)
	var colours := {}
	for state: String in ["", "hover_", "pressed_", "hover_pressed_", "focus_"]:
		colours["font_%scolor" % state] = color
		colours["icon_%s" % ("normal_color" if state == "" else state + "color")] = color
	colours.font_disabled_color = c(ThemeColors.TEXT_SOFT)
	colours.icon_disabled_color = c(ThemeColors.TEXT_SOFT)
	return colours
