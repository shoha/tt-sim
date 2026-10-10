extends GutTest

## The Play together card (PlayTogetherCard): at rest the seam is centred and nothing is
## picked; hovering a face swings the seam away from it; the pill is one focus stop where Left
## and Right pick a face (and on an end face let focus move on); Accept presses (pad A too);
## Join opens in place with the field editing, and Esc, pad B or the disc goes back; a join
## under way locks the field and going back drops it; an error shows in place; pad input is
## ignored while the window is unfocused; an instant state set kills the easings under way.


func before_all() -> void:
	UIManager.add_pad_accept_and_back()


func _card() -> PlayTogetherCard:
	var card := PlayTogetherCard.new()
	card.window_focused = func() -> bool: return true
	add_child_autofree(card)
	return card


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


## Run every easing under way to its end.
func _settle() -> void:
	for tween in get_tree().get_processed_tweens():
		tween.custom_step(5.0)


func test_at_rest_the_seam_is_centred_and_both_faces_show() -> void:
	var card := _card()
	assert_eq(card.eyebrow.text, PlayTogetherCard.EYEBROW)
	assert_eq(card.eyebrow.theme_type_variation, &"Eyebrow")
	assert_eq(card.hot, PlayTogetherCard.Face.NONE)
	assert_almost_eq(card.wash().split, 0.5, 0.0001)
	assert_eq(card.wash().warm, ThemeColors.PERSIMMON)
	assert_eq(card.wash().cool, ThemeColors.LAKE)
	assert_true(card.host_face.visible and card.join_face.visible)
	assert_false(card.code_edit.is_visible_in_tree(), "no field until Join")
	assert_eq(card.pill.custom_minimum_size, PlayTogetherCard.CARD_SIZE)
	assert_eq(card.host_face.tooltip_text, PlayTogetherCard.HOST_TIP)
	assert_eq(card.join_face.tooltip_text, PlayTogetherCard.JOIN_TIP)
	assert_eq(card.pill.focus_mode, Control.FOCUS_ALL, "one focus stop")
	assert_eq(card.host_face.focus_mode, Control.FOCUS_NONE)
	assert_eq(card.join_face.focus_mode, Control.FOCUS_NONE)


## Hovering Host swings the seam 6% toward Join and deepens Host; hovering Join the other way;
## leaving both puts it back.
func test_hover_swings_the_seam_away_from_the_face() -> void:
	var card := _card()
	card.host_face.mouse_entered.emit()
	_settle()
	assert_eq(card.hot, PlayTogetherCard.Face.HOST)
	assert_almost_eq(card.wash().split, 0.5 + PlayTogetherCard.SWING, 0.001)
	assert_eq(card.wash().warm, ThemeColors.PERSIMMON_HOVER)
	card.join_face.mouse_entered.emit()
	_settle()
	assert_eq(card.hot, PlayTogetherCard.Face.JOIN)
	assert_almost_eq(card.wash().split, 0.5 - PlayTogetherCard.SWING, 0.001)
	assert_eq(card.wash().cool, ThemeColors.LAKE_HOVER)
	assert_eq(card.wash().warm, ThemeColors.PERSIMMON)
	card.join_face.mouse_exited.emit()
	_settle()
	assert_eq(card.hot, PlayTogetherCard.Face.NONE)
	assert_almost_eq(card.wash().split, 0.5, 0.001)


## The seam eases over MOTION_WASH, not at once.
func test_the_seam_eases() -> void:
	var card := _card()
	card.set_hot(PlayTogetherCard.Face.JOIN)
	await wait_seconds(PlayTogetherCard.MOTION_WASH * 0.4)
	var part: float = card.wash().split
	assert_between(part, 0.5 - PlayTogetherCard.SWING + 0.001, 0.499, "part way: %f" % part)


## Focus picks Host; Right picks Join; Right again on Join is not consumed (focus moves on);
## Left comes back; the ring wraps the card.
func test_left_and_right_pick_a_face_on_one_focus_stop() -> void:
	var card := _card()
	card.pill.grab_focus()
	assert_eq(card.hot, PlayTogetherCard.Face.HOST)
	assert_true(card.ring_shown(), "the ring wraps the card")
	card.pill.gui_input.emit(_key(KEY_RIGHT))
	assert_eq(card.hot, PlayTogetherCard.Face.JOIN)
	card.pill.gui_input.emit(_key(KEY_RIGHT))
	assert_eq(card.hot, PlayTogetherCard.Face.JOIN, "on the end face Right lets focus move on")
	card.pill.gui_input.emit(_key(KEY_LEFT))
	assert_eq(card.hot, PlayTogetherCard.Face.HOST)


