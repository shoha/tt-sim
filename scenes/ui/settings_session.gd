class_name SettingsSession
extends RefCounted

## What the open Settings menu knows about itself beyond its rows: the defaults every control would
## take, whether the controls differ from the saved file (the "unsaved changes" mark and the Apply
## button's state), the per-group Reset, and the live preview of the cheap rows.
##
## Defaults are not listed twice: they are what SettingsMenu._show_defaults puts on the controls,
## read once into a dictionary (control name to value) when the menu opens. The four preferences
## that save the moment they change are not part of _show_defaults, so SettingsSpec.LIVE_DEFAULTS
## names theirs.
##
## Preview: moving a row that is not in SettingsSpec.APPLY_ONLY applies the whole preview set
## (SettingsMenu._apply_preview) once the menu is open, so a shadow, water or grid change shows on
## the board behind the sheet. Nothing is saved until Apply; closing with unsaved changes puts the
## saved values back on the controls and on the board (revert_if_dirty).

const CLEAN_TEXT := "All changes applied"
const DIRTY_TEXT := "Unsaved changes: Apply keeps them"
const DISCARDED_TOAST := "Unsaved changes discarded"
const UNDO_TEXT := "Every setting is back to its default"
## A group's Reset reads this, off, while the group is already at its defaults.
const RESET_WORD := "Reset"
const DEFAULTS_WORD := "Defaults"
## Loaded by path, not named, so the start-up script graph does not grow (test_boot_graph).
const CHROME_SCRIPT := "res://scenes/ui/settings_chrome.gd"

## Set once the menu has finished opening: before that and after it closes nothing previews.
var live := false

var _menu: SettingsMenu
var _layout: SettingsLayout
var _status: Label
var _chrome  # SettingsChrome: the "More below" hint and the small-text warning
var _baseline := ""
var _defaults := {}
var _dirty := false
var _flush_queued := false
var _preview_needed := false
var _slider_tween: Tween


func _init(menu: SettingsMenu, layout: SettingsLayout) -> void:
	_menu = menu
	_layout = layout


## Wires the controls, the group Reset buttons and the footer's status line. Call after the saved
## values are on the controls.
func start() -> void:
	_build_status()
	_chrome = (load(CHROME_SCRIPT) as GDScript).new(_menu)
	_chrome.start()
	for control in value_controls():
		_connect_changed(control)
	for group in _layout.groups:
		var button := group.reset as Button
		if button:
			button.pressed.connect(reset_group.bind(group))
	_compute_defaults()
	mark_clean()


## Every control that holds a setting's value, in tree order.
func value_controls() -> Array[Control]:
	var out: Array[Control] = []
	for node in _menu.tab_container.find_children("*", "Control", true, false):
		if node is HSlider or node is CheckButton or node is OptionButton:
			out.append(node as Control)
	return out


## Control name to value, for every value control.
func read_all() -> Dictionary:
	var out := {}
	for control in value_controls():
		out[String(control.name)] = value_of(control)
	return out


## Puts `values` (a read_all result) on the controls without firing any handler.
func write_all(values: Dictionary) -> void:
	for control in value_controls():
		if values.has(String(control.name)):
			show_value(control, values[String(control.name)])


static func value_of(control: Control) -> Variant:
	if control is OptionButton:
		return (control as OptionButton).get_selected_id()
	if control is CheckButton:
		return (control as CheckButton).button_pressed
	return (control as HSlider).value


static func show_value(control: Control, value: Variant) -> void:
	if control is OptionButton:
		var option := control as OptionButton
		var index := option.get_item_index(int(value))
		option.select(index if index >= 0 else 0)
	elif control is CheckButton:
		(control as CheckButton).set_pressed_no_signal(bool(value))
	else:
		(control as HSlider).set_value_no_signal(float(value))


