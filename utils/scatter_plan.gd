class_name ScatterPlan
extends RefCounted

## How ScatterGenerator samples one biome: per species, the candidate field it draws from
## and how dense that field must be for the delivered density to land on the palette
## target (docs/ASSET_PIPELINE.md section 9: rules are targets, never Geoscatter's
## compensated requests). Pure data built by pure statics; ScatterGenerator evaluates it.
##
## Delivered density = packed density * expected keep. Packing is Matern III on a field
## of CANDIDATES_PER_BUCKET hashed candidates per bucket, sized by inverting a measured
## packing curve (PACKING_TIMES). The keep is the product of every thinning applied after
## spacing, each modelled the way treecube models it for Geoscatter (pattern_keep,
## relation_keep, clump coverage), plus the clearance smaller classes keep around larger
## ones. Where a model is measured rather than derived, the measurement is next to it.

## Size classes in generation order; relations and clearance only look backwards.
const SIZE_CLASSES := ["large", "medium", "small", "ground"]
const CANDIDATES_PER_BUCKET := 4
## Packing time cap (candidate intensity times pi (r/2)^2, see PACKING_TIMES). At 12 a
## packing reaches 0.486 of the 0.547 jamming coverage; going further costs candidates
## (and survival recursion) roughly in proportion for a few percent more density. Only a
## species asking for more than 0.486 coverage is affected, and build() reports it.
const MAX_PACKING_TIME := 12.0
## Each clump's radius varies by +-this share around radius_m, so clumps are not all one
## size (Geoscatter's clump random factor; its exact semantics are not documented, this
## is a mean-preserving stand-in).
const CLUMP_RADIUS_JITTER := 0.25
## Clump parents keep this share of the radius apart (treecube: radius * 0.5, so clumps
## read as separate tufts without culling a fifth of the parents).
const CLUMP_PARENT_SPACING := 0.5
## Clump coverage is modelled as 1 - exp(-gain * x), x = parents * disc area. Poisson
## parents would be gain 1; spaced, four-per-bucket parents overlap less and cover more,
## the more so the more they crowd. Measured 2026-09-26 on temperate_forest (membership
## averaged on a 0.25 m grid over 60 x 60 m): gain 1.09 to 1.14 at x = 0.4 to 0.5 (sparse
## stone and fern clumps), 1.33 to 1.39 at x = 2.1 to 2.7 (dense ground cover); the line
## gain = BASE + SLOPE * x runs through both ends.
const CLUMP_COVERAGE_GAIN_BASE := 1.05
const CLUMP_COVERAGE_GAIN_SLOPE := 0.1
## Additive clumps (see additive_clumps): a child's keep is the summed membership of every
## clump over it divided by this, capped at 1, so up to this many overlapping clumps add
## density the way Geoscatter's per-parent children do.
const CLUMP_SATURATION := 3.0
## Grass masses (contract: docs/ASSET_PIPELINE.md section 9, "Species clump, mass fields";
## ScatterMass). Optional clump fields, read only with `mass` 1, so every other rule plans and
## places exactly as before. PaletteLibrary keeps a field only when given, clamped to its range
## here ([low, high]); an absent one takes its contract default:
##   mass             1: the clumps are masses: a child keeps the union of the clumps over it
##                    (never the additive sum) and carries its clump parent, the mass anchor.
##   stretch          >= 1: each clump an ellipse of the same area, stretch times longer than wide.
##   angle_deg        the long axis' direction in world XZ (degrees from +X toward +Z), and
##   angle_jitter_deg each parent's own turn from it, uniform in +-this.
##   edge_shrink      the scale lost at the clump rim (ScatterGenerator.CLUMP_SCALE_SHRINK).
##   radius_jitter    each parent's radius spread (CLUMP_RADIUS_JITTER).
##   core_scale       a tuft's width at the clump centre, times its own scale, easing to 1 at the
##                    rim as 1 - edge^2 (ScatterMass.append_scale); core_height its height there
##                    (core_scale when absent); core_height_m caps a grown tuft's height in
##                    metres (0: no cap); core_hold holds the core's growth out to this share of
##                    the reach (ScatterMass.held_edge).
##   follow           1: each parent's long axis runs along the nearest zone edge's contour
##                    (GroundZones.zone_flow; needs the biome's ground_look).
##   parent_group     > 0: the rules of one group share their parents (a field named for the
##                    group, not the species); they agree on the swathe fields.
##   parent_spacing_m the parents' own spacing when larger than CLUMP_PARENT_SPACING of the radius.
##   bare             > 0: the biome's grass keeps off its ground-accent openings, fading out over
##                    this many accent-noise units (ScatterMass.bare_keep).
##   shoulder_m       > 0: a child stands back this far from where its ground thins.
##   zone_core, zone_share, zone_fill and the arrays zone_keep and zone_family: whole swathes
##                    dropped by the drawn zones (ScatterMass.zone_kept, zone_share_keep, filled).
const MASS_FIELDS := {
	"mass": [0.0, 1.0],
	"stretch": [1.0, 1000.0],
	"angle_deg": [-360.0, 360.0],
	"angle_jitter_deg": [0.0, 180.0],
	"edge_shrink": [0.0, 1.0],
	"radius_jitter": [0.0, 0.9],
	"core_scale": [1.0, 1000.0],
	"core_height": [0.0001, 1000.0],
	"core_height_m": [0.0, 1000.0],
	"core_hold": [0.0, 0.95],
	"follow": [0.0, 1.0],
	"parent_group": [0.0, 1000000.0],
	"parent_spacing_m": [0.0, 1000.0],
	"bare": [0.0, 1000.0],
	"shoulder_m": [0.0, 1000.0],
	"zone_core": [0.0, 1.0],
	"zone_share": [0.0, 1.0],
	"zone_fill": [0.0, 1.0],
}
## The four-element mass fields and their ranges: zone_keep (the share of parents kept in each
## zone) and zone_family (each zone's family; integers).
const MASS_ARRAYS := {"zone_keep": [0.0, 1.0], "zone_family": [0.0, 3.0]}
## Spaced parents overlap more evenly than Poisson ones, so fewer points see no clump and
## the mean keep runs above the Poisson estimate by up to this share (additive_coverage).
## Measured 2026-09-26 with the calibration test: without it, dense ground cover delivered
## 1.04x (x = 1) to 1.15x (x = 2.5) its target, where x is the mean overlap count.
const ADDITIVE_REGULARITY_GAIN := 0.12
## Degrees added to every species' slope_max_deg (P3-7). The palette's limits are
## Geoscatter's (trees 35, shrubs 40, ground cover 50, each fading out over 10 more), made
## for Blender terrains with no rock rule; ScatterGenerator only runs on in-game documents,
## where TerrainRules already turns steep ground to rock and ScatterGround keeps plants off
## it. On top of that the raw limits stripped the trees and shrubs off a hill raised with the
## Raise brush (35 to 47 degree flanks), leaving a bare mound in a forest. With 10 more,
## trees stand to 45 degrees and thin out by 55, and the rock rule (44..58) takes over.
const SLOPE_ALLOWANCE_DEG := 10.0
## A spaced random species keeps this share of its own spacing clear of every larger
## class's spaced instances (a bush 1 m from a tree trunk, a log 0.4 m from a boulder), so
## smaller classes respect larger ones and a boulder never swallows a trunk.
const CLEARANCE_FRACTION := 0.5
## How each size class answers the painted density d (0..1) before it thins its candidates
## (density_response()). Trees and shrubs lead: 1 - (1 - d)^lead, so a quick pass of the
## brush, which paints well under full density toward the edges of its stroke, already
## stands most of the trees a full paint would (a woodland, not a lawn with a tree in it);
## ground cover lags: d^lag, so the open cover of a light pass is open under the trees too.
## Both are 1 at d = 1, so a fully painted area delivers exactly the palette targets the
## calibration tests assert, and both are 0 at d = 0. Thinning takes the understory before
## the trees for the same reason (Clear still removes everything).
const DENSITY_RESPONSE := {
	"large": {"lead": 3.0, "lag": 1.0},
	"medium": {"lead": 2.5, "lag": 1.0},
	"small": {"lead": 1.0, "lag": 1.0},
	"ground": {"lead": 1.0, "lag": 1.6},
}
## A species rule's fields and their neutral defaults (PaletteLibrary fills the same ones
## when it validates the palette; tests may pass partial rules). `avoid_bare` > 0 keeps the
## species itself off the biome's ground-accent openings, fading in over that many accent-noise
## units (_plan_masses; clump `bare` does the same for a biome's whole grass).
const RULE_DEFAULTS := {
	"key": "",
	"kind": "",
	"size_class": "",
	"density_per_m2": 0.0,
	"min_spacing_m": 0.0,
	"slope_max_deg": 90.0,
	"slope_min_deg": 0.0,
	"response": {},
	"scale_spread": 0.0,
	"scale_floor": null,
	"yaw_random_deg": 360.0,
	"align": "upright",
	"pattern": null,
	"clump": null,
	"near": [],
	"avoid": [],
	"avoid_bare": 0.0,
	"assets": [],
}

