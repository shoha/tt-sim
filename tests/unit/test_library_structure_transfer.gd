extends "res://tests/unit/library_transfer_case.gd"

## Structures in a multiplayer library transfer (card S3, docs/systems/library.md "Multiplayer"):
## a map's structure references are asked for like assets, the host's partial holds only the
## structures asked for (index cut to them, their recipes and tiles), the client checks every file
## before it keeps anything, a later request only EXTENDS the kept copy, and a hostile request or
## bundle is refused. The world is the transfer world with two structures added to `alienworld`.

const SW := preload("res://tests/unit/library_structure_world.gd")


func _root() -> String:
	return "user://test_library_structure_transfer"


func before_each() -> void:
	super()
	SW.write(_paths["alien"], {"hut": "cottage", "manor": "townhouse"})


## The map that uses only the structure `ref` of alienworld (no plant, no biome).
func _map_using(refs: Array) -> MapDocument:
	var doc := MapDocument.new()
	var plan := PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])
	for k in refs.size():
		doc.structures.append(Structure.make(k + 1, String(refs[k]), plan, 5))
	doc.libraries = (
		[{"id": "alienworld", "version": "0.3.1", "hash": "abc12345"}] as Array[Dictionary]
	)
	return doc


func _plan_for(doc: MapDocument, ids: Array = ["core"]) -> Dictionary:
	return LibraryTransfer.plan(doc, _view(ids), _assets())


# ---- the client's plan ----


func test_a_missing_library_is_requested_with_the_structures_the_map_uses() -> void:
	_become_client()
	var plan := _plan_for(_map_using(["alienworld:hut"]))
	assert_eq(plan["requests"].size(), 1)
	var request: Dictionary = plan["requests"][0]
	assert_eq(request["structures"], ["alienworld:hut"])
	assert_eq(request["assets"], [])
	assert_eq(LibraryPartial.request_problem(request), "")


func test_an_installed_library_with_the_structure_asks_for_nothing() -> void:
	_host_served()
	var plan := _plan_for(_map_using(["alienworld:hut"]), ["core", "alienworld"])
	assert_eq(plan["requests"], [])
	assert_eq(plan["satisfied"], ["alienworld"])


func test_a_players_own_copy_lacking_the_structure_is_blocked_not_replaced() -> void:
	_host_served()
	var plan := _plan_for(_map_using(["alienworld:castle"]), ["core", "alienworld"])
	assert_eq(plan["requests"], [])
	assert_eq(plan["blocked"][0]["code"], "lacks")


func test_a_hint_carries_the_structure_references_and_plans_back_to_the_same_request() -> void:
	var doc := _map_using(["alienworld:hut", "alienworld:manor"])
	var hint := LibraryTransfer.hint_of(doc, "alienworld")
	assert_eq(hint["structures"], ["alienworld:hut", "alienworld:manor"])
	assert_eq(LibraryPartial.request_problem(hint), "")
	var rebuilt := LibraryTransfer.document_of_hint(hint)
	assert_eq(
		rebuilt.structures.map(func(s: Structure) -> String: return s.recipe), hint["structures"]
	)


# ---- the host's partial ----


func test_the_partial_holds_only_the_structures_asked_for() -> void:
	var request := _request_for(["alienworld:hut"])
	var host := _host_served()
	var files := _bundle_files(request, host)
	assert_true(files.has("alienworld/structures/index.json"))
	assert_true(files.has("alienworld/structures/hut.structure.json"))
	assert_true(files.has("alienworld/thumbnails/structures/hut.jpg"), "the tile travels")
	assert_false(files.has("alienworld/structures/manor.structure.json"))
	assert_false(files.has("alienworld/thumbnails/structures/manor.jpg"))
	var index: Dictionary = JSON.parse_string(
		(files["alienworld/structures/index.json"] as PackedByteArray).get_string_from_utf8()
	)
	assert_eq(
		(index["structures"] as Array).map(func(e: Dictionary) -> String: return e["id"]), ["hut"]
	)
	var library: Dictionary = JSON.parse_string(
		(files["alienworld/library.json"] as PackedByteArray).get_string_from_utf8()
	)
	assert_eq(library["partial"]["structures"], ["hut"])
	assert_eq(LibraryTransfer.quote(request, host)["libraries"][0]["structures"], 1)


func test_a_structure_the_host_lacks_is_skipped_and_counted() -> void:
	var request := _request_for(["alienworld:hut", "alienworld:castle"])
	var quote := LibraryTransfer.quote(request, _host_served())
	assert_true(quote["ok"])
	assert_eq(quote["skipped"], 1)


func test_a_request_is_authorized_only_for_structures_a_served_map_uses() -> void:
	var request := _request_for(["alienworld:hut"])
	var usage := LibraryTransfer.usage_of([_map_using(["alienworld:hut"])])
	assert_eq(LibraryTransfer.authorize(request, usage), "")
	var other := LibraryTransfer.usage_of([_map_using(["alienworld:manor"])])
	assert_ne(LibraryTransfer.authorize(request, other), "", "a structure no served map uses")
	var merged := LibraryTransfer.usage_of([])
	LibraryTransfer.merge_usage(merged, usage)
	assert_eq(LibraryTransfer.authorize(request, merged), "")


func test_hostile_structure_requests_are_refused() -> void:
	var request := _request_for(["alienworld:hut"])
	var cases := {
		"not a list": func(r: Dictionary) -> void: r["structures"] = "alienworld:hut",
		"too many": func(r: Dictionary) -> void: r["structures"] = _many(129),
		"another library": func(r: Dictionary) -> void: r["structures"] = ["core:cottage"],
		"malformed": func(r: Dictionary) -> void: r["structures"] = ["alienworld:Bad Id"],
		"not text": func(r: Dictionary) -> void: r["structures"] = [5],
		"no library": func(r: Dictionary) -> void: r["structures"] = [":hut"],
		"held not a list": func(r: Dictionary) -> void: r["held_structures"] = 3,
	}
	for label: String in cases:
		var bad := request.duplicate(true)
		(cases[label] as Callable).call(bad)
		assert_ne(LibraryPartial.request_problem(bad), "", label)


