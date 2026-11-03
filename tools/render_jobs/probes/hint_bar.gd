extends RefCounted

## Render-job probe (`call` op) for the input hint bar's vertical layout (jobs/hintbar_look.json).
## `action`:
## - `measure`: log the bar's rects in canvas pixels (the bar, its backdrop panel, the row, and
##   for each chip the hbox, the key cap and the caption), the backdrop's StyleBox content
##   margins, and the gap above and below the key caps inside the backdrop.
## - `row` (`which`): stage a hint row on the live bar. `two` is a row long enough to wrap onto
##   two lines, `alt` swaps the camera chip for the Alt + Q E one, `long` is the authoring row
##   with the tool's keys, `play` is the usual play row.

const ROWS := {
	"play":
	[
		["Esc", "Pause"],
		["WASD", "Pan"],
		["Scroll", "Zoom"],
		["Q E", "Turn"],
		["Home", "Reset camera"],
		["M", "Measure"],
		["G", "Grid"],
		["F1", "Help"],
	],
	"two":
	[
		["Esc", "Pause"],
		["WASD", "Pan"],
		["Scroll", "Zoom"],
		["Q E", "Turn"],
		["Home", "Reset camera"],
		["M", "Measure"],
		["G", "Grid"],
		["Click", "Place a thing"],
		["Right-click", "Undo the last stroke"],
		["Middle-drag", "Orbit the camera"],
		["Ctrl + click", "Snap to a token"],
		["Tab", "Switch the shape"],
		["F1", "Help"],
	],
	"long":
	[
		["Click", "Paint"],
		["Shift + click", "Smooth"],
		["Ctrl + click", "Erase"],
		["[ ]", "Brush size"],
		["Alt + drag", "Orbit"],
		["Middle-drag", "Pan"],
		["Scroll", "Zoom"],
		["Alt + Q E", "Turn"],
		["Home", "Reset camera"],
		["F1", "Help"],
	],
}


static func run(_base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"measure":
			return _measure()
		"row":
			return _row(String(step.get("which", "play")))
	return "unknown action %s" % step.get("action", "")


static func _hints() -> InputHints:
	return UIManager.get("_input_hints") as InputHints


static func _row(which: String) -> String:
	var hints := _hints()
	if hints == null:
		return "no hint bar"
	if which == "alt":
		var rows: Array = ROWS["play"].duplicate()
		var live := CameraRig.turn_hint(true)
		var spec: Array = []
		for pair in rows:
			spec.append({"key": live.key, "action": live.action} if pair[0] == "Q E" else _hint(pair))
		hints.set_hints(spec)
		return "row alt"
	if not ROWS.has(which):
		return "unknown row %s" % which
	var spec: Array = []
	for pair in ROWS[which]:
		spec.append(_hint(pair))
	hints.set_hints(spec)
	return "row %s" % which


static func _hint(pair: Array) -> Dictionary:
	return {"key": pair[0], "action": pair[1]}


static func _measure() -> String:
	var hints := _hints()
	if hints == null:
		return "no hint bar"
	var bar := hints.get("_bar") as Control
	var backdrop := hints.get("_backdrop") as PanelContainer
	var row := hints.hints_container
	var lines := PackedStringArray()
	var screen := bar.get_viewport().get_visible_rect().size
	var window := bar.get_window()
	var scale := window.content_scale_factor
	lines.append("window %s, content scale %.3f, canvas %s" % [str(window.size), scale, str(screen)])
	lines.append("bar offset_transform %s" % str(bar.offset_transform_position))
	var offsets := [bar.offset_top, bar.offset_bottom, bar.custom_minimum_size]
	lines.append("bar offset_top %s bottom %s custom min %s" % offsets)
	var mins := [
		bar.get_combined_minimum_size(),
		backdrop.get_combined_minimum_size(),
		row.get_combined_minimum_size()
	]
	lines.append("min size: bar %s, backdrop %s, row %s" % mins)
	lines.append("scene %s" % hints.scene_file_path)
	lines.append("bar rect %s" % _rect(bar))
	lines.append("backdrop rect %s" % _rect(backdrop))
	var box := backdrop.get_theme_stylebox(&"panel")
	lines.append(
		(
			"backdrop margins l%.1f t%.1f r%.1f b%.1f"
			% [
				box.get_margin(SIDE_LEFT),
				box.get_margin(SIDE_TOP),
				box.get_margin(SIDE_RIGHT),
				box.get_margin(SIDE_BOTTOM)
			]
		)
	)
	lines.append("row rect %s" % _rect(row))
	var caps_top := INF
	var caps_bottom := -INF
	for chip in row.get_children():
		var cap := chip.get_child(0) as Control
		var label := chip.get_child(1) as Control
		var parts := [chip.name, _rect(chip), _rect(cap), _rect(label)]
		lines.append("  %s hbox %s cap %s caption %s" % parts)
		caps_top = minf(caps_top, cap.get_global_rect().position.y)
		caps_bottom = maxf(caps_bottom, cap.get_global_rect().end.y)
	var panel := backdrop.get_global_rect()
	var above := caps_top - panel.position.y
	var below := panel.end.y - caps_bottom
	lines.append("gap above caps %.2f, gap below caps %.2f" % [above, below])
	lines.append("backdrop %.2f tall, caps span %.2f" % [panel.size.y, caps_bottom - caps_top])
	lines.append("backdrop above the screen's bottom edge by %.2f" % (screen.y - panel.end.y))
	for node in bar.get_tree().get_nodes_in_group(InputHints.OBSTACLES):
		var control := node as Control
		if control != null and control.is_visible_in_tree():
			var hit := control.get_global_rect().intersects(panel)
			lines.append("obstacle %s %s overlaps backdrop: %s" % [control.name, _rect(control), hit])
	return "\n".join(lines)


static func _rect(control: Control) -> String:
	var r := control.get_global_rect()
	return "(x %.1f y %.1f w %.1f h %.1f)" % [r.position.x, r.position.y, r.size.x, r.size.y]