## The response axes ScatterGenerator evaluates (a rule's `response`, steps S12a and S12c).
const RESPONSE_EVALUATED: Array[String] = ["slope", "height", "wet", "water_dist"]

## Matern III coverage curve for spacing r: packing time t = candidate intensity times
## pi (r/2)^2 against coverage theta = survivor density times pi (r/2)^2. Measured
## 2026-09-26 by simulation (Poisson candidates on a periodic 40 r square, mean of three
## seeds); jamming is 0.547. Four-per-bucket candidates are more even than Poisson (a
## candidate's own bucket holds three others, not four on average), which _packing()
## corrects for.
const PACKING_TIMES := [
	0.0,
	0.02,
	0.05,
	0.1,
	0.15,
	0.2,
	0.25,
	0.3,
	0.4,
	0.5,
	0.75,
	1.0,
	1.5,
	2.0,
	3.0,
	4.0,
	6.0,
	8.0,
	10.0,
	12.0,
	16.0,
]
const PACKING_COVERAGE := [
	0.0,
	0.0195,
	0.0448,
	0.0800,
	0.1126,
	0.1401,
	0.1620,
	0.1808,
	0.2142,
	0.2405,
	0.2906,
	0.3251,
	0.3644,
	0.3899,
	0.4174,
	0.4380,
	0.4578,
	0.4711,
	0.4784,
	0.4860,
	0.4938,
]

