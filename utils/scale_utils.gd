extends RefCounted
class_name ScaleUtils

## Static utility class for converting between world-space distances and game-unit
## distances.  TTSim follows the glTF standard: 1 Godot world unit = 1 meter.
## The conversion to game units (feet, inches, squares, etc.) is controlled by
## three per-level values stored in LevelData:
##   grid_cell_size      – meters per grid square (default 1.524 = 5 ft)
##   display_unit_per_cell – game-units per grid square (e.g. 5.0 for 5 ft)
##   display_unit        – label string (e.g. "ft")

## ── Presets ──────────────────────────────────────────────────────────────────

const PRESETS := {
	"dnd_5ft":
	{
		"label": "D&D / Pathfinder (5 ft squares)",
		"grid_cell_size": 1.524,
		"display_unit": "ft",
		"display_unit_per_cell": 5.0,
	},
	"dnd_metric":
	{
		"label": "D&D / Pathfinder (1.5 m squares)",
		"grid_cell_size": 1.524,
		"display_unit": "m",
		"display_unit_per_cell": 1.524,
	},
	"metric_1m":
	{
		"label": "Metric (1 m squares)",
		"grid_cell_size": 1.0,
		"display_unit": "m",
		"display_unit_per_cell": 1.0,
	},
	"generic_squares":
	{
		"label": "Generic (1 m = 1 square)",
		"grid_cell_size": 1.0,
		"display_unit": "sq",
		"display_unit_per_cell": 1.0,
	},
}

## Default preset key applied to new levels.
const DEFAULT_PRESET := "dnd_5ft"

## ── Conversion helpers ───────────────────────────────────────────────────────


## Convert a world-space distance (meters) to display units.
static func world_to_display(
	distance_world: float, grid_cell_size: float, display_unit_per_cell: float
) -> float:
	if grid_cell_size <= 0.0:
		return distance_world
	return (distance_world / grid_cell_size) * display_unit_per_cell


## Format a single distance value: "30 ft"
static func format_distance(
	distance_world: float,
	grid_cell_size: float,
	display_unit_per_cell: float,
	unit_label: String,
) -> String:
	var val := world_to_display(distance_world, grid_cell_size, display_unit_per_cell)
	return "%d %s" % [roundi(val), unit_label]


## Format distance with optional elevation info.
## When the elevation delta exceeds the threshold the result includes
## the horizontal distance, signed elevation change, and the direct (3-D)
## distance.  Example:  "30 ft  |  +15 ft elev  |  33 ft direct"
static func format_distance_with_elevation(
	horizontal_distance: float,
	elevation_delta: float,
	direct_distance: float,
	grid_cell_size: float,
	display_unit_per_cell: float,
	unit_label: String,
	elevation_threshold: float = 0.15,
) -> String:
	var h := format_distance(horizontal_distance, grid_cell_size, display_unit_per_cell, unit_label)
	if absf(elevation_delta) < elevation_threshold:
		return h
	var elev_val := world_to_display(absf(elevation_delta), grid_cell_size, display_unit_per_cell)
	var sign_str := "+" if elevation_delta >= 0.0 else "-"
	var d := format_distance(direct_distance, grid_cell_size, display_unit_per_cell, unit_label)
	return "%s  |  %s%d %s elev  |  %s direct" % [h, sign_str, roundi(elev_val), unit_label, d]


## ── Grid snap helpers ────────────────────────────────────────────────────


## Snap a world position to the nearest grid cell center on the XZ plane.
## Cell centers are at half-cell offsets from the grid lines (e.g. for a 1m grid
## with origin 0, centers are at 0.5, 1.5, 2.5 …).
## Y is preserved (terrain height conformance). The [param origin] parameter
## aligns snapping with the grid overlay's origin offset.
static func snap_to_grid(
	world_pos: Vector3, cell_size: float, origin: Vector2 = Vector2.ZERO
) -> Vector3:
	if cell_size <= 0.0:
		return world_pos
	var half := cell_size * 0.5
	return Vector3(
		roundf((world_pos.x - origin.x - half) / cell_size) * cell_size + origin.x + half,
		world_pos.y,
		roundf((world_pos.z - origin.y - half) / cell_size) * cell_size + origin.y + half,
	)


## ── Preset helpers ───────────────────────────────────────────────────────────


## Apply a named preset to a LevelData resource.
## Returns true if the preset key was found, false otherwise.
static func apply_preset(level_data: LevelData, preset_key: String) -> bool:
	if not PRESETS.has(preset_key):
		return false
	var p: Dictionary = PRESETS[preset_key]
	level_data.grid_cell_size = p.grid_cell_size
	level_data.display_unit = p.display_unit
	level_data.display_unit_per_cell = p.display_unit_per_cell
	return true


## Return an array of {"key": String, "label": String} suitable for populating
## a preset dropdown, plus a trailing "Custom" entry.
static func get_preset_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for key in PRESETS:
		options.append({"key": key, "label": PRESETS[key].label})
	options.append({"key": "custom", "label": "Custom"})
	return options
