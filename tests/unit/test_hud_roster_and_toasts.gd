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


## Identical names are numbered from the second ("Bramble", "Bramble 2"), in a stable order, and a
## number a token already wears is skipped.
func test_identical_names_are_numbered() -> void:
	var rows := TokenRosterModel.rows(
		[
			_token("Bramble", "c"),
			_token("Bramble", "a"),
			_token("bramble", "b"),
			_token("Goblin", "g1"),
			_token("Goblin 2", "g2"),
			_token("Goblin", "g3"),
		],
		false,
		Callable()
	)
	var shown: Array = rows.map(func(r: Dictionary) -> String: return r["display_name"])
	assert_eq(shown, ["Bramble", "bramble 2", "Bramble 3", "Goblin", "Goblin 3", "Goblin 2"])
	var ids: Array = rows.map(func(r: Dictionary) -> String: return r["id"])
	assert_eq(ids, ["a", "b", "c", "g1", "g3", "g2"], "equal names keep the id order")


## A row carries the token's portrait (40 px) and a 4 px health bar whose track shows.
func test_a_row_has_a_portrait_and_a_health_bar_with_a_track() -> void:
	var roster := _roster([_token("Wren", "a", 10, 40)])
	await wait_frames(2)
	var content := roster.row_node("a").get_node("Content")
	var portrait := content.get_node("Portrait") as TextureRect
	assert_eq(portrait.custom_minimum_size, Vector2(40, 40))
	assert_not_null(portrait.texture, "a placeholder shows until the picture is made")
	var bar := content.get_node("Words/Bar") as ProgressBar
	assert_eq(bar.custom_minimum_size.y, 4.0)
	assert_eq(bar.max_value, 40.0)
	assert_eq(bar.value, 10.0)
	var track := bar.get_theme_stylebox("background") as StyleBoxFlat
	assert_not_null(track)
	assert_gte(track.bg_color.a, 0.4, "the track is drawn, not a transparent stub")


## The card repeats nothing the row says, and the header has no second Add token.
func test_the_card_holds_actions_only_and_the_header_has_no_add_button() -> void:
	var roster := _roster([_token("Wren", "a")])
	await wait_frames(1)
	roster.pick_row(0)
	var card := roster.find_child("SelectedCard", true, false) as Control
	assert_not_null(card.find_child("FindButton", true, false))
	assert_not_null(card.find_child("ActionsButton", true, false))
	assert_eq(card.find_children("*", "Label", true, false).size(), 0, "no name or health words")
	assert_null(roster.find_child("AddTokenButton", true, false))


## Picking a row marks the token on the board whatever the pin setting says (the marker holds it).
func test_picking_a_row_marks_the_token_and_closing_clears_it() -> void:
	var a := _token("Wren", "a")
	var roster := _roster([a])
	await wait_frames(1)
	roster.pick_row(0)
	assert_true(roster.focus_marker.is_marking(a))
	roster.focus_marker.set_selected(null)
	assert_false(roster.focus_marker.is_marking(a))


## The marker's pure rules: the ring is wider than the token, and the pin head stays on screen.
func test_marker_rules() -> void:
	assert_gt(TokenFocusMarker.ring_radius(0.5), 0.5)
	assert_gt(TokenFocusMarker.ring_radius(0.0), 0.3, "a tiny footprint still gets a ring")
	var canvas := Vector2(1280, 720)
	var inside := TokenFocusMarker.head_position(Vector2(600, 400), canvas)
	assert_lt(inside.y, 400.0, "the head stands above the token")
	var off := TokenFocusMarker.head_position(Vector2(-300, -50), canvas)
	assert_gte(off.x, TokenFocusMarker.EDGE_MARGIN)
	assert_gte(off.y, TokenFocusMarker.EDGE_MARGIN)
	var far := TokenFocusMarker.head_position(Vector2(5000, 5000), canvas)
	assert_lte(far.x, canvas.x - TokenFocusMarker.EDGE_MARGIN)
	assert_lte(far.y, canvas.y - TokenFocusMarker.EDGE_MARGIN)


## The hint bar teaches the roster key in both views.
func test_the_play_hints_name_the_tokens_key() -> void:
	for street in [false, true]:
		var found := false
		for hint in CameraRig.play_hints(street):
			found = found or (hint["key"] == "T" and hint["action"] == "Tokens")
		assert_true(found, "T Tokens is in the row (street %s)" % street)


## The ring's chalk over its ink keeps 3:1 against any board: the ink band is the darker one on
## a bright meadow and the chalk the lighter one on a dark forest.
func test_the_marker_ring_has_contrast_against_both_bright_and_dark_ground() -> void:
	var host := Control.new()
	host.theme = ThemeColors.glass_theme()
	add_child_autofree(host)
	var ink := ThemeColors.of(host, ThemeColors.SURFACE)
	var chalk := ThemeColors.of(host, ThemeColors.TEXT)
	var meadow := Color(0.45, 0.62, 0.25)
	var forest := Color(0.08, 0.14, 0.08)
	assert_gte(_contrast(ink, meadow), 3.0, "ink over bright grass")
	assert_gte(_contrast(chalk, forest), 3.0, "chalk over dark spruce")


