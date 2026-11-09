extends GutTest

## The start-up compiles every script the autoloads and the main scene name, and everything those
## name (perf audit boot, 2026-11-09): about 7.7 ms a script in an exported pack, nearly all of the
## time before the title. This walks that graph from the sources, as tools/boot_graph.gd does
## (class_name references with comments and strings stripped, preloads, extends paths, scene and
## resource ext_resources), and fails when it grows past LIMIT_SCRIPTS: a new class_name reference
## from start-up code to play, authoring or procgen code pulls its whole web into every launch.
## When it fails, run tools/boot_graph.gd (--show=<script> names who brought it in) and load the
## new part on first use (OnDemand, StructureProcgen) instead. When it shrinks, lower the limit.

## Measured 2026-11-09 after the boot card's stages (812 at the start of the card). 669 since the
## gpuoptions card: shadow_cascades.gd, foliage_edges.gd and settings_gpu_options.gd apply a saved
## setting when a map's environment is built, so they are start-up code, not first-use code.
const LIMIT_SCRIPTS := 669

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
