class_name SettlementBarLink
extends RefCounted

## Joins the Street tool's picked-street bar (WallToolPane, its SettlementSection) to the editor's
## settlement edits: each press of the section is one SettlementEditor call (one history entry),
## and the bar shows the street's settlement again after any edit, undo or redo
## (AuthoringEditor.edited). Kept apart from WallTool so the tool file stays small.


## Shows street `wall_id` (-1: none) and its settlement on `pane`.
static func show(pane: WallToolPane, editor: AuthoringEditor, wall_id: int) -> void:
	var held: Wall = editor.document.wall(wall_id) if wall_id >= 0 else null
	var settlement: Settlement = null
	if held != null:
		settlement = editor.settlements.of_street(wall_id)
	pane.show_selection(held.copy() if held != null else null, settlement)


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
			show(pane, editor, mode.selected_id)
	)
	pane.kit_requested.connect(
		func(kit: String) -> void:
			var editor := _editor(controller)
			var held := editor.settlements.of_street(mode.selected_id) if editor != null else null
			if held != null:
				editor.settlements.set_kit(held.id, kit)
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


## Re-shows the picked street on `pane` after an undo, redo or edit.
static func follow_edits(
	controller: AuthoringController, mode: WallBrush, pane: WallToolPane
) -> void:
	var editor := _editor(controller)
	if editor == null:
		return
	var again := func() -> void:
		if is_instance_valid(pane) and mode.selected_id >= 0:
			show(pane, editor, mode.selected_id)
	editor.edited.connect(again)
	pane.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(editor) and editor.edited.is_connected(again):
				editor.edited.disconnect(again)
	)


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
