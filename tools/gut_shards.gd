extends SceneTree

## Runs a GUT config's scripts split across several Godot processes at once, for a full run
## in a fraction of the serial time:
##
##   godot --headless --path <project> --script res://tools/gut_shards.gd -- [-n=<shards>]
##       [-gconfig=<config, default tests/.gutconfig.json>] [--write-times]
##
## Each shard is an ordinary GUT command-line run on a disjoint list of scripts, with its own
## config, engine log and JUnit file under user://gut_shards/, and its own test data root
## (Paths.gut_data_root keys it by process id), so no two shards write the same store. The
## default shard count is half the logical processors, at most MAX_DEFAULT_SHARDS.
##
## Scripts are dealt longest first onto the shard with the least time so far. The weights are
## the per-script times of the last sharded run on this machine (user://gut_shards/times.json)
## or, on a clean machine such as CI, the committed table tests/gut_times.json, which lists the
## scripts of a second or more and weighs every other script at its "*" entry. `--write-times`
## rewrites that table from this run. Inside a shard the scripts keep the serial run's
## (alphabetical) order. One script never splits, so the longest script bounds the wall time.
##
## When every shard has exited, the runner prints one line per shard, each failing test with
## its first message, and the totals, then exits 1 when a shard failed, crashed or hung. A
## shard still running after HANG_S is killed and counts as failed. Killing the runner itself
## leaves its shards running: stop them by process id.

const OUT_DIR := "user://gut_shards/"
const TIMES_FILE := "user://gut_shards/times.json"
const COMMITTED_TIMES := "res://tests/gut_times.json"
const DEFAULT_CONFIG := "res://tests/.gutconfig.json"
const GUT_CMDLN := "res://addons/gut/gut_cmdln.gd"
const MAX_DEFAULT_SHARDS := 8
## The committed table names the scripts at or above this many seconds.
const COMMIT_MIN_S := 1.0
const POLL_S := 0.2
const POLL_FPS := 10
const HANG_S := 900.0
## Keys copied from the base config into every shard's config.
const CONFIG_KEYS := [
	"prefix", "suffix", "pre_run_script", "post_run_script", "log_level", "double_strategy"
]


func _initialize() -> void:
	# The runner only polls its shards: uncapped, its idle frames would spin a core.
	Engine.max_fps = POLL_FPS
	var opts := parse_args(OS.get_cmdline_user_args(), OS.get_processor_count())
	var base := _read_json(str(opts.config))
	if base.is_empty():
		printerr("gut_shards: cannot read the config %s" % opts.config)
		quit(2)
		return
	var scripts := collect_scripts(base)
	var times := _read_json(TIMES_FILE)
	if times.is_empty():
		times = _read_json(COMMITTED_TIMES)
	var shards := partition(scripts, times, int(opts.shards))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var start_ms := Time.get_ticks_msec()
	for i in shards.size():
		_start_shard(shards[i], i, base)
	await _wait_for(shards)
	var wall_s := (Time.get_ticks_msec() - start_ms) / 1000.0
	var ok := _report(shards, wall_s)
	var measured := {}
	for shard: Dictionary in shards:
		measured.merge(shard.get("result", {}).get("times", {}), true)
	_write_json(TIMES_FILE, times.merged(measured, true))
	if opts.write_times and ok:
		_write_json(COMMITTED_TIMES, committed_table(measured))
	quit(0 if ok else 1)


## The options after `--`: `-n=<shards>` (default half of `processors`, at most
## MAX_DEFAULT_SHARDS), `-gconfig=<path>` (a relative path is under res://) and
## `--write-times`.
static func parse_args(args: PackedStringArray, processors: int) -> Dictionary:
	var opts := {
		"shards": clampi(int(processors / 2.0), 1, MAX_DEFAULT_SHARDS),
		"config": DEFAULT_CONFIG,
		"write_times": false,
	}
	for arg in args:
		if arg.begins_with("-n="):
			opts.shards = maxi(1, int(arg.substr(3)))
		elif arg.begins_with("-gconfig="):
			var path := arg.substr(9)
			var absolute := path.contains("://") or path.is_absolute_path()
			opts.config = path if absolute else "res://" + path
		elif arg == "--write-times":
			opts.write_times = true
	return opts


