@tool
extends ProgrammaticTheme

const UPDATE_ON_SAVE = true
const inter_font = preload("res://assets/fonts/Inter-VariableFont_opsz,wght.ttf")

# =============================================================================
# SEMANTIC COLOR PALETTE
# =============================================================================
# These base colors define the theme's identity. All other colors derive from these.

const COLOR_ADJUSTMENT: float = 0.2

# -- Core Background Colors --
const color_background: Color = Color("#1a121a") # Deepest background (inputs, tracks)
var color_background_darker: Color = color_background.darkened(COLOR_ADJUSTMENT)
var color_background_darkest: Color = color_background.darkened(COLOR_ADJUSTMENT * 2)
var color_background_lighter: Color = color_background.lightened(COLOR_ADJUSTMENT)

# -- Surface Colors (layered content areas) --
const color_surface1: Color = Color("#2c1f2b") # Panels, cards (was content1)
const color_surface2: Color = Color("#3e2b3c") # Elevated surfaces (was content2)
const color_surface3: Color = Color("#50374d") # Higher elevation (was content3)
const color_surface4: Color = Color("#62435f") # Highest elevation (was content4)

# -- Interactive/Accent Colors --
const color_accent: Color = Color("#db924b") # Primary interactive elements (was primary)
var color_accent_lighter: Color = color_accent.lightened(COLOR_ADJUSTMENT) # Hover state
var color_accent_darker: Color = color_accent.darkened(COLOR_ADJUSTMENT) # Pressed state
var color_accent_darkest: Color = color_accent.darkened(COLOR_ADJUSTMENT * 2) # Guides/lines

# -- Secondary Accent --
const color_secondary: Color = Color("#5a8486")
var color_secondary_darker: Color = color_secondary.darkened(COLOR_ADJUSTMENT)
var color_secondary_darkest: Color = color_secondary.darkened(COLOR_ADJUSTMENT * 2)
var color_secondary_lighter: Color = color_secondary.lightened(COLOR_ADJUSTMENT)

# -- Neutral/Default --
const color_neutral: Color = Color("#413841") # Shadows, neutral elements (was default)
var color_neutral_darker: Color = color_neutral.darkened(COLOR_ADJUSTMENT)
var color_neutral_darkest: Color = color_neutral.darkened(COLOR_ADJUSTMENT * 2)
var color_neutral_lighter: Color = color_neutral.lightened(COLOR_ADJUSTMENT)

# -- Status Colors --
const color_success: Color = Color("#9db787")
var color_success_darker: Color = color_success.darkened(COLOR_ADJUSTMENT)
var color_success_darkest: Color = color_success.darkened(COLOR_ADJUSTMENT * 2)
var color_success_lighter: Color = color_success.lightened(COLOR_ADJUSTMENT)

const color_warning: Color = Color("#ffd25f")
var color_warning_darker: Color = color_warning.darkened(COLOR_ADJUSTMENT)
var color_warning_darkest: Color = color_warning.darkened(COLOR_ADJUSTMENT * 2)
var color_warning_lighter: Color = color_warning.lightened(COLOR_ADJUSTMENT)

const color_danger: Color = Color("#fc9581")
var color_danger_darker: Color = color_danger.darkened(COLOR_ADJUSTMENT)
var color_danger_darkest: Color = color_danger.darkened(COLOR_ADJUSTMENT * 2)
var color_danger_lighter: Color = color_danger.lightened(COLOR_ADJUSTMENT)

# -- Text Colors --
const color_text_on_dark: Color = Color(0.875, 0.875, 0.875, 1) # Text on dark backgrounds (was input)
const color_text_on_accent: Color = color_surface1 # Text on accent-colored backgrounds

# -- Utility Colors --
const color_transparent: Color = Color(0.0, 0.0, 0.0, 0.0)

# =============================================================================
# SHARED DIMENSIONS
# =============================================================================

const shadow_color: Color = color_neutral
const shadow_size: int = 4
const corner_r: int = 6
const border_w: int = 1
const margin_w: int = 4  # Base spacing unit
const spacing_sm: int = 4
const spacing_md: int = 8
const spacing_lg: int = 12
const spacing_xl: int = 16

# =============================================================================
# REUSABLE STYLEBOX COMPONENTS
# =============================================================================

