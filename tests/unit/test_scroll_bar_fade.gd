extends GutTest

## ScrollBarFade: a content list's scroll bar is the handle alone, clear at rest, fading in
## while the pointer is over the list and for a moment after a scroll, then out (user verdict
## 2026-10-10). The drawers' panes, the Settings tabs and the room share it.


func _scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(200, 100)
	var content := Control.new()
	content.custom_minimum_size = Vector2(180, 600)
	scroll.add_child(content)
	add_child_autofree(scroll)
	return scroll


func _settle() -> void:
	await wait_seconds(maxf(Constants.ANIM_HOVER_SOFT_IN, Constants.ANIM_HOVER_SOFT_OUT) + 0.1)


func test_the_bar_rests_clear() -> void:
	var scroll := _scroll()
	var fade := ScrollBarFade.attach(scroll)
	assert_eq(fade.get_parent(), scroll)
	assert_eq(scroll.get_v_scroll_bar().modulate.a, 0.0)
	assert_false(fade.is_shown())


func test_the_pointer_over_the_list_fades_it_in_and_leaving_fades_it_out() -> void:
	var scroll := _scroll()
	var fade := ScrollBarFade.attach(scroll)
	scroll.mouse_entered.emit()
	await _settle()
	assert_almost_eq(scroll.get_v_scroll_bar().modulate.a, 1.0, 0.01)
	assert_true(fade.is_shown())
	fade._linger.timeout.emit()
	await _settle()
	assert_almost_eq(scroll.get_v_scroll_bar().modulate.a, 1.0, 0.01, "stays while over it")
	scroll.mouse_exited.emit()
	assert_false(fade._linger.is_stopped(), "lingers after the pointer leaves")
	fade._linger.timeout.emit()
	await _settle()
	assert_almost_eq(scroll.get_v_scroll_bar().modulate.a, 0.0, 0.01)


func test_a_scroll_with_the_pointer_elsewhere_shows_it_for_a_moment() -> void:
	var scroll := _scroll()
	var fade := ScrollBarFade.attach(scroll)
	await wait_process_frames(2)
	scroll.get_v_scroll_bar().value = 50.0
	assert_true(fade.is_shown())
	assert_false(fade._linger.is_stopped())
	assert_almost_eq(fade._linger.wait_time, ScrollBarFade.LINGER_S, 0.001)
	fade._linger.timeout.emit()
	await _settle()
	assert_false(fade.is_shown())


func test_the_pane_stack_uses_it() -> void:
	var stack := PaneStack.new()
	add_child_autofree(stack)
	var pane := VBoxContainer.new()
	stack.add_pane(&"a", pane)
	var wrapper := pane.get_parent()
	assert_not_null(wrapper.find_child("ScrollBarFade", false, false), "a drawer pane")
