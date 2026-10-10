@tool
extends "res://themes/painted_theme_kit.gd"

## The engine controls of the Painted Table themes: fields, toggles, ranges, tabs, popups,
## tooltips and lists (docs/UI_TASTE.md, "Engine surfaces are themed too"). Every control
## type here has normal, hover, pressed, disabled and focus styles (I1), so none falls back to
## Godot's default look or to the primary fill (G2). Colours are roles, so the same code
## draws paper and glass.

const _CHECK_BOX := '<rect x="2.75" y="2.75" width="14.5" height="14.5" rx="4"'
const _TICK := (
	'<path d="M6 10.2 L8.8 13 L14 7.4" fill="none" stroke-width="2"'
	+ ' stroke-linecap="round" stroke-linejoin="round"'
)


## Fields: an inset well with text-colour text, a soft placeholder and the focus ring.
func define_fields() -> void:
	var well := box(c(ThemeColors.SURFACE_INSET), RADIUS_CONTROL, 12, CONTROL_PAD_V)
	var read_only: Dictionary = inherit(well, {bg_color = c(ThemeColors.SURFACE_HOVER)})
	var text_colors := {
		font = font_body,
		font_size = SIZE_BODY,
		font_color = c(ThemeColors.TEXT),
		font_selected_color = c(ThemeColors.TEXT),
		font_placeholder_color = c(ThemeColors.TEXT_SOFT),
		caret_color = c(ThemeColors.TEXT),
		selection_color = Color(c(ThemeColors.STATE), 0.3),
	}
	define_style(
		"LineEdit",
		inherit(
			text_colors,
			{
				normal = well,
				focus = ring(),
				read_only = read_only,
				font_uneditable_color = c(ThemeColors.TEXT_SOFT),
				clear_button_color = c(ThemeColors.TEXT_SOFT),
				clear_button_color_pressed = c(ThemeColors.TEXT),
			}
		)
	)
	define_style(
		"TextEdit",
		inherit(
			text_colors,
			{
				normal = well,
				focus = ring(),
				read_only = read_only,
				font_readonly_color = c(ThemeColors.TEXT_SOFT),
			}
		)
	)
	define_variant_style(
		"ValueChip",
		"LineEdit",
		{
			font_size = SIZE_CAPTION,
			normal = box(c(ThemeColors.SURFACE_INSET), RADIUS_CHIP, SPACE_1, 2),
			focus = ring(RADIUS_CHIP),
		}
	)
	var hover: Dictionary = inherit(well, {bg_color = c(ThemeColors.SURFACE_HOVER)})
	var option := {
		normal = well,
		hover = hover,
		pressed = hover,
		disabled = inherit(well, {bg_color = Color(c(ThemeColors.SURFACE_INSET), 0.5)}),
		focus = ring(),
		font = font_body,
		font_size = SIZE_BODY,
		font_color = c(ThemeColors.TEXT),
		font_hover_color = c(ThemeColors.TEXT),
		font_pressed_color = c(ThemeColors.TEXT),
		font_hover_pressed_color = c(ThemeColors.TEXT),
		font_focus_color = c(ThemeColors.TEXT),
		font_disabled_color = c(ThemeColors.TEXT_SOFT),
		modulate_arrow = 1,
		arrow_margin = 12,
	}
	define_style("OptionButton", option)
	var soft := c(ThemeColors.TEXT_SOFT)
	var strong := c(ThemeColors.TEXT)
	define_style(
		"SpinBox",
		{
			up_icon_modulate = soft,
			up_hover_icon_modulate = strong,
			up_pressed_icon_modulate = strong,
			up_disabled_icon_modulate = Color(soft, 0.5),
			down_icon_modulate = soft,
			down_hover_icon_modulate = strong,
			down_pressed_icon_modulate = strong,
			down_disabled_icon_modulate = Color(soft, 0.5),
			up_background_hovered = box(c(ThemeColors.SURFACE_HOVER), RADIUS_CHIP),
			up_background_pressed = box(c(ThemeColors.SURFACE_INSET), RADIUS_CHIP),
			down_background_hovered = box(c(ThemeColors.SURFACE_HOVER), RADIUS_CHIP),
			down_background_pressed = box(c(ThemeColors.SURFACE_INSET), RADIUS_CHIP),
		}
	)


