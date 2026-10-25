extends GutTest

## LibraryVersions (semantic versions and dependency ranges) and LibraryResolver (which libraries
## found on disk can be served, and in what order), both pure: the ranges `^1.0`, `~1.2`, exact,
## partial, comparators and `*`; prerelease tags ignored; duplicates, disabled libraries, cycles,
## depth and the built-in core as a provider.


func test_versions_parse_and_compare() -> void:
	var parsed := LibraryVersions.parse("1.2.3")
	assert_eq([parsed["major"], parsed["minor"], parsed["patch"], parsed["parts"]], [1, 2, 3, 3])
	assert_eq(LibraryVersions.parse("1.2")["parts"], 2)
	assert_eq(LibraryVersions.parse("v2")["major"], 2)
	assert_eq(LibraryVersions.parse("1.0.0-dev")["pre"], "dev")
	for bad in ["", "x", "1.x", "1..2", "1.2.3.4", "-1.0.0", "1.2.", "1.0.0000000000"]:
		assert_eq(LibraryVersions.parse(bad), {}, "'%s' is not a version" % bad)
	assert_eq(LibraryVersions.compare("1.2.0", "1.10.0"), -1, "numbers, not strings")
	assert_eq(LibraryVersions.compare("2.0.0", "1.99.99"), 1)
	assert_eq(LibraryVersions.compare("1.0.0-dev", "1.0.0"), 0, "prerelease is ignored")
	assert_true(LibraryVersions.is_full("1.0.0"))
	assert_false(LibraryVersions.is_full("1.0"))


func test_caret_ranges_hold_the_leftmost_non_zero_part() -> void:
	for yes in ["1.0.0", "1.4.2", "1.99.0", "1.0.0-dev"]:
		assert_true(LibraryVersions.satisfies(yes, "^1.0"), yes)
	for no in ["0.9.9", "2.0.0", "2.1.0"]:
		assert_false(LibraryVersions.satisfies(no, "^1.0"), no)
	assert_true(LibraryVersions.satisfies("0.3.9", "^0.3.1"))
	assert_false(LibraryVersions.satisfies("0.4.0", "^0.3.1"))
	assert_false(LibraryVersions.satisfies("0.3.0", "^0.3.1"))
	assert_true(LibraryVersions.satisfies("0.0.3", "^0.0.3"))
	assert_false(LibraryVersions.satisfies("0.0.4", "^0.0.3"))
	assert_true(LibraryVersions.satisfies("0.9.0", "^0"))
	assert_false(LibraryVersions.satisfies("1.0.0", "^0"))
	assert_true(LibraryVersions.satisfies("1.9.0", "^1"))


func test_tilde_exact_partial_and_comparator_ranges() -> void:
	assert_true(LibraryVersions.satisfies("1.2.9", "~1.2.3"))
	assert_false(LibraryVersions.satisfies("1.3.0", "~1.2.3"))
	assert_false(LibraryVersions.satisfies("1.2.2", "~1.2.3"))
	assert_true(LibraryVersions.satisfies("1.9.0", "~1"))
	assert_false(LibraryVersions.satisfies("2.0.0", "~1"))
	assert_true(LibraryVersions.satisfies("1.4.0", "1.4.0"))
	assert_false(LibraryVersions.satisfies("1.4.1", "1.4.0"))
	assert_true(LibraryVersions.satisfies("1.4.7", "1.4"), "a partial version matches its family")
	assert_false(LibraryVersions.satisfies("1.5.0", "1.4"))
	assert_true(LibraryVersions.satisfies("3.0.0", ">=2.5"))
	assert_false(LibraryVersions.satisfies("2.4.9", ">=2.5"))
	assert_true(LibraryVersions.satisfies("1.5.0", ">=1.0.0 <2.0.0"))
	assert_false(LibraryVersions.satisfies("2.0.0", ">=1.0.0 <2.0.0"))
	assert_true(LibraryVersions.satisfies("1.0.0", "<=1.0.0"))
	assert_false(LibraryVersions.satisfies("1.0.0", ">1.0.0"))
	assert_true(LibraryVersions.satisfies("1.0.0", "=1.0.0"))
	for any in ["*", "", "  "]:
		assert_true(LibraryVersions.satisfies("7.1.2", any), "'%s' accepts any version" % any)


