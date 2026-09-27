class_name ScatterGenerator
extends RefCounted

## Turns a palette biome and a painted density field into scatter rows: palette asset id ->
## flat [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz] rows (Y-up, MapDocument.ROW_STRIDE floats
## each), for the instances whose origin lies in a given set of 10 m chunk cells
## (ScatterChunker.CHUNK_SIZE_WORLD_UNITS) and inside the map bounds. Pure statics; the
## only state is a per-call memo that dies with the call. Species rules are the palette
## contract (docs/ASSET_PIPELINE.md section 9); the look being matched is treecube's
## Geoscatter presets (treecube/geoscatter.py). ScatterPlan decides how each species is
## sampled and how dense its candidates must be; this class evaluates candidates.
##
## Region independence. A brush regenerates only the chunks it touched, so a chunk's rows
## must not depend on which other chunks are generated with it. Nothing here iterates in
## an order that matters: every species (or spacing group) owns a global candidate field,
## a grid of buckets each holding ScatterPlan.CANDIDATES_PER_BUCKET candidates whose
## position, priority and every later random choice come from hash(map seed, biome,
## field, bucket, index). A candidate's fate is a pure function of that field and the
## inputs, evaluated lazily and memoized, so a chunk alone, with its neighbours, or inside
## the whole map yields byte-identical rows. Exactly four candidates per bucket (not a
## Poisson count) keeps the delivered count stable at map scale while staying random
## inside a bucket.
##
## Spacing is Matern III: a candidate survives unless a surviving candidate of higher
## priority lies within the spacing. That is random sequential packing driven by a finite
## candidate intensity, so it reaches densities Matern II (drop both of a close pair)
## cannot: boreal large trees want 0.032 per m2 at 4.5 m, 93 percent of the jamming limit,
## while Matern II saturates at 0.016. The survival recursion only ever climbs to higher
## priorities, so it terminates; it runs on an explicit stack and is memoized, and it is
## evaluated the same way whichever chunk asks, which makes chunk borders seamless.
##
## Everything else thins after spacing: painted density (through the size class's response,
## ScatterPlan.DENSITY_RESPONSE: trees lead, ground cover lags), the pattern noise, slope,
## clump membership, near/avoid relations and the clearance around larger classes each give
## a keep probability, and one hashed uniform per candidate is tested against their
## product. Thinning after spacing is what makes a half-density brush deliver the share its
## response asks for (thinning the candidates instead would barely dent a saturated packing), it
## never breaks the spacing, and it matches Geoscatter, whose masks and patterns cull
## after its distribution.
##
## Species are resolved large -> ground (palette order). Relations and clearance only look
## at earlier species, and ask for their final instances near a point lazily, so a chunk
## near a border sees exactly the boulders or trees the neighbouring chunk would hold.
## That laziness has a reach: repainting one chunk can change relation-driven instances
## (stones near a boulder) up to a relation's distance plus transition into the next one.

const ROW_STRIDE := 10
## Geoscatter's slope falloff (treecube SLOPE_FALLOFF_DEGREES): full density up to
## slope_max_deg, linear to none at slope_max_deg + this.
const SLOPE_FALLOFF_DEG := 10.0
## Random tilt of normal-aligned species around the ground normal, radians
## (treecube: s_rot_random_tilt_value 0.12 on every kind that is not upright).
const NORMAL_TILT_MAX_RAD := 0.12
## Clumped ground cover shrinks toward the clump edge by up to this share (treecube keeps
## Geoscatter's clump scale at 0.2 for ground cover only).
const CLUMP_SCALE_SHRINK := 0.2
## Pattern noise defaults when geoscatter_pattern lacks a value (treecube's _pattern).
const DEFAULT_NOISE_SCALE := 2.0
const DEFAULT_MAPPING_SCALE := 0.1
const DEFAULT_NOISE_DETAIL := 1.0
const DEFAULT_NOISE_CONTRAST := 2.0

const _MASK32 := 0xFFFFFFFF
## Bucket keys pack two signed bucket indices into one int.
const _BUCKET_OFFSET := 1 << 20
const _BUCKET_SPAN := 1 << 21
## Candidate record in a bucket: x, z, priority (32-bit hash), owner species, id, hash.
const _STRIDE := 6
## Salts for the independent hashed values of one candidate.
const _SALT_X := 0x68E31DA4
const _SALT_Z := 0x3C6EF372
const _SALT_PRIORITY := 0x1B56C4E9
const _SALT_OWNER := 0x5BD1E995
const _SALT_ACCEPT := 0x27D4EB2F
const _SALT_ASSET := 0x165667B1
const _SALT_YAW := 0x61C88647
const _SALT_SCALE := 0x2545F491
const _SALT_TILT := 0x4F1BBCDC
const _SALT_TILT_DIRECTION := 0x7A4D3B1F
const _SALT_RADIUS := 0x0B4E0EF3
const _SALT_CANDIDATE := 0x632BE5AB
const _SALT_NOISE := 0x2F6B1C3D


## Rows for `cells` of one biome. `species` is PaletteLibrary.species(biome_id) (or any
## list of the same shape, in large -> ground order); `density_at(Vector2 world xz) ->
## float` is the painted density 0..1, `height_at(Vector2) -> float` the ground height and
## `normal_at(Vector2) -> Vector3` the unit ground normal. `bounds` is the map rectangle in
## world XZ; nothing outside it is placed. Returns asset id -> flat rows; rows of one
## asset are in cell order as given, then in a fixed order inside each cell.
static func generate(
	biome_id: String,
	species: Array[Dictionary],
	density_at: Callable,
	height_at: Callable,
	normal_at: Callable,
	map_seed: int,
	cells: Array[Vector2i],
	bounds: Rect2
) -> Dictionary[String, PackedFloat32Array]:
	var cells_by_species: Array = []
	cells_by_species.resize(species.size())
	cells_by_species.fill(cells)
	return generate_species_cells(
		biome_id, species, density_at, height_at, normal_at, map_seed, cells_by_species, bounds
	)


