class_name FireTool
extends ToolDescriptor

## The Fire tool: persistent ground fire that keeps burning where painted, scorches its ground
## to ash, burns forest under it to snags, and never spreads (FireBrush does the gestures,
## FireEditor the edit, FireField the drawing). Its pane is FireToolPane. A dressed Blender
## map's ground is the GLB's, so there the tool is disabled with a tooltip saying why, as
## Paint is. A play brush too (card F2): the GM's Events pane lists it with the intensity tiles
## and Advanced (EventsPane), and its "Lay fire" group reaches every peer as three ops, the
## fire, the burnt forest and the ash (LiveEditCodec.ops_of). Design:
## docs/plans/2026-10-11-fire-features/design.md.

const ID := &"fire"
const LABEL := "Fire"
const UNAVAILABLE_TOOLTIP := "Fire: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Ground fire that keeps burning and leaves ash."
	icon = "campfire"
	brush_mode = FireBrush
	contexts = AUTHORING | PLAY
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [
		[
			"Left Drag (Fire)",
			(
				"Area: lay fire. Line: draw a line of fire. Trees under it burn to snags, the"
				+ " ground to ash"
			),
		],
		["Ctrl + Left Drag (Fire)", "Put fire out; the ash and snags stay"],
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> FireBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as FireBrush


## Only where the ground is the document's (the ash is a painted surface).
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and works_on(controller.editor)


func works_on(editor: AuthoringEditor) -> bool:
	return editor.can_paint()


## The burnt biome's assets and the ash's textures start loading, so the first lay's release
## binds them warm.
func prepare(controller: AuthoringController) -> void:
	warm(controller.editor)


## What a lay's release binds (the burnt biome's assets, the ash's textures, the flame
## material) starts loading on `editor`'s map: authoring's prepare(), and PlayEvents' pick.
static func warm(editor: AuthoringEditor) -> void:
	if editor == null:
		return
	var root := editor.palette_root
	var plan := FireSweep.plan_for(PaletteLibrary.biomes(root), PaletteLibrary.surfaces(root))
	if String(plan.biome) != "":
		editor.prepare_biome(String(plan.biome))
	if String(plan.surface) != "" and is_instance_valid(editor.terrain):
		editor.terrain.warm_surface(String(plan.surface))
	FireLook.request_book()


func build_pane(panel: AuthoringPanel) -> Control:
	return FireToolPane.new(panel)


## The shape and intensity tiles set the brush's mode, and the shape tiles follow Tab; size and
## strength go through the panel's own Advanced rows (AuthoringPanel.build_advanced), already
## wired to the brush.
func connect_pane(controller: AuthoringController, pane: Control) -> void:
	var fire_pane := pane as FireToolPane
	if fire_pane == null:
		return
	fire_pane.shape_selected.connect(
		func(value: int) -> void:
			if controller.brush != null:
				of(controller.brush).shape = value
				controller.brush.redraw()
	)
	fire_pane.intensity_selected.connect(
		func(value: int) -> void:
			if controller.brush != null:
				of(controller.brush).intensity = value
	)
	if controller.brush != null:
		controller.brush.shape_toggled.connect(
			func() -> void: fire_pane.select_shape(of(controller.brush).shape)
		)
