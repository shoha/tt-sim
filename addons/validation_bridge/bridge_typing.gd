class_name BridgeTyping
extends RefCounted

## Text entry and screenshot-to-file helpers for the validation bridge.
##
## Everything here is static and viewport-free where it can be, so the grammar can be tested without
## a live bridge and socket (the bridge's own coroutines stay in validation_bridge.gd).
##
## Typing model: `game_type` reaches a text field the way a real keyboard does. The target gets GUI
## focus, then each character is injected as an InputEventKey press and release carrying the
## character's unicode, through `Input.parse_input_event`, so the focused LineEdit or TextEdit runs
## its own text insertion (selection replace, max_length, caret movement) and emits `text_changed`
## on its own; the game's handlers run exactly as they would for a person. A newline is an Enter
## key and a tab is a Tab key. `TypeWatch` counts the field's `text_changed` and `text_submitted`
## signals around the call so the report can say whether they fired.
##
## Screenshot-to-file model: a PNG may be written only inside the project's user data folder or the
## OS temp folder, so an agent's look loop can keep downscaled copies without the bridge becoming a
## way to write anywhere on disk. `screenshot_path_error` is the whole policy.

## Folder names the OS temp folder can be read from, in order of preference.
const TEMP_ENV_VARS: PackedStringArray = ["TEMP", "TMP", "TMPDIR"]

## How many ancestors a label search climbs when it looks for the field a label belongs to.
const LABEL_CLIMB_LEVELS: int = 3


## Counts the `text_changed` and `text_submitted` emissions of one text field while it exists.
## Call `stop()` before dropping it so the connections do not outlive the report.
class TypeWatch:
	extends RefCounted

	var changed: int = 0
	var submitted: int = 0
	var _control: Control = null

	func _init(control: Control) -> void:
		_control = control
		control.connect(&"text_changed", _on_changed)
		if control.has_signal(&"text_submitted"):
			control.connect(&"text_submitted", _on_submitted)

	func stop() -> void:
		if not is_instance_valid(_control):
			return
		if _control.is_connected(&"text_changed", _on_changed):
			_control.disconnect(&"text_changed", _on_changed)
		if _control.has_signal(&"text_submitted") and _control.is_connected(
			&"text_submitted", _on_submitted
		):
			_control.disconnect(&"text_submitted", _on_submitted)

	# LineEdit emits text_changed(String); TextEdit emits it with no argument. The default makes
	# one handler fit both.
	func _on_changed(_new_text: String = "") -> void:
		changed += 1

	func _on_submitted(_new_text: String = "") -> void:
		submitted += 1


# ---------------------------------------------------------------------------
# Screenshot path policy
# ---------------------------------------------------------------------------


## Forward slashes, dot segments resolved, no trailing slash. Pure.
static func normalize_path(path: String) -> String:
	var p := path.replace("\\", "/").simplify_path()
	while p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.substr(0, p.length() - 1)
	return p


## The folders a screenshot may be written under: the project's user data folder and the OS temp
## folder, as absolute normalized paths. Empty entries are dropped.
static func default_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	roots.append(normalize_path(ProjectSettings.globalize_path("user://")))
	for var_name in TEMP_ENV_VARS:
		var value := OS.get_environment(var_name)
		if not value.is_empty() and not roots.has(normalize_path(value)):
			roots.append(normalize_path(value))
	if OS.get_name() != "Windows":
		roots.append("/tmp")
	return roots


## Why `path` may not be written, or "" when it may. The path must be absolute (no `res://` or
## `user://`), end in `.png`, and sit strictly inside one of `roots` after dot segments are
## resolved, so `<temp>/../elsewhere/x.png` is rejected. `case_insensitive` is for Windows paths.
## Pure.
static func screenshot_path_error(
	path: String, roots: PackedStringArray, case_insensitive: bool
) -> String:
	if path.strip_edges().is_empty():
		return "path is empty"
	if path.contains("://"):
		return "path must be an absolute file path, not a Godot URL: %s" % path
	var normal := normalize_path(path)
	if not normal.is_absolute_path():
		return "path must be absolute: %s" % path
	if not normal.to_lower().ends_with(".png"):
		return "path must end in .png: %s" % path
	var candidate := normal.to_lower() if case_insensitive else normal
	for root in roots:
		if root.is_empty():
			continue
		var base := root.to_lower() if case_insensitive else root
		if candidate.begins_with(base + "/") and candidate.length() > base.length() + 1:
			return ""
	return (
		"path must be inside the project user data folder or the OS temp folder (%s): %s"
		% [", ".join(roots), path]
	)


# ---------------------------------------------------------------------------
# Key events
# ---------------------------------------------------------------------------


## The keycode a printable ASCII character is typed with, or KEY_NONE when it has no simple one.
static func keycode_for_char(code: int) -> Key:
	if code >= 97 and code <= 122:
		return (KEY_A + (code - 97)) as Key
	if code >= 65 and code <= 90:
		return (KEY_A + (code - 65)) as Key
	if code >= 48 and code <= 57:
		return (KEY_0 + (code - 48)) as Key
	if code == 32:
		return KEY_SPACE
	return KEY_NONE


