extends "res://tests/unit/library_transfer_case.gd"

## Multiplayer library transfer, the client's side of a bundle (docs/systems/library.md
## "Multiplayer" and "The cache of downloaded collections"): verify_and_install keeps a good
## partial as an ordinary user library marked "from host", merges a later delta into it, replaces
## it when the host's copy changed, never writes over the player's own copy, and refuses every
## hostile bundle with a structured error, writing nothing (wrong sha256 or size, an extra file,
## traversal, a disallowed extension, a reserved or official id, an id or version mismatch, a full
## library posing as a partial, a bad GLB, truncation, caps).


func _root() -> String:
	return "user://test_library_transfer_install"


## Installs the spire's bundle on the client as the first download (host label "Ann").
func _first_download(host: Dictionary) -> Dictionary:
	var request := Tw.request_for(Tw.map_using_spire(), _view(["core"]), _assets())
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx({"host": "Ann"})
	)
	assert_true(made["ok"], str(made["errors"]))
	LibraryRegistry.apply(_paths["base"])
	return made


## The map that also uses the shard, and the plan the client makes for it now.
func _delta_plan() -> Dictionary:
	var doc := Tw.map_using_spire()
	doc.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	return LibraryTransfer.plan(doc, _view(["core", "alienworld"]), _assets())


func _folder_state(id: String) -> Dictionary:
	return LibraryFromHost.read_folder_files(id)


# ---- installing on the client ----


func test_a_good_bundle_is_kept_as_a_user_library_marked_from_host() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	assert_false(_assets().has(Tw.SPIRE))
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx({"host": "Ann"})
	)
	assert_true(made["ok"], str(made["errors"]))
	assert_eq(made["libraries"], ["alienworld"])
	assert_true(_has_dir(_installed_path("alienworld")), "an ordinary user library folder")
	assert_true(SafeDelete.is_owned(_installed_path("alienworld")), "SafeDelete may remove it")
	var record := LibraryFromHost.record_of("alienworld")
	assert_eq(record["host"], "Ann")
	assert_eq(record["version"], "0.3.1")
	assert_eq(record["source_hash"], host["alienworld"]["hash"], "the host's FULL library hash")
	assert_eq(record["assets"], ["Crystal_Spire_v0"])
	assert_eq(record["received_at"], 1000)
	assert_true(record["partial"])
	LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["status"], "ok")
	assert_true(info["received"], "marked from host")
	assert_eq(info["from_host"]["host"], "Ann")
	assert_eq(info["source"], "user", "listed like any other collection")
	assert_false(info["official"])
	assert_false(info["partial"].is_empty(), "the manager can badge it partial")
	assert_eq(info["version"], "0.3.1")
	assert_true(_assets().has(Tw.SPIRE), "the used asset is served")
	assert_false(_assets().has(Tw.SHARD), "the unused one is not in the partial")
	assert_not_null(AssetStore.mesh_for(Tw.SPIRE, _paths["base"]), "the GLB loads, hash checked")
	assert_eq(
		LibraryRegistry.record_of("alienworld")["hash"],
		host["alienworld"]["hash"],
		"a map saved here records the full library's hash"
	)


func test_the_markers_are_not_part_of_the_library() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var listing := LibraryRegistry.read_sources(_installed_path("alienworld"))
	assert_false(LibraryFromHost.RECORD_FILE in listing["files"])
	assert_false(SafeDelete.MARKER in listing["files"])
	assert_eq(
		LibraryRegistry.info("alienworld", _paths["base"])["hash"],
		host["alienworld"]["hash"],
		"the record does not change the identity"
	)


func test_a_downloaded_collection_switches_off_and_on_like_any_other() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	assert_true(LibraryRegistry.set_enabled("alienworld", false))
	LibraryRegistry.apply(_paths["base"])
	assert_eq(LibraryRegistry.served().keys(), ["core"], "off: not served")
	PaletteLibrary.clear_cache()
	assert_false(_assets().has(Tw.SPIRE), "off: not in the palette")
	assert_eq(LibraryRegistry.info("alienworld", _paths["base"])["enabled"], false)
	assert_true(LibraryRegistry.set_enabled("alienworld", true))
	LibraryRegistry.apply(_paths["base"])
	assert_true(_assets().has(Tw.SPIRE), "on again")


