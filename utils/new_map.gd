class_name NewMap
extends RefCounted

## The documents authoring mode starts from: a new map of a chosen size and starting
## biome, and the empty dressing layer over a Blender-made map.glb. Pure (no nodes, no
## files); the palette is read, never written.
##
## Starting cover. A starting biome does two things. It sets the base ground surface (the
## biome's ground_surface, so a forest starts on forest floor, not grey), and it paints the
## biome's masks with a gentle, uneven cover so the map opens already looking like a place:
## denser groves toward the edges, an open glade in the middle where a battle happens, and
## noise-shaped copses and clearings between, never a uniform carpet. The painted density is
## what the generator scales every species by, so the cover is sparse where it is low and a
## brush stroke over it adds to a living map instead of an empty one. Everything is derived
## from the map seed, so the same seed gives the same map.

## Map size choices in feet; one grid cell is 5 ft, so these are 20, 30 and 40 cells, even
## counts that keep grid lines on the origin.
const SIZES_FT: Array[int] = [100, 150, 200]
const DEFAULT_SIZE_FT := 100
const FEET_PER_CELL := 5.0
## A custom map is width x depth in whole 5 ft squares. Up to RECOMMENDED_MAX_FT a side the
## builder's whole-map view stays near the 200 ft one's cost; past it the New map screen
## says the map is big (it plays the same at the table, but opens, saves and shows whole
## more slowly while built); MAX_FT is the document format's limit (MapDocument
## MAX_SIZE_CELLS squares), where the field stops. Size probe, 2026-10-09.
const RECOMMENDED_MAX_FT := 250
const MAX_FT := MapDocument.MAX_SIZE_CELLS * 5
const MIN_FT := MapDocument.MIN_SIZE_CELLS * 5
## Base surface of a map started from bare ground (no starting biome).
const BARE_SURFACE := "grass"
## The id NewMapDialog uses for its "Bare ground" tile.
const BARE_BIOME := ""
## Name of a map created in authoring until the author names it.
const DEFAULT_NAME := "Untitled map"

## Starting cover: painted density at the centre and at the edge (0..1), how far noise may
## move it either way, the noise feature size in metres (about the size of a copse at the
## game camera), and the density below which a sample is left unpainted (a real clearing).
const COVER_CENTRE_DENSITY := 0.14
const COVER_EDGE_DENSITY := 0.6
const COVER_NOISE_AMPLITUDE := 0.32
const COVER_FEATURE_M := 12.0
const COVER_MIN_DENSITY := 0.05
## Where the edge groves begin and reach full density, as a fraction of the way from the
## centre to the edge (a rounded-square distance, so corners are not favoured).
const COVER_GLADE_RADIUS := 0.35
const COVER_EDGE_RADIUS := 0.95
## A line glade's near bank (glade_density) counts whole once its direction from the line has
## this dot with the camera's direction (cos 45 degrees, less a margin).
const GLADE_NEAR_FULL_DOT := 0.65
## A big or long map's cover (LandformGrowth): the noise's feature size grows by this share
## at full room; a clearing (clearing_density) is open within CLEARING_INNER of its radius, at
## most CLEARING_OPEN_SHARE of the glade's density there, its outline warped by CLEARING_WARP.
const COVER_FEATURE_GROWTH := 0.5
const CLEARING_INNER := 0.55
const CLEARING_OPEN_SHARE := 0.5
const CLEARING_WARP := 0.25
## The cover's feather at the map edge (2026-10-09; play shows the whole map, and a
## grassland's tall grass stopped dead along it in a straight line): the cover thins to none
## over EDGE_FEATHER_SHARE of the shorter half extent inside the edge (within
## EDGE_FEATHER_MIN_M..EDGE_FEATHER_MAX_M), the band's depth pushed in and out by
## EDGE_FEATHER_WOBBLE by the cover noise read at twice its feature size (EDGE_WOBBLE_OFFSET
## away), so the scatter ends in a ragged fringe that runs out onto the skirt's bare ground.
## Trees answer the density late (ScatterPlan.DENSITY_RESPONSE), so the groves keep their
## edge and the ground cover thins first.
const EDGE_FEATHER_SHARE := 0.1
const EDGE_FEATHER_MIN_M := 2.0
const EDGE_FEATHER_MAX_M := 6.0
const EDGE_FEATHER_WOBBLE := 0.6
const EDGE_WOBBLE_OFFSET := Vector2(911.0, -517.0)


static func cells_for_feet(feet: int) -> int:
	return roundi(float(feet) / FEET_PER_CELL)


## The size in cells of a map `width_ft` by `depth_ft` (whole squares, rounded); a depth of 0
## or less means a square map.
static func size_cells(width_ft: int, depth_ft: int = 0) -> Vector2i:
	var depth := depth_ft if depth_ft > 0 else width_ft
	return Vector2i(cells_for_feet(width_ft), cells_for_feet(depth))


