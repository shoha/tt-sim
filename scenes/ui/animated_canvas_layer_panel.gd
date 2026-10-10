class_name AnimatedCanvasLayerPanel
extends CanvasLayer

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
## Rows that should fade and lift in one after another are returned from
## _stagger_targets(); the base hides them before the first frame and runs the
## stagger alongside animate_in().
##
## One scrim (docs/UI_TASTE.md G1): a panel opened over a live panel whose ColorRect is a
## Scrim (a confirmation over the pause menu, the picker over it) lays no scrim of its own,
## since a second one darkened the sheet below to grey-mauve. It stands on the scrim already
## there and takes the place of the sheet below, which fades out (cover) and comes back, with
## its focus, as the panel over it closes.

## Stack of live panels, topmost last. Only the topmost panel traps Tab, so a
## dialog opened over another panel (e.g. LevelPickerDialog over the pause
## menu) does not have its Tab presses yanked back into the panel below it.
static var _trap_stack: Array[AnimatedCanvasLayerPanel] = []

@export var play_sounds: bool = true
## When true, Tab/Shift+Tab focus cycling is trapped within the panel.
@export var trap_focus: bool = true

var _panel_tween: Tween
var _focusable_controls: Array[Control] = []
## The scrimmed panel this one stands over and hides (see the header), or null.
var _covered: AnimatedCanvasLayerPanel = null
var _cover_tween: Tween
## The control that had focus in this panel when a panel covered it, for its return.
var _focus_before_cover: Control = null
var _leaving: bool = false


func _ready() -> void:
	# Start hidden for animation
	$ColorRect.modulate.a = 0.0
	$CenterContainer.modulate.a = 0.0

	# Let subclass do its setup (connect signals, load data, etc.)
	_on_panel_ready()

	# Build focus ring for trapping
	if trap_focus:
		rebuild_focus_trap()

	# Over a scrimmed panel, share its scrim and take the place of its sheet (one scrim).
	_covered = _scrimmed_panel_below()
	if _covered != null:
		($ColorRect as CanvasItem).self_modulate.a = 0.0
		_covered.cover(true)

	# Register as the topmost panel, even when trap_focus is false — a
	# non-trapping panel is still the topmost surface, so a lower trapping
	# panel must not steal Tab from it.
	_trap_stack.push_back(self)

	# Hide the staggered rows before anything is drawn, then start both entrances in
	# this same synchronous run: UiMotion.stagger_in zeroes its targets' alpha before
	# its first await, so no frame ever shows the rows at full alpha, and the rows
	# begin lifting in two frames later while the panel itself is still fading.
	var targets := _stagger_targets()
	animate_in()
	if not targets.is_empty():
		UiMotion.stagger_in(targets, self)


func _exit_tree() -> void:
	_trap_stack.erase(self)
	_uncover()


## The topmost live panel below this one that stands on a scrim (its ColorRect is a Scrim),
## or null.
func _scrimmed_panel_below() -> AnimatedCanvasLayerPanel:
	for i in range(_trap_stack.size() - 1, -1, -1):
		var panel := _trap_stack[i]
		if not is_instance_valid(panel) or panel == self or panel._leaving:
			continue
		if not panel.is_inside_tree() or panel.is_queued_for_deletion():
			continue
		var backdrop := panel.get_node_or_null("ColorRect") as CanvasItem
		if backdrop is Scrim and backdrop.is_visible_in_tree():
			return panel
		return null
	return null


