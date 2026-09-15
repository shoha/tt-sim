class_name DropIndicatorRenderer
extends Node3D

## Renders drop indicator visuals (dotted line + landing circle) during token dragging.
## This is a pure visual component - attach as child to a draggable object.
##
## RENDER ORDER NOTE:
## This uses OPAQUE rendering (TRANSPARENCY_DISABLED) intentionally. The lo-fi
## post-processing shader (lofi_canvas.gdshader) uses hint_screen_texture which
## only captures opaque objects. Transparent objects would render AFTER the screen
## texture is captured and thus wouldn't receive the lo-fi effect, making them
## visually inconsistent with the rest of the scene.
##
## Trade-off: We lose semi-transparency but gain visual cohesion with the scene.
## The bright emission color ensures visibility without needing alpha blending.

const DOT_LENGTH: float = 0.15
const DOT_GAP: float = 0.1
const LINE_THICKNESS: float = 0.03
const CIRCLE_RADIUS: float = 0.3  # Default/max circle radius
const MAX_CIRCLE_RADIUS: float = 0.4  # Cap to keep the indicator compact on large tokens
const CIRCLE_SEGMENTS: int = 32
const RAYCAST_LENGTH: float = 100.0
const TERRAIN_COLLISION_LAYER: int = 1  # Only raycast against terrain, not other tokens

## Pulsing animation settings
const PULSE_SPEED: float = 3.0
const PULSE_AMOUNT: float = 0.15

## Skip the raycast + line rebuild when start_position has barely moved since
## the last update() call -- avoids rebuilding the ImmediateMesh every frame.
const REBUILD_EPSILON: float = 0.001

## The RigidBody3D to exclude from raycasts (the token being dragged)
var exclude_body: RigidBody3D

var _line_mesh_instance: MeshInstance3D
var _line_immediate_mesh: ImmediateMesh
var _circle_mesh_instance: MeshInstance3D
var _circle_immediate_mesh: ImmediateMesh

## Dynamic circle radius (set from token collision footprint)
var _circle_radius: float = CIRCLE_RADIUS

## Pulse animation time
var _pulse_time: float = 0.0

## Cached raycast inputs/outputs from the last rebuild, so update() can skip
## re-raycasting and redrawing the line when the token hasn't moved.
var _last_start: Vector3 = Vector3.INF
var _last_hit: Dictionary = {}

## Debug counter: how many times the dotted line has actually been rebuilt.
## Exists so tests can assert a rebuild was (or wasn't) skipped.
var _line_rebuilds: int = 0

## True between show_indicator() and hide_indicator(). The circle mesh instance
## itself is only shown once _pose_circle() has actually posed it for a hit, so a
## fresh drag never flashes the circle at the origin or at a stale prior pose.
var _showing: bool = false


func _ready() -> void:
	_create_meshes()
	hide_indicator()


func _create_meshes() -> void:
	var material = _create_indicator_material()

	# Line mesh: rebuilt in world space whenever the drag start or raycast hit moves.
	# top_level = true so its transform is independent of the token and geometry can
	# be built directly in world space (no to_local conversions).
	_line_immediate_mesh = ImmediateMesh.new()
	_line_mesh_instance = MeshInstance3D.new()
	_line_mesh_instance.mesh = _line_immediate_mesh
	_line_mesh_instance.material_override = material
	_line_mesh_instance.top_level = true
	add_child(_line_mesh_instance)

	# Circle mesh: built once below as a unit-radius fan at the origin facing +Y,
	# then simply posed (transform + scale) every frame instead of being rebuilt.
	_circle_immediate_mesh = ImmediateMesh.new()
	_circle_mesh_instance = MeshInstance3D.new()
	_circle_mesh_instance.mesh = _circle_immediate_mesh
	_circle_mesh_instance.material_override = material.duplicate()
	_circle_mesh_instance.top_level = true
	add_child(_circle_mesh_instance)
	_build_circle_mesh()


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
	_showing = true
	_line_mesh_instance.show()
	# The circle is intentionally left hidden here -- it has no valid pose yet, and
	# showing it now would flash it at the origin (first drag) or at whatever pose
	# a previous drag last left it at. _pose_circle() shows it once update() has
	# actually posed it against a real hit.


func hide_indicator() -> void:
	_clear_line_mesh()
	# Force a fresh raycast + line rebuild on the next drag rather than trusting
	# stale cached values from whatever the previous drag last saw.
	_last_start = Vector3.INF
	_last_hit = {}
	_showing = false
	_line_mesh_instance.hide()
	_circle_mesh_instance.hide()


func _clear_line_mesh() -> void:
	if _line_immediate_mesh:
		_line_immediate_mesh.clear_surfaces()


