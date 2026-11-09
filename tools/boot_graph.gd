extends SceneTree

## The static script graph the game compiles before its first frame (perf audit boot, 2026-11-09).
##
## GDScript compiles every script a script names before the script itself is usable: a global
## class_name anywhere in its code (type hints and `is` checks included), a `preload`, an
## `extends`, and every script a preloaded scene or resource refers to. The autoloads and the main
## scene are loaded before the first frame, so their whole closure is compiled at start-up, on the
## main thread, whether or not the title needs it.
##
## This tool reads the sources (comments and strings stripped, so a class named only in a doc
## comment is not an edge), builds that graph and prints:
## - per root (each autoload in project order, then the main scene) the scripts it adds and their
##   source size, a proxy for compile time;
## - the scripts whose removal from the boot graph drops the most source (the script itself plus
##   everything only it reaches), with the boot scripts that name it: those are the edges to cut.
##
## godot --headless --path <project> --script res://tools/boot_graph.gd [-- --top=30 --show=<path>]
## `--show=<res path>` lists every boot script that names that one, and a shortest chain from a
## root to it.

const SCAN_DIRS: Array[String] = [
	"res://autoloads",
	"res://scenes",
	"res://utils",
	"res://resources",
	"res://procgen",
	"res://addons",
	"res://themes",
]

var _class_paths: Dictionary = {}  # class_name -> res path
var _edges: Dictionary = {}  # res path -> Array[String] of res paths
var _sizes: Dictionary = {}  # res path -> bytes (scripts only; other resources 0)
var _string_re := RegEx.new()
var _ident_re := RegEx.new()
var _preload_re := RegEx.new()
var _extends_path_re := RegEx.new()
var _ext_res_re := RegEx.new()


func _initialize() -> void:
	_string_re.compile("\"\"\"[\\s\\S]*?\"\"\"|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'")
	_ident_re.compile("\\b[A-Z][A-Za-z0-9_]*\\b")
	_preload_re.compile("preload\\(\\s*\"([^\"]+)\"\\s*\\)")
	_extends_path_re.compile("^extends\\s+\"([^\"]+)\"")
	_ext_res_re.compile("\\[ext_resource[^\\]]*?path=\"([^\"]+)\"")
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_class_paths[String(entry["class"])] = String(entry["path"])
	var args := _user_args()
	var top := int(args.get("top", "30"))
	var roots := _roots()
	for root in roots:
		_visit(root)
	if args.has("cut"):
		_apply_cuts(String(args["cut"]))
	_report(roots, top)
	if args.has("show"):
		for target in String(args["show"]).split(","):
			_show(roots, target)
	if args.has("deps"):
		_deps(roots, String(args["deps"]))
	if args.has("fence"):
		_fence(roots, String(args["fence"]).split(","))
	quit(0)


## `--fence=res://procgen/,res://scenes/states/authoring/` walks the boot graph without
## entering those folders and prints what is left plus every edge that crosses the fence: the
## references to turn into on-demand loads for the fenced code to leave the start-up.
func _fence(roots: Array[String], prefixes: PackedStringArray) -> void:
	var fenced := func(p: String) -> bool:
		for prefix in prefixes:
			if p.begins_with(prefix):
				return true
		return false
	var seen := {}
	var stack: Array[String] = roots.duplicate()
	var crossings: Dictionary = {}  # from -> Array of to
	while not stack.is_empty():
		var p: String = stack.pop_back()
		if seen.has(p):
			continue
		seen[p] = true
		for d: String in _edges.get(p, []):
			if fenced.call(d):
				if not crossings.has(p):
					crossings[p] = []
				crossings[p].append(d.get_file())
			elif not seen.has(d):
				stack.append(d)
	var n_edges := 0
	for p: String in crossings:
		n_edges += (crossings[p] as Array).size()
	print("\n-- fenced: %d scripts (%.0f KB) left, %d edges from %d scripts cross --" % [
		_scripts(seen), _kb(seen), n_edges, crossings.size()])
	var keys: Array = crossings.keys()
	keys.sort()
	for p: String in keys:
		print("  %s -> %s" % [p, ", ".join(crossings[p])])


## `--cut=a.gd>b.gd;c.gd>*` removes edges (file names, `*` for every edge out of a file) to
## see what the boot graph would be without them, before changing any code.
func _apply_cuts(spec: String) -> void:
	for pair in spec.split(";"):
		var ends := pair.split(">")
		if ends.size() != 2:
			continue
		for p: String in _edges:
			if p.get_file() != ends[0]:
				continue
			var kept: Array[String] = []
			for d: String in _edges[p]:
				if ends[1] != "*" and d.get_file() != ends[1]:
					kept.append(d)
			_edges[p] = kept


## The direct dependencies of `path`, each with how many boot scripts only it brings in.
func _deps(roots: Array[String], path: String) -> void:
	var full := _reach(roots, "")
	print("\n-- direct deps of %s (scripts reached through it alone if the edge were cut) --" % path)
	var rows: Array = []
	for d: String in _edges.get(path, []):
		var saved: Array[String] = _edges[path].duplicate()
		var kept: Array[String] = []
		for x: String in saved:
			if x != d:
				kept.append(x)
		_edges[path] = kept
		var without := _reach(roots, "")
		_edges[path] = saved
		rows.append([_scripts(full) - _scripts(without), _scripts(_reach([d], "")), d])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	for row: Array in rows:
		print("  drop %3d  closure %3d  %s" % [row[0], row[1], row[2]])


