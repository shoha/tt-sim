extends "res://tests/unit/library_transfer_case.gd"

## Multiplayer library transfer, the client's side of a bundle (docs/systems/library.md
## "Multiplayer"): verify_and_install accepts a good partial into the transient cache and refuses
## every hostile one with a structured error, writing nothing (wrong sha256 or size, an extra
## file, traversal, a disallowed extension, a reserved or official id, an id or version mismatch,
## a full library posing as a partial, a bad GLB, truncation, caps); the cache (LRU, session sweep,
## promote) and the registry's `received` source.


func _root() -> String:
	return "user://test_library_transfer_install"


# ---- installing on the client ----


func test_a_good_bundle_installs_into_the_transient_cache_and_is_served() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	assert_false(_assets().has(Tw.SPIRE))
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx()
	)
	assert_true(made["ok"], str(made["errors"]))
	assert_eq(made["libraries"], ["alienworld"])
	assert_true(_has_dir(_received_root().path_join("alienworld")))
	assert_false(_has_dir(_client_user.path_join("alienworld")), "never an installed user library")
	LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["status"], "ok")
	assert_true(info["received"])
	assert_eq(info["source"], "received")
	assert_false(info["official"])
	assert_false(info["partial"].is_empty(), "the manager can badge it partial")
	assert_eq(info["version"], "0.3.1")
	assert_true(_assets().has(Tw.SPIRE), "the used asset is served")
	assert_false(_assets().has(Tw.SHARD), "the unused one is not in the partial")
	assert_not_null(AssetStore.mesh_for(Tw.SPIRE, _paths["base"]), "the GLB loads, hash checked")
	assert_eq(
		LibraryRegistry.record_of("alienworld", _paths["base"])["hash"],
		info["partial"]["source_hash"],
		"a map saved here records the full library's hash"
	)


func test_the_manager_list_keeps_a_partial_library_apart_from_installed_ones() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	LibraryTransfer.verify_and_install(LibraryTransfer.build_bundle(request, host), _ctx())
	LibraryRegistry.apply(_paths["base"])
	var listed := LibraryRegistry.list(_paths["base"])
	var found := listed.filter(func(i: Dictionary) -> bool: return i["id"] == "alienworld")
	var alien: Dictionary = found[0]
	assert_true(alien["received"] and not alien["partial"].is_empty())
	assert_false(DirAccess.dir_exists_absolute(_client_user + "/alienworld"))
	# The user scan skips the dot folder: removing the cache removes the library.
	LibraryReceivedStore.sweep_session()
	LibraryRegistry.apply(_paths["base"])
	assert_true(LibraryRegistry.info("alienworld", _paths["base"]).is_empty())


func test_a_wrong_sha256_is_refused_and_nothing_is_written() -> void:
	var request := _request()
	var files := _bundle_files(request, _host_served())
	var glb := "alienworld/assets/tree/Crystal_Spire_v0.glb"
	var data: PackedByteArray = files[glb]
	data[data.size() - 1] = (data[data.size() - 1] + 1) % 256
	files[glb] = data
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_false(made["ok"])
	assert_has(_codes(made), LibraryPartial.E_HASH)
	assert_false(_has_dir(_received_root().path_join("alienworld")))


func test_a_wrong_size_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	var glb := "alienworld/assets/tree/Crystal_Spire_v0.glb"
	var data: PackedByteArray = files[glb]
	data.append(0)
	files[glb] = data
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_has(_codes(made), LibraryPartial.E_HASH)


func test_an_extra_file_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	files["alienworld/assets/tree/Sneaky.glb"] = PackedByteArray([1, 2, 3])
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_false(made["ok"])
	assert_has(_codes(made), LibraryPartial.E_EXTRA)
	assert_false(_has_dir(_received_root().path_join("alienworld")))


func test_a_stray_file_outside_any_library_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	files["loose.json"] = PackedByteArray([123, 125])
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_has(_codes(made), LibraryPartial.E_EXTRA)


func test_path_traversal_is_refused() -> void:
	for evil in ["alienworld/../../outside.json", "alienworld/a/../b.json", "alienworld//x.json"]:
		var files := _bundle_files(_request(), _host_served())
		files[evil] = PackedByteArray([123, 125])
		_become_client()
		var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
		assert_false(made["ok"], evil)
		assert_false(FileAccess.file_exists(_root() + "/outside.json"))


