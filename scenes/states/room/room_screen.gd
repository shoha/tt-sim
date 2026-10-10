class_name RoomScreen
extends CanvasLayer

## Root's ROOM state: the RoomPanel full screen on paper, between maps. With no map out the
## backdrop is the default sky (the title's backdrop, until painted backdrops land). Root
## frees it on leaving ROOM. Copy, Invite, Choose avatar and adding to the shelf are the
## panel's own; Set out and Leave go to Root through the panel's signals.

## Cleared by tests and the UI tour before adding, so the panel never reads NetworkManager.
@export var connect_network := true

var backdrop: ColorRect
var panel: RoomPanel


func _init() -> void:
	name = "RoomScreen"
	layer = 5


func _ready() -> void:
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	backdrop.color = ThemeColors.of(backdrop, ThemeColors.BACKDROP)
	panel = RoomPanel.new()
	panel.name = "RoomPanel"
	panel.in_drawer = false
	panel.connect_network = connect_network
	add_child(panel)
	panel.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