const _MASK32 := 0xFFFFFFFF

## Clumps add up where they overlap (a child keeps min(1, summed membership /
## CLUMP_SATURATION)) instead of the union of clump discs keeping everything they cover.
## The union made dense ground cover such as alpine flowers (0.35 parents per m2 of 1.2 m
## clumps cover about 97 % of the ground) an even speckle; summed overlaps vary from one
## clump to four or five, which reads as drifts. A static switch so a probe can render both
## in one run; the generator reads it on worker threads, so change it only between jobs.
static var additive_clumps: bool = true


## The plan for one biome: {"species": [...], "fields": [...]}. Each species entry carries
## its normalized rule, the field it draws from (-1 when it places nothing), its resolved
## relations, the expected keep of all its thinning, flattened per-candidate constants,
## and "reachable", the share of its target the packing cap allows (1.0 unless the target
## is denser than MAX_PACKING_TIME can pack). Each field carries its hashed seed,
## candidate intensity, bucket size, spacing and owner species with their shares.
static func build(biome_id: String, species: Array[Dictionary], map_seed: int) -> Dictionary:
	var rules: Array[Dictionary] = []
	var index_of := {}
	for i in species.size():
		var rule := RULE_DEFAULTS.duplicate()
		rule.merge(species[i], true)
		rules.append(rule)
		index_of[rule.key] = i
	var entries: Array[Dictionary] = []
	for i in rules.size():
		entries.append(_plan_species(rules, i, index_of))
	_plan_clearance(entries)
	var fields: Array[Dictionary] = []
	_plan_groups(biome_id, map_seed, entries, fields)
	_plan_masses(biome_id, map_seed, entries)
	for entry in entries:
		if entry.clumped:
			_plan_clump_fields(biome_id, map_seed, entry, fields)
	_plan_clearance_fields(entries)
	for entry in entries:
		for relation in entry.near + entry.avoid:
			entries[relation.target].referenced = true
		for field_index in entry.clearance:
			for owner in fields[field_index].owners:
				entries[owner].referenced = true
	return {"species": entries, "fields": fields}


## Packing time for a target coverage theta (inverse of PACKING_COVERAGE, linear between
## samples), capped at MAX_PACKING_TIME.
static func packing_time(theta: float) -> float:
	if theta <= 0.0:
		return 0.0
	for i in range(1, PACKING_TIMES.size()):
		if PACKING_COVERAGE[i] >= theta:
			var span: float = PACKING_COVERAGE[i] - PACKING_COVERAGE[i - 1]
			var t: float = (theta - PACKING_COVERAGE[i - 1]) / span
			return minf(lerpf(PACKING_TIMES[i - 1], PACKING_TIMES[i], t), MAX_PACKING_TIME)
	return MAX_PACKING_TIME


## Coverage a packing reaches at time t (PACKING_COVERAGE interpolated).
static func packing_coverage(t: float) -> float:
	for i in range(1, PACKING_TIMES.size()):
		if PACKING_TIMES[i] >= t:
			var span: float = PACKING_TIMES[i] - PACKING_TIMES[i - 1]
			return lerpf(
				PACKING_COVERAGE[i - 1], PACKING_COVERAGE[i], (t - PACKING_TIMES[i - 1]) / span
			)
	return PACKING_COVERAGE[PACKING_COVERAGE.size() - 1]


