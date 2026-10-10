class_name RoomScreen
extends CanvasLayer

## Root's ROOM state: the RoomPanel full screen on paper, between maps, over the painted
## backdrop (PaintedBackdrop) in the mood of the selected shelf map, morning with none. The
## heading, the room code's caption and the selected map's name and readiness sit straight on
## the backdrop and are kept legible in every mood. Root frees it on leaving ROOM. Copy,
## Invite, Choose avatar and adding to the shelf are the panel's own; Set out and Leave go to
## Root through the panel's signals.

## The wait Root shows over the title while hosting starts, before this screen opens: the
## operation, and its one step (Steam answers with a lobby), the caption in Cancel's band until
## Cancel is offered (LoadingOverlay.show_indeterminate()).
const OPENING := "Opening a room..."
const OPENING_STEP := "Asking Steam for a lobby"

## Cleared by tests and the UI tour before adding, so the panel never reads NetworkManager.
@export var connect_network := true

var backdrop: PaintedBackdrop
var panel: RoomPanel


func _init() -> void:
	name = "RoomScreen"
	layer = 5


func _ready() -> void:
	backdrop = PaintedBackdrop.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	# The room opens in the mood already on screen (the title's), then follows the selection.
	backdrop.show_mood(PaintedBackdrop.last_mood, true)
	panel = RoomPanel.new()
	panel.name = "RoomPanel"
	panel.in_drawer = false
	panel.connect_network = connect_network
	panel.selection_shown.connect(backdrop.show_mood_of)
	panel.selection_shown.connect(backdrop.refresh_zones.unbind(1))
	add_child(panel)
	backdrop.keep_legible(
		[
			[panel.title_label.get_parent()],
			[panel.code_label.get_parent().get_parent()],
			[panel.map_name_label, panel.readiness_label],
		]
	)
	panel.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
