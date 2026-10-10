extends GutTest

## Paths' data root: every per-user store lives under it, "user://" unless the process
## started with the user argument `--data-root=<name>`, which the multi-process scenarios
## in tests/net/ give each peer. Without it every store must stay exactly where the shipped
## game always kept it. With it every store must move under the test root, the asset cache
## index first among them: three local clients once wrote the real index at once and each
## evicted a real cached model to fit its download.
##
## A GUT command-line run has no --data-root, but Paths gives it a test root of its own
## (gut_data_root), so these tests, like every other, never see the real user's stores; the
## stores load at that root. The redirect tests call Paths.use_data_root() and put the run's
## root back in after_each().

const ROOT_NAME := "_paths_test_root"
const AssetCacheScript := preload("res://autoloads/asset_cache_manager.gd")

## The shipped path of every store Paths owns, by the name it has there
const SHIPPED := {
	"LEVELS_DIR": "user://levels/",
	"SETTINGS_PATH": "user://settings.cfg",
	"GRAPHICS_WARMUP_PATH": "user://graphics_warmup.cfg",
	"PERF_LOG_DIR": "user://perf_logs/",
	"ASSET_CACHE_DIR": "user://asset_cache/",
	"ASSET_CACHE_INDEX_PATH": "user://asset_cache_index.json",
	"USER_ASSETS_DIR": "user://user_assets/",
	"AVATARS_DIR": "user://avatars/",
	"UPDATES_DIR": "user://updates/",
}


## The data root this run started with, put back after each redirect test
var _run_root := ""


func before_all() -> void:
	_run_root = Paths.DATA_ROOT


func after_each() -> void:
	Paths.use_data_root(_run_root)
	Paths.remove_test_data_root(Paths.test_data_root(ROOT_NAME))


func _stores() -> Dictionary:
	return {
		"LEVELS_DIR": Paths.LEVELS_DIR,
		"SETTINGS_PATH": Paths.SETTINGS_PATH,
		"GRAPHICS_WARMUP_PATH": Paths.GRAPHICS_WARMUP_PATH,
		"PERF_LOG_DIR": Paths.PERF_LOG_DIR,
		"ASSET_CACHE_DIR": Paths.ASSET_CACHE_DIR,
		"ASSET_CACHE_INDEX_PATH": Paths.ASSET_CACHE_INDEX_PATH,
		"USER_ASSETS_DIR": Paths.USER_ASSETS_DIR,
		"AVATARS_DIR": Paths.AVATARS_DIR,
		"UPDATES_DIR": Paths.UPDATES_DIR,
	}


func test_the_shipped_root_keeps_every_store_at_its_shipped_path() -> void:
	assert_eq(Paths.SHIPPED_DATA_ROOT, "user://")
	assert_eq(Paths.store_paths(Paths.SHIPPED_DATA_ROOT), SHIPPED)


func test_every_store_is_under_the_root_the_run_started_with() -> void:
	assert_eq(Paths.DATA_ROOT, _run_root)
	assert_eq(_stores(), Paths.store_paths(_run_root))


func test_a_gut_command_line_run_has_a_test_root_of_its_own() -> void:
	var expected := Paths.gut_data_root(OS.get_cmdline_args(), OS.get_process_id())
	if expected == "":
		pending("not a GUT command-line run (the editor panel has no runner script)")
		return
	assert_eq(_run_root, expected)
	assert_true(_run_root.begins_with("user://_test_roots/gut_"), _run_root)
	assert_ne(_run_root, Paths.SHIPPED_DATA_ROOT)


func test_gut_data_root_names_only_the_gut_runner() -> void:
	var gut_args := PackedStringArray(
		["--headless", "--script", "res://addons/gut/gut_cmdln.gd"]
	)
	assert_eq(Paths.gut_data_root(gut_args, 4242), "user://_test_roots/gut_4242/")
	assert_eq(Paths.gut_data_root(PackedStringArray(), 4242), "")
	assert_eq(Paths.gut_data_root(PackedStringArray(["--headless", "--path", "x"]), 4242), "")
	assert_eq(
		Paths.gut_data_root(PackedStringArray(["--script", "res://tools/render_map.gd"]), 4242), ""
	)