## The keep a painted density `density` (0..1) gives a species of `size_class` (see
## DENSITY_RESPONSE; an unknown class answers linearly). Pure.
static func density_response(density: float, size_class: String) -> float:
	var shape: Dictionary = DENSITY_RESPONSE.get(size_class, {})
	return respond(density, float(shape.get("lead", 1.0)), float(shape.get("lag", 1.0)))


## density_response() with the shape already looked up (ScatterGenerator's per-candidate
## path reads the entry's response_lead / response_lag).
static func respond(density: float, lead: float, lag: float) -> float:
	var d := clampf(density, 0.0, 1.0)
	if lead != 1.0:
		d = 1.0 - pow(1.0 - d, lead)
	if lag != 1.0:
		d = pow(d, lag)
	return d


## A response curve ([[x, y], ...], as the validated rule carries it) flattened to
## [x0, y0, x1, y1, ...] for curve_value(); empty for no curve (or fewer than two points).
static func flatten_curve(points: Variant) -> PackedFloat64Array:
	var flat := PackedFloat64Array()
	if not points is Array or (points as Array).size() < 2:
		return flat
	for point: Array in points as Array:
		flat.append(float(point[0]))
		flat.append(float(point[1]))
	return flat


## A flattened response curve at `x`: piecewise linear between its points, held at the first
## and last y beyond its ends, clamped to 0..1; 1 for an empty curve. The one definition the
## generator uses (and the native port must repeat expression for expression).
static func curve_value(points: PackedFloat64Array, x: float) -> float:
	var n := points.size()
	if n < 4:
		return 1.0
	if x <= points[0]:
		return clampf(points[1], 0.0, 1.0)
	if x >= points[n - 2]:
		return clampf(points[n - 1], 0.0, 1.0)
	var i := 2
	while points[i] < x:
		i += 2
	var x0 := points[i - 2]
	var y0 := points[i - 1]
	var y1 := points[i + 1]
	return clampf(y0 + (y1 - y0) * ((x - x0) / (points[i] - x0)), 0.0, 1.0)


## Whether a rule carries terrain response the generator evaluates: a slope minimum or a curve
## on an axis in RESPONSE_EVALUATED.
static func has_terrain_response(rule: Dictionary) -> bool:
	if float(rule.get("slope_min_deg", 0.0)) > 0.0:
		return true
	var response: Variant = rule.get("response")
	if not response is Dictionary:
		return false
	for axis: String in RESPONSE_EVALUATED:
		if (response as Dictionary).get(axis) is Array:
			return true
	return false


## Whether a rule carries a water_dist curve (the axis that needs the distance grid).
static func has_water_dist(rule: Dictionary) -> bool:
	var response: Variant = rule.get("response")
	return response is Dictionary and (response as Dictionary).get("water_dist") is Array


## Whether a rule asks for clumps (a clump block with parents and a radius).
static func is_clumped(rule: Dictionary) -> bool:
	var clump: Variant = rule.clump
	return (
		clump is Dictionary
		and clump.get("parents_per_m2", 0.0) > 0.0
		and clump.get("radius_m", 0.0) > 0.0
	)


