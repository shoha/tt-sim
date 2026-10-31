class_name WindCompass
extends RefCounted

## The Weather pane's wind direction words and picker table (docs/systems/wind.md "Phase (d) and (e)
## as built"). Pure: no scene tree. WeatherSettings.wind_direction_deg is the way the wind blows
## TOWARD, degrees on the map plane (0 = +x, 90 = +z, below 0 = the default direction); players
## say where it comes FROM, so every name here is the source. North is -z (up the default view),
## east is +x, so wind from the north blows toward +z (90 degrees).

## The picker's id for "the default direction" (wind_direction_deg = -1).
const AUTO_ID := &"auto"
## How far (degrees) a stored direction may sit from a compass point and still count as that point.
const POINT_TOLERANCE_DEG := 1.0
## Beyond this many degrees from the nearest point the readout says "roughly".
const ROUGH_DEG := 7.0

## The eight points as [id, short label, source name, degrees the wind blows toward].
const POINTS: Array = [
	[&"n", "N", "north", 90.0],
	[&"ne", "NE", "north-east", 135.0],
	[&"e", "E", "east", 180.0],
	[&"se", "SE", "south-east", 225.0],
	[&"s", "S", "south", 270.0],
	[&"sw", "SW", "south-west", 315.0],
	[&"w", "W", "west", 0.0],
	[&"nw", "NW", "north-west", 45.0],
]

## The picker's order, three to a line so it reads as a compass: NW N NE / W Auto E / SW S SE.
const GRID: Array[StringName] = [&"nw", &"n", &"ne", &"w", &"auto", &"e", &"sw", &"s", &"se"]


## The row of point [param id] (an entry of POINTS), or an empty array for auto and unknown ids.
static func point(id: StringName) -> Array:
	for entry: Array in POINTS:
		if entry[0] == id:
			return entry
	return []


## The wind_direction_deg that picking [param id] writes: the point's heading, or the default
## sentinel (-1) for auto and unknown ids.
static func direction_for(id: StringName) -> float:
	var entry := point(id)
	return float(entry[3]) if not entry.is_empty() else WeatherSettings.WIND_DIRECTION_AUTO


## The picker id a stored [param deg] shows: auto below 0, a point within POINT_TOLERANCE_DEG,
## else an empty name (a hand-edited or imported direction no tile stands for).
static func id_for(deg: float) -> StringName:
	if deg < 0.0:
		return AUTO_ID
	for entry: Array in POINTS:
		if (
			absf(angle_difference(deg_to_rad(deg), deg_to_rad(float(entry[3]))))
			< deg_to_rad(POINT_TOLERANCE_DEG)
		):
			return entry[0]
	return &""


## The point nearest [param deg] (a direction of 0 or more; the default direction counts as its
## own heading), as its POINTS row.
static func nearest(deg: float) -> Array:
	var heading := WindPresets.default_direction_deg() if deg < 0.0 else deg
	var best: Array = POINTS[0]
	var best_gap := INF
	for entry: Array in POINTS:
		var gap := absf(angle_difference(deg_to_rad(heading), deg_to_rad(float(entry[3]))))
		if gap < best_gap:
			best_gap = gap
			best = entry
	return best


## The sentence under the picker: "Wind from the north-west", "Wind from the south-west
## (automatic)" for the default direction, "Wind from roughly the west" for a direction that sits
## between points.
static func readout(deg: float) -> String:
	var entry := nearest(deg)
	if deg < 0.0:
		return "Wind from the %s (automatic)" % entry[2]
	var heading := deg_to_rad(deg)
	var off := rad_to_deg(absf(angle_difference(heading, deg_to_rad(float(entry[3])))))
	if off > ROUGH_DEG:
		return "Wind from roughly the %s" % entry[2]
	return "Wind from the %s" % entry[2]


## The tooltip of picker tile [param id]: what picking it does, in plain words.
static func tooltip_for(id: StringName) -> String:
	if id == AUTO_ID:
		return "Let the level choose: the wind blows from the %s." % nearest(-1.0)[2]
	var entry := point(id)
	if entry.is_empty():
		return ""
	return "The wind blows in from the %s." % entry[2]
