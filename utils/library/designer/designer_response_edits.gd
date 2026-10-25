class_name DesignerResponseEdits
extends RefCounted

## The terrain-response edits of the biome designer (step S12 in the editor): a rule's
## `response` curves (slope, height, wet) and its `slope_min_deg`, as commands on a
## BiomeDesignerModel. Static functions over the model so the model keeps one class's worth of
## public methods and no reference cycle; the curve rules themselves are ResponseCurve's.


## Rule `key`'s curve on `axis` (a copy; [] when it has none).
static func curve(model: BiomeDesignerModel, key: String, axis: String) -> Array:
	var response: Dictionary = model.value(key, "response", {})
	return (response.get(axis, []) as Array).duplicate(true)


## Sets (points) or removes (null) the curve on `axis`; an emptied `response` goes away.
## `merge`: a point being dragged, so the drag is one undo step.
static func set_curve(
	model: BiomeDesignerModel, key: String, axis: String, points: Variant, merge: bool = false
) -> bool:
	var at := model.rule_index(key)
	if at < 0 or not LibraryContracts.RESPONSE_AXES.has(axis):
		return false
	var response: Dictionary = (model.value(key, "response", {}) as Dictionary).duplicate(true)
	if points == null:
		if not response.has(axis):
			return false
		response.erase(axis)
	else:
		if response.get(axis) == points:
			return false
		response[axis] = points
	var op := (
		DesignerPatch.erase_op(["rules", at, "response"])
		if response.is_empty()
		else DesignerPatch.set_op(["rules", at, "response"], response)
	)
	var tag := "curve:%s:%s" % [key, axis] if merge else ""
	return model.apply_edit("Edit %s curve" % axis, [op], tag)


static func add_point(
	model: BiomeDesignerModel, key: String, axis: String, x: float, y: float = -1.0
) -> bool:
	var points := curve(model, key, axis)
	if points.is_empty():
		points = ResponseCurve.flat(axis)
	return set_curve(model, key, axis, ResponseCurve.add_point(axis, points, x, y))


static func remove_point(model: BiomeDesignerModel, key: String, axis: String, index: int) -> bool:
	return set_curve(model, key, axis, ResponseCurve.remove_point(curve(model, key, axis), index))


static func move_point(
	model: BiomeDesignerModel,
	key: String,
	axis: String,
	index: int,
	x: float,
	y: float,
	merge: bool = true
) -> bool:
	var points := curve(model, key, axis)
	if points.is_empty():
		return false
	var moved := ResponseCurve.move_point(axis, points, index, x, y)
	return set_curve(model, key, axis, moved, merge)


## A preset shape (ResponseCurve.PRESETS); "none" removes the curve.
static func set_preset(model: BiomeDesignerModel, key: String, axis: String, shape: String) -> bool:
	var points: Variant = null if shape == "none" else ResponseCurve.preset(axis, shape)
	return set_curve(model, key, axis, points)


## The band edge in degrees: 0 or null clears it.
static func set_slope_min(
	model: BiomeDesignerModel, key: String, degrees: Variant, merge: bool = false
) -> bool:
	if degrees == null or float(degrees) <= 0.0:
		return model.set_field(key, "slope_min_deg", null)
	return model.set_field(key, "slope_min_deg", float(degrees), merge)
