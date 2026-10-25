extends "res://tests/unit/library_transfer_case.gd"

## Multiplayer library transfer, the client's plan and the host's partial (docs/systems/library.md
## "Multiplayer"): what a client asks a host for (plan), what the host will quote and send
## (authorize, quote, build_bundle: only the used assets, the biome-defs cut to their used rules,
## the surfaces those biomes use, no official dependency). Installing is in
## test_library_transfer_install.gd.


func _root() -> String:
	return "user://test_library_transfer_plan"


# ---- plan: what to ask for ----


func test_a_library_the_client_lacks_is_requested_with_the_used_ids_only() -> void:
	var request := _request()
	assert_eq(request["library"], "alienworld")
	assert_eq(request["protocol"], LibraryPartial.PROTOCOL)
	assert_eq(request["version"], "0.3.1")
	assert_eq(request["hash"], "abc12345")
	assert_eq(request["reason"], "missing")
	assert_eq(request["assets"], [Tw.SPIRE, Tw.CORE_OAK])
	assert_eq(request["biomes"], [World.ALIEN_RUNTIME])
	assert_eq(request["surfaces"], ["alienworld__crystal_dust"])
	assert_true(request["have"].has("core"), "the client says what it has")
	assert_eq(LibraryPartial.request_problem(request), "")


func test_core_is_never_requested() -> void:
	_become_client()
	var doc := MapDocument.new()
	doc.scatter["forest_summer_s1/Oak"] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	var plan := LibraryTransfer.plan(doc, _view(["core"]), _assets())
	assert_eq(plan["requests"], [])
	assert_eq(plan["blocked"], [])


func test_an_installed_library_with_every_used_asset_asks_for_nothing() -> void:
	_host_served()
	var plan := LibraryTransfer.plan(Tw.map_using_spire(), _view(["core", "alienworld"]), _assets())
	assert_eq(plan["requests"], [])
	assert_eq(plan["satisfied"], ["alienworld"])


func test_an_older_installed_version_of_the_players_own_is_never_replaced_by_the_hosts() -> void:
	# The client has 0.2.0 (same major) without the Spire; the map was saved with 0.3.1. A copy
	# the player installed is theirs: nothing is requested over it, the plan says what it lacks.
	World.edit_json(
		_paths["alien"] + "/library.json", func(d: Dictionary) -> void: d["version"] = "0.2.0"
	)
	LibraryRegistry.apply(_paths["base"])
	var assets: Dictionary = _assets().duplicate()
	assets.erase(Tw.SPIRE)
	var plan := LibraryTransfer.plan(Tw.map_using_spire(), _view(["core", "alienworld"]), assets)
	assert_eq(plan["requests"], [])
	assert_eq(plan["blocked"][0]["code"], "older")
	assert_string_contains(plan["blocked"][0]["text"], "0.2.0 is installed")


func test_the_same_version_lacking_an_asset_is_blocked_not_requested() -> void:
	_host_served()
	var assets: Dictionary = _assets().duplicate()
	assets.erase(Tw.SPIRE)
	var plan := LibraryTransfer.plan(Tw.map_using_spire(), _view(["core", "alienworld"]), assets)
	assert_eq(plan["requests"], [])
	assert_eq(plan["blocked"][0]["code"], "lacks")


func test_another_major_version_is_blocked() -> void:
	_host_served()
	var plan := LibraryTransfer.plan(Tw.map_using_spire("2.0.0"), _view(["core", "alienworld"]), {})
	assert_eq(plan["requests"], [])
	assert_eq(plan["blocked"][0]["code"], "incompatible")


func test_a_disabled_library_is_blocked_with_a_reason() -> void:
	_host_served()
	LibraryRegistry.set_enabled("alienworld", false)
	LibraryRegistry.apply(_paths["base"])
	var plan := LibraryTransfer.plan(Tw.map_using_spire(), _view(["core", "alienworld"]), {})
	assert_eq(plan["blocked"][0]["code"], "disabled")


func test_a_reserved_library_id_is_blocked() -> void:
	var doc := MapDocument.new()
	doc.scatter["dev__x_summer_s1/Tree"] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	var plan := LibraryTransfer.plan(doc, {}, {})
	assert_eq(plan["requests"], [])
	assert_eq(plan["blocked"][0]["code"], "reserved")


func test_a_downloaded_partial_that_lacks_more_is_extended_by_a_delta() -> void:
	var request := _request()
	var host := _host_served()
	_become_client()
	var made := LibraryTransfer.verify_and_install(
		LibraryTransfer.build_bundle(request, host), _ctx()
	)
	assert_true(made["ok"], str(made["errors"]))
	LibraryRegistry.apply(_paths["base"])
	var doc := Tw.map_using_spire()
	doc.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	var plan := LibraryTransfer.plan(doc, _view(["core", "alienworld"]), _assets())
	assert_eq((plan["requests"] as Array).size(), 1)
	assert_eq(plan["requests"][0]["reason"], "more")
	assert_eq(plan["requests"][0]["assets"], [Tw.SHARD], "only what is missing")