func test_bad_ranges_and_versions_satisfy_nothing() -> void:
	assert_false(LibraryVersions.satisfies("not-a-version", "^1.0"))
	assert_false(LibraryVersions.satisfies("1.0.0", "^banana"))
	assert_false(LibraryVersions.satisfies("1.0.0", ">=1.0 &&"))
	assert_eq(LibraryVersions.range_problem("^1.0"), "")
	assert_eq(LibraryVersions.range_problem("*"), "")
	assert_ne(LibraryVersions.range_problem("^banana"), "")
	assert_ne(LibraryVersions.range_problem(">=1.0 &&"), "")
	assert_ne(LibraryVersions.range_problem("1".repeat(80)), "")
	assert_eq(LibraryVersions.describe("^1.0"), "^1.0")
	assert_eq(LibraryVersions.describe("*"), "any version")


# ---- LibraryResolver ----


func _entry(id: String, version: String, deps: Array = [], extra: Dictionary = {}) -> Dictionary:
	var out := {
		"id": id,
		"version": version,
		"source": "user",
		"folder": "user://libraries/" + id,
		"enabled": true,
		"read_ok": true,
		"reasons": [],
		"dependencies": deps,
	}
	out.merge(extra, true)
	return out


func _dep(id: String, version: String = "*") -> Dictionary:
	return {"id": id, "version": version}


func _resolve(entries: Array[Dictionary]) -> Dictionary:
	return LibraryResolver.resolve(entries, {"id": "core", "version": "1.0.0"})


func _order_ids(resolved: Dictionary) -> Array:
	return (resolved["order"] as Array).map(
		func(i: int) -> String: return resolved["entries"][i]["id"]
	)


func test_load_order_is_core_first_then_alphabetical_with_dependencies_before_dependents() -> void:
	var entries: Array[Dictionary] = [
		_entry("zebra", "1.0.0"),
		_entry("apple", "1.0.0", [_dep("zebra")]),
		_entry("core", "1.2.0", [], {"source": "official", "official": true}),
		_entry("mango", "1.0.0"),
	]
	# apple comes first alphabetically but needs zebra, which is laid just before it.
	assert_eq(_order_ids(_resolve(entries)), ["core", "zebra", "apple", "mango"])


func test_the_built_in_core_provides_core_when_no_folder_does() -> void:
	var entries: Array[Dictionary] = [_entry("alien", "0.1.0", [_dep("core", "^1.0")])]
	var resolved := _resolve(entries)
	assert_eq(resolved["entries"][0]["status"], "ok")
	assert_eq(resolved["entries"][0]["provides"], {"core": "built in"})
	var too_new: Array[Dictionary] = [_entry("alien", "0.1.0", [_dep("core", "^2.0")])]
	assert_eq(_resolve(too_new)["entries"][0]["status"], "error")


func test_a_broken_core_folder_falls_back_to_the_built_in_core() -> void:
	var entries: Array[Dictionary] = [
		_entry("core", "", [], {"source": "official", "read_ok": false, "reasons": ["bad"]}),
		_entry("alien", "0.1.0", [_dep("core", "^1.0")]),
	]
	var resolved := _resolve(entries)
	assert_eq(resolved["entries"][0]["status"], "error")
	assert_eq(resolved["entries"][1]["status"], "ok", "the game's own core still provides core")


func test_official_beats_user_and_the_first_folder_wins_among_users() -> void:
	var entries: Array[Dictionary] = [
		_entry("dup", "1.0.0", [], {"folder": "user://libraries/b"}),
		_entry("dup", "2.0.0", [], {"folder": "user://libraries/a"}),
		_entry("dup", "3.0.0", [], {"source": "official", "official": true}),
	]
	var resolved := _resolve(entries)
	assert_eq(resolved["entries"][2]["status"], "ok")
	assert_eq(resolved["entries"][0]["status"], "error")
	assert_eq(resolved["entries"][1]["status"], "error")
	assert_string_contains(resolved["entries"][0]["reasons"][0], "official library")
	var users: Array[Dictionary] = [
		_entry("dup", "1.0.0", [], {"folder": "user://libraries/b"}),
		_entry("dup", "2.0.0", [], {"folder": "user://libraries/a"}),
	]
	var among := _resolve(users)
	assert_eq(among["entries"][1]["status"], "ok", "folder a sorts first")
	assert_string_contains(among["entries"][0]["reasons"][0], "user://libraries/a")


