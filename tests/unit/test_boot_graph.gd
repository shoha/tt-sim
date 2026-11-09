extends GutTest

## The start-up compiles every script the autoloads and the main scene name, and everything those
## name (perf audit boot, 2026-11-09): about 7.7 ms a script in an exported pack, nearly all of the
## time before the title. This walks that graph from the sources, as tools/boot_graph.gd does
## (class_name references with comments and strings stripped, preloads, extends paths, scene and
## resource ext_resources), and fails when it grows past LIMIT_SCRIPTS: a new class_name reference
## from start-up code to play, authoring or procgen code pulls its whole web into every launch.
## When it fails, run tools/boot_graph.gd (--show=<script> names who brought it in) and load the
## new part on first use (OnDemand, StructureProcgen) instead. When it shrinks, lower the limit.

## Measured 2026-11-09 after the boot cards' stages (812 at the start of the first card, 669 at
## the start of boot2). 341 after boot2's play, authoring and procgen cut: the start-up names no
## board token, game map, table (LevelPlayController), authoring editor or procgen evaluator,
## settlement, prop or ornament class; Root makes the table when a session or a map first needs it
## (Root._ensure_table), and StructureProcgen loads the procgen parts on the first build.
## 343 with IdleThrottle (sysidle): a 130-line Node Root adds after the title is up; LoadPacing and
## the Settings graphics helper name it, so it is in the graph (one script, no web behind it).
## 344 with GroundClipmapSetting (clipmap1): a 40-line constants class the Settings graphics helper
## names, kept apart so the clipmap's own scripts are not in the start-up graph.
const LIMIT_SCRIPTS := 344

var _classes: Dictionary = {}
var _strings := RegEx.create_from_string(
	"\"\"\"[\\s\\S]*?\"\"\"|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"
)
var _idents := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9_]*\\b")
var _preloads := RegEx.create_from_string("preload\\(\\s*\"([^\"]+)\"\\s*\\)")
var _extends := RegEx.create_from_string("(?m)^extends\\s+\"([^\"]+)\"")
var _ext_res := RegEx.create_from_string("\\[ext_resource[^\\]]*?path=\"([^\"]+)\"")


func test_the_start_up_script_graph_stays_within_its_limit() -> void:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_classes[String(entry["class"])] = String(entry["path"])
	var roots: Array[String] = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key := String(prop["name"])
		if key.begins_with("autoload/"):
			roots.append(_path(String(ProjectSettings.get_setting(key)).trim_prefix("*")))
	roots.append(_path(String(ProjectSettings.get_setting("application/run/main_scene"))))
	var seen := {}
	var stack: Array[String] = roots
	while not stack.is_empty():
		var at: String = stack.pop_back()
		if seen.has(at):
			continue
		seen[at] = true
		for dep in _deps(at):
			if not seen.has(dep):
				stack.append(dep)
	var scripts := seen.keys().filter(func(p: String) -> bool: return p.ends_with(".gd")).size()
	assert_gt(scripts, 100, "the walk found the autoloads' graph")
	assert_lte(
		scripts,
		LIMIT_SCRIPTS,
		(
			"the start-up now compiles %d scripts, over the limit of %d (measured 2026-11-09): see"
			+ " this file's header"
		)
		% [scripts, LIMIT_SCRIPTS]
	)
	gut.p("start-up script graph: %d scripts (limit %d)" % [scripts, LIMIT_SCRIPTS])


## BootPrecompile's roots exist and are listed once: a renamed script would make the worker skip
## its door silently, and the first map would compile it instead.
func test_the_precompile_roots_are_current() -> void:
	var seen := {}
	for path in BootPrecompile.ROOTS:
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		assert_false(seen.has(path), "%s is listed once" % path)
		seen[path] = true
	assert_true(seen.has("res://scenes/states/playing/game_map.tscn"), "the map scene is a root")
	assert_true(
		seen.has("res://scenes/states/authoring/authoring_controller.gd"), "authoring is a root"
	)


## A window close while the worker runs is held back (auto_accept_quit off), so the engine does not
## tear the scripts down under a compile (measured: an access violation on 5 of 6 early quits).
func test_a_close_request_waits_for_the_worker() -> void:
	var precompile := BootPrecompile.new()
	add_child_autofree(precompile)
	var release := Semaphore.new()
	precompile._thread = Thread.new()
	precompile._thread.start(func() -> void: release.wait())
	assert_true(get_tree().auto_accept_quit, "the engine quits on a close request by default")
	precompile.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var held := not get_tree().auto_accept_quit
	get_tree().auto_accept_quit = true
	assert_true(held, "the close request is held back while the worker runs")
	assert_true(precompile._stop, "and the worker is told to stop")
	release.post()
	precompile._thread.wait_to_finish()
	precompile.set_process(false)


## Settlement.KIND_NAMES copies procgen's list so the resource does not name ProcgenSettlement.
func test_settlement_kind_names_follow_procgen() -> void:
	assert_eq(Settlement.KIND_NAMES, ProcgenSettlement.NAMES, "the copy follows procgen's kits")


func _path(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else path
	return path


func _deps(path: String) -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	if path.ends_with(".gd"):
		for m in _preloads.search_all(text):
			out.append(_path(m.get_string(1)))
		for m in _extends.search_all(text):
			out.append(_path(m.get_string(1)))
		var lines := _strings.sub(text, "\"\"", true).split("\n")
		for i in lines.size():
			var hash_at := lines[i].find("#")
			if hash_at >= 0:
				lines[i] = lines[i].substr(0, hash_at)
		for m in _idents.search_all("\n".join(lines)):
			var target: String = _classes.get(m.get_string(), "")
			if target != "" and target != path:
				out.append(target)
	elif path.ends_with(".tscn") or path.ends_with(".tres"):
		for m in _ext_res.search_all(text):
			var dep := _path(m.get_string(1))
			if dep.get_extension() in ["gd", "tscn", "tres"]:
				out.append(dep)
	return out
