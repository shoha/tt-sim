extends GutTest

## AuthoringSession dirty tracking and AuthoringHistory, the undo seam the brushes record into.


func test_a_loaded_map_starts_clean_and_an_edit_dirties_it() -> void:
	var session := AuthoringSession.new()
	watch_signals(session)
	assert_false(session.is_dirty())
	assert_false(session.needs_autosave())
	session.mark_edited()
	assert_true(session.is_dirty())
	assert_signal_emitted_with_parameters(session, "dirty_changed", [true])
	session.mark_edited()
	assert_signal_emit_count(session, "dirty_changed", 1, "only the change is signalled")


func test_a_new_map_starts_unsaved() -> void:
	var session := AuthoringSession.unsaved()
	assert_true(session.is_dirty())
	assert_true(session.needs_autosave())


func test_save_cleans_and_supersedes_the_autosave() -> void:
	var session := AuthoringSession.unsaved()
	watch_signals(session)
	session.mark_saved()
	assert_false(session.is_dirty())
	assert_false(session.needs_autosave())
	assert_signal_emitted_with_parameters(session, "dirty_changed", [false])


func test_autosave_is_needed_once_per_new_edit() -> void:
	var session := AuthoringSession.new()
	session.mark_edited()
	assert_true(session.needs_autosave())
	session.mark_autosaved()
	assert_false(session.needs_autosave())
	assert_true(session.is_dirty(), "an autosave is not a save")
	session.mark_edited()
	assert_true(session.needs_autosave())


func test_history_undo_and_redo_run_the_entry_and_track_availability() -> void:
	var history := AuthoringHistory.new()
	var log: Array[String] = []
	assert_false(history.can_undo())
	assert_eq(history.undo(), "", "nothing to undo")
	history.record(
		{
			"label": "Paint",
			"undo": func() -> void: log.append("undo"),
			"redo": func() -> void: log.append("redo"),
		}
	)
	assert_true(history.can_undo())
	assert_false(history.can_redo())
	assert_eq(history.undo(), "Paint")
	assert_true(history.can_redo())
	assert_eq(history.redo(), "Paint")
	assert_eq(log, ["undo", "redo"])


func test_recording_clears_redo_and_the_stack_is_bounded() -> void:
	var history := AuthoringHistory.new()
	for i in AuthoringHistory.MAX_ENTRIES + 5:
		history.record({"label": str(i)})
	history.undo()
	assert_true(history.can_redo())
	history.record({"label": "new"})
	assert_false(history.can_redo())
	var undone := 0
	while history.can_undo():
		history.undo()
		undone += 1
	assert_eq(undone, AuthoringHistory.MAX_ENTRIES)