## Why a map `width_ft` by `depth_ft` (0: square) cannot be made, in one sentence, or "" when
## it can: each side, in whole 5 ft squares, must be MIN_FT to MAX_FT.
static func size_error(width_ft: int, depth_ft: int = 0) -> String:
	if MapDocument.size_in_range(size_cells(width_ft, depth_ft)):
		return ""
	return "A map side must be %d to %d ft." % [MIN_FT, MAX_FT]


## True when a map `width_ft` by `depth_ft` (0: square) is over RECOMMENDED_MAX_FT on either
## side, so the New map screen shows its quiet "big map" line.
static func is_big(width_ft: int, depth_ft: int = 0) -> bool:
	var depth := depth_ft if depth_ft > 0 else width_ft
	return maxi(width_ft, depth) > RECOMMENDED_MAX_FT


## A new map `size_ft` feet wide (X) and `depth_ft` deep (Z; 0 or less: square). With a
## starting biome (a palette biome id), the base surface is that biome's ground surface and
## the starting cover is painted into its masks; with BARE_BIOME (or a biome the palette
## lacks) it is BARE_SURFACE and unpainted. With a `landform` other than
## StartingLandform.FLAT the recipe shapes the document first (heights, carved water, a
## crossing, from the seed) and the glade is centred on its stage. A big or long map's thin
## cover is then greened (LandformPlacement.paint_sparse). The scatter rows are left empty:
## they are generated from the masks once the map is shown. A size size_error() refuses gives
## null, with the error pushed.
static func create(
	size_ft: int,
	biome_id: String,
	seed_value: int,
	root: String = PaletteLibrary.DEFAULT_ROOT,
	landform: String = StartingLandform.FLAT,
	depth_ft: int = 0
) -> MapDocument:
	var refusal := size_error(size_ft, depth_ft)
	if refusal != "":
		push_error("NewMap: " + refusal)
		return null
	var biome := PaletteLibrary.biome(biome_id, root) if biome_id != BARE_BIOME else {}
	var surface: String = biome.get("ground_surface", "")
	if surface == "":
		surface = BARE_SURFACE
	var doc := MapDocument.create_flat(
		size_cells(size_ft, depth_ft), surface, PaletteLibrary.palette_version(root), seed_value
	)
	var stage := Vector2.ZERO
	var glade := {}
	var clearings: Array = []
	if landform != StartingLandform.FLAT:
		var shaped := StartingLandform.apply(doc, landform, seed_value, biome_id, root)
		stage = shaped.stage
		glade = shaped.get("glade", {})
		clearings = shaped.get("clearings", [])
	if not biome.is_empty():
		paint_starting_cover(doc, biome_id, stage, glade, clearings)
		LandformPlacement.paint_sparse(doc, biome_id, root)
	return doc


## create() from the new-map spec NewMapDialog emits and AuthoringController opens:
## {"size_ft" (the width), "depth_ft", "biome_id", "seed", "landform"}, each optional
## (DEFAULT_SIZE_FT, the width, BARE_BIOME, a fresh random_seed(), StartingLandform.FLAT).
static func from_spec(spec: Dictionary, root: String = PaletteLibrary.DEFAULT_ROOT) -> MapDocument:
	return create(
		int(spec.get("size_ft", DEFAULT_SIZE_FT)),
		String(spec.get("biome_id", BARE_BIOME)),
		int(spec.get("seed", random_seed())),
		root,
		String(spec.get("landform", StartingLandform.FLAT)),
		int(spec.get("depth_ft", 0))
	)


## The loading line while a map opens from `spec` (empty for a map that is not new): a
## landform other than Flat is named ("Shaping the valley..."); anything else is "Building
## the map...".
static func opening_status(spec: Dictionary) -> String:
	var kind := String(spec.get("landform", StartingLandform.FLAT))
	if kind == StartingLandform.FLAT or not StartingLandform.NAMES.has(kind):
		return "Building the map..."
	return "Shaping the %s..." % String(StartingLandform.NAMES[kind]).to_lower()


