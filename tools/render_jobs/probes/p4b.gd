extends RefCounted

## Render-job probe (`call` op) for the phase 4b follow-ups (P4b-0). step.action:
##   line {from, to, n, surface}  on the open authoring map, `n` points (default 21) from
##                                `from` to `to` (map XZ): ground, water level, depth, the wet
##                                dressing's bed / shore / wet line, and the painted weight of
##                                `surface` at the nearest sample. For the path-meets-water fix.


static func run(root: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"line":
			return _line(root, step)
	return "unknown action %s" % step.get("action", "")


static func _vec(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _line(root: Node, step: Dictionary) -> String:
	var ctrl := root.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.document == null:
		return "no authoring map"
	var doc := ctrl.document
	var from := _vec(step.get("from"))
	var to := _vec(step.get("to"))
	var n := maxi(2, int(step.get("n", 21)))
	var surface := String(step.get("surface", ""))
	var slot := doc.surface_ids.find(surface)
	var levels := WaterGeometry.levels(doc)
	var field := doc.water_dressing
	var lines := PackedStringArray()
	for i in n:
		var p := from.lerp(to, float(i) / float(n - 1))
		var s := doc.world_to_sample(p)
		var near := s.round()
		var at := doc.sample_index(int(near.x), int(near.y))
		var h := WaterGeometry.ground_at(doc, p)
		var level := levels[at]
		var dressing := WaterDressing.sample(field, doc.samples_x(), doc.samples_z(), s)
		var wet_line := 0.0
		if field.size() == doc.sample_count() * WaterDressing.CHANNELS:
			wet_line = field[at * WaterDressing.CHANNELS + 3] / 255.0
		var paint := doc.surface_weight(at, slot) if slot >= 0 else -1
		lines.append(
			(
				"(%.2f, %.2f) h %.3f level %s depth %s bed %.2f shore %.2f wet %.2f %s %d"
				% [
					p.x,
					p.y,
					h,
					"dry" if level == WaterGeometry.DRY else "%.3f" % level,
					"-" if level == WaterGeometry.DRY else "%.3f" % (level - h),
					dressing.x,
					dressing.y,
					wet_line,
					surface,
					paint
				]
			)
		)
	return "\n".join(lines)