## Accept presses the picked face: Join opens in place with the field focused and editing.
func test_accept_on_join_opens_join_in_place() -> void:
	var card := _card()
	card.pill.grab_focus()
	card.pill.gui_input.emit(_key(KEY_RIGHT))
	card.pill.gui_input.emit(_key(KEY_ENTER))
	assert_true(card.joining)
	assert_true(card.code_edit.is_visible_in_tree())
	assert_true(card.disc_button.is_visible_in_tree(), "Host is a disc at the left")
	assert_false(card.host_face.visible, "the faces give way to the field")
	assert_true(card.code_edit.has_focus())
	assert_true(card.code_edit.is_editing(), "edit() after grab_focus(): typing goes in")
	assert_false(card.ring_shown(), "one ring in Join mode: the field's own")
	_settle()
	assert_almost_eq(card.wash().disc, 1.0, 0.001, "the warm wash is a disc")


## Esc in the field goes back to the card, Join still picked and the pill focused; so do the
## disc and pad B.
func test_esc_the_disc_and_pad_b_go_back() -> void:
	var card := _card()
	card.open_join()
	card.code_edit.gui_input.emit(_key(KEY_ESCAPE))
	assert_false(card.joining, "Esc went back")
	assert_eq(card.hot, PlayTogetherCard.Face.JOIN)
	assert_true(card.pill.has_focus())
	card.open_join()
	card.disc_button.pressed.emit()
	assert_false(card.joining, "the disc went back")
	card.open_join()
	card.join_button.gui_input.emit(_pad(JOY_BUTTON_B))
	assert_false(card.joining, "pad B went back")


## Pad A accepts as Enter does; pad input is ignored while the window is not focused.
func test_pad_a_presses_and_an_unfocused_window_ignores_the_pad() -> void:
	var card := _card()
	card.pill.grab_focus()
	card.set_hot(PlayTogetherCard.Face.JOIN)
	card.window_focused = func() -> bool: return false
	card.pill.gui_input.emit(_pad(JOY_BUTTON_A))
	assert_false(card.joining, "a pad in another game's hands does nothing here")
	card.window_focused = func() -> bool: return true
	card.pill.gui_input.emit(_pad(JOY_BUTTON_A))
	assert_true(card.joining, "pad A pressed Join")
	assert_true(InputMap.action_has_event(&"ui_cancel", _pad(JOY_BUTTON_B)))


## Join asks with the trimmed code; an empty code says what to type; a join under way locks
## the field, and going back then drops it; a failure shows in place with the code selected.
func test_a_join_submits_locks_and_fails_in_place() -> void:
	var card := _card()
	watch_signals(card)
	card.open_join()
	card.submit()
	assert_signal_not_emitted(card, "join_submitted")
	assert_eq(card.status_label.text, PlayTogetherCard.NO_CODE)
	card.code_edit.text = " 2kq9xw "
	card.code_edit.text_submitted.emit(card.code_edit.text)
	assert_signal_emitted_with_parameters(card, "join_submitted", ["2kq9xw"])
	card.show_connecting()
	assert_true(card.busy)
	assert_false(card.code_edit.editable)
	assert_true(card.join_button.disabled)
	assert_eq(card.status_label.text, PlayTogetherCard.CONNECTING)
	assert_false(card.status_icon.visible, "progress is not an error")
	card.show_error(SessionFlow.NO_ROOM)
	assert_false(card.busy)
	assert_true(card.code_edit.editable)
	assert_eq(card.status_label.text, SessionFlow.NO_ROOM)
	assert_true(card.status_icon.visible)
	assert_eq(card.code_edit.get_selected_text(), " 2kq9xw ", "the code to correct, selected")
	card.code_edit.text_changed.emit("x")
	assert_false(card.status_row.visible, "typing clears the error")
	card.show_connecting()
	card.close_join()
	assert_signal_emitted(card, "join_cancelled")
	assert_false(card.busy)


