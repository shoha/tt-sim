extends GutTest

## LibraryQuery and the compiler's use of it (design doc 2.6.3, step S8a): filter clauses over
## category, subtype, group, ids, role and library; the shared tag, size class and season
## filters; hash, id and explicit group order; count; pins; the 64-asset cap; lock files;
## dependencies; and the guarantee that a query of `ref` clauses alone compiles as it always did.
## The catalogs here are built in the test, so nothing depends on a library on disk.

const TREES: Array[String] = ["oak", "birch", "pine", "maple", "acacia", "willow"]
## TREES ordered by fnv1a32("meadow/trees|<group>") then group id (computed outside GDScript).
const HASH_ORDER_TREES: Array[String] = ["willow", "pine", "birch", "oak", "maple", "acacia"]
## ... and for the salt "meadow/other".
const HASH_ORDER_OTHER: Array[String] = ["pine", "birch", "maple", "oak", "acacia", "willow"]


func _entry(
	id: String,
	group: String,
	category: String = "tree",
	tags: Array = [],
	size_class: String = "large",
	seasons: Array = [],
	roles: Array = []
) -> Dictionary:
	return {
		"id": id,
		"group": group,
		"name": group,
		"category": category,
		"subtype": group,
		"tags": tags,
		"seasons": seasons,
		"roles": roles,
		"size_class": size_class,
		"wind_category": "tree",
		"dimensions_m": [1.0, 2.0, 1.0],
		"file": "assets/%s.glb" % id,
		"node": id + "_LOD0",
	}


## Two variants of each tree group, in the order given.
func _trees(order: Array[String]) -> Array:
	var out: Array = []
	for group in order:
		for variant in 2:
			out.append(_entry("Tree_%s_v%d" % [group, variant], group))
	return out


func _context(entries: Array, deps: Dictionary = {}) -> Dictionary:
	var catalog := {}
	for entry: Dictionary in entries:
		catalog[entry["id"]] = entry
	return {"library": "mini", "catalog": catalog, "folder": "", "deps": deps}


func _scope(rule: String = "trees", season: String = "summer") -> Dictionary:
	return {"biome": "meadow", "rule": rule, "season": season, "label": "test"}