## Updates the drop indicator based on the token's current position
## start_position: The bottom center of the token in global space
func update(start_position: Vector3) -> void:
	if not is_instance_valid(_line_mesh_instance):
		return

	# Advance pulse animation
	_pulse_time += get_process_delta_time()

	if start_position.distance_squared_to(_last_start) > REBUILD_EPSILON * REBUILD_EPSILON:
		_last_start = start_position
		_last_hit = _raycast_down(start_position)
		_rebuild_line(start_position)

	if _last_hit.is_empty():
		# No terrain under the drag -- match the old per-frame-rebuild behaviour of
		# not drawing a circle for a frame with no hit, instead of leaving it frozen
		# at its last pose.
		_circle_mesh_instance.hide()
		return

	# Apply pulsing to the landing circle radius
	var pulse_scale: float = 1.0 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMOUNT
	_pose_circle(_last_hit.position, _last_hit.normal, _circle_radius * pulse_scale)


## Clears and redraws the dotted line for the current _last_start/_last_hit.
## Split out of update() so the raycast-skip branch above stays simple.
func _rebuild_line(start_position: Vector3) -> void:
	_clear_line_mesh()
	if not _last_hit.is_empty():
		_draw_dotted_line(start_position, _last_hit.position)
	_line_rebuilds += 1


func _raycast_down(from: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAYCAST_LENGTH)
	query.collision_mask = TERRAIN_COLLISION_LAYER  # Only hit terrain, not other tokens
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


## top_level means the mesh instance's local space IS world space, so vertices
## are built directly in world space with no to_local conversion.
func _draw_thick_segment(start: Vector3, end: Vector3, perp1: Vector3, perp2: Vector3) -> void:
	var half_thickness: float = LINE_THICKNESS * 0.5

	var offset1: Vector3 = perp1 * half_thickness
	var offset2: Vector3 = perp2 * half_thickness
	var offset3: Vector3 = -offset1
	var offset4: Vector3 = -offset2

	# Draw 4 rectangular faces around the line
	_add_segment_face(start, end, offset1, offset2)
	_add_segment_face(start, end, offset2, offset3)
	_add_segment_face(start, end, offset3, offset4)
	_add_segment_face(start, end, offset4, offset1)


func _add_segment_face(start: Vector3, end: Vector3, offset_a: Vector3, offset_b: Vector3) -> void:
	var p1: Vector3 = start + offset_a
	var p2: Vector3 = start + offset_b
	var p3: Vector3 = end + offset_b
	var p4: Vector3 = end + offset_a

	# First triangle
	_line_immediate_mesh.surface_add_vertex(p1)
	_line_immediate_mesh.surface_add_vertex(p2)
	_line_immediate_mesh.surface_add_vertex(p3)

	# Second triangle
	_line_immediate_mesh.surface_add_vertex(p1)
	_line_immediate_mesh.surface_add_vertex(p3)
	_line_immediate_mesh.surface_add_vertex(p4)


## Builds the landing circle once as a unit-radius fan at the origin facing +Y.
## Posing it per frame (see _pose_circle) reorients/rescales this same prebuilt
## geometry instead of rebuilding the mesh every frame.
func _build_circle_mesh() -> void:
	_circle_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var angle_step: float = TAU / CIRCLE_SEGMENTS
	var center: Vector3 = Vector3.ZERO

	for i in range(CIRCLE_SEGMENTS):
		var angle1: float = i * angle_step
		var angle2: float = (i + 1) * angle_step

		var p1: Vector3 = Vector3(cos(angle1), 0.0, sin(angle1))
		var p2: Vector3 = Vector3(cos(angle2), 0.0, sin(angle2))

		_circle_immediate_mesh.surface_add_vertex(center)
		_circle_immediate_mesh.surface_add_vertex(p1)
		_circle_immediate_mesh.surface_add_vertex(p2)

	_circle_immediate_mesh.surface_end()


## Poses the prebuilt unit circle to land on the hit point, oriented to the
## surface normal and scaled to the (pulsing) radius.
func _pose_circle(hit_position: Vector3, normal: Vector3, radius: float) -> void:
	# Create a basis oriented to the surface
	var up: Vector3 = normal
	var right: Vector3 = up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward: Vector3 = right.cross(up).normalized()

	# Offset slightly above the surface to prevent z-fighting
	var origin: Vector3 = hit_position + normal * 0.01

	_circle_mesh_instance.global_transform = Transform3D(Basis(right, up, forward), origin)
	_circle_mesh_instance.scale = Vector3.ONE * radius
	if _showing:
		_circle_mesh_instance.show()
