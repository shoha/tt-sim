extends GutTest

## AuthoringHistory's memory cap: entries say how many bytes they hold, and the oldest are
## dropped past max_bytes (the newest always stays).


func _entry(bytes: int, log: Array, label: String) -> Dictionary:
	return {
		"label": label,
		"undo": func() -> void: log.append("undo " + label),
		"redo": func() -> void: log.append("redo " + label),
		"bytes": bytes,
	}


func test_oldest_entries_drop_past_the_byte_cap() -> void:
	var history := AuthoringHistory.new()
	history.max_bytes = 1000
	var log: Array = []
	for i in 5:
		history.record(_entry(300, log, str(i)))
	assert_eq(history.undo_count(), 3, "900 bytes fit, 1200 do not")
	assert_true(history.held_bytes() <= 1000)
	assert_eq(history.undo(), "4")
	assert_eq(history.undo(), "3")
	assert_eq(history.undo(), "2")
	assert_eq(history.undo(), "", "0 and 1 were dropped")


func test_the_newest_entry_stays_even_when_it_alone_is_over_the_cap() -> void:
	var history := AuthoringHistory.new()
	history.max_bytes = 100
	var log: Array = []
	history.record(_entry(50, log, "small"))
	history.record(_entry(500, log, "huge"))
	assert_eq(history.undo_count(), 1)
	assert_eq(history.undo(), "huge")


func test_entries_without_bytes_count_only_toward_the_entry_cap() -> void:
	var history := AuthoringHistory.new()
	var log: Array = []
	for i in AuthoringHistory.MAX_ENTRIES + 5:
		history.record({"label": str(i)})
	assert_eq(history.undo_count(), AuthoringHistory.MAX_ENTRIES)
	assert_eq(history.held_bytes(), 0)
	assert_true(log.is_empty())
