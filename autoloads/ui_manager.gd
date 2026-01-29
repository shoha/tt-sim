extends Node

## Centralized UI management for modals, overlays, and app state access.
##
## Provides:
## - Access to current app state (so any component can query it)
## - Modal management (push/pop modal stack with proper input handling)
## - Overlay tracking (for things like Level Editor that respond to ESC)
## - Centralized ESC key handling for closing modals/overlays and pause toggle

signal modal_opened(modal: Control)
signal modal_closed(modal: Control)

var _modal_stack: Array[Control] = []
var _overlay_stack: Array[Control] = []
var _root: Node = null

# State enum values (must match Root.State)
const STATE_TITLE_SCREEN := 0
const STATE_PLAYING := 1
const STATE_PAUSED := 2


func _ready() -> void:
	# Process input even when game is paused (for ESC to unpause)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Defer getting root reference until scene tree is ready
	call_deferred("_find_root")


func _find_root() -> void:
	_root = get_tree().root.get_node_or_null("Root")


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
		elif _root:
			var current_state := get_current_state()
			if current_state == STATE_PLAYING:
				_root.push_state(STATE_PAUSED)
				get_viewport().set_input_as_handled()
			elif current_state == STATE_PAUSED:
				_root.pop_state()
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


## Get current app state from Root
func get_current_state() -> int:
	if _root and _root.has_method("get_current_state"):
		return _root.get_current_state()
	return -1


## Check if app is in a specific state
func is_state(state: int) -> bool:
	return get_current_state() == state


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
