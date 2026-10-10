extends GutTest

## Level map streaming for map.glb + map.ttmap: the host's variant whitelist (on top of the
## active-level authorization gate), the client-side request refusing unknown variants,
## the cache extension per file type, and the stale-cache check against the host's content
## hash. Unit level only: AssetStreamer's RPCs and a real second peer over Steam are not
## exercised here.
##
## The cache tests use the live AssetManager.cache, which in a GUT run keeps its files and
## index in the run's own test data root (Paths.gut_data_root), never the real user's. They
## still use a folder name no real level can have and remove their entries afterwards.

const CacheScript := preload("res://autoloads/asset_cache_manager.gd")
const ACTIVE := "my_dungeon"
const CACHE_FOLDER := "_gut_t4_cache"


func after_each() -> void:
	for variant in [Paths.LEVEL_MAP_VARIANT, Paths.LEVEL_MAP_DOCUMENT_VARIANT]:
		AssetManager.cache.remove_cached(
			Paths.LEVEL_MAPS_PACK_ID, CACHE_FOLDER, variant, Paths.get_level_map_file_type(variant)
		)


func test_whitelisted_variants_name_the_two_map_files() -> void:
	var streamer := AssetManager.streamer
	assert_eq(
		streamer.level_map_file_for_request(ACTIVE, "map", ACTIVE), Paths.get_level_map_path(ACTIVE)
	)
	assert_eq(
		streamer.level_map_file_for_request(ACTIVE, "ttmap", ACTIVE),
		Paths.get_level_map_document_path(ACTIVE)
	)
	assert_true(streamer.level_map_file_for_request(ACTIVE, "ttmap", ACTIVE).ends_with("map.ttmap"))


func test_unknown_variants_are_refused() -> void:
	var streamer := AssetManager.streamer
	for variant in ["", "model", "map.glb", "level", "../level.json", "thumbnail", "MAP", "ttmap/"]:
		assert_eq(
			streamer.level_map_file_for_request(ACTIVE, variant, ACTIVE), "", "refused: " + variant
		)


func test_whitelist_keeps_the_authorization_gate() -> void:
	var streamer := AssetManager.streamer
	assert_eq(streamer.level_map_file_for_request("other_level", "ttmap", ACTIVE), "")
	assert_eq(streamer.level_map_file_for_request(ACTIVE, "map", ""), "")
	assert_eq(streamer.level_map_file_for_request("../../etc/passwd", "ttmap", ACTIVE), "")


func test_client_refuses_to_request_an_unknown_variant() -> void:
	var failures := []
	var record := func(pack: String, asset: String, variant: String, error: String, _t: String):
		failures.append([pack, asset, variant, error])
	AssetManager.streamer.asset_failed.connect(record)
	AssetManager.streamer.request_map_file_from_host(ACTIVE, "../level.json")
	AssetManager.streamer.asset_failed.disconnect(record)
	assert_eq(failures, [[Paths.LEVEL_MAPS_PACK_ID, ACTIVE, "../level.json", "Unknown map file"]])


func test_file_types_and_cache_extensions() -> void:
	assert_eq(Paths.get_level_map_file_type("map"), "model")
	assert_eq(Paths.get_level_map_file_type("ttmap"), Paths.LEVEL_MAP_DOCUMENT_FILE_TYPE)
	assert_eq(Paths.get_level_map_file_type("x"), "")
	var cache := AssetManager.cache
	assert_eq(cache.extension_for("model"), ".glb")
	assert_eq(cache.extension_for(Paths.LEVEL_MAP_DOCUMENT_FILE_TYPE), ".ttmap")
	assert_eq(cache.extension_for("icon"), ".png")


func _store(variant: String, text: String) -> String:
	return AssetManager.cache.store_asset(
		Paths.LEVEL_MAPS_PACK_ID,
		CACHE_FOLDER,
		variant,
		text.to_utf8_buffer(),
		Paths.get_level_map_file_type(variant)
	)


func test_matching_hash_uses_the_cache() -> void:
	var path := _store("ttmap", "document v1")
	assert_true(path.ends_with("/ttmap.ttmap"))
	var digest := MapFileHash.hash_bytes("document v1".to_utf8_buffer())
	assert_eq(AssetManager.streamer.get_cached_map_file(CACHE_FOLDER, "ttmap", digest), path)
	assert_true(FileAccess.file_exists(path))


func test_mismatched_hash_drops_the_stale_copy() -> void:
	var path := _store("map", "glb v1")
	var newer := MapFileHash.hash_bytes("glb v2".to_utf8_buffer())
	assert_eq(AssetManager.streamer.get_cached_map_file(CACHE_FOLDER, "map", newer), "")
	assert_false(FileAccess.file_exists(path), "the stale file is removed")
	assert_eq(AssetManager.streamer.get_cached_map_file(CACHE_FOLDER, "map", ""), "")


func test_no_host_hash_accepts_the_cached_copy() -> void:
	var path := _store("map", "glb v1")
	assert_eq(AssetManager.streamer.get_cached_map_file(CACHE_FOLDER, "map", ""), path)
	assert_eq(AssetManager.streamer.get_cached_map_path(CACHE_FOLDER), path)


func test_entry_without_a_stored_hash_is_hashed_once() -> void:
	var path := _store("map", "glb v1")
	var cache := AssetManager.cache
	# An entry cached before hashing existed: registered from disk, no hash in the index.
	cache.register_cached_file(Paths.LEVEL_MAPS_PACK_ID, CACHE_FOLDER, "map", path, "model")
	var expected := MapFileHash.hash_bytes("glb v1".to_utf8_buffer())
	assert_eq(
		cache.get_cached_hash(Paths.LEVEL_MAPS_PACK_ID, CACHE_FOLDER, "map", "model"), expected
	)
	assert_eq(AssetManager.streamer.get_cached_map_file(CACHE_FOLDER, "map", expected), path)


func test_malformed_stored_hash_is_not_trusted() -> void:
	var entry = CacheScript.CacheEntry.from_dict({"path": "user://x", "content_hash": "not-hex"})
	assert_eq(entry.content_hash, "")
	var good := MapFileHash.hash_bytes("x".to_utf8_buffer())
	assert_eq(CacheScript.CacheEntry.from_dict({"content_hash": good}).content_hash, good)
