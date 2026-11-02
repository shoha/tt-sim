@tool
class_name Draggable3D
extends Node3D

## Something the player can pick up with the mouse: a Node3D that owns one physics body (the
## first CollisionObject3D below it) and hands presses on that body to the DragController. The
## controller moves the body; this node only reports the lifecycle back as signals
## (dragging_started / dragging_stopped / dragging_cancelled, no arguments) and says how high
## above the ground the body should ride (height_offset) and on which ground it rests
## (drag_resolver). DraggableToken is the one subclass: it adds the pickup spring, the lean,
## the settle and the network sync.
##
## The body must have physics picking on (input_ray_pickable) and sit in a SubViewport with
## physics_object_picking, which is how a press on it arrives as an input_event.

signal dragging_started
signal dragging_stopped
signal dragging_cancelled

## How far above the ground point the body's origin rides while dragged. DraggableToken keeps
## this at half the token's height and tweens it up for the pickup spring.
@export var height_offset: float = 0.0
## Whether the body takes part in physics picking (it must, to be pressed).
@export var input_ray_pickable: bool = true

## The CollisionObject3D that is picked and moved.
var body: CollisionObject3D


func _ready() -> void:
	body = _find_body()
	if body:
		body.input_event.connect(_on_body_input_event)
		body.input_ray_pickable = input_ray_pickable


func get_rid() -> RID:
	return body.get_rid()


func get_height_offset() -> float:
	return height_offset


## The ground resolver this object drags on (DragController.ground_resolver, valid): the shared
## one by default. An object that rests differently overrides this to bind its own trailing
## arguments (DraggableToken binds its water draft, so a swimmer is dragged at swim depth).
func drag_resolver(resolver: Callable) -> Callable:
	return resolver


## A mouse event on the body. A left press hands the drag to the controller, with the press
## position in the viewport's own coordinate space (the space the controller later compares
## motion events against).
func _on_body_input_event(
	_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int
) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.is_pressed():
		return
	press_at(button.position)


## Arm a drag on this object as if its body were pressed at `screen_position` (viewport
## coordinates). Returns whether a drag was armed (false when there is no controller, dragging
## is switched off, or a subclass refuses). The one entry for a press that does not come from
## the body's own picking, such as a click on a token's map pin (TokenMarkers).
func press_at(screen_position: Vector2) -> bool:
	var controller := get_tree().get_first_node_in_group(DragController.GROUP) as DragController
	if controller == null or not controller.dragging_enabled:
		return false
	controller.press(self, screen_position)
	return true


func _find_body() -> CollisionObject3D:
	var found := find_children("*", "CollisionObject3D", true, false)
	return found[0] as CollisionObject3D if not found.is_empty() else null


func _get_configuration_warnings() -> PackedStringArray:
	if _find_body() == null:
		return PackedStringArray(
			["No CollisionObject3D below this node, so it cannot be picked up. Add a body."]
		)
	return PackedStringArray()
