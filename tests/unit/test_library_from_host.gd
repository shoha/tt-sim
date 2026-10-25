extends "res://tests/unit/library_transfer_case.gd"

## The cache of collections downloaded from a host (LibraryFromHost; docs/systems/library.md "The
## cache of downloaded collections"): the inventory, the least-recently-used eviction under a size
## cap that spares what an open map uses, last-used stamps, the clear that removes only what a
## host sent (and refuses a junction inside), the player's own copy being out of reach, the
## adoption of a `.received` folder the earlier session-only cache left, and the import step not
## being able to pass for a download. Install, delta and consent are in
## test_library_transfer_install.gd, test_library_transfer_flow.gd and the consent test.


func _root() -> String:
	return "user://test_library_from_host"


func before_each() -> void:
	super.before_each()
	LibraryRegistry.user_root = _client_user
	LibraryFromHost.reported_leftovers.clear()


## A from-host collection that is not a valid library: only what the cache looks at (a record, the
## ownership marker, `payload` bytes of files).
func _fake(id: String, payload: int, last_used: int, host: String = "Ann") -> String:
	var folder := _client_user.path_join(id)
	World.write_text(folder + "/library.json", "{}")
	var blob := PackedByteArray()
	blob.resize(payload)
	World.write_bytes(folder + "/assets/blob.glb", blob)
	assert_true(SafeDelete.mark(folder, "test", _client_user))
	assert_true(
		(
			LibraryFromHost
			. write_record(
				folder,
				{
					"format": 1,
					"id": id,
					"host": host,
					"version": "1.0.0",
					"source_hash": "h",
					"received_at": last_used,
					"last_used": last_used,
					"assets": [],
					"partial": true,
					"assets_only": false,
					"auto_delta": true,
				}
			)
		)
	)
	return folder


func _ids(items: Array) -> Array:
	return items.map(func(i: Dictionary) -> String: return i["id"])


## A directory junction (no admin rights needed) from `link` to `target`.
func _junction(link: String, target: String) -> bool:
	if OS.get_name() != "Windows":
		return false
	DirAccess.make_dir_recursive_absolute(link.get_base_dir())
	var from := ProjectSettings.globalize_path(link).replace("/", "\\")
	var to := ProjectSettings.globalize_path(target).replace("/", "\\")
	var output: Array = []
	var code := OS.execute("cmd", ["/c", "mklink", "/J", from, to], output)
	return code == OK and DirAccess.dir_exists_absolute(link)


# ---- the inventory ----


func test_the_inventory_lists_only_what_a_host_sent_oldest_use_first() -> void:
	_fake("newer", 100, 30)
	_fake("older", 200, 10)
	World.write_alien(_client_user.path_join("mine"))
	World.write_text(_client_user.path_join("stranger") + "/library.json", "{}")
	var items := LibraryFromHost.inventory()
	assert_eq(_ids(items), ["older", "newer"])
	assert_gt(int(items[0]["bytes"]), 200, "the size on disk counts every file")
	assert_eq(items[0]["host"], "Ann")
	assert_eq(LibraryFromHost.total_bytes(), int(items[0]["bytes"]) + int(items[1]["bytes"]))


func test_a_record_that_is_not_a_record_makes_an_ordinary_library() -> void:
	var folder := _fake("odd", 10, 1)
	assert_false(LibraryFromHost.read_record(folder).is_empty())
	World.write_text(folder + "/" + LibraryFromHost.RECORD_FILE, "not json")
	assert_true(LibraryFromHost.read_record(folder).is_empty())
	World.write_json(folder + "/" + LibraryFromHost.RECORD_FILE, {"format": 1, "id": "other"})
	assert_true(LibraryFromHost.read_record(folder).is_empty(), "a record names its own folder")
	World.write_json(folder + "/" + LibraryFromHost.RECORD_FILE, {"format": 9, "id": "odd"})
	assert_true(LibraryFromHost.read_record(folder).is_empty())
	assert_false(LibraryFromHost.is_from_host("odd"))


func test_the_import_step_cannot_pass_for_a_download() -> void:
	var source := _root() + "/source/alienworld"
	World.write_alien(source)
	World.write_json(source + "/" + LibraryFromHost.RECORD_FILE, {"format": 1, "id": "alienworld"})
	var plan := LibraryImporter.inspect(source)
	assert_true(plan["ok"], str(plan["errors"]))
	var staged := LibraryImporter.stage(plan)
	assert_true(staged["ok"], str(staged))
	assert_false(
		FileAccess.file_exists(String(staged["folder"]) + "/" + LibraryFromHost.RECORD_FILE),
		"the record is left out of an import"
	)
	assert_true(FileAccess.file_exists(String(staged["folder"]) + "/library.json"))
	LibraryImporter.discard(String(staged["folder"]))