## generate() with its own cell list per species: `cells_by_species[s]` (an
## Array[Vector2i], possibly empty) lists the cells species s is generated for. A brush
## regenerates every species in the cells its dab touches but only the relation-driven
## ones in the halo around them (see species_reach), which is most of the saving: the
## halo species are the sparse ones. Rows of one asset come out in the order generate()
## gives; species with a shorter or missing list simply place nothing elsewhere.
##
## `species_density_at`, when valid, replaces `density_at`: Callable(p, ScatterGround role)
## -> float, called with each species' ScatterPlan ground_role (document_fields: boulders
## gather at cliff feet, trees keep back from tier faces).
static func generate_species_cells(
	biome_id: String,
	species: Array[Dictionary],
	density_at: Callable,
	height_at: Callable,
	normal_at: Callable,
	map_seed: int,
	cells_by_species: Array,
	bounds: Rect2,
	species_density_at: Callable = Callable()
) -> Dictionary[String, PackedFloat32Array]:
	var the_plan := ScatterPlan.build(biome_id, species, map_seed)
	var ctx := _context(the_plan, density_at, height_at, normal_at, bounds)
	if species_density_at.is_valid():
		ctx["species_density_at"] = species_density_at
	var result: Dictionary[String, PackedFloat32Array] = {}
	for s in the_plan.species.size():
		var cells: Array[Vector2i] = []
		if s < cells_by_species.size() and cells_by_species[s] is Array:
			cells.assign(cells_by_species[s])
		if not cells.is_empty():
			_generate_species(ctx, s, cells, result)
	return result


## How far, in metres, the painted density can reach into each species' instances: an
## instance of species s at p depends on the density within species_reach(plan)[s] of p
## (plus one sample step for the bilinear lookup), and on nothing painted further away.
## Spacing, candidate positions and species choice never depend on paint, so a species
## with no relations or clearance has reach 0: only its own point matters. Otherwise the
## reach adds up along every dependency, because the instance a relation looks at has
## its own reach: avoid and near relations (distance plus transition), a clumped
## species' near relations through its parents (clump radius with jitter plus transition,
## then the relation), and clearance around larger classes. Dependencies only point to
## larger size classes, which the palette lists first; the passes repeat until nothing
## grows so a palette listed in another order still resolves (the chains are acyclic, so
## at most one pass per species). This is the "relation halo" a brush regenerates beyond
## the cells it painted.
static func species_reach(the_plan: Dictionary) -> PackedFloat32Array:
	var entries: Array = the_plan.species
	var reach := PackedFloat32Array()
	reach.resize(entries.size())
	for _pass in entries.size() + 1:
		var grew := false
		for s in entries.size():
			var r := _reach_of(the_plan, s, reach)
			if r > reach[s]:
				reach[s] = r
				grew = true
		if not grew:
			break
	return reach


## One species' reach given the current estimates for the others (see species_reach).
static func _reach_of(the_plan: Dictionary, s: int, reach: PackedFloat32Array) -> float:
	var entry: Dictionary = the_plan.species[s]
	var fields: Array = the_plan.fields
	var r := 0.0
	for relation in entry.avoid:
		r = maxf(r, relation.distance + relation.transition + reach[relation.target])
	# Clump children take near relations through their parents (_parent_kept), whose
	# influence spreads over the clump; unclumped species take them directly.
	var through := 0.0
	if entry.clumped:
		var clump: Dictionary = entry.rule.clump
		through = clump.radius_m * (1.0 + ScatterPlan.CLUMP_RADIUS_JITTER) + clump.transition_m
	for relation in entry.near:
		r = maxf(r, through + relation.distance + relation.transition + reach[relation.target])
	for field_index in entry.clearance:
		for owner in fields[field_index].owners:
			if owner != s:
				r = maxf(r, entry.clearance_m + reach[owner])
	return r