func test_a_downloaded_collection_is_served_again_after_a_restart() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var before := LibraryRegistry.info("alienworld", _paths["base"])
	# A new session: every in-memory state is gone, only the disk remains.
	LibraryFromHost.open_ids = {}
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.official_root = _paths["official"]
	var started := LibraryFromHost.startup()
	assert_eq(started["swept"], 0)
	LibraryRegistry.apply(_paths["base"])
	assert_true(_assets().has(Tw.SPIRE), "still served")
	var after := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(after["hash"], before["hash"])
	assert_true(after["received"])
	assert_eq(LibraryFromHost.inventory().size(), 1)


func test_removing_a_downloaded_collection_is_the_ordinary_remove() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	assert_true(LibraryInstall.remove("alienworld")["ok"])
	assert_false(_has_dir(_installed_path("alienworld")))
	LibraryRegistry.apply(_paths["base"])
	assert_true(LibraryRegistry.info("alienworld", _paths["base"]).is_empty())


# ---- the delta ----


func test_a_second_request_asks_only_for_what_is_missing() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var plan := _delta_plan()
	assert_eq(plan["requests"].size(), 1)
	var request: Dictionary = plan["requests"][0]
	assert_eq(request["reason"], "more")
	assert_eq(request["assets"], [Tw.SHARD], "the shard only, not the spire again")
	assert_eq(request["biomes"], [], "the biome is already kept")
	assert_eq(request["surfaces"], [], "so is the surface")
	assert_has(request["full"]["assets"], Tw.SPIRE, "the whole request stays for a changed host")
	assert_has(request["full"]["assets"], Tw.SHARD)
	var delta := _bundle_files(request, host)
	assert_false(delta.has("alienworld/assets/tree/Crystal_Spire_v0.glb"), "not sent again")
	assert_true(delta.has("alienworld/assets/rock/Crystal_Shard_v0.glb"))
	assert_false(
		delta.keys().any(func(p: String) -> bool: return p.begins_with("alienworld/surfaces"))
	)
	var whole: int = LibraryTransfer.quote(request["full"], host)["bytes"]
	assert_lt(int(LibraryTransfer.quote(request, host)["bytes"]), whole, "the delta is smaller")


func test_a_delta_is_merged_into_the_kept_copy() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var spire_file: PackedByteArray = _folder_state("alienworld")["assets/tree/Crystal_Spire_v0.glb"]
	var request: Dictionary = _delta_plan()["requests"][0]
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx({"host": "Ann", "now": 2000})
	)
	assert_true(made["ok"], str(made["errors"]))
	assert_eq(made["merged"], ["alienworld"])
	LibraryRegistry.apply(_paths["base"])
	assert_true(_assets().has(Tw.SPIRE) and _assets().has(Tw.SHARD), "both are served now")
	assert_not_null(AssetStore.mesh_for(Tw.SPIRE, _paths["base"]))
	assert_not_null(AssetStore.mesh_for(Tw.SHARD, _paths["base"]))
	var files := _folder_state("alienworld")
	assert_eq(files["assets/tree/Crystal_Spire_v0.glb"], spire_file, "the kept bytes are untouched")
	var catalog: Dictionary = JSON.parse_string(files["assets/catalog.json"].get_string_from_utf8())
	var ids: Array = (catalog["assets"] as Array).map(func(e: Dictionary) -> String: return e["id"])
	assert_eq(ids, ["Crystal_Spire_v0", "Crystal_Shard_v0"], "the catalog is the union")
	for entry: Dictionary in catalog["assets"]:
		assert_eq(LibraryPartial.sha256_of(files[entry["file"]]), entry["sha256"], "hashes agree")
		assert_eq(int(entry["bytes"]), (files[entry["file"]] as PackedByteArray).size())
	var biome: Dictionary = JSON.parse_string(
		files["biomes/crystal_basin.json"].get_string_from_utf8()
	)
	var keys: Array = (biome["rules"] as Array).map(func(r: Dictionary) -> String: return r["key"])
	assert_eq(keys, ["trees", "stones"], "the biome-def is the union of the rules")
	var library: Dictionary = JSON.parse_string(files["library.json"].get_string_from_utf8())
	assert_eq(library["partial"]["assets"], ["Crystal_Shard_v0", "Crystal_Spire_v0"])
	assert_eq(library["partial"]["source_hash"], host["alienworld"]["hash"])
	var record := LibraryFromHost.record_of("alienworld")
	assert_eq(record["assets"], ["Crystal_Shard_v0", "Crystal_Spire_v0"])
	assert_eq(record["received_at"], 1000, "first received then")
	assert_eq(record["last_used"], 2000)
	assert_eq(record["host"], "Ann")
	var again := (
		LibraryPartial
		. inspect(
			files,
			{
				"id": "alienworld",
				"official_ids": ["core"],
				"surfaces": PaletteLibrary.get_palette(_paths["base"])["surfaces"],
				"dependencies": {},
			}
		)
	)
	assert_true(again["ok"], str(again["errors"]))


