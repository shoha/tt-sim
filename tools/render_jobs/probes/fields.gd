extends RefCounted

## Render-job probe (`call` op) for village fields (topic fields, docs/systems/villages.md
## section 11). step.action:
##   lay {field, kind}            what a Village tool press lays (the pane's Lay and kind rows)
##   add {id, at, radius, kind}   lays a field for settlement `id` (map XZ) through the editor
##   report                       the fields, their strokes and the plants standing
## Every action returns the line the job log prints.


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var editor := ctrl.editor
	match String(step.get("action", "report")):
		"lay":
			if ctrl.brush == null:
				return "no brush"
			var mode := VillageTool.of(ctrl.brush)
			mode.set_lay(bool(step.get("field", true)), String(step.get("kind", "")))
			return "lay field=%s kind=%s" % [str(mode.lay_field), mode.field_kind]
		"add":
			var at: Array = step.get("at", [0, 0])
			var ok := editor.settlements.add_field(
				int(step.get("id", 1)),
				Vector2(float(at[0]), float(at[1])),
				float(step.get("radius", 8.0)),
				String(step.get("kind", "crops"))
			)
			var settlements := AuthoredSettlements.of_map(editor.map_root)
			settlements.flush()
			return (
				"add %s refusal=%s ground=%s"
				% [str(ok), editor.settlements.last_refusal, str(editor.settlements.last_ground)]
			)
	var lines := PackedStringArray()
	for settlement in editor.document.settlements:
		lines.append(
			"village %d %s seed %d: %d fields, %d strokes"
			% [
				settlement.id,
				settlement.kit,
				settlement.seed_value,
				settlement.fields.size(),
				settlement.ground.size()
			]
		)
	var plants := (
		editor.map_root.get_node_or_null(AuthoredFieldPlants.NODE_NAME) as AuthoredFieldPlants
	)
	lines.append("plants %d" % (plants.placed if plants != null else 0))
	return "; ".join(lines)
