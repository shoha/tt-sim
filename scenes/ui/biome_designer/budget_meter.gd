class_name DesignerBudgetMeter
extends HBoxContainer

## The designer's budget meter (design doc 4.4): "1.9M / 8M tris | 142 draw | 4.1 ms". The
## triangles are the proving ground's instances times the catalog's LOD0 triangles, scaled to a
## 200 ft map (four 100 ft tiles) against the player's foliage primitive budget; the bar turns
## amber at 60 percent of it and red at the budget (DesignerBudget). The draw calls and the render
## time are the world viewport's own, read from the renderer once a second. Over budget is also
## said in words, never by colour alone.

const REFRESH_SECONDS := 0.5

var session: BiomeDesignerSession = null
## The renderer's reading, set by the host so the meter needs no scene tree access of its own:
## a Callable returning {draw_calls, primitives, cpu_ms, gpu_ms}.
var live_source: Callable = Callable()

var _bar: Control
var _label: Label
var _clock: float = 0.0
var _estimate: Dictionary = {}
var _live: Dictionary = {}


func _init() -> void:
	name = "BudgetMeter"
	_bar = Control.new()
	_bar.name = "Bar"
	_bar.custom_minimum_size = Vector2(120.0, 14.0)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_label = Label.new()
	_label.name = "Words"
	_label.theme_type_variation = &"Caption"
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size = Vector2(1.0, 0.0)
	add_child(_label)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	session.regenerated.connect(func(_stats: Dictionary) -> void: refresh())
	refresh()


## Recomputes the estimate from the scatter now.
func refresh() -> void:
	if session == null:
		return
	_estimate = session.budget()
	_read_live()
	_show()


func estimate() -> Dictionary:
	return _estimate


func words() -> String:
	return _label.text


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		refresh()


func _read_live() -> void:
	if live_source.is_valid():
		_live = live_source.call()


func _show() -> void:
	if _estimate.is_empty():
		_label.text = "Budget: nothing placed yet"
		return
	var map: Dictionary = _estimate["map"]
	var budget := float(_budget())
	var parts: Array[String] = [
		(
			"%s / %s tris (200 ft map)"
			% [DesignerBudget.short(float(map["triangles"])), DesignerBudget.short(budget)]
		),
		"%s per 100 ft tile" % DesignerBudget.short(float(_estimate["per_tile"]["triangles"])),
		"%d draw est." % int(_estimate["draw_calls"]),
	]
	if not _live.is_empty():
		parts.append(
			(
				"%d draw, %.1f ms render"
				% [int(_live.get("draw_calls", 0)), float(_live.get("cpu_ms", 0.0))]
			)
		)
	var level := String(map["level"])
	if level == "red":
		parts.append("OVER BUDGET")
	elif level == "amber":
		parts.append("near the budget")
	_label.text = " | ".join(PackedStringArray(parts))
	_bar.queue_redraw()


func _budget() -> int:
	return FoliageDensityController.budget_from_settings()


func _draw_bar() -> void:
	var rect := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(rect, ThemeColors.of(_bar, ThemeColors.SURFACE_INSET))
	if _estimate.is_empty():
		return
	var share := clampf(float(_estimate["map"]["share"]), 0.0, 1.0)
	var role := {"ok": ThemeColors.SUCCESS, "amber": ThemeColors.WARNING, "red": ThemeColors.DANGER}
	var fill := Rect2(rect.position, Vector2(rect.size.x * share, rect.size.y))
	_bar.draw_rect(fill, ThemeColors.of(_bar, role[String(_estimate["map"]["level"])]))
	_bar.draw_rect(rect, ThemeColors.of(_bar, ThemeColors.EDGE), false, 1.0)
