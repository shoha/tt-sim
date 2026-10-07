extends GutTest

## Drag-to-place for saved avatars: an AvatarCard with `draggable` turns a held press moved
## DRAG_THRESHOLD_PX into drag_started (a plain click stays a click), and
## DragPlaceController.begin_drag runs a drag whose drop calls the given placer, as the
## pack tabs' drags do through _on_drag_place_started.


func _press(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	return event


func _move(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	return event


func _card(draggable: bool) -> AvatarCard:
	var card := AvatarCard.new()
	card.draggable = draggable
	add_child_autofree(card)
	watch_signals(card)
	return card


func test_a_held_card_dragged_past_the_threshold_starts_a_drag_once() -> void:
	var card := _card(true)
	card._on_gui_input(_press(Vector2(20, 20), true))
	card._on_gui_input(_move(Vector2(23, 20)))
	assert_signal_not_emitted(card, "drag_started", "within the threshold")
	card._on_gui_input(_move(Vector2(20 + AvatarCard.DRAG_THRESHOLD_PX, 20)))
	assert_signal_emit_count(card, "drag_started", 1)
	card._on_gui_input(_move(Vector2(60, 40)))
	assert_signal_emit_count(card, "drag_started", 1, "one drag per press")


func test_a_click_or_a_hover_is_no_drag() -> void:
	var card := _card(true)
	card._on_gui_input(_press(Vector2(20, 20), true))
	card._on_gui_input(_press(Vector2(21, 20), false))
	card._on_gui_input(_move(Vector2(60, 20)))
	assert_signal_not_emitted(card, "drag_started", "released, then only hovered")


func test_a_card_that_is_not_draggable_never_drags() -> void:
	var card := _card(false)
	card._on_gui_input(_press(Vector2(20, 20), true))
	card._on_gui_input(_move(Vector2(80, 20)))
	assert_signal_not_emitted(card, "drag_started")


func test_begin_drag_shows_the_ghost_and_escape_cancels_without_placing() -> void:
	var controller := DragPlaceController.new()
	add_child_autofree(controller)
	var placed: Array = []
	controller.begin_drag(
		null,
		func(at: Vector3) -> BoardToken:
			placed.append(at)
			return null
	)
	assert_true(controller._drag_placing, "dragging")
	assert_not_null(controller._drag_ghost, "the ghost follows the cursor")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	assert_true(controller.handle_input(escape), "Escape is taken")
	assert_false(controller._drag_placing, "cancelled")
	assert_false(controller._place_fn.is_valid(), "the placer is dropped")
	assert_eq(placed.size(), 0, "nothing placed")