## Host floods the card, then asks for the room; the wash then settles back.
func test_host_floods_then_asks_for_the_room() -> void:
	var card := _card()
	watch_signals(card)
	card.press(PlayTogetherCard.Face.HOST)
	assert_signal_not_emitted(card, "host_pressed", "not before the flood")
	await wait_seconds(PlayTogetherCard.MOTION_WASH * 1.4 + 0.15)
	assert_signal_emitted(card, "host_pressed")
	_settle()
	assert_almost_eq(card.wash().split, 0.5 + PlayTogetherCard.SWING, 0.001, "back at Host")


## An instant set kills the easings under way: reset() mid-swing lands at rest and stays.
func test_an_instant_set_kills_running_easings() -> void:
	var card := _card()
	card.set_hot(PlayTogetherCard.Face.HOST)
	card.open_join()
	card.reset()
	await wait_seconds(PlayTogetherCard.MOTION_WASH + 0.1)
	assert_almost_eq(card.wash().split, 0.5, 0.0001)
	assert_almost_eq(card.wash().disc, 0.0, 0.0001)
	assert_eq(card.wash().warm, ThemeColors.PERSIMMON)
	assert_false(card.joining)
	assert_eq(card.code_edit.text, "")


## Keyboard focus marks the picked face with a soft ring inside it (more than the seam's
## swing): on Host, then on Join after Right; not with the pointer alone, nor in Join mode.
func test_focus_rings_the_picked_face() -> void:
	var card := _card()
	card.set_hot(PlayTogetherCard.Face.HOST)
	assert_eq(card.wash().focus, 0.0, "a hover alone has no ring")
	card.reset()
	card.pill.grab_focus()
	assert_eq(card.wash().focus, 1.0)
	assert_eq(card.wash().focus_side, -1.0, "on Host")
	card.pill.gui_input.emit(_key(KEY_RIGHT))
	assert_eq(card.wash().focus_side, 1.0, "on Join")
	card.open_join()
	assert_eq(card.wash().focus, 0.0, "one ring in Join mode: the field's")


## The shader never lightens a wash under a face's words: the rects it reads hold each face's
## icon, title and caption as drawn, inside the face's block; and paper words on every step of
## both washes (rest, hover, press) keep 4.5:1, so a wash at or below its step keeps them.
func test_the_words_keep_their_contrast() -> void:
	var card := _card()
	var rects := card.text_rects()
	for face: PlayTogetherCard.Face in [PlayTogetherCard.Face.HOST, PlayTogetherCard.Face.JOIN]:
		var words: Rect2 = rects[face]
		var prefix := "Host" if face == PlayTogetherCard.Face.HOST else "Join"
		for part: String in ["Icon", "Title", "Caption"]:
			var control := card.pill.get_node(prefix + part) as Control
			var drawn := Rect2(control.position, control.size)
			if control is Label:
				var label := control as Label
				var font := label.get_theme_font(&"font")
				var size := label.get_theme_font_size(&"font_size")
				var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				drawn.size.x = minf(width, label.size.x)
				if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
					drawn.position.x += label.size.x - drawn.size.x
			assert_true(words.grow(0.5).encloses(drawn), "%s%s in %s" % [prefix, part, words])
		assert_gt(words.size.x, 40.0, "%s: the words have width" % prefix)
	var host: Rect2 = rects[PlayTogetherCard.Face.HOST]
	var join: Rect2 = rects[PlayTogetherCard.Face.JOIN]
	var seam_reach := PlayTogetherCard.CARD_SIZE.x * PlayTogetherCard.SWING
	assert_lt(host.end.x, PlayTogetherCard.CARD_SIZE.x * 0.5 - seam_reach - 5.0, "Host clear")
	assert_gt(join.position.x, PlayTogetherCard.CARD_SIZE.x * 0.5 + seam_reach + 5.0, "Join clear")
	var steps := [
		ThemeColors.PERSIMMON,
		ThemeColors.PERSIMMON_HOVER,
		ThemeColors.PERSIMMON_PRESS,
		ThemeColors.LAKE,
		ThemeColors.LAKE_HOVER,
		ThemeColors.LAKE_PRESS,
	]
	for step: Color in steps:
		var ratio := _contrast(ThemeColors.PAPER, step)
		assert_gt(ratio, 4.5, "paper on %s: %.2f" % [step.to_html(false), ratio])


