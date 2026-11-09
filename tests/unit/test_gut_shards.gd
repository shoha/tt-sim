extends GutTest

## The sharded test runner's pure parts (tools/gut_shards.gd): the scripts a config names, the
## longest-first dealing onto the lightest shard, the options and the committed weights table.

const Shards := preload("res://tools/gut_shards.gd")


func test_collect_scripts_finds_the_full_suite_sorted_without_repeats() -> void:
	var config := {
		"dirs": ["res://tests/unit/"],
		"include_subdirs": true,
		"prefix": "test_",
		"suffix": ".gd",
		"tests": ["res://tests/unit/test_gut_shards.gd"],
	}
	var scripts := Shards.collect_scripts(config)
	assert_gt(scripts.size(), 100)
	assert_true(scripts.has("res://tests/unit/test_gut_shards.gd"))
	var sorted := scripts.duplicate()
	sorted.sort()
	assert_eq(scripts, sorted, "sorted")
	var seen := {}
	for path in scripts:
		assert_false(seen.has(path), "%s once" % path)
		seen[path] = true
		assert_true(path.get_file().begins_with("test_") and path.ends_with(".gd"), path)


func test_partition_deals_every_script_once_longest_first_onto_the_lightest_shard() -> void:
	var scripts := PackedStringArray(["a", "b", "c", "d", "e", "f"])
	var times := {"a": 10.0, "b": 6.0, "c": 5.0, "d": 4.0, "e": 1.0, "f": 1.0}
	var shards := Shards.partition(scripts, times, 2)
	assert_eq(shards.size(), 2)
	# a (10) | b (6) c (5): b+c = 11 > a; then d to a (14), e and f to b+c (12, 13).
	assert_eq(shards[0].scripts, PackedStringArray(["a", "d"]))
	assert_eq(shards[1].scripts, PackedStringArray(["b", "c", "e", "f"]))
	assert_almost_eq(shards[0].weight, 14.0, 1e-6)
	assert_almost_eq(shards[1].weight, 13.0, 1e-6)


func test_partition_drops_empty_shards_and_weighs_unknown_scripts_at_the_star_entry() -> void:
	var shards := Shards.partition(PackedStringArray(["x", "y"]), {"*": 0.5}, 4)
	assert_eq(shards.size(), 2, "two scripts fill two shards")
	for shard: Dictionary in shards:
		assert_almost_eq(shard.weight, 0.5, 1e-6)
	var all := PackedStringArray()
	for shard: Dictionary in Shards.partition(PackedStringArray(["p", "q", "r"]), {}, 1):
		all.append_array(shard.scripts)
	assert_eq(all, PackedStringArray(["p", "q", "r"]), "one shard holds everything, sorted")


func test_parse_args_defaults_to_half_the_processors_capped() -> void:
	assert_eq(Shards.parse_args(PackedStringArray(), 24).shards, Shards.MAX_DEFAULT_SHARDS)
	assert_eq(Shards.parse_args(PackedStringArray(), 4).shards, 2)
	assert_eq(Shards.parse_args(PackedStringArray(), 1).shards, 1)
	var opts := Shards.parse_args(
		PackedStringArray(["-n=3", "-gconfig=tests/.gutconfig_ui.json", "--write-times"]), 24
	)
	assert_eq(opts.shards, 3)
	assert_eq(opts.config, "res://tests/.gutconfig_ui.json")
	assert_true(opts.write_times)
	assert_eq(Shards.parse_args(PackedStringArray(["-n=0"]), 24).shards, 1)


func test_committed_table_keeps_the_slow_scripts_and_weighs_the_rest_by_their_mean() -> void:
	var table := Shards.committed_table({"slow": 12.345, "edge": 1.0, "a": 0.2, "b": 0.4, "*": 9.0})
	assert_eq(table, {"slow": 12.3, "edge": 1.0, "*": 0.3})


func test_a_young_lock_file_is_live_and_an_old_or_unreadable_one_is_not() -> void:
	assert_true(Shards.lock_is_live("1000 4242", 1005.0), "five seconds old: another run is alive")
	assert_true(Shards.lock_is_live("1000 4242\n", 1000.0), "just written")
	assert_false(Shards.lock_is_live("1000 4242", 1000.0 + Shards.LOCK_LIVE_S), "a killed run's lock")
	assert_false(Shards.lock_is_live("1000 4242", 1500.0), "long stale")
	assert_false(Shards.lock_is_live("2000 4242", 1500.0), "dated in the future: a bad clock")
	assert_false(Shards.lock_is_live("", 1500.0), "empty")
	assert_false(Shards.lock_is_live("soon", 1500.0), "unreadable")


func test_a_shard_without_a_verdict_is_a_crash() -> void:
	var verdict := {"tests": 3}
	assert_false(Shards.crashed(0, false, verdict), "passed")
	assert_false(Shards.crashed(1, false, verdict), "GUT's own failure exit")
	assert_true(Shards.crashed(-1073741819, false, verdict), "an access violation")
	assert_true(Shards.crashed(0, true, verdict), "killed after the hang limit")
	assert_true(Shards.crashed(1, false, {}), "no JUnit file")


func test_the_log_tail_skips_blank_lines_and_keeps_the_last_ones() -> void:
	var text := "a\n\nb\r\n  \nc\nd\n"
	assert_eq(Shards.tail_lines(text, 2), PackedStringArray(["c", "d"]))
	assert_eq(Shards.tail_lines(text, 10), PackedStringArray(["a", "b", "c", "d"]))
	assert_eq(Shards.tail_lines("", 5), PackedStringArray())


func test_the_committed_table_names_existing_scripts() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Shards.COMMITTED_TIMES))
	assert_true(parsed is Dictionary, "tests/gut_times.json parses")
	if not parsed is Dictionary:
		return
	assert_true((parsed as Dictionary).has("*"))
	for path: String in parsed:
		if path != "*":
			assert_true(FileAccess.file_exists(path), "%s exists (refresh with --write-times)" % path)