func test_absolute_and_drive_paths_are_refused() -> void:
	for evil in ["alienworld/C:/x.json", "alienworld/back\\slash.json", "alienworld/con.json"]:
		var files := _bundle_files(_request(), _host_served())
		files[evil] = PackedByteArray([123, 125])
		_become_client()
		assert_false(
			LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())["ok"], evil
		)


func test_a_disallowed_extension_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	files["alienworld/payload.gd"] = "extends Node".to_utf8_buffer()
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_has(_codes(made), LibraryPartial.E_EXTENSION)


func test_a_library_claiming_core_or_an_official_id_is_never_accepted() -> void:
	var host := _host_served()
	var files := _bundle_files(_request(), host)
	var as_core := {}
	for path: String in files:
		as_core[path.replace("alienworld/", "core/")] = files[path]
	_become_client()
	var made := LibraryTransfer.verify_and_install(
		LibraryPartial.encode(as_core), _ctx({"library": "core"})
	)
	assert_has(_codes(made), LibraryPartial.E_RESERVED)
	assert_false(_has_dir(_received_root().path_join("core")))
	# An official non-core id too.
	var official := _ctx({"official_ids": ["core", "alienworld"]})
	var made_official := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), official)
	assert_has(_codes(made_official), LibraryPartial.E_RESERVED)
	# And a reserved grammar id (dev).
	var as_dev := {}
	for path: String in files:
		as_dev[path.replace("alienworld/", "dev/")] = files[path]
	var made_dev := LibraryTransfer.verify_and_install(
		LibraryPartial.encode(as_dev), _ctx({"library": "dev"})
	)
	assert_has(_codes(made_dev), LibraryPartial.E_RESERVED)


func test_an_id_that_differs_from_the_folder_or_the_request_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	# library.json names another id than its folder.
	var renamed := files.duplicate()
	var library: Dictionary = JSON.parse_string(
		files["alienworld/library.json"].get_string_from_utf8()
	)
	library["id"] = "impostor"
	renamed["alienworld/library.json"] = LibraryPartial.json_bytes(library)
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(renamed), _ctx())
	assert_has(_codes(made), LibraryPartial.E_ID)
	# The host sends a different library than the one asked for.
	var other := {}
	for path: String in files:
		other[path.replace("alienworld/", "otherlib/")] = files[path]
	var made_other := LibraryTransfer.verify_and_install(LibraryPartial.encode(other), _ctx())
	assert_has(_codes(made_other), LibraryPartial.E_ID)
	# A library nobody asked for beside the right one.
	var extra := files.duplicate()
	for path: String in files:
		extra[path.replace("alienworld/", "bonus/")] = files[path]
	var made_extra := LibraryTransfer.verify_and_install(LibraryPartial.encode(extra), _ctx())
	assert_false(made_extra["ok"])


func test_another_major_version_than_the_map_was_saved_with_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	var library: Dictionary = JSON.parse_string(
		files["alienworld/library.json"].get_string_from_utf8()
	)
	library["version"] = "9.0.0"
	files["alienworld/library.json"] = LibraryPartial.json_bytes(library)
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_has(_codes(made), LibraryPartial.E_VERSION)


func test_a_full_library_posing_as_a_partial_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	var library: Dictionary = JSON.parse_string(
		files["alienworld/library.json"].get_string_from_utf8()
	)
	library.erase("partial")
	files["alienworld/library.json"] = LibraryPartial.json_bytes(library)
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_has(_codes(made), LibraryPartial.E_PARTIAL)


func test_a_catalog_without_hashes_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	var catalog: Dictionary = JSON.parse_string(
		files["alienworld/assets/catalog.json"].get_string_from_utf8()
	)
	for entry: Dictionary in catalog["assets"]:
		entry.erase("sha256")
	files["alienworld/assets/catalog.json"] = LibraryPartial.json_bytes(catalog)
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_has(_codes(made), LibraryPartial.E_HASH)


func test_a_glb_that_is_not_a_glb_is_refused() -> void:
	var files := _bundle_files(_request(), _host_served())
	var glb := "alienworld/assets/tree/Crystal_Spire_v0.glb"
	var junk := PackedByteArray(
		[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]
	)
	files[glb] = junk
	var catalog: Dictionary = JSON.parse_string(
		files["alienworld/assets/catalog.json"].get_string_from_utf8()
	)
	catalog["assets"][0]["sha256"] = LibraryPartial.sha256_of(junk)
	catalog["assets"][0]["bytes"] = junk.size()
	files["alienworld/assets/catalog.json"] = LibraryPartial.json_bytes(catalog)
	_become_client()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_false(made["ok"])
	assert_has(_codes(made), LibraryPartial.E_INVALID)