# ---- the size cap and the eviction ----


func test_over_the_cap_the_least_recently_used_go_first() -> void:
	_fake("aaa", 1000, 10)
	_fake("bbb", 1000, 20)
	_fake("ccc", 1000, 30)
	var one := int(LibraryFromHost.inventory()[0]["bytes"])
	var removed := LibraryFromHost.evict_to_fit(one, [], one * 2)
	assert_eq(removed, ["aaa", "bbb"], "room for one more: the two oldest go")
	assert_eq(_ids(LibraryFromHost.inventory()), ["ccc"])
	assert_false(_has_dir(_installed_path("aaa")))


func test_what_the_install_keeps_and_what_an_open_map_uses_is_not_evicted() -> void:
	_fake("aaa", 1000, 10)
	_fake("bbb", 1000, 20)
	_fake("ccc", 1000, 30)
	LibraryFromHost.open_ids = {"aaa": true}
	var removed := LibraryFromHost.evict_to_fit(0, ["bbb"], 0)
	assert_eq(removed, ["ccc"], "the open map's and the incoming one's stay, even over the cap")
	assert_eq(_ids(LibraryFromHost.inventory()), ["aaa", "bbb"])


func test_a_new_download_over_the_cap_evicts_the_oldest_unused_one() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	PaletteLibrary.get_palette()
	_fake("oldlib", 50_000, 1)
	_fake("spared", 50_000, 2)
	LibraryFromHost.open_ids = {"spared": true}
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx({"cap": 60_000})
	)
	assert_true(made["ok"], str(made["errors"]))
	assert_eq(made["evicted"], ["oldlib"])
	assert_false(_has_dir(_installed_path("oldlib")))
	assert_true(_has_dir(_installed_path("spared")), "an open map uses it")
	assert_true(_has_dir(_installed_path("alienworld")))


func test_the_cap_comes_from_settings_and_defaults_to_one_gigabyte() -> void:
	assert_eq(LibraryFromHost.cap_bytes(), 1024 * 1024 * 1024)
	assert_true(LibraryFromHost.set_cap_mb(256))
	assert_eq(LibraryFromHost.cap_bytes(), 256 * 1024 * 1024)
	assert_true(LibraryFromHost.set_cap_mb(0))
	assert_eq(LibraryFromHost.cap_bytes(), LibraryFromHost.MIN_CAP_MB * 1024 * 1024)
	# Other settings in the file are kept.
	LibraryRegistry.set_enabled("alienworld", false)
	assert_true(LibraryFromHost.set_cap_mb(512))
	assert_eq(LibraryRegistry.disabled_ids(), PackedStringArray(["alienworld"]))


# ---- last used ----


func test_opening_a_map_stamps_the_collections_it_uses() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	LibraryTransfer.verify_and_install(LibraryTransfer.build_bundle(request, host), _ctx())
	LibraryFromHost.touch("alienworld", 5)
	assert_eq(LibraryFromHost.record_of("alienworld")["last_used"], 5)
	LibraryRegistry.apply(_paths["base"])
	var out := await MapLibraryGate.run(Tw.map_using_spire(), Callable(), _paths["base"])
	assert_true(out["proceed"])
	assert_gt(int(LibraryFromHost.record_of("alienworld")["last_used"]), 5, "stamped by the gate")
	assert_true(LibraryFromHost.open_ids.has("alienworld"), "and protected from eviction")


func test_touch_ignores_what_is_not_from_a_host() -> void:
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryFromHost.touch("alienworld", 5)
	assert_true(LibraryFromHost.record_of("alienworld").is_empty())
	LibraryFromHost.touch("../nope", 5)
	LibraryFromHost.touch("", 5)


# ---- clearing ----


