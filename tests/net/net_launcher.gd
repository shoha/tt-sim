extends Node

## Runs one multi-process ENet scenario (tests/net/<scenario>.tscn) with N peers on this
## machine and exits 0 only when every peer passed and the real user's data is untouched.
## One command form serves every scenario, so it is allowlisted once:
##
##   godot --headless --path D:/dev/tt-sim res://tests/net/net_launcher.tscn --
##     --data-root=net_launcher --scenario=<name> [--peers=2] [--timeout-s=180] [--port=28471]
##
## Peer 0 is the host (--role=host), peer 1 "client", peer i >= 2 "client<i>". Each is its
## own headless Godot process started with the scenario's args (--role, --rendezvous, --out,
## --timeout-s, --port), its own test data root (--data-root=net_<scenario>_<role>, see
## Paths) and its own engine log (--log-file), so no two processes share a store and none
## writes the real user's. The launcher needs a --data-root of its own for the same reason
## (its autoloads start before it runs) and refuses to start peers without one.
##
## Logs stay in .godot/net_runs/<scenario>/ (gitignored; the next run of that scenario
## replaces them): <role>.log is the scenario's log ending in its NET_RESULT line,
## <role>.godot.log the engine's, rv.* the rendezvous files. The launcher prints each peer's
## NET_RESULT and ends with one `NET_LAUNCH {json}` line.
##
## Before the peers start it records the modification time of every file in the shipped
## stores (watched_stores(): Paths.store_paths("user://") and the import source index). The run
## fails when a file that existed then was modified or deleted by the end, or when a new file
## or folder appeared under a store in NEVER_WRITTEN. Other new files and folders (a render
## job from another session creating and deleting its test level in the real user://levels/,
## say) are only reported, as `shipped_files_added`. Peers still running GRACE_S after the
## scenario timeout are killed, and all of them at once when a peer has not opened its scenario
## log STARTUP_S after the start. Every test root of the run, the launcher's own included, is
## deleted at the end, pass or fail.

const SCENARIO_DIR := "res://tests/net/"
const RUNS_DIR := "res://.godot/net_runs/"
const DEFAULT_PEERS := 2
const MAX_PEERS := 8
const DEFAULT_TIMEOUT_S := 180
const DEFAULT_PORT := 28471
## Time the peers get past the scenario timeout to write their result and quit
const GRACE_S := 30.0
## Time a peer gets to open its scenario log. A scenario script that fails to parse leaves a
## bare scene that never quits, so a peer still without a log by then fails the run at once
## (its <role>.godot.log holds the parse error) instead of burning CPU until the timeout.
const STARTUP_S := 60.0
const POLL_S := 0.25
## Gap between starting the host and each client, so the host's port is open first
const CLIENT_START_DELAY_S := 0.5
## How deep the store snapshot looks into a store folder (user://levels/<level>/<file> is 2)
const SNAPSHOT_DEPTH := 4
## The stores (keys of watched_stores()) a new file or folder fails the run in. Every peer has
## a root of its own for them, and nothing but a peer with a store left pointing at user://
## (or the user's own game, which should not run during a launch) writes them while a run
## goes. The others are written by other sessions' render jobs and probes at any time: levels
## (test levels), avatars, perf logs, settings and the import source index. A change to a file
## that existed before the run fails in every store.
const NEVER_WRITTEN := [
	"ASSET_CACHE_DIR", "ASSET_CACHE_INDEX_PATH", "USER_ASSETS_DIR", "UPDATES_DIR"
]
## Files one worker-thread task stats
const STAT_CHUNK := 512
## How many new paths the report lists (the count is always given)
const ADDED_SAMPLE := 10

var _args: Dictionary = {}
var _report: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		var eq := s.find("=")
		if s.begins_with("--") and eq > 0:
			_args[s.substr(2, eq - 2)] = s.substr(eq + 1)
	var ok := await _run()
	_report["pass"] = ok
	print("NET_LAUNCH " + JSON.stringify(_report))
	get_tree().quit(0 if ok else 1)


