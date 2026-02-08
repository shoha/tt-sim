@tool
extends Node3D
class_name DragAndDrop3D

signal dragging_started(draggingObject: DraggingObject3D)
signal dragging_stopped(draggingObject: DraggingObject3D)
signal dragging_cancelled(draggingObject: DraggingObject3D)

@export var mousePositionDepth := 100
@export var groupExclude: Array[String] = []
@export_flags_3d_physics var collisionMask: int = 1
## Controls how quickly the dragged object follows the cursor.
## Higher values = snappier response. Uses frame-rate independent exponential smoothing.
@export var drag_speed := 20.0

@export_group("Drag Feel")
## Pixels of mouse movement required before a drag begins.
## Prevents accidental micro-drags when clicking tokens.
@export var drag_threshold_px: float = 5.0
## Height adjustment per scroll wheel step while dragging.
@export var height_step: float = 0.25

@export_group("Edge Pan")
## Enable camera panning when dragging a token near screen edges.
@export var edge_pan_enabled: bool = true
## Distance from screen edge (in pixels) that triggers panning.
@export var edge_pan_margin: float = 50.0
## Camera pan speed multiplier during edge panning.
@export var edge_pan_speed: float = 4.0

@export_group("Swap")
## If [code]true[/code], you swap the dragging objects if the snap position is already taken[br]
## So your drag Object will take the place and the object that was previously in the place becomes the drag object[br][br]
@export var swapDraggingObjects := false

@export_group("Snap")
@export var useSnap := false:
	set(value):
		useSnap = value
		notify_property_list_changed()
@export_enum("Node Children", "Group") var sourceSnapMode := "Node Children":
	set(value):
		sourceSnapMode = value
		notify_property_list_changed()
@export var snapSourceNode: Node
@export var SnapSourceGroup: String
@export var snapOverlap := false

var _currentDraggingObject: DraggingObject3D
var _otherObjectOnPosition: DraggingObject3D
var _target_drag_position: Vector3 = Vector3.ZERO
var _has_target_position: bool = false

# Drag threshold state
var _pending_drag_object: DraggingObject3D = null
var _drag_start_mouse_pos: Vector2 = Vector2.ZERO

# Height control during drag
var _drag_height_offset: float = 0.0

## Edge pan direction in screen space (read by camera controller).
## X: -1 = left edge, +1 = right edge. Y: -1 = top edge, +1 = bottom edge.
var edge_pan_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not Engine.is_editor_hint() and not DragAndDropGroupHelper.is_connected("group_added", _set_dragging_object_signals):
		DragAndDropGroupHelper.group_added.connect(_set_dragging_object_signals)

	_set_group()

func _set_group() -> void:
	if Engine.is_editor_hint(): return

	await get_tree().current_scene.ready
	DragAndDropGroupHelper.add_node_to_group(self, "DragAndDrop3D")

func _set_dragging_object_signals(group: String, node: Node) -> void:
	if group == "draggingObjects" and not node.is_connected("object_body_mouse_down", set_dragging_object):
		node.object_body_mouse_down.connect(set_dragging_object.bind(node))


## Called when a draggable object receives mouse down.
## Starts a pending drag that only activates after the mouse moves past the threshold.
func set_dragging_object(object: DraggingObject3D) -> void:
	if _currentDraggingObject or _pending_drag_object:
		return # Already dragging or pending
	_pending_drag_object = object
	_drag_start_mouse_pos = get_viewport().get_mouse_position()


## Actually begin the drag after the movement threshold is met.
func _begin_drag(object: DraggingObject3D) -> void:
	_currentDraggingObject = object
	_pending_drag_object = null
	_drag_height_offset = 0.0
	dragging_started.emit(_currentDraggingObject)


func _input(event: InputEvent) -> void:
	# --- Pending drag: waiting for mouse to move past threshold ---
	if _pending_drag_object and not _currentDraggingObject:
		if event is InputEventMouseMotion:
			var current_mouse = get_viewport().get_mouse_position()
			if current_mouse.distance_to(_drag_start_mouse_pos) >= drag_threshold_px:
				_begin_drag(_pending_drag_object)
				_update_target_position()
		elif event is InputEventMouseButton:
			if event.button_index == 1 and not event.is_pressed():
				# Released before threshold - this was a click, not a drag
				_pending_drag_object = null
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
				# Right-click cancels pending drag
				_pending_drag_object = null
		return

	# --- Active drag handling ---
	if not _currentDraggingObject:
		return

	if event is InputEventMouseButton:
		if event.button_index == 1 and not event.is_pressed():
			stop_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			cancel_drag()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			_drag_height_offset += height_step
			_update_target_position()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			_drag_height_offset -= height_step
			_update_target_position()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_target_position()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Frame-rate independent exponential smoothing
	if _currentDraggingObject and _has_target_position:
		var currentPos = _currentDraggingObject.objectBody.global_position
		var smooth_factor = 1.0 - exp(-drag_speed * delta)
		_currentDraggingObject.objectBody.global_position = currentPos.lerp(_target_drag_position, smooth_factor)

	# Update edge pan direction for camera controller to read
	_update_edge_pan()


func stop_drag() -> void:
	var swaped = _swap_dragging_objects()

	if swaped: return

	edge_pan_direction = Vector2.ZERO
	dragging_stopped.emit(_currentDraggingObject)

	_currentDraggingObject = null
	_has_target_position = false
	_drag_height_offset = 0.0