# Common border/corner settings (merged into styleboxes via inherit)
var _base_rounded: Dictionary:
	get: return {
		border_ = border_width(border_w),
		corner_ = corner_radius(corner_r),
	}

var _base_content_margin: Dictionary:
	get: return {
		content_margin_ = content_margins(spacing_md, spacing_md),
	}

var _base_button_margin: Dictionary:
	get: return {
		content_margin_ = content_margins(margin_w * 2, margin_w),
	}

# Reusable focus style (empty for all controls)
var style_focus_empty: Dictionary:
	get: return stylebox_empty({})

# Solid color stylebox helper - when bg and border are the same
func style_solid(color: Color, extras: Dictionary = {}) -> Dictionary:
	return inherit(stylebox_flat({
		bg_color = color,
		border_color = color,
	}), extras)

# Selection stylebox (used in Tree, ItemList, etc.)
func style_selection(color: Color) -> Dictionary:
	return style_solid(color)

# Hover selection stylebox
func style_selection_hover() -> Dictionary:
	return style_solid(color_accent_lighter)

# Panel/container background
func style_panel() -> Dictionary:
	return stylebox_flat({
		bg_color = color_surface1,
		border_color = color_surface1,
		corner_ = corner_radius(corner_r),
		content_margin_ = content_margins(spacing_lg, spacing_md),
	})

# Input field background
func style_input_bg() -> Dictionary:
	return stylebox_flat({
		bg_color = color_background,
		content_margin_ = content_margins(margin_w * 2),
	})

# Bordered panel (for popups, dialogs)
func style_bordered_panel() -> Dictionary:
	return stylebox_flat({
		bg_color = color_background,
		border_color = color_accent,
		border_ = border_width(border_w),
		content_margin_ = content_margins(margin_w * 2),
	})

func setup():
	set_save_path("res://themes/generated/dark_theme.tres")

func define_theme():
	define_default_font(inter_font)
	define_default_font_size(16)

	_define_label()
	_define_button()
	_define_checkbox_and_checkbutton()
	_define_menu_button()
	_define_panel()
	_define_editors()
	_define_spinbox()
	_define_scrollbars()
	_define_sliders()
	_define_progressbar()
	_define_tabs()
	_define_tree()
	_define_popup_menu()
	_define_containers()
	_define_item_list()
	_define_window()
	_define_accept_dialog()
	_define_separator()


# =============================================================================
# CONTROL DEFINITIONS
# =============================================================================

# Font sizes - tighter hierarchy for better visual flow
const font_size_title: int = 20   # Main titles (Level Editor)
const font_size_h1: int = 18      # Primary headings
const font_size_h2: int = 16      # Secondary headings
const font_size_h3: int = 15      # Subsection headings
const font_size_body: int = 14    # Body text and field labels
const font_size_caption: int = 12 # Hints, status text


func _define_label():
	define_style("Label", {
		font_size = font_size_title,
		focus = style_focus_empty,
		normal = inherit(stylebox_flat({
			bg_color = color_transparent,
			border_color = color_transparent,
		}), _base_rounded),
	})

	# Heading level variants
	define_variant_style("H1", "Label", { font_size = font_size_h1 })
	define_variant_style("H2", "Label", { font_size = font_size_h2 })
	define_variant_style("H3", "Label", { font_size = font_size_h3 })

	# Section header - accent colored, for prominent panel titles
	define_variant_style("SectionHeader", "Label", {
		font_size = font_size_h2,
		font_color = color_accent,
	})

	# Panel header - light text on dark surfaces, for panel/popup titles
	define_variant_style("PanelHeader", "Label", {
		font_size = font_size_h2,
		font_color = color_text_on_dark,
	})

	# Body text - smaller than headings, for general content
	define_variant_style("Body", "Label", { font_size = font_size_body })

	# Caption/muted text - smallest, for secondary info
	define_variant_style("Caption", "Label", {
		font_size = font_size_caption,
		font_color = Color(color_text_on_dark, 0.7),
	})


