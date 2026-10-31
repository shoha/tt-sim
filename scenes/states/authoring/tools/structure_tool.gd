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
const LABEL := "Buildings"
## Set on the map's AuthoredStructures while one sync_missing check waits for its next build.
const WATCH_META := &"tt_missing_watch"
const UNAVAILABLE_TOOLTIP := "Building: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = StructureToolPane.SUMMARY
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
		["Click bare ground (selected)", "Put another building down; the new one is selected"],
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


## The key caps on the hint bar: the gestures this user has not done once yet, for a lot
## following the pointer or a selected building (StructureHints).
func key_hints(brush: BrushTool) -> Array:
	return StructureHints.rows(StructureHints.done(), of(brush).has_selection())


## Puts the brush and the pane on one pick: the brush's own when it has one the pane lists, else
## the tile the pane preselects (the first in its display order, which is not the store's).
static func sync_pick(mode: StructureBrush, pane: StructureToolPane) -> void:
	if mode.ref != "" and pane.has_ref(mode.ref):
		pane.select_ref(mode.ref)
	elif pane.picked_ref() != "":
		mode.pick(pane.picked_ref())


## The tiles set the brush's structure and pick the tool again, so a brush put down with a right
## click comes back with any tile; Mix afresh draws the next lot's look afresh.
func connect_pane(controller: AuthoringController, pane: Control) -> void:
	var structure_pane := pane as StructureToolPane
	if structure_pane == null:
		return
	# The pane and the brush start on one pick: the brush's own when it has one (a rebuilt pane
	# shows it), else the tile the pane preselects.
	if controller.brush != null:
		sync_pick(of(controller.brush), structure_pane)
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


## The selected building's bar (card S5), on the authoring controller's brush.
func _connect_selection(controller: AuthoringController, pane: StructureToolPane) -> void:
	if controller.brush != null:
		connect_selection(controller.brush, pane, controller.refresh_tool_hints)


## Marks the Decorate chips whose ornament the structure's build found no room for (the build's
## placed kinds against the kinds asked in `params`). A build lands on a worker some frames after
## an edit, so while the structure has no built node yet the check repeats once when the map's
## structures next report a build.
static func sync_missing(
	map_root: Node, pane: StructureToolPane, structure_id: int, params: Dictionary
) -> void:
	if map_root == null or pane == null:
		return
	var asked := StructureOrnaments.kinds_of(params)
	pane.ornaments_section.show_missing(
		AuthoredStructures.missing_kinds_in(map_root, structure_id, asked)
	)
	var structures := map_root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures
	if structures == null or structures.has_meta(WATCH_META) or asked.is_empty():
		return
	structures.set_meta(WATCH_META, true)
	structures.built.connect(
		func(_count: int) -> void:
			structures.remove_meta(WATCH_META)
			if is_instance_valid(pane) and is_instance_valid(map_root):
				pane.ornaments_section.show_missing(
					AuthoredStructures.missing_kinds_in(map_root, structure_id, asked)
				),
		CONNECT_ONE_SHOT
	)


## The selected building's bar: the brush says which building is selected and the bar shows it;
## each button is one call on the brush, one history entry, and the bar is shown again from the
## record afterwards. The brush's mode outlives the pane, so the old connections (to a pane that
## is gone) are dropped first. `hints_changed` is called when the hint bar's rows change (a
## selection, a gesture done once). Authoring and the GM's Events pane both call it.
func connect_selection(brush: BrushTool, pane: StructureToolPane, hints_changed: Callable) -> void:
	var mode := of(brush)
	for link: Dictionary in mode.selection_changed.get_connections():
		mode.selection_changed.disconnect(link["callable"])
	for link: Dictionary in mode.gesture_done.get_connections():
		mode.gesture_done.disconnect(link["callable"])
	var editor := brush.editor
	# A gesture done once is remembered per user, and its key fades from the bar.
	mode.gesture_done.connect(
		func(id: StringName) -> void:
			if StructureHints.mark(id):
				hints_changed.call()
	)
	var show := func(structure_id: int) -> void:
		var held := (
			brush.editor.document.structure(structure_id)
			if structure_id >= 0 and brush.editor != null
			else null
		)
		pane.show_selection(held.copy() if held != null else null)
		if held != null:
			sync_missing(brush.editor.map_root, pane, held.id, held.params)
	mode.selection_changed.connect(show)
	mode.selection_changed.connect(func(_structure_id: int) -> void: hints_changed.call())
	var act := func(call: Callable) -> void:
		if brush.editor != null:
			call.call(brush.editor)
		show.call(mode.selected_id)
	pane.variant_picked.connect(func(ref: String) -> void: act.call(mode.swap_variant.bind(ref)))
	pane.param_stepped.connect(
		func(param: String, direction: int) -> void:
			act.call(mode.step_selected.bind(param, direction))
	)
	# The Decorate row: the ornaments ride in the record's params (StructureOrnaments), so one
	# click is one set_ornaments edit, one history entry, which every peer's build follows.
	pane.ornaments_requested.connect(
		func(kinds: Array, label: String) -> void:
			act.call(
				func(e: AuthoringEditor) -> void:
					if mode.selected_id >= 0:
						e.structures.set_ornaments(mode.selected_id, kinds, label)
			)
	)
	pane.ivy_requested.connect(
		func(amount: float) -> void:
			act.call(
				func(e: AuthoringEditor) -> void:
					var held := e.document.structure(mode.selected_id)
					if held != null:
						e.structures.set_ornaments(
							held.id, StructureOrnaments.kinds_of(held.params), "Change ivy of", amount
						)
			)
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
