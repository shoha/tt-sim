extends AnimatedCanvasLayerPanel
class_name PlayerSelectionDialog

## Modal dialog that lists connected players as buttons.
## Emits player_selected(peer_id) when a player is chosen.

signal player_selected(peer_id: int)

@onready var title_label: Label = %TitleLabel
@onready var player_list: VBoxContainer = %PlayerList
@onready var cancel_button: Button = %CancelButton

var _closing: bool = false


func _on_panel_ready() -> void:
	cancel_button.set_meta("ui_silent", true)
	cancel_button.pressed.connect(_on_cancel_pressed)


func setup(title: String, players: Dictionary, exclude_peer_ids: Array[int] = []) -> void:
	title_label.text = title

	# Clear any placeholder children
	for child in player_list.get_children():
		child.queue_free()

	# Add a button per player
	for peer_id in players:
		if peer_id in exclude_peer_ids:
			continue
		var info: Dictionary = players[peer_id]
		var player_name: String = info.get("name", "Player")
		var btn := Button.new()
		btn.text = player_name
		btn.theme_type_variation = &"Secondary"
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var captured_peer_id: int = peer_id
		btn.pressed.connect(func(): _on_player_selected(captured_peer_id))
		player_list.add_child(btn)

	# If no players to show, add a label
	if player_list.get_child_count() == 0:
		var lbl := Label.new()
		lbl.text = "No players connected"
		lbl.theme_type_variation = &"Body"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_list.add_child(lbl)


func _on_player_selected(peer_id: int) -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play_confirm()
	player_selected.emit(peer_id)
	animate_out()


func _on_cancel_pressed() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play_cancel()
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
