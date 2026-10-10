extends RefCounted

## Theme-bypass counts for the UI ratchet (docs/UI_TASTE.md; the GUT test
## tests/unit/test_ui_theme_bypass.gd and the baseline writer bypass_baseline.gd beside this
## file). For every .gd and .tscn file under SCAN_ROOTS, three counts:
## - `colour`: `Color(` literals, a colour picked in place of a ThemeColors role (C1, C4).
##   `Color.from_*`, `Color.WHITE` and role reads do not count.
## - `override`: `add_theme_*_override(` calls in scripts and `theme_override_*/` properties
##   in scenes, a value set on one control instead of in the theme (G7, S1).
## - `font_size`: a font size written as a number (T1, T2): the size argument of
##   add_theme_font_size_override, a `font_size =` assignment (LabelSettings), and a scene's
##   `theme_override_font_sizes/*` or `font_size` property. A size read from a constant does
##   not count here (it still counts as an override).
## Full-line script comments are skipped. SKIPPED_DIRS hold 3D-only code, whose colours are
## materials and gizmos rather than UI (C1's exemption). The baseline is
## {"files": {path: {rule: count}}}; a count may fall, never rise.
##
## Some rules and review methods here are adapted from Impeccable by Paul Bakaus
## (https://github.com/pbakaus/impeccable), Apache License 2.0.

const SCAN_ROOTS: Array[String] = ["res://scenes", "res://autoloads"]
## Directories left out, each with its reason.
const SKIPPED_DIRS := {
	"res://scenes/maps": "built-in map scenes: 3D materials",
	"res://scenes/terrain": "ground, water and skirt materials",
	"res://scenes/effects": "particles and weather",
	"res://scenes/board_token": "token materials, the selection glow and 3D markers",
}
const BASELINE_PATH := "res://tests/ui_bypass_baseline.json"
const RULES: Array[String] = ["colour", "override", "font_size"]
const ABOUT := (
	"Theme-bypass ratchet baseline: per file, today's count of each rule (colour literals,"
	+ " theme overrides, literal font sizes). A count may only fall."
	+ " tests/unit/test_ui_theme_bypass.gd checks it; tools/ui_audit/bypass_baseline.gd"
	+ " lowers it after a migration."
)
const _COLOUR := "(?<![\\w.])Color\\("
const _SCRIPT_PATTERNS := {
	"colour": [_COLOUR],
	"override": ["\\badd_theme_\\w+_override\\("],
	"font_size":
	[
		"\\badd_theme_font_size_override\\([^,()]+,\\s*\\d+\\s*\\)",
		"(?<!\\w)font_size\\s*=\\s*\\d+\\b",
	],
}
const _SCENE_PATTERNS := {
	"colour": [_COLOUR],
	"override": ["^theme_override_\\w+/"],
	"font_size": ["^theme_override_font_sizes/\\w+\\s*=\\s*\\d+", "^font_size\\s*=\\s*\\d+"],
}


## The counts per rule in one file's text (`is_scene`: a .tscn), rules at zero left out. Pure.
static func count_text(text: String, is_scene: bool) -> Dictionary:
	return _count(text, is_scene, _compile(_SCENE_PATTERNS if is_scene else _SCRIPT_PATTERNS))


## {path: {rule: count}} for every scanned file with at least one count.
static func scan() -> Dictionary:
	var compiled := {false: _compile(_SCRIPT_PATTERNS), true: _compile(_SCENE_PATTERNS)}
	var files := {}
	for root in SCAN_ROOTS:
		for path in _files_under(root):
			var is_scene := path.ends_with(".tscn")
			var counts := _count(
				FileAccess.get_file_as_string(path), is_scene, compiled[is_scene]
			)
			if not counts.is_empty():
				files[path] = counts
	return files


## The committed baseline's files as {path: {rule: int}}; empty when it is missing or bad.
static func load_baseline(path: String = BASELINE_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not (parsed as Dictionary).get("files") is Dictionary:
		return {}
	var files := {}
	var raw: Dictionary = parsed["files"]
	for file in raw:
		var counts := {}
		for rule in raw[file]:
			counts[rule] = int(raw[file][rule])
		files[file] = counts
	return files


## One line per file and rule whose count is above its baseline (a file the baseline does
## not name has a baseline of zero). Pure.
static func rises(current: Dictionary, baseline: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for file in _sorted(current.keys()):
		for rule in RULES:
			var now := int(current[file].get(rule, 0))
			var was := int(baseline.get(file, {}).get(rule, 0))
			if now > was:
				out.append("%s: %s %d, baseline %d" % [file, rule, now, was])
	return out


## One line per file and rule now below its baseline: entries a card can lower. Pure.
static func falls(current: Dictionary, baseline: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for file in _sorted(baseline.keys()):
		for rule in RULES:
			var was := int(baseline[file].get(rule, 0))
			var now := int(current.get(file, {}).get(rule, 0))
			if now < was:
				out.append("%s: %s %d, baseline %d" % [file, rule, now, was])
	return out


## The baseline with each entry lowered to today's count where that is smaller; rises are
## left at their baseline and files at zero dropped. Pure.
static func lowered(current: Dictionary, baseline: Dictionary) -> Dictionary:
	var out := {}
	for file in baseline:
		var counts := {}
		for rule in RULES:
			var was := int(baseline[file].get(rule, 0))
			var now := mini(was, int(current.get(file, {}).get(rule, 0)))
			if now > 0:
				counts[rule] = now
		if not counts.is_empty():
			out[file] = counts
	return out


## The sum of each rule over `files`. Pure.
static func totals(files: Dictionary) -> Dictionary:
	var out := {}
	for rule in RULES:
		var sum := 0
		for file in files:
			sum += int(files[file].get(rule, 0))
		out[rule] = sum
	return out


## A one-line trend: each rule's total today against the baseline's. Pure.
static func summary(current: Dictionary, baseline: Dictionary) -> String:
	var now := totals(current)
	var was := totals(baseline)
	var parts := PackedStringArray()
	for rule in RULES:
		parts.append("%s %d (baseline %d)" % [rule, now[rule], was[rule]])
	return "UI theme bypasses: " + ", ".join(parts)


## The baseline file's text for `files`, keys sorted so a change diffs line by line. Pure.
static func to_json(files: Dictionary) -> String:
	return JSON.stringify({"about": ABOUT, "files": files}, "\t", true) + "\n"


static func _compile(patterns: Dictionary) -> Dictionary:
	var out := {}
	for rule in patterns:
		var list: Array[RegEx] = []
		for pattern: String in patterns[rule]:
			list.append(RegEx.create_from_string(pattern))
		out[rule] = list
	return out


static func _count(text: String, is_scene: bool, compiled: Dictionary) -> Dictionary:
	var counts := {}
	for line in text.split("\n"):
		if not is_scene and line.strip_edges().begins_with("#"):
			continue
		for rule in compiled:
			for regex: RegEx in compiled[rule]:
				var found := regex.search_all(line).size()
				if found > 0:
					counts[rule] = int(counts.get(rule, 0)) + found
	return counts


static func _files_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if SKIPPED_DIRS.has(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		out.append_array(_files_under(dir_path.path_join(sub)))
	return out


static func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out
