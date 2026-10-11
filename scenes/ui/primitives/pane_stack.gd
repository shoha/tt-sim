class_name PaneStack
extends Control

## Hosts several panes at the same full-rect position and shows one at a time.
## Each pane is wrapped in a vertical ScrollContainer so tall content scrolls
## while the host's header and footer stay pinned; its bar shows only while wanted
## (ScrollBarFade), and a pane that runs past the bottom fades there (ScrollFade), so
## something always says more is below. Swaps crossfade: the
## outgoing pane fades out while the incoming one fades in and slides a few
## pixels from the rail side.
##
## [member bar_in_margin] (the drawers): the bar lies in the margin past the stack's right
## edge rather than in a gutter taken from the pane, so a pane is the stack's width whether
## it scrolls or not and ends on the same edge as the rows pinned above and below it (the
## authoring map name, the Visuals foot). The margin must be wider than the bar.

signal pane_changed(id: StringName)

const FADE_OUT_DURATION := 0.10

## Incoming panes slide in from the right (rail on the right edge) or left.
var slide_from_right: bool = true
## Put the scroll bar in the host's margin, past the stack's right edge (see the header).
## Set before the first add_pane().
var bar_in_margin: bool = false
var current: StringName = &""

var _wrappers: Dictionary = {}
var _panes: Dictionary = {}
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func add_pane(id: StringName, pane: Control) -> void:
	var wrapper := ScrollContainer.new()
	wrapper.name = String(id) + "Scroll"
	wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.visible = false
	wrapper.offset_transform_enabled = true
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(pane)
	wrapper.add_child(ScrollFade.new())
	ScrollBarFade.attach(wrapper)
	if bar_in_margin:
		# The pane keeps the bar's width spare at all times and the wrapper reaches that far
		# past the stack, so the pane is the stack's width with or without a bar.
		wrapper.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
		wrapper.theme_changed.connect(_reach_into_margin.bind(wrapper))
	add_child(wrapper)
	_wrappers[id] = wrapper
	_panes[id] = pane


## Extend `wrapper` past the stack's right edge by its bar's width (bar_in_margin).
func _reach_into_margin(wrapper: ScrollContainer) -> void:
	var bar := wrapper.get_v_scroll_bar()
	var reach := bar.get_combined_minimum_size().x
	reach += float(wrapper.get_theme_constant(&"scrollbar_h_separation"))
	if not is_equal_approx(wrapper.offset_right, reach):
		wrapper.offset_right = reach


func get_pane(id: StringName) -> Control:
	return _panes.get(id)


func show_pane(id: StringName, animate: bool = true) -> void:
	if id == current or not _wrappers.has(id):
		return
	var outgoing: Control = _wrappers.get(current)
	var previous := current
	var incoming: Control = _wrappers[id]
	current = id
	if _tween and _tween.is_valid():
		_tween.kill()
	for other_id: StringName in _wrappers:
		if other_id != id and other_id != previous:
			var other_wrapper: Control = _wrappers[other_id]
			_reset_wrapper(other_wrapper)
			other_wrapper.visible = false
	incoming.visible = true
	if not animate:
		if outgoing:
			_reset_wrapper(outgoing)
			outgoing.visible = false
		_reset_wrapper(incoming)
		pane_changed.emit(id)
		return
	var offset := Constants.ANIM_PANE_SWAP_OFFSET_PX * (1.0 if slide_from_right else -1.0)
	incoming.modulate.a = 0.0
	incoming.offset_transform_position = Vector2(offset, 0.0)
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(true)
	if outgoing:
		outgoing.offset_transform_position = Vector2.ZERO
		_tween.tween_property(outgoing, "modulate:a", 0.0, FADE_OUT_DURATION)
	_tween.tween_property(incoming, "modulate:a", 1.0, Constants.ANIM_PANE_SWAP)
	_tween.tween_property(
		incoming, "offset_transform_position", Vector2.ZERO, Constants.ANIM_PANE_SWAP
	)
	_tween.chain().tween_callback(_on_swap_finished.bind(outgoing))
	pane_changed.emit(id)


func _on_swap_finished(outgoing: Control) -> void:
	if outgoing and outgoing != _wrappers.get(current):
		outgoing.visible = false
		_reset_wrapper(outgoing)


func _reset_wrapper(wrapper: Control) -> void:
	wrapper.modulate.a = 1.0
	wrapper.offset_transform_position = Vector2.ZERO
