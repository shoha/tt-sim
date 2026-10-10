class_name PaintTool
extends ToolDescriptor

## The Paint tool: lays a palette surface (a path, a yard, bare rock) on the document's own
## ground (BrushTool.Mode.PAINT; SurfaceStroke on the surface weights). Its pane is
## AuthoringPanel's surface swatches. A dressed Blender map's ground is the GLB's, so there
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
	brush_mode = BrushTool.Mode.PAINT
	unavailable_tooltip = UNAVAILABLE_TOOLTIP


## Only where the ground is the document's.
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and controller.editor.can_paint()


## Armed once a surface is picked (the pane preselects one).
func armed(controller: AuthoringController) -> bool:
	return controller.brush.paint_surface != ""


## The picked surface's textures start loading and its tile shows as picked.
func prepare(controller: AuthoringController) -> void:
	controller.use_surface(controller.brush.paint_surface)


## The rail item, then which surfaces can take a paint slot and the Built tiles' order.
func refresh(controller: AuthoringController) -> void:
	super.refresh(controller)
	controller.refresh_paint_limits()