## Start the peers, wait for them, check their results and the shipped stores, and delete
## the run's test roots. True on a pass.
func _run() -> bool:
	var scenario := str(_args.get("scenario", ""))
	_report["scenario"] = scenario
	var scene := SCENARIO_DIR + scenario + ".tscn"
	if scenario == "" or not scenario.is_valid_identifier() or not ResourceLoader.exists(scene):
		return _fail("no scenario %s (pass --scenario=<name> of a tests/net/*.tscn)" % scene)
	if Paths.DATA_ROOT == Paths.SHIPPED_DATA_ROOT:
		return _fail("the launcher needs its own test root: pass --data-root=net_launcher")
	var peer_count := clampi(int(_args.get("peers", DEFAULT_PEERS)), 2, MAX_PEERS)
	var timeout_s := int(_args.get("timeout-s", DEFAULT_TIMEOUT_S))
	var logs := ProjectSettings.globalize_path(RUNS_DIR + scenario + "/")
	_clear_folder(logs)
	var peers: Array[Dictionary] = []
	for i in peer_count:
		var role := "host" if i == 0 else ("client" if i == 1 else "client%d" % i)
		var root_name := "net_%s_%s" % [scenario, role]
		peers.append(
			{
				"role": role,
				"root_name": root_name,
				"root": Paths.test_data_root(root_name),
				"out": logs + role + ".log",
				"engine_log": logs + role + ".godot.log",
			}
		)
	for peer in peers:
		Paths.remove_test_data_root(peer.root)
	var snapshot_start_ms := Time.get_ticks_msec()
	var before := _snapshot_stores()
	_report["shipped_files_watched"] = before.size()
	_report["shipped_snapshot_ms"] = Time.get_ticks_msec() - snapshot_start_ms
	var common := [
		"--rendezvous=" + logs + "rv",
		"--timeout-s=%d" % timeout_s,
		"--port=%d" % int(_args.get("port", DEFAULT_PORT)),
	]
	var started := true
	for peer in peers:
		if peer.role != "host":
			await get_tree().create_timer(CLIENT_START_DELAY_S).timeout
		peer["pid"] = _start_peer(scene, peer, common)
		started = started and int(peer.pid) > 0
		print("net_launcher: %s started (pid %d)" % [peer.role, peer.pid])
	# A peer that failed to start fails the run; the others are stopped at once.
	await _wait_for(peers, timeout_s + GRACE_S if started else 0.0)
	var ok := _collect(peers) and started
	var changes := compare_snapshots(before, _snapshot_stores(), never_written_paths())
	var failed := failed_changes(changes)
	_report["shipped_files_changed"] = failed
	var added: Array = changes.added
	_report["shipped_files_added"] = added.size()
	if not added.is_empty():
		_report["shipped_files_added_sample"] = added.slice(0, ADDED_SAMPLE)
		print("net_launcher: %d new paths in the shipped stores (not a failure)" % added.size())
	ok = ok and failed.is_empty()
	_report["logs"] = logs
	_report["test_roots_removed"] = _remove_roots(peers)
	return ok


func _fail(reason: String) -> bool:
	_report["reason"] = reason
	push_error("net_launcher: " + reason)
	return false


## Start one peer process; its pid, or -1.
func _start_peer(scene: String, peer: Dictionary, common: Array) -> int:
	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--log-file",
			peer.engine_log,
			scene,
			"--",
			"--role=" + str(peer.role),
			"--out=" + str(peer.out),
			"--data-root=" + str(peer.root_name),
		]
	)
	args.append_array(common)
	return OS.create_process(OS.get_executable_path(), args)


