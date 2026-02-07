extends Node3D
class_name DropIndicatorRenderer

## Renders drop indicator visuals (dotted line + landing circle) during token dragging.
## This is a pure visual component - attach as child to a draggable object.
##
## RENDER ORDER NOTE:
## This uses OPAQUE rendering (TRANSPARENCY_DISABLED) intentionally. The lo-fi
## post-processing shader (lofi_composite.gdshader) uses hint_screen_texture which
## only captures opaque objects. Transparent objects would render AFTER the screen
## texture is captured and thus wouldn't receive the lo-fi effect, making them
## visually inconsistent with the rest of the scene.
##
## Trade-off: We lose semi-transparency but gain visual cohesion with the scene.
## The bright emission color ensures visibility without needing alpha blending.

const DOT_LENGTH: float = 0.15
const DOT_GAP: float = 0.1
const LINE_THICKNESS: float = 0.03
const CIRCLE_RADIUS: float = 0.3 # Default/max circle radius
const MAX_CIRCLE_RADIUS: float = 0.4 # Cap to keep the indicator compact on large tokens
const CIRCLE_SEGMENTS: int = 32
const RAYCAST_LENGTH: float = 100.0
const TERRAIN_COLLISION_LAYER: int = 1 # Only raycast against terrain, not other tokens

## Pulsing animation settings
const PULSE_SPEED: float = 3.0
const PULSE_AMOUNT: float = 0.15

var _line_mesh_instance: MeshInstance3D
var _line_immediate_mesh: ImmediateMesh
var _circle_mesh_instance: MeshInstance3D
var _circle_immediate_mesh: ImmediateMesh

## The RigidBody3D to exclude from raycasts (the token being dragged)
var exclude_body: RigidBody3D

## Dynamic circle radius (set from token collision footprint)
var _circle_radius: float = CIRCLE_RADIUS

## Pulse animation time
var _pulse_time: float = 0.0


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
	# Use opaque rendering so indicators are captured by post-process effects
	# Cyan/blue with emission for a softer, more polished look
	material.albedo_color = Color(0.2, 0.7, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.1, 0.5, 1.0, 1.0)
	material.emission_energy_multiplier = 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return material


## Set the circle radius based on the token's collision footprint.
## Call this when creating the indicator so it matches the token's size.
func set_token_footprint(collision_shape: CollisionShape3D) -> void:
	if collision_shape and collision_shape.shape:
		var aabb = collision_shape.shape.get_debug_mesh().get_aabb()
		# Use a fraction of the footprint so the indicator stays compact,
		# just large enough to communicate placement position
		_circle_radius = clampf(max(aabb.size.x, aabb.size.z) * 0.25, 0.2, MAX_CIRCLE_RADIUS)


func show_indicator() -> void:
	_pulse_time = 0.0
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

	# Advance pulse animation
	_pulse_time += get_process_delta_time()

	var hit_result = _raycast_down(start_position)
	if hit_result:
		_draw_dotted_line(start_position, hit_result.position)
		# Apply pulsing to the landing circle radius
		var pulse_scale = 1.0 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMOUNT
		_draw_landing_circle(hit_result.position, hit_result.normal, _circle_radius * pulse_scale)


func _raycast_down(from: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAYCAST_LENGTH)
	query.collision_mask = TERRAIN_COLLISION_LAYER # Only hit terrain, not other tokens
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


func _draw_landing_circle(hit_position: Vector3, normal: Vector3, radius: float) -> void:
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

		var p1 = offset_position + (right * cos(angle1) + forward * sin(angle1)) * radius
		var p2 = offset_position + (right * cos(angle2) + forward * sin(angle2)) * radius

		var local_center = _circle_mesh_instance.to_local(offset_position)
		var local_p1 = _circle_mesh_instance.to_local(p1)
		var local_p2 = _circle_mesh_instance.to_local(p2)

		_circle_immediate_mesh.surface_add_vertex(local_center)
		_circle_immediate_mesh.surface_add_vertex(local_p1)
		_circle_immediate_mesh.surface_add_vertex(local_p2)

	_circle_immediate_mesh.surface_end()