## Fade this panel's sheet out while a panel stacked over it holds the screen (`on`), or
## back in, giving focus back to the control that had it.
func cover(on: bool) -> void:
	var sheet := $CenterContainer/PanelContainer as Control
	if _cover_tween and _cover_tween.is_valid():
		_cover_tween.kill()
	_cover_tween = create_tween().set_trans(Tween.TRANS_CUBIC)
	if on:
		var focused := get_viewport().gui_get_focus_owner()
		_focus_before_cover = focused if focused != null and sheet.is_ancestor_of(focused) else null
		_cover_tween.set_ease(Tween.EASE_IN)
		_cover_tween.tween_property(sheet, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
		_cover_tween.tween_callback(sheet.hide)
		return
	sheet.show()
	_cover_tween.set_ease(Tween.EASE_OUT)
	_cover_tween.tween_property(sheet, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	if is_instance_valid(_focus_before_cover) and _focus_before_cover.is_visible_in_tree():
		_focus_before_cover.grab_focus()
	_focus_before_cover = null


## Give the covered panel its sheet back, once.
func _uncover() -> void:
	var below := _covered
	_covered = null
	if not is_instance_valid(below) or below._leaving:
		return
	if below.is_inside_tree() and not below.is_queued_for_deletion():
		below.cover(false)


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
	_panel_tween.tween_property($ColorRect, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	_panel_tween.tween_property(
		$CenterContainer, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION
	)
	_panel_tween.tween_property(panel, "scale", Vector2.ONE, Constants.ANIM_FADE_IN_DURATION)

	if play_sounds:
		AudioManager.play(&"open")

	await _panel_tween.finished
	if not is_instance_valid(self):
		return
	_on_after_animate_in()


## Smoothly hide the panel with scale + fade animation, then queue_free().
func animate_out() -> void:
	_leaving = true
	_on_before_animate_out()
	# The sheet below comes back as this one goes.
	_uncover()

	if _panel_tween:
		_panel_tween.kill()

	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2

	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.set_ease(Tween.EASE_IN)
	_panel_tween.set_trans(Tween.TRANS_CUBIC)
	_panel_tween.tween_property($ColorRect, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	_panel_tween.tween_property(
		$CenterContainer, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION
	)
	_panel_tween.tween_property(
		panel, "scale", Vector2(0.95, 0.95), Constants.ANIM_FADE_OUT_DURATION
	)

	if play_sounds:
		AudioManager.play(&"close")

	await _panel_tween.finished
	if not is_instance_valid(self):
		return
	_on_after_animate_out()


# ---------------------------------------------------------------------------
# Focus trap
# ---------------------------------------------------------------------------


## Collect all focusable controls inside the panel for Tab-wrapping. Re-callable:
## a subclass that hides/shows containers after _ready() (see LobbyClient's join form) must
## call this again after each swap, or the trap keeps naming controls that are
## no longer visible.
func rebuild_focus_trap() -> void:
	_focusable_controls.clear()
	_collect_focusable($CenterContainer, _focusable_controls)


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		if (
			c.is_visible_in_tree()
			and c.focus_mode != Control.FOCUS_NONE
			and not c.is_set_as_top_level()
		):
			out.append(c)
	for child in node.get_children():
		_collect_focusable(child, out)


## True while any panel is live (a sheet is up), for keys that must not reach the board
## under it, such as the room drawer's Tab.
static func any_open() -> bool:
	return _trap_stack.any(func(p: AnimatedCanvasLayerPanel) -> bool: return is_instance_valid(p))


## True when this panel is the topmost live panel and should trap Tab.
## Prunes freed panels from the stack before checking.
func is_top_trap() -> bool:
	_trap_stack = _trap_stack.filter(
		func(p: AnimatedCanvasLayerPanel) -> bool: return is_instance_valid(p)
	)
	return not _trap_stack.is_empty() and _trap_stack.back() == self


func _input(event: InputEvent) -> void:
	if not trap_focus or _focusable_controls.is_empty():
		return
	if not is_top_trap():
		return
	if (
		not event.is_action_pressed("ui_focus_next")
		and not event.is_action_pressed("ui_focus_prev")
	):
		return

	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _focusable_controls.has(focused):
		# Focus escaped — pull it back to the first visible entry.
		if _grab_visible(0, 1):
			get_viewport().set_input_as_handled()
		return

	var idx := _focusable_controls.find(focused)
	if event.is_action_pressed("ui_focus_next") and idx == _focusable_controls.size() - 1:
		if _grab_visible(0, 1):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_prev") and idx == 0:
		if _grab_visible(_focusable_controls.size() - 1, -1):
			get_viewport().set_input_as_handled()


## Grab focus on the first visible entry found walking from [param start_idx]
## by [param step] (1 forward, -1 backward), wrapping once around the whole
## list. Returns false without touching focus if nothing in the list is
## currently visible — the trap must never consume the event in that case.
func _grab_visible(start_idx: int, step: int) -> bool:
	var count := _focusable_controls.size()
	for i in range(count):
		var idx := (start_idx + i * step + count) % count
		var control := _focusable_controls[idx]
		if control.is_visible_in_tree():
			control.grab_focus()
			return true
	return false


# ---------------------------------------------------------------------------
# Lifecycle hooks — override in subclasses
# ---------------------------------------------------------------------------


## Called after the animate-in tween finishes (e.g. grab focus on a button).
func _on_after_animate_in() -> void:
	pass


## Controls to fade and lift in one after another as the panel appears, usually
## UiMotion.visible_children() of the content box. Return them here rather than
## calling UiMotion.stagger_in from _on_after_animate_in: that ordering let the rows
## fade in with the panel and then snapped them to alpha 0 for a second entrance
## (the pause menu's "appears, vanishes, animates in" report, 2026-09-17).
func _stagger_targets() -> Array[Control]:
	return []


## Called before the animate-out tween starts (e.g. unregister overlay).
func _on_before_animate_out() -> void:
	pass


## Called after the animate-out tween finishes. Default: queue_free().
func _on_after_animate_out() -> void:
	queue_free()