## Paints `biome_id` over the whole document with the starting cover (see the header),
## replacing any biome masks it had. The glade is centred on `centre` (map XZ metres; a
## landform's stage): the groves still grow toward the map's edges, so a stage near one
## side simply shifts the glade there. A landform may shape the glade instead (`glade`, the
## recipe's {"line": PackedVector2Array, "half_width", "rise", and optionally "near",
## "near_open", "near_edge"}; P5-7, the Valley's floor): the glade is then the ground within
## `half_width` of the line, the groves come back over the next `rise` metres, and the bank
## facing the camera stays thinner (glade_density). `clearings` ([{"at", "radius"}], a big
## or long map's meadows and tarn shores, LandformGrowth) open more ground
## (clearing_density). On a map with room (LandformGrowth.room) the copses and clearings of
## the cover noise grow by up to COVER_FEATURE_GROWTH, so a big map's forest keeps a few bold
## shapes instead of finer noise. Every map's cover feathers out at its edge (edge_feather).
static func paint_starting_cover(
	doc: MapDocument,
	biome_id: String,
	centre: Vector2 = Vector2.ZERO,
	glade: Dictionary = {},
	clearings: Array = []
) -> void:
	var count := doc.sample_count()
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(count)
	density.resize(count)
	var noise := _cover_noise(
		doc.map_seed, COVER_FEATURE_M * (1.0 + COVER_FEATURE_GROWTH * LandformGrowth.room(doc))
	)
	var half := doc.extent_m() * 0.5
	var feather := edge_feather_m(half)
	var feather_reach := feather * (1.0 + EDGE_FEATHER_WOBBLE)
	var line: PackedVector2Array = glade.get("line", PackedVector2Array())
	for z in doc.samples_z():
		for x in doc.samples_x():
			var world := doc.sample_to_world(Vector2(x, z))
			var noise_value := noise.get_noise_2d(world.x, world.y)
			var value := (
				glade_density(world, glade, noise_value)
				if line.size() >= 2
				else starting_density(world - centre, half, noise_value)
			)
			if not clearings.is_empty():
				value = clearing_density(world, clearings, value, noise_value)
			if minf(half.x - absf(world.x), half.y - absf(world.y)) < feather_reach:
				var at := world * 0.5 + EDGE_WOBBLE_OFFSET
				value *= edge_feather(world, half, feather, noise.get_noise_2d(at.x, at.y))
				value = value if value >= COVER_MIN_DENSITY else 0.0
			var byte := roundi(value * 255.0)
			var index := doc.sample_index(x, z)
			density[index] = byte
			slots[index] = 1 if byte > 0 else 0
	doc.biome_ids = PackedStringArray([biome_id])
	doc.biome_slots = slots
	doc.biome_density = density


## The starting cover density (0..1) at world XZ `world` on a map of half extent `half`,
## given the cover noise there (-1..1). Pure.
static func starting_density(world: Vector2, half: Vector2, noise_value: float) -> float:
	var u := absf(world.x) / maxf(half.x, 0.001)
	var v := absf(world.y) / maxf(half.y, 0.001)
	# Rounded-square distance from the centre: 0 at the centre, 1 at an edge midpoint.
	var reach := pow(pow(u, 4.0) + pow(v, 4.0), 0.25)
	return _cover_value(smoothstep(COVER_GLADE_RADIUS, COVER_EDGE_RADIUS, reach), noise_value)


## The starting cover density (0..1) of a line glade (P5-7) at `distance` metres from its
## line: the glade's density within `half_width`, rising over the next `rise` metres to
## `edge_max` of the way to the groves' density (1: the groves'), plus the cover noise
## (-1..1). Pure.
static func line_density(
	distance: float, half_width: float, rise: float, noise_value: float, edge_max: float = 1.0
) -> float:
	var edge := smoothstep(half_width, half_width + maxf(rise, 0.001), distance)
	return _cover_value(edge * edge_max, noise_value)


## The starting cover density (0..1) at map point `world` under a line glade `glade` (the
## recipe's {"line", "half_width", "rise"}, optionally "near", "near_open", "near_cap" and
## "near_edge"), given the cover noise there. On the bank facing `near` (the direction toward
## the camera, StartingLandform.NEAR) the glade reaches `near_open` metres further, that band
## held at most at `near_cap` whatever the noise, and the groves beyond come back only to
## `near_edge` of their density, each in proportion to how squarely the bank
## faces `near` (fully from GLADE_NEAR_FULL_DOT on, so a bank 45 degrees off the camera
## counts whole), so trees on the camera-side slope do not stand between the camera and the
## glade (P5-7, the Valley's near bank). Pure.
static func glade_density(world: Vector2, glade: Dictionary, noise_value: float) -> float:
	var line: PackedVector2Array = glade.line
	var near_at := StartingLandform.nearest_on(line, world)
	var facing := 0.0
	var near: Vector2 = glade.get("near", Vector2.ZERO)
	if near != Vector2.ZERO and near_at.x > 1e-3:
		var k := int(near_at.z)
		var q := Geometry2D.get_closest_point_to_segment(world, line[k], line[k + 1])
		facing = smoothstep(0.0, GLADE_NEAR_FULL_DOT, (world - q).normalized().dot(near))
	var half_width := float(glade.half_width)
	var open := half_width + float(glade.get("near_open", 0.0)) * facing
	var value := line_density(
		near_at.x,
		open,
		float(glade.rise),
		noise_value,
		lerpf(1.0, float(glade.get("near_edge", 1.0)), facing)
	)
	if near_at.x > half_width and near_at.x <= open:
		# The near band: the cover noise would otherwise raise copses of tall trees in it.
		value = minf(value, lerpf(1.0, float(glade.get("near_cap", 1.0)), facing))
		value = value if value >= COVER_MIN_DENSITY else 0.0
	return value


