extends GutTest

## The join screen swaps between entering a code and waiting for the host. The
## footer button is Back while the form is up and Leave once a connection is
## under way, and Connect is the screen's only accent action. Network calls are
## guarded off the same way the host lobby guards hosting.

const SCENE := preload("res://scenes/states/lobby/lobby_client.tscn")


func _lobby() -> LobbyClient:
	var lobby: LobbyClient = SCENE.instantiate()
	lobby.connect_network = false
	add_child_autofree(lobby)
	return lobby


func test_header_reads_as_a_sentence() -> void:
	var lobby := _lobby()
	assert_eq(lobby.header.title_label.text, "Join a game")
	assert_eq(lobby.header.caption_label.text, "Enter the room code from the host")


func test_input_state_offers_back() -> void:
	var lobby := _lobby()
	assert_true(lobby.input_container.visible)
	assert_false(lobby.waiting_container.visible)
	assert_eq(lobby.leave_button.text, "Back")


func test_connecting_state_offers_leave_and_locks_the_form() -> void:
	var lobby := _lobby()
	lobby._show_connecting_state()
	assert_eq(lobby.leave_button.text, "Leave")
	assert_true(lobby.connect_button.disabled)
	assert_false(lobby.room_code_input.editable)


func test_connect_is_the_only_accent_action() -> void:
	var lobby := _lobby()
	assert_eq(lobby.connect_button.theme_type_variation, &"")
	assert_eq(lobby.leave_button.theme_type_variation, &"Secondary")
	assert_eq(lobby.paste_button.theme_type_variation, &"IconButton")
	assert_eq(lobby.paste_button.tooltip_text, "Paste")


func test_footer_hugs_the_right() -> void:
	var lobby := _lobby()
	var footer := lobby.leave_button.get_parent() as HBoxContainer
	assert_eq(footer.alignment, BoxContainer.ALIGNMENT_END)


func test_leave_press_asks_to_leave() -> void:
	var lobby := _lobby()
	watch_signals(lobby)
	lobby._on_leave_pressed()
	assert_signal_emitted(lobby, "leave_requested")


func test_connected_state_rebuilds_the_focus_trap_around_visible_controls() -> void:
	var lobby := _lobby()
	lobby._show_connected_state()
	for control in lobby._focusable_controls:
		assert_true(control.is_visible_in_tree(), control.name)
	assert_true(lobby._focusable_controls.has(lobby.leave_button))


func test_returning_to_input_state_rebuilds_the_focus_trap() -> void:
	var lobby := _lobby()
	lobby._show_connected_state()
	lobby._show_input_state()
	assert_true(lobby._focusable_controls.has(lobby.connect_button))
	assert_false(lobby._focusable_controls.has(lobby.player_list))
