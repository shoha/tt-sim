class_name LevelPickerDialog
extends AnimatedCanvasLayerPanel

## Modal map chooser: the room's Add a map and the pause menu's Change map. Wraps a two-column
## LevelGrid; Choose confirms the selected card and double-click chooses directly. Its cards
## only choose, so they carry no management menu (that is the library's, on the title). The
## grid grows with the canvas so a short library shows whole: as tall as its cards, between
## MIN_GRID_HEIGHT and MAX_GRID_HEIGHT and never past the canvas less the sheet's own chrome
## and an EDGE above and below; past that it scrolls (_fit_grid()).

signal level_chosen(level_info: Dictionary)
signal closed

const MIN_GRID_HEIGHT := 240.0
const MAX_GRID_HEIGHT := 760.0
## The sheet's least distance from the canvas's top and bottom.
const EDGE := 32.0

var grid: LevelGrid
var provider: Callable = LevelManager.get_saved_levels

var _title: String = "Choose a map"
var _locked_path: String = ""
var _closing: bool = false

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
	grid.manageable = false
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.selection_changed.connect(_on_selection_changed)
	grid.level_activated.connect(_on_level_activated)
	grid.levels_changed.connect(_on_levels_changed)
	grid.content_resized.connect(_fit_grid)
	grid_slot.add_child(grid)
	get_viewport().size_changed.connect(_fit_grid)
	grid.refresh()
	choose_button.pressed.connect(_on_choose_pressed)
	cancel_button.set_meta("ui_silent", true)
	cancel_button.pressed.connect(_on_cancel_pressed)
	UIManager.register_overlay($ColorRect as Control)


func _on_after_animate_in() -> void:
	cancel_button.grab_focus()


## Size the grid to its cards within the canvas (see the class comment).
func _fit_grid() -> void:
	if grid == null or not is_inside_tree():
		return
	var sheet := grid_slot.get_parent().get_parent() as Control
	var chrome := sheet.get_combined_minimum_size().y - grid_slot.get_combined_minimum_size().y
	var room := get_viewport().get_visible_rect().size.y - chrome - EDGE * 2.0
	var most := maxf(MIN_GRID_HEIGHT, minf(room, MAX_GRID_HEIGHT))
	var target := floorf(clampf(grid.content_height(), MIN_GRID_HEIGHT, most))
	if not is_equal_approx(grid_slot.custom_minimum_size.y, target):
		grid_slot.custom_minimum_size.y = target


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


func _on_selection_changed(_info: Dictionary) -> void:
	choose_button.disabled = false


func _on_levels_changed() -> void:
	choose_button.disabled = grid.selected_info().is_empty()


func _on_level_activated(info: Dictionary) -> void:
	_choose(info)


func _on_choose_pressed() -> void:
	var info := grid.selected_info()
	if info.is_empty():
		return
	_choose(info)


func _choose(info: Dictionary) -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"confirm")
	level_chosen.emit(info)
	animate_out()


func _on_cancel_pressed() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"cancel")
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
