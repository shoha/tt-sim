class_name ScrollBarFade
extends Node

## Shows a ScrollContainer's vertical bar only while it is wanted (user verdict 2026-10-10:
## scroll bars over content lists are the handle alone, visible while the pointer is over the
## list, fading in and out, never a bare persistent track). Add one as a child of the
## ScrollContainer, or call [method attach]; the drawers' panes (PaneStack), the Settings tabs
## and the room's lists use it. It is the library grid's bar behaviour (LevelGrid._show_bar)
## made reusable; the grid's own copy is to be swapped for it.
##
## The bar rests clear (modulate alpha 0). It fades in while the pointer is over the list
## (the container or anything in it) and for LINGER_S after a wheel, pad or drag scroll with
## the pointer elsewhere, then out, at the soft hover speeds (M1). Hidden, it still takes a
## click or a drag where it stands, so a pointer always finds it. The theme's lane is already
## clear, so the handle is all that ever shows.

## How long the bar stays after a scroll with the pointer elsewhere.
const LINGER_S := 0.8

var _scroll: ScrollContainer
var _tween: Tween = null
## Where the running fade is heading (true: in).
var _target_on := false
var _pointer_over := false
var _linger: Timer


## Add a ScrollBarFade to `scroll` and return it.
static func attach(scroll: ScrollContainer) -> ScrollBarFade:
	var fade := ScrollBarFade.new()
	fade.name = "ScrollBarFade"
	scroll.add_child(fade)
	return fade


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer
	if _scroll == null:
		push_warning("ScrollBarFade: the parent is not a ScrollContainer")
		return
	var bar := _scroll.get_v_scroll_bar()
	bar.modulate.a = 0.0
	bar.value_changed.connect(_on_scrolled)
	_scroll.mouse_entered.connect(_on_pointer.bind(true))
	_scroll.mouse_exited.connect(_on_pointer.bind(false))
	_linger = Timer.new()
	_linger.name = "BarLinger"
	_linger.one_shot = true
	_linger.wait_time = LINGER_S
	_linger.timeout.connect(show_bar.bind(false))
	add_child(_linger)


## Whether the bar is shown or on its way in (its fade target).
func is_shown() -> bool:
	if _tween != null and _tween.is_valid() and _tween.is_running():
		return _target_on
	return _scroll != null and _scroll.get_v_scroll_bar().modulate.a > 0.5


## Fade the bar in (`on`) or out. Out waits while the pointer is over the list.
func show_bar(on: bool) -> void:
	if not on and _pointer_over:
		return
	if _scroll == null or not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_target_on = on
	var duration := Constants.ANIM_HOVER_SOFT_IN if on else Constants.ANIM_HOVER_SOFT_OUT
	_tween = create_tween()
	_tween.tween_property(_scroll.get_v_scroll_bar(), "modulate:a", 1.0 if on else 0.0, duration)


func _on_scrolled(_value: float) -> void:
	show_bar(true)
	if not _pointer_over:
		_linger.start()


func _on_pointer(inside: bool) -> void:
	_pointer_over = inside
	if inside:
		show_bar(true)
	else:
		_linger.start()
