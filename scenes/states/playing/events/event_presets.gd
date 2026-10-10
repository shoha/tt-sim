class_name EventPresets
extends RefCounted

## The Events pane's presets with spectacle: terrain events the GM sets off with one gesture
## (a bridge collapsing, a stand of trees toppling), each a ToolDescriptor whose BrushMode
## (CollapseMode, ToppleMode) fires a TerrainEvent instead of editing the map stroke by stroke.
## They are play's alone and not map tools, so they stay out of ToolRegistry (authoring's rail
## and help never list them); PlayEvents arms them on GameMap's brush as it arms a brush, and
## EventsPane shows them in their own field above Brushes.

const COLLAPSE := &"collapse"
const TOPPLE := &"topple"

static var _presets: Array[ToolDescriptor] = []


## Every preset, in tile order.
static func all() -> Array[ToolDescriptor]:
	if _presets.is_empty():
		_presets = [
			_make(
				COLLAPSE,
				"Collapse",
				"bridge-plank",
				"A bridge breaks and falls into the water. Click a bridge.",
				CollapseMode
			),
			_make(
				TOPPLE,
				"Topple",
				"tree",
				"Trees fall away from where you click. Drag out for a wider stand.",
				ToppleMode
			),
		]
	return _presets


## The preset with id `id`, or null.
static func find(id: StringName) -> ToolDescriptor:
	for preset in all():
		if preset.id == id:
			return preset
	return null


static func _make(
	id: StringName, label: String, icon: String, summary: String, mode: GDScript
) -> ToolDescriptor:
	var preset := ToolDescriptor.new()
	preset.id = id
	preset.label = label
	preset.icon = icon
	preset.summary = summary
	preset.contexts = ToolDescriptor.PLAY
	preset.brush_mode = mode
	return preset
