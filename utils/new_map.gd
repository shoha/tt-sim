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


static func cells_for_feet(feet: int) -> int:
	return roundi(float(feet) / FEET_PER_CELL)


## A new flat map `size_ft` feet square. With a starting biome (a palette biome id), the base
## surface is that biome's ground surface and the starting cover is painted into its masks;
## with BARE_BIOME (or a biome the palette lacks) it is BARE_SURFACE and unpainted. The
## scatter rows are left empty: they are generated from the masks once the map is shown.
static func create(
	size_ft: int, biome_id: String, seed_value: int, root: String = PaletteLibrary.DEFAULT_ROOT
) -> MapDocument:
	var cells := cells_for_feet(size_ft)
	var biome := PaletteLibrary.biome(biome_id, root) if biome_id != BARE_BIOME else {}
	var surface: String = biome.get("ground_surface", "")
	if surface == "":
		surface = BARE_SURFACE
	var doc := MapDocument.create_flat(
		Vector2i(cells, cells), surface, PaletteLibrary.palette_version(root), seed_value
	)
	if not biome.is_empty():
		paint_starting_cover(doc, biome_id)
	return doc


## Paints `biome_id` over the whole document with the starting cover (see the header),
## replacing any biome masks it had.
static func paint_starting_cover(doc: MapDocument, biome_id: String) -> void:
	var count := doc.sample_count()
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(count)
	density.resize(count)
	var noise := _cover_noise(doc.map_seed)
	var half := doc.extent_m() * 0.5
	for z in doc.samples_z():
		for x in doc.samples_x():
			var world := doc.sample_to_world(Vector2(x, z))
			var value := starting_density(world, half, noise.get_noise_2d(world.x, world.y))
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
	var edge := smoothstep(COVER_GLADE_RADIUS, COVER_EDGE_RADIUS, reach)
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