## The cover density `value` at map point `world` opened by `clearings` ([{"at", "radius"}],
## LandformGrowth's meadows and tarn shores): within CLEARING_INNER of a clearing's radius it
## is at most CLEARING_OPEN_SHARE of the glade's density, easing back to `value` at the
## radius, the outline pushed in and out by the cover noise (`noise_value`, CLEARING_WARP of
## the radius) so it is not a circle. Pure.
static func clearing_density(
	world: Vector2, clearings: Array, value: float, noise_value: float
) -> float:
	for clearing: Dictionary in clearings:
		var radius := maxf(float(clearing.radius), 1e-3)
		var reach := world.distance_to(clearing.at) / radius + noise_value * CLEARING_WARP
		var open := lerpf(
			COVER_CENTRE_DENSITY * CLEARING_OPEN_SHARE, 1.0, smoothstep(CLEARING_INNER, 1.0, reach)
		)
		value = minf(value, open)
	return value if value >= COVER_MIN_DENSITY else 0.0


## The share of the cover kept at map point `world` on a map of half extent `half` (see
## EDGE_FEATHER_SHARE): all of it from `width` inside the edge, that depth stretched by
## EDGE_FEATHER_WOBBLE times `wobble` (-1..1), easing to none at the edge. Pure.
static func edge_feather(world: Vector2, half: Vector2, width: float, wobble: float) -> float:
	var inside := minf(half.x - absf(world.x), half.y - absf(world.y))
	return smoothstep(0.0, width * (1.0 + EDGE_FEATHER_WOBBLE * wobble), inside)


## The depth (metres) of the cover's edge feather on a map of half extent `half`.
static func edge_feather_m(half: Vector2) -> float:
	return clampf(
		minf(half.x, half.y) * EDGE_FEATHER_SHARE, EDGE_FEATHER_MIN_M, EDGE_FEATHER_MAX_M
	)


## The cover density for `edge` (0 the glade, 1 the groves) and the noise there.
static func _cover_value(edge: float, noise_value: float) -> float:
	var value := lerpf(COVER_CENTRE_DENSITY, COVER_EDGE_DENSITY, edge)
	value += noise_value * COVER_NOISE_AMPLITUDE
	value = clampf(value, 0.0, 1.0)
	return value if value >= COVER_MIN_DENSITY else 0.0


static func _cover_noise(seed_value: int, feature_m: float = COVER_FEATURE_M) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_value & 0x7fffffff
	noise.frequency = 1.0 / feature_m
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	return noise


## The empty dressing document for a Blender-made map whose geometry spans `local_bounds`
## (in the map root's own frame, which is the document's frame). The document is centred
## on the origin like every map document, so it is made large enough to reach the farthest
## geometry on each axis, in whole even cells, within MapDocument's size limits. No base
## surface (the GLB brings its ground) and has_base_map set.
static func create_dressing(
	local_bounds: AABB,
	seed_value: int,
	cell_size_m: float = LevelData.DEFAULT_GRID_CELL_SIZE,
	root: String = PaletteLibrary.DEFAULT_ROOT
) -> MapDocument:
	var cells := dressing_cells(local_bounds, cell_size_m)
	var doc := MapDocument.create_flat(cells, "", PaletteLibrary.palette_version(root), seed_value)
	doc.has_base_map = true
	return doc


## The size in cells of the dressing document over geometry spanning `local_bounds`: centred
## on the origin, reaching the farthest geometry on each axis, in whole even cells, within
## MapDocument's size limits. Pure.
static func dressing_cells(
	local_bounds: AABB, cell_size_m: float = LevelData.DEFAULT_GRID_CELL_SIZE
) -> Vector2i:
	var reach := Vector2(
		maxf(absf(local_bounds.position.x), absf(local_bounds.end.x)),
		maxf(absf(local_bounds.position.z), absf(local_bounds.end.z))
	)
	return Vector2i(_even_cells(reach.x, cell_size_m), _even_cells(reach.y, cell_size_m))


static func _even_cells(half_extent_m: float, cell_size_m: float) -> int:
	var cells := ceili(2.0 * half_extent_m / cell_size_m)
	cells += cells % 2
	return clampi(cells, 2, MapDocument.MAX_SIZE_CELLS)


## A fresh map seed. Kept within 31 bits: the ground shader's breakup seed and FastNoiseLite
## both take a 32-bit int, and MapDocumentIO writes the seed as a JSON number.
static func random_seed() -> int:
	return randi() & 0x7fffffff