## Wait until every started peer has exited or `limit_s` has passed, then kill the rest. A
## peer that has not opened its scenario log STARTUP_S after the start ends the wait early.
func _wait_for(peers: Array[Dictionary], limit_s: float) -> void:
	var start_ms := Time.get_ticks_msec()
	var deadline_ms := start_ms + int(limit_s * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		var running := peers.filter(func(p: Dictionary) -> bool: return _running(p))
		if running.is_empty():
			return
		if Time.get_ticks_msec() - start_ms > int(STARTUP_S * 1000.0):
			var silent := running.filter(
				func(p: Dictionary) -> bool: return not FileAccess.file_exists(str(p.out))
			)
			if not silent.is_empty():
				_report["reason"] = (
					"%s never started its scenario in %d s; see its .godot.log"
					% [silent[0].role, int(STARTUP_S)]
				)
				print("net_launcher: " + str(_report.reason))
				break
		await get_tree().create_timer(POLL_S).timeout
	var waited_s := (Time.get_ticks_msec() - start_ms) / 1000.0
	for peer in peers:
		if _running(peer):
			OS.kill(int(peer.pid))
			peer["killed"] = true
			print("net_launcher: killed %s (pid %d) after %.0f s" % [peer.role, peer.pid, waited_s])


func _running(peer: Dictionary) -> bool:
	return int(peer.get("pid", -1)) > 0 and OS.is_process_running(int(peer.pid))


## Each peer's exit code and NET_RESULT into the report; true when all of them passed.
func _collect(peers: Array[Dictionary]) -> bool:
	var ok := true
	var results := {}
	for peer in peers:
		var exit_code := OS.get_process_exit_code(int(peer.pid))
		var result := _net_result(str(peer.out))
		print("net_launcher: %s exit %d NET_RESULT %s" % [peer.role, exit_code, str(result)])
		results[peer.role] = {
			"exit": exit_code,
			"killed": peer.get("killed", false),
			"pass": bool(result.get("pass", false)),
			"reason": str(result.get("reason", "no NET_RESULT")),
		}
		ok = ok and exit_code == 0 and bool(result.get("pass", false))
		ok = ok and not peer.get("killed", false)
	_report["peers"] = results
	return ok


## The last NET_RESULT {json} line of a scenario log, or {}.
static func _net_result(log_path: String) -> Dictionary:
	if not FileAccess.file_exists(log_path):
		return {}
	var result := {}
	for line in FileAccess.get_file_as_string(log_path).split("\n"):
		var at := line.find("NET_RESULT ")
		if at >= 0:
			var parsed: Variant = JSON.parse_string(line.substr(at + "NET_RESULT ".length()))
			result = parsed if parsed is Dictionary else {}
	return result


## Every store the run watches, by key: Paths.store_paths() of the shipped root plus the
## import source index, which lives beside them and which Paths does not list as a store.
## Always the shipped root (the launcher's own data root is a test root).
static func watched_stores() -> Dictionary:
	var stores := Paths.store_paths(Paths.SHIPPED_DATA_ROOT)
	stores["IMPORT_SOURCES_PATH"] = Paths.SHIPPED_DATA_ROOT + Paths.IMPORT_SOURCES_NAME
	return stores


## The paths of the stores in NEVER_WRITTEN (folders end in "/").
static func never_written_paths() -> Array:
	var stores := watched_stores()
	var paths := []
	for key in NEVER_WRITTEN:
		paths.append(stores[key])
	return paths


## Every file and folder in the shipped stores -> its modification time (0 for a folder). The
## listing is a tenth of the cost (31,000 files take 0.13 s) and the stat of each file the rest
## (2.1 s one after the other), so the stats run on the worker threads (0.33 s).
static func _snapshot_stores() -> Dictionary:
	var folders := []
	var files := []
	var stores := watched_stores()
	for key in stores:
		var path: String = stores[key]
		if path.ends_with("/"):
			_list_folder(path, folders, files, SNAPSHOT_DEPTH)
		elif FileAccess.file_exists(path):
			files.append(path)
	var times := modified_times(files)
	var snapshot := {}
	for folder in folders:
		snapshot[folder] = 0
	for i in files.size():
		# A file that vanished since the listing has no time, and is left out.
		if times[i] != 0:
			snapshot[files[i]] = times[i]
	return snapshot


## Append `folder` to `folders` and its files to `files`, then do the same for each folder in
## it down `depth` more levels.
static func _list_folder(folder: String, folders: Array, files: Array, depth: int) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	folders.append(folder)
	for file_name in dir.get_files():
		files.append(folder + file_name)
	if depth > 0:
		for sub in dir.get_directories():
			_list_folder(folder + sub + "/", folders, files, depth - 1)


## The modification time of each of `paths`, in order (0 for a file that is gone), taken in
## chunks on the worker threads. Each chunk writes only its own slots of `times`.
static func modified_times(paths: Array) -> Array:
	var times := []
	times.resize(paths.size())
	var chunks := ceili(paths.size() / float(STAT_CHUNK))
	if chunks > 0:
		var task := WorkerThreadPool.add_group_task(_stat_chunk.bind(paths, times), chunks)
		WorkerThreadPool.wait_for_group_task_completion(task)
	return times


static func _stat_chunk(chunk: int, paths: Array, times: Array) -> void:
	var from := chunk * STAT_CHUNK
	for i in range(from, mini(from + STAT_CHUNK, paths.size())):
		times[i] = FileAccess.get_modified_time(paths[i])


## What happened to the watched paths between two snapshots, in four lists of paths:
## `modified` and `deleted` are files that existed in `before` (a folder that went away is not
## listed; the files in it are), `added` is every new file or folder, and `added_never_written`
## is the part of that under or equal to a path of `never_written` (a folder ends in "/").
static func compare_snapshots(
	before: Dictionary, after: Dictionary, never_written: Array = []
) -> Dictionary:
	var changes := {"modified": [], "deleted": [], "added": [], "added_never_written": []}
	for path in before:
		if int(before[path]) == 0:
			continue
		if not after.has(path):
			changes.deleted.append(path)
		elif after[path] != before[path]:
			changes.modified.append(path)
	for path in after:
		if before.has(path):
			continue
		if _under_any(path, never_written):
			changes.added_never_written.append(path)
		else:
			changes.added.append(path)
	return changes


## What fails the run in `changes` (compare_snapshots()): each modified or deleted file and
## each new path in a never-written store, as "<kind> <path>".
static func failed_changes(changes: Dictionary) -> Array:
	var failed := []
	for kind in ["modified", "deleted"]:
		for path in changes[kind]:
			failed.append("%s %s" % [kind, path])
	for path in changes.added_never_written:
		failed.append("added %s" % path)
	return failed


## True when `path` is one of `stores` or, for a folder store (ending in "/"), inside it.
static func _under_any(path: String, stores: Array) -> bool:
	for store: String in stores:
		if path == store or (store.ends_with("/") and path.begins_with(store)):
			return true
	return false


## Delete every test root of the run, the launcher's own last. True when all are gone.
func _remove_roots(peers: Array[Dictionary]) -> bool:
	var ok := true
	for peer in peers:
		ok = Paths.remove_test_data_root(peer.root) and ok
	return Paths.remove_test_data_root(Paths.DATA_ROOT) and ok


## Empty an absolute folder of the files a previous run left there, creating it if needed.
static func _clear_folder(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var dir := DirAccess.open(folder)
	for file_name in dir.get_files():
		dir.remove(file_name)
