class_name ShadowOutset
extends Container

## The holder ShadowGutter.outset puts around a scroll: its one child is laid out `room` px
## (left, top, right, bottom) larger than the holder on every side, and the holder's minimum size
## is the child's less that room, so the scroll's content stays exactly where it stood while its
## clip reaches out far enough for a button's shadow and focus ring at the content's edge.

## The room the child reaches out by, as (left, top, right, bottom).
var room: Vector4 = Vector4.ZERO:
	set(value):
		room = value
		update_minimum_size()
		queue_sort()


func _get_minimum_size() -> Vector2:
	var child := _child()
	if child == null:
		return Vector2.ZERO
	var wanted := child.get_combined_minimum_size()
	return Vector2(maxf(wanted.x - room.x - room.z, 0.0), maxf(wanted.y - room.y - room.w, 0.0))


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var child := _child()
	if child != null:
		var whole := Vector2(size.x + room.x + room.z, size.y + room.y + room.w)
		fit_child_in_rect(child, Rect2(-room.x, -room.y, whole.x, whole.y))


func _child() -> Control:
	for node in get_children():
		if node is Control:
			return node as Control
	return null