# Helper to generate button styles for a given color
func _button_styles(base_color: Color, lighter: Color, darker: Color) -> Dictionary:
	var style_normal = inherit(stylebox_flat({
		bg_color = base_color,
		border_color = base_color,
	}), _base_rounded, _base_button_margin)

	var style_hover = inherit(style_normal, {
		bg_color = lighter,
		border_color = lighter,
	})

	var style_pressed = inherit(style_normal, {
		bg_color = darker,
		border_color = lighter,
	})

	var style_disabled = inherit(style_normal, {
		bg_color = Color(base_color, 0.5),
		border_color = Color(darker, 0.5),
	})

	return {
		normal = style_normal,
		hover = style_hover,
		pressed = style_pressed,
		hover_pressed = style_pressed,
		focus = style_focus_empty,
		disabled = style_disabled,
		font = inter_font,
		font_color = color_text_on_accent,
		font_hover_color = color_text_on_accent,
		font_pressed_color = color_text_on_accent,
		font_hover_pressed_color = color_text_on_accent,
		font_focus_color = color_text_on_accent,
		font_disabled_color = color_text_on_accent,
	}


func _define_button():
	# Primary button (default)
	define_style("Button", _button_styles(color_accent, color_accent_lighter, color_accent_darker))

	# Button variants
	define_variant_style("Secondary", "Button",
		_button_styles(color_secondary, color_secondary_lighter, color_secondary_darker))

	define_variant_style("Success", "Button",
		_button_styles(color_success, color_success_lighter, color_success_darker))

	define_variant_style("Warning", "Button",
		_button_styles(color_warning, color_warning_lighter, color_warning_darker))

	define_variant_style("Danger", "Button",
		_button_styles(color_danger, color_danger_lighter, color_danger_darker))


# Helper for toggle font colors (CheckBox, CheckButton)
func _toggle_font_colors(base_color: Color, lighter: Color) -> Dictionary:
	return {
		font_color = base_color,
		font_hover_color = lighter,
		font_pressed_color = base_color,
		font_hover_pressed_color = lighter,
		font_focus_color = base_color,
		font_disabled_color = base_color,
	}

# Helper to generate CheckBox styles for a given color
func _checkbox_styles(base_color: Color, lighter: Color) -> Dictionary:
	var style_transparent = style_solid(color_transparent)
	return inherit({
		normal = style_transparent,
		hover = style_transparent,
		pressed = style_transparent,
		hover_pressed = style_transparent,
		checkbox_checked_color = lighter,
		checkbox_unchecked_color = lighter,
	}, _toggle_font_colors(base_color, lighter))

# Helper to generate CheckButton styles for a given color
func _checkbutton_styles(base_color: Color, lighter: Color) -> Dictionary:
	var style_transparent = style_solid(color_transparent)
	return inherit({
		normal = style_transparent,
		hover = style_transparent,
		pressed = style_transparent,
		hover_pressed = style_transparent,
		button_checked_color = lighter,
		button_unchecked_color = lighter,
	}, _toggle_font_colors(base_color, lighter))


func _define_checkbox_and_checkbutton():
	# CheckBox - primary and variants
	define_style("CheckBox", _checkbox_styles(color_accent, color_accent_lighter))

	define_variant_style("SecondaryCheckBox", "CheckBox",
		_checkbox_styles(color_secondary, color_secondary_lighter))
	define_variant_style("SuccessCheckBox", "CheckBox",
		_checkbox_styles(color_success, color_success_lighter))
	define_variant_style("WarningCheckBox", "CheckBox",
		_checkbox_styles(color_warning, color_warning_lighter))
	define_variant_style("DangerCheckBox", "CheckBox",
		_checkbox_styles(color_danger, color_danger_lighter))

	# CheckButton - primary and variants
	define_style("CheckButton", _checkbutton_styles(color_accent, color_accent_lighter))

	define_variant_style("SecondaryCheckButton", "CheckButton",
		_checkbutton_styles(color_secondary, color_secondary_lighter))
	define_variant_style("SuccessCheckButton", "CheckButton",
		_checkbutton_styles(color_success, color_success_lighter))
	define_variant_style("WarningCheckButton", "CheckButton",
		_checkbutton_styles(color_warning, color_warning_lighter))
	define_variant_style("DangerCheckButton", "CheckButton",
		_checkbutton_styles(color_danger, color_danger_lighter))


# Helper to generate MenuButton styles for a given color
func _menu_button_styles(base_color: Color, lighter: Color) -> Dictionary:
	var style_normal = inherit(stylebox_flat({
		bg_color = base_color,
		border_color = base_color,
	}), _base_rounded, _base_button_margin)

	return {
		normal = style_normal,
		hover = style_normal,
		pressed = style_normal,
		hover_pressed = style_normal,
		font_color = base_color,
		font_hover_color = lighter,
		font_pressed_color = base_color,
		font_hover_pressed_color = lighter,
		font_focus_color = base_color,
		font_disabled_color = base_color,
	}


