extends Node

## Centralized UI management for overlays and app state access.
##
## Provides:
## - Access to current app state (so any component can query it)
## - Overlay tracking (for things like Level Editor that respond to ESC)
## - Centralized ESC key handling for closing overlays and pause toggle
## - Confirmation dialogs
## - Toast notifications
## - Scene transitions
## - Input hints

var _overlay_stack: Array[Control] = []

## Cached current state (updated via EventBus.state_changed).
## Values match RootScript.State enum (TITLE_SCREEN=0, ..., PLAYING=3, PAUSED=4).
var _current_state: int = -1

# Preload scene resources at script load time
const CONFIRMATION_DIALOG_SCENE := preload("res://scenes/ui/confirmation_dialog.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TOAST_CONTAINER_SCENE := preload("res://scenes/ui/toast_container.tscn")
const TRANSITION_OVERLAY_SCENE := preload("res://scenes/ui/transition_overlay.tscn")
const INPUT_HINTS_SCENE := preload("res://scenes/ui/input_hints.tscn")
const DOWNLOAD_QUEUE_SCENE := preload("res://scenes/ui/download_queue.tscn")
const HELP_OVERLAY_SCENE := preload("res://scenes/ui/help_overlay.tscn")

# Persistent UI components
var _toast_container: Node = null
var _transition_overlay: Node = null
var _input_hints: Node = null
var _download_queue: Node = null
var _help_overlay: Node = null


func _ready() -> void:
	# Process input even when game is paused (for ESC to unpause)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Listen for state changes via the EventBus (no Root import needed)
	EventBus.state_changed.connect(_on_state_changed)

	call_deferred("_setup_ui_components")


func _on_state_changed(_old_state: int, new_state: int) -> void:
	_current_state = new_state


func _setup_ui_components() -> void:
	# Create persistent UI components
	_toast_container = TOAST_CONTAINER_SCENE.instantiate()
	add_child(_toast_container)

	_transition_overlay = TRANSITION_OVERLAY_SCENE.instantiate()
	add_child(_transition_overlay)

	_input_hints = INPUT_HINTS_SCENE.instantiate()
	add_child(_input_hints)

	_download_queue = DOWNLOAD_QUEUE_SCENE.instantiate()
	add_child(_download_queue)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Clean stale overlays
		_overlay_stack = _overlay_stack.filter(func(o): return is_instance_valid(o))
		# Priority 1: Close overlays (like Level Editor)
		if _overlay_stack.size() > 0:
			_close_top_overlay()
			get_viewport().set_input_as_handled()
		# Priority 2: Toggle pause if playing
		elif _current_state == 3:  # Root.State.PLAYING
			EventBus.pause_requested.emit()
			get_viewport().set_input_as_handled()
		elif _current_state == 4:  # Root.State.PAUSED
			EventBus.resume_requested.emit()
			get_viewport().set_input_as_handled()


func _close_top_overlay() -> void:
	if _overlay_stack.size() > 0:
		var overlay = _overlay_stack.pop_back()
		if not is_instance_valid(overlay):
			return
		# Try animate_out first, then close, then just hide
		if overlay.has_method("animate_out"):
			overlay.animate_out()
		elif overlay.has_method("close"):
			overlay.close()
		else:
			overlay.hide()


## Get current app state (updated via EventBus.state_changed).
func get_current_state() -> int:
	return _current_state


## Check if app is in a specific state
func is_state(state: int) -> bool:
	return _current_state == state


# --- Overlay Management ---


## Register an overlay (like Level Editor) for ESC handling
func register_overlay(overlay: Control) -> void:
	if overlay not in _overlay_stack:
		_overlay_stack.push_back(overlay)


## Unregister an overlay
func unregister_overlay(overlay: Control) -> void:
	var idx = _overlay_stack.find(overlay)
	if idx >= 0:
		_overlay_stack.remove_at(idx)


## Check if any overlay is open
func has_open_overlay() -> bool:
	return _overlay_stack.size() > 0


## Get the number of open overlays
func get_overlay_count() -> int:
	return _overlay_stack.size()


# --- Confirmation Dialog ---


## Show a confirmation dialog and return it for await
func show_confirmation(
	title: String,
	message: String,
	confirm_text: String = "Confirm",
	cancel_text: String = "Cancel",
	confirm_callback: Callable = Callable(),
	cancel_callback: Callable = Callable(),
	confirm_style: String = "Success",
	confirm_sound_override: Callable = Callable()
) -> Node:
	var dialog = CONFIRMATION_DIALOG_SCENE.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		title,
		message,
		confirm_text,
		cancel_text,
		confirm_callback,
		cancel_callback,
		confirm_style,
		confirm_sound_override
	)
	return dialog


