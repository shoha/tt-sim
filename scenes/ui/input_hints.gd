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
##
## A tool (the measure tool) lays its own keys over the base hints with set_tool_hints: they
## lead the row, and of the base hints only KEPT_WITH_A_TOOL stays, so the camera keys step
## out while a tool is active and its row fits one line at 720p. The base hints are kept
## underneath, untouched, and come back in their own order when the tool clears its layer.
##
## The bar never lies under an open drawer, under a bottom-corner button or past the canvas
## edge. It centres in the span of the board the open drawers leave free
## (DrawerContainer.free_span), sliding there by its backdrop's offset_transform_position.x as
## a drawer slides. Shown controls in OBSTACLES (the play HUD's Add token and Save map) end
## that span where they stand, and the bar moves aside only as far as they need. Its row (a
## centred flow) is held to the span less DRAWER_CLEARANCE each side, so a row longer than the
## span wraps onto a second line, growing up from the bottom edge: the play row beside the
## Visuals drawer and Add token, or beside the room drawer at 150%. Drawers tell it when they
## open or close (DrawerContainer.WATCHERS), an obstacle when it shows or hides; a window
## resize and a change of chips refit it too.

## How far below its resting place the bar starts its entrance, in pixels.
const SLIDE_DISTANCE := 12.0
const BAR_IN_DURATION := 0.25
## The least space between the bar and an open drawer or the canvas edge, each side (space_3).
const DRAWER_CLEARANCE := 12.0
## The drawer slide's length (DrawerContainer.slide_duration), so the bar moves with it.
const SHIFT_DURATION := 0.25
## Controls along the bottom edge the bar keeps clear of.
const OBSTACLES := &"hint_bar_obstacles"
## Base hint keys that stay beside a tool's own: Help.
const KEPT_WITH_A_TOOL: Array[String] = ["F1"]

## The base hints (set_hints, add_hint, remove_hint).
var _current_hints: Array[Dictionary] = []
## The active tool's own hints; while any, they lead and replace the base hints but the kept.
var _tool_hints: Array[Dictionary] = []
## Key -> chip, for every chip in the row, leaving ones included.
var _chips: Dictionary = {}
## Key -> the chip's running fade.
var _chip_tweens: Dictionary = {}
## Keys whose chip is fading out.
var _leaving: Dictionary = {}
var _bar_tween: Tween
var _bar_shown: bool = false
## Where the backdrop stands for the open drawers: its x shift.
var _shift_tween: Tween
var _shift: float = 0.0

@onready var hints_container: HFlowContainer = %HintRow
@onready var _bar: MarginContainer = %HintBar
@onready var _backdrop: PanelContainer = %BackdropPanel


func _ready() -> void:
	_bar.modulate.a = 0.0
	_bar.offset_transform_enabled = true
	_bar.offset_transform_position = Vector2(0.0, SLIDE_DISTANCE)
	_backdrop.offset_transform_enabled = true
	add_to_group(DrawerContainer.WATCHERS)
	get_viewport().size_changed.connect(on_drawers_moved, CONNECT_DEFERRED)


## Centre the bar in the board span the open drawers leave free, as near that centre as the
## obstacles allow, and hold its row to the clear span. The move is animated while the bar
## shows, so it slides beside the drawer.
func on_drawers_moved() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var span := DrawerContainer.free_span(viewport)
	var centre := (span.x + span.y) / 2.0
	var clear := _clear_span(viewport, span, centre)
	var half := _fit_row(clear.y - clear.x - 2.0 * DRAWER_CLEARANCE) / 2.0
	var lowest := clear.x + DRAWER_CLEARANCE + half
	var place := clampf(centre, lowest, maxf(clear.y - DRAWER_CLEARANCE - half, lowest))
	var shift := place - viewport.get_visible_rect().get_center().x
	if is_equal_approx(shift, _shift):
		return
	_shift = shift
	if _shift_tween and _shift_tween.is_valid():
		_shift_tween.kill()
	if not _bar_shown:
		_backdrop.offset_transform_position.x = shift
		return
	_shift_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shift_tween.tween_property(_backdrop, "offset_transform_position:x", shift, SHIFT_DURATION)


## `span` narrowed by the shown OBSTACLES in it: one right of `centre` ends it there, one left
## of it starts it. Each obstacle refits the bar when it shows or hides.
func _clear_span(viewport: Viewport, span: Vector2, centre: float) -> Vector2:
	var clear := span
	for node in get_tree().get_nodes_in_group(OBSTACLES):
		var control := node as Control
		if control == null or control.get_viewport() != viewport:
			continue
		if not control.visibility_changed.is_connected(on_drawers_moved):
			control.visibility_changed.connect(on_drawers_moved)
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if rect.end.x <= span.x or rect.position.x >= span.y:
			continue
		if rect.get_center().x >= centre:
			clear.y = minf(clear.y, rect.position.x)
		else:
			clear.x = maxf(clear.x, rect.end.x)
	return clear


## Hold the backdrop to the row's one-line width, or to `room` when that is narrower (the
## flow then wraps), and return that width. A width, not an animation: it changes with the
## chips or the span.
func _fit_row(room: float) -> float:
	var chips := 0
	var line := 0.0
	for chip in hints_container.get_children():
		line += (chip as Control).get_combined_minimum_size().x
		chips += 1
	if chips > 1:
		line += float(hints_container.get_theme_constant(&"h_separation")) * float(chips - 1)
	line += _backdrop.get_theme_stylebox(&"panel").get_minimum_size().x
	_backdrop.custom_minimum_size.x = minf(line, maxf(room, 0.0))
	return _backdrop.custom_minimum_size.x


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


## Lay a tool's own hints over the base ones while it is active (see the header). Each hint
## is a dictionary with "key" and "action", as for set_hints; an empty array clears the layer.
func set_tool_hints(hints: Array) -> void:
	var next: Array[Dictionary] = []
	for hint in hints:
		next.append({"key": String(hint["key"]), "action": String(hint["action"])})
	if next == _tool_hints:
		return
	_tool_hints = next
	_sync()


## Drop the tool's layer: the base hints return in their own order.
func clear_tool_hints() -> void:
	set_tool_hints([])


## What the row shows, in order: the base hints, or the tool's hints followed by the base
## hints in KEPT_WITH_A_TOOL.
func shown_hints() -> Array[Dictionary]:
	if _tool_hints.is_empty():
		return _current_hints
	var shown: Array[Dictionary] = _tool_hints.duplicate()
	var taken := {}
	for hint in shown:
		taken[hint["key"]] = true
	for hint in _current_hints:
		if KEPT_WITH_A_TOOL.has(hint["key"]) and not taken.has(hint["key"]):
			shown.append(hint)
	return shown


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


## Bring the chips in line with shown_hints(), animating only what changed. While
## the bar is hidden (or on its way out) nobody sees single chips, so stale ones
## go at once and new ones arrive opaque; the bar's own entrance carries them.
func _sync() -> void:
	var shown := shown_hints()
	if shown.is_empty():
		_show_bar(false)
		return
	var animate := _bar_shown
	var wanted := {}
	for hint in shown:
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
	for hint in shown:
		previous = _sync_chip(hint, previous, animate)
	on_drawers_moved()
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
	on_drawers_moved()


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
