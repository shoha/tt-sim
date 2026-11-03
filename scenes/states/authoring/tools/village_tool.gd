class_name VillageTool
extends ToolDescriptor

## The Village tool: opens, sizes and removes the plazas of a dressed village and picks its
## character (VillageBrush does the gestures, SettlementEditor the edits, VillagePlazas the pure
## rules). A plaza is a ring on the ground the street opens into: the ground under it is repaved
## with the character's plaza surface and the character's plaza rules furnish it. Its pane is
## VillageToolPane. A dressed Blender map's ground is the GLB's, so there the tool is disabled
## with a tooltip saying why, as Wall is. Authoring only: what it does reaches every peer through
## the ordinary `surface` and `settlements` live edits. Design: docs/systems/villages.md section 10.

const ID := &"village"
const LABEL := "Village"
const UNAVAILABLE_TOOLTIP := "Village: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Open plazas and lay fields in a village."
	icon = "village"
	brush_mode = VillageBrush
	contexts = AUTHORING
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [
		[
			"Left Click or Drag (Village)",
			"Open a plaza on the ground; a drag sizes it. Dress a street with the Wall tool first",
		],
		["Drag a plaza's edge (Village)", "Resize it; the ground is repaved when you let go"],
		["Click a plaza (Village)", "Pick it: the pane then sizes or removes it"],
		["Drag a barrel, stall or bench (Village)", "Move it; it stays where you put it"],
		["Click a piece (Village)", "Pick it: Swap, Back and Remove show beside it and in the pane"],
		["Q and E, R over a piece (Village)", "Turn it a notch (Shift a quarter); show another draw"],
		["Delete (Village)", "Remove the piece or plaza under the cursor"],
		["[ and ] (Village)", "A plaza one metre smaller or larger; Shift + scroll over one"],
		["Escape (picked plaza)", "Let go of the plaza"],
		["Crops, Orchard, Garden (Lay out)","Clicks then lay that field at the village's edge"],
	]


## While a furnishing is under the pointer or picked, the keys that act on it, so the screen says
## which mapping is live (Q and E turn the piece here, the camera's turn keys move to Alt).
func key_hints(brush: BrushTool) -> Array:
	var mode := of(brush)
	if mode == null or not (mode.props.has_hover() or mode.props.has_picked()):
		return []
	var field := VillageFurnishings.is_field_piece(
		mode.props.hover_slot if mode.props.has_hover() else mode.props.slot
	)
	if field:
		return [{"key": "Del", "action": "Remove piece"}]
	return [
		{"key": "Drag", "action": "Move piece"},
		{"key": "Q E", "action": "Turn piece"},
		{"key": "R", "action": "Re-roll"},
		{"key": "Del", "action": "Remove"},
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> VillageBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as VillageBrush


## Only where the ground is the document's (a plaza is painted into its surfaces).
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and works_on(controller.editor)


func works_on(editor: AuthoringEditor) -> bool:
	return editor.can_paint()


## A Dress places buildings' furnishings: their decor and shaders warm up now (StructureWarmup).
func prepare(controller: AuthoringController) -> void:
	StructureTool.warm(controller)


func build_pane(panel: AuthoringPanel) -> Control:
	return VillageToolPane.new(panel.palette_root)


## The pane's picks are single editor calls (one history entry each), and the pane shows the
## document again whenever the mode says what it shows changed. The brush's mode outlives the
## pane, so the old connections (to a pane that is gone) are dropped first.
func connect_pane(controller: AuthoringController, pane: Control) -> void:
	var village_pane := pane as VillageToolPane
	if village_pane == null or controller.brush == null:
		return
	var brush := controller.brush
	var mode := of(brush)
	for link: Dictionary in mode.view_changed.get_connections():
		mode.view_changed.disconnect(link["callable"])
	mode.view_changed.connect(
		func() -> void:
			refresh_pane(brush, mode, village_pane)
			controller.refresh_tool_hints()
	)
	village_pane.village_picked.connect(
		func(village: int) -> void:
			mode.select(village, -1)
			controller.pick_tool(ID)
	)
	village_pane.kit_picked.connect(
		func(kit: String) -> void:
			if brush.editor != null and mode.selected_village > 0:
				if brush.editor.settlements.set_kit(mode.selected_village, kit):
					SettlementBarLink.tell_bridges(brush, brush.editor)
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.boundary_picked.connect(
		func(choice: String) -> void:
			if brush.editor != null and mode.selected_village > 0:
				apply_boundary(brush.editor, mode.selected_village, choice)
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.radius_committed.connect(
		func(radius: float) -> void:
			if brush.editor != null and mode.set_selected_radius(brush.editor, radius):
				brush.redraw()
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.lay_picked.connect(
		func(field: bool, kind: String) -> void:
			mode.set_lay(field, kind)
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.remove_requested.connect(
		func() -> void:
			if brush.editor != null:
				mode.remove_selected(brush.editor)
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.swap_requested.connect(
		func() -> void:
			if brush.editor != null:
				var words := mode.props.swap(brush.editor)
				if words != "":
					brush.refused.emit(words)
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.unpin_requested.connect(
		func() -> void:
			if brush.editor != null:
				mode.props.unpin(brush.editor)
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.restore_requested.connect(
		func() -> void:
			if brush.editor != null and mode.selected_village > 0:
				mode.props.preview_restore(brush.editor, mode.selected_village, false)
				mode.props.restore(brush.editor, mode.selected_village)
			refresh_pane(brush, mode, village_pane)
	)
	village_pane.restore_hover_changed.connect(
		func(over: bool) -> void:
			if brush.editor != null and mode.selected_village > 0:
				mode.props.preview_restore(brush.editor, mode.selected_village, over)
				brush.redraw()
	)


## Applies a Boundary pane choice to village `village`: Automatic gives back the kit's draw, None
## sets no boundary, any other choice is a VillageBoundary.KINDS entry. One history entry, or false
## when nothing changed.
static func apply_boundary(editor: AuthoringEditor, village: int, choice: String) -> bool:
	match choice:
		VillageToolPane.AUTO_CHOICE:
			return editor.settlements.auto_boundary(village)
		VillageToolPane.NONE_CHOICE:
			return editor.settlements.set_boundary(village, "")
		_:
			return editor.settlements.set_boundary(village, choice)


## Shows the open document's villages, and the mode's pick, on `pane`.
static func refresh_pane(brush: BrushTool, mode: VillageBrush, pane: VillageToolPane) -> void:
	if not is_instance_valid(pane) or brush.editor == null:
		return
	var editor := brush.editor
	var state := state_for(editor.document, mode)
	if mode.sizing():
		state = VillagePlazas.with_preview(state, mode.preview_radius())
	var k :=ScaleUtils.world_to_display(editor.map_scale(), brush.unit_cell_m, brush.unit_per_cell)
	pane.show_state(state, k, brush.unit_label)


## What the pane shows for `mode` on `doc`: the picked village, its plazas and fields, the picked
## disc and what a press lays.
static func state_for(doc: MapDocument, mode: VillageBrush) -> Dictionary:
	var plaza := mode.selected_plaza if mode.selected_group == VillageFields.GROUP_PLAZAS else -1
	var state := VillagePlazas.state_of(doc, mode.selected_village, plaza)
	state = VillageFields.with_fields(
		state, doc, mode.selected_village, mode.selected_group, mode.selected_plaza, mode.field_kind
	)
	state["lay_field"] = mode.lay_field
	state["prop"] = mode.props.pane_state(doc, mode.selected_village)
	return state
