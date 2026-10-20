extends GutTest

## How AuthoredScatter lands finished jobs (utils/scatter_apply.gd; card native-cover round 2):
## a cell lands only its newest waiting result, a provisional landing that changes nothing is
## skipped, the frame budget defers the rest to the next frame, and a rebuild leaves unchanged
## assets alone and merges an asset's grow-ins in batches.

const BIOME := "temperate_forest_summer_s1"
const OAK := BIOME + "/Tree_Oak_summer_01"
const BIG_BUDGET := 1_000_000_000
const DAB := Rect2(2.0, 2.0, 1.0, 1.0)

var _map: Node3D = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)


func _scatter() -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = BIG_BUDGET
	_map.add_child(scatter)
	return scatter


func _regen() -> ScatterRegen:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 11)
	doc.biome_ids = PackedStringArray([BIOME])
	var regen := ScatterRegen.for_document(doc)
	regen.whole_leads = true
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	return regen


## `count` oaks inside cell (0, 0), starting at the `first`-th of a fixed sequence.
func _oaks(count: int, first: int = 0) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for i in range(first, first + count):
		var p := Vector2(0.5 + fmod(i * 1.37, 9.0), 0.5 + fmod(i * 2.11, 9.0))
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


## A finished entry as ScatterApply.collect leaves it: `job` with `rows` of oaks in its cells.
func _finished(job: Dictionary, rows: PackedFloat32Array) -> Dictionary:
	var by_cell := {}
	for cell in job.cells:
		by_cell[cell] = {OAK: rows}
	return {"job": job, "result": {"rows_by_cell": by_cell}, "needs": [OAK]}


func test_a_cell_lands_only_its_newest_waiting_result() -> void:
	var scatter := _scatter()
	var cell := Vector2i.ZERO
	scatter.set_cells({cell: {OAK: _oaks(2)}}, false)
	var regen := _regen()
	regen.request_region(DAB, true, 0)
	var older := regen.take_job(1, 0)
	assert_true(older.get("whole", false), "a whole lead")
	regen.landed(older, 10)
	regen.request_region(DAB, true, 100)
	var newer := regen.take_job(1, 110)
	assert_true(newer.get("lead", false), "landed: the cell takes its next lead while one waits")
	var finished: Array[Dictionary] = [_finished(older, _oaks(3)), _finished(newer, _oaks(5))]
	scatter.landing.land(scatter, finished, regen)
	assert_true(finished.is_empty(), "both left the queue")
	assert_eq(scatter.landing.counts.dropped, 1, "the older one unapplied")
	assert_eq(scatter.cell_rows(cell)[OAK], _oaks(5), "the cell shows the newest")


func test_a_provisional_landing_that_changes_nothing_is_skipped() -> void:
	var scatter := _scatter()
	var cell := Vector2i.ZERO
	scatter.set_cells({cell: {OAK: _oaks(4)}}, false)
	var node := scatter.get_cell_node(cell, OAK)
	var multimesh := node.multimesh
	var regen := _regen()
	regen.request_region(DAB, true, 0)
	var lead := regen.take_job(1, 0)
	regen.request_region(DAB, true, 20)  # the brush moved on: the lead lands stale
	var finished: Array[Dictionary] = [_finished(lead, _oaks(4))]
	watch_signals(scatter)
	scatter.landing.land(scatter, finished, regen)
	assert_eq(scatter.landing.counts.skipped, 1, "skipped")
	assert_signal_not_emitted(scatter, "cells_applied", "nothing rebuilt")
	assert_same(scatter.get_cell_node(cell, OAK).multimesh, multimesh, "the node as it was")


func test_the_frame_budget_defers_what_does_not_fit() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(3, 3): {OAK: _oaks(1)}}, false)  # resolves the species
	var regen := _regen()
	regen.request_region(DAB)
	var first := regen.take_job(100)
	regen.request_region(Rect2(-12.0, -12.0, 1.0, 1.0))  # cell (-2, -2), far from the first
	var second := regen.take_job(100)
	var finished: Array[Dictionary] = [_finished(first, _oaks(30)), _finished(second, _oaks(30))]
	scatter.landing.budget_usec = 0
	scatter.landing.land(scatter, finished, regen)
	assert_eq(finished.size(), 1, "the first lands whatever its cost; the second waits")
	scatter.landing.land(scatter, finished, regen)
	assert_true(finished.is_empty(), "and lands the next frame")


func test_a_rebuild_leaves_an_unchanged_asset_alone() -> void:
	var scatter := _scatter()
	var cell := Vector2i.ZERO
	scatter.set_cells({cell: {OAK: _oaks(4)}}, false)
	var multimesh := scatter.get_cell_node(cell, OAK).multimesh
	scatter.set_cells({cell: {OAK: _oaks(4)}})
	assert_same(scatter.get_cell_node(cell, OAK).multimesh, multimesh, "untouched")
	assert_false(scatter.is_growing(), "nothing grows")
	scatter.lean_rebuild = false
	scatter.set_cells({cell: {OAK: _oaks(4)}})
	assert_ne(scatter.get_cell_node(cell, OAK).multimesh, multimesh, "round 1 rebuilt it")


func test_grow_ins_of_one_asset_merge_together() -> void:
	var scatter := _scatter()
	var cell := Vector2i.ZERO
	scatter.set_cells({cell: {OAK: _oaks(2)}}, false)
	for n in [3, 4, 5]:
		scatter.set_cells({cell: {OAK: _oaks(n)}})
	var entries: Array = (scatter.get("_growing") as Dictionary)[cell][OAK]
	assert_eq(entries.size(), 3, "three grow-ins")
	scatter.call("_finish_growth", cell, OAK, entries[0])
	scatter.call("_finish_growth", cell, OAK, entries[1])
	assert_eq(scatter.get_growing_nodes(cell, OAK).size(), 3, "two finished wait for the third")
	scatter.call("_finish_growth", cell, OAK, entries[2])
	assert_false(scatter.is_growing(), "one merge for all three")
	assert_eq(scatter.get_cell_node(cell, OAK).multimesh.instance_count, 5, "every oak settled")