func _ids(selection: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for found: Dictionary in selection["found"]:
		out.append(String(found["local"]))
	return out


func _select(query: Dictionary, context: Dictionary, scope: Dictionary = {}) -> Dictionary:
	var warnings: Array[String] = []
	var chosen := scope if not scope.is_empty() else _scope()
	var result := LibraryQuery.select(query, context, chosen, warnings)
	result["warnings"] = warnings
	return result


# ---- the hash ----


func test_fnv1a32_matches_the_reference_vectors() -> void:
	assert_eq(LibraryQuery.fnv1a32(""), 0x811C9DC5)
	assert_eq(LibraryQuery.fnv1a32("a"), 0xE40C292C)
	assert_eq(LibraryQuery.fnv1a32("foobar"), 0xBF9CF968)
	assert_eq(LibraryQuery.group_hash("meadow/trees", "oak"), LibraryQuery.fnv1a32("meadow/trees|oak"))


func test_query_hash_ignores_whole_float_versus_int_and_key_order() -> void:
	var a := {"match": [{"category": "tree"}], "count": 3, "pin": ["x"]}
	var b := {"pin": ["x"], "count": 3.0, "match": [{"category": "tree"}]}
	assert_eq(LibraryQuery.query_hash(a), LibraryQuery.query_hash(b))
	b["count"] = 4
	assert_ne(LibraryQuery.query_hash(a), LibraryQuery.query_hash(b))


# ---- filters ----


func test_category_and_subtype_filter_and_clauses_are_ored() -> void:
	var entries := _trees(TREES)
	entries.append(_entry("Rock_A", "rock_a", "rock"))
	entries.append(_entry("Bush_A", "bush_a", "bush"))
	var context := _context(entries)
	var rocks := _select({"match": [{"category": "rock"}]}, context)
	assert_eq(_ids(rocks), ["Rock_A"])
	var both := _select({"match": [{"category": "rock"}, {"category": "bush"}]}, context)
	assert_eq(_ids(both), ["Rock_A", "Bush_A"], "OR of clauses, ordered by group hash")
	var oak := _select({"match": [{"category": "tree", "subtype": "oak"}]}, context)
	assert_eq(_ids(oak), ["Tree_oak_v0", "Tree_oak_v1"], "AND inside a clause")
	var none := _select({"match": [{"category": "rock", "subtype": "oak"}]}, context)
	assert_true(_ids(none).is_empty())


func test_group_ids_and_role_clauses() -> void:
	var entries := _trees(["oak", "pine"])
	entries.append(_entry("Shrub_A", "shrub_a", "bush", [], "medium", [], ["shrub"]))
	var context := _context(entries)
	assert_eq(_ids(_select({"match": [{"group": "pine"}]}, context)), ["Tree_pine_v0", "Tree_pine_v1"])
	assert_eq(_ids(_select({"match": [{"ids": ["Tree_oak_v1"]}]}, context)), ["Tree_oak_v1"])
	assert_eq(_ids(_select({"match": [{"role": "shrub"}]}, context)), ["Shrub_A"])
	assert_eq(_ids(_select({"match": [{"library": "mini", "role": "shrub"}]}, context)), ["Shrub_A"])


func test_shared_tag_and_size_filters() -> void:
	var entries := [
		_entry("T_a", "a", "tree", ["dry", "umbrella"], "large"),
		_entry("T_b", "b", "tree", ["dry"], "medium"),
		_entry("T_c", "c", "tree", ["wet", "umbrella"], "large"),
	]
	var context := _context(entries)
	var base := {"match": [{"category": "tree"}], "order": "id"}
	var query := base.duplicate(true)
	query["tags_all"] = ["dry", "umbrella"]
	assert_eq(_ids(_select(query, context)), ["T_a"])
	query = base.duplicate(true)
	query["tags_any"] = ["wet", "umbrella"]
	assert_eq(_ids(_select(query, context)), ["T_a", "T_c"])
	query = base.duplicate(true)
	query["tags_none"] = ["dry"]
	assert_eq(_ids(_select(query, context)), ["T_c"])
	query = base.duplicate(true)
	query["size_class"] = ["medium"]
	assert_eq(_ids(_select(query, context)), ["T_b"])


func test_seasons_auto_keeps_unrestricted_and_matching_assets() -> void:
	var entries := [
		_entry("T_all", "all"),
		_entry("T_summer", "summer_only", "tree", [], "large", ["summer", "autumn"]),
		_entry("T_winter", "winter_only", "tree", [], "large", ["winter"]),
	]
	var context := _context(entries)
	var query := {"match": [{"category": "tree"}], "order": "id"}
	assert_eq(_ids(_select(query, context, _scope("trees", "summer"))), ["T_all", "T_summer"])
	assert_eq(_ids(_select(query, context, _scope("trees", "winter"))), ["T_all", "T_winter"])
	query["seasons"] = "any"
	assert_eq(_ids(_select(query, context, _scope("trees", "winter"))).size(), 3)


# ---- order, count, pin ----


func test_hash_order_is_golden_and_independent_of_catalog_file_order() -> void:
	var query := {"match": [{"category": "tree"}], "count": "all"}
	var forward := _select(query, _context(_trees(TREES)))
	assert_eq(forward["groups"], HASH_ORDER_TREES)
	var shuffled: Array[String] = ["maple", "willow", "oak", "acacia", "pine", "birch"]
	var other := _select(query, _context(_trees(shuffled)))
	assert_eq(other["groups"], HASH_ORDER_TREES, "catalog order does not change the selection")
	assert_eq(_ids(other), _ids(forward))
	assert_eq(_select(query, _context(_trees(TREES)), _scope("other"))["groups"], HASH_ORDER_OTHER)


func test_variants_of_a_group_stay_together_in_id_order() -> void:
	var result := _select({"match": [{"category": "tree"}]}, _context(_trees(TREES)))
	var ids := _ids(result)
	assert_eq(ids.size(), 12)
	assert_eq(ids[0], "Tree_willow_v0")
	assert_eq(ids[1], "Tree_willow_v1")
	assert_eq(ids[2], "Tree_pine_v0")


func test_count_takes_the_first_groups_and_is_stable() -> void:
	var query := {"match": [{"category": "tree"}], "count": 2}
	var result := _select(query, _context(_trees(TREES)))
	assert_eq(result["groups"], ["willow", "pine"])
	assert_eq(_ids(result).size(), 4)
	query["count"] = 100
	assert_eq(_select(query, _context(_trees(TREES)))["groups"].size(), 6)
	query["count"] = "all"
	assert_eq(_select(query, _context(_trees(TREES)))["groups"].size(), 6)


func test_order_id_and_explicit() -> void:
	var context := _context(_trees(TREES))
	var by_id := _select({"match": [{"category": "tree"}], "order": "id", "count": 3}, context)
	assert_eq(by_id["groups"], ["acacia", "birch", "maple"])
	var listed := {
		"match": [{"ids": ["Tree_pine_v0", "Tree_oak_v1", "Tree_birch_v0"]}], "order": "explicit"
	}
	assert_eq(_select(listed, context)["groups"], ["pine", "oak", "birch"])


func test_pins_come_first_with_all_variants_and_bypass_filters() -> void:
	var context := _context(_trees(TREES))
	var query := {
		"match": [{"category": "tree", "subtype": "oak"}], "pin": ["Tree_acacia_v1"], "count": 1
	}
	var result := _select(query, context)
	assert_eq(result["groups"], ["acacia", "oak"], "the pinned group, then the one filter match")
	assert_eq(_ids(result), ["Tree_acacia_v0", "Tree_acacia_v1", "Tree_oak_v0", "Tree_oak_v1"])
	var unknown := _select({"match": [{"category": "tree"}], "pin": ["Nope"]}, context)
	assert_true("Nope" in str(unknown["warnings"]))
	assert_eq(unknown["groups"].size(), 6)


func test_pin_alone_selects_without_a_filter_clause() -> void:
	var context := _context(_trees(TREES))
	var query := {"match": [{"ref": "Tree_oak_v0"}], "pin": ["pine"]}
	assert_true(LibraryQuery.has_selection(query))
	assert_eq(_ids(_select(query, context)), ["Tree_pine_v0", "Tree_pine_v1"])


func test_a_ref_only_query_selects_nothing_here() -> void:
	var context := _context(_trees(TREES))
	var query := {"match": [{"ref": "Tree_oak_v0"}], "count": "all", "order": "explicit"}
	assert_false(LibraryQuery.has_selection(query))
	assert_true(_ids(_select(query, context)).is_empty())


func test_the_selection_is_capped_at_64_assets() -> void:
	var entries: Array = []
	for i in 70:
		entries.append(_entry("Grass_%02d" % i, "grass"))
	var result := _select({"match": [{"category": "tree"}]}, _context(entries))
	assert_eq(_ids(result).size(), LibraryContracts.QUERY_MAX_ASSETS)
	assert_true("first 64" in str(result["warnings"]))


# ---- locks ----


func test_a_valid_lock_replaces_the_selection() -> void:
	var context := _context(_trees(TREES))
	var query := {"match": [{"category": "tree"}], "count": 2}
	var lock := {
		"query": LibraryQuery.query_hash(query), "assets": ["Tree_birch_v1", "Tree_acacia_v0"]
	}
	var scope := _scope()
	scope["lock"] = lock
	var result := _select(query, context, scope)
	assert_true(result["locked"])
	assert_eq(_ids(result), ["Tree_birch_v1", "Tree_acacia_v0"])


func test_a_stale_lock_is_ignored_with_a_warning() -> void:
	var context := _context(_trees(TREES))
	var query := {"match": [{"category": "tree"}], "count": 2}
	var scope := _scope()
	scope["lock"] = {"query": "00000000", "assets": ["Tree_birch_v1"]}
	var result := _select(query, context, scope)
	assert_false(result["locked"])
	assert_eq(result["groups"], ["willow", "pine"])
	assert_true("stale" in str(result["warnings"]))
	scope["lock"] = {"query": LibraryQuery.query_hash(query), "assets": ["Tree_gone_v0"]}
	result = _select(query, context, scope)
	assert_false(result["locked"])
	assert_true("Tree_gone_v0" in str(result["warnings"]))


# ---- dependencies ----


func _dependency_context() -> Dictionary:
	var dep_entries := [_entry("Tree_oak_v0", "oak"), _entry("Tree_old_v0", "old")]
	var dep_catalog := {}
	for entry: Dictionary in dep_entries:
		dep_catalog[entry["id"]] = entry
	var deps := {
		"core":
		{
			"read": {"library": {"retired": ["Tree_old_v0"]}, "catalog": dep_catalog},
			"folder": "D:/core"
		}
	}
	return _context([_entry("Tree_oak_v0", "oak"), _entry("Own_v0", "own")], deps)


func test_a_dependencys_assets_are_candidates_under_a_prefixed_local_id() -> void:
	var context := _dependency_context()
	var all := LibraryQuery.candidates(context)
	var locals: Array[String] = []
	for candidate in all:
		locals.append(String(candidate["local"]))
	assert_eq(locals, ["Own_v0", "Tree_oak_v0", "core__Tree_oak_v0"], "sorted; retired id left out")
	var result := _select({"match": [{"library": "core"}]}, context)
	assert_eq(_ids(result), ["core__Tree_oak_v0"])
	assert_eq(result["found"][0]["folder"], "D:/core")
	assert_eq(result["found"][0]["library"], "core")
	assert_eq(_ids(_select({"match": [{"group": "core:oak"}]}, context)), ["core__Tree_oak_v0"])
	assert_eq(_ids(_select({"match": [{"ids": ["core:Tree_oak_v0"]}]}, context)), ["core__Tree_oak_v0"])
	assert_eq(_ids(_select({"match": [{"library": "mini", "group": "oak"}]}, context)), ["Tree_oak_v0"])


func test_a_ref_naming_a_group_expands_to_its_variants() -> void:
	var context := _context(_trees(TREES))
	assert_eq(LibraryQuery.group_members("oak", context).size(), 2)
	assert_true(LibraryQuery.group_members("Tree_oak_v0", context).is_empty(), "an entry is no group")
	assert_true(LibraryQuery.group_members("nonesuch", context).is_empty())
	var dep := _dependency_context()
	assert_eq(LibraryQuery.group_members("core:oak", dep).size(), 1)


func test_why_not_names_the_failed_conditions() -> void:
	var entries := [_entry("T_a", "a", "tree", ["dry"], "large", ["winter"])]
	var all := LibraryQuery.candidates(_context(entries))
	var query := {"match": [{"category": "rock"}], "tags_all": ["wet"]}
	var why := LibraryQuery.why_not(query, all[0], "summer")
	assert_true("category is tree, not rock" in why)
	assert_true("lacks tag wet" in why)
	assert_true("not in season summer" in why)
	assert_true(LibraryQuery.why_not({"match": [{"category": "tree"}]}, all[0], "winter").is_empty())


# ---- reader and compiler ----


func _library_text() -> String:
	return JSON.stringify(
		{
			"format": "ttsim-library",
			"format_version": 1,
			"id": "mini",
			"name": "Mini",
			"version": "0.1.0",
			"contract": 1,
		}
	)


func _read(rule_query: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var catalog := {"format": "ttsim-catalog", "format_version": 1, "assets": _trees(TREES)}
	var rule := {
		"key": "trees",
		"role": "canopy_tree",
		"density_per_m2": 0.01,
		"query": rule_query,
	}
	rule.merge(extra)
	var biome := {
		"format": "ttsim-biome",
		"format_version": 1,
		"id": "meadow",
		"name": "Meadow",
		"seasons": [{"id": "summer", "seed": 1}],
		"ground": {},
		"rules": [rule],
	}
	return LibraryReader.read(
		{
			"library": _library_text(),
			"catalog": JSON.stringify(catalog),
			"biomes": {"meadow.json": JSON.stringify(biome)},
		}
	)


func _compiled_assets(read: Dictionary) -> Array:
	var compiled := BiomeCompiler.compile(read, {"surfaces": {}})
	var biomes: Array = compiled["palette"].get("biomes", [])
	if biomes.is_empty():
		return []
	return biomes[0]["species"][0]["assets"]


func test_the_compiler_selects_by_query_and_prefixes_the_biome() -> void:
	var read := _read({"match": [{"category": "tree"}], "count": 2})
	assert_true(read["ok"], str(read["errors"]))
	var assets := _compiled_assets(read)
	assert_eq(
		assets,
		[
			"mini__meadow_summer_s1/Tree_willow_v0",
			"mini__meadow_summer_s1/Tree_willow_v1",
			"mini__meadow_summer_s1/Tree_pine_v0",
			"mini__meadow_summer_s1/Tree_pine_v1"
		]
	)


func test_refs_come_first_and_a_ref_only_query_compiles_as_before() -> void:
	var refs := _read({"match": [{"ref": "Tree_oak_v1"}, {"ref": "Tree_oak_v0"}], "count": "all", "order": "explicit"})
	assert_eq(
		_compiled_assets(refs),
		["mini__meadow_summer_s1/Tree_oak_v1", "mini__meadow_summer_s1/Tree_oak_v0"],
		"listed order, untouched by count and order"
	)
	var mixed := _read({"match": [{"ref": "Tree_oak_v1"}, {"group": "oak"}]})
	assert_eq(
		_compiled_assets(mixed),
		["mini__meadow_summer_s1/Tree_oak_v1", "mini__meadow_summer_s1/Tree_oak_v0"],
		"the ref, then the filter's variants, the duplicate once"
	)
	var group_ref := _read({"match": [{"ref": "pine"}]})
	assert_eq(
		_compiled_assets(group_ref),
		["mini__meadow_summer_s1/Tree_pine_v0", "mini__meadow_summer_s1/Tree_pine_v1"],
		"a ref may name a group"
	)


func test_a_lock_in_the_read_result_pins_the_selection() -> void:
	var query := {"match": [{"category": "tree"}], "count": 1}
	var read := _read(query)
	var lock := {
		"format": "ttsim-biome-lock",
		"format_version": 1,
		"rules":
		{
			"summer/trees":
			{"query": LibraryQuery.query_hash(query), "assets": ["Tree_birch_v0"]}
		},
	}
	var catalog := {"format": "ttsim-catalog", "format_version": 1, "assets": _trees(TREES)}
	var with_lock := LibraryReader.read(
		{
			"library": _library_text(),
			"catalog": JSON.stringify(catalog),
			"biomes": read_biomes(query),
			"locks": {"meadow.lock.json": JSON.stringify(lock)},
		}
	)
	assert_true(with_lock["ok"], str(with_lock["errors"]))
	assert_eq(_compiled_assets(with_lock), ["mini__meadow_summer_s1/Tree_birch_v0"])
	assert_eq(_compiled_assets(read).size(), 2, "without the lock the first group (2 variants)")


func read_biomes(query: Dictionary) -> Dictionary:
	var biome := {
		"format": "ttsim-biome",
		"format_version": 1,
		"id": "meadow",
		"name": "Meadow",
		"seasons": [{"id": "summer", "seed": 1}],
		"ground": {},
		"rules":
		[{"key": "trees", "role": "canopy_tree", "density_per_m2": 0.01, "query": query}],
	}
	return {"meadow.json": JSON.stringify(biome)}


func test_a_malformed_lock_is_a_warning_not_an_error() -> void:
	var catalog := {"format": "ttsim-catalog", "format_version": 1, "assets": _trees(TREES)}
	var read := LibraryReader.read(
		{
			"library": _library_text(),
			"catalog": JSON.stringify(catalog),
			"biomes": read_biomes({"match": [{"category": "tree"}]}),
			"locks": {"meadow.lock.json": "{not json", "b.lock.json": '{"format": "ttsim-biome-lock", "rules": {"x": 3}}'},
		}
	)
	assert_true(read["ok"], str(read["errors"]))
	assert_true("not a readable lock file" in str(read["warnings"]))
	assert_true("malformed" in str(read["warnings"]))


func test_the_reader_checks_query_clauses_and_filters() -> void:
	var good := _read(
		{
			"match": [{"category": "tree", "subtype": "oak", "role": "canopy_tree"}, {"ref": "oak"}],
			"tags_any": ["dry"],
			"size_class": ["large"],
			"seasons": "auto",
			"count": 3,
			"order": "hash",
			"pin": ["Tree_oak_v0"],
		}
	)
	assert_true(good["ok"], str(good["errors"]))
	assert_true(good["warnings"].is_empty(), str(good["warnings"]))
	var bad_queries: Array[Dictionary] = [
		{"match": [{"category": "dragons"}]},
		{"match": [{"role": "flyer"}]},
		{"match": [3]},
		{"match": [{"category": "tree"}], "count": 0},
		{"match": [{"category": "tree"}], "count": "some"},
		{"match": [{"category": "tree"}], "order": "random"},
		{"match": [{"category": "tree"}], "seasons": "never"},
		{"match": [{"category": "tree"}], "size_class": ["huge"]},
		{"match": [{"category": "tree"}], "tags_all": "dry"},
		{"match": [{"category": "tree"}], "pin": ["a/b"]},
		{"match": [{"ids": [3]}]},
	]
	for query in bad_queries:
		assert_false(_read(query)["ok"], "should be refused: %s" % JSON.stringify(query))
	var odd := _read({"match": [{"category": "tree", "colour": "red"}, {}]})
	assert_true(odd["ok"])
	assert_true("colour" in str(odd["warnings"]), str(odd["warnings"]))
	assert_true("matches every asset" in str(odd["warnings"]))
