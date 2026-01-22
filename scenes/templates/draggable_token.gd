@tool

extends DraggingObject3D
class_name DraggableToken

## Adds drag-and-drop functionality to a token's RigidBody3D
## Handles visual feedback during dragging (drop indicators, lean effects)
## This is a pure interaction component - it has no knowledge of game entity data
##
## Expected hierarchy:
## DraggableToken (this)
## └── RigidBody3D
##     ├── CollisionShape3D (required)
##     └── Visual nodes (MeshInstance3D, etc.)

const ROTATION_FACTOR: float = 0.0001
const PICKUP_HEIGHT: float = 0.25 # How much to raise the token while dragging
const RAYCAST_LENGTH: float = 100.0 # Maximum distance to raycast downward
const DOT_LENGTH: float = 0.15 # Length of each dash in the dotted line
const DOT_GAP: float = 0.1 # Gap between dashes
const LINE_THICKNESS: float = 0.03 # Thickness of the line
const CIRCLE_RADIUS: float = 0.3 # Radius of the landing circle indicator
const CIRCLE_SEGMENTS: int = 32 # Number of segments for the circle
const INERTIA_LEAN_STRENGTH: float = 0.3 # How much the token leans from drag velocity (in radians)
const LEAN_SMOOTHING: float = 8.0 # How quickly the lean adjusts to velocity changes

var _base_height_offset: float = 0.0
var _line_mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _circle_mesh_instance: MeshInstance3D
var _circle_immediate_mesh: ImmediateMesh
var _last_drag_position: Vector3 = Vector3.ZERO
var _drag_velocity: Vector3 = Vector3.ZERO
var _target_lean_rotation: Basis = Basis.IDENTITY
var _visual_children: Array[Node3D] = []

@onready var _rigid_body: RigidBody3D = $RigidBody3D
@onready var _collision_shape: CollisionShape3D = $RigidBody3D/CollisionShape3D

func _ready() -> void:
	if not _rigid_body:
		return

	update_height_offset()

	# Only set up dragging signals and line mesh during gameplay
	if not Engine.is_editor_hint():
		# Collect all visual children (non-CollisionShape nodes) of the RigidBody3D
		_collect_visual_children()
		_create_line_mesh()

		# Connect to dragging signals to disable gravity while dragging
		dragging_started.connect(_on_dragging_started)
		dragging_stopped.connect(_on_dragging_stopped)

	super ()

func _create_line_mesh() -> void:
		# Create the line mesh for the drop indicator
		_immediate_mesh = ImmediateMesh.new()
		_line_mesh_instance = MeshInstance3D.new()
		_line_mesh_instance.mesh = _immediate_mesh

		# Create a material to make the line more visible
		var material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.0, 0.0, 0.5) # Bright red
		material.emission_enabled = true
		material.emission = Color(1.0, 0.0, 0.0, 0.5) # Bright red emission
		material.emission_energy_multiplier = 2.0
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_line_mesh_instance.material_override = material

		add_child(_line_mesh_instance)

		# Create the circle mesh for the landing indicator
		_circle_immediate_mesh = ImmediateMesh.new()
		_circle_mesh_instance = MeshInstance3D.new()
		_circle_mesh_instance.mesh = _circle_immediate_mesh
		_circle_mesh_instance.material_override = material.duplicate()

		add_child(_circle_mesh_instance)

func _collect_visual_children() -> void:
	# Collect all visual children of the rigid body (excluding collision shapes)
	for child in _rigid_body.get_children():
		if child is Node3D and not child is CollisionShape3D:
			_visual_children.append(child)