static func _plan_species(species: Array[Dictionary], i: int, index_of: Dictionary) -> Dictionary:
	var rule: Dictionary = species[i]
	var placeable: bool = rule.density_per_m2 > 0.0 and not rule.assets.is_empty()
	var clumped: bool = placeable and is_clumped(rule)
	var clump: Variant = rule.clump
	if clumped:
		clump = {"transition_m": 0.0, "children_spacing_m": 0.0}.merged(clump, true)
		rule.clump = clump
	var mass: Dictionary = _mass_of(rule, clump if clumped else {})
	var spacing: float = rule.min_spacing_m
	if clumped and clump.children_spacing_m > 0.0:
		spacing = clump.children_spacing_m
	var keep := 1.0
	var pattern: Variant = rule.pattern
	if pattern is Dictionary:
		pattern = {"influence": 0.0, "scale_influence": 0.0}.merged(pattern, true)
		# Symmetric noise has mean 0.5, so the pattern keeps 1 - influence / 2 on average
		# (treecube's measured pattern_keep: half at full influence).
		keep *= 1.0 - 0.5 * pattern.influence
	var near := _relations(rule.near, i, index_of, species)
	var avoid := _relations(rule.avoid, i, index_of, species)
	var parent_keep := 1.0
	for relation in near:
		# treecube relation_keep: affinity removes `influence` of what lies outside reach.
		var covered := _relation_covered(relation)
		var near_keep: float = covered + (1.0 - covered) * (1.0 - relation.influence)
		if clumped:
			parent_keep *= near_keep
		else:
			keep *= near_keep
	for relation in avoid:
		keep *= 1.0 - _relation_covered(relation) * relation.influence
	if clumped:
		keep *= _clump_coverage(clump, parent_keep)
	var slope_max: float = minf(rule.slope_max_deg + SLOPE_ALLOWANCE_DEG, 90.0)
	var scale_floor: Variant = rule.scale_floor
	var response: Dictionary = DENSITY_RESPONSE.get(rule.size_class, {})
	var terrain := _plan_terrain(rule)
	return (
		{
			"key": rule.key,
			"index": i,
			"rule": rule,
			"rank": maxi(0, SIZE_CLASSES.find(rule.size_class)),
			"placeable": placeable,
			"clumped": clumped,
			"spacing": spacing,
			"pattern": pattern if pattern is Dictionary else null,
			"near": near,
			"avoid": avoid,
			"keep": maxf(keep, 0.01),
			"field": -1,
			"parent_field": -1,
			"clearance": [],
			"clearance_m": 0.0,
			"reachable": 1.0,
			"referenced": false,
			# Flattened for ScatterGenerator's per-candidate path.
			"slope_max": slope_max,
			"slope_cos": cos(deg_to_rad(slope_max)) if slope_max < 90.0 else -2.0,
			"influence": pattern.influence if pattern is Dictionary else 0.0,
			"scale_influence": pattern.scale_influence if pattern is Dictionary else 0.0,
			"align_normal": rule.align == "normal",
			"ground_role": ScatterGround.plan_role(rule),
			"footing_m": GroundSnap.footing_radius(rule),
			"yaw_range": deg_to_rad(rule.yaw_random_deg),
			"scale_spread": float(rule.scale_spread),
			"scale_floor": float(scale_floor) if scale_floor != null else -1.0,
			"clump_scale": clumped and rule.size_class == "ground",
			"asset_count": rule.assets.size(),
			"response_lead": float(response.get("lead", 1.0)),
			"response_lag": float(response.get("lag", 1.0)),
		}
		. merged(terrain)
		. merged(mass)
	)


## A rule's terrain response, flattened for the per-candidate path (S12a): `slope_min` degrees and
## its cosine (-2 = off), the curves as [x0, y0, x1, y1, ...] arrays (empty = none), and
## `has_response`, whether any of it is evaluated. A rule without the fields gets the neutral
## values, so a legacy plan runs exactly the arithmetic it always did. The water_dist curve reads
## the distance grid (ScatterTerrain.water_distance_grid, S12c).
static func _plan_terrain(rule: Dictionary) -> Dictionary:
	var slope_min := clampf(float(rule.get("slope_min_deg", 0.0)), 0.0, 90.0)
	var curves: Dictionary = rule.response if rule.get("response") is Dictionary else {}
	return {
		"slope_min": slope_min,
		"slope_min_cos": cos(deg_to_rad(slope_min)) if slope_min > 0.0 else -2.0,
		"curve_slope": flatten_curve(curves.get("slope")),
		"curve_height": flatten_curve(curves.get("height")),
		"curve_wet": flatten_curve(curves.get("wet")),
		"curve_water_dist": flatten_curve(curves.get("water_dist")),
		"has_response": has_terrain_response(rule),
	}


## A rule's mass entries (ScatterMass reads them; MASS_FIELDS has the fields): with clump `mass`
## 1, its stretch, core growth, follow, zone rule, radius jitter and edge shrink; otherwise the
## values every other rule plans with (mass_bare and mass_zones are set by _plan_masses).
static func _mass_of(rule: Dictionary, clump: Dictionary) -> Dictionary:
	var out := {
		"mass": false,
		"mass_stretch": 1.0,
		"mass_core": 1.0,
		"mass_core_y": 1.0,
		"mass_core_y_max": 0.0,
		"mass_core_hold": 0.0,
		"mass_follow": false,
		"mass_zone": {},
		"mass_zones": {},
		"mass_bare": [],
		"clump_jitter": CLUMP_RADIUS_JITTER,
		"clump_shrink": ScatterGenerator.CLUMP_SCALE_SHRINK,
	}
	if float(clump.get("mass", 0.0)) < 0.5:
		return out
	var core := maxf(1.0, float(clump.get("core_scale", 1.0)))
	# The height cap as a height scale over the rule's tallest ungrown asset (0 = none).
	var cap_m := float(clump.get("core_height_m", 0.0))
	var tallest := float(rule.get("base_height_m", rule.get("height_m", 0.0)))
	out.mass = true
	out.mass_stretch = maxf(1.0, float(clump.get("stretch", 1.0)))
	out.mass_core = core
	out.mass_core_y = maxf(float(clump.get("core_height", core)), 0.1)
	out.mass_core_y_max = cap_m / tallest if cap_m > 0.0 and tallest > 0.0 else 0.0
	out.mass_core_hold = clampf(float(clump.get("core_hold", 0.0)), 0.0, 0.95)
	out.mass_follow = float(clump.get("follow", 0.0)) > 0.0
	out.mass_zone = ScatterMass.zone_rule(clump)
	out.clump_jitter = float(clump.get("radius_jitter", CLUMP_RADIUS_JITTER))
	out.clump_shrink = float(clump.get("edge_shrink", ScatterGenerator.CLUMP_SCALE_SHRINK))
	return out