## Every test script a GUT config names: its `tests` list and the matching files under its
## `dirs` (recursing when `include_subdirs` is set), sorted and without repeats.
static func collect_scripts(config: Dictionary) -> PackedStringArray:
	var found := {}
	for path in config.get("tests", []):
		found[str(path)] = true
	var prefix := str(config.get("prefix", "test_"))
	var suffix := str(config.get("suffix", ".gd"))
	var recurse := bool(config.get("include_subdirs", false))
	for dir in config.get("dirs", []):
		_scan(str(dir), prefix, suffix, recurse, found)
	var out := PackedStringArray(found.keys())
	out.sort()
	return out


static func _scan(dir: String, prefix: String, suffix: String, recurse: bool, found: Dictionary):
	for file in DirAccess.get_files_at(dir):
		if file.begins_with(prefix) and file.ends_with(suffix):
			found[dir.path_join(file)] = true
	if recurse:
		for sub in DirAccess.get_directories_at(dir):
			_scan(dir.path_join(sub), prefix, suffix, recurse, found)


## `scripts` dealt onto `count` shards, longest first onto the lightest shard, weighed by
## `times` (script path to seconds; a script it lacks weighs its "*" entry, else the median).
## Each shard is a dictionary with its sorted `scripts` and its total `weight`; empty shards
## are dropped.
static func partition(scripts: PackedStringArray, times: Dictionary, count: int) -> Array:
	var fallback := float(times.get("*", _median(times.values())))
	var weighted := []
	for path in scripts:
		weighted.append([float(times.get(path, fallback)), path])
	weighted.sort_custom(
		func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1])
	)
	var shards := []
	for i in maxi(1, count):
		shards.append({"scripts": PackedStringArray(), "weight": 0.0})
	for item in weighted:
		var best := 0
		for i in range(1, shards.size()):
			if shards[i].weight < shards[best].weight:
				best = i
		shards[best].scripts.append(item[1])
		shards[best].weight += item[0]
	var out := []
	for shard in shards:
		if not shard.scripts.is_empty():
			shard.scripts.sort()
			out.append(shard)
	return out


## The committed weights from a run's per-script `times`: each script at or above
## COMMIT_MIN_S to a tenth of a second, and "*", the mean of the rest to a hundredth.
static func committed_table(times: Dictionary) -> Dictionary:
	var table := {}
	var rest := 0.0
	var rest_count := 0
	for path in times:
		var seconds := float(times[path])
		if path == "*":
			continue
		if seconds >= COMMIT_MIN_S:
			table[path] = snappedf(seconds, 0.1)
		else:
			rest += seconds
			rest_count += 1
	table["*"] = snappedf(rest / maxi(rest_count, 1), 0.01)
	return table


static func _median(values: Array) -> float:
	if values.is_empty():
		return 1.0
	var sorted := values.map(func(v) -> float: return float(v))
	sorted.sort()
	return sorted[int(sorted.size() / 2.0)]


func _start_shard(shard: Dictionary, index: int, base: Dictionary) -> void:
	var config := {"dirs": [], "tests": Array(shard.scripts), "include_subdirs": false}
	for key in CONFIG_KEYS:
		if base.has(key):
			config[key] = base[key]
	config["should_exit"] = true
	config["should_exit_on_success"] = true
	var stem := ProjectSettings.globalize_path(OUT_DIR).path_join("shard_%d" % index)
	shard["config"] = stem + ".json"
	shard["log"] = stem + ".log"
	shard["junit"] = stem + ".xml"
	for path in [shard.log, shard.junit]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_write_json(shard.config, config)
	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--log-file",
			shard.log,
			"--script",
			GUT_CMDLN,
			"--",
			"-gconfig=" + shard.config,
			"-gjunit_xml_file=" + shard.junit,
		]
	)
	shard["start_ms"] = Time.get_ticks_msec()
	shard["pid"] = OS.create_process(OS.get_executable_path(), args)