# ---- requests from a peer ----


func test_request_problem_refuses_malformed_requests() -> void:
	var good := _request()
	assert_eq(LibraryPartial.request_problem(good), "")
	assert_ne(LibraryPartial.request_problem("text"), "")
	var other := good.duplicate(true)
	other["protocol"] = 99
	assert_true("protocol" in LibraryPartial.request_problem(other))
	for mutate: Callable in [
		func(r: Dictionary) -> void: r["library"] = "Bad Id",
		func(r: Dictionary) -> void: r["library"] = "core",
		func(r: Dictionary) -> void: r["assets"] = "not a list",
		func(r: Dictionary) -> void: r["assets"] = [1, 2],
		func(r: Dictionary) -> void: r["assets"] = ["no_slash"],
		func(r: Dictionary) -> void: r["assets"] = ["a/b/c"],
		func(r: Dictionary) -> void:
			r["biomes"] = range(300).map(func(i: int) -> String: return "b%d" % i),
		func(r: Dictionary) -> void: r["version"] = "x".repeat(100),
		func(r: Dictionary) -> void: r["have"] = {"core": 5},
		func(r: Dictionary) -> void: r["have"] = "core",
	]:
		var bad := good.duplicate(true)
		mutate.call(bad)
		assert_ne(LibraryPartial.request_problem(bad), "", "refused: %s" % str(bad.keys()))


func test_authorize_allows_only_what_a_served_map_uses() -> void:
	var request := _request()
	var usage := LibraryTransfer.usage_of([Tw.map_using_spire()])
	assert_eq(LibraryTransfer.authorize(request, usage), "")
	var greedy := request.duplicate(true)
	(greedy["assets"] as Array).append(Tw.SHARD)
	assert_string_contains(LibraryTransfer.authorize(greedy, usage), "Crystal_Shard_v0")
	assert_ne(LibraryTransfer.authorize(request, LibraryTransfer.usage_of([])), "")


# ---- the host's partial ----


func test_the_bundle_holds_only_the_used_assets_biome_rules_and_surfaces() -> void:
	var request := _request()
	var files := _bundle_files(request, _host_served())
	var paths: Array = files.keys()
	paths.sort()
	assert_eq(
		paths,
		[
			"alienworld/assets/catalog.json",
			"alienworld/assets/tree/Crystal_Spire_v0.glb",
			"alienworld/biomes/crystal_basin.json",
			"alienworld/library.json",
			"alienworld/surfaces/crystal_dust/albedo.png",
			"alienworld/surfaces/crystal_dust/height.png",
			"alienworld/surfaces/crystal_dust/normal.png",
			"alienworld/surfaces/crystal_dust/orm.png",
			"alienworld/surfaces/crystal_dust/surface.json",
		]
	)
	var catalog: Dictionary = JSON.parse_string(
		files["alienworld/assets/catalog.json"].get_string_from_utf8()
	)
	assert_eq(
		catalog["assets"].map(func(e: Dictionary) -> String: return e["id"]), ["Crystal_Spire_v0"]
	)
	for entry: Dictionary in catalog["assets"]:
		assert_true(entry.has("sha256") and entry.has("bytes"), "hash and size always set")
	var biome: Dictionary = JSON.parse_string(
		files["alienworld/biomes/crystal_basin.json"].get_string_from_utf8()
	)
	assert_eq(biome["rules"].size(), 1, "the stones rule has no used asset")
	assert_eq(biome["rules"][0]["key"], "trees")
	var refs: Array = biome["rules"][0]["query"]["match"].map(
		func(m: Dictionary) -> String: return m["ref"]
	)
	assert_eq(refs, ["Crystal_Spire_v0", "core:Tree_Oak_v0"])


func test_the_partial_library_json_keeps_identity_and_records_what_was_kept() -> void:
	var files := _bundle_files(_request(), _host_served())
	var library: Dictionary = JSON.parse_string(
		files["alienworld/library.json"].get_string_from_utf8()
	)
	assert_eq(library["id"], "alienworld")
	assert_eq(library["version"], "0.3.1")
	assert_eq(library["name"], "Alien World")
	assert_false(library.has("stats"))
	assert_false(library.has("thumbnail"))
	var partial: Dictionary = library["partial"]
	assert_eq(partial["assets"], ["Crystal_Spire_v0"])
	assert_eq(partial["biomes"], ["crystal_basin"])
	assert_eq(partial["surfaces"], ["crystal_dust"])
	assert_false(partial["assets_only"])
	assert_eq(partial["source_version"], "0.3.1")
	assert_ne(partial["source_hash"], "")


func test_a_second_biome_and_surface_are_sent_only_when_the_map_uses_them() -> void:
	var request := _request()
	(request["assets"] as Array).append(Tw.ICE_RUNTIME + "/Crystal_Unused_v0")
	(request["biomes"] as Array).append(Tw.ICE_RUNTIME)
	(request["surfaces"] as Array).append("alienworld__night_rock")
	var files := _bundle_files(request, _host_served())
	assert_true(files.has("alienworld/biomes/ice_flats.json"))
	assert_true(files.has("alienworld/assets/rock/Crystal_Unused_v0.glb"))
	assert_true(files.has("alienworld/surfaces/night_rock/albedo.png"))
	assert_false(files.has("alienworld/assets/rock/Crystal_Shard_v0.glb"))


