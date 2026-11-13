class_name PainterTreeSpecies
extends RefCounted
## Which scatter trees the painted look grows itself, and what each tree row becomes: a species,
## an age, an openness and a seed (docs/systems/painter.md "Trees"). Pure static functions over
## the data in species.json (the asset table and each species' form props, as the painterspike
## sheet resolved them), safe on a worker thread once data() has been read on the main thread.
##
## Every value is a function of the row alone, so a tree does not change when another is painted
## or erased, and every peer grows the same tree from the same map:
##   species   the first asset-table group the asset id contains ("Tree_Oak" in "Tree_Oak_v1");
##             no group (Acacia, Cactus, Palm, DeadTree) leaves the asset to its GLB
##   age       from the row's scale against the asset's nominal 1 (the spike used the scale
##             against the mean of the map's rows of that asset, which moved with every brush)
##   openness  a pure function of the point: the map's biome density there (dense forest grows
##             closed, tall-boled trees, a lone tree spreads) and a slow world noise for variety;
##             the spike counted neighbouring tree rows within 6 m, which made a tree change when
##             one beside it was painted
##   seed      an integer hash of the row's position in centimetres (map rows are lossless on a
##             2^-10 grid, so every platform rounds them the same)

const DATA := "res://painter/trees/species.json"
## The row's scale is at index SCALE_AT of its MapDocument row (ScatterGenerator.ROW_STRIDE).
const SCALE_AT := 7
## Age at the nominal scale, its slope per unit of scale, and its range (the spike's).
const AGE := {"mid": 0.6, "slope": 1.2, "lo": 0.25, "hi": 0.95}
## A sapling's (the spike's: young rowan).
const SAPLING_AGE := {"mid": 0.28, "slope": 0.5, "lo": 0.15, "hi": 0.42}
const SAPLING_GROUP := "Tree_Sapling"
## Openness: closed at a full biome density, open where none; the noise's period in metres and
## its share.
const OPEN_DENSE := 0.2
const OPEN_BARE := 0.85
const OPEN_NOISE_M := 23.0
const OPEN_NOISE := 0.3

static var _data: Dictionary = {}
static var _arch: Dictionary = {}


## The species data (loaded once): {"assets": group -> species, "species": name ->
## {"conifer", "form"}, "wide"}.
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if parsed is Dictionary:
			_data = parsed
	return _data


## The species the painted look grows for `asset_id`, "" when it stays a GLB.
static func species_for(asset_id: String) -> String:
	var assets: Dictionary = data().get("assets", {})
	for group: String in assets:
		if asset_id.contains(group):
			return str(assets[group])
	return ""


## Every species name in the data.
static func names() -> Array[String]:
	var out: Array[String] = []
	out.assign((data().get("species", {}) as Dictionary).keys())
	return out


static func is_conifer(species: String) -> bool:
	return bool(((data()["species"] as Dictionary)[species] as Dictionary)["conifer"])


## The pack's neighbour mode (1: a grid over the whole tree), the spike's.
static func wide() -> int:
	return int(data().get("wide", 1))


## The generator's architecture of `species` (PainterTreeSkeleton.species_of), cached. Call it
## on the main thread before a worker grows the species.
static func architecture(species: String) -> Dictionary:
	if not _arch.has(species):
		var form: Dictionary = ((data()["species"] as Dictionary)[species] as Dictionary)["form"]
		_arch[species] = PainterTreeSkeleton.species_of(form)
	return _arch[species]


## A row's age from its scale (pure).
static func age_of(asset_id: String, scale: float) -> float:
	var k: Dictionary = SAPLING_AGE if asset_id.contains(SAPLING_GROUP) else AGE
	return clampf(float(k["mid"]) + (scale - 1.0) * float(k["slope"]), k["lo"], k["hi"])


## A tree's key: its row position in whole centimetres.
static func key_of(position: Vector3) -> Vector3i:
	return Vector3i(
		roundi(position.x * 100.0), roundi(position.y * 100.0), roundi(position.z * 100.0)
	)


## A tree's seed from its key (integer arithmetic only, the same on every platform).
static func seed_of(key: Vector3i) -> int:
	var h: int = (key.x * 73856093) ^ (key.y * 19349663) ^ (key.z * 83492791)
	return absi(h) % 1000000007


## Openness at `position` for a biome density there of `density` (0..1): pure in the point.
static func openness_at(position: Vector3, density: float) -> float:
	var base := lerpf(OPEN_BARE, OPEN_DENSE, clampf(density, 0.0, 1.0))
	var n := _vnoise(position.x / OPEN_NOISE_M + 17.0, position.z / OPEN_NOISE_M + 5.0) - 0.5
	return clampf(base + n * OPEN_NOISE, 0.1, 0.9)


## The generator's context for a row: {"age", "openness"}.
static func context(
	asset_id: String, scale: float, position: Vector3, density: float
) -> Dictionary:
	return {"age": age_of(asset_id, scale), "openness": openness_at(position, density)}


## A smooth value noise in 0..1 over the plane (integer lattice, hashed corners).
static func _vnoise(x: float, z: float) -> float:
	var xi := floorf(x)
	var zi := floorf(z)
	var fx := x - xi
	var fz := z - zi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := _corner(int(xi), int(zi))
	var b := _corner(int(xi) + 1, int(zi))
	var c := _corner(int(xi), int(zi) + 1)
	var d := _corner(int(xi) + 1, int(zi) + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


static func _corner(x: int, z: int) -> float:
	var h: int = (x * 374761393 + z * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10006.0
