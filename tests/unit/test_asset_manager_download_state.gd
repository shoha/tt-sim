extends GutTest

## Tests for download state persistence (resumable pack downloads).
##
## These tests exercise the state-file helpers directly on AssetManager
## without needing HTTP downloads.

const USER_ASSETS_USER_DIR := "user://user_assets/"
const TEST_PACK_ID := "test_resume_pack"


func _get_pack_dir() -> String:
	return USER_ASSETS_USER_DIR + TEST_PACK_ID + "/"


func _get_state_path() -> String:
	return _get_pack_dir() + "download_state.json"


func _get_manifest_path() -> String:
	return _get_pack_dir() + "manifest.json"


func _write_test_manifest() -> Dictionary:
	var pack_dir := _get_pack_dir()
	if not DirAccess.dir_exists_absolute(pack_dir):
		DirAccess.make_dir_recursive_absolute(pack_dir)
	var manifest := {
		"pack_id": TEST_PACK_ID,
		"display_name": "Test Resume Pack",
		"base_url": "https://example.com/pack/",
		"assets":
		{
			"a1":
			{
				"display_name": "Asset 1",
				"variants": {"default": {"model": "a1.glb", "icon": "a1.png"}}
			},
			"a2":
			{
				"display_name": "Asset 2",
				"variants": {"default": {"model": "a2.glb", "icon": "a2.png"}}
			}
		}
	}
	var file := FileAccess.open(_get_manifest_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "", false))
	file.close()
	return manifest


func _write_test_state(total_variants: int = 2) -> void:
	var state := {
		"manifest_url": "https://example.com/pack/manifest.json",
		"started_at": "2026-01-01T00:00:00",
		"total_variants": total_variants,
	}
	var file := FileAccess.open(_get_state_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(state, "", false))
	file.close()


func _create_file(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("stub")
	file.close()


func _cleanup() -> void:
	var pack_dir := _get_pack_dir()
	if DirAccess.dir_exists_absolute(pack_dir):
		# Remove files
		for subdir in ["models/", "icons/", ""]:
			var dir := DirAccess.open(pack_dir + subdir)
			if dir:
				dir.list_dir_begin()
				var fname := dir.get_next()
				while fname != "":
					if not dir.current_is_dir():
						dir.remove(fname)
					fname = dir.get_next()
				dir.list_dir_end()
		# Remove subdirs then pack dir
		for subdir in ["models", "icons"]:
			if DirAccess.dir_exists_absolute(pack_dir + subdir):
				DirAccess.remove_absolute(pack_dir + subdir)
		DirAccess.remove_absolute(pack_dir)


func before_each() -> void:
	_cleanup()


func after_all() -> void:
	_cleanup()


func test_get_incomplete_downloads_returns_pack_with_missing_files() -> void:
	_write_test_manifest()
	_write_test_state(2)
	# Simulate: a1.glb downloaded, a2.glb missing
	_create_file(_get_pack_dir() + "models/a1.glb")
	_create_file(_get_pack_dir() + "icons/a1.png")

	# Reload packs so AssetManager knows about this pack
	AssetManager.reload_packs()

	var incomplete := AssetManager.get_incomplete_downloads()
	assert_eq(incomplete.size(), 1, "Should find one incomplete pack")
	assert_eq(incomplete[0].pack_id, TEST_PACK_ID)
	assert_eq(incomplete[0].total_variants, 2)
	assert_eq(incomplete[0].downloaded_variants, 1, "One variant fully present")


func test_get_incomplete_downloads_skips_fully_downloaded_pack() -> void:
	_write_test_manifest()
	_write_test_state(2)
	# All files present
	_create_file(_get_pack_dir() + "models/a1.glb")
	_create_file(_get_pack_dir() + "icons/a1.png")
	_create_file(_get_pack_dir() + "models/a2.glb")
	_create_file(_get_pack_dir() + "icons/a2.png")

	AssetManager.reload_packs()

	var incomplete := AssetManager.get_incomplete_downloads()
	# Pack is fully downloaded -- state file should have been cleaned up
	var found := false
	for item in incomplete:
		if item.pack_id == TEST_PACK_ID:
			found = true
	assert_false(found, "Fully downloaded pack should not appear as incomplete")


func test_dismiss_pack_download_removes_state_file() -> void:
	_write_test_manifest()
	_write_test_state()

	assert_true(FileAccess.file_exists(_get_state_path()), "State file should exist before dismiss")
	AssetManager.dismiss_pack_download(TEST_PACK_ID)
	assert_false(
		FileAccess.file_exists(_get_state_path()), "State file should be gone after dismiss"
	)


func test_get_incomplete_downloads_ignores_packs_without_state_file() -> void:
	_write_test_manifest()
	# No download_state.json -- this is an on-demand pack, not a user-initiated download

	AssetManager.reload_packs()

	var incomplete := AssetManager.get_incomplete_downloads()
	var found := false
	for item in incomplete:
		if item.pack_id == TEST_PACK_ID:
			found = true
	assert_false(found, "Pack without download_state.json should not appear")