func _define_menu_button():
	define_style("MenuButton", _menu_button_styles(color_accent, color_accent_lighter))

	define_variant_style("SecondaryMenuButton", "MenuButton",
		_menu_button_styles(color_secondary, color_secondary_lighter))
	define_variant_style("SuccessMenuButton", "MenuButton",
		_menu_button_styles(color_success, color_success_lighter))
	define_variant_style("WarningMenuButton", "MenuButton",
		_menu_button_styles(color_warning, color_warning_lighter))
	define_variant_style("DangerMenuButton", "MenuButton",
		_menu_button_styles(color_danger, color_danger_lighter))


func _define_panel():
	var panel = style_panel()
	define_style("Panel", { panel = panel })
	define_style("PanelContainer", { panel = panel })

	# Elevated panel - slightly lighter background for nested panels
	define_variant_style("PanelElevated", "PanelContainer", {
		panel = inherit(stylebox_flat({
			bg_color = color_surface2,
			border_color = color_surface2,
		}), _base_rounded),
	})

	# Bordered panel - subtle border for grouping related controls
	define_variant_style("PanelBordered", "PanelContainer", {
		panel = stylebox_flat({
			bg_color = color_transparent,
			border_color = color_surface3,
			border_ = border_width(border_w),
			corner_ = corner_radius(corner_r),
			content_margin_ = content_margins(margin_w * 2),
		}),
	})

	# Inset panel - darker background, appears recessed (for lists, content areas)
	define_variant_style("PanelInset", "PanelContainer", {
		panel = inherit(stylebox_flat({
			bg_color = color_background,
			border_color = color_background,
		}), _base_rounded, _base_content_margin),
	})


func _define_editors():
	# Shared editor colors
	var editor_colors = {
		caret_color = color_accent,
		selection_color = Color(color_accent, 0.5),
		font_color = color_text_on_dark,
		font_placeholder_color = Color(color_text_on_dark, 0.75),
	}

	var normal_style = style_input_bg()

	define_style("LineEdit", inherit({
		clear_button_color = color_accent,
		clear_button_color_pressed = color_accent_lighter,
		focus = style_focus_empty,
		normal = normal_style,
	}, editor_colors))

	define_style("TextEdit", inherit({
		focus = style_focus_empty,
		normal = normal_style,
	}, editor_colors))


func _define_spinbox():
	var bg_hovered = stylebox_flat({bg_color = color_surface2})
	var bg_pressed = stylebox_flat({bg_color = color_surface3})

	define_style("SpinBox", {
		up_icon_modulate = color_accent,
		up_disabled_icon_modulate = color_accent_darker,
		up_hover_icon_modulate = color_accent_lighter,
		up_pressed_icon_modulate = color_accent_darker,
		up_background_hovered = bg_hovered,
		up_background_pressed = bg_pressed,
		down_icon_modulate = color_accent,
		down_disabled_icon_modulate = color_accent_darker,
		down_hover_icon_modulate = color_accent_lighter,
		down_pressed_icon_modulate = color_accent_darker,
		down_background_hovered = bg_hovered,
		down_background_pressed = bg_pressed,
	})


func _define_scrollbars():
	var grabber_normal = inherit(style_solid(color_accent), {
		border_ = border_width(border_w * 2),
	})
	var grabber_pressed = inherit(style_solid(color_accent_darker), {
		border_ = border_width(border_w * 2),
	})
	var scroll_track = inherit(style_solid(color_background), {
		border_ = border_width(border_w * 4),
	})

	var scrollbar_style = {
		grabber = grabber_normal,
		grabber_highlight = grabber_normal, # Same as normal
		grabber_pressed = grabber_pressed,
		scroll = scroll_track,
	}

	define_style("VScrollBar", scrollbar_style)
	define_style("HScrollBar", scrollbar_style)