func test_stores_that_copy_a_path_copied_the_runs_root() -> void:
	var stores := Paths.store_paths(_run_root)
	assert_eq(LevelManager.levels_dir, stores.LEVELS_DIR)
	assert_eq(UiPreferences.settings_path, stores.SETTINGS_PATH)
	assert_eq(AuthoringAutosave.directory, stores.LEVELS_DIR + "_autosave/")
	assert_eq(AvatarLibrary.directory, stores.AVATARS_DIR)
	assert_eq(UpdateManager._pending_update_file, stores.UPDATES_DIR + "pending_update.json")
	assert_eq(UpdateManager._update_success_file, stores.UPDATES_DIR + "update_success.txt")
	assert_eq(
		AssetManager.cache.get_expected_cache_path("p", "a", "v"),
		stores.ASSET_CACHE_DIR + "p/a/v.glb"
	)


func test_args_without_a_data_root_select_the_shipped_root() -> void:
	assert_eq(Paths.data_root_from_args(PackedStringArray()), "user://")
	assert_eq(
		Paths.data_root_from_args(PackedStringArray(["-gconfig=x.json", "--role=host"])),
		"user://"
	)


func test_the_argument_selects_a_test_root() -> void:
	var args := PackedStringArray(["--role=client", "--data-root=net_sync_client"])
	assert_eq(Paths.data_root_from_args(args), "user://_test_roots/net_sync_client/")


func test_a_test_root_name_cannot_climb_out_or_name_the_shipped_root() -> void:
	assert_eq(Paths.test_data_root("../.."), "user://_test_roots/unnamed/")
	assert_eq(Paths.test_data_root(""), "user://_test_roots/unnamed/")
	assert_eq(Paths.test_data_root("a/../b"), "user://_test_roots/ab/")
	assert_eq(Paths.test_data_root("C:\\x"), "user://_test_roots/Cx/")


func test_a_test_root_moves_every_store() -> void:
	var root := Paths.test_data_root(ROOT_NAME)
	Paths.use_data_root(root)
	var moved := _stores()
	for key in SHIPPED:
		var expected: String = root + str(SHIPPED[key]).trim_prefix("user://")
		assert_eq(moved[key], expected, key)


func test_the_asset_cache_writes_its_files_and_index_under_a_test_root() -> void:
	var real_index := str(SHIPPED["ASSET_CACHE_INDEX_PATH"])
	var real_index_time := _modified_time(real_index)
	var root := Paths.test_data_root(ROOT_NAME)
	Paths.use_data_root(root)
	var cache: Node = add_child_autofree(AssetCacheScript.new())

	var path: String = cache.store_asset("paths_test", "asset", "v", PackedByteArray([1, 2, 3]))

	assert_eq(path, root + "asset_cache/paths_test/asset/v.glb")
	assert_true(FileAccess.file_exists(path), "The cached file is in the test root")
	assert_true(FileAccess.file_exists(root + "asset_cache_index.json"), "So is its index")
	assert_eq(_modified_time(real_index), real_index_time, "The real index is untouched")


## A file's modification time, or -1 when it does not exist (a fresh machine has no index).
func _modified_time(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else -1


func test_removing_a_test_root_refuses_anything_else() -> void:
	assert_false(Paths.remove_test_data_root("user://"))
	assert_false(Paths.remove_test_data_root("user://levels/"))
	assert_false(Paths.remove_test_data_root("user://_test_roots/"))
	assert_false(Paths.remove_test_data_root("user://_test_roots/../levels/"))
	assert_push_error(4, "Each refusal is logged")


func test_removing_a_test_root_deletes_its_tree() -> void:
	var root := Paths.test_data_root(ROOT_NAME)
	DirAccess.make_dir_recursive_absolute(root + "levels/deep/")
	var file := FileAccess.open(root + "levels/deep/level.json", FileAccess.WRITE)
	file.store_string("{}")
	file.close()

	assert_true(Paths.remove_test_data_root(root))
	assert_false(DirAccess.dir_exists_absolute(root))