## CheckBox and CheckButton (the switch): drawn icons in the state role when on; off is the
## soft text outline (the check) or the filled track role (the switch), so the off state
## still reads at 3:1 (C6). icon_max_width is 0 here: both inherit Button's 20 px cap,
## which CheckButton applies to its switch and drew it as a 20x11 hairline.
func define_toggles() -> void:
	var plain := box(Color(c(ThemeColors.SURFACE), 0.0), RADIUS_CONTROL, SPACE_1, SPACE_1)
	var hover: Dictionary = inherit(plain, {bg_color = c(ThemeColors.SURFACE_HOVER)})
	var base := {
		normal = plain,
		hover = hover,
		pressed = plain,
		hover_pressed = hover,
		disabled = plain,
		focus = ring(),
		font = font_body,
		font_size = SIZE_BODY,
		font_color = c(ThemeColors.TEXT),
		font_hover_color = c(ThemeColors.TEXT),
		font_pressed_color = c(ThemeColors.TEXT),
		font_hover_pressed_color = c(ThemeColors.TEXT),
		font_focus_color = c(ThemeColors.TEXT),
		font_disabled_color = c(ThemeColors.TEXT_SOFT),
		h_separation = SPACE_2,
		icon_max_width = 0,
	}
	var on := _switch(true, 1.0)
	var off := _switch(false, 1.0)
	var on_disabled := _switch(true, 0.45)
	var off_disabled := _switch(false, 0.45)
	define_style(
		"CheckButton",
		inherit(
			base,
			{
				checked = on,
				unchecked = off,
				checked_disabled = on_disabled,
				unchecked_disabled = off_disabled,
				checked_mirrored = on,
				unchecked_mirrored = off,
				checked_disabled_mirrored = on_disabled,
				unchecked_disabled_mirrored = off_disabled,
				button_checked_color = Color.WHITE,
				button_unchecked_color = Color.WHITE,
			}
		)
	)
	define_style(
		"CheckBox",
		inherit(
			base,
			{
				checked = check_icon(true, false, 1.0),
				unchecked = check_icon(false, false, 1.0),
				checked_disabled = check_icon(true, false, 0.45),
				unchecked_disabled = check_icon(false, false, 0.45),
				radio_checked = check_icon(true, true, 1.0),
				radio_unchecked = check_icon(false, true, 1.0),
				radio_checked_disabled = check_icon(true, true, 0.45),
				radio_unchecked_disabled = check_icon(false, true, 0.45),
				checkbox_checked_color = Color.WHITE,
				checkbox_unchecked_color = Color.WHITE,
			}
		)
	)


## Sliders, progress bars and scroll bars: a slider's pill track in the track role (3:1, so
## the unfilled part still reads), the fill and the knob in the state role (lake shows
## state, C5). The track is a 3 px rail under a 6 px fill. Godot draws both at the track
## stylebox's minimum height, so the track is 3 px and the fill's expand margins widen it
## 1.5 px each way.
func define_ranges() -> void:
	define_style("HSlider", _slider(false))
	define_style("VSlider", _slider(true))
	define_style(
		"ProgressBar",
		{
			background = box(c(ThemeColors.SURFACE_INSET), RADIUS_PILL),
			fill = box(c(ThemeColors.STATE), RADIUS_PILL),
			font_color = c(ThemeColors.TEXT),
			font_size = SIZE_CAPTION,
		}
	)
	# The grabber is opaque, in the track role at rest (3:1 on every surface of its leaf: ink
	# on paper, chalk on glass), deepening to the soft text role on hover and the text role
	# while dragged. A translucent grey read 1.7:1 over a midday sky.
	var thumb := box(c(ThemeColors.TRACK), RADIUS_PILL, 3, 3)
	var lane := box(Color(c(ThemeColors.SURFACE_INSET), 0.0), RADIUS_PILL, 3, 3)
	var bar := {
		scroll = lane,
		scroll_focus = lane,
		grabber = thumb,
		grabber_highlight = inherit(thumb, {bg_color = c(ThemeColors.TEXT_SOFT)}),
		grabber_pressed = inherit(thumb, {bg_color = c(ThemeColors.TEXT)}),
	}
	define_style("VScrollBar", bar)
	define_style("HScrollBar", bar)
	# A bar over the painted backdrop (the title's card list) sits on a strip of paper of its
	# own, so its grabber holds 3:1 against the paper in every mood rather than against a sky
	# that runs from midday white to night blue. Godot draws the grabber the bar's full width,
	# so its paper border is what keeps it in from the strip's sides.
	var strip := box(c(ThemeColors.SURFACE), RADIUS_PILL, 5, 5, edge(1, c(ThemeColors.EDGE)))
	var inked := edge(3, c(ThemeColors.SURFACE))
	define_variant_style(
		"CardGridBar",
		"VScrollBar",
		{
			scroll = strip,
			scroll_focus = strip,
			grabber = inherit(thumb, inked),
			grabber_highlight = inherit(thumb, inked, {bg_color = c(ThemeColors.TEXT_SOFT)}),
			grabber_pressed = inherit(thumb, inked, {bg_color = c(ThemeColors.TEXT)}),
		}
	)


