class_name SettingsChrome
extends RefCounted

## Two small signs the Settings sheet gives about itself, beside its rows (SettingsSession loads
## this by path and calls refresh() whenever the controls change):
##
## - "More below": a tab whose rows run past its bottom edge says so in words in a line kept free
##   above the footer rule, and the line goes (fades) once the scroll has reached the end. The
##   bottom fade (ScrollFade) shows rows are cut; the words say groups follow (T-S5). The line
##   keeps its height whether shown or not, so nothing jumps as the scroll moves.
## - A small-text warning under Interface size: a fixed size picked on a window so small that the
##   caption would draw under InterfaceSize.CAPTION_FLOOR_PX physical px (100% on a 720p window
##   draws 9). Auto never lands there.

const MORE_TEXT := "↓  More below"
const SMALL_TEXT := "Text is very small at this window size. Auto picks a readable size."

var _menu: SettingsMenu
var _more: Label
var _warning: Label
var _tween: Tween


func _init(menu: SettingsMenu) -> void:
	_menu = menu


func start() -> void:
	_build_more()
	_build_warning()
	refresh()


## Re-reads the scroll position and the Interface size choice.
func refresh() -> void:
	_update_more()
	_update_warning()


## Whether the visible tab has rows below the part on show.
func more_below() -> bool:
	var tab := _menu.tab_container.get_current_tab_control() as ScrollContainer
	if tab == null or not _menu.tab_container.visible:
		return false
	var bar := tab.get_v_scroll_bar()
	return bar.max_value - bar.page > 1.0 and bar.value + bar.page < bar.max_value - 1.0


## Whether the picked Interface size would draw the caption role under the floor on this window.
func small_text() -> bool:
	var window := Vector2(_menu.get_tree().root.size)
	var choice := _menu.interface_size_option.get_selected_id()
	var factor := (
		InterfaceSize.auto_factor(window) if choice == InterfaceSize.AUTO else choice / 100.0
	)
	var drawn := InterfaceSize.CAPTION_PX * InterfaceSize.window_scale(window) * factor
	return drawn < InterfaceSize.CAPTION_FLOOR_PX - 0.01


func _build_more() -> void:
	var tabs := _menu.tab_container
	var column := tabs.get_parent()
	_more = Label.new()
	_more.name = "MoreBelow"
	_more.theme_type_variation = &"Caption"
	_more.text = MORE_TEXT
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more.modulate.a = 0.0
	column.add_child(_more)
	column.move_child(_more, tabs.get_index() + 1)
	for tab in tabs.get_children():
		var scroll := tab as ScrollContainer
		if scroll:
			var bar := scroll.get_v_scroll_bar()
			bar.changed.connect(_update_more)
			bar.value_changed.connect(_on_scrolled)
			# A redraw follows every layout that settles the bar (a wrapped line, a freshly shown
			# tab), where a change signal can come while the sizes are still the first guess.
			scroll.draw.connect(_update_more)
	tabs.tab_changed.connect(_on_tab_changed)


func _on_scrolled(_value: float) -> void:
	_update_more()


func _on_tab_changed(_index: int) -> void:
	_update_more.call_deferred()


func _update_more() -> void:
	var wanted := 1.0 if more_below() else 0.0
	if is_equal_approx(_more.modulate.a, wanted):
		return
	if _tween:
		_tween.kill()
	_tween = _more.create_tween()
	_tween.tween_property(_more, "modulate:a", wanted, UiMotion.fade_s(UiMotion.STATE_S))


func _build_warning() -> void:
	var block := _menu.find_child("RowBlock_InterfaceSize", true, false)
	if block == null:
		return
	_warning = Label.new()
	_warning.name = "SmallTextWarning"
	_warning.theme_type_variation = &"CaptionState"
	_warning.text = SMALL_TEXT
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warning.visible = false
	block.add_child(_warning)


func _update_warning() -> void:
	if _warning:
		_warning.visible = small_text()
