extends CanvasLayer
class_name AnimatedCanvasLayerPanel

## Base class for CanvasLayer panels with backdrop + centered panel animation and sounds.
##
## Provides the same modular pattern as AnimatedVisibilityContainer but for
## full-screen CanvasLayer overlays (settings, dialogs, pause menu, etc.).
##
## Expected scene structure:
##   CanvasLayer (this)
##   ├── ColorRect          (semi-transparent backdrop)
##   └── CenterContainer
##       └── PanelContainer (the content panel)
##
## Subclasses override _on_panel_ready() instead of _ready() and can hook into
## _on_after_animate_in() / _on_before_animate_out() / _on_after_animate_out().

@export var play_sounds: bool = true
## When true, Tab/Shift+Tab focus cycling is trapped within the panel.
@export var trap_focus: bool = true

var _panel_tween: Tween
var _focusable_controls: Array[Control] = []


func _ready() -> void:
	# Start hidden for animation
	$ColorRect.modulate.a = 0.0
	$CenterContainer.modulate.a = 0.0

	# Let subclass do its setup (connect signals, load data, etc.)
	_on_panel_ready()

	# Build focus ring for trapping
	if trap_focus:
		_build_focusable_list()

	# Animate in
	animate_in()


## Override this in subclasses instead of _ready().
func _on_panel_ready() -> void:
	pass


## Smoothly show the panel with scale + fade animation.
func animate_in() -> void:
	if _panel_tween:
		_panel_tween.kill()

	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.9, 0.9)

	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.set_ease(Tween.EASE_OUT)
	_panel_tween.set_trans(Tween.TRANS_BACK)
	_panel_tween.tween_property($ColorRect, "modulate:a", 1.0, 0.2)
	_panel_tween.tween_property($CenterContainer, "modulate:a", 1.0, 0.2)
	_panel_tween.tween_property(panel, "scale", Vector2.ONE, 0.2)

	if play_sounds:
		AudioManager.play_open()

	await _panel_tween.finished
	_on_after_animate_in()


## Smoothly hide the panel with scale + fade animation, then queue_free().
func animate_out() -> void:
	_on_before_animate_out()

	if _panel_tween:
		_panel_tween.kill()

	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2

	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.set_ease(Tween.EASE_IN)
	_panel_tween.set_trans(Tween.TRANS_CUBIC)
	_panel_tween.tween_property($ColorRect, "modulate:a", 0.0, 0.15)
	_panel_tween.tween_property($CenterContainer, "modulate:a", 0.0, 0.15)
	_panel_tween.tween_property(panel, "scale", Vector2(0.95, 0.95), 0.15)

	if play_sounds:
		AudioManager.play_close()

	await _panel_tween.finished
	_on_after_animate_out()


# ---------------------------------------------------------------------------
# Focus trap
# ---------------------------------------------------------------------------


## Collect all focusable controls inside the panel for Tab-wrapping.
func _build_focusable_list() -> void:
	_focusable_controls.clear()
	_collect_focusable($CenterContainer, _focusable_controls)


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		if c.visible and c.focus_mode != Control.FOCUS_NONE and not c.is_set_as_top_level():
			out.append(c)
	for child in node.get_children():
		_collect_focusable(child, out)


func _input(event: InputEvent) -> void:
	if not trap_focus or _focusable_controls.is_empty():
		return
	if (
		not event.is_action_pressed("ui_focus_next")
		and not event.is_action_pressed("ui_focus_prev")
	):
		return

	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _focusable_controls.has(focused):
		# Focus escaped — pull it back
		_focusable_controls[0].grab_focus()
		get_viewport().set_input_as_handled()
		return

	var idx := _focusable_controls.find(focused)
	if event.is_action_pressed("ui_focus_next") and idx == _focusable_controls.size() - 1:
		_focusable_controls[0].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_prev") and idx == 0:
		_focusable_controls[_focusable_controls.size() - 1].grab_focus()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Lifecycle hooks — override in subclasses
# ---------------------------------------------------------------------------


## Called after the animate-in tween finishes (e.g. grab focus on a button).
func _on_after_animate_in() -> void:
	pass


## Called before the animate-out tween starts (e.g. unregister overlay).
func _on_before_animate_out() -> void:
	pass


## Called after the animate-out tween finishes. Default: queue_free().
func _on_after_animate_out() -> void:
	queue_free()