## Tabs: label type, the soft text role at rest, and the selected tab underlined in the
## state role (the active tab is a state, not an action).
func define_tabs() -> void:
	var selected := box(
		Color(c(ThemeColors.SURFACE), 0.0),
		0,
		CONTROL_PAD_H,
		CONTROL_PAD_V,
		{border_color = c(ThemeColors.STATE), border_width_bottom = 2}
	)
	var unselected: Dictionary = inherit(
		selected, {border_color = Color(c(ThemeColors.STATE), 0.0)}
	)
	var hovered: Dictionary = inherit(
		unselected,
		{
			bg_color = c(ThemeColors.SURFACE_HOVER),
			corner_radius_top_left = RADIUS_CHIP,
			corner_radius_top_right = RADIUS_CHIP,
		}
	)
	var tabs := {
		tab_selected = selected,
		tab_unselected = unselected,
		tab_hovered = hovered,
		tab_disabled = unselected,
		tab_focus = ring(RADIUS_CHIP),
		font = font_label,
		font_size = SIZE_LABEL,
		font_selected_color = c(ThemeColors.TEXT),
		font_hovered_color = c(ThemeColors.TEXT),
		font_unselected_color = c(ThemeColors.TEXT_SOFT),
		font_disabled_color = Color(c(ThemeColors.TEXT_SOFT), 0.6),
		icon_selected_color = c(ThemeColors.STATE),
		icon_hovered_color = c(ThemeColors.TEXT),
		icon_unselected_color = c(ThemeColors.TEXT_SOFT),
	}
	define_style("TabBar", tabs)
	define_style(
		"TabContainer",
		inherit(tabs, {panel = box(Color(c(ThemeColors.SURFACE), 0.0), 0), side_margin = 0})
	)


## PopupMenu, tooltips and engine windows: a raised surface with the edge line; hover is
## the inset wash. Popups draw no shadow (a popup window clips it).
func define_popups() -> void:
	var raised := c(ThemeColors.SURFACE_RAISED)
	if on_glass:
		raised = Color(raised, 0.98)
	var panel := box(raised, RADIUS_CONTROL, SPACE_2, SPACE_2, edge(1, c(ThemeColors.EDGE)))
	define_style(
		"PopupMenu",
		{
			panel = panel,
			hover = box(c(ThemeColors.SURFACE_HOVER), RADIUS_CHIP),
			separator = {type = "stylebox_line", color = c(ThemeColors.EDGE), thickness = DIVIDER},
			font = font_body,
			font_size = SIZE_BODY,
			font_color = c(ThemeColors.TEXT),
			font_hover_color = c(ThemeColors.TEXT),
			font_accelerator_color = c(ThemeColors.TEXT_SOFT),
			font_disabled_color = Color(c(ThemeColors.TEXT_SOFT), 0.7),
			font_separator_color = c(ThemeColors.TEXT_SOFT),
			checked = check_icon(true, false, 1.0),
			unchecked = check_icon(false, false, 1.0),
			radio_checked = check_icon(true, true, 1.0),
			radio_unchecked = check_icon(false, true, 1.0),
			v_separation = SPACE_2,
			h_separation = SPACE_2,
			item_start_padding = SPACE_2,
			item_end_padding = SPACE_3,
		}
	)
	# A tooltip is a dark ink chip on paper and a raised chip on glass: chalk text either way.
	var tip_bg := ThemeColors.INK if not on_glass else Color(ThemeColors.GLASS_RAISED, 0.98)
	define_style("TooltipPanel", {panel = box(tip_bg, RADIUS_CHIP, SPACE_3, SPACE_2)})
	define_style(
		"TooltipLabel", {font = font_body, font_size = SIZE_CAPTION, font_color = ThemeColors.CHALK}
	)
	var window_border := box(
		c(ThemeColors.SURFACE),
		RADIUS_CONTROL,
		0,
		0,
		{
			expand_margin_left = 8,
			expand_margin_top = 32,
			expand_margin_right = 8,
			expand_margin_bottom = 8,
		}
	)
	define_style(
		"Window",
		{
			embedded_border = window_border,
			embedded_unfocused_border = window_border,
			title_color = c(ThemeColors.TEXT),
			title_font = font_label,
		}
	)
	define_style(
		"AcceptDialog", {panel = box(c(ThemeColors.SURFACE), 0, SHEET_PADDING, SHEET_PADDING)}
	)


