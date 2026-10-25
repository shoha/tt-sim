extends RefCounted

## Timing for the native scatter generator (card native-scatter, 2026-10-20), run through
## tools/native_scatter_run.gd. Every task runs GDScript (ScatterNative.force_gdscript) and native
## in the same run, alternating, so drift falls on both alike. Figures are headless and CPU only;
## take them on a quiet machine (docs/PERFORMANCE.md).
##   job      the gen-native probe's cell (a fresh 200 ft grassland at seed 1234, cell (0, 0) and
##            2 m around it painted to full density) as one ScatterRegen job, one thread: the
##            whole job, and for native also pack() alone and the library's own generate time.
##   threads  1, 6 and 12 such jobs at once on WorkerThreadPool: per-job time and the batch.
##   map      a whole new map's scatter build (NewMap.create, then every cell through
##            ScatterRegen's jobs as AuthoredScatter runs them, min(cores / 2, 6) at once, apply
##            and rendering left out): wall time to the last job.
##   counts   native and fallback jobs (ScatterNative.fallbacks) for the five landform recipe
##            maps' whole builds.

const BIOME := "grassland_meadow_summer_s1"
const SIZE_FT := 200
const SEED := 1234
const PAINT_MARGIN_M := 2.0
const LANDFORMS := ["valley", "hilltop", "terraces", "lakeshore", "gorge"]

var _mutex := Mutex.new()
var _usec: Array[int] = []


func run(args: Dictionary) -> void:
	match String(args.get("task", "job")):
		"job":
			_job(int(args.get("runs", "15")), int(args.get("warm", "3")))
		"threads":
			_threads(int(args.get("runs", "4")))
		"map":
			_map(int(args.get("runs", "3")), String(args.get("landform", "flat")))
		"counts":
			_counts()
		"pack":
			_pack_parts(int(args.get("runs", "15")))
		"curves":
			_curves(int(args.get("runs", "9")))
	ScatterNative.force_gdscript = false
	print("native_scatter_bench: library %s" % ScatterNative.version())


func _probe_doc() -> MapDocument:
	var doc := NewMap.create(SIZE_FT, BIOME, SEED)
	var slot := doc.biome_ids.find(BIOME) + 1
	var rect := Rect2(Vector2.ZERO, Vector2(10.0, 10.0)).grow(PAINT_MARGIN_M)
	var first := Vector2i(doc.world_to_sample(rect.position).ceil())
	var last := Vector2i(doc.world_to_sample(rect.end).floor())
	var columns := doc.samples_x()
	for z in range(maxi(first.y, 0), mini(last.y, doc.samples_z() - 1) + 1):
		for x in range(maxi(first.x, 0), mini(last.x, columns - 1) + 1):
			doc.biome_slots[z * columns + x] = slot
			doc.biome_density[z * columns + x] = 255
	return doc


## The probe cell's job as ScatterRegen makes it (every species, cell (0, 0)).
func _probe_work(doc: MapDocument) -> Dictionary:
	var regen := ScatterRegen.for_document(doc)
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	regen.built_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("built"))
	regen.cliff_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	regen.request_region(Rect2(4.0, 4.0, 2.0, 2.0))
	var job := regen.take_job()
	while not regen.take_job().is_empty():
		pass
	return job.work


func _job(runs: int, warm: int) -> void:
	var doc := _probe_doc()
	var work := _probe_work(doc)
	var gd := PackedFloat64Array()
	var nt := PackedFloat64Array()
	var packed := PackedFloat64Array()
	var inner := PackedFloat64Array()
	var entry: Dictionary = work[BIOME]
	var species: Array[Dictionary] = []
	species.assign(entry.species)
	for k in warm + runs:
		ScatterNative.force_gdscript = true
		var t := Time.get_ticks_usec()
		ScatterRegen.run(doc, work)
		var g := Time.get_ticks_usec() - t
		ScatterNative.force_gdscript = false
		var n := 0
		for _r in 5:  # native is ~50x faster: five runs per GDScript run
			t = Time.get_ticks_usec()
			ScatterRegen.run(doc, work)
			n = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			var job := ScatterNative.pack(
				doc,
				BIOME,
				species,
				entry.cells_by_species,
				entry.window,
				entry.built,
				entry.cliff,
				PackedFloat32Array()
			)
			var p := Time.get_ticks_usec() - t
			var out: Dictionary = ScatterNative._instance().call("generate", job)
			if k >= warm:
				nt.append(n / 1000.0)
				packed.append(p / 1000.0)
				inner.append(int(out.usec) / 1000.0)
		if k >= warm:
			gd.append(g / 1000.0)
	print(
		(
			(
				"job (probe cell, one thread): GDScript median %.2f ms (n %d, min %.2f max %.2f);"
				+ " native median %.3f ms (n %d, min %.3f max %.3f): pack %.3f ms + library %.3f ms;"
				+ " %.1fx"
			)
			% [
				_median(gd),
				gd.size(),
				_min(gd),
				_max(gd),
				_median(nt),
				nt.size(),
				_min(nt),
				_max(nt),
				_median(packed),
				_median(inner),
				_median(gd) / _median(nt)
			]
		)
	)


