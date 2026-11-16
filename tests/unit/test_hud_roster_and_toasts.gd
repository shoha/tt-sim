extends GutTest

## The gameplay HUD of card ui-hud: the token roster (what it lists, who sees what, select and
## focus), the toast stack (a repeat joins its toast, the pointer pauses the clock, Reduce
## motion drops the slide), the idle fade of the hint bar, and the HUD's hit targets at 720p.

const TOAST_SCENE := preload("res://scenes/ui/toast_container.tscn")
const HINTS_SCENE := preload("res://scenes/ui/input_hints.tscn")

var _saved_reduce := false


func before_each() -> void:
	_saved_reduce = UiMotion.user_reduce


func after_each() -> void:
	UiMotion.user_reduce = _saved_reduce


func _token(
	token_name: String, id: String, hp: int = 40, max_hp: int = 40, shown := true
) -> BoardToken:
	var token := BoardToken.new()
	token.token_name = token_name
	token.network_id = id
	token.max_health = max_hp
	token.current_health = hp
	token.is_visible_to_players = shown
	# Not in the tree: a BoardToken asks for its factory once it enters one.
	autofree(token)
	return token


# -- The roster's model ------------------------------------------------------------------------


## A player never sees a token the GM hid (G14: the list must not leak what the board hides).
func test_a_player_does_not_see_hidden_tokens_and_the_gm_does() -> void:
	var tokens: Array = [_token("Wren", "a"), _token("Ghost", "b", 10, 10, false)]
	var player := TokenRosterModel.rows(tokens, false, Callable())
	assert_eq(player.size(), 1)
	assert_eq(player[0]["name"], "Wren")
	var gm := TokenRosterModel.rows(tokens, true, Callable())
	assert_eq(gm.size(), 2)
	assert_true(gm[0]["hidden"] or gm[1]["hidden"], "the GM's row is marked hidden")


## Tokens a player controls come first, then the rest by name with numbers in natural order.
func test_yours_first_then_natural_name_order() -> void:
	var tokens: Array = [
		_token("Goblin 10", "g10"),
		_token("Goblin 2", "g2"),
		_token("Zed", "z"),
		_token("Amber", "a"),
	]
	var mine := func(token: BoardToken) -> bool: return token.network_id == "z"
	var rows := TokenRosterModel.rows(tokens, false, mine)
	var names: Array = rows.map(func(r: Dictionary) -> String: return r["name"])
	assert_eq(names, ["Zed", "Amber", "Goblin 2", "Goblin 10"])
	assert_true(rows[0]["yours"])
	assert_false(rows[1]["yours"])


func test_health_reads_down_hurt_or_healthy() -> void:
	assert_eq(TokenRosterModel.health_of(0, 30), TokenRosterModel.Health.DOWN)
	assert_eq(TokenRosterModel.health_of(12, 30), TokenRosterModel.Health.HURT)
	assert_eq(TokenRosterModel.health_of(13, 30), TokenRosterModel.Health.HEALTHY)
	assert_eq(TokenRosterModel.health_of(30, 30), TokenRosterModel.Health.HEALTHY)
	assert_eq(TokenRosterModel.health_of(5, 0), TokenRosterModel.Health.HEALTHY, "no maximum")


## Health is in words as well as the bar's colour (C7), and a hidden token says so.
func test_status_text_carries_health_in_words() -> void:
	var rows := TokenRosterModel.rows(
		[_token("A", "a", 12, 40), _token("B", "b", 0, 40, false)], true, Callable()
	)
	assert_eq(TokenRosterModel.status_text(rows[0]), "HP 12/40")
	assert_eq(TokenRosterModel.status_text(rows[1]), "Down, hidden")
	assert_eq(TokenRosterModel.count_text(0), "No tokens on the table")
	assert_eq(TokenRosterModel.count_text(1), "1 token")
	assert_eq(TokenRosterModel.count_text(8), "8 tokens")


# -- The roster's drawer ------------------------------------------------------------------------


func _roster(tokens: Array) -> TokenRoster:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.theme = ThemeColors.glass_theme()
	add_child_autofree(host)
	var roster := TokenRoster.new()
	roster.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(roster)
	roster.setup(func() -> Array: return tokens, Callable(), func() -> bool: return true)
	return roster


## One row per token, a press selects it, the card shows it, and the host hears about it.
func test_pressing_a_row_selects_the_token_and_reports_it() -> void:
	var a := _token("Wren", "a")
	var b := _token("Brindle", "b", 5, 40)
	var roster := _roster([a, b])
	await wait_frames(1)
	assert_eq(roster.row_count(), 2)
	watch_signals(roster)
	var picked := roster.pick_row(0)
	assert_eq(picked, "Brindle", "rows are in name order")
	assert_eq(roster.selected_id, "b")
	assert_signal_emitted_with_parameters(roster, "token_chosen", [b])
	assert_true(roster.find_child("SelectedCard", true, false).visible, "the card shows")
	assert_eq(roster.pick_row(9), "", "out of range picks nothing")


