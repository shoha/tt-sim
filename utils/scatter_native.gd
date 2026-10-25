class_name ScatterNative
extends RefCounted

## The native scatter generator's one door (card native-scatter, 2026-10-20). A C++ GDExtension
## (native/, class TTScatterNative) runs ScatterGenerator's per-cell path row for row with the
## GDScript, about fifty times faster; this wrapper packs a ScatterRegen job's biome once (the
## plan as ScatterPlan.build makes it, the window's grids as document_fields and
## ScatterGround.sampler build them, each species' pattern-noise settings, the cells and the
## blockers), makes the one call, and hands back rows in generate_species_cells' form.
##
## No script names the native class: a checkout without the built library (CI's tests, a fresh
## clone, an export without it) has no such class, and an identifier would fail to parse. The
## class is found through ClassDB, and wherever it is missing every job runs in GDScript, which
## stays the reference the native rows are tested against (test_scatter_native).
##
## Fallback. A job reaches the native path only when the port covers everything it can reach;
## otherwise it runs whole in GDScript, never mixed (later species read earlier species' memos).
## The port covers every branch generation has today (painted surfaces, the path fringe, the rule
## noise on steep ground, wet dressing, crossings, rock blockers); a branch added to the GDScript
## later must be ported or refused here. fallbacks() counts jobs by outcome; force_gdscript sends
## every job back, for A/B runs and tests. Thread-safe: run_biome() is called from
## ScatterRegen.run on WorkerThreadPool tasks; the shared state is read-only after first use or
## under a mutex.

const CLASS_NAME := "TTScatterNative"
## The word version() carries once the library evaluates terrain response (S12b).
const CAPABILITY_CURVES := "curves"
## ... and the water_dist axis (S12c): its distance grid in the job's source, ScatterTerrain.
const CAPABILITY_WATER := "water"

## True: every job runs in GDScript (A/B measurements, tests of the GDScript path).
static var force_gdscript := false

static var _mutex := Mutex.new()
static var _native: Object = null
static var _consts: Dictionary = {}
static var _counts: Dictionary = {}


## Whether the native library is loaded (the class exists).
static func available() -> bool:
	return ClassDB.class_exists(CLASS_NAME)


## Whether jobs will run natively: the library is loaded and not forced off.
static func active() -> bool:
	return not force_gdscript and available()


## The loaded library's build stamp, or "" without it.
static func version() -> String:
	var native := _instance()
	return String(native.call("version")) if native != null else ""


## Jobs per outcome since the last reset: "native", and each fallback reason ("forced",
## "missing", "grids", or a reason the library gave).
static func fallbacks() -> Dictionary:
	_mutex.lock()
	var copy := _counts.duplicate()
	_mutex.unlock()
	return copy


static func reset_counts() -> void:
	_mutex.lock()
	_counts.clear()
	_mutex.unlock()


## One biome of a ScatterRegen job (`entry`: species, cells_by_species, window, built, cliff,
## blockers) on `snapshot`, natively: generate_species_cells' rows, with the mass anchors merged
## into `anchors`; or null when the job must run in GDScript (counted by reason).
static func run_biome(
	snapshot: MapDocument, biome_id: String, entry: Dictionary, anchors: Dictionary
) -> Variant:
	var species: Array[Dictionary] = []
	species.assign(entry.species)
	var reason := _refusal(species)
	if reason != "":
		_count(reason)
		return null
	var job := pack(
		snapshot,
		biome_id,
		species,
		entry.cells_by_species,
		entry.window,
		entry.get("built", PackedStringArray()),
		entry.get("cliff", PackedStringArray()),
		entry.get("blockers", PackedFloat32Array())
	)
	if job.is_empty():  # nothing painted for the biome: generation places nothing
		_count("native")
		return {}
	var out: Dictionary = _instance().call("generate", job)
	if out.has("error"):
		_count(String(out.error))
		return null
	_count("native")
	anchors.merge(out.anchors, true)
	return out.rows