## Gives every mass entry the biome's zone record (GroundZones.record of its ground_look on
## `map_seed`, shared read-only) and, when a mass rule sets clump `bare`, every grass entry the
## biome's bare openings (ScatterMass.bare_params with the largest `bare`), so no lone tuft
## stands in a clearing. An entry whose rule sets `avoid_bare` gets openings of its own whatever
## its kind (a bromeliad kept off the wetland's mud while the reeds and sedge, which belong there,
## stay): zero from the edge the shader draws (the look's accent edge_scale) and fading in over
## `avoid_bare`, after the clump's openings when a grass entry has both. Nothing for a biome
## without a mass rule or an `avoid_bare`, so every other plan is exactly as before.
static func _plan_masses(biome_id: String, map_seed: int, entries: Array[Dictionary]) -> void:
	var avoiding := entries.any(func(entry: Dictionary) -> bool: return _avoid_bare(entry) > 0.0)
	if not avoiding and not entries.any(func(entry: Dictionary) -> bool: return entry.mass):
		return
	var look := GroundLook.for_biome(biome_id)
	var zones := GroundZones.record(look, map_seed)
	var bare := 0.0
	for entry in entries:
		if entry.mass:
			entry.mass_zones = zones
			bare = maxf(bare, float(entry.rule.clump.get("bare", 0.0)))
	var records := ScatterMass.bare_params(biome_id, map_seed, bare, zones) if bare > 0.0 else []
	var edge_scale := float(look.get("accent_shape", {}).get("edge_scale", 1.0))
	for entry in entries:
		if bare > 0.0 and entry.rule.kind == ScatterGround.GRASS_KIND:
			entry.mass_bare = records
		var own := _avoid_bare(entry)
		if own > 0.0:
			var drawn := ScatterMass.bare_params(biome_id, map_seed, own, zones, edge_scale)
			entry.mass_bare = entry.mass_bare + drawn


## An entry's own bare margin (its rule's `avoid_bare`; 0 for a partial test rule without one).
static func _avoid_bare(entry: Dictionary) -> float:
	return float(entry.rule.get("avoid_bare", 0.0))


## Expected share of the ground inside a clump. Clumps are a union of discs of radius
## radius_m (+- CLUMP_RADIUS_JITTER) plus a smoothstep falloff across transition_m, which
## counts for about half its width; near relations thin the parents by `parent_keep`.
static func _clump_coverage(clump: Dictionary, parent_keep: float) -> float:
	var radius: float = clump.radius_m
	var reach: float = radius + clump.transition_m * 0.5
	var disc := PI * (reach * reach + pow(CLUMP_RADIUS_JITTER * radius, 2.0) / 3.0)
	var x: float = clump.parents_per_m2 * parent_keep * disc
	if additive_clumps and float(clump.get("mass", 0.0)) < 0.5:
		return additive_coverage(x)
	return 1.0 - exp(-(CLUMP_COVERAGE_GAIN_BASE + CLUMP_COVERAGE_GAIN_SLOPE * x) * x)


## Mean keep of additive clumps whose discs overlap a point `x` times on average:
## E[min(1, n / CLUMP_SATURATION)] with n Poisson(x), raised by ADDITIVE_REGULARITY_GAIN
## as the overlaps grow (spaced parents vary less than Poisson ones), at most 1.
static func additive_coverage(x: float) -> float:
	var gain := 1.0 + ADDITIVE_REGULARITY_GAIN * (1.0 - exp(-x))
	return minf(1.0, _poisson_saturated_mean(x) * gain)