## Hovers only deepen (C6), built in OKLCH (C8): each hover step is darker than rest and
## lighter than press, at the same hue within a degree.
func test_hover_steps_deepen_at_the_same_hue() -> void:
	var ramps := [
		[ThemeColors.PERSIMMON, ThemeColors.PERSIMMON_HOVER, ThemeColors.PERSIMMON_PRESS],
		[ThemeColors.LAKE, ThemeColors.LAKE_HOVER, ThemeColors.LAKE_PRESS],
	]
	for ramp: Array in ramps:
		var rest := _lch(ramp[0])
		var hover := _lch(ramp[1])
		var press := _lch(ramp[2])
		assert_lt(hover.x, rest.x, "hover darker than rest")
		assert_gt(hover.x, press.x, "hover lighter than press")
		assert_almost_eq(hover.z, rest.z, deg_to_rad(1.0), "hover at rest's hue")


## Join mode: Join is the one fill (persimmon), the back disc steps back to paper with a
## persimmon arrow, one 8 px step from the code field.
func test_join_mode_has_one_fill_and_a_quiet_disc() -> void:
	var card := _card()
	card.open_join()
	assert_eq(card.join_button.theme_type_variation, &"WashJoin")
	assert_eq(card.disc_button.theme_type_variation, &"WashDisc")
	var join_fill := card.join_button.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_eq(join_fill.bg_color, ThemeColors.PERSIMMON, "Join is the fill")
	var disc := card.disc_button.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_eq(disc.bg_color, ThemeColors.PAPER_RAISED, "the disc steps back to paper")
	assert_eq(card.disc_button.get_theme_color(&"icon_normal_color"), ThemeColors.PERSIMMON)
	var disc_end := card.disc_button.position.x + card.disc_button.size.x
	var field_x := (card.code_edit.get_parent() as Control).position.x
	assert_almost_eq(field_x - disc_end, PlayTogetherCard.FIELD_GAP, 0.01, "8 px apart")
	_settle()
	assert_almost_eq(card.disc_button.modulate.a, 1.0, 0.001, "the disc faded in")


## The version gate's failure is not the code's: the field keeps it as typed, unselected.
func test_a_failure_the_code_did_not_cause_leaves_it_unselected() -> void:
	var card := _card()
	card.open_join()
	card.code_edit.text = "2kq9xw"
	card.show_error("The host is running TTSim 0.2.9, but you have 0.2.10.", false)
	assert_eq(card.code_edit.get_selected_text(), "")
	assert_eq(card.code_edit.caret_column, 6)


## The slot under the pill holds a three-line failure, so a failure never grows the card; the
## alert icon is the body line's height.
func test_the_slot_holds_the_longest_failure() -> void:
	var card := _card()
	var version := VersionGate.mismatch_message("0.2.9", "0.2.10")
	var reserved := card.slot.custom_minimum_size.y
	var before := card.get_combined_minimum_size().y
	card.show_error(version)
	await wait_process_frames(2)
	assert_lte(card.status_row.get_combined_minimum_size().y, reserved + 0.5, "the message fits")
	assert_eq(card.get_combined_minimum_size().y, before, "the card did not grow")
	var font := card.status_label.get_theme_font(&"font")
	var line := font.get_height(card.status_label.get_theme_font_size(&"font_size"))
	assert_almost_eq(card.status_icon.custom_minimum_size.y, line, 1.0, "the icon is a line tall")


func _lch(color: Color) -> Vector3:
	return BackdropPaint.to_oklch(Vector3(color.r, color.g, color.b))


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


## Long words never reflow the faces: each caption ends in an ellipsis inside its block.
func test_captions_keep_to_their_blocks() -> void:
	var card := _card()
	var host := card.pill.get_node("HostCaption") as Label
	var join := card.pill.get_node("JoinCaption") as Label
	assert_eq(host.size.x, PlayTogetherCard.TEXT_BLOCK)
	assert_eq(host.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_lt(host.position.x + host.size.x, PlayTogetherCard.CARD_SIZE.x * 0.44 - 5.0)
	assert_gt(join.position.x, PlayTogetherCard.CARD_SIZE.x * 0.56 + 5.0)
