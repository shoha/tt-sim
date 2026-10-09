class_name InputHints
extends CanvasLayer

## Contextual input hints in a bar at the bottom centre of the screen: one
## chip per hint, a `KeyChip` key cap beside a caption (the help overlay's
## shortcut rows use the same chip).
##
## The bar stays anchored to the bottom edge. Its entrance and exit tween its
## alpha and [member Control.offset_transform_position], a draw-time offset that
## never touches the anchors or offsets; tweening [member Control.position]
## instead rewrote the offsets against the top anchor and parked the bar at the
## top of the screen. The bar slides only when it appears or empties.
##
## Hint changes are diffed by key, so a hint toggled mid-drag does not rebuild
## the bar: a chip whose key stays is kept (its caption updated in place), a new
## key's chip fades in, and a dropped key's chip fades out where it stands and is
## then freed. A key re-added while its chip is still fading out takes that chip
## back.

## How far below its resting place the bar starts its entrance, in pixels.
const SLIDE_DISTANCE := 12.0
const BAR_IN_DURATION := 0.25

var _current_hints: Array[Dictionary] = []
## Key -> chip, for every chip in the row, leaving ones included.
var _chips: Dictionary = {}
## Key -> the chip's running fade.
var _chip_tweens: Dictionary = {}
## Keys whose chip is fading out.
var _leaving: Dictionary = {}
var _bar_tween: Tween
var _bar_shown: bool = false

@onready var hints_container: HBoxContainer = %HintRow
@onready var _bar: MarginContainer = %HintBar


func _ready() -> void:
	_bar.modulate.a = 0.0
	_bar.offset_transform_enabled = true
	_bar.offset_transform_position = Vector2(0.0, SLIDE_DISTANCE)


## Set hints to display. Each hint is a dictionary with "key" and "action".
## Example: [{"key": "ESC", "action": "Pause"}, {"key": "E", "action": "Interact"}]
func set_hints(hints: Array) -> void:
	if _are_hints_equal(hints):
		return
	_current_hints.clear()
	for hint in hints:
		_current_hints.append({"key": String(hint["key"]), "action": String(hint["action"])})
	_sync()


## Clear all hints; the bar slides out.
func clear_hints() -> void:
	_current_hints.clear()
	_sync()


## Add a single hint, or relabel the hint already on that key.
func add_hint(key: String, action: String) -> void:
	for hint in _current_hints:
		if hint["key"] == key:
			if hint["action"] == action:
				return
			hint["action"] = action
			_sync()
			return
	_current_hints.append({"key": key, "action": action})
	_sync()


## Remove a hint by key. A key that is not shown is a no-op.
func remove_hint(key: String) -> void:
	var removed := false
	for i in range(_current_hints.size() - 1, -1, -1):
		if _current_hints[i]["key"] == key:
			_current_hints.remove_at(i)
			removed = true
	if removed:
		_sync()


## The chip shown for [param key], or null. A chip that is fading out still
## counts until it is freed.
func chip_for(key: String) -> Control:
	return _chips.get(key)


func _are_hints_equal(new_hints: Array) -> bool:
	if new_hints.size() != _current_hints.size():
		return false
	for i in range(new_hints.size()):
		if (
			new_hints[i]["key"] != _current_hints[i]["key"]
			or new_hints[i]["action"] != _current_hints[i]["action"]
		):
			return false
	return true


## Bring the chips in line with [member _current_hints], animating only what
## changed. While the bar is hidden (or on its way out) nobody sees single
## chips, so stale ones go at once and new ones arrive opaque; the bar's own
## entrance carries them.
func _sync() -> void:
	if _current_hints.is_empty():
		_show_bar(false)
		return
	var animate := _bar_shown
	var wanted := {}
	for hint in _current_hints:
		wanted[hint["key"]] = true
	for key in _chips.keys():
		if wanted.has(key):
			continue
		if not animate:
			_drop_chip(key)
		elif not _leaving.has(key):
			_leaving[key] = true
			_fade_chip(key, 0.0)
	var previous: Control = null
	for hint in _current_hints:
		previous = _sync_chip(hint, previous, animate)
	_show_bar(true)


