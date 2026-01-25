extends Node3D
class_name DropIndicatorRenderer

## Renders drop indicator visuals (dotted line + landing circle) during token dragging
## This is a pure visual component - attach as child to a draggable object

const DOT_LENGTH: float = 0.15
const DOT_GAP: float = 0.1
const LINE_THICKNESS: float = 0.03
const CIRCLE_RADIUS: float = 0.3
const CIRCLE_SEGMENTS: int = 32
const RAYCAST_LENGTH: float = 100.0

var _line_mesh_instance: MeshInstance3D
var _line_immediate_mesh: ImmediateMesh
var _circle_mesh_instance: MeshInstance3D
var _circle_immediate_mesh: ImmediateMesh

## The RigidBody3D to exclude from raycasts (the token being dragged)
var exclude_body: RigidBody3D


func _ready() -> void:
	_create_meshes()
	hide_indicator()


func _create_meshes() -> void:
	var material = _create_indicator_material()

	# Line mesh
	_line_immediate_mesh = ImmediateMesh.new()
	_line_mesh_instance = MeshInstance3D.new()
	_line_mesh_instance.mesh = _line_immediate_mesh
	_line_mesh_instance.material_override = material
	add_child(_line_mesh_instance)

	# Circle mesh
	_circle_immediate_mesh = ImmediateMesh.new()
	_circle_mesh_instance = MeshInstance3D.new()
	_circle_mesh_instance.mesh = _circle_immediate_mesh
	_circle_mesh_instance.material_override = material.duplicate()
	add_child(_circle_mesh_instance)


func _create_indicator_material() -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.0, 0.0, 0.5)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 0.0, 0.5)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func show_indicator() -> void:
	_line_mesh_instance.show()
	_circle_mesh_instance.show()


func hide_indicator() -> void:
	_clear_meshes()
	_line_mesh_instance.hide()
	_circle_mesh_instance.hide()


func _clear_meshes() -> void:
	if _line_immediate_mesh:
		_line_immediate_mesh.clear_surfaces()
	if _circle_immediate_mesh:
		_circle_immediate_mesh.clear_surfaces()


## Updates the drop indicator based on the token's current position
## start_position: The bottom center of the token in global space
func update(start_position: Vector3) -> void:
	if not is_instance_valid(_line_mesh_instance):
		return

	_clear_meshes()

	var hit_result = _raycast_down(start_position)
	if hit_result:
		_draw_dotted_line(start_position, hit_result.position)
		_draw_landing_circle(hit_result.position, hit_result.normal)


func _raycast_down(from: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAYCAST_LENGTH)
	if exclude_body:
		query.exclude = [exclude_body.get_rid()]
	return space_state.intersect_ray(query)


func _draw_dotted_line(from: Vector3, to: Vector3) -> void:
	var direction = (to - from).normalized()
	var total_distance = from.distance_to(to)

	if total_distance < 0.01:
		return

	# Create perpendicular vectors for line thickness
	var perp1 = direction.cross(Vector3.UP).normalized()
	if perp1.length_squared() < 0.001:
		perp1 = direction.cross(Vector3.RIGHT).normalized()
	var perp2 = direction.cross(perp1).normalized()

	_line_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var current_distance = 0.0
	while current_distance < total_distance:
		var dash_end_distance = min(current_distance + DOT_LENGTH, total_distance)
		var dash_start = from + direction * current_distance
		var dash_end = from + direction * dash_end_distance

		_draw_thick_segment(dash_start, dash_end, perp1, perp2)
		current_distance += DOT_LENGTH + DOT_GAP

	_line_immediate_mesh.surface_end()


func _draw_thick_segment(start: Vector3, end: Vector3, perp1: Vector3, perp2: Vector3) -> void:
	var half_thickness = LINE_THICKNESS * 0.5

	var offsets = [
		perp1 * half_thickness,
		perp2 * half_thickness,
		- perp1 * half_thickness,
		- perp2 * half_thickness
	]

	# Draw 4 rectangular faces around the line
	for i in range(4):
		var next_i = (i + 1) % 4
		var offset1 = offsets[i]
		var offset2 = offsets[next_i]

		var p1 = _line_mesh_instance.to_local(start + offset1)
		var p2 = _line_mesh_instance.to_local(start + offset2)
		var p3 = _line_mesh_instance.to_local(end + offset2)
		var p4 = _line_mesh_instance.to_local(end + offset1)

		# First triangle
		_line_immediate_mesh.surface_add_vertex(p1)
		_line_immediate_mesh.surface_add_vertex(p2)
		_line_immediate_mesh.surface_add_vertex(p3)

		# Second triangle
		_line_immediate_mesh.surface_add_vertex(p1)
		_line_immediate_mesh.surface_add_vertex(p3)
		_line_immediate_mesh.surface_add_vertex(p4)


func _draw_landing_circle(hit_position: Vector3, normal: Vector3) -> void:
	# Offset slightly above surface to prevent z-fighting
	var offset_position = hit_position + normal * 0.01

	# Create a basis oriented to the surface
	var up = normal
	var right = up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward = right.cross(up).normalized()

	_circle_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var angle_step = TAU / CIRCLE_SEGMENTS

	for i in range(CIRCLE_SEGMENTS):
		var angle1 = i * angle_step
		var angle2 = (i + 1) * angle_step

		var p1 = offset_position + (right * cos(angle1) + forward * sin(angle1)) * CIRCLE_RADIUS
		var p2 = offset_position + (right * cos(angle2) + forward * sin(angle2)) * CIRCLE_RADIUS

		var local_center = _circle_mesh_instance.to_local(offset_position)
		var local_p1 = _circle_mesh_instance.to_local(p1)
		var local_p2 = _circle_mesh_instance.to_local(p2)

		_circle_immediate_mesh.surface_add_vertex(local_center)
		_circle_immediate_mesh.surface_add_vertex(local_p1)
		_circle_immediate_mesh.surface_add_vertex(local_p2)

	_circle_immediate_mesh.surface_end()