## Why jobs cannot run natively ("" when they can). Every branch generation has today is ported;
## a branch added later is refused here until it is. Terrain response (a rule's slope_min_deg or
## response curves, step S12a) runs in GDScript unless the loaded library reports the "curves"
## capability in version() (S12b), and a water_dist curve (S12c) unless it reports "water"; a
## stale library, which would ignore the new plan keys, is thereby kept from placing different rows.
static func _refusal(species: Array[Dictionary] = []) -> String:
	if force_gdscript:
		return "forced"
	if _instance() == null:
		return "missing"
	if WaterDressing.CHANNELS != 4:
		return "water channels"
	if species.any(ScatterPlan.has_terrain_response) and not version().contains(CAPABILITY_CURVES):
		return "curves"
	if species.any(ScatterPlan.has_water_dist) and not version().contains(CAPABILITY_WATER):
		return "water"
	return ""


## The native job for generate_species_cells(biome_id, species, document_fields(doc, biome_id,
## window, built, cliff), cells_by_species, blockers): {} when the biome has no paint.
static func pack(
	doc: MapDocument,
	biome_id: String,
	species: Array[Dictionary],
	cells_by_species: Array,
	window: Rect2,
	built: PackedStringArray,
	cliff: PackedStringArray,
	blockers: PackedFloat32Array
) -> Dictionary:
	var source := source_for(doc, biome_id, window, built, cliff)
	if source.is_empty():
		return {}
	var plan := ScatterPlan.build(biome_id, species, doc.map_seed)
	if species.any(ScatterPlan.has_water_dist):  # the grid only for a job that reads it
		source["water_dist"] = ScatterTerrain.water_distance_grid(doc)
	var fields: Array[Dictionary] = []
	fields.assign(plan.fields)
	var noise := []
	for plan_entry: Dictionary in plan.species:
		var made := ScatterGenerator._noise(plan_entry, fields)
		if made == null:
			noise.append(null)
		else:
			noise.append(
				[made.seed, made.frequency, made.fractal_octaves, float(made.get_meta("contrast"))]
			)
	var half := doc.extent_m() * 0.5
	var job_consts := consts().duplicate()
	job_consts["additive_clumps"] = ScatterPlan.additive_clumps
	return {
		"consts": job_consts,
		"plan": plan,
		"noise": noise,
		"source": source,
		"bounds": Rect2(-half, doc.extent_m()),
		"cells_by_species": cells_by_species,
		"blockers": blockers,
	}


