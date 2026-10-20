extends GutTest

## ScatterRegen's live cells (utils/scatter_regen.gd, "Live cells"; card brush-latency): a
## stroke's stale jobs show as provisional results while the brush is down, throttled per cell,
## and the rows a stroke settles on are exactly what latest-wins alone gives. Also the shrink-out
## of rows a later apply removes while they are still growing in (AuthoredScatter).

const BIOME := "temperate_forest_summer_s1"
const OAK := BIOME + "/Tree_Oak_summer_01"
const BIG_BUDGET := 1_000_000_000
## Simulated frames: 16 ms each, a job runs four of them, three run at once.
const FRAME_MSEC := 16
const JOB_FRAMES := 4
const SLOTS := 3

var _map: Node3D = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)


func _flat_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 11)
	doc.biome_ids = PackedStringArray([BIOME])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	doc.biome_slots = slots
	doc.biome_density = density
	return doc


## Paints the biome at `value` inside `rect` (world XZ), overwriting what was there.
func _paint(doc: MapDocument, rect: Rect2, value: int) -> void:
	for z in doc.samples_z():
		for x in doc.samples_x():
			if rect.has_point(doc.sample_to_world(Vector2(x, z))):
				var i := doc.sample_index(x, z)
				doc.biome_slots[i] = 1
				doc.biome_density[i] = value


func _generate_all(doc: MapDocument) -> Dictionary:
	var bounds := Rect2(-doc.extent_m() * 0.5, doc.extent_m())
	var fields := ScatterGenerator.document_fields(doc, BIOME)
	var rows := ScatterGenerator.generate(
		BIOME,
		PaletteLibrary.species(BIOME),
		fields.density_at,
		fields.height_at,
		fields.normal_at,
		doc.map_seed,
		ScatterGenerator.cells_in_bounds(bounds),
		fields.bounds
	)
	return AuthoredScatter.rows_by_cell_of(rows)


## A map with forest over its west half, the start of every stroke here.
func _start_doc() -> MapDocument:
	var doc := _flat_doc()
	_paint(doc, Rect2(-16.0, -16.0, 16.0, 32.0), 255)
	return doc


## Frame `f` of the stroke: a 3 m dab moving east along z = 1 and painting more thickly as it
## goes (thinning the forest at first, then filling the open half).
func _dab(f: int) -> Rect2:
	return Rect2(-9.0 + 1.2 * f, -2.0, 6.0, 6.0)


func _dab_value(f: int) -> int:
	return mini(70 + 25 * f, 255)


## Runs a stroke of `frames` frames through the scheduler the way AuthoredScatter does (cancel,
## finish, apply, take, one frame at a time), then lets it settle. Returns {"cells": the rows
## every cell ends with, "provisional": provisional applies, "final": current applies}. `whole`:
## lead jobs carry every species (ScatterRegen.whole_leads, the native path).
func _simulate(live: bool, frames: int, whole: bool = false) -> Dictionary:
	var doc := _start_doc()
	var cells := _generate_all(doc)
	var regen := ScatterRegen.for_document(doc)
	regen.whole_leads = whole
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	var in_flight: Array[Dictionary] = []
	var counts := {"provisional": 0, "final": 0}
	var f := 0
	while f < frames or not in_flight.is_empty() or regen.has_pending():
		var now := f * FRAME_MSEC
		if f < frames:
			_paint(doc, _dab(f), _dab_value(f))
			regen.request_region(_dab(f), live, now)
			regen.cancel_stale(in_flight)
		for entry in in_flight.duplicate():
			if entry.get("cancelled", false):
				# A posted cancel stops the job at once; its partial rows are never applied.
				in_flight.erase(entry)
				continue
			if f < int(entry.done):
				continue
			in_flight.erase(entry)
			var job: Dictionary = entry.job
			var result := ScatterRegen.run(entry.snapshot, job.work)
			var current := regen.accept(job, now)
			var shown := regen.provisional(job, now)
			counts.final += current.size()
			counts.provisional += shown.size()
			for cell in current + shown:
				cells[cell] = ScatterRegen.merge_cell(
					cells.get(cell, {}), job.regenerated[cell], result.rows_by_cell.get(cell, {})
				)
		while in_flight.size() < SLOTS and regen.has_pending():
			var job := regen.take_job(1, now)
			if job.is_empty():  # whole leads: only held cells left, their leads out
				break
			in_flight.append(
				{
					"job": job,
					"cancel": Semaphore.new(),
					"snapshot": ScatterRegen.snapshot(doc),
					# A lead job is a small share of the work.
					"done": f + (1 if job.get("lead", false) else JOB_FRAMES),
				}
			)
		f += 1
		assert_lt(f, 2000, "the simulation settles")
		if f >= 2000:
			break
	for cell in cells.keys():
		if (cells[cell] as Dictionary).is_empty():
			cells.erase(cell)
	return {"cells": cells, "provisional": counts.provisional, "final": counts.final, "doc": doc}


