class_name ProvingGround
extends RefCounted

## The map the biome designer judges a biome on (design doc 4.2, step S8a): a fixed 150 ft map
## built from the authoring document API, so the real scatter solver, the real ground look and
## the native extension run on it exactly as on an author's map. Every feature a rule's fields
## answer to has a place on it, painted at full density with one fixed seed:
##
## - a SLOPE DOME in the north-west corner whose slope grows from 0 degrees at the summit to 60
##   at its foot (height = ln(cos(60 degrees * r / R)) / k, so each ring is one slope: the slope
##   response and slope_min_deg show as rings, rocks gather at the steep foot);
## - a RIDGE in the north-east running north to south, up to about 45 degrees on its flanks and
##   3.4 m above the plain (the height curve, a tree line);
## - a PATH BAND across the middle, a built surface two and a half metres wide (the fringe
##   behaviour of plants at a path);
## - a WATER CHANNEL along the south with its banks (the bank and emergent habits, the wet
##   curve);
## - a flat MEADOW between the path and the water, split into three painted DENSITY ZONES (full,
##   half and a fifth) from west to east.
##
## build() returns the MapDocument; layout() names every region in world metres for the designer's
## overlays and camera. Pure document work like NewMap.create (a worker thread may build it).
## Map and model: docs/systems/biome_designer.md.

const SIZE_FT := 150
const SEED := 1234
const FALLBACK_SURFACE := "grass"
const FALLBACK_PATH := "dirt_road_packed"
## The slope at the foot of the dome, in degrees.
const DOME_FOOT_DEG := 60.0
const RIDGE_HEIGHT_M := 3.4
const PATH_WIDTH_M := 2.4
const PATH_SOFT_M := 0.6
const RIVER_HALF_WIDTH_M := 1.4
const DENSITY_ZONES: Array[int] = [255, 128, 51]
## Region sizes and places as shares of the map's half extent.
const DOME_CENTRE := Vector2(-0.5, -0.5)
const DOME_RADIUS := 0.4
const RIDGE_X := 0.58
const RIDGE_Z := Vector2(-0.92, -0.1)
const RIDGE_HALF_WIDTH := 0.2
const PATH_Z := 0.07
const PATH_WOBBLE_M := 0.8
const RIVER_Z := 0.64
const MEADOW_Z := Vector2(0.2, 0.48)
const MEADOW_X := Vector2(-0.95, -0.02)


## The proving ground for the palette biome `biome_id` (its ground and path surfaces, painted
## everywhere). options: "size_ft" (150), "seed" (1234), "root" (the palette root).
static func build(biome_id: String, options: Dictionary = {}) -> MapDocument:
	var root := String(options.get("root", PaletteLibrary.DEFAULT_ROOT))
	var size_ft := int(options.get("size_ft", SIZE_FT))
	var seed_value := int(options.get("seed", SEED))
	var biome := PaletteLibrary.biome(biome_id, root)
	var surface := String(biome.get("ground_surface", ""))
	var doc := MapDocument.create_flat(
		NewMap.size_cells(size_ft),
		surface if surface != "" else FALLBACK_SURFACE,
		PaletteLibrary.palette_version(root),
		seed_value
	)
	if doc == null:
		return null
	var regions := layout(doc)
	_shape(doc, regions)
	_water(doc, regions)
	_paint_biome(doc, biome_id, regions)
	var paths: Array = biome.get("path_surfaces", [])
	var path_surface := String(paths[0]) if not paths.is_empty() else FALLBACK_PATH
	StartingLandform.paint_line(
		doc, path_surface, regions["path"]["line"], PATH_WIDTH_M, PATH_SOFT_M
	)
	return doc