func test_a_truncated_bundle_is_refused() -> void:
	var bytes := LibraryTransfer.build_bundle(_request(), _host_served())
	_become_client()
	for cut in [bytes.size() - 1, bytes.size() / 2, 12, 8]:
		var made := LibraryTransfer.verify_and_install(bytes.slice(0, cut), _ctx())
		assert_false(made["ok"], "cut at %d" % cut)
	var long := bytes.duplicate()
	long.append(7)
	assert_false(LibraryTransfer.verify_and_install(long, _ctx())["ok"], "trailing bytes")
	assert_false(_has_dir(_received_root().path_join("alienworld")))


func test_a_bundle_header_cannot_ask_for_memory_the_caps_do_not_allow() -> void:
	var head := PackedByteArray()
	head.append_array(LibraryPartial.MAGIC)
	head.append(LibraryPartial.BUNDLE_VERSION)
	head.resize(9)
	head.encode_u32(5, 5_000_000)
	assert_eq(LibraryPartial.decode(head)["code"], LibraryPartial.E_CAPS, "file count")
	# One file that claims 3 GiB.
	var big := PackedByteArray()
	big.append_array(LibraryPartial.MAGIC)
	big.append(LibraryPartial.BUNDLE_VERSION)
	big.resize(9)
	big.encode_u32(5, 1)
	var name_bytes := "a/library.json".to_utf8_buffer()
	var size_head := PackedByteArray()
	size_head.resize(2)
	size_head.encode_u16(0, name_bytes.size())
	big.append_array(size_head)
	big.append_array(name_bytes)
	var length := PackedByteArray()
	length.resize(4)
	length.encode_u32(0, 3_000_000_000)
	big.append_array(length)
	assert_eq(LibraryPartial.decode(big)["code"], LibraryPartial.E_CAPS, "file size")
	assert_false(LibraryPartial.header_ok(5, 2_000_000_000, 32768))
	assert_false(LibraryPartial.header_ok(10_000_000, 1000, 32768))
	assert_true(LibraryPartial.header_ok(3, 70000, 32768))


func test_a_bundle_over_the_total_cap_is_refused_while_decoding() -> void:
	var files := {}
	for i in 5:
		var data := PackedByteArray()
		data.resize(60 * 1024 * 1024)
		files["a/f%d.glb" % i] = data
	var decoded := LibraryPartial.decode(LibraryPartial.encode(files))
	assert_false(decoded["ok"])
	assert_eq(decoded["code"], LibraryPartial.E_CAPS)


func test_too_many_files_or_libraries_are_refused() -> void:
	var files := {}
	for i in LibraryPartial.MAX_LIBRARIES + 1:
		files["lib%d/library.json" % i] = PackedByteArray([123, 125])
	_become_client()
	assert_false(LibraryTransfer.verify_and_install(files, _ctx())["ok"])


func test_garbage_is_not_a_bundle() -> void:
	_become_client()
	for bytes in [
		PackedByteArray(), PackedByteArray([1, 2, 3]), "TTLQ____________".to_utf8_buffer()
	]:
		var made := LibraryTransfer.verify_and_install(bytes, _ctx())
		assert_false(made["ok"])
		assert_gt((made["errors"] as Array).size(), 0)


# ---- the transient cache ----


func _fake_received(id: String, bytes: int, last_used: int) -> void:
	var root := _received_root()
	DirAccess.make_dir_recursive_absolute(root.path_join(id))
	World.write_text(root.path_join(id + "/library.json"), "{}")
	World.write_json(
		root.path_join(id + LibraryReceivedStore.MARKER_SUFFIX),
		{
			"id": id,
			"version": "1.0.0",
			"bytes": bytes,
			"received_at": last_used,
			"last_used": last_used
		}
	)


func test_the_cache_evicts_the_least_recently_used_first() -> void:
	_fake_received("aaa", 300, 10)
	_fake_received("bbb", 300, 20)
	_fake_received("ccc", 300, 30)
	var removed := LibraryReceivedStore.evict_to_fit(700, [], 1000)
	assert_eq(removed, ["aaa", "bbb"])
	assert_false(_has_dir(_received_root().path_join("aaa")))
	assert_true(_has_dir(_received_root().path_join("ccc")))
	assert_eq(
		LibraryReceivedStore.inventory().map(func(i: Dictionary) -> String: return i["id"]), ["ccc"]
	)