func _define_sliders():
	var track = inherit(style_solid(color_background), {
		border_ = border_width(border_w * 4),
	})
	var grabber_area = inherit(style_solid(color_accent), {
		border_ = border_width(border_w * 2),
	})

	var slider_style = {
		grabber_area = grabber_area,
		grabber_area_highlight = grabber_area,
		slider = track,
	}

	define_style("HSlider", slider_style)
	define_style("VSlider", slider_style)


func _define_progressbar():
	define_style("ProgressBar", {
		background = stylebox_flat({bg_color = color_background}),
		fill = stylebox_flat({bg_color = color_accent}),
	})


func _define_tabs():
	var tab_selected = stylebox_flat({
		bg_color = color_background,
		border_color = color_accent,
		border_width_top = border_w,
		content_margin_ = content_margins(margin_w * 4, margin_w * 3),
	})

	var tab_unselected = inherit(tab_selected, {
		border_color = color_transparent,
		bg_color = color_transparent,
	})

	define_style("TabContainer", {
		tab_selected = tab_selected,
		tab_focus = style_focus_empty,
		tab_disabled = tab_unselected,
		tab_hovered = inherit(tab_selected, {bg_color = color_surface2}),
		tab_unselected = tab_unselected,
		side_margin = 0,
		tab_separation = margin_w,
		panel = stylebox_flat({bg_color = color_background}),
	})


func _define_tree():
	var selected = style_selection(color_accent)
	var hovered = style_selection_hover()

	define_style("Tree", {
		# Line colors (using accent variations for hierarchy visibility)
		children_hl_line_color = color_accent_darker,
		guide_color = color_accent_darkest,
		parent_hl_line_color = color_accent_darker,
		relationship_line_color = color_accent_darker,
		# Font colors
		font_color = color_text_on_dark,
		font_hovered_color = color_text_on_accent,
		font_selected_color = color_text_on_accent,
		# Styles
		focus = style_focus_empty,
		hovered = hovered,
		hovered_selected = selected,
		hovered_selected_focus = selected,
		selected = selected,
		selected_focus = selected,
		# Margins
		inner_item_margin_bottom = margin_w,
		inner_item_margin_left = margin_w * 2,
		inner_item_margin_right = margin_w * 2,
		inner_item_margin_top = margin_w,
		# Panel
		panel = inherit(stylebox_flat({bg_color = color_background}), _base_content_margin),
	})


func _define_popup_menu():
	define_style("PopupMenu", {
		panel = style_bordered_panel(),
		hover = style_selection_hover(),
		font_hover_color = color_text_on_accent,
	})


func _define_containers():
	define_style("BoxContainer", {
		separation = spacing_sm,
	})

	# Variant for tighter spacing (e.g., X/Y/Z coordinate rows)
	define_variant_style("BoxContainerTight", "BoxContainer", {
		separation = spacing_sm,
	})

	# Variant for more spacing between groups
	define_variant_style("BoxContainerSpaced", "BoxContainer", {
		separation = spacing_lg,
	})

	define_style("MarginContainer", {
		margin_left = spacing_md,
		margin_top = spacing_md,
		margin_right = spacing_md,
		margin_bottom = spacing_md,
	})


func _define_item_list():
	var selected = style_selection(color_accent)
	var hovered = style_selection_hover()

	define_style("ItemList", {
		panel = style_panel(),
		hovered = hovered,
		hovered_selected = hovered,
		hovered_selected_focus = hovered,
		selected = selected,
		selected_focus = selected,
		focus = style_focus_empty,
		font_color = color_text_on_dark,
		font_hovered_color = color_text_on_accent,
		font_selected_color = color_text_on_accent,
		font_hovered_selected_color = color_text_on_accent,
	})


func _define_window():
	var window_border = stylebox_flat({
		bg_color = color_accent,
		border_color = color_surface1,
		border_ = border_width(10, 36, 10, 10),
		expand_margin_ = expand_margins(10, 36, 10, 10),
	})

	define_style("Window", {
		embedded_border = window_border,
		embedded_unfocused_border = window_border,
	})


func _define_accept_dialog():
	define_style("AcceptDialog", {
		panel = style_bordered_panel(),
	})

func _define_separator():
	var separator_base = {
		color = color_surface3,
		thickness = border_w * 3,
		grow_begin = -5,
		grow_end = -5,
	}

	define_style("HSeparator", {separator = stylebox_line(separator_base)})
	define_style("VSeparator", {separator = stylebox_line(inherit(separator_base, {vertical = true}))})