func _threads(runs: int) -> void:
	var doc := _probe_doc()
	var work := _probe_work(doc)
	for count in [1, 6, 12]:
		for native in [true, false]:
			ScatterNative.force_gdscript = not native
			var per_job := PackedFloat64Array()
			var batches := PackedFloat64Array()
			var rounds := runs if native else maxi(1, runs / 2)
			for _r in rounds + 1:
				_usec.clear()
				var t := Time.get_ticks_usec()
				var ids: Array[int] = []
				for _j in count:
					ids.append(WorkerThreadPool.add_task(_run_one.bind(doc, work)))
				for id in ids:
					WorkerThreadPool.wait_for_task_completion(id)
				var batch := Time.get_ticks_usec() - t
				if _r == 0:
					continue  # warm-up
				batches.append(batch / 1000.0)
				for u in _usec:
					per_job.append(u / 1000.0)
			print(
				(
					"threads %2d %-8s per job median %8.2f ms (min %.2f max %.2f), batch median %8.2f ms"
					% [
						count,
						"native" if native else "GDScript",
						_median(per_job),
						_min(per_job),
						_max(per_job),
						_median(batches)
					]
				)
			)


func _run_one(doc: MapDocument, work: Dictionary) -> void:
	var t := Time.get_ticks_usec()
	ScatterRegen.run(doc, work)
	var spent := Time.get_ticks_usec() - t
	_mutex.lock()
	_usec.append(spent)
	_mutex.unlock()


func _map(runs: int, landform: String) -> void:
	for native in [false, true]:
		ScatterNative.force_gdscript = not native
		var walls := PackedFloat64Array()
		var jobs := 0
		for _r in runs:
			var built := _build(
				NewMap.create(SIZE_FT, BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, landform)
			)
			walls.append(built.ms)
			jobs = built.jobs
		print(
			(
				"map %s (%d ft %s, seed %d): %-8s whole scatter build median %.0f ms (%s), %d jobs"
				% [
					landform,
					SIZE_FT,
					BIOME,
					SEED,
					"native" if native else "GDScript",
					_median(walls),
					walls,
					jobs
				]
			)
		)


## Every cell of `doc` through ScatterRegen's jobs, as AuthoredScatter runs them: {ms, jobs}.
func _build(doc: MapDocument) -> Dictionary:
	var regen := ScatterRegen.for_document(doc)
	for biome_id in doc.biome_ids:
		regen.set_biome(biome_id, PaletteLibrary.species(biome_id))
	regen.built_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("built"))
	regen.cliff_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	var snapshot := ScatterRegen.snapshot(doc)
	var limit := clampi(OS.get_processor_count() >> 1, 1, AuthoredScatter.MAX_JOBS)
	var started := Time.get_ticks_usec()
	regen.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var running: Array[Dictionary] = []
	var jobs := 0
	while regen.has_pending() or not running.is_empty():
		while running.size() < limit:
			var job := regen.take_job()
			if job.is_empty():
				break
			var holder := {"job": job, "result": {}}
			holder["id"] = WorkerThreadPool.add_task(
				func() -> void: holder.result = ScatterRegen.run(snapshot, job.work)
			)
			running.append(holder)
			jobs += 1
		var first: Dictionary = running.pop_front()
		WorkerThreadPool.wait_for_task_completion(first.id)
		regen.accept(first.job)
	return {"ms": (Time.get_ticks_usec() - started) / 1000.0, "jobs": jobs}


func _counts() -> void:
	ScatterNative.force_gdscript = false
	for landform in LANDFORMS:
		ScatterNative.reset_counts()
		var doc := NewMap.create(SIZE_FT, BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, landform)
		var built := _build(doc)
		print(
			(
				"counts %-9s water %s crossings %d: %s (%d jobs, %.0f ms)"
				% [
					landform,
					doc.water_dressing.size() == doc.sample_count() * WaterDressing.CHANNELS,
					doc.crossings.size(),
					ScatterNative.fallbacks(),
					built.jobs,
					built.ms
				]
			)
		)