func test_a_live_stroke_settles_on_the_rows_latest_wins_gives() -> void:
	var today := _simulate(false, 10)
	var live := _simulate(true, 10)
	assert_eq(today.provisional, 0, "latest-wins alone shows nothing provisional")
	assert_gt(live.provisional, 0, "the live stroke showed results while the brush was down")
	var expected := _generate_all(live.doc)
	var all_cells := {}
	all_cells.merge(today.cells)
	all_cells.merge(live.cells)
	all_cells.merge(expected)
	for cell in all_cells:
		assert_eq(live.cells.get(cell, {}), today.cells.get(cell, {}), "cell %s as today" % cell)
		assert_eq(live.cells.get(cell, {}), expected.get(cell, {}), "cell %s as generated" % cell)


## Whole leads (the native path, card native-cover): the stroke shows provisional rows ground
## cover included, and still settles on exactly latest-wins' rows and the generator's.
func test_a_live_stroke_with_whole_leads_settles_on_the_rows_latest_wins_gives() -> void:
	var today := _simulate(false, 10)
	var live := _simulate(true, 10, true)
	assert_gt(live.provisional, 0, "the live stroke showed results while the brush was down")
	var expected := _generate_all(live.doc)
	var all_cells := {}
	all_cells.merge(today.cells)
	all_cells.merge(live.cells)
	all_cells.merge(expected)
	for cell in all_cells:
		assert_eq(live.cells.get(cell, {}), today.cells.get(cell, {}), "cell %s as today" % cell)
		assert_eq(live.cells.get(cell, {}), expected.get(cell, {}), "cell %s as generated" % cell)


func test_a_whole_lead_carries_the_ground_cover_and_stands_as_the_full_job() -> void:
	var regen := _regen()
	regen.whole_leads = true
	var dab := Rect2(2.0, 2.0, 1.0, 1.0)
	var painted := Vector2i(0, 0)
	regen.request_region(dab, true, 0)
	var lead := regen.take_job(100, 0)
	assert_true(lead.get("lead", false) and lead.get("whole", false), "a whole lead job first")
	assert_eq(lead.cells, [painted] as Array[Vector2i])
	var ground := 0
	for rule in PaletteLibrary.species(BIOME):
		if rule.get("size_class", "") == ScatterRegen.GROUND_CLASS:
			for asset_id in rule.get("assets", []):
				ground += 1 if asset_id in lead.regenerated[painted] else 0
	assert_gt(ground, 0, "the ground cover is in it")
	assert_true(OAK in lead.regenerated[painted], "and the trees")
	regen.request_region(dab, true, 10)
	var held := regen.take_job(100, 20)
	assert_false(painted in held.get("cells", []), "no other job while the brush is on the cell")
	assert_eq(regen.accept(lead, 30), [] as Array[Vector2i], "stale: not current")
	assert_eq(regen.provisional(lead, 30), [painted] as Array[Vector2i], "it shows for now")
	assert_eq(_full_job(regen, 40).get("cells", []).count(painted), 0, "still held at 40 ms")
	var full := _full_job(regen, 70)
	assert_true(painted in full.cells, "once the brush has left, the full job (latest-wins)")
	assert_true(painted in regen.accept(full, 90))
	# A whole lead no request overtook lands as the cell's final rows.
	regen.request_region(dab, true, 200)
	var last := regen.take_job(100, 200)
	assert_true(last.get("whole", false) and painted in last.cells)
	assert_eq(regen.accept(last, 230), [painted] as Array[Vector2i], "current: accepted")
	assert_eq(regen.provisional(last, 230), [] as Array[Vector2i], "and not shown twice")
	assert_false(painted in regen.take_job(100, 300).get("cells", []), "the cell owes nothing")


func _regen() -> ScatterRegen:
	var regen := ScatterRegen.for_document(_flat_doc())
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	return regen


func _entry(job: Dictionary) -> Dictionary:
	return {"job": job, "cancel": Semaphore.new()}


## Takes jobs until a full (not lead) one comes out.
func _full_job(regen: ScatterRegen, now: int) -> Dictionary:
	var job := regen.take_job(100, now)
	while job.get("lead", false):
		job = regen.take_job(100, now)
	return job