func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear()
	var lb := b.srgb_to_linear()
	var ya := 0.2126 * la.r + 0.7152 * la.g + 0.0722 * la.b
	var yb := 0.2126 * lb.r + 0.7152 * lb.g + 0.0722 * lb.b
	return (maxf(ya, yb) + 0.05) / (minf(ya, yb) + 0.05)


## The drawer is a list narrower than the 396 drawer token, so it stays left of the board
## centre of a 1280x720 canvas at Auto (914 px wide): its panel and rail end before 457.
func test_the_roster_stays_left_of_the_board_centre_at_720p() -> void:
	assert_lt(TokenRoster.WIDTH + TokenRoster.TAB_WIDTH, 914.0 / 2.0)


## Thirty tokens scroll inside the drawer and its card stays on screen: the panel never grows
## past the height it was given (a wrapping label's transient minimum once pushed the card off
## the bottom edge, found in the first capture).
func test_thirty_tokens_scroll_and_the_card_stays_in_the_drawer() -> void:
	var tokens: Array = []
	for i in 30:
		tokens.append(_token("Token %d" % i, "id%d" % i))
	var host := Control.new()
	host.theme = ThemeColors.glass_theme()
	add_child_autofree(host)
	var roster := TokenRoster.new()
	host.add_child(roster)
	roster.size = Vector2(1920, 1080)
	roster.setup(func() -> Array: return tokens, Callable(), func() -> bool: return true)
	roster.reveal()
	roster.open()
	roster.pick_row(2)
	await wait_frames(30)
	var card := roster.find_child("SelectedCard", true, false) as Control
	assert_true(card.visible)
	assert_lte(card.get_global_rect().end.y, 1080.0, "the card ends inside the drawer's height")


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


## Good news never pushes an error off the stack unread: the oldest non-error makes room.
func test_an_error_outlasts_a_run_of_other_toasts() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	toasts.show_toast("It failed. Try again.", ToastContainer.ToastType.ERROR, 30.0)
	for i in 8:
		toasts.show_toast("Saved %d" % i, ToastContainer.ToastType.SUCCESS, 30.0)
	assert_eq(toasts._active_toasts.size(), ToastContainer.MAX_VISIBLE_TOASTS)
	var kept := false
	for toast: Control in toasts._active_toasts:
		kept = kept or toast.get_meta(ToastContainer.TYPE_META) == ToastContainer.ToastType.ERROR
	assert_true(kept, "the error is still up")


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


## A kept toast (duration 0) has a 40 px close control that sends it away, and an error among
## them leaves by itself after ERROR_KEPT_S; a kept info toast has no clock.
func test_a_kept_toast_has_a_close_control_and_an_error_times_out() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	toasts.show_toast("Could not save. Check the disk.", ToastContainer.ToastType.ERROR, 0.0)
	toasts.show_toast("Connecting", ToastContainer.ToastType.INFO, 0.0)
	toasts.show_toast("Saved", ToastContainer.ToastType.SUCCESS, 30.0)
	var error: Control = toasts._active_toasts[0]
	var close := error.find_child("Close", true, false) as Button
	assert_not_null(close, "a kept error has a close control")
	assert_gte(close.custom_minimum_size.x, 40.0)
	assert_gte(close.custom_minimum_size.y, 40.0)
	assert_ne(close.tooltip_text, "", "a tooltip")
	assert_ne(close.accessibility_name, "", "an accessible name")
	var timer := error.get_node("DismissTimer") as Timer
	assert_almost_eq(timer.wait_time, ToastContainer.ERROR_KEPT_S, 0.01)
	var info: Control = toasts._active_toasts[1]
	assert_not_null(info.find_child("Close", true, false))
	assert_null(info.get_node_or_null("DismissTimer"), "a kept info toast has no clock")
	assert_null(toasts._active_toasts[2].find_child("Close", true, false), "a timed toast has none")
	close.pressed.emit()
	assert_false(toasts._active_toasts.has(error), "the close control dismisses it")


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
func test_the_bar_reports_its_top_edge_only_while_shown() -> void:
	var hints: InputHints = HINTS_SCENE.instantiate()
	add_child_autofree(hints)
	assert_eq(hints.top_edge(), INF, "no hints, no bar")
	hints.set_hints([{"key": "Esc", "action": "Pause"}])
	await wait_frames(2)
	assert_lt(hints.top_edge(), INF)
	hints._fade_idle()
	assert_eq(hints.top_edge(), INF, "a faded bar blocks nothing")


## A tool's own hints are how the tool is used: they never fade.
func test_a_tool_s_hints_never_fade() -> void:
	var hints: InputHints = HINTS_SCENE.instantiate()
	add_child_autofree(hints)
	hints.set_hints([{"key": "Esc", "action": "Pause"}])
	hints.set_tool_hints([{"key": "Click", "action": "Add point"}])
	await wait_frames(2)
	hints._fade_idle()
	assert_false(hints._idle_faded)
