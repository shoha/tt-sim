class_name SettlementBarLink
extends RefCounted

## Joins the Street tool's picked-street bar (WallToolPane, its SettlementSection) to the editor's
## settlement edits: each press of the section is one SettlementEditor call (one history entry),
## and the bar shows the street's settlement again after any edit, undo or redo
## (AuthoringEditor.edited). Kept apart from WallTool so the tool file stays small.


## Shows street `wall_id` (-1: none) and its settlement on `pane`.
static func show(pane: WallToolPane, editor: AuthoringEditor, wall_id: int) -> void:
	pane.set_meta(&"street", wall_id)
	_follow(pane, editor)
	var held: Wall = editor.document.wall(wall_id) if wall_id >= 0 else null
	var settlement: Settlement = null
	if held != null:
		settlement = editor.settlements.of_street(wall_id)
		if settlement == null and held.is_row():
			# The Dress button is one press away: its paving's layers are bound meanwhile.
			prepare_dress(editor, pane.settlement_section.kit())
	pane.show_selection(held.copy() if held != null else null, settlement)


## Binds the ground layers of the surfaces a Dress in `kit` paints on `editor`'s map
## (ProcgenSettlement.ground_of: road, door path, plaza) ahead of the Dress, so its paving sets
## only uniforms (AuthoredTerrain.prepare_surfaces).
static func prepare_dress(editor: AuthoringEditor, kit: String) -> void:
	if editor == null or not is_instance_valid(editor.terrain):
		return
	var ground := ProcgenSettlement.ground_of(ProcgenSettlement.kit_named(kit))
	var names := PackedStringArray()
	for role: String in ground:
		names.append(String(ground[role]))
	editor.terrain.prepare_surfaces(names)


## Connects `pane`'s dress requests to `controller`'s editor, for the street `mode` has picked.
static func connect_pane(
	controller: AuthoringController, mode: WallBrush, pane: WallToolPane
) -> void:
	pane.dress_requested.connect(
		func(kit: String, wealth: float, density: float) -> void:
			var editor := _editor(controller)
			if editor == null or mode.selected_id < 0:
				return
			if editor.settlements.dress(mode.selected_id, kit, wealth, density) < 0:
				controller.brush.refused.emit(_refusal(editor))
			else:
				tell_bridges(controller.brush, editor)
			show(pane, editor, mode.selected_id)
	)
	pane.kit_requested.connect(
		func(kit: String) -> void:
			var editor := _editor(controller)
			var held := editor.settlements.of_street(mode.selected_id) if editor != null else null
			if held != null and editor.settlements.set_kit(held.id, kit):
				tell_bridges(controller.brush, editor)
			if editor != null:
				show(pane, editor, mode.selected_id)
	)
	pane.feel_requested.connect(
		func(wealth: float, density: float) -> void:
			var editor := _editor(controller)
			var held := editor.settlements.of_street(mode.selected_id) if editor != null else null
			if held != null:
				editor.settlements.set_feel(held.id, wealth, density)
	)
	pane.clear_requested.connect(
		func() -> void:
			var editor := _editor(controller)
			var held := editor.settlements.of_street(mode.selected_id) if editor != null else null
			if held != null:
				editor.settlements.clear(held.id)
				show(pane, editor, mode.selected_id)
	)


## Re-shows the picked street on `pane` after an undo, redo or edit (connected the first time a
## street is shown, when the editor exists).
static func _follow(pane: WallToolPane, editor: AuthoringEditor) -> void:
	if pane.has_meta(&"follows_edits"):
		return
	pane.set_meta(&"follows_edits", true)
	var again := func() -> void:
		var street: int = pane.get_meta(&"street", -1)
		if is_instance_valid(pane) and street >= 0:
			show(pane, editor, street)
	editor.edited.connect(again)
	pane.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(editor) and editor.edited.is_connected(again):
				editor.edited.disconnect(again)
	)


## Toasts on `brush` (its `refused` signal, as a refused field does) when the last Dress or change
## of character left a stretch of water its street runs through without a bridge
## (SettlementEditor.last_bridges, VillageBridges.refusal_text). The dress itself stands.
static func tell_bridges(brush: BrushTool, editor: AuthoringEditor) -> void:
	var refused: Array[StringName] = []
	refused.assign(editor.settlements.last_bridges.get("refused", []))
	var text := VillageBridges.refusal_text(refused)
	if text != "" and brush != null:
		brush.refused.emit(text)


static func _editor(controller: AuthoringController) -> AuthoringEditor:
	if controller.brush == null or controller.brush.editor == null:
		return null
	return controller.brush.editor


static func _refusal(editor: AuthoringEditor) -> String:
	match editor.settlements.last_refusal:
		SettlementEditor.REFUSED_FULL:
			return "That map already holds as many dressed streets as it can"
		SettlementEditor.REFUSED_STREET:
			return "Only a street can be dressed"
	return "That street cannot be dressed"
