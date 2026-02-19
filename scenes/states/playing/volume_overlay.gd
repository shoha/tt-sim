extends Node
class_name VolumeOverlay

## Renders a 3D volume indicator (sphere or cylinder) for MeasureTool.
## Adds MeshInstance3D geometry directly to the SubViewport for world-space rendering,
## and a 2D radius label in a CanvasLayer above the lo-fi shader.
##
## NOTE: The fill mesh uses TRANSPARENCY_ALPHA. Godot's lo-fi post-process
## (lofi_composite.gdshader) only captures opaque geometry, so the fill will render
## after the lo-fi pass and appear crisp. The wireframe is opaque and will receive
## the lo-fi effect. This is intentional — the fill reads clearly as a UI overlay.

const CYLINDER_HEIGHT: float = 10.0   # World meters (~33 ft). Covers most TTRPG column spells.
const RING_SEGMENTS: int = 32
const VERTICAL_LINES: int = 8

const WIRE_COLOR_LOCKED := Color(1.0, 0.85, 0.2, 1.0)
const WIRE_COLOR_PREVIEW := Color(1.0, 0.85, 0.2, 0.5)
const FILL_COLOR_LOCKED := Color(1.0, 0.85, 0.2, 0.12)
const FILL_COLOR_PREVIEW := Color(1.0, 0.85, 0.2, 0.06)

enum Shape { SPHERE, CYLINDER }


## Build vertex pairs for a horizontal ring at center + (0, y_offset, 0).
## Returns PackedVector3Array with 2*segments vertices (pairs for PRIMITIVE_LINES).
static func build_horizontal_ring(
	center: Vector3, radius: float, y_offset: float, segments: int
) -> PackedVector3Array:
	var verts := PackedVector3Array()
	for i in range(segments):
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		verts.append(center + Vector3(cos(a) * radius, y_offset, sin(a) * radius))
		verts.append(center + Vector3(cos(b) * radius, y_offset, sin(b) * radius))
	return verts


## References — set once via setup()
var _camera: Camera3D
var _world_viewport: SubViewport

## 3D geometry nodes — added as children of _world_viewport
var _fill_instance: MeshInstance3D
var _wire_instance: MeshInstance3D
var _wire_mesh: ImmediateMesh

## Materials — created once in setup(), colors updated in show()
var _wire_material: StandardMaterial3D
var _fill_material: StandardMaterial3D

## 2D label — CanvasLayer + PanelContainer added to overlay_parent
var _canvas_layer: CanvasLayer
var _label_panel: PanelContainer
var _label: Label

## State
var _center: Vector3 = Vector3.ZERO
var _radius: float = 0.0
var _is_showing: bool = false


func _ready() -> void:
	set_process(false)


## One-time initialization. Called by MeasureTool.setup().
func setup(cam: Camera3D, viewport: SubViewport, overlay_parent: Node) -> void:
	_camera = cam
	_world_viewport = viewport
	_create_materials()
	_create_mesh_instances()
	_create_label(overlay_parent)
	set_process(true)


func clear() -> void:
	_is_showing = false
	if _fill_instance:
		_fill_instance.visible = false
	if _wire_instance:
		_wire_instance.visible = false
		_wire_mesh.clear_surfaces()
	if _label_panel:
		_label_panel.visible = false


func _create_materials() -> void:
	_wire_material = StandardMaterial3D.new()
	_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wire_material.albedo_color = WIRE_COLOR_LOCKED

	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_material.albedo_color = FILL_COLOR_LOCKED


func _create_mesh_instances() -> void:
	_wire_mesh = ImmediateMesh.new()
	_wire_instance = MeshInstance3D.new()
	_wire_instance.mesh = _wire_mesh
	_wire_instance.material_override = _wire_material
	_wire_instance.visible = false
	_world_viewport.add_child(_wire_instance)

	_fill_instance = MeshInstance3D.new()
	_fill_instance.material_override = _fill_material
	_fill_instance.visible = false
	_world_viewport.add_child(_fill_instance)


func _create_label(overlay_parent: Node) -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = Constants.LAYER_MEASURE_OVERLAY
	overlay_parent.add_child(_canvas_layer)

	var result := MapOverlayUtils.create_label_panel(16)
	_label_panel = result.panel
	_label = result.label
	_canvas_layer.add_child(_label_panel)
