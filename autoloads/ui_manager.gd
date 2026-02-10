extends Node

## Centralized UI management for modals, overlays, and app state access.
##
## Provides:
## - Access to current app state (so any component can query it)
## - Modal management (push/pop modal stack with proper input handling)
## - Overlay tracking (for things like Level Editor that respond to ESC)
## - Centralized ESC key handling for closing modals/overlays and pause toggle
## - Confirmation dialogs
## - Toast notifications
## - Scene transitions
## - Loading screens
## - Input hints

signal modal_opened(modal: Control)
signal modal_closed(modal: Control)

var _modal_stack: Array[Control] = []
var _overlay_stack: Array[Control] = []

## Cached current state (updated via EventBus.state_changed).
## Values match RootScript.State enum (TITLE_SCREEN=0, ..., PLAYING=3, PAUSED=4).
var _current_state: int = -1

# State constants matching the Root.State enum so UIManager doesn't need to
# import root.gd.  Keep these in sync with Root.State if it changes.
const STATE_PLAYING := 3
const STATE_PAUSED := 4

# Preload scene resources at script load time
const CONFIRMATION_DIALOG_SCENE := preload("res://scenes/ui/confirmation_dialog.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TOAST_CONTAINER_SCENE := preload("res://scenes/ui/toast_container.tscn")
const TRANSITION_OVERLAY_SCENE := preload("res://scenes/ui/transition_overlay.tscn")
const LOADING_OVERLAY_SCENE := preload("res://scenes/ui/loading_overlay.tscn")
const INPUT_HINTS_SCENE := preload("res://scenes/ui/input_hints.tscn")
const DOWNLOAD_QUEUE_SCENE := preload("res://scenes/ui/download_queue.tscn")

# Persistent UI components
var _toast_container: Node = null
var _transition_overlay: Node = null
var _loading_overlay: Node = null
var _input_hints: Node = null
var _download_queue: Node = null


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

	_loading_overlay = LOADING_OVERLAY_SCENE.instantiate()
	add_child(_loading_overlay)

	_input_hints = INPUT_HINTS_SCENE.instantiate()
	add_child(_input_hints)

	_download_queue = DOWNLOAD_QUEUE_SCENE.instantiate()
	add_child(_download_queue)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Priority 1: Close modals
		if _modal_stack.size() > 0:
			close_top_modal()
			get_viewport().set_input_as_handled()
		# Priority 2: Close overlays (like Level Editor)
		elif _overlay_stack.size() > 0:
			_close_top_overlay()
			get_viewport().set_input_as_handled()
		# Priority 3: Toggle pause if playing
		elif _current_state == STATE_PLAYING:
			EventBus.pause_requested.emit()
			get_viewport().set_input_as_handled()
		elif _current_state == STATE_PAUSED:
			EventBus.resume_requested.emit()
			get_viewport().set_input_as_handled()


func _close_top_overlay() -> void:
	if _overlay_stack.size() > 0:
		var overlay = _overlay_stack[-1]
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


## Open a modal and add to stack
func open_modal(modal: Control, parent: Node = null) -> void:
	if parent:
		parent.add_child(modal)
	_modal_stack.push_back(modal)
	modal_opened.emit(modal)


## Close the top modal
func close_top_modal() -> void:
	if _modal_stack.size() > 0:
		var modal = _modal_stack.pop_back()
		modal_closed.emit(modal)
		modal.queue_free()


## Close a specific modal
func close_modal(modal: Control) -> void:
	var idx = _modal_stack.find(modal)
	if idx >= 0:
		_modal_stack.remove_at(idx)
		modal_closed.emit(modal)
		modal.queue_free()


## Check if any modal is open
func has_open_modal() -> bool:
	return _modal_stack.size() > 0


## Get the number of open modals
func get_modal_count() -> int:
	return _modal_stack.size()


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


# --- Loading Screen ---


## Show loading screen
func show_loading(title: String = "Loading...") -> void:
	if _loading_overlay:
		_loading_overlay.show_loading(title)


## Update loading progress (0.0 to 1.0)
func set_loading_progress(value: float, status: String = "") -> void:
	if _loading_overlay:
		_loading_overlay.set_progress(value, status)


## Hide loading screen
func hide_loading() -> void:
	if _loading_overlay:
		await _loading_overlay.hide_loading()


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