func test_clear_removes_only_what_a_host_sent() -> void:
	_fake("hosted_one", 100, 1)
	_fake("hosted_two", 100, 2)
	World.write_alien(_client_user.path_join("alienworld"))
	World.write_text(_client_user.path_join("stranger") + "/library.json", "{}")
	var core_before := FileAccess.get_file_as_string(_paths["core"] + "/library.json")
	var report := LibraryFromHost.clear_all()
	assert_eq(report["removed"], ["hosted_one", "hosted_two"])
	assert_eq(report["failed"], [])
	assert_gt(int(report["bytes"]), 200)
	assert_false(_has_dir(_installed_path("hosted_one")))
	assert_true(_has_dir(_installed_path("alienworld")), "the player's own collection stays")
	assert_true(FileAccess.file_exists(_installed_path("alienworld") + "/library.json"))
	assert_true(_has_dir(_installed_path("stranger")), "a folder nobody recorded stays")
	assert_eq(FileAccess.get_file_as_string(_paths["core"] + "/library.json"), core_before)
	assert_eq(LibraryFromHost.inventory(), [])


func test_remove_refuses_a_collection_the_player_installed() -> void:
	World.write_alien(_client_user.path_join("alienworld"))
	var refused := LibraryFromHost.remove("alienworld")
	assert_false(refused["ok"])
	assert_true(_has_dir(_installed_path("alienworld")))
	assert_false(LibraryFromHost.remove("core")["ok"])
	assert_false(LibraryFromHost.remove("../outside")["ok"])


func test_a_junction_inside_a_downloaded_collection_stops_its_removal() -> void:
	var folder := _fake("hosted_one", 100, 1)
	var canary := _root() + "/canary"
	World.write_text(canary + "/precious.txt", "keep")
	if not _junction(folder + "/assets/link", canary):
		pending("no directory junction on this system")
		return
	_fake("hosted_two", 100, 2)
	var report := LibraryFromHost.clear_all()
	assert_eq(report["failed"], ["hosted_one"], "the link stops that one")
	assert_eq(report["removed"], ["hosted_two"], "the rest is still cleared")
	assert_true(FileAccess.file_exists(canary + "/precious.txt"), "the link target is untouched")
	assert_true(_has_dir(folder), "and so is the collection with the link in it")


func test_a_downloaded_collection_whose_marker_is_gone_is_not_deleted() -> void:
	var folder := _fake("hosted_one", 100, 1)
	DirAccess.remove_absolute(folder + "/" + SafeDelete.MARKER)
	var report := LibraryFromHost.clear_all()
	assert_eq(report["failed"], ["hosted_one"])
	assert_true(FileAccess.file_exists(folder + "/library.json"), "SafeDelete wants its marker")


# ---- the earlier session-only cache ----


## Lays the spire's partial under `.received/alienworld` as the earlier version did, with the
## `<id>.received.json` record beside it.
func _leftover(with_record: bool = true) -> String:
	var request := _request()
	var host := _host_served()
	var files := _bundle_files(request, host)
	_become_client()
	var legacy := _client_user.path_join(".received")
	for path: String in files:
		World.write_bytes(legacy.path_join(path), files[path])
	if with_record:
		World.write_json(
			legacy.path_join("alienworld.received.json"),
			{
				"id": "alienworld",
				"version": "0.3.1",
				"bytes": 10,
				"received_at": 42,
				"last_used": 43
			}
		)
	return legacy


func test_a_leftover_received_folder_is_adopted_once_as_a_from_host_collection() -> void:
	var legacy := _leftover()
	var report := LibraryFromHost.migrate_received()
	assert_eq(report["adopted"], ["alienworld"])
	assert_eq(report["left"], [])
	assert_true(_has_dir(_installed_path("alienworld")), "now in the normal folder")
	var record := LibraryFromHost.record_of("alienworld")
	assert_eq(record["host"], "an earlier session")
	assert_eq(record["received_at"], 42)
	assert_true(record["partial"])
	assert_false(_has_dir(legacy.path_join("alienworld")), "the old folder is gone")
	assert_false(FileAccess.file_exists(legacy.path_join("alienworld.received.json")))
	LibraryRegistry.apply(_paths["base"])
	assert_true(_assets().has(Tw.SPIRE), "and served like any collection")
	assert_eq(LibraryFromHost.migrate_received()["adopted"], [], "once")


func test_startup_adopts_the_leftover_and_serves_it() -> void:
	_leftover()
	var started := LibraryFromHost.startup()
	assert_eq(started["adopted"], ["alienworld"])
	LibraryRegistry.apply(_paths["base"])
	assert_true(_assets().has(Tw.SPIRE))


