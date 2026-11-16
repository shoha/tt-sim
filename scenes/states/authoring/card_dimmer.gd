class_name CardDimmer
extends Node

## Steps the map tools' open card back while a brush is down on the board, so the stroke is seen
## over the footprint the card takes, and brings it back when the button is let go (the critic's
## seventh fix: the Biome and Place cards take about 29% of a 720p window). A press on the card or
## its rail does nothing here. Reduce motion cuts instead of easing. It only watches the mouse:
## the board's brush gets every event as before.

## The card and the rail beside it: a press over either is the author using the drawer.
var card: Control
var rail: Control
## Whether the card is open (a closed drawer has nothing to dim).
var is_open: Callable

var _tween: Tween


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or card == null:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not button.pressed:
		dim(false)
	elif is_open.call() and not _over_chrome(button.global_position):
		dim(true)


## Steps the card back (`on`) or returns it, eased over UiMotion's feedback times.
func dim(on: bool) -> void:
	var target := AuthoringChrome.STROKE_DIM if on else 1.0
	if _tween and _tween.is_valid():
		_tween.kill()
	if UiMotion.reduced() or is_equal_approx(card.modulate.a, target):
		card.modulate.a = target
		return
	var seconds := UiMotion.FEEDBACK_IN_S if on else UiMotion.FEEDBACK_OUT_S
	_tween = create_tween().set_trans(UiMotion.ARRIVE_TRANS).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "modulate:a", target, seconds)


func _over_chrome(point: Vector2) -> bool:
	return card.get_global_rect().has_point(point) or rail.get_global_rect().has_point(point)
