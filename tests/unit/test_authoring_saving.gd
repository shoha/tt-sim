extends GutTest

## Saving off the main thread (topic perfaudit, card authsave): MapDocumentSnapshot freezes a
## document so an edit after the capture never reaches the file, MapDocumentWriter runs one write
## at a time on a worker and hands failures back on the main thread, every file is replaced
## atomically, and AuthoringSaving coalesces autosave ticks and Save presses. Everything writes
## under user://_authsave_test/ (levels and the autosave slot included).

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const ROOT := "user://_authsave_test/"
const ROW := [0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]


## AuthoringSaving's host without a map: counts syncs, never regenerates.
class FakeHost:
	extends Node
	var session := AuthoringSession.unsaved()
	var document: MapDocument = null
	var level: LevelData = null
	var syncs := 0
	var open := true

	func is_session_open() -> bool:
		return open

	func sync_document() -> void:
		syncs += 1

	func can_autosave() -> bool:
		return true

	func prepare_save_async() -> void:
		await get_tree().process_frame

	func capture_thumbnail() -> Image:
		return null


func before_each() -> void:
	LevelManager.levels_dir = ROOT + "levels/"
	AuthoringAutosave.directory = ROOT + "levels/_autosave/"
	DirAccess.make_dir_recursive_absolute(ROOT + "levels/")


func after_each() -> void:
	_remove_tree(ROOT)
	LevelManager.levels_dir = Paths.LEVELS_DIR
	AuthoringAutosave.directory = Paths.LEVELS_DIR + "_autosave/"


func _remove_tree(path: String) -> void:
	if LibraryPaths.verify(path) != "":  # "" and "." mean the working directory (the project)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub) + "/")
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path.trim_suffix("/"))


func _job(doc: MapDocument, path: String) -> MapDocumentWriter.Job:
	var job := MapDocumentWriter.Job.new()
	job.snapshot = MapDocumentSnapshot.capture(doc)
	job.path = path
	return job


## A brush stroke's worth of edits: heights, a mask, a biome dab and a row appended.
func _stroke(doc: MapDocument, n: int) -> void:
	var at := (n * 37) % doc.sample_count()
	doc.heights[at] += 0.25
	doc.erase_mask[at] = 255 - doc.erase_mask[at]
	doc.biome_density[at] = (n * 11) % 256
	doc.scatter[Fixtures.TREE_ID].append_array(PackedFloat32Array(ROW))


