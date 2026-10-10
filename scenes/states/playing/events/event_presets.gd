class_name EventPresets
extends RefCounted

## The Events pane's presets with spectacle: one-shot terrain events the GM sets off with one
## gesture (a bridge dropping into the water, a stand of trees toppling, a forest set alight),
## each a ToolDescriptor whose BrushMode (CollapseMode, ToppleMode, IgniteMode) fires a
## TerrainEvent instead of editing the map
## stroke by stroke. They are play's alone and not map tools, so they stay out of ToolRegistry
## (authoring's rail and help never list them); PlayEvents arms them on GameMap's brush as it
## arms a brush, and EventsPane shows them in their own field (HEADING) above Brushes.
##
## Their labels are what they do, as the cursor pills say it ("Drop bridge", "Topple trees",
## "Start a fire"), so they read as events beside the Brushes' nouns, and their icons show the
## happening (a span broken over the water, a tree leaning as it falls, a flame) so they never
## repeat a brush's picture.

const COLLAPSE := &"collapse"
const TOPPLE := &"topple"
const IGNITE := &"ignite"
## The pane's heading over the presets: one-shot happenings on the table, beside the Brushes
## that build the map ("Events" is the pane's own title).
const HEADING := "Happenings"
const DROP_LABEL := CollapseMode.DROP
const TOPPLE_LABEL := ToppleMode.TEXT
const IGNITE_LABEL := IgniteMode.IGNITE_TEXT
## The Drop bridge tile's tooltip while the map has no bridge to drop.
const NO_BRIDGE_TOOLTIP := "No bridge stands on this map. Lay one with the Bridge brush first."

static var _presets: Array[ToolDescriptor] = []


## Every preset, in tile order.
static func all() -> Array[ToolDescriptor]:
	if _presets.is_empty():
		var drop := _make(
			COLLAPSE,
			DROP_LABEL,
			"bridge-broken",
			"A bridge breaks and falls into the water for everyone. Click a bridge.",
			CollapseMode
		)
		drop.unavailable_tooltip = NO_BRIDGE_TOOLTIP
		_presets = [
			drop,
			_make(
				TOPPLE,
				TOPPLE_LABEL,
				"tree-falling",
				"Trees fall away from where you click, for everyone. Drag out for a wider stand.",
				ToppleMode
			),
			_make(
				IGNITE,
				IGNITE_LABEL,
				"flame",
				(
					"Fire spreads through the forest from where you click and leaves ash and"
					+ " charred snags, for everyone. Drag out for a wider fire."
				),
				IgniteMode
			),
		]
	return _presets


## The preset with id `id`, or null.
static func find(id: StringName) -> ToolDescriptor:
	for preset in all():
		if preset.id == id:
			return preset
	return null


## The preset that sets off events of TerrainEvent kind `kind`, or null: its label names the
## event's history entry and its icon the event's toasts, so the tile, the undo and the chips
## say and show one thing (UI_TASTE W5).
static func for_kind(kind: int) -> ToolDescriptor:
	match kind:
		TerrainEvent.Kind.BRIDGE_COLLAPSE:
			return find(COLLAPSE)
		TerrainEvent.Kind.FOREST_FALL:
			return find(TOPPLE)
		TerrainEvent.Kind.FIRE:
			return find(IGNITE)
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