## A press and a release for one key. `unicode` rides on the press only, as with a real keyboard.
static func key_pair(keycode: Key, unicode: int = 0, shift: bool = false) -> Array[InputEventKey]:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.unicode = unicode
	press.shift_pressed = shift
	press.pressed = true
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.shift_pressed = shift
	release.pressed = false
	return [press, release]


## The events that type `text`: a press and a release per character, in order. A newline becomes an
## Enter key, a tab a Tab key, and a carriage return is dropped (so "\r\n" is one Enter).
static func key_events_for_text(text: String) -> Array[InputEventKey]:
	var events: Array[InputEventKey] = []
	for i in text.length():
		var code := text.unicode_at(i)
		if code == 13:
			continue
		if code == 10:
			events.append_array(key_pair(KEY_ENTER))
		elif code == 9:
			events.append_array(key_pair(KEY_TAB))
		else:
			var shift := code >= 65 and code <= 90
			events.append_array(key_pair(keycode_for_char(code), code, shift))
	return events


# ---------------------------------------------------------------------------
# Finding the field
# ---------------------------------------------------------------------------


## True for the controls `game_type` can type into.
static func is_text_input(node: Node) -> bool:
	return node is LineEdit or node is TextEdit


## Finds the text field a `control` query names, under `root`. Returns {"ok": true, "control": c}
## or {"ok": false, "error": ..., "matches": [...]}.
##
## An empty query means the field that has GUI focus now. Otherwise the query is matched against
## visible Controls the way `click_control` does (node path, node name, exact text) and also against
## a field's placeholder text. A match that is not itself a text field resolves to the field it
## stands for: the first field inside it, else the first field after it among its siblings, climbing
## a few levels (so the text of a "Map name" label finds the field beside it).
static func resolve_target(root: Node, query: String) -> Dictionary:
	if query.is_empty():
		var focused: Control = null
		if root.is_inside_tree():
			focused = root.get_viewport().gui_get_focus_owner()
		if focused == null or not is_text_input(focused):
			return {"ok": false, "error": "no 'control' given and no text field has focus"}
		return {"ok": true, "control": focused}
	var visible: Array[Control] = []
	_collect_visible(root, visible)
	var hits := _matches(visible, query)
	var fields: Array[Control] = []
	for hit in hits:
		var field := field_for(hit)
		if field != null and not fields.has(field):
			fields.append(field)
	if fields.is_empty():
		return {"ok": false, "error": "No visible text field matches '%s'" % query}
	if fields.size() > 1:
		var paths: Array = fields.map(func(c: Control) -> String: return str(c.get_path()))
		return {"ok": false, "error": "'%s' is ambiguous" % query, "matches": paths}
	return {"ok": true, "control": fields[0]}


## The text field a control stands for: itself, the first field inside it, or the first field after
## it among its siblings (climbing up to LABEL_CLIMB_LEVELS ancestors). Null when there is none.
static func field_for(node: Control) -> Control:
	var inside := first_field_in(node)
	if inside != null:
		return inside
	var current: Node = node
	for _level in LABEL_CLIMB_LEVELS:
		var parent := current.get_parent()
		if parent == null:
			return null
		var seen := false
		for sibling in parent.get_children():
			if sibling == current:
				seen = true
			elif seen:
				var found := first_field_in(sibling)
				if found != null:
					return found
		current = parent
	return null


## `node` if it is a visible text field, else the first visible one beneath it in tree order.
static func first_field_in(node: Node) -> Control:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if is_text_input(node):
		return node as Control
	for child in node.get_children():
		var found := first_field_in(child)
		if found != null:
			return found
	return null


static func _collect_visible(node: Node, out: Array[Control]) -> void:
	if node is Control and (node as Control).is_visible_in_tree():
		out.append(node as Control)
	for child in node.get_children():
		_collect_visible(child, out)


## Tiers as in BridgeInspector.find_matches (path, name, text) plus placeholder text last.
static func _matches(controls: Array[Control], query: String) -> Array[Control]:
	var tiers: Array[Callable] = [
		func(c: Control) -> bool: return str(c.get_path()) == query,
		func(c: Control) -> bool: return str(c.name) == query,
		func(c: Control) -> bool: return str(c.get("text")) == query and c.get("text") != null,
		func(c: Control) -> bool: return str(c.get("placeholder_text")) == query and query != "",
	]
	for tier in tiers:
		var hits: Array[Control] = []
		for c in controls:
			if tier.call(c):
				hits.append(c)
		if not hits.is_empty():
			return hits
	return []


# ---------------------------------------------------------------------------
# Field state
# ---------------------------------------------------------------------------


## The field's current text. Works for LineEdit and TextEdit, which both expose `text`.
static func text_of(field: Control) -> String:
	return str(field.get("text"))


## Moves the caret to the end of the text, so typing appends the way a click past the last
## character would.
static func caret_to_end(field: Control) -> void:
	if field is LineEdit:
		var line_edit: LineEdit = field
		line_edit.caret_column = line_edit.text.length()
	elif field is TextEdit:
		var text_edit: TextEdit = field
		var last := text_edit.get_line_count() - 1
		text_edit.set_caret_line(last)
		text_edit.set_caret_column(text_edit.get_line(last).length())


## Whether the field takes typed text at all.
static func is_editable(field: Control) -> bool:
	if field is LineEdit:
		return (field as LineEdit).editable
	if field is TextEdit:
		return (field as TextEdit).editable
	return false
