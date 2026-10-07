class_name AvatarRoster
extends AnimatedCanvasLayerPanel

## The title screen's "Avatars": the player's saved avatars (AvatarLibrary) as cards with
## their rendered figures (AvatarGrid, AvatarThumbnails), led by a "Make an avatar" card.
## A card opens the builder on that avatar (AvatarBuilder.open_for_library, no game or map
## needed) and its overflow menu offers Edit, Duplicate and Delete (Delete asks first).
## With no avatars yet the panel invites the first one. The grid follows the library, so
## a builder save shows at once.

signal closed

const SCENE_PATH := "res://scenes/ui/avatar_roster.tscn"
## The panel's share of the window and its limits.
const PANEL_SHARE := Vector2(0.72, 0.8)
const PANEL_MIN := Vector2(720, 520)
const PANEL_MAX := Vector2(1280, 1100)
const COLUMNS := 5
## The panel's height besides the grid (header, empty note, footer, padding), and the
## least grid height.
const GRID_CHROME := 190.0
const MIN_GRID_HEIGHT := 200.0

var grid: AvatarGrid
var _closing := false
var _max_grid_height := 600.0

@onready var panel: PanelContainer = %PanelContainer
@onready var content: VBoxContainer = %Content
@onready var header_slot: VBoxContainer = %HeaderSlot
@onready var empty_box: VBoxContainer = %Empty
@onready var grid_slot: VBoxContainer = %GridSlot
@onready var count_label: Label = %Count
@onready var done_button: Button = %DoneButton


## Opens the roster under `parent`.
static func open(parent: Node) -> AvatarRoster:
	var roster := (load(SCENE_PATH) as PackedScene).instantiate() as AvatarRoster
	parent.add_child(roster)
	return roster


func _on_panel_ready() -> void:
	var header := MenuHeader.new()
	header.name = "Header"
	header_slot.add_child(header)
	header.setup("Your avatars", "Make your characters ahead of time; place them in any game", true)
	header.close_requested.connect(close)
	grid = AvatarGrid.new()
	grid.name = "Grid"
	grid.columns = COLUMNS
	grid.with_menu = true
	grid.make_caption = "A pose, a face, colours"
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.avatar_pressed.connect(edit)
	grid.make_pressed.connect(make)
	grid.action_requested.connect(_on_action_requested)
	grid_slot.add_child(grid)
	grid.content_resized.connect(func() -> void: _fit_height.call_deferred())
	AvatarLibrary.events().changed.connect(_refresh_state)
	grid.refresh()
	_refresh_state()
	done_button.pressed.connect(close)
	get_viewport().size_changed.connect(_fit_to_window)
	_fit_to_window()


func _exit_tree() -> void:
	super._exit_tree()
	if AvatarLibrary.events().changed.is_connected(_refresh_state):
		AvatarLibrary.events().changed.disconnect(_refresh_state)


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children(content)


## Opens the builder for a new avatar; its save lands in the library.
func make() -> AvatarBuilder:
	return AvatarBuilder.open_for_library(get_tree().root)


## Opens the builder on saved avatar `entry`.
func edit(entry: Dictionary) -> AvatarBuilder:
	return AvatarBuilder.open_for_library(get_tree().root, entry)


func close() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play_cancel()
	animate_out()


func _on_after_animate_out() -> void:
	closed.emit()
	queue_free()


func _on_action_requested(entry: Dictionary, action: StringName) -> void:
	match action:
		&"edit":
			edit(entry)
		&"duplicate":
			AvatarLibrary.duplicate_entry(String(entry.id))
		&"delete":
			UIManager.show_danger_confirmation(
				"Delete avatar",
				"Delete %s? This cannot be undone." % String(entry.name),
				func() -> void: AvatarLibrary.delete(String(entry.id))
			)


func _refresh_state() -> void:
	var count := AvatarLibrary.list().size()
	empty_box.visible = count == 0
	count_label.text = "%d avatar%s" % [count, "" if count == 1 else "s"]
	_fit_height.call_deferred()


## A large share of the window's width, within limits; the height follows the cards (an
## empty or small library gives a short panel), up to a share of the window.
func _fit_to_window() -> void:
	var window := get_viewport().get_visible_rect().size
	var wanted := (window * PANEL_SHARE).clamp(PANEL_MIN, PANEL_MAX)
	panel.custom_minimum_size = Vector2(minf(wanted.x, window.x - 48.0), 0.0)
	_max_grid_height = minf(wanted.y, window.y - 48.0) - GRID_CHROME
	_fit_height.call_deferred()


## The grid's height: its cards, up to what the window allows (then it scrolls).
func _fit_height() -> void:
	if grid == null:
		return
	var most := maxf(_max_grid_height, MIN_GRID_HEIGHT)
	var height := clampf(grid.content_height(), MIN_GRID_HEIGHT, most)
	if not is_equal_approx(grid_slot.custom_minimum_size.y, height):
		grid_slot.custom_minimum_size.y = height


func _unhandled_input(event: InputEvent) -> void:
	# A builder or a confirmation opened over the roster takes Escape itself.
	if event.is_action_pressed("ui_cancel") and is_top_trap():
		close()
		get_viewport().set_input_as_handled()
