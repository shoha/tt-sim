class_name ScrollFade
extends Node

## Fades the bottom edge of a ScrollContainer's content while more of it waits below, so a
## long section ends in a soft fade rather than a row cut through its glyphs (Settings,
## Graphics). Add one as a child of the ScrollContainer.
##
## The container becomes its own mask: it draws an opaque rect that ends in an opaque to
## clear ramp at most HEIGHT tall, and clips its children to that alpha (CLIP_CHILDREN_ONLY),
## so the fade works over any surface without knowing its colour. Scrolled to the end, the
## mask is the whole rect and the last row shows whole.
##
## The ramp starts no higher than the top of the row the bottom edge cuts (or the bottom of
## the last whole row, when the edge falls between rows): a row in full view is never dimmed,
## since a half-faded row reads as a disabled one. A row is a shown control laid out by a
## VBoxContainer inside the scroll.
##
## With `at_top` (the title's library grid, whose top is a hard clip under its sticky heading)
## the top edge fades too, over TOP_HEIGHT, once the content has scrolled: the ramp comes in
## with the first TOP_HEIGHT px of scroll (top_alpha), so the grid at rest is untouched and a
## card scrolled under the heading thins out instead of being cut by a straight line.
## `at_bottom` off leaves the foot alone (a grid that runs to the window's edge).

## The fade's height in virtual px at most: about half a row.
const HEIGHT := 24.0
## The top fade's height: the grid's 12 px room over its first line and a little of the card.
const TOP_HEIGHT := 20.0

## Fade the top edge once scrolled.
var at_top := false
## Fade the bottom edge while more waits below.
var at_bottom := true

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
	# The opaque middle runs from under the top ramp (if any) to over the bottom one (if any).
	var start := 0.0
	var edge := top_alpha(float(_scroll.scroll_vertical)) if at_top else 1.0
	if edge < 1.0:
		start = minf(TOP_HEIGHT, size.y)
		var faded := Color.WHITE
		faded.a = edge
		_ramp(0.0, start, faded, Color.WHITE)
	var end := size.y
	if at_bottom and more_below():
		end = maxf(fade_top(_row_spans(), size.y), start)
		_ramp(end, size.y, Color.WHITE, Color.TRANSPARENT)
	_scroll.draw_rect(Rect2(0.0, start, size.x, end - start), Color.WHITE)


## A band of the mask from `from` to `to`, its alpha running from `upper` to `lower`.
func _ramp(from: float, to: float, upper: Color, lower: Color) -> void:
	var width := _scroll.size.x
	var band := PackedVector2Array(
		[Vector2(0.0, from), Vector2(width, from), Vector2(width, to), Vector2(0.0, to)]
	)
	_scroll.draw_polygon(band, PackedColorArray([upper, upper, lower, lower]))


## The mask's alpha at the very top edge after `scrolled` px of scroll: whole at rest, clear
## from TOP_HEIGHT on, so the top fade comes in with the scroll rather than at once. Pure.
static func top_alpha(scrolled: float) -> float:
	return 1.0 - clampf(scrolled / TOP_HEIGHT, 0.0, 1.0)


## Where the fade starts for a view `bottom` tall over rows spanning `spans` (Vector2(top,
## bottom) in the view's coordinates): HEIGHT above the edge, or lower, at the top of the
## innermost row the edge cuts, or the bottom of the last row above it, so no whole row fades.
## Pure.
static func fade_top(spans: Array[Vector2], bottom: float) -> float:
	var top := maxf(bottom - HEIGHT, 0.0)
	for span in spans:
		if span.x >= bottom:
			continue
		top = maxf(top, span.x if span.y > bottom else span.y)
	return minf(top, bottom)


## The spans of the rows inside the scroll, in its own coordinates.
func _row_spans() -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var origin := _scroll.get_global_rect().position.y
	for node in _scroll.find_children("*", "Control", true, false):
		var row := node as Control
		if not (row.get_parent() is VBoxContainer) or not row.is_visible_in_tree():
			continue
		var rect := row.get_global_rect()
		spans.append(Vector2(rect.position.y - origin, rect.end.y - origin))
	return spans