func _many(count: int) -> Array:
	var out: Array = []
	for k in count:
		out.append("alienworld:s%d" % k)
	return out


func _request_for(refs: Array) -> Dictionary:
	_become_client()
	var plan := _plan_for(_map_using(refs))
	assert_eq(plan["requests"].size(), 1)
	return plan["requests"][0]


# ---- the client keeps it ----


func test_a_structures_only_bundle_installs_and_the_registry_serves_it() -> void:
	var request := _request_for(["alienworld:hut"])
	var host := _host_served()
	_become_client()
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx({"host": "Ann"})
	)
	assert_true(made["ok"], str(made["errors"]))
	LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["status"], "ok", str(info["reasons"]))
	assert_eq(info["structure_count"], 1)
	assert_true(LibraryStructureStore.has("alienworld:hut"))
	assert_false(LibraryStructureStore.has("alienworld:manor"))
	assert_eq(LibraryRegistry.record_of("alienworld")["hash"], host["alienworld"]["hash"])
	var doc := _map_using(["alienworld:hut"])
	assert_true(MapLibraries.check(doc.libraries)["ok"], "the map opens")
	var ground := SW.map_with("alienworld:hut")
	var parts := StructureGeometry.build_one(ground, ground.structures[0])
	assert_eq(parts.problem, "")
	assert_false(parts.placeholder)
	assert_eq(_plan_for(doc, ["core", "alienworld"])["requests"], [], "nothing more to ask")


func test_a_later_request_extends_the_kept_copy_with_the_missing_structure_only() -> void:
	var host := _host_served()
	var first := _request_for(["alienworld:hut"])
	_become_client()
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(first, host), _ctx({"host": "Ann"})
	)
	assert_true(made["ok"], str(made["errors"]))
	LibraryRegistry.apply(_paths["base"])
	var plan := _plan_for(
		_map_using(["alienworld:hut", "alienworld:manor"]), ["core", "alienworld"]
	)
	assert_eq(plan["requests"].size(), 1, str(plan))
	var request: Dictionary = plan["requests"][0]
	assert_eq(request["reason"], "more")
	assert_eq(request["structures"], ["alienworld:manor"], "the manor only")
	assert_eq(request["held_structures"], ["hut"])
	assert_eq(request["full"]["structures"], ["alienworld:hut", "alienworld:manor"])
	var delta := _bundle_files(request, host)
	assert_false(delta.has("alienworld/structures/hut.structure.json"), "not sent again")
	assert_true(delta.has("alienworld/structures/manor.structure.json"))
	var merged := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx({"host": "Ann", "now": 2000})
	)
	assert_true(merged["ok"], str(merged["errors"]))
	assert_eq(merged["merged"], ["alienworld"])
	LibraryRegistry.apply(_paths["base"])
	assert_true(LibraryStructureStore.has("alienworld:hut"))
	assert_true(LibraryStructureStore.has("alienworld:manor"))
	var kept := LibraryFromHost.read_folder_files("alienworld")
	var index: Dictionary = JSON.parse_string(
		(kept["structures/index.json"] as PackedByteArray).get_string_from_utf8()
	)
	assert_eq(
		(index["structures"] as Array).map(func(e: Dictionary) -> String: return e["id"]),
		["hut", "manor"],
		"the index is the union"
	)


# ---- hostile bundles ----


func _good_files() -> Dictionary:
	var request := _request_for(["alienworld:hut"])
	var host := _host_served()
	var files := _bundle_files(request, host)
	_become_client()
	return files


func _install_refused(files: Dictionary) -> Dictionary:
	var made := LibraryTransfer.verify_and_install(files, _ctx())
	assert_false(made["ok"])
	assert_false(_has_dir(_installed_path("alienworld")), "nothing was written")
	return made


func test_a_bundle_with_a_structure_file_the_index_does_not_list_is_refused() -> void:
	var files := _good_files()
	files["alienworld/structures/extra.structure.json"] = SW.recipe_text("cottage").to_utf8_buffer()
	assert_has(_codes(_install_refused(files)), LibraryPartial.E_EXTRA)


func test_a_bundle_whose_recipe_is_not_a_safe_document_is_refused() -> void:
	var files := _good_files()
	var data: Dictionary = JSON.parse_string(SW.recipe_text("cottage"))
	data["nodes"][0]["type"] = "run_script"
	files["alienworld/structures/hut.structure.json"] = JSON.stringify(data).to_utf8_buffer()
	var made := _install_refused(files)
	assert_gt((made["errors"] as Array).size(), 0)


func test_a_bundle_with_an_oversize_recipe_is_refused_by_the_cap() -> void:
	var files := _good_files()
	var big := (
		SW.recipe_text("cottage") + " ".repeat(int(LibraryContracts.STRUCTURE_CAPS["recipe_bytes"]))
	)
	files["alienworld/structures/hut.structure.json"] = big.to_utf8_buffer()
	_install_refused(files)


func test_a_bundle_with_a_traversing_or_misnamed_structure_path_is_refused() -> void:
	var files := _good_files()
	files["alienworld/structures/../library.structure.json"] = (
		SW.recipe_text("cottage").to_utf8_buffer()
	)
	assert_has(_codes(_install_refused(files)), LibraryPartial.E_TRAVERSAL)