func test_a_leftover_that_fails_the_checks_is_reported_and_left() -> void:
	var legacy := _leftover()
	var glb := legacy.path_join("alienworld/assets/tree/Crystal_Spire_v0.glb")
	var data := FileAccess.get_file_as_bytes(glb)
	data[data.size() - 1] = (data[data.size() - 1] + 1) % 256
	World.write_bytes(glb, data)
	var report := LibraryFromHost.migrate_received()
	assert_eq(report["adopted"], [])
	assert_eq(report["left"].size(), 1)
	assert_eq(report["left"][0]["id"], "alienworld")
	assert_true(_has_dir(legacy.path_join("alienworld")), "nothing is deleted")
	assert_false(_has_dir(_installed_path("alienworld")))


func test_a_leftover_whose_id_is_already_installed_is_left_alone() -> void:
	var legacy := _leftover()
	World.write_alien(_client_user.path_join("alienworld"))
	var before := FileAccess.get_file_as_string(_installed_path("alienworld") + "/library.json")
	var report := LibraryFromHost.migrate_received()
	assert_eq(report["adopted"], [])
	assert_eq(report["left"][0]["id"], "alienworld")
	assert_true(_has_dir(legacy.path_join("alienworld")))
	assert_eq(
		FileAccess.get_file_as_string(_installed_path("alienworld") + "/library.json"), before
	)
	assert_true(
		LibraryFromHost.record_of("alienworld").is_empty(), "the player's copy stays theirs"
	)


func test_a_stale_leftover_is_reported_once_and_remembered_across_runs() -> void:
	var legacy := _leftover()
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryRegistry.apply(_paths["base"])
	var first := LibraryFromHost.migrate_received()
	assert_eq(first["left"].size(), 1, "reported the first time")
	assert_eq(first["stale"], ["alienworld"])
	assert_true(FileAccess.file_exists(legacy.path_join("alienworld.reported")))
	var second := LibraryFromHost.migrate_received()
	assert_eq(second["left"], [], "not reported again in the session")
	assert_eq(second["stale"], ["alienworld"], "but still known to the manager")
	LibraryFromHost.reported_leftovers.clear()  # a new start: only the marker file remains
	var third := LibraryFromHost.migrate_received()
	assert_eq(third["left"], [], "nor on the next start")
	assert_eq(third["stale"], ["alienworld"])
	assert_true(_has_dir(legacy.path_join("alienworld")), "nothing was deleted by reporting")


func test_a_stale_leftover_is_removed_through_safe_delete_and_only_when_stale() -> void:
	var legacy := _leftover()
	assert_true(LibraryFromHost.stale_received().is_empty(), "not installed: not stale")
	assert_false(LibraryFromHost.remove_stale_received("alienworld")["ok"], "refused")
	assert_true(_has_dir(legacy.path_join("alienworld")))
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryRegistry.apply(_paths["base"])
	LibraryFromHost.migrate_received()
	assert_eq(LibraryFromHost.stale_received(), ["alienworld"])
	var result := LibraryFromHost.remove_stale_received("alienworld")
	assert_true(result["ok"], str(result))
	assert_false(_has_dir(legacy.path_join("alienworld")))
	assert_false(FileAccess.file_exists(legacy.path_join("alienworld.received.json")))
	assert_false(FileAccess.file_exists(legacy.path_join("alienworld.reported")))
	assert_true(_has_dir(_installed_path("alienworld")), "the installed collection is untouched")
	assert_true(LibraryFromHost.stale_received().is_empty())
	assert_false(LibraryFromHost.remove_stale_received("..")["ok"], "an unsafe id is refused")


func test_the_manager_row_offers_removal_and_hides_when_nothing_is_left() -> void:
	var legacy := _leftover()
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryRegistry.apply(_paths["base"])
	var section := LibraryStaleSection.new()
	add_child_autofree(section)
	assert_true(section.visible)
	assert_eq(section.summary_label.text, LibraryStaleSection.summary_text(1))
	assert_string_contains(
		section.summary_label.text, "1 old copy of collections you already have takes"
	)
	assert_string_contains(LibraryStaleSection.remove_message(2), "2 old copies")
	assert_true(_has_dir(legacy.path_join("alienworld")), "showing the row deletes nothing")
	var report := section.remove_now()
	assert_eq(report["removed"], ["alienworld"])
	assert_false(_has_dir(legacy.path_join("alienworld")))
	assert_false(section.visible)