static func same(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


## The default value of every control, by name (computed on first use).
func defaults() -> Dictionary:
	if _defaults.is_empty():
		_compute_defaults()
	return _defaults


func is_dirty() -> bool:
	return _dirty


## The saved file now matches the controls (after load, Apply or a revert).
func mark_clean() -> void:
	_baseline = _snapshot()
	refresh()


## Re-reads the controls: the status line, the Apply button (the lead only while there is something
## to apply, bare words otherwise so its waiting state still reads), each group's Reset (the word
## says "Defaults" when there is nothing to reset) and Reset all (quiet while nothing differs).
func refresh() -> void:
	_dirty = _snapshot() != _baseline
	if _status:
		_status.text = DIRTY_TEXT if _dirty else CLEAN_TEXT
		_status.theme_type_variation = &"CaptionState" if _dirty else &"Caption"
	_menu.apply_button.disabled = not _dirty
	_menu.apply_button.theme_type_variation = &"Primary" if _dirty else &"Ghost"
	var everything_default := true
	for group in _layout.groups:
		var at_defaults := group_at_defaults(group)
		everything_default = everything_default and at_defaults
		var button := group.reset as Button
		if button:
			button.disabled = at_defaults
			button.text = DEFAULTS_WORD if at_defaults else RESET_WORD
	_menu.reset_button.theme_type_variation = &"Ghost" if everything_default else &"Secondary"
	if _chrome:
		_chrome.refresh()


## Whether every group's rows already hold their defaults.
func all_at_defaults() -> bool:
	for group in _layout.groups:
		if not group_at_defaults(group):
			return false
	return true


## After Reset all: says what happened and offers the way back (`before` is read_all from just
## before the reset), since the reset is undone safely instead of confirmed first.
func offer_undo(before: Dictionary) -> void:
	UIManager.show_undo_toast(UNDO_TEXT, restore.bind(before))


## Puts `values` (a read_all result) back, the four preferences that save at once through their
## own handlers, and previews them.
func restore(values: Dictionary) -> void:
	for control in value_controls():
		var key := String(control.name)
		if not values.has(key):
			continue
		if SettingsSpec.LIVE_DEFAULTS.has(key):
			_set_live(control, values[key])
		else:
			show_value(control, values[key])
	if _menu.has_method(&"_refresh_quality"):
		_menu.call(&"_refresh_quality")
	_changed(null, true)


func group_at_defaults(group: Dictionary) -> bool:
	var table := defaults()
	for control in group.controls:
		var key := String(control.name)
		if table.has(key) and not same(value_of(control), table[key]):
			return false
	return true


## Puts every control of `group` back on its default. The four preferences that save at once go
## through their own handlers; the rest only show the default (Apply applies it, and the preview
## has already shown it). Sliders glide there (UiMotion.STATE_S) and snap under Reduce motion.
func reset_group(group: Dictionary) -> void:
	var table := defaults()
	var sliders: Array = []
	for control in group.controls:
		var key := String(control.name)
		if not table.has(key):
			continue
		if SettingsSpec.LIVE_DEFAULTS.has(key):
			_set_live(control, table[key])
		elif control is HSlider:
			sliders.append([control, table[key]])
		else:
			show_value(control, table[key])
	_glide(sliders)
	if _menu.has_method(&"_refresh_quality"):
		_menu.call(&"_refresh_quality")
	_changed(null, true)


## Something changed a control without a signal (a Reset): re-read it, and preview when asked.
func touch(previews: bool = true) -> void:
	_changed(null, previews)


## Closing with unsaved changes: the saved values go back on the controls and on the board.
func revert_if_dirty() -> void:
	live = false
	if not _dirty:
		return
	_menu._load_settings()
	_menu._apply_preview()
	mark_clean()
	UIManager.show_toast(DISCARDED_TOAST, 0)


func _set_live(control: Control, value: Variant) -> void:
	if control is OptionButton:
		var option := control as OptionButton
		var index := option.get_item_index(int(value))
		option.select(index)
		option.item_selected.emit(index)
	elif control is CheckButton:
		(control as CheckButton).button_pressed = bool(value)


func _glide(sliders: Array) -> void:
	if sliders.is_empty():
		return
	if _slider_tween and _slider_tween.is_valid():
		_slider_tween.kill()
	_menu._resetting = true
	if UiMotion.reduced():
		for pair in sliders:
			(pair[0] as HSlider).value = pair[1]
		_menu._resetting = false
		return
	_slider_tween = _menu.create_tween()
	_slider_tween.set_parallel(true)
	_slider_tween.set_ease(Tween.EASE_OUT)
	_slider_tween.set_trans(UiMotion.ARRIVE_TRANS)
	for pair in sliders:
		_slider_tween.tween_property(pair[0], "value", pair[1], UiMotion.STATE_S)
	_slider_tween.finished.connect(_on_glide_finished.bind(_slider_tween))


func _on_glide_finished(tween: Tween) -> void:
	if tween == _slider_tween:
		_menu._resetting = false


func _compute_defaults() -> void:
	var saved := read_all()
	_menu._show_defaults(true)
	_defaults = read_all()
	for key in SettingsSpec.LIVE_DEFAULTS:
		_defaults[key] = SettingsSpec.LIVE_DEFAULTS[key]
	write_all(saved)
	_menu._update_value_labels()
	if _menu.has_method(&"_refresh_quality"):
		_menu.call(&"_refresh_quality")


func _snapshot() -> String:
	var config := ConfigFile.new()
	_menu._write_values(config)
	return config.encode_to_text()


func _connect_changed(control: Control) -> void:
	var live_row := SettingsSpec.LIVE_DEFAULTS.has(String(control.name))
	var previews := not live_row and not SettingsSpec.APPLY_ONLY.has(String(control.name))
	if control is HSlider:
		(control as HSlider).value_changed.connect(_changed.bind(previews))
	elif control is CheckButton:
		(control as CheckButton).toggled.connect(_changed.bind(previews))
	else:
		(control as OptionButton).item_selected.connect(_changed.bind(previews))


func _changed(_value: Variant, previews: bool) -> void:
	_preview_needed = _preview_needed or previews
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_flush_queued = false
	refresh()
	if _preview_needed and live:
		_menu._apply_preview()
	_preview_needed = false


func _build_status() -> void:
	var footer := _menu.reset_button.get_parent()
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"Caption"
	_status.text = CLEAN_TEXT
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status)
	footer.move_child(_status, 0)