## The card goes when its token leaves the table.
func test_the_card_clears_when_the_token_is_gone() -> void:
	var a := _token("Wren", "a")
	var tokens: Array = [a]
	var roster := _roster(tokens)
	await wait_frames(1)
	roster.pick_row(0)
	tokens.clear()
	roster.refresh()
	assert_eq(roster.row_count(), 0)
	assert_eq(roster.selected_id, "")
	assert_false(roster.find_child("SelectedCard", true, false).visible)


## Every row is at least a 40 px target (UI_TASTE S6 asks about 44) and its press carries a name.
func test_rows_are_large_targets_with_names() -> void:
	var roster := _roster([_token("Wren", "a")])
	await wait_frames(1)
	var row := roster.row_node("a")
	assert_gte(row.custom_minimum_size.y, 44.0)
	var press := row.get_node("Press") as Button
	assert_ne(press.accessibility_name, "", "an accessible name")
	assert_eq(press.tooltip_text, "Wren", "the tooltip carries a long name whole")


## The drawer is a list narrower than the 396 drawer token, so it stays left of the board
## centre of a 1280x720 canvas at Auto (914 px wide): its panel and rail end before 457.
func test_the_roster_stays_left_of_the_board_centre_at_720p() -> void:
	assert_lt(TokenRoster.WIDTH + 44.0, 914.0 / 2.0)


# -- Toasts --------------------------------------------------------------------------------------


## The same words again join the toast already up and count, not stack a second chip.
func test_a_repeated_toast_counts_instead_of_stacking() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	toasts.show_toast("Marigold moved", ToastContainer.ToastType.INFO, 30.0)
	toasts.show_toast("Marigold moved", ToastContainer.ToastType.INFO, 30.0)
	toasts.show_toast("Marigold moved", ToastContainer.ToastType.INFO, 30.0)
	assert_eq(toasts._active_toasts.size(), 1)
	var badge := toasts._active_toasts[0].find_child("Count", true, false) as Label
	assert_eq(badge.text, "x3")
	toasts.show_toast("Marigold moved", ToastContainer.ToastType.WARNING, 30.0)
	assert_eq(toasts._active_toasts.size(), 2, "another kind is its own toast")


## At most MAX_VISIBLE_TOASTS stack; a long sequence drops the oldest.
func test_a_long_sequence_keeps_the_stack_short() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	for i in 11:
		toasts.show_toast("Toast number %d" % i, ToastContainer.ToastType.INFO, 30.0)
	assert_eq(toasts._active_toasts.size(), ToastContainer.MAX_VISIBLE_TOASTS)


## A toast arrives sliding SLIDE_PX on its offset transform (M3) and dismisses by timer.
func test_a_toast_slides_in_on_the_offset_transform() -> void:
	UiMotion.user_reduce = false
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	toasts.show_toast("Map saved", ToastContainer.ToastType.SUCCESS, 30.0)
	var toast: Control = toasts._active_toasts[0]
	assert_true(toast.offset_transform_enabled)
	assert_almost_eq(toast.offset_transform_position.y, ToastContainer.SLIDE_PX, 0.01)
	assert_not_null(toast.get_node_or_null("DismissTimer"), "the toast owns its clock")


## Reduce motion keeps the fade and drops the slide (M5).
func test_reduce_motion_drops_the_toast_slide() -> void:
	UiMotion.user_reduce = true
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	toasts.show_toast("Map saved", ToastContainer.ToastType.SUCCESS, 30.0)
	var toast: Control = toasts._active_toasts[0]
	assert_eq(toast.offset_transform_position, Vector2.ZERO)
	assert_eq(toast.modulate.a, 0.0, "still fades in")


## The pointer on a toast holds its clock; leaving it gives at least HOVER_GRACE_S more.
func test_the_pointer_pauses_a_toast() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	toasts.show_toast("Map saved", ToastContainer.ToastType.SUCCESS, 4.0)
	var toast: Control = toasts._active_toasts[0]
	var timer := toast.get_node("DismissTimer") as Timer
	toast.mouse_entered.emit()
	assert_true(timer.paused)
	toast.mouse_exited.emit()
	assert_false(timer.paused)
	assert_gte(timer.time_left, 1.0 - 0.01)


func test_the_kind_icon_is_big_enough_to_read() -> void:
	assert_gte(ToastContainer.ICON_SIZE, 24)


# -- The hint bar --------------------------------------------------------------------------------


## The bar fades when the hints have stood unchanged and comes back on a change.
func test_the_hint_bar_fades_when_idle_and_returns_on_a_change() -> void:
	var hints: InputHints = HINTS_SCENE.instantiate()
	add_child_autofree(hints)
	hints.set_hints([{"key": "Esc", "action": "Pause"}])
	await wait_frames(2)
	hints._fade_idle()
	assert_true(hints._idle_faded)
	hints.set_hints([{"key": "Esc", "action": "Pause"}, {"key": "F1", "action": "Help"}])
	assert_false(hints._idle_faded, "a changed hint wakes the bar")


## A tool's own hints are how the tool is used: they never fade.
func test_a_tool_s_hints_never_fade() -> void:
	var hints: InputHints = HINTS_SCENE.instantiate()
	add_child_autofree(hints)
	hints.set_hints([{"key": "Esc", "action": "Pause"}])
	hints.set_tool_hints([{"key": "Click", "action": "Add point"}])
	await wait_frames(2)
	hints._fade_idle()
	assert_false(hints._idle_faded)