## Public method to update height offset based on bounding box
## Should be called when the token's scale or collision shape changes
func update_height_offset() -> void:
	if Engine.is_editor_hint():
		return

	if not _collision_shape or not _collision_shape.shape:
		return

	# Get the bounding box of the shape
	var aabb: AABB = _collision_shape.shape.get_debug_mesh().get_aabb()

	# Account for the rigid_body's scale transformation
	var scaled_aabb_position = aabb.position * _rigid_body.scale
	var scaled_aabb_size = aabb.size * _rigid_body.scale

	# Account for the collision shape's local position (also affected by scale)
	var scaled_collision_position = _collision_shape.position * _rigid_body.scale

	# Calculate the top of the shape with scaling applied
	var shape_top = scaled_collision_position.y + scaled_aabb_position.y + scaled_aabb_size.y

	# Set height offset to align the bottom of the bounding box at y=0
	_base_height_offset = shape_top / 2
	heightOffset = shape_top / 2

## Get the visual children (non-collision nodes) of the rigid body
## Useful for external components that need to manipulate visuals
func get_visual_children() -> Array[Node3D]:
	return _visual_children

func _on_dragging_started() -> void:
	# Disable gravity while dragging
	_rigid_body.gravity_scale = 0.0
	# Raise the token to create a "picked up" effect
	heightOffset = _base_height_offset + PICKUP_HEIGHT
	# Initialize drag tracking
	_last_drag_position = _rigid_body.global_position
	_drag_velocity = Vector3.ZERO

func _on_dragging_stopped() -> void:
	# Reset visual children rotation
	for child in _visual_children:
		if is_instance_valid(child):
			child.transform.basis = Basis.IDENTITY

	# Re-enable gravity when dragging stops
	_rigid_body.gravity_scale = 1.0

	# Lower the token back to its base height
	heightOffset = _base_height_offset
	# Clear the line and circle
	if _immediate_mesh and is_instance_valid(_line_mesh_instance):
		_immediate_mesh.clear_surfaces()
	if _circle_immediate_mesh and is_instance_valid(_circle_mesh_instance):
		_circle_immediate_mesh.clear_surfaces()
	# Reset velocity tracking
	_drag_velocity = Vector3.ZERO
	_target_lean_rotation = Basis.IDENTITY

func _update_inertia_lean(delta: float) -> void:
	# Calculate drag velocity from position change
	var current_position = _rigid_body.global_position
	var position_delta = current_position - _last_drag_position

	# Smooth the velocity to avoid jitter
	_drag_velocity = _drag_velocity.lerp(position_delta / delta, 0.3)
	_last_drag_position = current_position

	# Calculate lean based on horizontal (XZ plane) movement
	var horizontal_velocity = Vector3(_drag_velocity.x, 0, _drag_velocity.z)

	if horizontal_velocity.length() > 0.001:
		# Calculate lean axis perpendicular to movement direction (cross with UP)
		var lean_axis = horizontal_velocity.cross(Vector3.UP).normalized()
		# Calculate lean angle based on velocity magnitude
		var lean_angle = clamp(horizontal_velocity.length() * INERTIA_LEAN_STRENGTH, 0.0, 0.5) # Max ~28 degrees

		# Create target lean rotation
		_target_lean_rotation = Basis(lean_axis, lean_angle)
	else:
		# No movement, return to upright
		_target_lean_rotation = Basis.IDENTITY

	# Apply rotation to visual children only, not the rigid body
	for child in _visual_children:
		if is_instance_valid(child):
			var current_basis = child.transform.basis.orthonormalized()
			child.transform.basis = current_basis.slerp(_target_lean_rotation, LEAN_SMOOTHING * delta).orthonormalized()

func _process(_delta: float) -> void:
	# Only update drop indicator during gameplay when dragging
	if Engine.is_editor_hint():
		return
	if _is_dragging:
		_update_drop_indicator()
		_update_inertia_lean(_delta)

