class_name LevelPickerDialog
extends AnimatedCanvasLayerPanel

## Modal level chooser used by the host lobby's Change button and the pause
## menu's Change Level. Wraps a two-column LevelGrid; Choose confirms the
## selected card and double-click chooses directly. Replaces LevelBrowserDialog.

signal level_chosen(level_info: Dictionary)
signal closed

var grid: LevelGrid
var provider: Callable = LevelManager.get_saved_levels

var _title: String = "Choose a level"
var _locked_path: String = ""
var _chosen: bool = false

@onready var title_label: Label = %TitleLabel
@onready var grid_slot: VBoxContainer = %GridSlot
@onready var choose_button: Button = %ChooseButton
@onready var cancel_button: Button = %CancelButton


func setup(title: String, locked_path: String = "") -> void:
	_title = title
	_locked_path = locked_path
	if title_label:
		title_label.text = title


func _on_panel_ready() -> void:
	title_label.text = _title
	grid = LevelGrid.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.provider = provider
	grid.locked_path = _locked_path
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.selection_changed.connect(_on_selection_changed)
	grid.level_activated.connect(_on_level_activated)
	grid_slot.add_child(grid)
	grid.refresh()
	choose_button.pressed.connect(_on_choose_pressed)
	cancel_button.set_meta("ui_silent", true)
	cancel_button.pressed.connect(_on_cancel_pressed)
	UIManager.register_overlay($ColorRect as Control)


func _on_after_animate_in() -> void:
	cancel_button.grab_focus()


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


func _on_selection_changed(_info: Dictionary) -> void:
	choose_button.disabled = false


func _on_level_activated(info: Dictionary) -> void:
	_choose(info)


func _on_choose_pressed() -> void:
	var info := grid.selected_info()
	if info.is_empty():
		return
	_choose(info)


func _choose(info: Dictionary) -> void:
	if _chosen:
		return
	_chosen = true
	AudioManager.play_confirm()
	level_chosen.emit(info)
	animate_out()


func _on_cancel_pressed() -> void:
	AudioManager.play_cancel()
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