func test_the_core_dependency_is_not_sent_and_an_unknown_asset_is_skipped() -> void:
	var request := _request()
	(request["assets"] as Array).append(World.ALIEN_RUNTIME + "/Crystal_Gone_v9")
	var quote := LibraryTransfer.quote(request, _host_served())
	assert_true(quote["ok"], str(quote))
	assert_eq(quote["libraries"].size(), 1, "core ships with the game")
	assert_eq(quote["skipped"], 1)
	assert_eq(quote["libraries"][0]["id"], "alienworld")
	assert_eq(quote["libraries"][0]["assets"], 1)
	assert_eq(quote["libraries"][0]["name"], "Alien World")
	assert_eq(quote["libraries"][0]["author"], "Test Author")


func test_the_quote_sizes_match_the_bundle() -> void:
	var request := _request()
	var host := _host_served()
	var quote := LibraryTransfer.quote(request, host)
	var files := _bundle_files(request, host)
	var total := 0
	for data: PackedByteArray in files.values():
		total += data.size()
	assert_eq(quote["bytes"], total)
	assert_eq(quote["files"], files.size())


func test_a_bundle_built_twice_is_the_same_bytes() -> void:
	var request := _request()
	var host := _host_served()
	assert_eq(
		LibraryTransfer.build_bundle(request, host), LibraryTransfer.build_bundle(request, host)
	)


func test_the_host_refuses_what_it_does_not_have_or_what_ships_with_the_game() -> void:
	var host := _host_served()
	var request := _request()
	var lost := request.duplicate(true)
	lost["library"] = "nowhere"
	assert_eq(LibraryTransfer.quote(lost, host)["code"], "not_served")
	var major := request.duplicate(true)
	major["version"] = "9.0.0"
	assert_eq(LibraryTransfer.quote(major, host)["code"], "version")
	var bad := request.duplicate(true)
	bad["protocol"] = 2
	assert_eq(LibraryTransfer.quote(bad, host)["code"], "request")
	var official := host.duplicate(true)
	official["alienworld"]["official"] = true
	assert_eq(LibraryTransfer.quote(request, official)["code"], "official")


func test_a_dependency_the_client_lacks_is_sent_as_an_assets_only_part() -> void:
	# alienworld now depends on a user library `pool` whose asset a rule names.
	var pool: String = _paths["user"] + "/pool"
	var pool_lib := {
		"format": "ttsim-library",
		"format_version": 1,
		"id": "pool",
		"name": "Pool",
		"version": "1.0.0",
		"contract": 1,
		"license": "CC0-1.0",
		"dependencies": [],
	}
	World.write_library(
		pool,
		pool_lib,
		[
			World._asset("Pool_Rock_v0", "rock", "", "small"),
			World._asset("Pool_Other_v0", "rock", "", "small")
		],
		World._biome("pool_biome", "Pool", ["Pool_Rock_v0"], ["Pool_Other_v0"])
	)
	World.edit_json(
		_paths["alien"] + "/library.json",
		func(d: Dictionary) -> void:
			d["dependencies"] = [
				{"id": "core", "version": "^1.0"}, {"id": "pool", "version": "^1.0"}
			]
	)
	World.edit_json(
		_paths["alien"] + "/biomes/crystal_basin.json",
		func(d: Dictionary) -> void:
			d["rules"][0]["query"]["match"].append({"ref": "pool:Pool_Rock_v0"})
	)
	var host := _host_served()
	var request := _request()
	(request["assets"] as Array).append(World.ALIEN_RUNTIME + "/pool__Pool_Rock_v0")
	var files := _bundle_files(request, host)
	var library: Dictionary = JSON.parse_string(files["pool/library.json"].get_string_from_utf8())
	assert_true(library["partial"]["assets_only"])
	assert_eq(library["partial"]["assets"], ["Pool_Rock_v0"])
	assert_false(files.has("pool/assets/rock/Pool_Other_v0.glb"))
	assert_false(files.keys().any(func(p: String) -> bool: return p.begins_with("pool/biomes/")))
	# A client that has pool at a compatible version is not sent it again.
	var have := request.duplicate(true)
	have["have"]["pool"] = "1.2.0"
	var skipped := _bundle_files(have, host)
	assert_false(skipped.keys().any(func(p: String) -> bool: return p.begins_with("pool/")))


func test_the_usage_of_several_maps_is_merged() -> void:
	var usage := LibraryTransfer.usage_of([Tw.map_using_spire()])
	var other := MapDocument.new()
	other.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	LibraryTransfer.merge_usage(usage, LibraryTransfer.usage_of([other, null]))
	assert_true(usage["assets"].has(Tw.SPIRE) and usage["assets"].has(Tw.SHARD))
	assert_true(usage["biomes"].has(World.ALIEN_RUNTIME))
