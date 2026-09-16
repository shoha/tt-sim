extends GutTest

## PaneStack shows one pane at a time, wraps each in a scroll container,
## crossfades on animated swaps, and ignores no-op requests.


func _stack() -> PaneStack:
	var stack := PaneStack.new()
	stack.size = Vector2(320, 600)
	add_child_autofree(stack)
	stack.add_pane(&"a", VBoxContainer.new())
	stack.add_pane(&"b", VBoxContainer.new())
	return stack


func test_panes_start_hidden_until_shown() -> void:
	var stack := _stack()
	assert_false(stack._wrappers[&"a"].visible)
	assert_false(stack._wrappers[&"b"].visible)
	stack.show_pane(&"a", false)
	assert_true(stack._wrappers[&"a"].visible)
	assert_eq(stack.current, &"a")


func test_pane_is_wrapped_in_scroll_container() -> void:
	var stack := _stack()
	assert_true(stack._wrappers[&"a"] is ScrollContainer)
	assert_eq(stack.get_pane(&"a").get_parent(), stack._wrappers[&"a"])


func test_animated_swap_starts_tween_and_updates_current() -> void:
	var stack := _stack()
	stack.show_pane(&"a", false)
	watch_signals(stack)
	stack.show_pane(&"b")
	assert_eq(stack.current, &"b")
	assert_true(stack._wrappers[&"b"].visible)
	assert_true(stack._tween != null and stack._tween.is_valid())
	assert_signal_emitted_with_parameters(stack, "pane_changed", [&"b"])


func test_showing_current_pane_is_a_no_op() -> void:
	var stack := _stack()
	stack.show_pane(&"a", false)
	watch_signals(stack)
	stack.show_pane(&"a")
	assert_signal_not_emitted(stack, "pane_changed")


func test_unknown_pane_is_ignored() -> void:
	var stack := _stack()
	stack.show_pane(&"a", false)
	stack.show_pane(&"zzz")
	assert_eq(stack.current, &"a")


func test_rapid_double_swap_hides_the_first_outgoing_pane() -> void:
	var stack := _stack()
	stack.add_pane(&"c", VBoxContainer.new())
	stack.show_pane(&"a", false)
	stack.show_pane(&"b")
	stack.show_pane(&"c")
	assert_eq(stack.current, &"c")
	assert_false(
		stack._wrappers[&"a"].visible, "first outgoing pane is hidden when a new swap starts"
	)
	assert_eq(stack._wrappers[&"a"].modulate.a, 1.0)
	assert_eq(stack._wrappers[&"a"].offset_transform_position, Vector2.ZERO)
	assert_true(stack._wrappers[&"b"].visible, "the previous pane keeps fading out")
	assert_eq(stack._wrappers[&"b"].offset_transform_position, Vector2.ZERO)
	assert_true(stack._wrappers[&"c"].visible)