## pack()'s parts on the probe cell, one thread (card native-cover): where the GDScript of a
## native job goes.
func _pack_parts(runs: int) -> void:
	var doc := _probe_doc()
	var entry: Dictionary = _probe_work(doc)[BIOME]
	var species: Array[Dictionary] = []
	species.assign(entry.species)
	var parts := {}
	for k in runs + 2:
		var times := {}
		var t := Time.get_ticks_usec()
		ScatterNative.pack(
			doc,
			BIOME,
			species,
			entry.cells_by_species,
			entry.window,
			entry.built,
			entry.cliff,
			PackedFloat32Array()
		)
		times["pack"] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		ScatterNative.grids_for(doc, BIOME, entry.window, entry.built, entry.cliff)
		times["grids_for"] = Time.get_ticks_usec() - t
		var columns := doc.samples_x()
		var rows := doc.samples_z()
		var low := Vector2i(doc.world_to_sample(entry.window.position).floor())
		var high := Vector2i(doc.world_to_sample(entry.window.end).ceil())
		var rect := Rect2i(low, high - low + Vector2i.ONE).grow(1).intersection(
			Rect2i(0, 0, columns, rows)
		)
		t = Time.get_ticks_usec()
		TerrainRules.sample_fields(doc.heights, columns, rows, doc.sample_step(), rect)
		times["sample_fields"] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		ScatterGround.face_proximity(doc.heights, columns, rows, doc.sample_step(), rect)
		times["face_proximity"] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		ScatterGround._painted_fields(doc, rect, entry.built, entry.cliff)
		times["painted"] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		ScatterGround._built_fringe(doc, rect, entry.built)
		times["fringe"] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var plan := ScatterPlan.build(BIOME, species, doc.map_seed)
		times["plan"] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var fields: Array[Dictionary] = []
		fields.assign(plan.fields)
		for plan_entry: Dictionary in plan.species:
			ScatterGenerator._noise(plan_entry, fields)
		times["noise"] = Time.get_ticks_usec() - t
		if k < 2:
			continue
		for key in times:
			var list: PackedFloat64Array = parts.get(key, PackedFloat64Array())
			list.append(times[key] / 1000.0)
			parts[key] = list
	var line := PackedStringArray()
	for key in parts:
		line.append("%s %.2f" % [key, _median(parts[key])])
	print(
		(
			"pack parts (probe cell, median ms of %d, surfaces %s): %s"
			% [runs, str(doc.has_surface_entries()), ", ".join(line)]
		)
	)


