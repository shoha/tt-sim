class_name BridgeInspector
extends RefCounted

## Live Control discovery for the validation bridge.
##
## Two problems motivate this. First, injected clicks take raw coordinates, and this project's
## viewport is not a fixed size -- `window/stretch/aspect="expand"` makes it depend on the window's
## aspect ratio -- so every coordinate an agent picks off a screenshot needs a conversion that has
## repeatedly been got wrong and misdiagnosed as a broken bridge. A Control's global rect is already
## in the same viewport space the injectors use, so clicking a named Control needs no conversion at
## all. Second, the bridge's scene-tree snapshot walks `get_tree().current_scene` and is therefore
## blind to anything parented to `get_tree().root`, including dialogs and the level browser. This
## walks from whatever root it is handed, and the bridge hands it the window root.

## Upper bound on reported controls, so a deeply populated UI cannot flood the response.
const MAX_CONTROLS: int = 200


## Every Control at or beneath `root`, in tree order.
static func collect_controls(root: Node, visible_only: bool) -> Array:
	var out: Array = []
	_collect_recursive(root, visible_only, out)
	return out


static func _collect_recursive(node: Node, visible_only: bool, out: Array) -> void:
	if out.size() >= MAX_CONTROLS:
		return
	if node is Control:
		var control: Control = node
		if not visible_only or control.is_visible_in_tree():
			out.append(describe_control(control))
	for child: Node in node.get_children():
		if out.size() >= MAX_CONTROLS:
			return
		_collect_recursive(child, visible_only, out)


## Describes one Control, including its centre as a viewport-space point. `_cmd_input`'s
## `click_control` branch converts this to window space before injecting a click.
static func describe_control(control: Control) -> Dictionary:
	var rect := control.get_global_rect()
	var center := rect.get_center()
	var entry: Dictionary = {
		"name": str(control.name),
		"path": str(control.get_path()),
		"type": control.get_class(),
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"center": [center.x, center.y],
		"visible": control.is_visible_in_tree(),
	}
	var text: Variant = control.get("text")
	if text != null and str(text) != "":
		entry["text"] = str(text)
	if control is BaseButton:
		var button: BaseButton = control
		entry["disabled"] = button.disabled
		entry["pressed"] = button.button_pressed
	return entry


## Controls matching `query`, tried as a node path, then a node name, then exact button/label text.
##
## Returns every match rather than picking one: an ambiguous query is a caller error worth
## reporting, not something to resolve by guessing which "Close" button was meant.
static func find_matches(root: Node, query: String, visible_only: bool) -> Array:
	var all := collect_controls(root, visible_only)

	var by_path := all.filter(func(entry: Dictionary) -> bool: return entry["path"] == query)
	if not by_path.is_empty():
		return by_path

	var by_name := all.filter(func(entry: Dictionary) -> bool: return entry["name"] == query)
	if not by_name.is_empty():
		return by_name

	return all.filter(func(entry: Dictionary) -> bool: return entry.get("text", "") == query)
