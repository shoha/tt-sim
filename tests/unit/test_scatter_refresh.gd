extends GutTest

## ScatterRegen.replace_biome and the partial regeneration the biome designer relies on: after
## a rule is edited, regenerating only the species the edit can change (the edited rule and every
## species that reads it through a relation, a shared spacing field or a clearance) gives the same
## rows as regenerating the whole biome from scratch. Pure data (no scene): the jobs are run the
## way FoliageLibrary.adapt_async runs them.

const BIOME := "temperate_forest_summer_s1"
const WINDOW := Rect2(-12.0, -12.0, 24.0, 24.0)

var _doc: MapDocument = null


func before_all() -> void:
	_doc = ProvingGround.build(BIOME)


## All the jobs of `regen` run on `frozen`, merged cell by cell on top of `existing` the way the
## scatter applies a landing: {cell: {asset id: rows}}.
func _run(regen: ScatterRegen, frozen: MapDocument, existing: Dictionary) -> Dictionary:
	var by_cell := existing.duplicate(true)
	while regen.has_pending():
		var job := regen.take_job(16)
		if job.is_empty():
			break
		var result := ScatterRegen.run(frozen, job["work"])
		var rows_by_cell: Dictionary = result["rows_by_cell"]
		for cell: Vector2i in job["cells"]:
			var regenerated: PackedStringArray = job["regenerated"].get(cell, PackedStringArray())
			by_cell[cell] = ScatterRegen.merge_cell(
				by_cell.get(cell, {}), regenerated, rows_by_cell.get(cell, {})
			)
	return by_cell


func _rules() -> Array[Dictionary]:
	return PaletteLibrary.species(BIOME)


func _regen_for(rules: Array[Dictionary]) -> ScatterRegen:
	var regen := ScatterRegen.for_document(_doc)
	regen.set_biome(BIOME, rules)
	return regen


func _full(rules: Array[Dictionary]) -> Dictionary:
	var regen := _regen_for(rules)
	regen.request_region(WINDOW)
	return _run(regen, ScatterRegen.snapshot(_doc), {})


## `before` edited into `after` by regenerating only what replace_biome says.
func _partial(before: Array[Dictionary], after: Array[Dictionary]) -> Dictionary:
	var start := _full(before)
	var regen := _regen_for(before)
	var delta := regen.replace_biome(BIOME, after)
	# What ScatterRefresh.drop_assets does on screen: the removed rules' rows go.
	for cell: Vector2i in start:
		for asset_id in delta["removed_assets"]:
			(start[cell] as Dictionary).erase(asset_id)
	regen.request_region(WINDOW, false, -1, {BIOME: delta["indices"]})
	var rows := _run(regen, ScatterRegen.snapshot(_doc), start)
	rows["delta"] = delta
	return rows


func _same(a: Dictionary, b: Dictionary) -> bool:
	var left := a.duplicate()
	left.erase("delta")
	return _flat(left) == _flat(b)


## {cell string + asset: row count and a hash of the rows}, empty entries dropped.
func _flat(by_cell: Dictionary) -> Dictionary:
	var out := {}
	for cell: Vector2i in by_cell:
		for asset_id: String in by_cell[cell]:
			var rows: PackedFloat32Array = by_cell[cell][asset_id]
			if rows.size() > 0:
				out["%s|%s" % [cell, asset_id]] = [rows.size(), hash(rows)]
	return out


func _index_of(rules: Array[Dictionary], role_kind: String, size_class: String) -> int:
	for i in rules.size():
		if rules[i]["kind"] == role_kind and rules[i]["size_class"] == size_class:
			return i
	return -1


func test_an_unchanged_biome_requests_nothing() -> void:
	var rules := _rules()
	var regen := _regen_for(rules)
	var delta := regen.replace_biome(BIOME, rules)
	assert_true((delta["indices"] as PackedInt32Array).is_empty())
	assert_true((delta["removed_assets"] as PackedStringArray).is_empty())


func test_a_tree_density_edit_regenerates_the_same_rows_as_a_full_run() -> void:
	var before := _rules()
	var after := _rules()
	var at := _index_of(after, "tree", "large")
	assert_true(at >= 0)
	after[at]["density_per_m2"] = float(after[at]["density_per_m2"]) * 2.5
	var partial := _partial(before, after)
	var delta: Dictionary = partial["delta"]
	assert_true((delta["indices"] as PackedInt32Array).has(at))
	gut.p(
		"tree density edit: %d of %d species regenerated" % [delta["indices"].size(), after.size()]
	)
	assert_true(_same(partial, _full(after)), "partial rows equal a full regeneration")


func test_a_ground_cover_edit_touches_few_species_and_matches_a_full_run() -> void:
	var before := _rules()
	var after := _rules()
	var at := _index_of(after, "grass", "ground")
	assert_true(at >= 0)
	after[at]["slope_max_deg"] = 20.0
	var partial := _partial(before, after)
	var delta: Dictionary = partial["delta"]
	assert_true(
		delta["indices"].size() < after.size() / 2, "only a few of %d species" % after.size()
	)
	assert_true(_same(partial, _full(after)))


func test_a_slope_curve_edit_matches_a_full_run() -> void:
	var before := _rules()
	var after := _rules()
	var at := _index_of(after, "tree", "medium")
	assert_true(at >= 0)
	after[at]["response"] = {"slope": [[0.0, 1.0], [25.0, 0.2], [90.0, 0.0]]}
	after[at]["slope_min_deg"] = 3.0
	var partial := _partial(before, after)
	assert_true(_same(partial, _full(after)))


func test_removing_a_rule_clears_its_assets_and_matches_a_full_run() -> void:
	var before := _rules()
	var after := _rules()
	var at := _index_of(after, "tree", "large")
	var gone: Array = after[at]["assets"]
	after.remove_at(at)
	var partial := _partial(before, after)
	var delta: Dictionary = partial["delta"]
	for asset_id: String in gone:
		assert_true(asset_id in delta["removed_assets"], asset_id)
	assert_true(_same(partial, _full(after)), "and the rest is a full regeneration's")


func test_cancel_all_leaves_nothing_pending_and_makes_running_jobs_stale() -> void:
	var regen := _regen_for(_rules())
	regen.request_region(WINDOW)
	var job := regen.take_job(4)
	assert_true(regen.has_pending())
	regen.cancel_all()
	assert_false(regen.has_pending())
	assert_true(regen.is_stale(job), "a job already out lands as stale")
	regen.request_region(WINDOW)
	assert_true(regen.has_pending(), "and a new request works again")
