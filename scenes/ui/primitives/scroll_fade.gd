class_name ScrollFade
extends Node

## Fades the bottom edge of a ScrollContainer's content while more of it waits below, so a
## long section ends in a soft fade rather than a row cut through its glyphs (Settings,
## Graphics). Add one as a child of the ScrollContainer.
##
## The container becomes its own mask: it draws an opaque rect that ends in an opaque to
## clear ramp HEIGHT tall, and clips its children to that alpha (CLIP_CHILDREN_ONLY), so the
## fade works over any surface without knowing its colour. Scrolled to the end, the mask is
## the whole rect and the last row shows whole.

## The fade's height in virtual px: about half a row.
const HEIGHT := 24.0

var _scroll: ScrollContainer


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer
	if _scroll == null:
		push_warning("ScrollFade: the parent is not a ScrollContainer")
		return
	_scroll.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_scroll.draw.connect(_on_draw)
	_scroll.resized.connect(_scroll.queue_redraw)
	var bar := _scroll.get_v_scroll_bar()
	bar.value_changed.connect(_on_scrolled)
	bar.changed.connect(_scroll.queue_redraw)


## Whether content waits below the visible part.
func more_below() -> bool:
	if _scroll == null:
		return false
	var bar := _scroll.get_v_scroll_bar()
	return bar.value + bar.page < bar.max_value - 1.0


func _on_scrolled(_value: float) -> void:
	_scroll.queue_redraw()


func _on_draw() -> void:
	var size := _scroll.size
	if not more_below():
		_scroll.draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
		return
	var top := maxf(size.y - HEIGHT, 0.0)
	_scroll.draw_rect(Rect2(0.0, 0.0, size.x, top), Color.WHITE)
	var ramp := PackedVector2Array(
		[Vector2(0.0, top), Vector2(size.x, top), Vector2(size.x, size.y), Vector2(0.0, size.y)]
	)
	var alpha := PackedColorArray([Color.WHITE, Color.WHITE, Color.TRANSPARENT, Color.TRANSPARENT])
	_scroll.draw_polygon(ramp, alpha)