func test_a_tampered_delta_is_refused_and_the_kept_copy_is_untouched() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var before := _folder_state("alienworld")
	var record_before := LibraryFromHost.record_of("alienworld")
	var request: Dictionary = _delta_plan()["requests"][0]
	var files := _bundle_files(request, host)
	var glb := "alienworld/assets/rock/Crystal_Shard_v0.glb"
	var data: PackedByteArray = files[glb]
	data[data.size() - 1] = (data[data.size() - 1] + 1) % 256
	files[glb] = data
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(files), _ctx())
	assert_false(made["ok"])
	assert_has(_codes(made), LibraryPartial.E_HASH)
	assert_eq(_folder_state("alienworld"), before, "not one byte of the kept copy changed")
	assert_eq(LibraryFromHost.record_of("alienworld"), record_before)
	assert_false(_has_dir(_installed_path(LibraryFromHost.STAGING_PREFIX + "alienworld")))
	LibraryRegistry.apply(_paths["base"])
	assert_true(_assets().has(Tw.SPIRE) and not _assets().has(Tw.SHARD))


func test_a_delta_that_contradicts_the_kept_copy_is_refused_and_leaves_it() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var before := _folder_state("alienworld")
	var request: Dictionary = _delta_plan()["requests"][0]
	var files := _bundle_files(request, host)
	# The shard arrives, but the same asset id is already kept with other bytes: a delta that
	# disagrees with what is on disk is an error, not a silent overwrite.
	var clash := files.duplicate()
	var kept_catalog: Dictionary = JSON.parse_string(
		before["assets/catalog.json"].get_string_from_utf8()
	)
	var delta_catalog: Dictionary = JSON.parse_string(
		files["alienworld/assets/catalog.json"].get_string_from_utf8()
	)
	delta_catalog["assets"].append(kept_catalog["assets"][0].duplicate())
	delta_catalog["assets"].back()["sha256"] = "f".repeat(64)
	clash["alienworld/assets/catalog.json"] = LibraryPartial.json_bytes(delta_catalog)
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(clash), _ctx())
	assert_false(made["ok"])
	assert_eq(_folder_state("alienworld"), before)


func test_a_changed_host_copy_replaces_the_kept_one() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var request: Dictionary = _delta_plan()["requests"][0]
	var files := _bundle_files(request["full"], host)
	var library: Dictionary = JSON.parse_string(
		files["alienworld/library.json"].get_string_from_utf8()
	)
	library["partial"]["source_hash"] = "changed1"
	files["alienworld/library.json"] = LibraryPartial.json_bytes(library)
	var made := LibraryTransfer.verify_and_install(
		LibraryPartial.encode(files), _ctx({"now": 3000})
	)
	assert_true(made["ok"], str(made["errors"]))
	assert_eq(made["merged"], [], "another source hash is not a delta")
	var record := LibraryFromHost.record_of("alienworld")
	assert_eq(record["source_hash"], "changed1")
	assert_eq(record["received_at"], 3000, "a new copy")
	LibraryRegistry.apply(_paths["base"])
	assert_true(_assets().has(Tw.SPIRE) and _assets().has(Tw.SHARD), "all the full request")
	assert_false(_has_dir(_installed_path(LibraryFromHost.OLD_PREFIX + "alienworld")))


