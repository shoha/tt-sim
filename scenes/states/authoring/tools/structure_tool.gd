class_name StructureTool
extends ToolDescriptor

## The Structure tool: a building from a library, put down on the ground. Pick one on the
## palette strip (StructureToolPane), and a ghost lot follows the pointer, easing to the nearest
## dry, level, free ground; a click lays it, a drag sizes it, Q and E turn it, R draws it afresh,
## and right-click or Delete over one removes it (StructureBrush does the gesture,
## StructureEditor the edit, AuthoredStructures the nodes). It replaces the Wall tool's Building
## tile. A dressed Blender map's ground is the GLB's, so there the tool is disabled with a
## tooltip saying why, as Wall and Paint are. A play brush too: the GM's Events pane lists it,
## and what it lays reaches every peer as a "structures" live edit (LiveEditCodec).

const ID := &"structure"
const LABEL := "Building"
const UNAVAILABLE_TOOLTIP := "Building: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Put down a house, a cottage or a townhouse."
	icon = "home"
	brush_mode = StructureBrush
	contexts = AUTHORING | PLAY
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [
		["Click (Building)", "Put the building down; it settles on the nearest dry, level ground"],
		["Left Drag (Building)", "Drag from one corner to the opposite one to size it"],
		["Q / E (Building)", "Turn it 15 degrees (Shift: a quarter turn)"],
		["[ ] (Building)", "Make the building a click lays smaller or bigger"],
		["R (Building)", "Draw the next building afresh, or the one under the cursor"],
		["Right-click, Delete (Building)", "Remove the building under the cursor"],
		["Click a building", "Select it: corner dots resize, side tabs push, the body moves"],
		["Click a side tab (selected)", "Put the door on that side"],
		["Shift + drag a corner (selected)", "Move just that corner, off the square"],
		["Ctrl+D (selected)", "Copy the building beside itself"],
		["Escape (selected)", "Let go of the building"],
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> StructureBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as StructureBrush


## Only where the ground is the document's (a building follows the document's heights).
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and works_on(controller.editor)


func works_on(editor: AuthoringEditor) -> bool:
	return editor.can_paint()


func build_pane(_panel: AuthoringPanel) -> Control:
	return StructureToolPane.new()


## The tiles set the brush's structure and pick the tool again, so a brush put down with a right
## click comes back with any tile; Mix afresh draws the next lot's look afresh.
func connect_pane(controller: AuthoringController, pane: Control) -> void:
	var structure_pane := pane as StructureToolPane
	if structure_pane == null:
		return
	structure_pane.structure_selected.connect(
		func(ref: String) -> void:
			if controller.brush != null:
				of(controller.brush).pick(ref)
				controller.pick_tool(ID)
	)
	structure_pane.reroll_requested.connect(
		func() -> void:
			if controller.brush != null:
				of(controller.brush).reroll_at(controller.brush.editor, -1)
	)
	_connect_selection(controller, structure_pane)


## The selected building's bar (card S5): the brush says which building is selected and the bar
## shows it; each button is one call on the brush, one history entry, and the bar is shown again
## from the record afterwards. The brush's mode outlives the pane, so the old connections (to a
## pane that is gone) are dropped first.
func _connect_selection(controller: AuthoringController, pane: StructureToolPane) -> void:
	if controller.brush == null:
		return
	var mode := of(controller.brush)
	for link: Dictionary in mode.selection_changed.get_connections():
		mode.selection_changed.disconnect(link["callable"])
	var editor := controller.brush.editor
	var show := func(structure_id: int) -> void:
		var held := (
			controller.brush.editor.document.structure(structure_id)
			if structure_id >= 0 and controller.brush != null and controller.brush.editor != null
			else null
		)
		pane.show_selection(held.copy() if held != null else null)
	mode.selection_changed.connect(show)
	var act := func(call: Callable) -> void:
		if controller.brush != null and controller.brush.editor != null:
			call.call(controller.brush.editor)
		show.call(mode.selected_id)
	pane.variant_picked.connect(func(ref: String) -> void: act.call(mode.swap_variant.bind(ref)))
	pane.param_stepped.connect(
		func(param: String, direction: int) -> void:
			act.call(mode.step_selected.bind(param, direction))
	)
	pane.door_requested.connect(func() -> void: act.call(mode.door_next))
	pane.redraw_requested.connect(
		func() -> void:
			act.call(func(e: AuthoringEditor) -> void: e.structures.reroll(mode.selected_id))
	)
	pane.copy_requested.connect(func() -> void: act.call(mode.duplicate_selected))
	pane.remove_requested.connect(func() -> void: act.call(mode.delete_selected))
	pane.done_requested.connect(mode.deselect)
	if editor != null:
		show.call(mode.selected_id)