static func _poisson_saturated_mean(x: float) -> float:
	var mean := 0.0
	var p := exp(-x)
	var below := 0.0
	var n := 0
	while float(n) < CLUMP_SATURATION:
		mean += p * float(n) / CLUMP_SATURATION
		below += p
		n += 1
		p *= x / float(n)
	return mean + (1.0 - below)


## Relations resolved to earlier species (large -> ground), with the target's density for
## the keep model. Forward and self references are dropped, as treecube drops them.
static func _relations(
	raw: Array, i: int, index_of: Dictionary, species: Array[Dictionary]
) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	for raw_relation in raw:
		var target: int = index_of.get(raw_relation.get("species", ""), -1)
		if target < 0 or target >= i or species[target].assets.is_empty():
			continue
		var relation := {"distance_m": 0.0, "transition_m": 0.0, "influence": 1.0}.merged(
			raw_relation, true
		)
		# Two random species of one size class share a spacing field (_plan_groups), so
		# the target can never lie inside that spacing: the relation only acts beyond it.
		var shared := 0.0
		var own: Dictionary = species[i]
		var other: Dictionary = species[target]
		if not is_clumped(own) and not is_clumped(other):
			if own.size_class == other.size_class and own.min_spacing_m > 0.0:
				if other.min_spacing_m > 0.0:
					shared = maxf(own.min_spacing_m, other.min_spacing_m)
		(
			resolved
			. append(
				{
					"target": target,
					"distance": float(relation.distance_m),
					"transition": float(relation.transition_m),
					"influence": float(relation.influence),
					"target_density": float(other.density_per_m2),
					"shared_spacing": shared,
				}
			)
		)
	return resolved


## Share of the ground a relation's proximity covers (Poisson coverage of the target out
## to distance plus half the transition, which treecube measured the falloff counts for),
## minus the disc the shared spacing already keeps empty.
static func _relation_covered(relation: Dictionary) -> float:
	var reach: float = relation.distance + relation.transition * 0.5
	var free: float = maxf(0.0, reach * reach - pow(relation.shared_spacing, 2.0))
	return 1.0 - exp(-relation.target_density * PI * free)


## Spaced random species keep clear of every larger class's spaced random species, and
## the cleared share goes into the expected keep before intensities are sized: a
## clearance under half the larger class's spacing gives discs that never overlap, so
## the cleared share is exactly density * pi * clearance^2. `entry.clearance` lists the
## larger species here; _plan_clearance_fields() turns it into their fields once planned.
static func _plan_clearance(entries: Array[Dictionary]) -> void:
	for entry in entries:
		if not _is_spaced_random(entry):
			continue
		var clearance: float = entry.spacing * CLEARANCE_FRACTION
		var occupied := 0.0
		for other in entries:
			if _is_spaced_random(other) and other.rank < entry.rank:
				entry.clearance.append(other.index)
				occupied += other.rule.density_per_m2 * PI * clearance * clearance
		entry.clearance_m = clearance
		entry.keep *= 1.0 - minf(occupied, 0.9)


static func _plan_clearance_fields(entries: Array[Dictionary]) -> void:
	for entry in entries:
		var fields: Array[int] = []
		for other in entry.clearance:
			var field: int = entries[other].field
			if field >= 0 and not fields.has(field):
				fields.append(field)
		entry.clearance = fields


static func _is_spaced_random(entry: Dictionary) -> bool:
	return entry.placeable and not entry.clumped and entry.spacing > 0.0


## Random species share one Matern III field per size class, so two trees of different
## species are spaced like two of the same one (they would otherwise grow through each
## other). The group spacing is the largest of its members' (in the palette they agree).
## A candidate's species is drawn by the members' shares of the packed density, which
## Matern thinning preserves. Random species without spacing get a plain field each.
static func _plan_groups(
	biome_id: String, map_seed: int, entries: Array[Dictionary], fields: Array[Dictionary]
) -> void:
	var groups := {}
	for s in entries.size():
		var entry: Dictionary = entries[s]
		if entry.clumped or not entry.placeable:
			continue
		var group_key: String = (
			"spaced:" + String(entry.rule.size_class)
			if entry.spacing > 0.0
			else "plain:" + String(entry.key)
		)
		if not groups.has(group_key):
			groups[group_key] = []
		groups[group_key].append(s)
	for group_key in groups:
		var members: Array = groups[group_key]
		var spacing := 0.0
		var wanted := 0.0
		for s in members:
			spacing = maxf(spacing, entries[s].spacing)
			wanted += entries[s].rule.density_per_m2 / entries[s].keep
		var packing := _packing(wanted, spacing)
		var owners := PackedInt32Array()
		var cdf := PackedFloat64Array()
		var running := 0.0
		for s in members:
			running += entries[s].rule.density_per_m2 / entries[s].keep / wanted
			owners.append(s)
			cdf.append(running)
			entries[s].field = fields.size()
			entries[s].reachable = packing.y
		fields.append(_field(biome_id, map_seed, group_key, packing.x, spacing, owners, cdf))