## Keep, revive or create the chip for [param hint] and place it after
## [param previous]. Kept chips move only when they sit before the chip they
## should follow, so chips fading out stay where they were.
func _sync_chip(hint: Dictionary, previous: Control, animate: bool) -> Control:
	var key: String = hint["key"]
	var chip: Control = _chips.get(key)
	if chip == null:
		chip = _create_hint_widget(key, hint["action"])
		_chips[key] = chip
		hints_container.add_child(chip)
		hints_container.move_child(chip, 0 if previous == null else previous.get_index() + 1)
		if animate:
			chip.modulate.a = 0.0
			_fade_chip(key, 1.0)
		return chip
	_action_label(chip).text = hint["action"]
	if _leaving.has(key):
		_leaving.erase(key)
		_fade_chip(key, 1.0)
	elif not animate:
		_kill_chip_tween(key)
		chip.modulate.a = 1.0
	if previous != null and chip.get_index() < previous.get_index():
		hints_container.move_child(chip, previous.get_index())
	return chip


func _fade_chip(key: String, alpha: float) -> void:
	_kill_chip_tween(key)
	var chip: Control = _chips[key]
	var fading_in := alpha > 0.0
	var tween := chip.create_tween().set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT if fading_in else Tween.EASE_IN)
	var duration := (
		Constants.ANIM_FADE_IN_DURATION if fading_in else Constants.ANIM_FADE_OUT_DURATION
	)
	tween.tween_property(chip, "modulate:a", alpha, duration)
	if not fading_in:
		tween.tween_callback(_drop_chip.bind(key))
	_chip_tweens[key] = tween


func _kill_chip_tween(key: String) -> void:
	var tween: Tween = _chip_tweens.get(key)
	if tween and tween.is_valid():
		tween.kill()
	_chip_tweens.erase(key)


## Free [param key]'s chip now. Its fade, bound to the chip, dies with it (this
## also runs as a fade-out's own last step, so it does not kill that tween).
func _drop_chip(key: String) -> void:
	_chip_tweens.erase(key)
	_leaving.erase(key)
	var chip: Control = _chips.get(key)
	_chips.erase(key)
	if chip == null:
		return
	hints_container.remove_child(chip)
	chip.queue_free()


func _show_bar(on: bool) -> void:
	if on == _bar_shown:
		return
	_bar_shown = on
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	# Each leg tweens from wherever an interrupted one left off, so rapid
	# show/hide calls never drift.
	_bar_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC)
	if on:
		_bar_tween.set_ease(Tween.EASE_OUT)
		_bar_tween.tween_property(_bar, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
		_bar_tween.tween_property(_bar, "offset_transform_position:y", 0.0, BAR_IN_DURATION)
		return
	_bar_tween.set_ease(Tween.EASE_IN)
	_bar_tween.tween_property(_bar, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	_bar_tween.tween_property(
		_bar, "offset_transform_position:y", SLIDE_DISTANCE, Constants.ANIM_FADE_OUT_DURATION
	)
	_bar_tween.chain().tween_callback(_on_bar_hidden)


## The bar is out of sight with nothing to show: free its chips.
func _on_bar_hidden() -> void:
	if _bar_shown:
		return
	for key in _chips.keys():
		_drop_chip(key)


func _create_hint_widget(key: String, action: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.name = "Hint_" + key.validate_node_name()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)

	var chip := PanelContainer.new()
	chip.theme_type_variation = &"KeyChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key_label := Label.new()
	key_label.text = key
	key_label.theme_type_variation = &"Body"
	chip.add_child(key_label)
	hbox.add_child(chip)

	var action_label := Label.new()
	action_label.name = "Action"
	action_label.text = action
	action_label.theme_type_variation = &"Caption"
	hbox.add_child(action_label)
	return hbox


func _action_label(chip: Control) -> Label:
	return chip.get_node("Action") as Label
