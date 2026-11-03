class_name DragController
extends Node3D

## Picks tokens up with the mouse and carries them across the map. One lives in the GameMap's
## world viewport; every Draggable3D below the map finds it through the group and hands it a
## press (press()), and it drives the rest: the drag threshold, the ground ray, the follow,
## the drop and the cancel.
##
## A drag, as the player sees it:
##   1. Left press on a token arms a drag; nothing moves yet (DragState PENDING).
##   2. Once the pointer has travelled drag_threshold_px the drag begins: dragging_started.
##   3. Each frame the body eases toward a target on the ground under the cursor (the physics
##      ray from the camera, snapped to the grid unless Shift is held, put on the terrain by the
##      ground_resolver, lifted by the token's own height and the mouse wheel's steps).
##   4. Left release drops (dragging_stopped, the body placed on the exact target XZ), right
##      click or Escape cancels (dragging_cancelled; the token walks itself back).
##
## The pure rules live in DragMath and DragState; this node is the input, the ray and the signals.
## The camera controller reads is_dragging() and edge_pan_direction to pan while a token is held
## near the screen edge, and DragRuler reads the target to draw the measured line.

signal dragging_started(subject: Draggable3D)
signal dragging_stopped(subject: Draggable3D)
signal dragging_cancelled(subject: Draggable3D)

## The group every controller is in, so a draggable can find it without a path.
const GROUP := &"drag_controller"

## Length of the ground ray from the camera, in metres.
@export var ray_depth: float = 100.0
## Physics layers the ground ray hits.
@export_flags_3d_physics var collision_mask: int = 1
## How quickly the held body follows the target. Higher is snappier; the follow is a
## frame-rate independent exponential.
@export var drag_speed: float = 20.0

@export_group("Drag Feel")
## Pixels of mouse movement required before a drag begins, so a click never nudges a token.
@export var drag_threshold_px: float = 5.0
## Height adjustment per mouse wheel notch while dragging.
@export var height_step: float = 0.25

@export_group("Edge Pan")
## Pan the camera when a token is held near the screen edge.
@export var edge_pan_enabled: bool = true
## Distance from the screen edge, in pixels, where panning starts.
@export var edge_pan_margin: float = 50.0
## Camera pan speed multiplier while edge panning (read by the camera controller).
@export var edge_pan_speed: float = 4.0

## Edge pan direction in screen space, read by the camera controller. X: -1 left edge, +1 right
## edge. Y: -1 top edge, +1 bottom edge.
var edge_pan_direction: Vector2 = Vector2.ZERO

## When false, new drags are blocked (for example while the measure tool is active).
var dragging_enabled: bool = true

## Grid snap: when true, a held token aims at grid cell centres on XZ. GameMap configures it
## from LevelData. Hold Shift during a drag for a free move.
var grid_snap_enabled: bool = false
var grid_cell_size: float = 1.524
var grid_origin: Vector2 = Vector2.ZERO

## Optional func(point: Vector3) -> Vector3: the ground under `point`'s XZ, or Vector3.INF.
## When set, the drag target's height is re-resolved on it after the grid snap, so a token
## snapped across a tier edge rides on the tier its cell is on, not on the height the cursor ray
## hit. GameMap sets it only for maps with authored terrain; Blender maps leave it empty and
## keep the cursor-hit height. The dragged object may bind trailing arguments to it first
## (Draggable3D.drag_resolver).
var ground_resolver: Callable = Callable()

## Optional func(world_xz: Vector2) -> float: the ground height under world XZ (the map's
## GroundHeightField.world_height_at). With it, a perspective camera (the eye view) aims the
## drag at the first ground its ray meets on that field instead of the first physics hit
## (_pick_terrain); an orthographic camera keeps the physics ray either way. GameMap sets it.
var ground_height: Callable = Callable()

var _state: DragState = DragState.new()
var _target_drag_position: Vector3 = Vector3.ZERO
var _has_target_position: bool = false
## The target on the ground (after snap and ground_resolver, before the token's height offsets).
var _target_ground_position: Vector3 = Vector3.ZERO

# The latest pointer position from a motion or wheel event during a drag. The ground ray is cast
# from it at most once per frame, in _process, however many events arrived.
var _pending_pointer_position: Vector2 = Vector2.ZERO
var _pointer_dirty: bool = false

# Height added by the mouse wheel during the current drag.
var _wheel_offset: float = 0.0


func _ready() -> void:
	set_process(false)
	add_to_group(GROUP)


## A draggable was pressed at `press_position` (viewport coordinates): arm a drag on it. The
## drag only begins once the pointer has moved drag_threshold_px.
func press(subject: Draggable3D, press_position: Vector2) -> void:
	if not dragging_enabled:
		return
	_state.threshold = drag_threshold_px
	_state.press(subject, press_position)


## Begin dragging `subject` at once, with no press and no threshold. A press that crossed the
## threshold gets here too.
func begin_drag(subject: Draggable3D) -> void:
	if _state.is_active() or _state.begin(subject):
		_on_begun(subject)


## True while a token is held (not while a press is only armed). Used by the camera to block
## zoom and enable edge pan.
func is_dragging() -> bool:
	return _state.is_active()


## The held token, or null.
func get_subject() -> Draggable3D:
	return _subject()


## Where the held body is being steered (ground target plus the token's height offsets); valid
## while has_target().
func get_target_position() -> Vector3:
	return _target_drag_position


## The current target on the ground, before the height offsets; valid while has_target().
func get_target_ground_position() -> Vector3:
	return _target_ground_position


## Whether the pointer has produced a target yet in this drag.
func has_target() -> bool:
	return _has_target_position


