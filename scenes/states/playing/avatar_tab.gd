class_name AvatarTab
extends MarginContainer

## The "Avatar" tab of the Add Token browser: one tall action that opens the avatar
## builder (AvatarBuilder) for a new player figure, with a line on what the builder does.
## The browser relays build_requested to GameplayMenuController, which opens the builder
## and spawns the confirmed avatar where an asset would land.

signal build_requested

const TAB_TITLE := "Avatar"

@onready var actions: VBoxContainer = %Actions


func _ready() -> void:
	var button := UiActions.primary(
		"Make an avatar",
		"wand",
		"Pick a pose, a face, colours and a shape; the figure follows every pick.",
		actions
	)
	button.pressed.connect(func() -> void: build_requested.emit())