func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else "1"
	return out


## The autoloads in project order, then the main scene.
func _roots() -> Array[String]:
	var out: Array[String] = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key := String(prop["name"])
		if key.begins_with("autoload/"):
			out.append(_res_path(String(ProjectSettings.get_setting(key)).trim_prefix("*")))
	out.append(_res_path(String(ProjectSettings.get_setting("application/run/main_scene"))))
	return out


func _res_path(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else path
	return path


func _visit(path: String) -> void:
	var stack: Array[String] = [path]
	while not stack.is_empty():
		var p: String = stack.pop_back()
		if _edges.has(p):
			continue
		var deps := _deps_of(p)
		_edges[p] = deps
		for d in deps:
			if not _edges.has(d):
				stack.append(d)


func _deps_of(path: String) -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	if path.ends_with(".gd"):
		_sizes[path] = text.length()
		for m in _preload_re.search_all(text):
			_add(out, _res_path(m.get_string(1)))
		for line in text.split("\n"):
			var em := _extends_path_re.search(line)
			if em:
				_add(out, _res_path(em.get_string(1)))
		var code := _strip(text)
		var self_path := path
		for m in _ident_re.search_all(code):
			var target: String = _class_paths.get(m.get_string(), "")
			if not target.is_empty() and target != self_path:
				_add(out, target)
	elif path.ends_with(".tscn") or path.ends_with(".tres"):
		_sizes[path] = 0
		for m in _ext_res_re.search_all(text):
			var dep := _res_path(m.get_string(1))
			if dep.ends_with(".gd") or dep.ends_with(".tscn") or dep.ends_with(".tres"):
				_add(out, dep)
	else:
		_sizes[path] = 0
	return out


func _add(out: Array[String], dep: String) -> void:
	if not dep.is_empty() and not out.has(dep):
		out.append(dep)


## Source with string literals and comments removed (preloads were read before).
func _strip(text: String) -> String:
	var no_strings := _string_re.sub(text, "\"\"", true)
	var lines := no_strings.split("\n")
	for i in lines.size():
		var hash_at := lines[i].find("#")
		if hash_at >= 0:
			lines[i] = lines[i].substr(0, hash_at)
	return "\n".join(lines)


func _reach(roots: Array[String], skip: String) -> Dictionary:
	var seen := {}
	var stack: Array[String] = []
	for r in roots:
		if r != skip:
			stack.append(r)
	while not stack.is_empty():
		var p: String = stack.pop_back()
		if seen.has(p):
			continue
		seen[p] = true
		for d: String in _edges.get(p, []):
			if d != skip and not seen.has(d):
				stack.append(d)
	return seen


func _kb(paths: Dictionary) -> float:
	var total := 0
	for p: String in paths:
		total += int(_sizes.get(p, 0))
	return total / 1024.0


func _scripts(paths: Dictionary) -> int:
	var n := 0
	for p: String in paths:
		if p.ends_with(".gd"):
			n += 1
	return n


func _report(roots: Array[String], top: int) -> void:
	var all_scripts := {}
	for dir in SCAN_DIRS:
		_collect(dir, all_scripts)
	var full := _reach(roots, "")
	print("boot_graph: %d of %d scripts (%.0f of %.0f KB source) are in the boot graph" % [
		_scripts(full), all_scripts.size(), _kb(full), _kb_of_files(all_scripts)])
	print("\n-- per root (new scripts, KB) --")
	var seen := {}
	for r in roots:
		var mine := _reach([r], "")
		var fresh := {}
		for p: String in mine:
			if not seen.has(p):
				fresh[p] = true
				seen[p] = true
		print("  %-58s %4d  %7.1f" % [r, _scripts(fresh), _kb(fresh)])
	print("\n-- scripts whose removal drops the most (KB, scripts, named by) --")
	var rows: Array = []
	var full_kb := _kb(full)
	for p: String in full:
		if roots.has(p) or not (p.ends_with(".gd") or p.ends_with(".tscn")):
			continue
		var without := _reach(roots, p)
		rows.append([full_kb - _kb(without), _scripts(full) - _scripts(without), p])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in mini(top, rows.size()):
		var row: Array = rows[i]
		var by := _referrers(full, row[2])
		print("  %7.1f %4d  %s  <- %s" % [row[0], row[1], row[2], ", ".join(by.slice(0, 6))])


func _referrers(within: Dictionary, target: String) -> Array[String]:
	var out: Array[String] = []
	for p: String in within:
		if (_edges.get(p, []) as Array).has(target):
			out.append(p.get_file())
	return out


func _show(roots: Array[String], target: String) -> void:
	var full := _reach(roots, "")
	print("\n-- %s --\nnamed by: %s" % [target, ", ".join(_referrers(full, target))])
	var prev := {}
	var queue: Array[String] = roots.duplicate()
	for r in roots:
		prev[r] = ""
	while not queue.is_empty():
		var p: String = queue.pop_front()
		if p == target:
			break
		for d: String in _edges.get(p, []):
			if not prev.has(d):
				prev[d] = p
				queue.append(d)
	var chain: Array[String] = []
	var at := target
	while prev.has(at) and not at.is_empty():
		chain.push_front(at.get_file())
		at = prev[at]
	print("chain: %s" % " > ".join(chain))


func _collect(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out[dir.path_join(f)] = true
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), out)


func _kb_of_files(paths: Dictionary) -> float:
	var total := 0
	for p: String in paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f:
			total += f.get_length()
	return total / 1024.0
