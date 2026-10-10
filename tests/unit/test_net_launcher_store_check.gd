extends GutTest

## The net launcher's check that a run left the real user's data alone (tests/net/
## net_launcher.gd). Other sessions' render jobs create and delete their own test levels in
## the real user://levels/ while a launch runs, so a new file or folder there must not fail
## the run; what a test peer must never do is modify or delete a file that existed before it,
## or write a store only a misdirected peer writes (the asset cache, installed packs,
## updates).

const Launcher := preload("res://tests/net/net_launcher.gd")

## A before snapshot: two files of an existing level, a folder (0), the settings file and
## cached asset files. The values are modification times.
const BEFORE := {
	"user://levels/": 0,
	"user://levels/old_level/": 0,
	"user://levels/old_level/level.json": 100,
	"user://levels/old_level/map.glb": 200,
	"user://settings.cfg": 300,
	"user://asset_cache/": 0,
	"user://asset_cache/pack/model.glb": 400,
}


func _after(changes: Dictionary, removed: Array = []) -> Dictionary:
	var after := BEFORE.duplicate()
	for path in removed:
		after.erase(path)
	after.merge(changes, true)
	return after


func _changes_to(after: Dictionary) -> Dictionary:
	return Launcher.compare_snapshots(BEFORE, after, Launcher.never_written_paths())


func test_an_unchanged_store_has_no_changes() -> void:
	var changes := _changes_to(BEFORE.duplicate())
	assert_eq(changes.modified, [])
	assert_eq(changes.deleted, [])
	assert_eq(changes.added, [])
	assert_eq(Launcher.failed_changes(changes), [])


func test_a_new_level_folder_is_information_not_a_failure() -> void:
	var changes := _changes_to(
		_after(
			{
				"user://levels/_biglf_a/": 0,
				"user://levels/_biglf_a/level.json": 500,
				"user://levels/_biglf_a/map.glb": 501,
			}
		)
	)
	assert_eq(changes.added.size(), 3)
	assert_true("user://levels/_biglf_a/" in changes.added)
	assert_eq(changes.added_never_written, [])
	assert_eq(Launcher.failed_changes(changes), [], "New files never fail the run")


func test_a_new_file_in_an_existing_level_is_information() -> void:
	var changes := _changes_to(_after({"user://levels/old_level/thumb.png": 500}))
	assert_eq(changes.added, ["user://levels/old_level/thumb.png"])
	assert_eq(Launcher.failed_changes(changes), [])


func test_a_modified_existing_file_fails() -> void:
	var changes := _changes_to(_after({"user://levels/old_level/level.json": 999}))
	assert_eq(changes.modified, ["user://levels/old_level/level.json"])
	assert_eq(Launcher.failed_changes(changes), ["modified user://levels/old_level/level.json"])


func test_a_deleted_existing_file_fails() -> void:
	var changes := _changes_to(_after({}, ["user://settings.cfg"]))
	assert_eq(changes.deleted, ["user://settings.cfg"])
	assert_eq(Launcher.failed_changes(changes), ["deleted user://settings.cfg"])


func test_a_deleted_level_fails_through_its_files_not_its_folder() -> void:
	var changes := _changes_to(
		_after(
			{},
			[
				"user://levels/old_level/",
				"user://levels/old_level/level.json",
				"user://levels/old_level/map.glb",
			]
		)
	)
	assert_eq(changes.deleted.size(), 2, "The folder itself is not a file")
	assert_false("user://levels/old_level/" in changes.deleted)
	assert_eq(Launcher.failed_changes(changes).size(), 2)


func test_a_new_path_in_a_never_written_store_fails() -> void:
	var changes := _changes_to(
		_after(
			{
				"user://asset_cache/pack/other.glb": 500,
				"user://user_assets/": 0,
				"user://asset_cache_index.json": 501,
				"user://updates/pending_update.json": 502,
			}
		)
	)
	assert_eq(changes.added, [], "None of these is only information")
	assert_eq(changes.added_never_written.size(), 4)
	var failed := Launcher.failed_changes(changes)
	assert_eq(failed.size(), 4)
	assert_true("added user://asset_cache/pack/other.glb" in failed)
	assert_true("added user://asset_cache_index.json" in failed)


func test_a_changed_file_and_a_new_level_report_separately() -> void:
	var changes := _changes_to(
		_after({"user://settings.cfg": 301, "user://levels/_ui_tour_room/": 0})
	)
	assert_eq(Launcher.failed_changes(changes), ["modified user://settings.cfg"])
	assert_eq(changes.added, ["user://levels/_ui_tour_room/"])


func test_the_threaded_stat_matches_the_one_at_a_time_stat() -> void:
	var folder := Paths.DATA_ROOT + "_launcher_stat_test/"
	DirAccess.make_dir_recursive_absolute(folder)
	var paths := []
	for i in Launcher.STAT_CHUNK * 2 + 7:
		var path := "%sfile_%d.txt" % [folder, i]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("x")
		file.close()
		paths.append(path)
	paths.insert(3, folder + "missing.txt")

	var times := Launcher.modified_times(paths)

	assert_eq(times.size(), paths.size(), "A time for every path, over three chunks")
	assert_eq(times[3], 0, "A missing file has none")
	for i in paths.size():
		assert_eq(times[i], FileAccess.get_modified_time(paths[i]), paths[i])
	assert_eq(Launcher.modified_times([]), [])
	_remove_folder(folder)


func _remove_folder(folder: String) -> void:
	var dir := DirAccess.open(folder)
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(folder)


func test_the_launcher_watches_the_import_source_index_beside_the_stores() -> void:
	var stores := Launcher.watched_stores()
	assert_eq(stores.IMPORT_SOURCES_PATH, "user://import_sources.cfg")
	assert_eq(stores.IMPORT_SOURCES_PATH, Paths.SHIPPED_DATA_ROOT + Paths.IMPORT_SOURCES_NAME)
	for key in Paths.store_paths(Paths.SHIPPED_DATA_ROOT):
		assert_true(stores.has(key), "%s is watched" % key)


func test_only_the_stores_peers_alone_write_fail_on_new_files() -> void:
	var never := Launcher.never_written_paths()
	assert_true("user://asset_cache/" in never)
	assert_true("user://asset_cache_index.json" in never)
	assert_true("user://user_assets/" in never)
	assert_true("user://updates/" in never)
	assert_false("user://levels/" in never, "Other sessions write test levels there")
	assert_false("user://avatars/" in never, "Render probes write avatars there")
	assert_false("user://import_sources.cfg" in never)
