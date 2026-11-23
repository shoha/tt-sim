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


func test_order_reverses_or_rotates_a_shard_and_defaults_to_alphabetical() -> void:
	var scripts := PackedStringArray(["a", "b", "c", "d", "e"])
	assert_eq(Shards.ordered(scripts, Shards.ORDER_ALPHABETICAL), scripts)
	assert_eq(Shards.ordered(scripts, "nonsense"), scripts, "an unknown name changes nothing")
	assert_eq(
		Shards.ordered(scripts, Shards.ORDER_REVERSE), PackedStringArray(["e", "d", "c", "b", "a"])
	)
	assert_eq(
		Shards.ordered(scripts, Shards.ORDER_ROTATED), PackedStringArray(["c", "d", "e", "a", "b"])
	)
	assert_eq(Shards.parse_args(PackedStringArray(["--order=reverse"]), 4).order, "reverse")
	assert_eq(Shards.parse_args(PackedStringArray(), 4).order, Shards.ORDER_ALPHABETICAL)


func test_a_part_runs_every_kth_shard_of_one_deal() -> void:
	var opts := Shards.parse_args(PackedStringArray(["-n=2", "--part=2/2", "--slowest=5"]), 4)
	assert_eq([opts.part, opts.parts, opts.slowest], [2, 2, 5])
	for bad in ["--part=3/2", "--part=0/2", "--part=x", "--part=1/0"]:
		var plain := Shards.parse_args(PackedStringArray([bad]), 4)
		assert_eq([plain.part, plain.parts], [1, 1], bad + " runs everything")
	var times := {"a": 8.0, "b": 7.0, "c": 6.0, "d": 5.0, "e": 1.0, "f": 1.0}
	var dealt := Shards.partition(PackedStringArray(times.keys()), times, 4)
	var seen := PackedStringArray()
	var weights := []
	for part in [1, 2]:
		var weight := 0.0
		for shard: Dictionary in Shards.part_of(dealt, part, 2):
			seen.append_array(shard.scripts)
			weight += shard.weight
		weights.append(weight)
	seen.sort()
	assert_eq(seen, PackedStringArray(["a", "b", "c", "d", "e", "f"]), "the parts cover the deal once")
	# Shards 8, 7, 7 and 6: part 1 takes the first and third, part 2 the second and fourth.
	assert_eq(weights, [15.0, 13.0], "and weigh about the same")
	assert_eq(Shards.part_of(dealt, 1, 1), dealt, "one part is everything")


func test_slowest_lists_the_heaviest_scripts_first() -> void:
	var lines := Shards.slowest({"a": 1.0, "b": 30.5, "c": 2.25}, 2)
	assert_eq(lines.size(), 3, "a heading and two scripts")
	assert_true(lines[1].ends_with("b") and lines[1].contains("30.5"), lines[1])
	assert_true(lines[2].ends_with("c"), lines[2])
	assert_eq(Shards.slowest({"a": 1.0}, 0), PackedStringArray(), "off by default")


func test_timing_budget_scales_by_a_factor_of_at_least_one() -> void:
	var factor := TimingBudget.factor()
	assert_between(factor, 1.0, TimingBudget.MAX_FACTOR)
	assert_almost_eq(TimingBudget.limit(10.0), 10.0 * factor, 1e-6)
	assert_gt(TimingBudget.calibration_ms(), 0.0)
	assert_eq(TimingBudget.calibration_ms(), TimingBudget.calibration_ms(), "measured once")
	gut.p("TimingBudget %s" % TimingBudget.describe(10.0))


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