func _zip_entries(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var out := {}
	if reader.open(path) != OK:
		return out
	for entry_name in reader.get_files():
		if not entry_name.ends_with("/"):
			out[entry_name] = reader.read_file(entry_name)
	reader.close()
	return out


func _assert_entries(got: Dictionary, expected: Dictionary, label: String) -> void:
	assert_eq(got.keys().size(), expected.keys().size(), label + ": entry count")
	for entry_name in expected:
		assert_eq(got.get(entry_name), expected[entry_name], "%s: %s" % [label, entry_name])


## Waits (at most `max_frames` frames) until `cond` holds.
func _until(cond: Callable, max_frames: int = 600) -> void:
	for i in max_frames:
		if cond.call():
			return
		await get_tree().process_frame


func _saving_with_host(doc: MapDocument) -> AuthoringSaving:
	var host := FakeHost.new()
	host.document = doc
	host.level = AuthoringController.new_level()
	host.level.level_name = "_authsave_ map"
	add_child_autofree(host)
	var saving := AuthoringSaving.new(host)
	host.add_child(saving)
	return saving


# --- the snapshot ---------------------------------------------------------------------


func test_a_capture_is_not_reached_by_later_edits() -> void:
	var doc := Fixtures.full_doc()
	var expected: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	var snap := MapDocumentSnapshot.capture(doc)
	_stroke(doc, 3)
	doc.scatter["x/New"] = PackedFloat32Array(ROW)
	doc.biome_slots[1] = 2
	doc.biome_ids.append("x/biome")
	doc.crossings.clear()
	doc.map_seed = 99
	var got: Dictionary = snap.encode()["entries"]
	_assert_entries(got, expected, "captured")
	var now := MapDocumentIO.serialize(doc)
	assert_eq(now["error"], "")
	var heights: PackedByteArray = now["entries"][MapDocumentIO.HEIGHT_ENTRY]
	assert_ne(heights, expected[MapDocumentIO.HEIGHT_ENTRY], "the edits landed in the document")


func test_serialize_is_capture_then_encode_and_reads_back() -> void:
	var doc := Fixtures.full_doc()
	var path := ROOT + "round.ttmap"
	var writer := MapDocumentWriter.new()
	writer.start(_job(doc, path))
	var job := writer.wait()
	assert_eq(job.error, OK)
	_assert_entries(_zip_entries(path), MapDocumentIO.serialize(doc)["entries"], "written")
	var read: MapDocument = MapDocumentIO.read(path)["document"]
	assert_not_null(read)
	assert_eq(read.heights, doc.heights)
	assert_eq(read.water_bodies.size(), doc.water_bodies.size())
	assert_eq(read.crossings.size(), doc.crossings.size())


func test_strokes_during_worker_writes_never_tear_them() -> void:
	var doc := Fixtures.full_doc()
	var path := ROOT + "stress.ttmap"
	var writer := MapDocumentWriter.new()
	var strokes := 0
	for save in 4:
		var expected: Dictionary = MapDocumentIO.serialize(doc)["entries"]
		var job := _job(doc, path)
		writer.start(job)
		# Strokes land at once (the worker is running or about to) and every frame after.
		_stroke(doc, strokes)
		strokes += 1
		for frame in 600:
			if writer.poll() != null:
				break
			_stroke(doc, strokes)
			strokes += 1
			await get_tree().process_frame
		assert_true(job.done)
		assert_eq(job.error, OK)
		_assert_entries(_zip_entries(path), expected, "save %d" % save)
	writer.start(_job(doc, path))
	writer.wait()
	_assert_entries(_zip_entries(path), MapDocumentIO.serialize(doc)["entries"], "the last save")


# --- the writer -----------------------------------------------------------------------


func test_one_write_at_a_time_with_its_result_on_the_main_thread() -> void:
	var writer := MapDocumentWriter.new()
	var first := _job(Fixtures.full_doc(), ROOT + "a.ttmap")
	assert_true(writer.start(first))
	assert_true(writer.is_busy())
	assert_false(writer.start(_job(Fixtures.full_doc(), ROOT + "b.ttmap")), "refused while busy")
	assert_eq(writer.wait(), first)
	assert_true(first.done)
	assert_eq(first.error, OK)
	assert_gt(first.worker_usec, 0)
	assert_false(writer.is_busy())
	assert_null(writer.poll())
	assert_null(writer.wait())
	assert_false(FileAccess.file_exists(ROOT + "b.ttmap"))


func test_a_failed_write_comes_back_with_its_reason() -> void:
	var writer := MapDocumentWriter.new()
	var missing := _job(Fixtures.full_doc(), ROOT + "no_such_folder/x.ttmap")
	writer.start(missing)
	writer.wait()
	assert_ne(missing.error, OK)
	assert_string_contains(missing.message, "no_such_folder")
	var broken := Fixtures.full_doc()
	broken.heights[5] = NAN
	var refused := _job(broken, ROOT + "refused.ttmap")
	writer.start(refused)
	writer.wait()
	assert_eq(refused.error, ERR_INVALID_DATA)
	assert_string_contains(refused.message, "heights")
	assert_false(FileAccess.file_exists(ROOT + "refused.ttmap"))


func test_a_blocked_write_keeps_the_old_file_and_leaves_no_temp() -> void:
	var path := ROOT + "atomic.ttmap"
	var old := Fixtures.full_doc()
	assert_eq(MapDocumentIO.write(old, path), OK)
	var newer := Fixtures.full_doc()
	newer.map_seed = 7
	var writer := MapDocumentWriter.new()
	# The temp name is taken by a folder, so the packer cannot open it (any platform).
	DirAccess.make_dir_recursive_absolute(path + MapDocumentIO.TEMP_SUFFIX)
	var job := _job(newer, path)
	writer.start(job)
	writer.wait()
	DirAccess.remove_absolute(path + MapDocumentIO.TEMP_SUFFIX)
	assert_ne(job.error, OK)
	assert_eq(MapDocumentIO.read(path)["document"].map_seed, old.map_seed, "old file intact")
	if OS.get_name() != "Windows":
		return
	# A held handle fails the rename itself, after the whole temp file was written.
	var held := FileAccess.open(path, FileAccess.READ)
	var renamed := _job(newer, path)
	writer.start(renamed)
	writer.wait()
	held.close()
	assert_ne(renamed.error, OK)
	assert_false(FileAccess.file_exists(path + MapDocumentIO.TEMP_SUFFIX), "temp removed")
	assert_eq(MapDocumentIO.read(path)["document"].map_seed, old.map_seed, "old file intact")


func test_the_autosave_writes_its_level_after_its_document_atomically() -> void:
	var level := AuthoringController.new_level()
	level.level_name = "_authsave_ first"
	assert_eq(AuthoringAutosave.write(Fixtures.full_doc(), level), OK)
	assert_true(AuthoringAutosave.exists())
	level.level_name = "_authsave_ second"
	# The level's temp name is blocked: the document is replaced, the old level kept.
	DirAccess.make_dir_recursive_absolute(AuthoringAutosave.level_path() + MapDocumentIO.TEMP_SUFFIX)
	var job := AuthoringAutosave.job(Fixtures.full_doc(), level)
	MapDocumentWriter.run(job)
	DirAccess.remove_absolute(AuthoringAutosave.level_path() + MapDocumentIO.TEMP_SUFFIX)
	assert_ne(job.error, OK)
	assert_string_contains(job.message, AuthoringAutosave.LEVEL_NAME)
	assert_eq(AuthoringAutosave.read_level().level_name, "_authsave_ first")
	assert_false(FileAccess.file_exists(AuthoringAutosave.document_path() + MapDocumentIO.TEMP_SUFFIX))


# --- AuthoringSaving ------------------------------------------------------------------


func test_autosave_ticks_during_a_write_coalesce_into_one_follow_up() -> void:
	var saving := _saving_with_host(Fixtures.full_doc())
	var host: FakeHost = saving.get_parent()
	saving.autosave_tick()
	assert_true(saving.is_writing())
	var first_revision := host.session.revision
	host.session.mark_edited()
	saving.autosave_tick()
	saving.autosave_tick()
	assert_eq(host.syncs, 1, "ticks during the write wait")
	await _until(func() -> bool: return host.syncs >= 2 and not saving.is_writing())
	await wait_process_frames(3)
	assert_eq(host.syncs, 2, "one follow-up for both ticks")
	assert_gt(host.session.revision, first_revision)
	assert_eq(host.session.autosaved_revision, host.session.revision)
	assert_false(host.session.needs_autosave())
	assert_true(AuthoringAutosave.exists())


func test_an_edit_during_a_save_keeps_the_session_dirty() -> void:
	var saving := _saving_with_host(Fixtures.full_doc())
	var host: FakeHost = saving.get_parent()
	var saved_at := host.session.revision
	var pending: Array = []
	var run := func() -> void: pending.append(await saving.save_async())
	run.call()
	await _until(saving.is_writing)
	host.session.mark_edited()
	await _until(func() -> bool: return not pending.is_empty())
	assert_eq(pending, [true])
	assert_eq(host.session.saved_revision, saved_at, "the revision the snapshot held")
	assert_true(host.session.is_dirty(), "the stroke during the write is not saved yet")
	assert_true(host.session.needs_autosave())
	assert_true(FileAccess.file_exists(LevelManager.map_document_path(host.level.level_folder)))


func test_saves_pressed_during_a_save_make_one_follow_up() -> void:
	var saving := _saving_with_host(Fixtures.full_doc())
	var host: FakeHost = saving.get_parent()
	var results: Array = []
	var press := func() -> void: results.append(await saving.save_async())
	press.call()
	await _until(saving.is_writing)
	host.session.mark_edited()
	press.call()
	press.call()
	await _until(func() -> bool: return results.size() >= 3)
	assert_eq(results, [true, true, true])
	assert_eq(host.syncs, 2, "the first save and one follow-up")
	assert_false(host.session.is_dirty(), "the follow-up saved the edit")
	assert_eq(LevelManager.get_saved_levels().size(), 1)


func test_discarding_waits_for_an_autosave_in_flight() -> void:
	var saving := _saving_with_host(Fixtures.full_doc())
	saving.autosave_tick()
	assert_true(saving.is_writing())
	saving.discard_autosave()
	assert_false(saving.is_writing())
	assert_false(AuthoringAutosave.exists(), "nothing lands after the discard")
	assert_false(FileAccess.file_exists(AuthoringAutosave.document_path()))


func test_a_failed_autosave_marks_nothing() -> void:
	var broken := Fixtures.full_doc()
	broken.heights[0] = INF
	var saving := _saving_with_host(broken)
	var host: FakeHost = saving.get_parent()
	saving.autosave_tick()
	await _until(func() -> bool: return not saving.is_writing())
	assert_eq(host.session.autosaved_revision, 0)
	assert_true(host.session.needs_autosave())
	assert_ne(saving.last_write["error"], OK)
	assert_false(AuthoringAutosave.exists())
	assert_engine_error(1, "one warning naming the problem")
