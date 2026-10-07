class_name AvatarTab
extends MarginContainer

## The "Avatar" tab of the Add Token browser: the player's saved avatars (AvatarLibrary,
## made on the title screen or saved from a game) as cards with their figures, where one
## click places the avatar and a drag carries it onto the map (as a pack asset drags),
## followed by one tall action that opens the avatar builder for a new one. The browser
## relays them to GameplayMenuController, which spawns the avatar where an asset would land.

signal build_requested
signal avatar_chosen(entry: Dictionary)
## A card dragged past the drag threshold; `icon` is its picture.
signal avatar_drag_started(entry: Dictionary, icon: Texture2D)

const TAB_TITLE := "Avatar"
const COLUMNS := 4
const EMPTY_CAPTION := "Avatars you save show here. Make one, or use Avatars on the title screen."

var grid: AvatarGrid
var _heading: Label
var _empty: Label

@onready var content: VBoxContainer = %Content
@onready var actions: VBoxContainer = %Actions


func _ready() -> void:
	var button := UiActions.primary(
		"Make an avatar",
		"wand",
		"Pick a pose, a face, colours and a shape; the figure follows every pick.",
		actions
	)
	button.pressed.connect(func() -> void: build_requested.emit())
	_heading = Label.new()
	_heading.name = "Heading"
	_heading.text = "Your avatars"
	_heading.theme_type_variation = &"H3"
	content.add_child(_heading)
	_empty = Label.new()
	_empty.name = "Empty"
	_empty.text = EMPTY_CAPTION
	_empty.theme_type_variation = &"Caption"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_empty)
	grid = AvatarGrid.new()
	grid.name = "Grid"
	grid.columns = COLUMNS
	grid.make_card = false
	grid.draggable = true
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.avatar_pressed.connect(func(entry: Dictionary) -> void: avatar_chosen.emit(entry))
	grid.avatar_drag_started.connect(avatar_drag_started.emit)
	content.add_child(grid)
	# The saved avatars lead; the builder's action follows them.
	content.move_child(actions, -1)
	AvatarLibrary.events().changed.connect(_refresh_state)
	visibility_changed.connect(_on_visibility_changed)
	refresh()


func _exit_tree() -> void:
	if AvatarLibrary.events().changed.is_connected(_refresh_state):
		AvatarLibrary.events().changed.disconnect(_refresh_state)


## Reads the library again.
func refresh() -> void:
	grid.refresh()
	_refresh_state()


func _refresh_state() -> void:
	var empty := AvatarLibrary.list().is_empty()
	_empty.visible = empty
	_heading.visible = not empty


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh()