## The named regions of the proving ground of `doc`, in map XZ metres: {"dome": {centre,
## radius}, "ridge": {line, half_width, height}, "path": {line, width}, "river": {line,
## half_width}, "meadow": {rect}, "zones": [{rect, density}], "points": {name: Vector2} (places to
## aim the camera at)}.
static func layout(doc: MapDocument) -> Dictionary:
	var half := doc.extent_m() * 0.5
	var scale := minf(half.x, half.y)
	var path := PackedVector2Array()
	var x := -half.x
	while x <= half.x + 0.01:
		path.append(Vector2(x, PATH_Z * scale + PATH_WOBBLE_M * sin(x / 6.0)))
		x += 1.0
	var river_line := PackedVector2Array(
		[
			Vector2(-0.88 * half.x, (RIVER_Z + 0.03) * scale),
			Vector2(-0.2 * half.x, (RIVER_Z - 0.04) * scale),
			Vector2(0.4 * half.x, (RIVER_Z + 0.04) * scale),
			Vector2(0.9 * half.x, (RIVER_Z - 0.02) * scale),
		]
	)
	var meadow := Rect2(
		Vector2(MEADOW_X.x * half.x, MEADOW_Z.x * scale),
		Vector2((MEADOW_X.y - MEADOW_X.x) * half.x, (MEADOW_Z.y - MEADOW_Z.x) * scale)
	)
	var zones: Array[Dictionary] = []
	var third := meadow.size.x / 3.0
	for i in DENSITY_ZONES.size():
		var from := meadow.position + Vector2(third * i, 0.0)
		var area := Rect2(from, Vector2(third, meadow.size.y))
		zones.append({"rect": area, "density": DENSITY_ZONES[i]})
	var dome_centre := DOME_CENTRE * scale
	var ridge_z := RIDGE_Z * scale
	var ridge_top := Vector2(RIDGE_X * scale, ridge_z.x)
	var ridge_bottom := Vector2(RIDGE_X * scale, ridge_z.y)
	return {
		"dome": {"centre": dome_centre, "radius": DOME_RADIUS * scale},
		"ridge":
		{
			"line": PackedVector2Array([ridge_top, ridge_bottom]),
			"half_width": RIDGE_HALF_WIDTH * scale,
			"height": RIDGE_HEIGHT_M,
		},
		"path": {"line": path, "width": PATH_WIDTH_M},
		"river": {"line": river_line, "half_width": RIVER_HALF_WIDTH_M},
		"meadow": {"rect": meadow},
		"zones": zones,
		"points":
		{
			"dome": dome_centre,
			"dome_foot": dome_centre + Vector2(DOME_RADIUS * scale * 0.8, 0.0),
			"ridge": Vector2(RIDGE_X * scale, (ridge_z.x + ridge_z.y) * 0.5),
			"path": Vector2(0.0, PATH_Z * scale),
			"river": river_line[1],
			"meadow": meadow.get_center(),
			"centre": Vector2.ZERO,
		},
	}


## The slope in degrees the dome has at distance `r` from its centre (0 at the summit, 60 at the
## foot), for tests and the slope legend.
static func dome_slope_deg(r: float, radius: float) -> float:
	return DOME_FOOT_DEG * clampf(r / radius, 0.0, 1.0) if r < radius else 0.0


static func _shape(doc: MapDocument, regions: Dictionary) -> void:
	var dome: Dictionary = regions["dome"]
	var ridge: Dictionary = regions["ridge"]
	var line: PackedVector2Array = ridge["line"]
	var k := deg_to_rad(DOME_FOOT_DEG) / float(dome["radius"])
	var half_width: float = ridge["half_width"]
	var length := line[0].distance_to(line[1])
	StartingLandform.write_heights(
		doc,
		func(p: Vector2, h: float) -> float:
			var r := p.distance_to(dome["centre"])
			var lift := 0.0
			if r < float(dome["radius"]):
				lift += (log(cos(k * float(dome["radius"]))) * -1.0 + log(cos(k * r))) / k
			# The ridge: cos squared across, a smoothstep along so its ends run out.
			var across := absf(p.x - line[0].x)
			var along := (p.y - line[0].y) / length
			if across < half_width and along > -0.1 and along < 1.1:
				var section := pow(cos(PI * 0.5 * across / half_width), 2.0)
				var ends := smoothstep(-0.1, 0.15, along) * (1.0 - smoothstep(0.85, 1.1, along))
				lift += float(ridge["height"]) * section * ends
			return h + lift
	)


static func _water(doc: MapDocument, regions: Dictionary) -> void:
	var river: Dictionary = regions["river"]
	var course := StartingLandform.map_line(doc, river["line"], 1.0, 1.0)
	if course.size() >= 2:
		StartingLandform.carve_river(doc, course, float(river["half_width"]), WaterBody.Depth.WAIST)
	if not doc.water_bodies.is_empty():
		doc.water_dressing = WaterDressing.refresh(doc)


static func _paint_biome(doc: MapDocument, biome_id: String, regions: Dictionary) -> void:
	var count := doc.sample_count()
	var slots := PackedByteArray()
	slots.resize(count)
	slots.fill(1)
	var density := PackedByteArray()
	density.resize(count)
	density.fill(255)
	for zone: Dictionary in regions["zones"]:
		var rect: Rect2 = zone["rect"]
		for z in doc.samples_z():
			for x in doc.samples_x():
				if rect.has_point(doc.sample_to_world(Vector2(x, z))):
					density[doc.sample_index(x, z)] = int(zone["density"])
	doc.biome_ids = PackedStringArray([biome_id])
	doc.biome_slots = slots
	doc.biome_density = density