## generate() for one biome of a MapDocument: its density mask, heights and extent, over
## `cells`, with the palette under `palette_root`.
static func generate_for_document(
	doc: MapDocument,
	biome_id: String,
	cells: Array[Vector2i],
	palette_root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary[String, PackedFloat32Array]:
	var fields := document_fields(
		doc,
		biome_id,
		Rect2(),
		PackedStringArray(PaletteLibrary.surfaces_with_role("built", palette_root)),
		PackedStringArray(PaletteLibrary.surfaces_with_role("cliff", palette_root))
	)
	var cells_by_species: Array = []
	var species := PaletteLibrary.species(biome_id, palette_root)
	cells_by_species.resize(species.size())
	cells_by_species.fill(cells)
	return generate_species_cells(
		biome_id,
		species,
		fields.density_at,
		fields.height_at,
		fields.normal_at,
		doc.map_seed,
		cells_by_species,
		fields.bounds,
		fields.species_density_at
	)


## The sampling fields generate() takes, built from a MapDocument for one biome:
## {density_at, rock_density_at, species_density_at, height_at, normal_at, bounds}. Density
## is the biome's painted density (0 where another biome or none is painted), bilinear on
## the document's sample grid, times what the ground lets grow there for a ScatterGround
## role (species_density_at(p, role), ScatterGround.species_density; density_at and
## rock_density_at are its ROLE_COVER and ROLE_ROCK), `built_surfaces` and `cliff_surfaces`
## naming the palette surfaces with role "built" and "cliff".
## Heights and normals follow the terrain's own triangles (triangle_height,
## triangle_normal): the rendered chunks and the collision heightfield split every quad
## on the same diagonal, and a bilinear height differs from that surface by up to
## |h00 + h11 - h10 - h01| / 4 (0.38 m on a tier step), which floated or buried plants on
## sculpted ground. Outside the map the density is 0 and heights clamp to the edge.
##
## `window` (world XZ), when it has an area, limits the density decode to the samples
## inside it plus one sample of margin; density reads 0 elsewhere. Decoding the whole
## mask is a GDScript loop over every sample (about 6 ms on a 200 ft map), which a brush
## regenerating a few cells does not need. The caller must make the window cover every
## point generation can look at: the cells plus the deepest species_reach. The rule fields
## (curvature, steepness nearby) are computed over the same samples, reading heights up to
## TerrainRules.CURVATURE_RADIUS_M beyond them.
static func document_fields(
	doc: MapDocument,
	biome_id: String,
	window: Rect2 = Rect2(),
	built_surfaces: PackedStringArray = PackedStringArray(),
	cliff_surfaces: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var count := doc.sample_count()
	var slot := doc.biome_ids.find(biome_id) + 1
	var density := PackedFloat32Array()
	density.resize(count)
	var low := Vector2i.ZERO
	var high := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	if window.has_area():
		var first := doc.world_to_sample(window.position).floor()
		var last := doc.world_to_sample(window.end).ceil()
		low = Vector2i(first).clamp(low, high)
		high = Vector2i(last).clamp(low, high)
	var stride := doc.samples_x()
	var painted := (
		slot > 0 and doc.biome_slots.size() == count and doc.biome_density.size() == count
	)
	if painted:
		for z in range(low.y, high.y + 1):
			for i in range(z * stride + low.x, z * stride + high.x + 1):
				if doc.biome_slots[i] == slot:
					density[i] = doc.biome_density[i] / 255.0
	var heights := doc.heights
	if heights.size() != count:
		heights = PackedFloat32Array()
		heights.resize(count)
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	# Only a biome with paint places anything, so only then are the rule fields worth their
	# decode (DressingGround reads heights alone through biome "").
	var ground_at := Callable()
	if painted:
		var samples := Rect2i(low, high - low + Vector2i.ONE)
		ground_at = ScatterGround.sampler(doc, heights, samples, built_surfaces, cliff_surfaces)
	var plain_at := func(p: Vector2) -> float:
		var at := (p + half) / step
		if at.x < 0.0 or at.y < 0.0 or at.x > columns - 1 or at.y > rows - 1:
			return 0.0
		return bilinear(density, columns, rows, at)
	var species_density_at := func(p: Vector2, role: int) -> float:
		var d: float = plain_at.call(p)
		return ScatterGround.species_density(d, ground_at.call(p, role), role) if d > 0.0 else d
	var height_at := func(p: Vector2) -> float:
		return triangle_height(heights, columns, rows, (p + half) / step)
	var normal_at := func(p: Vector2) -> Vector3:
		return triangle_normal(heights, columns, rows, (p + half) / step, step)
	return {
		"density_at": species_density_at.bind(ScatterGround.ROLE_COVER),
		"rock_density_at": species_density_at.bind(ScatterGround.ROLE_ROCK),
		"species_density_at": species_density_at,
		"height_at": height_at,
		"normal_at": normal_at,
		"bounds": Rect2(-half, doc.extent_m()),
	}


## Every chunk cell a rectangle touches, row-major (Z rows, X columns).
static func cells_in_bounds(
	bounds: Rect2, chunk_size: float = ScatterChunker.CHUNK_SIZE_WORLD_UNITS
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var low := ScatterChunker.cell_for(
		Vector3(bounds.position.x, 0.0, bounds.position.y), chunk_size
	)
	var high := ScatterChunker.cell_for(Vector3(bounds.end.x, 0.0, bounds.end.y), chunk_size)
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			cells.append(Vector2i(x, z))
	return cells


## A fresh evaluation context over a plan: per-field bucket and spacing memos, per-species
## final-decision memos, clump-parent memos and pattern noises. "edge" carries the clump
## edge distance of the candidate evaluated last to the row it becomes.
static func _context(
	the_plan: Dictionary,
	density_at: Callable,
	height_at: Callable,
	normal_at: Callable,
	bounds: Rect2
) -> Dictionary:
	var fields: Array[Dictionary] = []
	for field in the_plan.fields:
		var live: Dictionary = field.duplicate()
		live["buckets"] = {}
		live["spaced"] = {}
		fields.append(live)
	var finals: Array[Dictionary] = []
	var parents: Array[Dictionary] = []
	var parent_buckets: Array[Dictionary] = []
	var parent_lists: Array[Dictionary] = []
	var noises: Array = []
	var contrasts := PackedFloat64Array()
	for entry in the_plan.species:
		finals.append({})
		parents.append({})
		parent_buckets.append({})
		parent_lists.append({})
		var noise := _noise(entry, fields)
		noises.append(noise)
		contrasts.append(noise.get_meta("contrast") if noise != null else 0.0)
	return {
		"plan": the_plan,
		"fields": fields,
		"final": finals,
		"parents": parents,
		"parent_buckets": parent_buckets,
		"parent_lists": parent_lists,
		"noise": noises,
		"contrast": contrasts,
		"density_at": density_at,
		"species_density_at": func(p: Vector2, _role: int) -> float: return density_at.call(p),
		"height_at": height_at,
		"normal_at": normal_at,
		"bounds": bounds,
		"edge": 1.0,
	}


## The pattern noise of one species, or null. Derivation from Geoscatter's settings
## (treecube _pattern): the noise texture is sampled at global coordinates times
## mapping_scale (0.1), then Blender's Noise Texture multiplies by its own scale (2 for
## medium and small, 3 for ground) before evaluating Perlin noise on a unit lattice. So
## one lattice period is 1 / (0.1 * scale) metres: 5 m for scale 2, 3.3 m for scale 3,
## i.e. dense and sparse patches about 2.5 m and 1.7 m across. FastNoiseLite's Perlin at
## frequency f has the same unit lattice scaled by f, so f = mapping_scale * scale. Detail
## 1 is two octaves at gain 0.5 in Blender, as here. Geoscatter's contrast 2 stretches
## the value about 0.5; applied the same way (_pattern_value). Uncertain: whether
## Geoscatter's texture mapping multiplies (assumed) or divides by mapping_scale, and how
## its "id_greyscale" sampling of the Color output narrows the value spread; the result
## was judged at the game camera, not measured against a Blender render.
static func _noise(entry: Dictionary, fields: Array[Dictionary]) -> FastNoiseLite:
	if entry.pattern == null or entry.field < 0:
		return null
	var settings: Variant = entry.pattern.get("geoscatter_pattern", {})
	var texture: Variant = settings.get("texture_dict", {}) if settings is Dictionary else {}
	if not texture is Dictionary:
		texture = {}
	var mapping: Variant = texture.get("mapping_scale", [])
	var mapping_scale := DEFAULT_MAPPING_SCALE
	if mapping is Array and not mapping.is_empty():
		mapping_scale = _number(mapping[0], DEFAULT_MAPPING_SCALE)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = clampi(
		int(_number(texture.get("detail"), DEFAULT_NOISE_DETAIL)) + 1, 1, 4
	)
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	noise.frequency = absf(mapping_scale * _number(texture.get("scale"), DEFAULT_NOISE_SCALE))
	noise.seed = _mix(fields[entry.field].seed ^ _SALT_NOISE) & 0x7FFFFFFF
	noise.set_meta("contrast", _number(texture.get("contrast"), DEFAULT_NOISE_CONTRAST))
	return noise


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) else fallback


## Pattern value 0..1 at a point: 0.5 + contrast * noise / 2, clamped.
static func _pattern_value(noise: FastNoiseLite, contrast: float, x: float, z: float) -> float:
	return clampf(0.5 + 0.5 * contrast * noise.get_noise_2d(x, z), 0.0, 1.0)


static func _generate_species(
	ctx: Dictionary, s: int, cells: Array[Vector2i], result: Dictionary
) -> void:
	var entry: Dictionary = ctx.plan.species[s]
	if entry.field < 0:
		return
	var field: Dictionary = ctx.fields[entry.field]
	if field.empty:
		return
	var referenced: bool = entry.referenced
	var edge_needed: bool = entry.clump_scale
	var single_owner: bool = field.owners.size() == 1
	var bounds: Rect2 = ctx.bounds
	var chunk := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var size: float = field.bucket
	var rows := PackedFloat32Array()
	var assets := PackedInt32Array()
	for cell in cells:
		var area := Rect2(Vector2(cell) * chunk, Vector2(chunk, chunk)).intersection(bounds)
		if area.size.x <= 0.0 or area.size.y <= 0.0:
			continue
		for bj in range(floori(area.position.y / size), floori(area.end.y / size) + 1):
			for bi in range(floori(area.position.x / size), floori(area.end.x / size) + 1):
				var cands := _bucket(field, bi, bj)
				for c in range(0, cands.size(), _STRIDE):
					if not single_owner and int(cands[c + 3]) != s:
						continue
					var x: float = cands[c]
					var z: float = cands[c + 1]
					if floori(x / chunk) != cell.x or floori(z / chunk) != cell.y:
						continue
					# A species nothing else asks about needs no memo; one that is asked
					# about may already have been decided while resolving a neighbour.
					var placed := (
						_final(ctx, s, cands, c) if referenced else _evaluate(ctx, entry, cands, c)
					)
					if not placed:
						continue
					var edge: float = ctx.edge
					if edge_needed and referenced:
						edge = _membership(ctx, s, x, z).y
					assets.append(_append_row(ctx, entry, cands, c, edge, rows))
	_split_rows(entry.rule.assets, rows, assets, result)


static func _split_rows(
	asset_ids: Array, rows: PackedFloat32Array, assets: PackedInt32Array, result: Dictionary
) -> void:
	if rows.is_empty():
		return
	if asset_ids.size() == 1:
		result[String(asset_ids[0])] = rows
		return
	var per_asset: Array[PackedFloat32Array] = []
	for _i in asset_ids.size():
		per_asset.append(PackedFloat32Array())
	for r in assets.size():
		per_asset[assets[r]].append_array(rows.slice(r * ROW_STRIDE, (r + 1) * ROW_STRIDE))
	for a in asset_ids.size():
		if not per_asset[a].is_empty():
			result[String(asset_ids[a])] = per_asset[a]


## The candidates of one bucket (memoized): CANDIDATES_PER_BUCKET records of _STRIDE
## floats, all derived from the field seed and the bucket indices alone.
static func _bucket(field: Dictionary, bi: int, bj: int) -> PackedFloat64Array:
	var key := (bi + _BUCKET_OFFSET) * _BUCKET_SPAN + (bj + _BUCKET_OFFSET)
	var buckets: Dictionary = field.buckets
	var cached: Variant = buckets.get(key)
	if cached != null:
		return cached
	var per_bucket := ScatterPlan.CANDIDATES_PER_BUCKET
	var size: float = field.bucket
	var owners: PackedInt32Array = field.owners
	var cdf: PackedFloat64Array = field.cdf
	var base := _mix(_mix(field.seed ^ (bi & _MASK32)) ^ (bj & _MASK32))
	var out := PackedFloat64Array()
	out.resize(per_bucket * _STRIDE)
	for k in per_bucket:
		var h := _mix(base + (k + 1) * _SALT_CANDIDATE)
		var o := k * _STRIDE
		out[o] = (bi + _unit(h, _SALT_X)) * size
		out[o + 1] = (bj + _unit(h, _SALT_Z)) * size
		out[o + 2] = _mix(h ^ _SALT_PRIORITY)
		var owner := owners[0]
		if owners.size() > 1:
			var pick := _unit(h, _SALT_OWNER)
			owner = owners[owners.size() - 1]
			for m in cdf.size():
				if pick < cdf[m]:
					owner = owners[m]
					break
		out[o + 3] = owner
		out[o + 4] = key * per_bucket + k
		out[o + 5] = h
	buckets[key] = out
	return out


## Whether a candidate of species s becomes an instance (memoized per species).
static func _final(ctx: Dictionary, s: int, cands: PackedFloat64Array, c: int) -> bool:
	var memo: Dictionary = ctx.final[s]
	var id := int(cands[c + 4])
	var known: Variant = memo.get(id)
	if known != null:
		return known
	var result := _evaluate(ctx, ctx.plan.species[s], cands, c)
	memo[id] = result
	return result


## Cheap thinning first, each test against the running keep product with one hashed
## uniform, then spacing, then the relation and clearance queries that may evaluate other
## species. Leaves the clump edge distance in ctx.edge for the row.
static func _evaluate(
	ctx: Dictionary, entry: Dictionary, cands: PackedFloat64Array, c: int
) -> bool:
	var x: float = cands[c]
	var z: float = cands[c + 1]
	var p := Vector2(x, z)
	var bounds: Rect2 = ctx.bounds
	if not bounds.has_point(p):
		return false
	var u := _unit(int(cands[c + 5]), _SALT_ACCEPT)
	# Painted density through the size class's response (ScatterPlan.DENSITY_RESPONSE).
	var painted: float = ctx.species_density_at.call(p, entry.ground_role)
	var keep := ScatterPlan.respond(painted, entry.response_lead, entry.response_lag)
	if u >= keep:
		return false
	var s: int = entry.index
	var influence: float = entry.influence
	if influence > 0.0:
		var pattern := _pattern_value(ctx.noise[s], ctx.contrast[s], x, z)
		keep *= 1.0 - influence * (1.0 - pattern)
		if u >= keep:
			return false
	var slope_cos: float = entry.slope_cos
	if slope_cos > -1.5:
		var normal: Vector3 = ctx.normal_at.call(p)
		if normal.y < slope_cos:
			var angle := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
			keep *= clampf(1.0 - (angle - entry.slope_max) / SLOPE_FALLOFF_DEG, 0.0, 1.0)
			if u >= keep:
				return false
	if entry.clumped:
		var membership := _membership(ctx, s, x, z)
		ctx.edge = membership.y
		keep *= membership.x
		if u >= keep:
			return false
	if entry.spacing > 0.0 and not _spaced_survives(ctx.fields[entry.field], cands, c):
		return false
	for relation in entry.avoid:
		keep *= 1.0 - relation.influence * _proximity(ctx, relation, x, z)
		if u >= keep:
			return false
	if not entry.clumped:
		for relation in entry.near:
			keep *= 1.0 - relation.influence * (1.0 - _proximity(ctx, relation, x, z))
			if u >= keep:
				return false
	for field_index in entry.clearance:
		if _occupied(ctx, field_index, x, z, entry.clearance_m):
			return false
	return true


## Matern III: true unless a surviving candidate of higher priority lies within the
## field's spacing. Depth-first on an explicit stack, deciding higher-priority neighbours
## first (highest first, so a survivor is usually found in one step), memoized per field.
## Most candidates of a sparse field have no higher neighbour at all, or have one already
## decided, and return before the stack is built.
static func _spaced_survives(field: Dictionary, cands: PackedFloat64Array, c: int) -> bool:
	var memo: Dictionary = field.spaced
	var id := int(cands[c + 4])
	var known: Variant = memo.get(id)
	if known != null:
		return known
	var first := _higher_neighbours(field, cands[c], cands[c + 1], cands[c + 2], id)
	if first.is_empty():
		memo[id] = true
		return true
	if memo.get(int(first[3])) == true:
		memo[id] = false
		return false
	var ids: Array[int] = [id]
	var lists: Array[PackedFloat64Array] = [first]
	var positions := PackedInt32Array([0])
	while not ids.is_empty():
		var top := ids.size() - 1
		var list := lists[top]
		var pos := positions[top]
		var survives := true
		var pushed := false
		while pos < list.size():
			var neighbour := int(list[pos + 3])
			var decided: Variant = memo.get(neighbour)
			if decided == null:
				positions[top] = pos
				ids.append(neighbour)
				lists.append(
					_higher_neighbours(field, list[pos], list[pos + 1], list[pos + 2], neighbour)
				)
				positions.append(0)
				pushed = true
				break
			if decided:
				survives = false
				break
			pos += 4
		if pushed:
			continue
		memo[ids[top]] = survives
		ids.pop_back()
		lists.pop_back()
		positions.resize(top)
	return memo[id]


## Candidates of `field` within its spacing of (x, z) with a higher priority than
## (priority, id), as flat [x, z, priority, id] records, highest priority first.
static func _higher_neighbours(
	field: Dictionary, x: float, z: float, priority: float, id: int
) -> PackedFloat64Array:
	var spacing: float = field.spacing
	var reach := spacing * spacing
	var size: float = field.bucket
	var found := PackedFloat64Array()
	var keys := PackedInt64Array()
	for bj in range(floori((z - spacing) / size), floori((z + spacing) / size) + 1):
		for bi in range(floori((x - spacing) / size), floori((x + spacing) / size) + 1):
			var cands := _bucket(field, bi, bj)
			for c in range(0, cands.size(), _STRIDE):
				var other: float = cands[c + 2]
				if other < priority or (other == priority and int(cands[c + 4]) <= id):
					continue
				var dx: float = cands[c] - x
				var dz: float = cands[c + 1] - z
				if dx * dx + dz * dz >= reach:
					continue
				keys.append(int(other) * 1048576 + keys.size())
				found.append(cands[c])
				found.append(cands[c + 1])
				found.append(other)
				found.append(cands[c + 4])
	if keys.size() < 2:
		return found
	keys.sort()
	var ordered := PackedFloat64Array()
	ordered.resize(found.size())
	for i in keys.size():
		var from := (keys[keys.size() - 1 - i] & 0xFFFFF) * 4
		for j in 4:
			ordered[i * 4 + j] = found[from + j]
	return ordered


## Clump membership at a point: x = 0..1 (1 inside a kept parent's radius, smoothly to 0
## across the transition), y = the distance to that parent over its reach (0 at the
## centre, 1 at the outer edge), for the clump scale falloff. With additive clumps
## (ScatterPlan.additive_clumps) x is the summed membership of every clump over the point
## over ScatterPlan.CLUMP_SATURATION, capped at 1, and y the nearest centre's.
static func _membership(ctx: Dictionary, s: int, x: float, z: float) -> Vector2:
	var entry: Dictionary = ctx.plan.species[s]
	var size: float = ctx.fields[entry.field].bucket
	var parents := _parents_near_bucket(ctx, s, floori(x / size), floori(z / size))
	var transition: float = entry.rule.clump.transition_m
	var best := Vector2(0.0, 1.0)
	var additive := ScatterPlan.additive_clumps
	var total := 0.0
	for i in range(0, parents.size(), 3):
		var dx := parents[i] - x
		var dz := parents[i + 1] - z
		var radius := parents[i + 2]
		var d := sqrt(dx * dx + dz * dz)
		var inside := 1.0
		if d > radius:
			if transition <= 0.0 or d >= radius + transition:
				continue
			inside = 1.0 - smoothstep(radius, radius + transition, d)
		var edge := d / (radius + transition)
		total += inside
		if additive:
			best.y = minf(best.y, edge)
		elif inside > best.x or (inside == best.x and edge < best.y):
			best = Vector2(inside, edge)
	if additive:
		best.x = minf(1.0, total / ScatterPlan.CLUMP_SATURATION)
	return best


## Kept clump parents whose reach overlaps one children bucket, as [x, z, radius]
## records (memoized per bucket, so each child checks only the few that matter).
static func _parents_near_bucket(ctx: Dictionary, s: int, bi: int, bj: int) -> PackedFloat64Array:
	var memo: Dictionary = ctx.parent_lists[s]
	var key := (bi + _BUCKET_OFFSET) * _BUCKET_SPAN + (bj + _BUCKET_OFFSET)
	var cached: Variant = memo.get(key)
	if cached != null:
		return cached
	var entry: Dictionary = ctx.plan.species[s]
	var clump: Dictionary = entry.rule.clump
	var child_size: float = ctx.fields[entry.field].bucket
	var rect := Rect2(bi * child_size, bj * child_size, child_size, child_size)
	var size: float = ctx.fields[entry.parent_field].bucket
	var transition: float = clump.transition_m
	var reach: float = clump.radius_m * (1.0 + ScatterPlan.CLUMP_RADIUS_JITTER) + transition
	var out := PackedFloat64Array()
	var low_x := floori((rect.position.x - reach) / size)
	var high_x := floori((rect.end.x + reach) / size)
	var low_z := floori((rect.position.y - reach) / size)
	var high_z := floori((rect.end.y + reach) / size)
	# Parents sit in their own, larger buckets; a child bucket gathers the few whose reach
	# overlaps it, so each child tests two or three parents, not a neighbourhood.
	for parent_j in range(low_z, high_z + 1):
		for parent_i in range(low_x, high_x + 1):
			var kept := _kept_parents(ctx, s, parent_i, parent_j)
			for c in range(0, kept.size(), 3):
				var px := kept[c]
				var pz := kept[c + 1]
				var radius := kept[c + 2]
				var dx := maxf(0.0, maxf(rect.position.x - px, px - rect.end.x))
				var dz := maxf(0.0, maxf(rect.position.y - pz, pz - rect.end.y))
				if dx * dx + dz * dz > (radius + transition) * (radius + transition):
					continue
				out.append(px)
				out.append(pz)
				out.append(radius)
	memo[key] = out
	return out


## The kept parents of one parent bucket as [x, z, radius] records (memoized per bucket).
static func _kept_parents(ctx: Dictionary, s: int, bi: int, bj: int) -> PackedFloat64Array:
	var memo: Dictionary = ctx.parent_buckets[s]
	var key := (bi + _BUCKET_OFFSET) * _BUCKET_SPAN + (bj + _BUCKET_OFFSET)
	var cached: Variant = memo.get(key)
	if cached != null:
		return cached
	var entry: Dictionary = ctx.plan.species[s]
	var radius: float = entry.rule.clump.radius_m
	var cands := _bucket(ctx.fields[entry.parent_field], bi, bj)
	var out := PackedFloat64Array()
	for c in range(0, cands.size(), _STRIDE):
		if _parent_kept(ctx, s, cands, c):
			var jitter := 2.0 * _unit(int(cands[c + 5]), _SALT_RADIUS) - 1.0
			out.append(cands[c])
			out.append(cands[c + 1])
			out.append(radius * (1.0 + ScatterPlan.CLUMP_RADIUS_JITTER * jitter))
	memo[key] = out
	return out


## A clump parent survives its spacing and the species' near relations (Geoscatter's
## affinity acts on clump parents: a clump whose parent is near its target survives whole).
static func _parent_kept(ctx: Dictionary, s: int, cands: PackedFloat64Array, c: int) -> bool:
	var memo: Dictionary = ctx.parents[s]
	var id := int(cands[c + 4])
	var known: Variant = memo.get(id)
	if known != null:
		return known
	var entry: Dictionary = ctx.plan.species[s]
	var kept := _spaced_survives(ctx.fields[entry.parent_field], cands, c)
	if kept and not entry.near.is_empty():
		var keep := 1.0
		for relation in entry.near:
			var near := _proximity(ctx, relation, cands[c], cands[c + 1])
			keep *= 1.0 - relation.influence * (1.0 - near)
		kept = _unit(int(cands[c + 5]), _SALT_ACCEPT) < keep
	memo[id] = kept
	return kept


## How near (x, z) is to an instance of the relation's target: 1 within distance, falling
## linearly to 0 across the transition (Geoscatter's proximity with falloff).
static func _proximity(ctx: Dictionary, relation: Dictionary, x: float, z: float) -> float:
	var target: int = relation.target
	var field_index: int = ctx.plan.species[target].field
	if field_index < 0:
		return 0.0
	var field: Dictionary = ctx.fields[field_index]
	var distance: float = relation.distance
	var transition: float = relation.transition
	var reach := distance + transition
	var size: float = field.bucket
	var best := 0.0
	for bj in range(floori((z - reach) / size), floori((z + reach) / size) + 1):
		for bi in range(floori((x - reach) / size), floori((x + reach) / size) + 1):
			var cands := _bucket(field, bi, bj)
			for c in range(0, cands.size(), _STRIDE):
				if int(cands[c + 3]) != target:
					continue
				var dx: float = cands[c] - x
				var dz: float = cands[c + 1] - z
				var d2 := dx * dx + dz * dz
				if d2 >= reach * reach:
					continue
				var d := sqrt(d2)
				var near := 1.0 if d <= distance else 1.0 - (d - distance) / transition
				if near <= best or not _final(ctx, target, cands, c):
					continue
				best = near
				if best >= 1.0:
					return best
	return best


## Whether any instance of a field (any of its species) lies within `clearance` of (x, z).
static func _occupied(
	ctx: Dictionary, field_index: int, x: float, z: float, clearance: float
) -> bool:
	var field: Dictionary = ctx.fields[field_index]
	var size: float = field.bucket
	for bj in range(floori((z - clearance) / size), floori((z + clearance) / size) + 1):
		for bi in range(floori((x - clearance) / size), floori((x + clearance) / size) + 1):
			var cands := _bucket(field, bi, bj)
			for c in range(0, cands.size(), _STRIDE):
				var dx: float = cands[c] - x
				var dz: float = cands[c + 1] - z
				if dx * dx + dz * dz >= clearance * clearance:
					continue
				if _final(ctx, int(cands[c + 3]), cands, c):
					return true
	return false


## Appends one instance row and returns its asset index. Y is the ground height; upright
## species stand on +Y, normal-aligned ones on the ground normal tilted by up to
## NORMAL_TILT_MAX_RAD; yaw spans yaw_random_deg centred on zero; scale is uniform in
## 1 +- scale_spread, shrunk where the pattern is low (scale_influence) and toward clump
## edges for ground cover (`edge`, 0 at a clump centre, 1 at its rim), never below
## scale_floor.
static func _append_row(
	ctx: Dictionary,
	entry: Dictionary,
	cands: PackedFloat64Array,
	c: int,
	edge: float,
	rows: PackedFloat32Array
) -> int:
	var x: float = cands[c]
	var z: float = cands[c + 1]
	var h := int(cands[c + 5])
	var p := Vector2(x, z)
	var up := Vector3.UP
	if entry.align_normal:
		var normal: Vector3 = ctx.normal_at.call(p)
		var tilt := _unit(h, _SALT_TILT) * NORMAL_TILT_MAX_RAD
		up = _tilted(normal, tilt, _unit(h, _SALT_TILT_DIRECTION) * TAU)
	var yaw: float = (_unit(h, _SALT_YAW) - 0.5) * entry.yaw_range
	var rotation := Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, yaw)
	var scale: float = 1.0 + entry.scale_spread * (2.0 * _unit(h, _SALT_SCALE) - 1.0)
	var scale_influence: float = entry.scale_influence
	if scale_influence > 0.0:
		var s: int = entry.index
		var pattern := _pattern_value(ctx.noise[s], ctx.contrast[s], x, z)
		scale *= 1.0 - scale_influence * (1.0 - pattern)
	if entry.clump_scale:
		scale *= 1.0 - CLUMP_SCALE_SHRINK * edge
	scale = maxf(scale, entry.scale_floor)
	var asset_count: int = entry.asset_count
	var asset := mini(floori(_unit(h, _SALT_ASSET) * asset_count), asset_count - 1)
	rows.append(x)
	rows.append(ctx.height_at.call(p))
	rows.append(z)
	rows.append(rotation.x)
	rows.append(rotation.y)
	rows.append(rotation.z)
	rows.append(rotation.w)
	rows.append(scale)
	rows.append(scale)
	rows.append(scale)
	return asset


## `normal` tilted by `angle` toward the tangent direction at `azimuth`.
static func _tilted(normal: Vector3, angle: float, azimuth: float) -> Vector3:
	if angle <= 0.0:
		return normal
	var helper := Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD
	var tangent := normal.cross(helper).normalized()
	var bitangent := normal.cross(tangent)
	var axis := tangent * cos(azimuth) + bitangent * sin(azimuth)
	return normal.rotated(axis, angle).normalized()


## The terrain surface's height at continuous sample coordinates `at` (clamped to the
## grid) of the row-major `grid`, `columns` x `rows`: linear over the triangle of the quad
## the point is in, with each quad split on its (1, 0)-(0, 1) diagonal, the triangles
## (a, a+1, a+cols) and (a+1, a+cols+1, a+cols) TerrainMeshBuilder draws and Jolt's
## HeightMapShape3D collides with. So a row stands exactly on the ground the player sees
## and a token lands on.
static func triangle_height(
	grid: PackedFloat32Array, columns: int, rows: int, at: Vector2
) -> float:
	var fx := clampf(at.x, 0.0, columns - 1)
	var fz := clampf(at.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * columns + x0
	if tx + tz <= 1.0:
		return grid[i] + (grid[i + 1] - grid[i]) * tx + (grid[i + columns] - grid[i]) * tz
	var h11 := grid[i + columns + 1]
	return h11 + (grid[i + columns] - h11) * (1.0 - tx) + (grid[i + 1] - h11) * (1.0 - tz)


## The terrain's shading normal at continuous sample coordinates `at`: the vertex normals
## of the triangle triangle_height() uses (central differences on the whole grid, as
## TerrainMeshBuilder computes them), interpolated barycentrically, which is the normal
## the rendered ground is lit with. `step` is the real sample step (MapDocument
## .sample_step()). Smooth across triangles, unlike the facet normal, so slope rules and
## normal-aligned species do not flicker triangle by triangle.
static func triangle_normal(
	grid: PackedFloat32Array, columns: int, rows: int, at: Vector2, step: Vector2
) -> Vector3:
	var fx := clampf(at.x, 0.0, columns - 1)
	var fz := clampf(at.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var n10 := vertex_normal(grid, columns, rows, x0 + 1, z0, step)
	var n01 := vertex_normal(grid, columns, rows, x0, z0 + 1, step)
	var n := Vector3.ZERO
	if tx + tz <= 1.0:
		var n00 := vertex_normal(grid, columns, rows, x0, z0, step)
		n = n00 * (1.0 - tx - tz) + n10 * tx + n01 * tz
	else:
		var n11 := vertex_normal(grid, columns, rows, x0 + 1, z0 + 1, step)
		n = n11 * (tx + tz - 1.0) + n01 * (1.0 - tx) + n10 * (1.0 - tz)
	return n.normalized()


## The normal of sample (x, z): central differences on the whole grid, one-sided at the
## edge; the same arithmetic as TerrainMeshBuilder.sample_normal.
static func vertex_normal(
	grid: PackedFloat32Array, columns: int, rows: int, x: int, z: int, step: Vector2
) -> Vector3:
	var x0 := maxi(x - 1, 0)
	var x1 := mini(x + 1, columns - 1)
	var z0 := maxi(z - 1, 0)
	var z1 := mini(z + 1, rows - 1)
	var row := z * columns
	var slope_x := (grid[row + x1] - grid[row + x0]) / ((x1 - x0) * step.x)
	var slope_z := (grid[z1 * columns + x] - grid[z0 * columns + x]) / ((z1 - z0) * step.y)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()


## Bilinear sample of a row-major grid at continuous sample coordinates, clamped.
static func bilinear(grid: PackedFloat32Array, columns: int, rows: int, at: Vector2) -> float:
	var fx := clampf(at.x, 0.0, columns - 1)
	var fz := clampf(at.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * columns + x0
	var top := lerpf(grid[i], grid[i + 1], tx)
	var bottom := lerpf(grid[i + columns], grid[i + columns + 1], tx)
	return lerpf(top, bottom, tz)


## 32-bit integer hash (xorshift-multiply, both multipliers under 2^31 so the product
## stays inside a signed 64-bit int and nothing relies on overflow).
static func _mix(value: int) -> int:
	var h := value & _MASK32
	h ^= h >> 16
	h = (h * 0x7FEB352D) & _MASK32
	h ^= h >> 15
	h = (h * 0x1B873593) & _MASK32
	h ^= h >> 16
	return h


## A uniform in [0, 1) from a candidate hash and a salt.
static func _unit(h: int, salt: int) -> float:
	return _mix(h ^ salt) / 4294967296.0