## Wait until every shard has exited, recording each one's wall time; kill a hung one.
func _wait_for(shards: Array) -> void:
	while true:
		var running := 0
		for shard: Dictionary in shards:
			if shard.has("wall_s"):
				continue
			var elapsed := (Time.get_ticks_msec() - int(shard.start_ms)) / 1000.0
			if int(shard.pid) > 0 and OS.is_process_running(int(shard.pid)):
				if elapsed < HANG_S:
					running += 1
					continue
				OS.kill(int(shard.pid))
				shard["killed"] = true
			shard["wall_s"] = elapsed
			shard["exit"] = OS.get_process_exit_code(int(shard.pid))
		if running == 0:
			return
		await create_timer(POLL_S).timeout


## Print each shard's line, the failing tests and the totals; true when every shard passed.
func _report(shards: Array, wall_s: float) -> bool:
	var ok := true
	var totals := {"tests": 0, "failing": 0, "pending": 0, "asserts": 0}
	var failures := PackedStringArray()
	var summed_s := 0.0
	for i in shards.size():
		var shard: Dictionary = shards[i]
		var result := read_junit(str(shard.junit))
		shard["result"] = result
		summed_s += float(shard.wall_s)
		for key in totals:
			totals[key] += int(result.get(key, 0))
		failures.append_array(result.get("failures", PackedStringArray()))
		var killed: bool = shard.get("killed", false)
		var passed: bool = int(shard.exit) == 0 and not killed and result.has("tests")
		ok = ok and passed
		var line := (
			"shard %d: %d scripts, %d tests, %d failing, %d pending, %.1f s, exit %d"
			% [
				i + 1,
				shard.scripts.size(),
				int(result.get("tests", 0)),
				int(result.get("failing", 0)),
				int(result.get("pending", 0)),
				float(shard.wall_s),
				int(shard.exit),
			]
		)
		if killed:
			line += ", killed after %d s" % int(HANG_S)
		if not passed:
			line += ", log " + str(shard.log)
		print(line)
	for line in failures:
		print("FAILED " + line)
	print(
		(
			"gut_shards: %d tests, %d failing, %d pending, %d asserts; %s in %.1f s wall (%.1f s summed)"
			% [
				totals.tests,
				totals.failing,
				totals.pending,
				totals.asserts,
				"passed" if ok else "FAILED",
				wall_s,
				summed_s,
			]
		)
	)
	return ok


## A GUT JUnit file's counts (`tests`, `failing`, `pending`, `asserts`), its `failures` (one
## "script::test: message" line each) and its per-script `times`; empty when it is missing.
static func read_junit(path: String) -> Dictionary:
	var parser := XMLParser.new()
	if not FileAccess.file_exists(path) or parser.open(path) != OK:
		return {}
	var out := {
		"tests": 0,
		"failing": 0,
		"pending": 0,
		"asserts": 0,
		"failures": PackedStringArray(),
		"times": {},
	}
	var script := ""
	var test := ""
	var in_failure := false
	while parser.read() == OK:
		var kind := parser.get_node_type()
		if kind == XMLParser.NODE_ELEMENT:
			var tag := parser.get_node_name()
			in_failure = tag == "failure"
			if tag == "testsuite":
				script = "res://" + parser.get_named_attribute_value_safe("name")
				out.times[script] = float(parser.get_named_attribute_value_safe("time"))
			elif tag == "testcase":
				test = parser.get_named_attribute_value_safe("name")
				out.tests += 1
				out.asserts += int(parser.get_named_attribute_value_safe("assertions"))
				var status := parser.get_named_attribute_value_safe("status")
				if status == "fail":
					out.failing += 1
				elif status == "pending":
					out.pending += 1
		elif kind == XMLParser.NODE_CDATA and in_failure:
			var message := parser.get_node_data().strip_edges().replace("\n", " ")
			out.failures.append("%s::%s: %s" % [script, test, message.left(300)])
			in_failure = false
	return out


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t", true) + "\n")