## Drop the held token. It is placed on the exact target XZ (see DragMath.landing) and
## dragging_stopped is emitted; the token's own settle takes it from there.
func stop_drag() -> void:
	var subject := _subject()
	if subject == null:
		_reset_drag()
		return
	var body: Node3D = subject.body
	if _has_target_position and body:
		body.global_position = DragMath.landing(
			body.global_position, _target_drag_position, ground_resolver.is_valid()
		)
	edge_pan_direction = Vector2.ZERO
	dragging_stopped.emit(subject)
	subject.dragging_stopped.emit()
	_reset_drag()


## Cancel the held token's drag; the token returns itself to where the drag began.
func cancel_drag() -> void:
	var subject := _subject()
	if subject == null:
		_reset_drag()
		return
	edge_pan_direction = Vector2.ZERO
	dragging_cancelled.emit(subject)
	subject.dragging_cancelled.emit()
	_reset_drag()


## Aim the held token at the ground under `screen_position` (viewport coordinates). Called for
## every pointer event that moves the target, at most once per frame.
func update_target_position(screen_position: Vector2) -> void:
	var subject := _subject()
	if subject == null:
		return
	var hit := _pick_ground(screen_position, subject)
	if hit == Vector3.INF:
		return
	var snap := grid_snap_enabled and not Input.is_key_pressed(KEY_SHIFT)
	var resolver := ground_resolver
	if resolver.is_valid():
		resolver = subject.drag_resolver(resolver)
	_target_ground_position = DragMath.resolve_target_ground(
		hit, snap, grid_cell_size, grid_origin, resolver
	)
	_target_drag_position = DragMath.lifted_target(
		_target_ground_position, subject.get_height_offset(), _wheel_offset
	)
	_has_target_position = true


func _input(event: InputEvent) -> void:
	if _state.is_pending():
		_input_pending(event)
	elif _state.is_active():
		_input_active(event)


# A press is armed and waiting for the pointer to travel the threshold.
func _input_pending(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# The event's own position, not get_viewport().get_mouse_position(): that cached cursor
		# only follows real OS motion and is stale for injected events.
		if _state.motion(motion.position):
			var subject := _subject()
			_on_begun(subject)
			update_target_position(motion.position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_state.abort_pending()  # released before the threshold: a click
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			_state.abort_pending()


# A token is held.
func _input_active(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			stop_drag()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			cancel_drag()
			get_viewport().set_input_as_handled()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_step_height(height_step, button.position)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_step_height(-height_step, button.position)
	elif event is InputEventMouseMotion:
		_pending_pointer_position = (event as InputEventMouseMotion).position
		_pointer_dirty = true
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			cancel_drag()
			get_viewport().set_input_as_handled()


func _step_height(step: float, pointer: Vector2) -> void:
	_wheel_offset += step
	_pending_pointer_position = pointer
	_pointer_dirty = true
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var subject := _subject()
	if subject == null:
		# The held token left the tree (a level cleared mid-drag): nothing to carry.
		_reset_drag()
		return
	# Cast the ground ray at most once per frame, from the last event's position.
	if _pointer_dirty:
		_pointer_dirty = false
		update_target_position(_pending_pointer_position)
	if _has_target_position and subject.body:
		subject.body.global_position = DragMath.eased(
			subject.body.global_position, _target_drag_position, drag_speed, delta
		)
	_update_edge_pan()


func _on_begun(subject: Draggable3D) -> void:
	_wheel_offset = 0.0
	_pointer_dirty = false
	_has_target_position = false
	set_process(true)
	dragging_started.emit(subject)
	subject.dragging_started.emit()


## The held draggable, or null (also when it was freed mid-drag).
func _subject() -> Draggable3D:
	if not _state.is_active() or not is_instance_valid(_state.subject):
		return null
	return _state.subject as Draggable3D


func _reset_drag() -> void:
	_state.finish()
	_has_target_position = false
	_wheel_offset = 0.0
	_pointer_dirty = false
	edge_pan_direction = Vector2.ZERO
	set_process(false)


func _update_edge_pan() -> void:
	if not edge_pan_enabled or not _state.is_active():
		edge_pan_direction = Vector2.ZERO
		return
	var viewport := get_viewport()
	edge_pan_direction = DragMath.edge_pan(
		viewport.get_mouse_position(), viewport.get_visible_rect().size, edge_pan_margin
	)


## The 3D point under `screen_position`: a physics ray from the camera through it. Takes the
## position explicitly, from the event in hand, because get_viewport().get_mouse_position() is
## stale for injected input and would cast from an unrelated point. Vector3.INF when the ray
## hits nothing (or there is no camera).
func _pick_ground(screen_position: Vector2, subject: Draggable3D) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE and ground_height.is_valid():
		return _pick_terrain(camera, screen_position)
	var query := PhysicsRayQueryParameters3D.new()
	query.from = camera.project_ray_origin(screen_position)
	query.to = camera.project_position(screen_position, ray_depth)
	query.collide_with_areas = true
	query.collision_mask = collision_mask
	if subject.body:
		query.exclude = [subject.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## The drag target under `screen_position` for a perspective camera (the eye view): the first
## ground the ray meets on the map's height field (ViewGround.march), never a wall, roof or
## trunk in front of it, so a token pressed behind a house is carried on the ground and not onto
## its facade. Vector3.INF for a ray flatter than EyeRig.MIN_GROUND_RAY_DEG below the horizon or
## past ViewGround.MARCH_MAX_M: the token stays where it was.
func _pick_terrain(camera: Camera3D, screen_position: Vector2) -> Vector3:
	var hit: Variant = ViewGround.march(
		camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position),
		ground_height
	)
	return hit if hit != null else Vector3.INF
