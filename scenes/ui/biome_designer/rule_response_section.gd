class_name DesignerResponseSection
extends Foldout

## The Terrain response section of the rule inspector (design doc 2.6, step S12 in the editor):
## the rule's density as a function of the slope of the ground, its height, the shore wetness
## and (S12c) the distance to water, each a curve of 2 to 8 points drawn and dragged in a
## CurveEditor, with the preset shapes (flat, ramp up, ramp down, bell, band) one click away. A
## curve only ever lowers the density (the rule's density is the density at curve value 1); no
## curve is the same as flat.

const HOW_TO := (
	"Density only goes down from the Placement density. Drag points; double-click to add one; "
	+ "right-click a point to remove it."
)
const AXIS_TIPS := {
	"slope": "Density by the slope of the ground under the plant, 0 to 90 degrees.",
	"height":
	(
		"Density by the ground's height in metres (the proving ground runs from the water bed "
		+ "up to the ridge)."
	),
	"wet":
	(
		"Density by shore wetness: 0 away from water, 1 at the waterline. Only within 2.4 m "
		+ "of water."
	),
	"water_dist":
	(
		"Density by the distance to the nearest water in metres: 0 on the water, 64 or more far "
		+ "from it (or on a map with no water)."
	),
}
const PRESET_OPTIONS: Array = [
	["none", "No curve"],
	["flat", "Flat"],
	["ramp_up", "Ramp up"],
	["ramp_down", "Ramp down"],
	["bell", "Bell"],
	["band", "Band"],
	["custom", "Custom"],
]

var session: BiomeDesignerSession = null

var _key: String = ""
var _editors: Dictionary = {}
var _presets: Dictionary = {}
var _syncing: bool = false


func _init() -> void:
	name = "Response"
	title = "Terrain response"
	button_room = true
	expanded = true


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	add_child(DesignerRows.caption("ResponseCaption", HOW_TO))
	for axis in ResponseCurve.axes():
		var heading := Label.new()
		heading.text = String(ResponseCurve.AXIS_LABELS[axis])
		heading.tooltip_text = String(AXIS_TIPS[axis])
		add_child(heading)
		var preset := DesignerRows.option(
			self, "Preset_" + axis, "Shape", PRESET_OPTIONS, String(AXIS_TIPS[axis])
		)
		preset.item_selected.connect(_on_preset.bind(axis))
		_presets[axis] = preset
		var editor := CurveEditor.new()
		editor.name = "Curve_" + axis
		editor.tooltip_text = String(AXIS_TIPS[axis])
		editor.curve_changed.connect(_on_curve.bind(axis))
		add_child(editor)
		_editors[axis] = editor
	session.model.changed.connect(func(_reason: String) -> void: _sync())


func show_rule(key: String) -> void:
	_key = key
	_sync()


## The CurveEditor of `axis`, for tests and probes.
func editor_of(axis: String) -> CurveEditor:
	return _editors.get(axis)


func _sync() -> void:
	if _key == "" or session == null or not session.model.has_rule(_key):
		return
	_syncing = true
	for axis: String in _editors:
		var editor: CurveEditor = _editors[axis]
		var points := DesignerResponseEdits.curve(session.model, _key, axis)
		if not editor.is_dragging():
			editor.set_curve(axis, points)
		var shape := "none" if points.is_empty() else ResponseCurve.preset_of(axis, points)
		DesignerRows.select(_presets[axis], shape if shape != "" else "custom")
	_syncing = false


func _on_curve(points: Array, final: bool, axis: String) -> void:
	if _syncing or _key == "":
		return
	DesignerResponseEdits.set_curve(session.model, _key, axis, points, not final)


func _on_preset(index: int, axis: String) -> void:
	if _syncing or _key == "":
		return
	var shape := String((_presets[axis] as OptionButton).get_item_metadata(index))
	if shape == "custom":
		return
	DesignerResponseEdits.set_preset(session.model, _key, axis, shape)
