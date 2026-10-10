class_name RoomDrawer
extends DrawerContainer

## The room over the table: the RoomPanel in its drawer form, on glass at the left edge, the
## same players, shelf and code as the full-screen room, learned once. The GM selects a shelf
## map and moves the table there; everyone sees who is here. Tab opens and closes it, only at
## a table (tab_toggles()); its tab handle shows only in a hosted or joined session. A player
## arriving or leaving sounds as in the room (the panel's own).

signal move_table_requested(key: String)
signal leave_requested

## Drawer width token (UI_TASTE S5), the room's side column too.
const WIDTH := RoomPanel.SIDE_WIDTH

## Cleared by tests before adding, so the panel never reads NetworkManager.
@export var connect_network := true

var panel: RoomPanel


func _on_ready() -> void:
	drawer_width = WIDTH
	tab_icon = preload("res://assets/icons/ui/users.svg")
	set_tab_tooltip("The room (Tab)")
	panel = RoomPanel.new()
	panel.name = "RoomPanel"
	panel.in_drawer = true
	panel.connect_network = connect_network
	content_container.add_child(panel)
	panel.move_table_requested.connect(_on_move_table_requested)
	panel.leave_requested.connect(_on_leave_requested)
	if connect_network:
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)


func _exit_tree() -> void:
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)


## Show the tab in a session, hide it (and the drawer) offline.
func update_visibility() -> void:
	if NetworkManager.is_networked():
		visible = true
		reveal()
	else:
		conceal()


func _input(event: InputEvent) -> void:
	if not tab_toggles(event, _at_table(), is_revealed, _board_busy()):
		return
	toggle()
	get_viewport().set_input_as_handled()


## Whether `event` opens or closes the drawer: a bare Tab press, at a table (`at_table`: Root
## is PLAYING with nothing paused over it), with the drawer's tab shown, and nothing else
## taking Tab (`busy`: an overlay or panel over the board, a focused text field, the measure
## tool, which cycles its mode with Tab). Pure.
static func tab_toggles(event: InputEvent, at_table: bool, revealed: bool, busy: bool) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_TAB:
		return false
	if key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return false
	return at_table and revealed and not busy


func _at_table() -> bool:
	return UIManager.get_current_state() == UIManager.ROOT_STATE_PLAYING


func _board_busy() -> bool:
	if UIManager.has_open_overlay() or AnimatedCanvasLayerPanel.any_open():
		return true
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return true
	var map := _game_map()
	return map != null and map.get_measure_tool() != null and map.get_measure_tool().is_active()


func _game_map() -> GameMap:
	var node := get_parent()
	while node != null and not node is GameMap:
		node = node.get_parent()
	return node as GameMap


func _on_move_table_requested(key: String) -> void:
	close()
	move_table_requested.emit(key)


func _on_leave_requested() -> void:
	close()
	leave_requested.emit()


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, _new_state: NetworkManager.ConnectionState
) -> void:
	update_visibility()