## The GDScript cost of a rule's terrain response (step S12a): the probe cell's job with every
## rule carrying identity curves (rows unchanged, so the delta is pure evaluation cost), variants
## interleaved, then ScatterTerrain.keep alone per call on the document's fields.
func _curves(runs: int) -> void:
	var doc := _probe_doc()
	var work := _probe_work(doc)
	var entry: Dictionary = work[BIOME]
	var identity := {
		"slope": [[0.0, 1.0], [90.0, 1.0]],
		"height": [[-500.0, 1.0], [5000.0, 1.0]],
		"wet": [[0.0, 1.0], [1.0, 1.0]],
		"water_dist": [[0.0, 1.0], [64.0, 1.0]],
	}
	# S12c: a lake beside the probe cell (wet-line byte only, so the ground rules stay quiet) and
	# the distance grid's build cost on this 200 ft map (one transform, then cached per dressing).
	var columns := doc.samples_x()
	var field := PackedByteArray()
	field.resize(doc.sample_count() * WaterDressing.CHANNELS)
	for z in doc.samples_z():
		for x in columns:
			if doc.sample_to_world(Vector2(x, z)).distance_to(Vector2(-8.0, 5.0)) <= 4.0:
				field[(z * columns + x) * WaterDressing.CHANNELS + 3] = 255
	doc.water_dressing = field
	var started := Time.get_ticks_usec()
	ScatterTerrain.water_distance_grid(doc)
	print(
		(
			"water distance grid (%d x %d samples, built once per dressing): %.1f ms"
			% [columns, doc.samples_z(), (Time.get_ticks_usec() - started) / 1000.0]
		)
	)
	var variants := {
		"legacy": {},
		"slope_min 20": {"slope_min_deg": 20.0},
		"identity slope": {"response": {"slope": identity["slope"]}},
		"identity height": {"response": {"height": identity["height"]}},
		"identity wet": {"response": {"wet": identity["wet"]}},
		"identity water_dist": {"response": {"water_dist": identity["water_dist"]}},
		"identity all four": {"response": identity},
	}
	var times := {}
	var native_times := {}
	var inner_times := {}
	var native_ok := ScatterNative.available() and ScatterNative.version().contains("curves")
	for k in 2 + runs:
		for label: String in variants:
			var species: Array[Dictionary] = []
			for rule: Dictionary in entry.species:
				species.append(rule.merged(variants[label].duplicate(true), true))
			var changed := entry.duplicate()
			changed["species"] = species
			var job := {BIOME: changed}
			ScatterNative.force_gdscript = true
			var t := Time.get_ticks_usec()
			ScatterRegen.run(doc, job)
			if k >= 2:
				var list: PackedFloat64Array = times.get(label, PackedFloat64Array())
				list.append((Time.get_ticks_usec() - t) / 1000.0)
				times[label] = list
			ScatterNative.force_gdscript = false
			if not native_ok:
				continue
			for _r in 5:  # native is ~50x faster: five runs per GDScript run
				t = Time.get_ticks_usec()
				ScatterRegen.run(doc, job)
				var whole := Time.get_ticks_usec() - t
				var packed := ScatterNative.pack(
					doc,
					BIOME,
					species,
					entry.cells_by_species,
					entry.window,
					entry.built,
					entry.cliff,
					PackedFloat32Array()
				)
				var out: Dictionary = ScatterNative._instance().call("generate", packed)
				if k >= 2:
					var whole_list: PackedFloat64Array = native_times.get(
						label, PackedFloat64Array()
					)
					whole_list.append(whole / 1000.0)
					native_times[label] = whole_list
					var inner_list: PackedFloat64Array = inner_times.get(
						label, PackedFloat64Array()
					)
					inner_list.append(int(out.usec) / 1000.0)
					inner_times[label] = inner_list
	var base := _median(times["legacy"])
	if native_ok:
		var native_base := _median(native_times["legacy"])
		var inner_base := _median(inner_times["legacy"])
		for label: String in variants:
			var whole_ms := _median(native_times[label])
			var inner_ms := _median(inner_times[label])
			print(
				(
					(
						"curves job (probe cell, native, median of %d): %-20s job %.3f ms (%+.3f ms,"
						+ " %+.1f%%), library alone %.3f ms (%+.3f ms, %+.1f%%)"
					)
					% [
						runs * 5,
						label,
						whole_ms,
						whole_ms - native_base,
						100.0 * (whole_ms / native_base - 1.0),
						inner_ms,
						inner_ms - inner_base,
						100.0 * (inner_ms / inner_base - 1.0)
					]
				)
			)
	else:
		print("curves job: no native library with the curves capability, native rows skipped")
	for label: String in variants:
		print(
			(
				"curves job (probe cell, GDScript, median of %d): %-20s %.2f ms (%+.2f ms, %+.1f%%)"
				% [
					runs,
					label,
					_median(times[label]),
					_median(times[label]) - base,
					100.0 * (_median(times[label]) / base - 1.0)
				]
			)
		)
	var fields := ScatterGenerator.document_fields(doc, BIOME)
	var ctx := {
		"normal_at": fields.normal_at,
		"height_at": fields.height_at,
		"wet_at": fields.wet_at,
		"water_dist_at": fields.water_dist_at,
	}
	var rule := {
		"key": "bench",
		"kind": "grass",
		"size_class": "small",
		"density_per_m2": 1.0,
		"assets": ["a"],
	}
	var points := PackedVector2Array()
	for i in 20000:
		points.append(Vector2(fmod(i * 0.7, 50.0) - 25.0, fmod(i * 1.3, 50.0) - 25.0))
	for label: String in variants:
		var species_rule := rule.merged(variants[label].duplicate(true), true)
		var plan_entry: Dictionary = ScatterPlan.build(BIOME, [species_rule], 1).species[0]
		var t := Time.get_ticks_usec()
		var sum := 0.0
		for p in points:
			sum += ScatterTerrain.keep(ctx, plan_entry, p, Vector3.ZERO)
		var per_call := 1000.0 * (Time.get_ticks_usec() - t) / points.size()
		print(
			"ScatterTerrain.keep alone: %-20s %.0f ns per call (sum %.1f)" % [label, per_call, sum]
		)
	ScatterNative.force_gdscript = false


func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _min(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[0] if not sorted.is_empty() else 0.0


func _max(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0