## Cancel the current drag and signal the dragged object to return to its start position.
func cancel_drag() -> void:
	if not _currentDraggingObject:
		return

	edge_pan_direction = Vector2.ZERO
	dragging_cancelled.emit(_currentDraggingObject)

	_currentDraggingObject = null
	_has_target_position = false
	_drag_height_offset = 0.0


## Check if a drag is currently active (used by camera to block zoom and enable edge pan).
func is_dragging() -> bool:
	return _currentDraggingObject != null


func _update_target_position() -> void:
	var mousePosition3D = _get_3d_mouse_position()

	if not mousePosition3D: return

	mousePosition3D.y += _currentDraggingObject.get_height_offset()
	mousePosition3D.y += _drag_height_offset
	_target_drag_position = mousePosition3D
	_has_target_position = true


## Compute edge pan direction based on mouse proximity to screen edges.
func _update_edge_pan() -> void:
	if not edge_pan_enabled or not _currentDraggingObject:
		edge_pan_direction = Vector2.ZERO
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var pan = Vector2.ZERO

	# Horizontal edges
	if mouse_pos.x < edge_pan_margin:
		pan.x = -(1.0 - mouse_pos.x / edge_pan_margin)
	elif mouse_pos.x > viewport_size.x - edge_pan_margin:
		pan.x = 1.0 - (viewport_size.x - mouse_pos.x) / edge_pan_margin

	# Vertical edges
	if mouse_pos.y < edge_pan_margin:
		pan.y = -(1.0 - mouse_pos.y / edge_pan_margin)
	elif mouse_pos.y > viewport_size.y - edge_pan_margin:
		pan.y = 1.0 - (viewport_size.y - mouse_pos.y) / edge_pan_margin

	edge_pan_direction = pan


func _get_3d_mouse_position():
	var mousePosition := get_viewport().get_mouse_position()
	var currentCamera := get_viewport().get_camera_3d()
	var params := PhysicsRayQueryParameters3D.new()

	params.from = currentCamera.project_ray_origin(mousePosition)
	params.to = currentCamera.project_position(mousePosition, mousePositionDepth)
	params.collide_with_areas = true
	params.exclude = _get_excluded_objects()
	params.set_collision_mask(collisionMask)

	var worldspace := get_world_3d().direct_space_state
	var intersect := worldspace.intersect_ray(params)

	if not intersect: return

	var snapPosition = _get_snap_position(intersect.collider)
	var isColliderParentDraggingObject = intersect.collider.get_parent() is DraggingObject3D

	if useSnap and snapPosition:
		_currentDraggingObject.snapPosition = snapPosition
	else:
		_currentDraggingObject.snapPosition = intersect.position

	_set_dragging_object_on_position(snapPosition, intersect.collider)

	var newPosition
	if snapPosition and not isColliderParentDraggingObject: newPosition = snapPosition
	else: newPosition = intersect.position

	return newPosition

func _get_excluded_objects() -> Array:
	var exclude := []

	exclude.append(_currentDraggingObject.get_rid())

	for string in groupExclude:
		for node in get_tree().get_nodes_in_group(string):
			exclude.append(node.get_rid())

	if useSnap and snapOverlap:
		for object: DraggingObject3D in get_tree().get_nodes_in_group("draggingObjects"):
			exclude.append(object.get_rid())

	return exclude

func _get_snap_position(collider: Node):
	if not useSnap: return

	if collider.get_parent() is DraggingObject3D:
		return collider.get_parent().snapPosition
	elif sourceSnapMode == "Node Children" and snapSourceNode != null:
		for node in snapSourceNode.get_children():
			if collider == node:
				return node.global_position
	elif sourceSnapMode == "Group" and collider.is_in_group(SnapSourceGroup):
		return collider.global_position

func _set_dragging_object_on_position(snapPosition, collider) -> void:
	if collider.get_parent() is DraggingObject3D:
		_otherObjectOnPosition = collider.get_parent()
	else:
		for draggingObject: DraggingObject3D in get_tree().get_nodes_in_group("draggingObjects"):
			var sameSnapPosition = draggingObject.snapPosition == snapPosition
			var notCurrentObject = draggingObject != _currentDraggingObject

			if sameSnapPosition and notCurrentObject:
				_otherObjectOnPosition = draggingObject
				return

		_otherObjectOnPosition = null

func _swap_dragging_objects() -> bool:
	if (not swapDraggingObjects or
		not _otherObjectOnPosition or
		_otherObjectOnPosition.snapPosition == null): return false

	var position: Vector3 = _otherObjectOnPosition.snapPosition
	position.y += _currentDraggingObject.get_height_offset()

	_currentDraggingObject.objectBody.global_position = position
	_currentDraggingObject = _otherObjectOnPosition
	_otherObjectOnPosition = null

	return true

func _validate_property(property: Dictionary) -> void:
	var hideList = []

	hideList += _editor_snap_validate()

	if property.name in hideList:
		property.usage = PROPERTY_USAGE_NO_EDITOR

func _editor_snap_validate() -> Array:
	var list = []

	if useSnap:
		if sourceSnapMode == "Node Children":
			list.append("SnapSourceGroup")
		else:
			list.append("snapSourceNode")
	else:
		list.append("sourceSnapMode")
		list.append("SnapSourceGroup")
		list.append("snapSourceNode")
		list.append("snapOverlap")

	return list
