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
			var built := _build(NewMap.create(SIZE_FT, BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, landform))
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
