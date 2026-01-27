@tool
extends ProgrammaticTheme

const UPDATE_ON_SAVE = true
const inter_font = preload("res://assets/fonts/Inter-VariableFont_opsz,wght.ttf")
const color_transparent: Color = Color(0.0, 0.0, 0.0, 0.0)

const color_adjustment: float = 0.2

const border: float = 0.0

const color_input: Color = Color(0.875, 0.875, 0.875, 1)

const color_background: Color = Color("#1a121a")
var color_background_darker: Color = color_background.darkened(color_adjustment)
var color_background_darkest: Color = color_background.darkened(color_adjustment * 2)
var color_background_lighter: Color = color_background.lightened(color_adjustment)

const color_default: Color = Color("#413841")
var color_default_darker: Color = color_default.darkened(color_adjustment)
var color_default_darkest: Color = color_default.darkened(color_adjustment * 2)
var color_default_lighter: Color = color_default.lightened(color_adjustment)
const color_primary: Color = Color("#db924b")
var color_primary_darker: Color = color_primary.darkened(color_adjustment)
var color_primary_darkest: Color = color_primary.darkened(color_adjustment * 2)
var color_primary_lighter: Color = color_primary.lightened(color_adjustment)
const color_secondary: Color = Color("#5a8486")
var color_secondary_darker: Color = color_secondary.darkened(color_adjustment)
var color_secondary_darkest: Color = color_secondary.darkened(color_adjustment * 2)
var color_secondary_lighter: Color = color_secondary.lightened(color_adjustment)
const color_success: Color = Color("#9db787")
var color_success_darker: Color = color_success.darkened(color_adjustment)
var color_success_darkest: Color = color_success.darkened(color_adjustment * 2)
var color_success_lighter: Color = color_success.lightened(color_adjustment)
const color_warning: Color = Color("#ffd25f")
var color_warning_darker: Color = color_warning.darkened(color_adjustment)
var color_warning_darkest: Color = color_warning.darkened(color_adjustment * 2)
var color_warning_lighter: Color = color_warning.lightened(color_adjustment)
const color_danger: Color = Color("#fc9581")
var color_danger_darker: Color = color_danger.darkened(color_adjustment)
var color_danger_darkest: Color = color_danger.darkened(color_adjustment * 2)
var color_danger_lighter: Color = color_danger.lightened(color_adjustment)

const color_content1: Color = Color("#2c1f2b")
const color_content2: Color = Color("#3e2b3c")
const color_content3: Color = Color("#50374d")
const color_content4: Color = Color("#62435f")

const shadow_color: Color = color_default
const shadow_size: int = 4

const corner_r: int = 4
const border_w: int = 1
const margin_w: int = 2

func setup():
	set_save_path("res://themes/generated/dark_theme.tres")