func test_the_merge_itself_refuses_another_version_or_source() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var request: Dictionary = _delta_plan()["requests"][0]
	var delta := {}
	var decoded: Dictionary = _bundle_files(request, host)
	for path: String in decoded:
		delta[path.trim_prefix("alienworld/")] = decoded[path]
	var current := _folder_state("alienworld")
	assert_true(LibraryPartialMerge.merge(current, delta)["ok"])
	var library: Dictionary = JSON.parse_string(delta["library.json"].get_string_from_utf8())
	library["version"] = "0.3.2"
	var other_version := delta.duplicate()
	other_version["library.json"] = LibraryPartial.json_bytes(library)
	assert_eq(LibraryPartialMerge.merge(current, other_version)["code"], "changed")
	library["version"] = "0.3.1"
	library["partial"]["source_hash"] = "zzz"
	var other_source := delta.duplicate()
	other_source["library.json"] = LibraryPartial.json_bytes(library)
	assert_eq(LibraryPartialMerge.merge(current, other_source)["code"], "changed")
	var same_path := delta.duplicate()
	same_path["assets/tree/Crystal_Spire_v0.glb"] = PackedByteArray([1, 2, 3])
	assert_eq(LibraryPartialMerge.merge(current, same_path)["code"], "merge")


# ---- the player's own copy ----


func test_the_players_own_full_copy_is_never_replaced_by_a_hosts() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryRegistry.apply(_paths["base"])
	var before := _folder_state("alienworld")
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx()
	)
	assert_false(made["ok"])
	assert_has(_codes(made), "own_copy")
	assert_eq(_folder_state("alienworld"), before, "not one byte of the player's copy changed")
	assert_true(LibraryFromHost.record_of("alienworld").is_empty(), "still no from-host record")
	assert_eq(LibraryFromHost.decide("alienworld", {}, "0.3.1")["mode"], "own")


func test_a_full_copy_of_the_same_version_needs_nothing_from_the_host() -> void:
	var host := _host_served()
	_become_client()
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryRegistry.apply(_paths["base"])
	var plan := LibraryTransfer.plan(Tw.map_using_spire(), _view(["core", "alienworld"]), _assets())
	assert_eq(plan["requests"], [])
	assert_eq(plan["satisfied"], ["alienworld"])
	assert_false(host.is_empty())


func test_an_own_copy_that_lacks_items_or_is_older_is_blocked_not_replaced() -> void:
	_become_client()
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryRegistry.apply(_paths["base"])
	var doc := Tw.map_using_spire()
	doc.scatter[World.ALIEN_RUNTIME + "/Crystal_Unused_v0"] = PackedFloat32Array(
		[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]
	)
	var plan := LibraryTransfer.plan(doc, _view(["core", "alienworld"]), _assets())
	assert_eq(plan["requests"], [], "nothing is ever requested over the player's own copy")
	assert_eq(plan["blocked"][0]["code"], "lacks")
	LibraryInstall.remove("alienworld")
	World.write_alien(_client_user.path_join("alienworld"), "0.2.0")
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.apply(_paths["base"])
	var older := LibraryTransfer.plan(doc, _view(["core", "alienworld"]), _assets())
	assert_eq(older["requests"], [])
	assert_eq(older["blocked"][0]["code"], "older")


func test_a_kept_copy_of_an_older_version_is_replaced_not_extended() -> void:
	var host := _host_served()
	_become_client()
	_first_download(host)
	var doc := Tw.map_using_spire("0.4.0")
	doc.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	var plan := LibraryTransfer.plan(doc, _view(["core", "alienworld"]), _assets())
	assert_eq(plan["requests"][0]["reason"], "newer")
	assert_has(plan["requests"][0]["assets"], Tw.SPIRE, "the whole request, not a delta")
	assert_has(plan["requests"][0]["assets"], Tw.SHARD)


# ---- hostile bundles ----


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
	assert_false(_has_dir(_installed_path("alienworld")))


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
	assert_false(_has_dir(_installed_path("alienworld")))


func test_a_bundle_cannot_carry_the_from_host_record_or_the_ownership_marker() -> void:
	var files := _bundle_files(_request(), _host_served())
	_become_client()
	var forged := files.duplicate()
	forged["alienworld/" + LibraryFromHost.RECORD_FILE] = '{"format": 1}'.to_utf8_buffer()
	var made := LibraryTransfer.verify_and_install(LibraryPartial.encode(forged), _ctx())
	assert_false(made["ok"])
	assert_has(_codes(made), LibraryPartial.E_EXTRA)
	var marked := files.duplicate()
	marked["alienworld/" + SafeDelete.MARKER] = "{}".to_utf8_buffer()
	assert_false(LibraryTransfer.verify_and_install(LibraryPartial.encode(marked), _ctx())["ok"])
	assert_false(_has_dir(_installed_path("alienworld")))


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
	assert_false(_has_dir(_installed_path("core")))
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
	assert_false(_has_dir(_installed_path("alienworld")))


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
