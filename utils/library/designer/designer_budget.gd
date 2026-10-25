class_name DesignerBudget
extends RefCounted

## The designer's budget meter (design doc 4.4): what the biome on the proving ground costs, as
## instances and triangles per 100 ft tile and for a whole map, against the player's foliage
## primitive budget (FoliageBudget, 2M to 24M, default 8M), plus an estimate of draw calls (one
## per species per occupied 10 m cell). Pure: it is handed the instance counts the scatter
## holds and the catalog's LOD0 triangles per asset; the live frame cost and the real draw calls
## come from the renderer (RenderingServer viewport info) in the meter's UI.

## A 100 ft tile, the unit the project counts density in (the default map is one).
const TILE_M2 := 929.03
## The map the verdict is for: a 200 ft map is four tiles.
const REFERENCE_TILES := 4.0
## The meter turns amber above this share of the budget and red above 1.0.
const AMBER_SHARE := 0.6
const RED_SHARE := 1.0
## Triangles the meter assumes for an asset the catalog does not give a count for.
const UNKNOWN_TRIANGLES := 500

## The triangle budget of one asset by catalog category (plantgen's per-prefix budgets: amber
## above it, red above 1.5 times it).
const ASSET_BUDGETS := {"tree": 3000, "bush": 2000, "ground_cover": 700}
const ASSET_BUDGET_DEFAULT := 1500


## The estimate. `counts`: {asset id: instances} on the proving ground; `cells`: {asset id: the
## number of 10 m cells holding it}; `triangles`: {asset id: LOD0 triangles}; `rules`: the
## palette biome's species ({key, assets}); `area_m2` the painted area; `budget` the primitive
## budget. Returns {instances, triangles, tiles (the area in 100 ft tiles), per_tile
## {instances, triangles}, map {triangles, share (of the budget, a 200 ft map), level ("ok",
## "amber" or "red")}, draw_calls (estimated), by_rule {key: {instances, triangles}}}.
static func estimate(
	counts: Dictionary,
	cells: Dictionary,
	triangles: Dictionary,
	rules: Array,
	area_m2: float,
	budget: int = FoliageBudget.PRIMITIVE_BUDGET
) -> Dictionary:
	var total_instances := 0
	var total_triangles := 0
	var draw_calls := 0
	for asset_id: String in counts:
		var n := int(counts[asset_id])
		total_instances += n
		total_triangles += n * int(triangles.get(asset_id, UNKNOWN_TRIANGLES))
		draw_calls += int(cells.get(asset_id, 0))
	var by_rule := {}
	for rule: Dictionary in rules:
		var instances := 0
		var tris := 0
		for asset_id: String in rule.get("assets", []):
			var n := int(counts.get(asset_id, 0))
			instances += n
			tris += n * int(triangles.get(asset_id, UNKNOWN_TRIANGLES))
		by_rule[String(rule["key"])] = {"instances": instances, "triangles": tris}
	var tiles := maxf(area_m2 / TILE_M2, 0.0001)
	var per_tile_tris := float(total_triangles) / tiles
	var map_tris := per_tile_tris * REFERENCE_TILES
	var share := map_tris / float(maxi(budget, 1))
	return {
		"instances": total_instances,
		"triangles": total_triangles,
		"tiles": tiles,
		"per_tile": {"instances": float(total_instances) / tiles, "triangles": per_tile_tris},
		"map": {"triangles": map_tris, "share": share, "level": level_of(share)},
		"draw_calls": draw_calls,
		"by_rule": by_rule,
	}


## "ok", "amber" or "red" for a share of the budget.
static func level_of(share: float) -> String:
	if share >= RED_SHARE:
		return "red"
	if share >= AMBER_SHARE:
		return "amber"
	return "ok"


## The LOD0 triangle count of each asset id the compiled `palette` biome places, from the
## candidates (LibraryQuery.candidates) the compile drew them from: {runtime asset id: triangles}.
static func triangles_of(biome: Dictionary, candidates: Array[Dictionary]) -> Dictionary:
	var by_local := {}
	for candidate in candidates:
		by_local[candidate["local"]] = candidate
	var out := {}
	for rule: Dictionary in biome.get("species", []):
		for asset_id: String in rule.get("assets", []):
			var local := asset_id.get_slice("/", 1)
			var candidate: Dictionary = by_local.get(local, {})
			if not candidate.is_empty():
				out[asset_id] = int(
					(candidate["entry"] as Dictionary).get("triangles", UNKNOWN_TRIANGLES)
				)
	return out


## "ok", "amber" or "red" for an asset of `category` with `triangles`.
static func asset_level(category: String, triangles: int) -> String:
	var budget := float(ASSET_BUDGETS.get(category, ASSET_BUDGET_DEFAULT))
	if float(triangles) > budget * 1.5:
		return "red"
	return "amber" if float(triangles) > budget else "ok"


## A short text for a count: 1.9M, 420k, 83.
static func short(value: float) -> String:
	if value >= 1000000.0:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%dk" % roundi(value / 1000.0)
	return str(roundi(value))
