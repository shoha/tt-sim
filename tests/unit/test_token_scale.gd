extends GutTest

## Per-token work that grew with the number of tokens on the table (card tokenscale):
## - a pack token leaves its model's shared idle clip alone once the clip loops, since writing
##   loop_mode emits `changed` and every mixer playing the clip then rebuilds its caches;
## - a token's controller sits in the viewport's unhandled input dispatch only while the pointer is
##   over it or a rotate or scale gesture runs, so an event no longer visits every token.

const IDLE := BoardTokenAnimationTree.IDLE


func _token() -> BoardToken:
	var model := Node3D.new()
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	model.add_child(part)
	var token := BoardTokenFactory.create_from_scene(model)
	add_child_autofree(token)
	return token


func _controller(token: BoardToken) -> BoardTokenController:
	return token.get_controller_component() as BoardTokenController


func _button(index: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_MIDDLE if index == MOUSE_BUTTON_MIDDLE and pressed else 0
	return event


func test_an_idle_token_is_out_of_the_input_dispatch() -> void:
	var controller := _controller(_token())
	assert_not_null(controller)
	assert_false(controller.wants_input())
	assert_false(controller.is_processing_unhandled_input())


func test_hover_puts_the_controller_in_and_leaving_takes_it_out() -> void:
	var controller := _controller(_token())
	controller._on_mouse_entered()
	assert_true(controller.is_processing_unhandled_input())
	controller._on_mouse_exited()
	assert_false(controller.is_processing_unhandled_input())


func test_a_gesture_keeps_the_controller_in_until_its_release() -> void:
	var controller := _controller(_token())
	controller._on_mouse_entered()
	controller._unhandled_input(_button(MOUSE_BUTTON_MIDDLE, true))
	assert_true(controller._rotating, "the middle button starts a rotation over the token")
	controller._on_mouse_exited()
	assert_true(
		controller.is_processing_unhandled_input(), "the pointer left mid-gesture: still in"
	)
	controller._unhandled_input(_button(MOUSE_BUTTON_MIDDLE, false))
	assert_false(controller._rotating)
	assert_false(controller.is_processing_unhandled_input())


func test_a_right_click_reaches_the_hovered_token_only() -> void:
	var idle := _controller(_token())
	var hovered := _controller(_token())
	hovered._on_mouse_entered()
	watch_signals(idle)
	watch_signals(hovered)
	get_tree().root.push_input(_button(MOUSE_BUTTON_RIGHT, true))
	assert_signal_emitted(hovered, "context_menu_requested")
	assert_signal_not_emitted(idle, "context_menu_requested")
	hovered._on_mouse_exited()


func _idle_player(token: BoardToken) -> AnimationPlayer:
	for node in token.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player.has_animation(IDLE):
			return player
	return null


func test_a_second_token_of_a_model_leaves_the_shared_idle_clip_alone() -> void:
	var path: String = AssetManager.resolve_model_path("beasts", "cow", "default")
	assert_ne(path, "", "the shipped Beasts pack has a cow")
	if path == "":
		return
	var first := BoardTokenFactory._create_from_model_path(path, "beasts", "cow")
	add_child_autofree(first)
	var player := _idle_player(first)
	assert_not_null(player, "the cow has the idle clip")
	if player == null:
		return
	var clip := player.get_animation(IDLE)
	assert_eq(clip.loop_mode, Animation.LOOP_LINEAR, "the first token makes the idle loop")
	var changes := [0]
	var count := func() -> void: changes[0] += 1
	clip.changed.connect(count)
	var second := BoardTokenFactory._create_from_model_path(path, "beasts", "cow")
	add_child_autofree(second)
	clip.changed.disconnect(count)
	var second_player := _idle_player(second)
	assert_same(second_player.get_animation(IDLE), clip, "the tokens share the model's clip")
	assert_eq(changes[0], 0, "the second token left the shared clip alone")
	assert_eq(second_player.get_animation(IDLE).loop_mode, Animation.LOOP_LINEAR)