## A clumped species' two fields: its parents (Matern III at CLUMP_PARENT_SPACING of the
## radius, delivering parents_per_m2) and its children (Matern III at the children
## spacing, dense enough that the clumps' covered share delivers the target).
static func _plan_clump_fields(
	biome_id: String, map_seed: int, entry: Dictionary, fields: Array[Dictionary]
) -> void:
	var clump: Dictionary = entry.rule.clump
	var owners := PackedInt32Array([entry.index])
	var cdf := PackedFloat64Array([1.0])
	var parent_spacing: float = clump.radius_m * CLUMP_PARENT_SPACING
	if entry.mass:  # a mass rule's swathes keep their own spacing
		parent_spacing = maxf(parent_spacing, float(clump.get("parent_spacing_m", 0.0)))
	var parents := _packing(clump.parents_per_m2, parent_spacing)
	entry.parent_field = fields.size()
	# Mass rules of one parent_group share their parents (the field's seed is its name).
	var group := int(clump.get("parent_group", 0.0)) if entry.mass else 0
	var name: String = "group:%d" % group if group > 0 else String(entry.key)
	fields.append(
		_field(biome_id, map_seed, "parents:" + name, parents.x, parent_spacing, owners, cdf)
	)
	var children := _packing(entry.rule.density_per_m2 / entry.keep, entry.spacing)
	entry.reachable = children.y
	entry.field = fields.size()
	fields.append(
		_field(biome_id, map_seed, "clump:" + entry.key, children.x, entry.spacing, owners, cdf)
	)


## Candidate intensity that makes a Matern III field at `spacing` deliver `density`
## survivors, and the share of it reachable under MAX_PACKING_TIME: Vector2(intensity,
## reachable). With four candidates per bucket, a candidate meets one fewer rival inside
## its own bucket than a Poisson field would, so its conflict rate is the Poisson one
## times g = 1 - f / 4, f being the share of its exclusion disc inside its own bucket.
## Survival then follows the Poisson curve at the effective time g * t, and delivered
## coverage is packing_coverage(g t) / g. Solved by two fixed-point steps (the bucket
## size, hence f, depends on the intensity).
static func _packing(density: float, spacing: float) -> Vector2:
	if spacing <= 0.0 or density <= 0.0:
		return Vector2(maxf(density, 0.0), 1.0)
	var disc := PI * spacing * spacing * 0.25
	var theta := density * disc
	var effective := packing_time(theta)
	var intensity := effective / disc
	var g := 1.0
	for _step in 2:
		var bucket := sqrt(CANDIDATES_PER_BUCKET / maxf(intensity, 1e-9))
		g = 1.0 - _own_bucket_share(spacing, bucket) / CANDIDATES_PER_BUCKET
		effective = packing_time(theta * g)
		intensity = effective / disc / g
	var reached := minf(packing_coverage(effective) / g, PACKING_COVERAGE[-1])
	return Vector2(intensity, minf(1.0, reached / theta))


## Expected share of a disc of radius r, centred uniformly in a square of side b, that
## lies inside the square: (pi r^2 - 8 r^3 / 3b + r^4 / 2b^2) / pi r^2 for r <= b, and
## about b^2 / pi r^2 beyond.
static func _own_bucket_share(r: float, b: float) -> float:
	var disc := PI * r * r
	if r <= b:
		return (disc - 8.0 * r * r * r / (3.0 * b) + pow(r, 4.0) / (2.0 * b * b)) / disc
	return b * b * (1.0 - 0.025 * b / r) / disc


static func _field(
	biome_id: String,
	map_seed: int,
	name: String,
	intensity: float,
	spacing: float,
	owners: PackedInt32Array,
	cdf: PackedFloat64Array
) -> Dictionary:
	# Four candidates per bucket at this intensity; the clamp caps a hostile density at
	# 400 per m2 rather than allocating millions of buckets.
	var bucket := clampf(sqrt(CANDIDATES_PER_BUCKET / maxf(intensity, 1e-9)), 0.1, 10000.0)
	return {
		"seed": ("%d|%s|%s" % [map_seed, biome_id, name]).hash() & _MASK32,
		"intensity": intensity,
		"bucket": bucket,
		"spacing": spacing,
		"owners": owners,
		"cdf": cdf,
		"empty": intensity <= 0.0,
	}