func _update_drop_indicator() -> void:
	# Safety check to ensure mesh instance is valid
	if not _line_mesh_instance or not is_instance_valid(_line_mesh_instance):
		return

	# Clear previous line and circle
	_immediate_mesh.clear_surfaces()
	_circle_immediate_mesh.clear_surfaces()

	# Get the bottom center of the token
	if not _collision_shape or not _collision_shape.shape:
		return

	var aabb: AABB = _collision_shape.shape.get_debug_mesh().get_aabb()
	var scaled_aabb_position = aabb.position * _rigid_body.scale
	var scaled_collision_position = _collision_shape.position * _rigid_body.scale
	var bottom_y = scaled_collision_position.y + scaled_aabb_position.y

	# Start from the bottom of the token in global space
	var start_pos = _rigid_body.global_position + Vector3(0, bottom_y, 0)

	# Raycast downward
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(start_pos, start_pos + Vector3.DOWN * RAYCAST_LENGTH)
	query.exclude = [_rigid_body.get_rid()]
	var result = space_state.intersect_ray(query)

	if result:
		var end_pos = result.position
		var surface_normal = result.normal
		_draw_dotted_line(start_pos, end_pos)
		_draw_landing_circle(end_pos, surface_normal)

func _draw_dotted_line(from: Vector3, to: Vector3) -> void:
	var direction = (to - from).normalized()
	var total_distance = from.distance_to(to)

	# Don't draw if distance is too small
	if total_distance < 0.01:
		return

	var current_distance = 0.0

	# Create perpendicular vectors for cylinder-like line thickness
	var perp1 = direction.cross(Vector3.UP).normalized()
	if perp1.length_squared() < 0.001: # If direction is parallel to UP
		perp1 = direction.cross(Vector3.RIGHT).normalized()
	var perp2 = direction.cross(perp1).normalized()

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	while current_distance < total_distance:
		var dash_end_distance = min(current_distance + DOT_LENGTH, total_distance)
		var dash_start = from + direction * current_distance
		var dash_end = from + direction * dash_end_distance

		# Create a thick line using quads (two triangles per side, 4 sides for rounded look)
		_draw_thick_segment(dash_start, dash_end, perp1, perp2)

		current_distance += DOT_LENGTH + DOT_GAP

	_immediate_mesh.surface_end()

func _draw_thick_segment(start: Vector3, end: Vector3, perp1: Vector3, perp2: Vector3) -> void:
	# Safety check
	if not _line_mesh_instance or not is_instance_valid(_line_mesh_instance):
		return

	var half_thickness = LINE_THICKNESS * 0.5

	# Create 4 sides of a rectangular prism
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
		_immediate_mesh.surface_add_vertex(p1)
		_immediate_mesh.surface_add_vertex(p2)
		_immediate_mesh.surface_add_vertex(p3)

		# Second triangle
		_immediate_mesh.surface_add_vertex(p1)
		_immediate_mesh.surface_add_vertex(p3)
		_immediate_mesh.surface_add_vertex(p4)

func _draw_landing_circle(hit_position: Vector3, normal: Vector3) -> void:
	# Safety check
	if not _circle_mesh_instance or not is_instance_valid(_circle_mesh_instance):
		return

	# Offset the circle slightly above the surface to prevent z-fighting
	var offset_position = hit_position + normal * 0.01

	# Create a basis oriented to the surface
	var up = normal
	var right = up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward = right.cross(up).normalized()

	# Draw the circle as a triangle fan
	_circle_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var angle_step = TAU / CIRCLE_SEGMENTS

	for i in range(CIRCLE_SEGMENTS):
		var angle1 = i * angle_step
		var angle2 = (i + 1) * angle_step

		# Calculate points on the circle
		var p1 = offset_position + (right * cos(angle1) + forward * sin(angle1)) * CIRCLE_RADIUS
		var p2 = offset_position + (right * cos(angle2) + forward * sin(angle2)) * CIRCLE_RADIUS

		# Convert to local space
		var local_center = _circle_mesh_instance.to_local(offset_position)
		var local_p1 = _circle_mesh_instance.to_local(p1)
		var local_p2 = _circle_mesh_instance.to_local(p2)

		# Create triangle from center to edge
		_circle_immediate_mesh.surface_add_vertex(local_center)
		_circle_immediate_mesh.surface_add_vertex(local_p1)
		_circle_immediate_mesh.surface_add_vertex(local_p2)

	_circle_immediate_mesh.surface_end()

func _exit_tree() -> void:
	if _line_mesh_instance:
		_line_mesh_instance.queue_free()
	if _circle_mesh_instance:
		_circle_mesh_instance.queue_free()