func test_a_dev_entry_is_never_a_duplicate_and_is_laid_last() -> void:
	var entries: Array[Dictionary] = [
		_entry("core", "1.0.0", [], {"source": "dev", "folder": "D:/dev/x"}),
		_entry("core", "1.2.0", [], {"source": "official", "official": true}),
		_entry("beta", "1.0.0"),
	]
	var resolved := _resolve(entries)
	assert_eq(_order_ids(resolved), ["core", "beta", "core"])
	assert_eq(resolved["order"], [1, 2, 0], "the official core, beta, then the override")


func test_disabled_is_not_an_error_but_dependents_are() -> void:
	var entries: Array[Dictionary] = [
		_entry("base", "1.0.0", [], {"enabled": false}),
		_entry("top", "1.0.0", [_dep("base")]),
	]
	var resolved := _resolve(entries)
	assert_eq(resolved["entries"][0]["status"], "disabled")
	assert_eq(resolved["entries"][1]["status"], "error")
	assert_string_contains(resolved["entries"][1]["reasons"][0], "which is disabled")
	assert_eq(resolved["order"], [])


func test_a_read_error_keeps_a_library_out_with_its_reasons() -> void:
	var entries: Array[Dictionary] = [
		_entry("bad", "", [], {"read_ok": false, "reasons": ["library.json is missing or empty"]}),
		_entry("needs_bad", "1.0.0", [_dep("bad")]),
	]
	var resolved := _resolve(entries)
	assert_eq(resolved["entries"][0]["reasons"], ["library.json is missing or empty"])
	assert_string_contains(resolved["entries"][1]["reasons"][0], "unavailable")


func test_cycles_and_deep_chains_are_errors_not_hangs() -> void:
	var cycle: Array[Dictionary] = [
		_entry("a", "1.0.0", [_dep("b")]),
		_entry("b", "1.0.0", [_dep("c")]),
		_entry("c", "1.0.0", [_dep("a")]),
	]
	var resolved := _resolve(cycle)
	for entry in resolved["entries"]:
		assert_eq(entry["status"], "error", entry["id"])
	assert_eq(resolved["order"], [])
	var self_loop: Array[Dictionary] = [_entry("loop", "1.0.0", [_dep("loop")])]
	assert_eq(_resolve(self_loop)["entries"][0]["status"], "error")
	var chain: Array[Dictionary] = [_entry("l0", "1.0.0")]
	for i in range(1, 7):
		chain.append(_entry("l%d" % i, "1.0.0", [_dep("l%d" % (i - 1))]))
	var deep := _resolve(chain)
	assert_eq(deep["entries"][4]["status"], "ok", "four levels above a library with none")
	assert_eq(deep["entries"][5]["status"], "error")
	assert_eq(deep["entries"][6]["status"], "error")


func test_the_resolver_does_not_change_its_input() -> void:
	var entries: Array[Dictionary] = [_entry("x", "1.0.0", [_dep("ghost")])]
	var resolved := _resolve(entries)
	assert_eq(entries[0]["reasons"], [])
	assert_false(entries[0].has("status"))
	assert_eq(resolved["entries"][0]["status"], "error")


func test_sixteen_libraries_at_most() -> void:
	var entries: Array[Dictionary] = []
	for i in 18:
		entries.append(_entry("lib%02d" % i, "1.0.0"))
	var resolved := _resolve(entries)
	assert_eq((resolved["order"] as Array).size(), 16)
	assert_eq(resolved["entries"][16]["status"], "error")
	assert_eq(resolved["entries"][17]["status"], "error")