## Tree and ItemList: an inset well; selection is the selected fill with its on-colour text.
func define_lists() -> void:
	var selected := box(c(ThemeColors.SELECTED), RADIUS_CHIP)
	var hovered := box(c(ThemeColors.SURFACE_HOVER), RADIUS_CHIP)
	var well := box(c(ThemeColors.SURFACE_INSET), RADIUS_CONTROL, SPACE_2, SPACE_2)
	var empty := {type = "stylebox_empty"}
	define_style(
		"Tree",
		{
			panel = well,
			focus = empty,
			selected = selected,
			selected_focus = selected,
			hovered = hovered,
			hovered_selected = selected,
			hovered_selected_focus = selected,
			font_color = c(ThemeColors.TEXT),
			font_hovered_color = c(ThemeColors.TEXT),
			font_selected_color = c(ThemeColors.ON_SELECTED),
			guide_color = Color(c(ThemeColors.TEXT_SOFT), 0.3),
			relationship_line_color = Color(c(ThemeColors.TEXT_SOFT), 0.5),
			parent_hl_line_color = c(ThemeColors.TEXT_SOFT),
			children_hl_line_color = c(ThemeColors.TEXT_SOFT),
		}
	)
	define_style(
		"ItemList",
		{
			panel = well,
			focus = empty,
			selected = selected,
			selected_focus = selected,
			hovered = hovered,
			hovered_selected = selected,
			hovered_selected_focus = selected,
			font_color = c(ThemeColors.TEXT),
			font_hovered_color = c(ThemeColors.TEXT),
			font_selected_color = c(ThemeColors.ON_SELECTED),
			font_hovered_selected_color = c(ThemeColors.ON_SELECTED),
		}
	)


## A 20 px check box (or radio when `radio`): on is the state fill with an on-colour tick,
## off an outline in the soft text role. `alpha` dims the disabled pair.
func check_icon(checked: bool, radio: bool, alpha: float) -> ImageTexture:
	var fill := ThemeColors.STATE if checked else ThemeColors.SURFACE_RAISED
	var line := ThemeColors.STATE if checked else ThemeColors.TEXT_SOFT
	var colours := "%s %s" % [paint("fill", fill, alpha), paint("stroke", line, alpha)]
	var outline := '<circle cx="10" cy="10" r="8.25"' if radio else _CHECK_BOX
	var body := '%s %s stroke-width="1.5"/>' % [outline, colours]
	if checked and radio:
		body += '<circle cx="10" cy="10" r="3.5" %s/>' % paint("fill", ThemeColors.ON_STATE, alpha)
	elif checked:
		body += '%s %s/>' % [_TICK, paint("stroke", ThemeColors.ON_STATE, alpha)]
	return svg_icon(20, 20, body)


## The 36x20 switch, a filled pill in both states so each holds 3:1 against the surface:
## on is the state role with the knob at the right, off the track role with the knob at the
## left. The knob is the on-state colour either way, so only its place and the track change.
func _switch(checked: bool, alpha: float) -> ImageTexture:
	var track_role := ThemeColors.STATE if checked else ThemeColors.TRACK
	var track := '<rect x="0" y="0" width="36" height="20" rx="10" %s/>'
	var knob := '<circle cx="%d" cy="10" r="7" %s/>'
	var knob_x := 26 if checked else 10
	return svg_icon(
		36,
		20,
		(
			track % paint("fill", track_role, alpha)
			+ knob % [knob_x, paint("fill", ThemeColors.ON_STATE, alpha)]
		)
	)


## A slider's items: the 3 px track rail, the 6 px fill over it and the knob, laid across
## (`vertical` false) or up.
func _slider(vertical: bool) -> Dictionary:
	var across := ["top", "bottom"] if not vertical else ["left", "right"]
	var rail := {}
	var widen := {}
	for side: String in across:
		rail["content_margin_" + side] = 1.5
		widen["expand_margin_" + side] = 1.5
	var fill := box(c(ThemeColors.STATE), RADIUS_PILL, 0, 0, widen)
	return {
		slider = box(c(ThemeColors.TRACK), RADIUS_PILL, 0, 0, rail),
		grabber_area = fill,
		grabber_area_highlight = inherit(fill, {bg_color = c(ThemeColors.STATE_HOVER)}),
		grabber = _knob(ThemeColors.STATE, 1.0),
		grabber_highlight = _knob(ThemeColors.STATE_HOVER, 1.0),
		grabber_disabled = _knob(ThemeColors.TEXT_SOFT, 0.5),
	}


## The 20 px slider knob: a raised disc with a ring in `role`.
func _knob(role: StringName, alpha: float) -> ImageTexture:
	var disc := '<circle cx="10" cy="10" r="7.5" %s %s stroke-width="3"/>'
	var fill := paint("fill", ThemeColors.SURFACE_RAISED, 1.0)
	return svg_icon(20, 20, disc % [fill, paint("stroke", role, alpha)])
