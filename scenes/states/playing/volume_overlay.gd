extends Node
class_name VolumeOverlay

## Renders a 3D volume indicator (sphere or cylinder) for MeasureTool.
## Adds MeshInstance3D geometry directly to the SubViewport for world-space rendering,
## and a 2D radius label in a CanvasLayer above the lo-fi shader.
##
## NOTE: Both the wireframe and fill use TRANSPARENCY_ALPHA (the preview wire color
## has alpha=0.5). Godot's lo-fi post-process (lofi_composite.gdshader) only captures
## opaque geometry, so both meshes render after the lo-fi pass and appear crisp.
## This is intentional — they read clearly as UI overlay elements distinct from world geometry.

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


## Show a volume shape. Call every frame during preview; call once to lock.
## [param shape] SPHERE or CYLINDER.
## [param center] World-space center of the shape.
## [param radius] XZ radius in world meters.
## [param label_text] Pre-formatted string, e.g. "20 ft" (from ScaleUtils.format_distance).
## [param is_preview] true while the user is dragging; false when the radius is locked.
func show(
	shape: Shape,
	center: Vector3,
	radius: float,
	label_text: String,
	is_preview: bool,
) -> void:
	_center = center
	_radius = radius
	_is_showing = true

	_wire_material.albedo_color = WIRE_COLOR_PREVIEW if is_preview else WIRE_COLOR_LOCKED
	_fill_material.albedo_color = FILL_COLOR_PREVIEW if is_preview else FILL_COLOR_LOCKED

	_update_wire_mesh(shape)
	_update_fill_mesh(shape)

	_fill_instance.visible = true
	_wire_instance.visible = true
	_label.text = label_text
	_label_panel.visible = true


func _update_wire_mesh(shape: Shape) -> void:
	_wire_mesh.clear_surfaces()
	_wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	match shape:
		Shape.SPHERE:
			_add_sphere_rings()
		Shape.CYLINDER:
			_add_cylinder_geometry()

	_wire_mesh.surface_end()


func _update_fill_mesh(shape: Shape) -> void:
	match shape:
		Shape.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = _radius
			sphere.height = _radius * 2.0
			_fill_instance.mesh = sphere
			_fill_instance.position = _center
		Shape.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = _radius
			cyl.bottom_radius = _radius
			cyl.height = CYLINDER_HEIGHT
			_fill_instance.mesh = cyl
			_fill_instance.position = _center + Vector3.UP * CYLINDER_HEIGHT * 0.5


func _add_sphere_rings() -> void:
	# XZ equatorial ring
	for i in range(RING_SEGMENTS):
		var a := TAU * i / RING_SEGMENTS
		var b := TAU * (i + 1) / RING_SEGMENTS
		_wire_mesh.surface_add_vertex(_center + Vector3(cos(a), 0.0, sin(a)) * _radius)
		_wire_mesh.surface_add_vertex(_center + Vector3(cos(b), 0.0, sin(b)) * _radius)

	# XY vertical ring
	for i in range(RING_SEGMENTS):
		var a := TAU * i / RING_SEGMENTS
		var b := TAU * (i + 1) / RING_SEGMENTS
		_wire_mesh.surface_add_vertex(_center + Vector3(cos(a), sin(a), 0.0) * _radius)
		_wire_mesh.surface_add_vertex(_center + Vector3(cos(b), sin(b), 0.0) * _radius)

	# YZ vertical ring
	for i in range(RING_SEGMENTS):
		var a := TAU * i / RING_SEGMENTS
		var b := TAU * (i + 1) / RING_SEGMENTS
		_wire_mesh.surface_add_vertex(_center + Vector3(0.0, cos(a), sin(a)) * _radius)
		_wire_mesh.surface_add_vertex(_center + Vector3(0.0, cos(b), sin(b)) * _radius)


func _add_cylinder_geometry() -> void:
	var top_y := _center.y + CYLINDER_HEIGHT

	# Bottom ring
	var bottom_verts := build_horizontal_ring(_center, _radius, 0.0, RING_SEGMENTS)
	for v in bottom_verts:
		_wire_mesh.surface_add_vertex(v)

	# Top ring
	var top_verts := build_horizontal_ring(_center, _radius, CYLINDER_HEIGHT, RING_SEGMENTS)
	for v in top_verts:
		_wire_mesh.surface_add_vertex(v)

	# Vertical lines
	for i in range(VERTICAL_LINES):
		var angle := TAU * i / VERTICAL_LINES
		var x := _center.x + cos(angle) * _radius
		var z := _center.z + sin(angle) * _radius
		_wire_mesh.surface_add_vertex(Vector3(x, _center.y, z))
		_wire_mesh.surface_add_vertex(Vector3(x, top_y, z))


func _process(_delta: float) -> void:
	if not _is_showing or not _camera or not _label_panel or not _label_panel.visible:
		return
	_update_label_position()


func _update_label_position() -> void:
	# Position label at the right edge of the shape, offset up to avoid overlapping the mesh.
	var edge_world := _center + Vector3.RIGHT * _radius
	var screen_pos := _camera.unproject_position(edge_world)
	screen_pos.y -= 24.0
	_label_panel.position = screen_pos - _label_panel.size * 0.5