func define_theme():
	define_default_font(inter_font)
	define_default_font_size(16)

	var label_style_focus = stylebox_empty({})
	var label_style_normal = stylebox_flat({
		bg_color = color_transparent,
		border_color = color_transparent,
		border_ = border_width(border_w, border_w, border_w, border_w),
		corner_ = corner_radius(corner_r, corner_r, corner_r, corner_r),
	})

	define_style("Label", {
		font_size = 24,
		focus = label_style_focus,
		normal = label_style_normal,
	})

	var button_style_normal = stylebox_flat({
		bg_color = color_primary,
		border_color = color_primary,
		border_ = border_width(border_w, border_w, border_w, border_w),
		corner_ = corner_radius(corner_r, corner_r, corner_r, corner_r),
		content_margin_ = content_margins(margin_w * 2, margin_w, margin_w * 2, margin_w),
		# expand_margin_left = margin_w * 2,
		# expand_margin_top = margin_w,
		# expand_margin_right = margin_w * 2,
		# expand_margin_bottom = margin_w,
	})

	var button_style_hover = inherit(button_style_normal, {
		bg_color = color_primary_lighter,
		border_color = color_primary_lighter,
	})

	var button_style_pressed = inherit(button_style_normal, {
		bg_color = color_primary_darker,
		border_color = color_primary_lighter,

	})

	var button_style_hover_pressed = inherit(button_style_pressed, {

	})

	var button_style_focus = stylebox_empty({})

	var button_style_disabled = inherit(button_style_normal, {
		bg_color = Color(color_primary, 0.5),
		border_color = color_secondary_darkest,
	})

	define_style("Button", {
		normal = button_style_normal,
		hover = button_style_hover,
		pressed = button_style_pressed,
		hover_pressed = button_style_hover_pressed,
		focus = button_style_focus,
		disabled = button_style_disabled,
		font = inter_font,
		font_color = color_content1,
		font_hover_color = color_content1,
		font_pressed_color = color_content1,
		font_hover_pressed_color = color_content1,
		font_focus_color = color_content1,
		font_disabled_color = color_content1,
	})

	var checkbox_style_normal = stylebox_flat({
		bg_color = color_transparent,
		border_color = color_transparent,
	})

	var checkbox_style_hover = inherit(checkbox_style_normal, {

	})

	var checkbox_style_pressed = inherit(checkbox_style_normal, {

	})

	var checkbox_style_hover_pressed = inherit(checkbox_style_pressed, {

	})

	define_style("CheckBox", {
		normal = checkbox_style_normal,
		hover = checkbox_style_hover,
		pressed = checkbox_style_pressed,
		hover_pressed = checkbox_style_hover_pressed,
		font_color = color_primary,
		font_hover_color = color_primary_lighter,
		font_pressed_color = color_primary,
		font_hover_pressed_color = color_primary_lighter,
		font_focus_color = color_primary,
		font_disabled_color = color_primary,
		checkbox_checked_color = color_primary_lighter,
		checkbox_unchecked_color = color_primary_lighter,
	})

	var checkbutton_style_normal = stylebox_flat({
		bg_color = color_transparent,
		border_color = color_transparent,
	})

	var checkbutton_style_hover = inherit(checkbutton_style_normal, {

	})

	var checkbutton_style_pressed = inherit(checkbutton_style_normal, {

	})

	var checkbutton_style_hover_pressed = inherit(checkbutton_style_pressed, {

	})

	define_style("CheckButton", {
		normal = checkbutton_style_normal,
		hover = checkbutton_style_hover,
		pressed = checkbutton_style_pressed,
		hover_pressed = checkbutton_style_hover_pressed,
		font_color = color_primary,
		font_hover_color = color_primary_lighter,
		font_pressed_color = color_primary,
		font_hover_pressed_color = color_primary_lighter,
		font_focus_color = color_primary,
		font_disabled_color = color_primary,
		button_checked_color = color_primary_lighter,
		button_unchecked_color = color_primary_lighter,
	})

	var menu_button_style_normal = inherit(button_style_normal, {
		bg_color = color_primary,
		border_color = color_primary,
	})

	var menu_button_style_hover = inherit(menu_button_style_normal, {

	})

	var menu_button_style_pressed = inherit(menu_button_style_normal, {

	})

	var menu_button_style_hover_pressed = inherit(menu_button_style_pressed, {

	})

	define_style("MenuButton", {
		normal = menu_button_style_normal,
		hover = menu_button_style_hover,
		pressed = menu_button_style_pressed,
		hover_pressed = menu_button_style_hover_pressed,
		font_color = color_primary,
		font_hover_color = color_primary_lighter,
		font_pressed_color = color_primary,
		font_hover_pressed_color = color_primary_lighter,
		font_focus_color = color_primary,
		font_disabled_color = color_primary,
	})

	var panel_style = stylebox_flat({
		bg_color = color_content1,
		border_color = color_content1,
		border_ = border_width(border_w, border_w, border_w, border_w),
		corner_ = corner_radius(corner_r, corner_r, corner_r, corner_r),
	})

	define_style("Panel", {
		panel = panel_style,
	})

	define_style("PanelContainer", {
		panel = panel_style,
	})

	var editor_normal_style = stylebox_flat({
		bg_color = color_background,
		content_margin_ = content_margins(margin_w * 2, margin_w * 2, margin_w * 2, margin_w * 2),
	})

	define_style("LineEdit", {
		caret_color = color_primary,
		clear_button_color = color_primary,
		clear_button_color_pressed = color_primary_lighter,
		selection_color = Color(color_primary, 0.5),
		font_color = color_input,
		font_placeholder_color = Color(color_input, 0.75),
		focus = stylebox_empty({}),
		normal = editor_normal_style,
	})

	define_style("TextEdit", {
		caret_color = color_primary,
		selection_color = Color(color_primary, 0.5),
		font_color = color_input,
		font_placeholder_color = Color(color_input, 0.75),
		focus = stylebox_empty({}),
		normal = editor_normal_style,
	})

	var spin_background_hovered = stylebox_flat({
		bg_color = color_content2,
	})

	var spin_background_pressed = stylebox_flat({
		bg_color = color_content3,
	})

	define_style("SpinBox", {
		up_icon_modulate = color_primary,
		up_disabled_icon_modulate = color_primary_darker,
		up_hover_icon_modulate = color_primary_lighter,
		up_pressed_icon_modulate = color_primary_darker,
		up_background_hovered = spin_background_hovered,
		up_background_pressed = spin_background_pressed,
		down_icon_modulate = color_primary,
		down_disabled_icon_modulate = color_primary_darker,
		down_hover_icon_modulate = color_primary_lighter,
		down_pressed_icon_modulate = color_primary_darker,
		down_background_hovered = spin_background_hovered,
		down_background_pressed = spin_background_pressed,
	})

	var scrollbar_style_normal = stylebox_flat({
		bg_color = color_primary,
		border_color = color_primary,
		border_ = border_width(border_w * 2, border_w * 2, border_w * 2, border_w * 2),
	})

	var scrollbar_style_highlight = inherit(scrollbar_style_normal, {
		bg_color = color_primary,
		border_color = color_primary,
	})

	var scrollbar_style_pressed = inherit(scrollbar_style_normal, {
		bg_color = color_primary_darker,
		border_color = color_primary_darker,
	})

	var scrollbar_scroll_style_normal = stylebox_flat({
		bg_color = color_background,
		border_color = color_background,
		border_ = border_width(border_w * 4, border_w * 4, border_w * 4, border_w * 4),
	})

	define_style("VScrollBar", {
		grabber = scrollbar_style_normal,
		grabber_highlight = scrollbar_style_highlight,
		grabber_pressed = scrollbar_style_pressed,
		scroll = scrollbar_scroll_style_normal,
	})

	define_style("HScrollBar", {
		grabber = scrollbar_style_normal,
		grabber_highlight = scrollbar_style_highlight,
		grabber_pressed = scrollbar_style_pressed,
		scroll = scrollbar_scroll_style_normal,
	})


	var slider_style_normal = stylebox_flat({
		bg_color = color_background,
		border_color = color_background,
		border_ = border_width(border_w * 4, border_w * 4, border_w * 4, border_w * 4),
	})

	var slider_style_highlight = inherit(slider_style_normal, {
		bg_color = color_primary,
		border_color = color_primary,
		border_ = border_width(border_w * 2, border_w * 2, border_w * 2, border_w * 2),
	})

	define_style("HSlider", {
		grabber_area = slider_style_highlight,
		grabber_area_highlight = slider_style_highlight,
		slider = slider_style_normal,
	})

	define_style("VSlider", {
		grabber_area = slider_style_highlight,
		grabber_area_highlight = slider_style_highlight,
		slider = slider_style_normal,
	})

	define_style("ProgressBar", {
		background = stylebox_flat({
			bg_color = color_background,
		}),
		fill = stylebox_flat({
			bg_color = color_primary,
		}),
	})

	var tabbar_tab_style_selected = stylebox_flat({
		bg_color = color_background,
		border_color = color_primary,
		border_width_top = border_w,
		content_margin_ = content_margins(margin_w * 4, margin_w * 3, margin_w * 4, margin_w * 3),
	})

	var tabbar_tab_style_unselected = inherit(tabbar_tab_style_selected, {
		border_color = color_transparent,
		bg_color = color_transparent,
	})

	var tabbar_tab_style_focus = stylebox_empty({})

	var tabbar_tab_style_disabled = inherit(tabbar_tab_style_selected, {
		border_color = color_transparent,
		bg_color = color_transparent,
	})

	var tabbar_tab_style_hovered = inherit(tabbar_tab_style_selected, {
		bg_color = color_content2,
	})

	define_style("TabContainer", {
		tab_selected = tabbar_tab_style_selected,
		tab_focus = tabbar_tab_style_focus,
		tab_disabled = tabbar_tab_style_disabled,
		tab_hovered = tabbar_tab_style_hovered,
		tab_unselected = tabbar_tab_style_unselected,
		side_margin = 0,
		tab_separation = margin_w,
		panel = stylebox_flat({
			bg_color = color_background,
		}),
	})

	var tree_style_selected = stylebox_flat({
		bg_color = color_primary,
		border_color = color_primary,
	})

	var tree_style_hovered_selected = inherit(tree_style_selected, {})

	var tree_style_hovered_selected_focus = inherit(tree_style_selected, {})

	var tree_style_selected_focus = inherit(tree_style_selected, {

	})

	var tree_style_hovered = inherit(tree_style_selected, {
		bg_color = color_primary_lighter,
		border_color = color_primary_lighter,
	})

	var tree_style_focus = stylebox_empty({})

	define_style("Tree", {
		children_hl_line_color = color_primary_darker,
		guide_color = color_primary_darkest,
		font_color = color_input,
		font_hovered_color = color_content1,
		font_selected_color = color_content1,
		parent_hl_line_color = color_primary_darker,
		relationship_line_color = color_primary_darker,
		focus = tree_style_focus,
		hovered = tree_style_hovered,
		hovered_selected = tree_style_hovered_selected,
		hovered_selected_focus = tree_style_hovered_selected_focus,
		inner_item_margin_bottom = margin_w,
		inner_item_margin_left = margin_w * 2,
		inner_item_margin_right = margin_w * 2,
		inner_item_margin_top = margin_w,
		selected = tree_style_selected,
		selected_focus = tree_style_selected_focus,
		panel = stylebox_flat({
			bg_color = color_background,
			content_margin_ = content_margins(margin_w * 2, margin_w * 2, margin_w * 2, margin_w * 2),
		}),
	})

	define_style("PopupMenu", {
		panel = stylebox_flat({
			bg_color = color_background,
			content_margin_ = content_margins(margin_w * 2, margin_w * 2, margin_w * 2, margin_w * 2),
			border_color = color_primary,
			border_ = border_width(border_w, border_w, border_w, border_w),
		}),
		hover = stylebox_flat({
			bg_color = color_primary_lighter,
			border_color = color_primary_lighter,
		}),
		font_hover_color = color_content1,
	})


	define_style("BoxContainer", {
		separation = margin_w * 2,
	})

	define_style("MarginContainer", {
		margin_left = margin_w,
		margin_top = margin_w,
		margin_right = margin_w,
		margin_bottom = margin_w,
	})

	define_style("ItemList", {
		panel = panel_style,
	})
