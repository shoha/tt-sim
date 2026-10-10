extends GutTest

## The title's Resume (ResumeEntry): hidden with no saved session; the newest named by the day
## it was last played and its maps; the older ones in a menu named the same way; each choice
## asks for its session id. The words are pure functions of the session and the clock.

## Friday 2026-10-09 20:00 UTC, and the zone used throughout (UTC, so days are UTC days).
const FRIDAY_EVENING := 1791576000
const DAY := 86400


func _entry(sessions: Array[Dictionary]) -> ResumeEntry:
	var entry := ResumeEntry.new()
	entry.provider = func() -> Array[Dictionary]: return sessions
	entry.clock = func() -> int: return FRIDAY_EVENING + DAY
	entry.bias_minutes = 0
	add_child_autofree(entry)
	return entry


func test_the_day_reads_as_people_say_it() -> void:
	var now := FRIDAY_EVENING
	assert_eq(ResumeEntry.when_of(now - 3600, now, 0), "today's")
	assert_eq(ResumeEntry.when_of(now - DAY, now, 0), "yesterday's")
	assert_eq(ResumeEntry.when_of(now - 3 * DAY, now, 0), "Tuesday's")
	assert_eq(ResumeEntry.when_of(now - 10 * DAY, now, 0), "29 September")
	assert_eq(ResumeEntry.when_of(0, now, 0), "", "unknown")
	# Local days: Thursday 23:30 UTC is yesterday in UTC, but two hours east it is already
	# Friday 01:30, the same day as Friday evening.
	var late := FRIDAY_EVENING - 20 * 3600 - 1800
	assert_eq(ResumeEntry.when_of(late, FRIDAY_EVENING, 0), "yesterday's")
	assert_eq(ResumeEntry.when_of(late, FRIDAY_EVENING, 120), "today's")


func test_the_button_and_the_menu_name_the_session() -> void:
	var now := FRIDAY_EVENING + DAY
	var friday := {"id": "a", "name": "Old Mill", "last_played": FRIDAY_EVENING, "maps": 3}
	assert_eq(ResumeEntry.button_text(friday, now, 0), "Resume yesterday's session")
	assert_eq(ResumeEntry.maps_line(friday), "Old Mill and 2 more")
	var old := {"id": "b", "name": "Oak's Lab", "last_played": FRIDAY_EVENING - 9 * DAY, "maps": 1}
	assert_eq(ResumeEntry.button_text(old, now, 0), "Resume the session from 30 September")
	assert_eq(ResumeEntry.maps_line(old), "Oak's Lab")
	assert_eq(ResumeEntry.menu_text(old, now, 0), "The session from 30 September: Oak's Lab")
	var week := {"id": "c", "name": "Fen", "last_played": FRIDAY_EVENING - 3 * DAY, "maps": 2}
	assert_eq(ResumeEntry.menu_text(week, now, 0), "Tuesday's session: Fen and 1 more")
	assert_eq(ResumeEntry.button_text({"id": "d"}, now, 0), ResumeEntry.RESUME_UNDATED)
	assert_eq(ResumeEntry.maps_line({"id": "d", "maps": 2}), "", "no name, no line")


func test_hidden_with_no_saved_session() -> void:
	var entry := _entry([])
	assert_false(entry.visible)


func test_the_newest_leads_and_the_older_ones_are_in_its_menu() -> void:
	var sessions: Array[Dictionary] = [
		{"id": "new", "name": "Old Mill", "last_played": FRIDAY_EVENING, "maps": 3},
		{"id": "mid", "name": "Fen", "last_played": FRIDAY_EVENING - 3 * DAY, "maps": 2},
		{"id": "old", "name": "Oak's Lab", "last_played": FRIDAY_EVENING - 9 * DAY, "maps": 1},
	]
	var entry := _entry(sessions)
	watch_signals(entry)
	assert_true(entry.visible)
	assert_eq(entry.resume_button.text, "Resume yesterday's session")
	assert_eq(entry.resume_button.theme_type_variation, &"Ghost", "quiet beside the card")
	assert_eq(entry.caption.text, "Old Mill and 2 more")
	var popup := entry.older_button.get_popup()
	assert_eq(popup.item_count, 2)
	assert_eq(popup.get_item_text(0), "Tuesday's session: Fen and 1 more")
	assert_eq(entry.older_button.tooltip_text, ResumeEntry.OLDER, "an icon button has a name")
	entry.resume_button.pressed.emit()
	assert_signal_emitted_with_parameters(entry, "resume_requested", ["new"])
	popup.id_pressed.emit(popup.get_item_id(1))
	assert_signal_emitted_with_parameters(entry, "resume_requested", ["old"])
	assert_eq(entry.session_ids(), ["new", "mid", "old"] as Array[String])


func test_one_session_has_no_older_menu() -> void:
	var sessions: Array[Dictionary] = [
		{"id": "only", "name": "Old Mill", "last_played": FRIDAY_EVENING, "maps": 1},
	]
	var entry := _entry(sessions)
	assert_false(entry.older_button.visible)
	assert_eq(entry.caption.text, "Old Mill")