## Show a danger confirmation (e.g., for delete actions)
func show_danger_confirmation(
	title: String, message: String, confirm_callback: Callable = Callable()
) -> Node:
	return show_confirmation(
		title, message, "Delete", "Cancel", confirm_callback, Callable(), "Danger"
	)


# --- Toast Notifications ---

## Toast type constants (must match ToastContainer.ToastType)
const TOAST_INFO := 0
const TOAST_SUCCESS := 1
const TOAST_WARNING := 2
const TOAST_ERROR := 3


## Show a toast notification
func show_toast(message: String, type: int = TOAST_INFO, duration: float = 3.0) -> void:
	if _toast_container and _toast_container.has_method("show_toast"):
		_toast_container.show_toast(message, type, duration)


## Show an info toast
func show_info(message: String) -> void:
	show_toast(message, TOAST_INFO)


## Show a success toast
func show_success(message: String) -> void:
	show_toast(message, TOAST_SUCCESS)


## Show a warning toast
func show_warning(message: String) -> void:
	show_toast(message, TOAST_WARNING)


## Show an error toast
func show_error(message: String) -> void:
	show_toast(message, TOAST_ERROR)


# --- Scene Transitions ---


## Fade out the screen
func fade_out(duration: float = 0.3) -> void:
	if _transition_overlay:
		await _transition_overlay.fade_out(duration)


## Fade in the screen
func fade_in(duration: float = 0.3) -> void:
	if _transition_overlay:
		await _transition_overlay.fade_in(duration)


## Perform a transition with a callback in the middle
func transition(
	middle_callback: Callable, fade_out_duration: float = 0.3, fade_in_duration: float = 0.3
) -> void:
	if _transition_overlay:
		await _transition_overlay.transition(middle_callback, fade_out_duration, fade_in_duration)


## Check if currently transitioning
func is_transitioning() -> bool:
	return _transition_overlay and _transition_overlay.is_transitioning()


# --- Input Hints ---


## Set input hints to display
func set_hints(hints: Array) -> void:
	if _input_hints:
		_input_hints.set_hints(hints)


## Clear all input hints
func clear_hints() -> void:
	if _input_hints:
		_input_hints.clear_hints()


## Add a single input hint
func add_hint(key: String, action: String) -> void:
	if _input_hints:
		_input_hints.add_hint(key, action)


## Remove an input hint
func remove_hint(key: String) -> void:
	if _input_hints:
		_input_hints.remove_hint(key)


# --- Settings Menu ---


## Open the settings menu
func open_settings() -> Node:
	var settings = SETTINGS_MENU_SCENE.instantiate()
	get_tree().root.add_child(settings)
	return settings


## Open the help overlay (F1)
func open_help() -> void:
	if _help_overlay and is_instance_valid(_help_overlay):
		return
	_help_overlay = HELP_OVERLAY_SCENE.instantiate()
	get_tree().root.add_child(_help_overlay)


## Close the help overlay
func close_help() -> void:
	if _help_overlay and is_instance_valid(_help_overlay):
		if _help_overlay.has_method("animate_out"):
			_help_overlay.animate_out()
		_help_overlay = null


## Toggle the help overlay
func toggle_help() -> void:
	if _help_overlay and is_instance_valid(_help_overlay):
		close_help()
	else:
		open_help()
