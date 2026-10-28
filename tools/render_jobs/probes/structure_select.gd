extends RefCounted

## Render-job probe (`call` op) for editing a placed building (the Building tool's selection, card
## S5; the gestures themselves are the driver's `input` and `gesture` ops). step.action:
##   lay {ref, at [x, z], size [w, d], seed}   lays a structure through the editor (one history
##                                              entry), as a click of the tool would.
##   bar {press, param, direction, ref}         presses a button of the selected building's bar:
##                                              press "variant" (ref), "param" (param, direction),
##                                              "door", "copy", "redraw", "remove" or "done".
##   report                                     the document's structures, the selection, the
##                                              brush's gesture state and the history depth.
##   flush                                      waits for the structure builds in flight.
## A new unsaved map only: nothing is saved, so no level is left behind.


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"lay":
			return _lay(base, step)
		"bar":
			return _bar(base, step)
		"report":
			return _report(base)
		"flush":
			var nodes := _nodes(base)
			return "flushed %d" % nodes.flush() if nodes != null else "no AuthoredStructures"
	return "unknown action %s" % step.get("action", "")


static func _ctrl(base: Node) -> AuthoringController:
	return base.get("_authoring_controller") as AuthoringController


static func _nodes(base: Node) -> AuthoredStructures:
	var ctrl := _ctrl(base)
	if ctrl == null or not is_instance_valid(ctrl.map_root):
		return null
	return ctrl.map_root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures


static func _mode(base: Node) -> StructureBrush:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.get_brush_tool() == null:
		return null
	return StructureTool.of(gm.get_brush_tool())


static func _lay(base: Node, step: Dictionary) -> String:
	var ctrl := _ctrl(base)
	if ctrl == null or ctrl.editor == null:
		return "no editor"
	var at: Array = step.get("at", [0, 0])
	var size: Array = step.get("size", [6, 4])
	var plan := StructurePlacement.rect_plan(
		Vector2(float(at[0]), float(at[1])), Vector2(float(size[0]), float(size[1])), 0.0
	)
	var lot := ctrl.editor.structures.lot(
		String(step.get("ref", "")), plan, int(step.get("seed", 7))
	)
	if lot == null:
		return "refused: %s" % ctrl.editor.structures.last_refusal
	return "laid #%d" % ctrl.editor.structures.add(lot)


static func _bar(base: Node, step: Dictionary) -> String:
	var ctrl := _ctrl(base)
	var pane := (
		ctrl.panel.tool_pane(StructureTool.ID) as StructureToolPane if ctrl != null else null
	)
	if pane == null:
		return "no pane"
	match String(step.get("press", "")):
		"variant":
			pane.variant_picked.emit(String(step.get("ref", "")))
		"param":
			pane.param_stepped.emit(String(step.get("param", "")), int(step.get("direction", 1)))
		"door":
			pane.door_requested.emit()
		"copy":
			pane.copy_requested.emit()
		"redraw":
			pane.redraw_requested.emit()
		"remove":
			pane.remove_requested.emit()
		"done":
			pane.done_requested.emit()
		_:
			return "unknown press %s" % step.get("press", "")
	return "pressed %s" % step.get("press", "")


static func _report(base: Node) -> String:
	var ctrl := _ctrl(base)
	if ctrl == null or ctrl.document == null:
		return "no document"
	var lines := PackedStringArray()
	for structure in ctrl.document.structures:
		lines.append(
			(
				"#%d %s size %s seed %d params %s front %s"
				% [
					structure.id,
					structure.recipe,
					StructureEdit.extent_of(structure.footprint),
					structure.seed_value,
					str(structure.params),
					ProcgenPlan.edge_middle(structure.footprint, 0)
				]
			)
		)
	var mode := _mode(base)
	var state := ""
	var gm := base.get("_game_map") as GameMap
	if gm != null and gm.get_brush_tool() != null and ctrl.editor != null:
		var tool := gm.get_brush_tool()
		state = (
			"; pointer hit %s (map %s, structure there %d)"
			% [
				tool.hit,
				ctrl.editor.to_map_xz(tool.hit) if tool.hit != Vector3.INF else "none",
				ctrl.editor.structures.structure_at(tool.hit) if tool.hit != Vector3.INF else -2
			]
		)
	if mode != null:
		var gesture := (
			"none"
			if mode.edit.is_empty()
			else (
				"%s dragged %s clamped %s"
				% [mode.edit["kind"], mode.edit["dragged"], mode.edit["clamped"]]
			)
		)
		state += (
			"; selected %d, gesture %s, hover handle %s"
			% [mode.selected_id, gesture, mode.hover_handle]
		)
	return "%s%s; undo depth %d" % ["; ".join(lines), state, ctrl.history.undo_count()]
