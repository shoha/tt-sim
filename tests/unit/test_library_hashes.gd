extends GutTest

## LibraryHashes (utils/library/library_hashes.gd): the file hashes and byte totals of a built
## library's library.json recomputed from the files (topic polish3).

const DIR := "user://test_library_hashes"


func before_each() -> void:
	_wipe()
	for relative in [
		"surfaces/a/albedo.png",
		"surfaces/a/albedo.png.import",
		"thumbnails/b.jpg",
		"assets/thumbs/c.png"
	]:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [DIR, relative.get_base_dir()])
	_write("surfaces/a/albedo.png", "aaaa")
	_write("surfaces/a/albedo.png.import", "sidecar")
	_write("thumbnails/b.jpg", "bb")
	_write("assets/thumbs/c.png", "ccc")


func after_each() -> void:
	_wipe()


func _write(relative: String, text: String) -> void:
	var file := FileAccess.open("%s/%s" % [DIR, relative], FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _wipe() -> void:
	# Only the test's own known files, never a recursive delete.
	for relative in [
		"surfaces/a/albedo.png",
		"surfaces/a/albedo.png.import",
		"thumbnails/b.jpg",
		"assets/thumbs/c.png"
	]:
		DirAccess.remove_absolute("%s/%s" % [DIR, relative])
	for relative in ["surfaces/a", "surfaces", "thumbnails", "assets/thumbs", "assets", ""]:
		DirAccess.remove_absolute("%s/%s" % [DIR, relative] if relative != "" else DIR)


func test_measure_hashes_every_file_but_sidecars_and_splits_the_byte_totals() -> void:
	var measured := LibraryHashes.measure(DIR)
	var hashes: Dictionary = measured["sha256"]
	assert_eq(hashes.size(), 3)
	assert_false(hashes.has("surfaces/a/albedo.png.import"), "sidecars are not hashed")
	assert_eq(hashes["thumbnails/b.jpg"], "bb".sha256_text())
	assert_eq(measured["surface_bytes"], 6, "surface files and pictures: 4 + 2")
	assert_eq(measured["thumb_bytes"], 3)


func test_a_library_that_agrees_has_no_differences_and_reconciling_is_a_no_op() -> void:
	var library := {"stats": {"file_sha256": {}, "surface_bytes": 0, "thumb_bytes": 0}}
	var fixed := LibraryHashes.reconciled(library, LibraryHashes.measure(DIR))
	assert_eq(LibraryHashes.differences(fixed, LibraryHashes.measure(DIR)), [] as Array[String])
	assert_eq(LibraryHashes.reconciled(fixed, LibraryHashes.measure(DIR)), fixed)
	assert_eq(fixed["stats"]["surface_bytes"], 6)


func test_a_changed_picture_and_stale_totals_are_named() -> void:
	var measured := LibraryHashes.measure(DIR)
	var library := LibraryHashes.reconciled(
		{"stats": {"file_sha256": {}, "surface_bytes": 0, "thumb_bytes": 0}}, measured
	)
	_write("thumbnails/b.jpg", "bbbbb")
	var again := LibraryHashes.measure(DIR)
	var lines := LibraryHashes.differences(library, again)
	assert_eq(lines.size(), 2)
	assert_true(
		lines.any(func(line: String) -> bool: return line.contains("sha256 of thumbnails/b.jpg"))
	)
	assert_true(lines.any(func(line: String) -> bool: return line.contains("surface_bytes")))
	assert_eq(
		LibraryHashes.differences(LibraryHashes.reconciled(library, again), again),
		[] as Array[String]
	)


func test_a_source_library_without_a_hash_list_is_left_alone() -> void:
	var source := {"name": "x", "stats": {"assets": 3}}
	assert_eq(LibraryHashes.reconciled(source, LibraryHashes.measure(DIR)), source)
	assert_eq(LibraryHashes.differences(source, LibraryHashes.measure(DIR)), [] as Array[String])


func test_the_core_library_in_the_repo_agrees_with_its_files() -> void:
	var text := FileAccess.get_file_as_string("res://libraries/core/library.json")
	var library: Dictionary = JSON.parse_string(text)
	var lines := LibraryHashes.differences(library, LibraryHashes.measure("res://libraries/core"))
	assert_eq(
		lines,
		[] as Array[String],
		"run tools/recompute_library_hashes.gd after regenerating a tile"
	)


func test_whole_numbers_come_back_as_ints_and_fractions_stay() -> void:
	var parsed: Variant = JSON.parse_string('{"a": 1, "b": [2, 2.5], "c": {"d": 145096153}}')
	var fixed: Dictionary = LibraryHashes.whole_numbers_as_ints(parsed)
	assert_typeof(fixed["a"], TYPE_INT)
	assert_typeof(fixed["b"][0], TYPE_INT)
	assert_typeof(fixed["b"][1], TYPE_FLOAT)
	assert_eq(JSON.stringify(fixed["c"]), '{"d":145096153}')