func test_a_lead_job_shows_the_large_species_while_the_full_job_is_owed() -> void:
	var regen := _regen()
	var dab := Rect2(2.0, 2.0, 1.0, 1.0)
	var painted := Vector2i(0, 0)
	regen.request_region(dab, true, 0)
	var lead := regen.take_job(100, 0)
	assert_true(lead.get("lead", false), "a live cell gets a lead job first")
	assert_eq(lead.cells, [painted] as Array[Vector2i], "the painted cell, nearest the dab")
	var ground := PackedStringArray()
	for rule in PaletteLibrary.species(BIOME):
		if rule.get("size_class", "") == ScatterRegen.GROUND_CLASS:
			ground.append_array(PackedStringArray(rule.get("assets", [])))
	var regenerated: PackedStringArray = lead.regenerated[painted]
	assert_true(OAK in regenerated, "the trees are in it")
	for asset_id in regenerated:
		assert_false(asset_id in ground, "%s: no ground cover" % asset_id)
	assert_true(regen.has_pending(), "the cell is still owed its full job")
	var entries: Array[Dictionary] = [_entry(lead)]
	regen.request_region(dab, true, 10)
	regen.cancel_stale(entries)
	assert_false(entries[0].get("cancelled", false), "a lead job is never cancelled")
	assert_eq(regen.accept(lead, 30), [] as Array[Vector2i], "nor current")
	assert_eq(regen.provisional(lead, 30), [painted] as Array[Vector2i], "it shows for now")
	regen.request_region(dab, true, 50)
	var next := regen.take_job(1, 60)
	assert_false(next.get("lead", false) and next.cells[0] == painted, "throttled at 30 ms")
	regen.request_region(dab, true, 190)
	var again := regen.take_job(1, 200)
	assert_true(again.get("lead", false) and again.cells[0] == painted, "due again at 170 ms")
	var full := _full_job(regen, 210)
	assert_true(painted in regen.accept(full, 250), "the full job lands under latest-wins")
	assert_eq(regen.provisional(again, 260), [] as Array[Vector2i], "nothing older shows after it")
	# Once the brush has left a cell, its full job goes before any lead job.
	regen.request_region(dab, true, 300)
	assert_false(regen.take_job(1, 400).get("lead", false), "no lead 100 ms after the brush left")


func test_a_request_that_is_not_live_keeps_latest_wins() -> void:
	var regen := _regen()
	var dab := Rect2(2.0, 2.0, 1.0, 1.0)
	regen.request_region(dab)
	var first := regen.take_job(100, 0)
	assert_false(first.get("lead", false), "no lead job")
	var entries: Array[Dictionary] = [_entry(first)]
	regen.request_region(dab)
	regen.cancel_stale(entries)
	assert_true(entries[0].get("cancelled", false), "a stale job is cancelled as before")
	assert_eq(regen.provisional(first, 500), [] as Array[Vector2i], "and never shown")
	# An undo over a live cell ends its live state: nothing from the stroke shows after it.
	regen.request_region(dab, true, 590)
	var lead := regen.take_job(100, 600)
	assert_true(lead.get("lead", false))
	regen.request_region(dab)
	assert_eq(regen.provisional(lead, 700), [] as Array[Vector2i])


func test_a_lead_result_no_newer_than_the_rows_on_screen_is_dropped() -> void:
	var regen := _regen()
	regen.request_region(Rect2(2.0, 2.0, 1.0, 1.0), true, 0)
	var lead := regen.take_job(100, 0)
	var full := _full_job(regen, 0)
	assert_true(Vector2i(0, 0) in regen.accept(full, 10), "nothing touched it since: current")
	assert_eq(regen.provisional(lead, 20), [] as Array[Vector2i], "the lead job is dropped")


func test_a_live_request_queues_the_cells_nearest_it_first() -> void:
	var regen := _regen()
	var cells := regen.request_region(Rect2(2.0, 2.0, 1.0, 1.0), true)
	assert_eq(cells[0], Vector2i(0, 0), "the painted cell first, its halo after")


# --- AuthoredScatter -----------------------------------------------------------------------


func _scatter() -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = BIG_BUDGET
	_map.add_child(scatter)
	return scatter


func _oak_rows(count: int) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for i in count:
		var p := Vector2(0.5 + fmod(i * 1.37, 9.0), 0.5 + fmod(i * 2.11, 9.0))
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


func _shrinking(scatter: AuthoredScatter) -> int:
	var count := 0
	for child in scatter.get_children():
		count += 1 if String(child.name).contains(ScatterShrink.INFIX) else 0
	return count


func test_rows_removed_while_growing_in_shrink_out_instead_of_vanishing() -> void:
	var scatter := _scatter()
	var cell := Vector2i.ZERO
	scatter.set_cells({cell: {OAK: _oak_rows(4)}})
	assert_true(scatter.is_growing(), "four oaks grow in")
	await wait_seconds(0.1)
	scatter.set_cells({cell: {OAK: _oak_rows(2)}})
	assert_eq(_shrinking(scatter), 1, "the two dropped mid-grow shrink from where they were")
	assert_eq(scatter.get_growing_nodes(cell, OAK).size(), 1, "the two kept keep growing")


func test_a_live_brush_stroke_on_workers_ends_on_the_generated_rows() -> void:
	var doc := _start_doc()
	var scatter := _scatter()
	scatter.set_cells(_generate_all(doc), false)
	scatter.attach_document(doc)
	for f in 10:
		_paint(doc, _dab(f), _dab_value(f))
		scatter.request_region(_dab(f), true)
		await get_tree().process_frame
	var waited := 0
	while scatter.is_regenerating() and waited < 600:
		await get_tree().process_frame
		waited += 1
	assert_false(scatter.is_regenerating(), "the stroke's regeneration finished")
	var expected := _generate_all(doc)
	for x in range(-2, 2):
		for z in range(-2, 2):
			var cell := Vector2i(x, z)
			assert_eq(scatter.cell_rows(cell), expected.get(cell, {}), "cell %s" % cell)