func test_touch_makes_a_library_recent_and_keep_protects_the_incoming() -> void:
	_fake_received("aaa", 300, 10)
	_fake_received("bbb", 300, 20)
	LibraryReceivedStore.touch("aaa", 99)
	assert_eq(LibraryReceivedStore.evict_to_fit(500, [], 1000), ["bbb"])
	_fake_received("ddd", 300, 1)
	assert_eq(LibraryReceivedStore.evict_to_fit(900, ["ddd"], 1000), ["aaa"], "the kept id stays")


func test_a_new_install_evicts_older_received_libraries_over_the_cap() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	_fake_received("oldlib", 600_000_000, 1)
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx({"cap": 600_000_000})
	)
	assert_true(made["ok"], str(made["errors"]))
	assert_false(_has_dir(_received_root().path_join("oldlib")))
	assert_true(_has_dir(_received_root().path_join("alienworld")))


func test_the_session_sweep_removes_what_this_session_received() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	LibraryTransfer.verify_and_install(LibraryTransfer.build_bundle(request, host), _ctx())
	_fake_received("leftover", 10, 5)
	assert_eq(LibraryReceivedStore.sweep_session(), ["alienworld"])
	assert_false(_has_dir(_received_root().path_join("alienworld")))
	assert_true(_has_dir(_received_root().path_join("leftover")), "not this session's")
	assert_eq(LibraryReceivedStore.sweep_leftovers(), ["leftover"])
	assert_eq(LibraryReceivedStore.inventory(), [])


func test_remove_refuses_an_id_that_is_not_a_library_id() -> void:
	World.write_text(_root() + "/keepme.txt", "x")
	assert_false(LibraryReceivedStore.remove("../keepme"))
	assert_false(LibraryReceivedStore.remove(".."))
	assert_true(FileAccess.file_exists(_root() + "/keepme.txt"))


func test_keep_promotes_a_received_library_into_the_user_libraries() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	LibraryTransfer.verify_and_install(LibraryTransfer.build_bundle(request, host), _ctx())
	var kept := LibraryReceivedStore.promote("alienworld")
	assert_true(kept["ok"], str(kept))
	assert_true(_has_dir(_client_user.path_join("alienworld")))
	assert_false(_has_dir(_received_root().path_join("alienworld")))
	assert_eq(LibraryReceivedStore.sweep_session(), [], "nothing left to sweep")
	LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["source"], "user")
	assert_false(info["partial"].is_empty(), "still marked partial in the manager")
	assert_false(LibraryReceivedStore.promote("alienworld")["ok"], "already installed")


func test_promote_goes_through_the_importer_when_there_is_one() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	LibraryTransfer.verify_and_install(LibraryTransfer.build_bundle(request, host), _ctx())
	var seen: Array = []
	var importer := func(folder: String) -> int:
		seen.append(folder)
		return OK
	assert_true(LibraryReceivedStore.promote("alienworld", importer)["ok"])
	assert_eq(seen.size(), 1)
	assert_true(String(seen[0]).ends_with("/alienworld"))


# ---- the registry's received source ----


func test_an_installed_library_beats_a_received_one_of_the_same_version() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	# The client installed alienworld 0.3.1 itself (all of it), then a host sends the partial.
	DirAccess.make_dir_recursive_absolute(_client_user)
	World.write_alien(_client_user.path_join("alienworld"))
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx()
	)
	assert_true(made["ok"])
	LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["source"], "user", "the player's own copy wins a tie")


func test_a_newer_received_partial_supersedes_an_older_installed_copy_for_the_session() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	World.write_alien(_client_user.path_join("alienworld"), "0.2.0")
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx()
	)
	assert_true(made["ok"])
	LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["source"], "received")
	assert_eq(info["version"], "0.3.1")
	assert_true(_assets().has(Tw.SPIRE))
	# When the session's cache goes, the installed 0.2.0 serves again.
	LibraryReceivedStore.sweep_session()
	LibraryRegistry.apply(_paths["base"])
	assert_eq(LibraryRegistry.info("alienworld", _paths["base"])["version"], "0.2.0")


func test_the_received_folder_is_a_dot_folder_the_user_scan_skips() -> void:
	assert_true(LibraryRegistry.received_root().get_file().begins_with("."))
	assert_eq(LibraryRegistry.received_root().get_base_dir(), LibraryRegistry.user_root)
