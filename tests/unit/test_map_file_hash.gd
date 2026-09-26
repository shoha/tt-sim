extends GutTest

## MapFileHash: validation of untrusted hash strings, file hashing, the per-path cache and
## the hashes a host attaches to a level dictionary.

const FOLDER := "_gut_t4_map_hash"
const SHA_OF_ABC := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(FOLDER))


func after_each() -> void:
	for path in [Paths.get_level_map_path(FOLDER), Paths.get_level_map_document_path(FOLDER)]:
		MapFileHash.invalidate(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(Paths.get_level_folder(FOLDER).trim_suffix("/"))


func _store(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_valid_hash_is_64_lowercase_hex() -> void:
	assert_true(MapFileHash.is_valid_hash(SHA_OF_ABC))
	assert_false(MapFileHash.is_valid_hash(SHA_OF_ABC.to_upper()))
	assert_false(MapFileHash.is_valid_hash(SHA_OF_ABC.substr(1)))
	assert_false(MapFileHash.is_valid_hash(SHA_OF_ABC + "0"))
	assert_false(MapFileHash.is_valid_hash(SHA_OF_ABC.replace("a", "g")))
	assert_false(MapFileHash.is_valid_hash(""))
	assert_false(MapFileHash.is_valid_hash(12))
	assert_false(MapFileHash.is_valid_hash(null))


func test_sanitize_keeps_only_known_variants_with_valid_hashes() -> void:
	var raw := {"map": SHA_OF_ABC, "ttmap": "zz", "icon": SHA_OF_ABC, 5: SHA_OF_ABC}
	assert_eq(MapFileHash.sanitize(raw), {"map": SHA_OF_ABC})
	assert_eq(MapFileHash.sanitize([SHA_OF_ABC]), {})
	assert_eq(MapFileHash.sanitize(null), {})


func test_hash_bytes_and_file_are_sha256() -> void:
	assert_eq(MapFileHash.hash_bytes("abc".to_utf8_buffer()), SHA_OF_ABC)
	var path := Paths.get_level_map_path(FOLDER)
	_store(path, "abc")
	assert_eq(MapFileHash.hash_file(path), SHA_OF_ABC)
	assert_eq(MapFileHash.hash_file(path + ".missing"), "")


func test_cached_hash_follows_invalidate() -> void:
	var path := Paths.get_level_map_path(FOLDER)
	_store(path, "abc")
	assert_eq(MapFileHash.hash_file_cached(path), SHA_OF_ABC)
	# Same size, written within the same second: only invalidate() can reveal the change.
	_store(path, "abd")
	MapFileHash.invalidate(path)
	assert_ne(MapFileHash.hash_file_cached(path), SHA_OF_ABC)
	DirAccess.remove_absolute(path)
	assert_eq(MapFileHash.hash_file_cached(path), "")


func test_level_dict_hashes_name_the_files_it_has() -> void:
	_store(Paths.get_level_map_path(FOLDER), "abc")
	_store(Paths.get_level_map_document_path(FOLDER), "abc")
	var both := {"level_folder": FOLDER, "map_path": "map.glb", "map_document": "map.ttmap"}
	assert_eq(MapFileHash.hashes_for_level_dict(both), {"map": SHA_OF_ABC, "ttmap": SHA_OF_ABC})
	var document_only := {"level_folder": FOLDER, "map_path": "", "map_document": "map.ttmap"}
	assert_eq(MapFileHash.hashes_for_level_dict(document_only), {"ttmap": SHA_OF_ABC})
	var built_in := {"level_folder": FOLDER, "map_path": "res://maps/x.glb", "map_document": ""}
	assert_eq(MapFileHash.hashes_for_level_dict(built_in), {})
	assert_eq(MapFileHash.hashes_for_level_dict({"map_path": "map.glb"}), {})
