class_name PaintTool
extends ToolDescriptor

## The Paint tool: lays a palette surface (a path, a yard, bare rock) on the document's own
## ground (PaintBrush; SurfaceStroke on the surface weights). Its pane is AuthoringPanel's
## surface swatches. A dressed Blender map's ground is the GLB's, so there
## the tool is disabled with a tooltip saying why; while every paint slot holds paint, the
## tiles of the other surfaces are disabled (AuthoringController.refresh_paint_limits).

const ID := &"paint"
const LABEL := "Paint"
const UNAVAILABLE_TOOLTIP := "Paint: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Lay paths, yards and rock."
	icon = "brush"
	brush_mode = PaintBrush
	contexts = AUTHORING | PLAY
	unavailable_tooltip = UNAVAILABLE_TOOLTIP


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> PaintBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as PaintBrush


## Only where the ground is the document's.
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and works_on(controller.editor)


func works_on(editor: AuthoringEditor) -> bool:
	return editor.can_paint()


## Armed once a surface is picked (the pane preselects one).
func armed(controller: AuthoringController) -> bool:
	return of(controller.brush).surface != ""


## The picked surface's textures start loading and its tile shows as picked.
func prepare(controller: AuthoringController) -> void:
	controller.use_surface(of(controller.brush).surface)


## The rail item, then which surfaces can take a paint slot and the Built tiles' order.
func refresh(controller: AuthoringController) -> void:
	super.refresh(controller)
	controller.refresh_paint_limits()