## What the library builds the window's grids from (card native-cover): the document's own
## arrays, shared not copied, the window's sample range and the few numbers grids_for derives
## (radii, the cliff band, each surface slot's kind), or {} when the biome has no paint. The
## library's grids equal grids_for's bit for bit (test_scatter_native); computing them there took
## a native job from 44 to about 20 ms (GDScript spent 24 ms in grids_for on the probe cell).
static func source_for(
	doc: MapDocument,
	biome_id: String,
	window: Rect2,
	built: PackedStringArray,
	cliff: PackedStringArray
) -> Dictionary:
	var count := doc.sample_count()
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var slot := doc.biome_ids.find(biome_id) + 1
	if not (slot > 0 and doc.biome_slots.size() == count and doc.biome_density.size() == count):
		return {}
	var low := Vector2i.ZERO
	var high := Vector2i(columns - 1, rows - 1)
	if window.has_area():
		low = Vector2i(doc.world_to_sample(window.position).floor()).clamp(low, high)
		high = Vector2i(doc.world_to_sample(window.end).ceil()).clamp(low, high)
	var step := doc.sample_step()
	var finest := maxf(minf(step.x, step.y), 1e-4)
	# Per surface slot what its weight counts toward (ScatterGround._painted_fields): 0 only the
	# total, 1 built, 2 rock, 3 ash.
	var kinds := PackedByteArray()
	kinds.resize(MapDocument.MAX_SURFACES)
	for s in doc.surface_ids.size():
		if built.has(doc.surface_ids[s]):
			kinds[s] = 1
		elif cliff.has(doc.surface_ids[s]):
			kinds[s] = 2
		elif doc.surface_ids[s] in ScatterGround.SCORCHED_SURFACES:
			kinds[s] = 3
	var wet := doc.water_dressing.size() == count * WaterDressing.CHANNELS
	var spans := PackedFloat64Array()
	for crossing in doc.crossings:
		spans.append_array(
			[crossing.start.x, crossing.start.y, crossing.end.x, crossing.end.y, crossing.width_m]
		)
	return {
		"columns": columns,
		"rows": rows,
		"step": step,
		"half": doc.extent_m() * 0.5,
		"seed_value": doc.map_seed & 0x7FFFFFFF,
		"slot": slot,
		"low": low,
		"high": high,
		"rect":
		Rect2i(low, high - low + Vector2i.ONE).grow(1).intersection(Rect2i(0, 0, columns, rows)),
		"biome_slots": doc.biome_slots,
		"biome_density": doc.biome_density,
		"heights": doc.heights,
		"curvature_radius": TerrainRules.radius_samples(minf(step.x, step.y)),
		"face_radius": maxi(1, roundi(ScatterGround.FACE_NEAR_RADIUS_M / finest)),
		"fringe_radius": maxi(1, roundi(ScatterGround.FRINGE_RADIUS_M / finest)),
		"start_cos": TerrainRules.cliff_start_cos(),
		"end_cos": TerrainRules.cliff_end_cos(),
		"surfaces": 1 if doc.has_surface_entries() else 0,
		"surface_weights": doc.surface_weights,
		"kinds": kinds,
		"used": doc.surface_ids.size(),
		"entries": MapDocument.SURFACE_ENTRIES,
		"channels": MapDocument.SURFACE_CHANNELS,
		"water": doc.water_dressing if wet else PackedByteArray(),
		"crossings": spans,
	}


## The library's grids for `source` (source_for's), keyed as grids_for keys them; {} without the
## library. The grid parity check's call.
static func native_grids(source: Dictionary) -> Dictionary:
	var native := _instance()
	if native == null:
		return {}
	return native.call("grids", source)


## The arrays document_fields and ScatterGround.sampler build for `window` (the same calls, so
## the same values), as whole-grid PackedFloat32Arrays, or {} when the biome has no paint. The
## GDScript reference the library's grids are tested against (native_grids).
static func grids_for(
	doc: MapDocument,
	biome_id: String,
	window: Rect2,
	built: PackedStringArray,
	cliff: PackedStringArray
) -> Dictionary:
	var count := doc.sample_count()
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var slot := doc.biome_ids.find(biome_id) + 1
	if not (slot > 0 and doc.biome_slots.size() == count and doc.biome_density.size() == count):
		return {}
	var low := Vector2i.ZERO
	var high := Vector2i(columns - 1, rows - 1)
	if window.has_area():
		low = Vector2i(doc.world_to_sample(window.position).floor()).clamp(low, high)
		high = Vector2i(doc.world_to_sample(window.end).ceil()).clamp(low, high)
	var density := PackedFloat32Array()
	density.resize(count)
	for z in range(low.y, high.y + 1):
		for i in range(z * columns + low.x, z * columns + high.x + 1):
			if doc.biome_slots[i] == slot:
				density[i] = doc.biome_density[i] / 255.0
	var heights := doc.heights
	if heights.size() != count:
		heights = PackedFloat32Array()
		heights.resize(count)
	var step := doc.sample_step()
	var rect := Rect2i(low, high - low + Vector2i.ONE).grow(1).intersection(
		Rect2i(0, 0, columns, rows)
	)
	var curvature := PackedFloat32Array()
	var steep := PackedFloat32Array()
	curvature.resize(count)
	steep.resize(count)
	TerrainRules.store_fields(
		TerrainRules.sample_fields(heights, columns, rows, step, rect), columns, curvature, steep
	)
	var paint: Dictionary = ScatterGround._painted_fields(doc, rect, built, cliff)
	var paints := not (paint.total as PackedFloat32Array).is_empty()
	# The library reads WaterDressing's field as 4 bytes per sample.
	var wet := doc.water_dressing.size() == count * WaterDressing.CHANNELS
	var spans := PackedFloat64Array()
	for crossing in doc.crossings:
		spans.append_array(
			[crossing.start.x, crossing.start.y, crossing.end.x, crossing.end.y, crossing.width_m]
		)
	return {
		"columns": columns,
		"rows": rows,
		"step": step,
		"half": doc.extent_m() * 0.5,
		"seed_value": doc.map_seed & 0x7FFFFFFF,
		"density": density,
		"heights": heights,
		"curvature": curvature,
		"steep": steep,
		"near_face": ScatterGround.face_proximity(heights, columns, rows, step, rect),
		"paint_total": paint.total,
		"paint_built": paint.built,
		"paint_rock": paint.rock,
		"paint_ash": paint.ash,
		"fringe": ScatterGround._built_fringe(doc, rect, built) if paints else PackedFloat32Array(),
		"water": doc.water_dressing if wet else PackedByteArray(),
		"crossings": spans,
	}


