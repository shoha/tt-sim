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


static func cells_for_feet(feet: int) -> int:
	return roundi(float(feet) / FEET_PER_CELL)


## A new map `size_ft` feet square. With a starting biome (a palette biome id), the base
## surface is that biome's ground surface and the starting cover is painted into its masks;
## with BARE_BIOME (or a biome the palette lacks) it is BARE_SURFACE and unpainted. With a
## `landform` other than StartingLandform.FLAT the recipe shapes the document first (heights,
## carved water, a crossing, from the seed) and the glade is centred on its stage. The
## scatter rows are left empty: they are generated from the masks once the map is shown.
static func create(
	size_ft: int,
	biome_id: String,
	seed_value: int,
	root: String = PaletteLibrary.DEFAULT_ROOT,
	landform: String = StartingLandform.FLAT
) -> MapDocument:
	var cells := cells_for_feet(size_ft)
	var biome := PaletteLibrary.biome(biome_id, root) if biome_id != BARE_BIOME else {}
	var surface: String = biome.get("ground_surface", "")
	if surface == "":
		surface = BARE_SURFACE
	var doc := MapDocument.create_flat(
		Vector2i(cells, cells), surface, PaletteLibrary.palette_version(root), seed_value
	)
	var stage := Vector2.ZERO
	var glade := {}
	if landform != StartingLandform.FLAT:
		var shaped := StartingLandform.apply(doc, landform, seed_value, biome_id, root)
		stage = shaped.stage
		glade = shaped.get("glade", {})
	if not biome.is_empty():
		paint_starting_cover(doc, biome_id, stage, glade)
	return doc


## create() from the new-map spec NewMapDialog emits and AuthoringController opens:
## {"size_ft", "biome_id", "seed", "landform"}, each optional (DEFAULT_SIZE_FT, BARE_BIOME,
## a fresh random_seed(), StartingLandform.FLAT).
static func from_spec(spec: Dictionary, root: String = PaletteLibrary.DEFAULT_ROOT) -> MapDocument:
	return create(
		int(spec.get("size_ft", DEFAULT_SIZE_FT)),
		String(spec.get("biome_id", BARE_BIOME)),
		int(spec.get("seed", random_seed())),
		root,
		String(spec.get("landform", StartingLandform.FLAT))
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
## facing the camera stays thinner (glade_density).
static func paint_starting_cover(
	doc: MapDocument, biome_id: String, centre: Vector2 = Vector2.ZERO, glade: Dictionary = {}
) -> void:
	var count := doc.sample_count()
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(count)
	density.resize(count)
	var noise := _cover_noise(doc.map_seed)
	var half := doc.extent_m() * 0.5
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


## The cover density for `edge` (0 the glade, 1 the groves) and the noise there.
static func _cover_value(edge: float, noise_value: float) -> float:
	var value := lerpf(COVER_CENTRE_DENSITY, COVER_EDGE_DENSITY, edge)
	value += noise_value * COVER_NOISE_AMPLITUDE
	value = clampf(value, 0.0, 1.0)
	return value if value >= COVER_MIN_DENSITY else 0.0


static func _cover_noise(seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_value & 0x7fffffff
	noise.frequency = 1.0 / COVER_FEATURE_M
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
	var reach := Vector2(
		maxf(absf(local_bounds.position.x), absf(local_bounds.end.x)),
		maxf(absf(local_bounds.position.z), absf(local_bounds.end.z))
	)
	var cells := Vector2i(_even_cells(reach.x, cell_size_m), _even_cells(reach.y, cell_size_m))
	var doc := MapDocument.create_flat(cells, "", PaletteLibrary.palette_version(root), seed_value)
	doc.has_base_map = true
	return doc


static func _even_cells(half_extent_m: float, cell_size_m: float) -> int:
	var cells := ceili(2.0 * half_extent_m / cell_size_m)
	cells += cells % 2
	return clampi(cells, 2, MapDocument.MAX_SIZE_CELLS)


## A fresh map seed. Kept within 31 bits: the ground shader's breakup seed and FastNoiseLite
## both take a 32-bit int, and MapDocumentIO writes the seed as a JSON number.
static func random_seed() -> int:
	return randi() & 0x7fffffff
