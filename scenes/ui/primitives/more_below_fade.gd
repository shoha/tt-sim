class_name MoreBelowFade
extends Control

## A band over the foot of a PaneStack that says more of the pane on show waits below: the
## surface colour rising from clear to nearly solid, with a small down chevron in it, so the row
## the foot cuts reads as continuing and not as clipped. It shows only while the pane can scroll
## further and goes at the end of the scroll (UI_TASTE round 2: Place and Biome cut their last
## tile row with only ScrollFade's soft mask to say so). Solid colours only, no texture. It eases
## in and out over UiMotion.FEEDBACK_IN_S, and cuts under Reduce motion. It takes no input.
##
## Owned by a PaneStack (PaneStack.more_below_fade); it reads the stack's current pane's scroll.

## The band's height in virtual px.
const HEIGHT := 44.0
## How solid the band is at the foot.
const FOOT_ALPHA := 0.96
const CHEVRON_PX := 16.0

var _stack: PaneStack
var _amount: float = 0.0
var _last_amount: float = -1.0


func _init() -> void:
	name = "MoreBelowFade"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_stack = get_parent() as PaneStack


## Whether the pane on show can scroll further down.
func more_below() -> bool:
	if _stack == null or not _stack.has_pane(_stack.current):
		return false
	var wrapper: ScrollContainer = _stack.wrapper_of(_stack.current)
	if wrapper == null or not wrapper.visible:
		return false
	var bar := wrapper.get_v_scroll_bar()
	return bar.max_value - bar.page > 1.0 and bar.value + bar.page < bar.max_value - 1.0


## How much of the band shows now, 0 to 1.
func amount() -> float:
	return _amount


func _process(delta: float) -> void:
	var target := 1.0 if more_below() else 0.0
	if UiMotion.reduced():
		_amount = target
	else:
		_amount = move_toward(_amount, target, delta / UiMotion.FEEDBACK_IN_S)
	if not is_equal_approx(_amount, _last_amount):
		_last_amount = _amount
		queue_redraw()


func _draw() -> void:
	if _amount <= 0.0:
		return
	var surface := ThemeColors.of(self, ThemeColors.SURFACE)
	var clear := surface
	clear.a = 0.0
	var foot := surface
	foot.a = FOOT_ALPHA * _amount
	var top := maxf(size.y - HEIGHT, 0.0)
	var band := PackedVector2Array(
		[Vector2(0.0, top), Vector2(size.x, top), Vector2(size.x, size.y), Vector2(0.0, size.y)]
	)
	draw_polygon(band, PackedColorArray([clear, clear, foot, foot]))
	var chevron := IconButton.load_icon("chevron-right")
	if chevron == null:
		return
	var tint := ThemeColors.of(self, ThemeColors.TEXT_SOFT)
	tint.a = _amount
	# The chevron points right; a quarter turn about its centre points it down.
	var centre := Vector2(size.x / 2.0, size.y - CHEVRON_PX * 0.75)
	draw_set_transform(centre, PI / 2.0, Vector2.ONE)
	draw_texture_rect(
		chevron,
		Rect2(Vector2(-CHEVRON_PX, -CHEVRON_PX) / 2.0, Vector2(CHEVRON_PX, CHEVRON_PX)),
		false,
		tint
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