## The constants the port reads by name (made once, then read-only; the native loader's names).
## pack() adds ScatterPlan.additive_clumps, a static var, to its own copy.
static func consts() -> Dictionary:
	_mutex.lock()
	if _consts.is_empty():
		_consts = _make_consts()
	var made := _consts
	_mutex.unlock()
	return made


static func _make_consts() -> Dictionary:
	var made := {
		"candidates_per_bucket": ScatterPlan.CANDIDATES_PER_BUCKET,
		"clump_saturation": ScatterPlan.CLUMP_SATURATION,
		"row_step": MapDocumentIO.ROW_STEP,
		"anchor_step": MapAnchorsIO.STEP,
		"tile_m": ScatterClumps.TILE_M,
		"tile_min_buckets": ScatterClumps.TILE_MIN_BUCKETS,
		"footing_directions": GroundSnap.FOOTING_DIRECTIONS,
		"footing_sag_m": GroundSnap.FOOTING_SAG_M,
		"footing_slope_tan": GroundSnap.FOOTING_SLOPE_TAN,
		"bound_slack": GroundZones.ZONE_BOUND_SLACK,
		"flow_step": GroundZones.ZONE_FLOW_STEP_M,
		"lattice": GroundAccents._lattice(),
		"noise_cells": GroundAccents.NOISE_CELLS,
		"accent_edge": GroundAccents.EDGE,
		"detail": GroundAccents.DETAIL,
		"detail_scale": GroundAccents.DETAIL_SCALE,
		"fine": GroundAccents.FINE,
		"fine_scale": GroundAccents.FINE_SCALE,
		"detail_offset": GroundAccents.DETAIL_OFFSET,
		"fine_offset": GroundAccents.FINE_OFFSET,
		"rotation": GroundAccents.ROTATION,
		"inv_uint_max": TerrainRules.INV_UINT_MAX,
		"cliff_start_cos": TerrainRules.cliff_start_cos(),
		"cliff_end_cos": TerrainRules.cliff_end_cos(),
	}
	var rules := _constants(TerrainRules)
	for name in [
		"CLIFF_EDGE_NOISE",
		"LIP_CURVATURE_START",
		"LIP_CURVATURE_END",
		"LIP_STRENGTH",
		"LIP_SHEER_TAIL",
		"RAMP_LOW",
		"RAMP_HIGH",
		"SCREE_CURVATURE_START",
		"SCREE_CURVATURE_END",
		"SCREE_NEAR_START",
		"SCREE_NEAR_END",
		"SCREE_EDGE_NOISE",
		"SCREE_BREAKUP_SCALE_M",
		"SCREE_FAN",
		"SCREE_BREAKUP_LOW",
		"SCREE_BREAKUP_HIGH",
		"RULE_NOISE_SCALE_M",
		"RULE_NOISE_SHEAR",
		"PAINT_EDGE_WARP_M",
		"PAINT_EDGE_SCALE_M",
		"PAINT_EDGE_NOISE",
		"PAINT_CLIFF_YIELD",
		"PAINT_WATER_YIELD",
		"PAINT_FORD_START_M",
		"PAINT_FORD_END_M",
		"CLIFF_NOISE_OFFSET",
		"SCREE_NOISE_OFFSET",
		"SCREE_BREAKUP_OFFSET",
		"PAINT_WARP_OFFSET_A",
		"PAINT_WARP_OFFSET_B",
		"PAINT_NOISE_OFFSET"
	]:
		made[String(name).to_lower()] = rules[name]
	var ground := _constants(ScatterGround)
	for name in [
		"ROLE_COVER",
		"ROLE_ROCK",
		"ROLE_TREE",
		"ROLE_SHRUB",
		"ROLE_TALL_COVER",
		"ROLE_BITS",
		"EDGE_BANK",
		"EDGE_EMERGENT",
		"FLOWER_BIT",
		"CHARRED_BIT",
		"SCREE_THIN",
		"SCREE_ROCK_BOOST",
		"FLOWER_VERGE_FILL",
		"FLOWER_VERGE_GATHER",
		"EDGE_BOOST",
		"PAVED_CLEAR_START",
		"PAVED_CLEAR_FULL",
		"TREE_FACE_START",
		"TREE_FACE_FULL",
		"SHRUB_FACE_START",
		"SHRUB_FACE_FULL",
		"FRINGE_START",
		"FRINGE_FULL",
		"ARID_BIT",
		"WET_CLEAR_START",
		"WET_CLEAR_FULL",
		"EMERGENT_DEPTH_START_M",
		"EMERGENT_DEPTH_FULL_M",
		"TREE_SHORE_START",
		"TREE_SHORE_FULL",
		"SHRUB_SHORE_START",
		"SHRUB_SHORE_FULL",
		"SHRUB_SHORE_KEEP",
		"TALL_SHORE_START",
		"TALL_SHORE_FULL",
		"FLOWER_SHORE_THIN",
		"ARID_SHORE_START",
		"ARID_SHORE_FULL"
	]:
		made[String(name).to_lower()] = ground[name]
	var crossing := _constants(CrossingGeometry)
	for name in [
		"CLEAR_MARGIN_M", "CLEAR_ANCHOR_M", "CLEAR_SOFT_M", "CLEAR_TREE_M", "CLEAR_SHRUB_M"
	]:
		made[String(name).to_lower()] = crossing[name]
	made["depth_scale"] = WaterDressing.DEPTH_SCALE
	made["water_dist_max_m"] = ScatterTerrain.WATER_DIST_MAX_M
	return made


static func _constants(script: Script) -> Dictionary:
	return script.get_script_constant_map()


## The pattern noise as the library computes it, at each (x, z) pair of `xz`: the noise parity
## check's call. Empty without the library.
static func noise_2d(
	seed_value: int, frequency: float, octaves: int, xz: PackedFloat64Array
) -> PackedFloat32Array:
	var native := _instance()
	if native == null:
		return PackedFloat32Array()
	return native.call("noise_2d", seed_value, frequency, octaves, xz)


static func _instance() -> Object:
	_mutex.lock()
	if _native == null and ClassDB.class_exists(CLASS_NAME):
		_native = ClassDB.instantiate(CLASS_NAME)
	var native := _native
	_mutex.unlock()
	return native


static func _count(reason: String) -> void:
	_mutex.lock()
	_counts[reason] = int(_counts.get(reason, 0)) + 1
	_mutex.unlock()
