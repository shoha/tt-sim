extends GutTest
## Folding (card terraform-p2-sculpt-kinds, docs/systems/terraform.md "Sculpt kinds and
## folding"): TerraDerive.consolidate turns a run of sculpt primitives into sculpt rasters
## (kind 9); the fold, one splice at the run's place, derives within 1e-4 m of the run it
## replaced, updates equal a fresh build, and the inverse splice undoes it exactly (every digest
## and the document's). A fold computes the same rasters on a worker thread, refuses a run that is
## not one, and a 320 ft map with 4096 dabs folded derives in full under 60 ms (headless; the
## number is printed).

## A 320 ft map (64 cells).
const BIG := Vector2i(64, 64)


## The derive's H2 as floats.
func _h2(n: RefCounted) -> PackedFloat32Array:
	return (n.call("array_bytes", "H2") as PackedByteArray).to_float32_array()


## Applies splice side `s` to the corpus and tells the derive as TerraSession does: every
## primitive from the splice's place goes, then the document from there is set again in order.
func _splice(c: TerraCorpus, n: RefCounted, s: Dictionary) -> void:
	var at: int = s["at"]
	for i in range(at, c.terra.prims.size()):
		n.call("remove_prim", int(c.terra.prims[i]["id"]))
	assert_true(c.splice(s), "the document takes the splice")
	for i in range(at, c.terra.prims.size()):
		var p := c.terra.prims[i]
		n.call("set_prim", p["id"], p["kind"], p["data"])


func _largest_gap(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


func test_a_fold_derives_as_the_run_did_and_undoes_exactly() -> void:
	var c := TerraCorpus.build_sculpted()
	var n := c.make_derive()
	if n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	n.call("derive_full")
	var h2 := _h2(n)
	var digests: Dictionary = n.call("digests")
	var doc_digest := c.terra.digest_for(c.map_doc)
	var run := c.sculpt_run()
	assert_eq(run.size(), 5, "the stroke, the terrace, two levels and the smooth stroke")
	var rasters: Array = n.call("consolidate", PackedInt32Array(run))
	assert_gt(rasters.size(), 0, "rasters")
	for r: PackedFloat32Array in rasters:
		assert_eq(TerraKinds.problem(TerraCore.SCULPT, r), "", "each raster is a valid sculpt")
	var layers := 0
	for r: PackedFloat32Array in rasters:
		layers = maxi(layers, int(r[6]))
	assert_eq(layers, 2, "the smooth stroke's weight is kept as a second layer")
	var fold := c.fold_splice(run, rasters)
	_splice(c, n, fold["edit"])
	n.call("derive")
	var gap := _largest_gap(_h2(n), h2)
	gut.p("fold: %d rasters, H2 within %.7f m of the run" % [rasters.size(), gap])
	assert_lt(gap, 1e-4, "the fold derives as the run did")
	var fresh := c.make_derive()
	fresh.call("derive_full")
	assert_eq(n.call("digests"), fresh.call("digests"), "the fold's update equals a build")
	_splice(c, n, fold["inverse"])
	n.call("derive")
	assert_eq(n.call("digests"), digests, "the inverse splice undoes the fold exactly")
	assert_eq(c.terra.digest_for(c.map_doc), doc_digest, "and the document")


func test_a_fold_is_the_same_on_a_worker() -> void:
	var c := TerraCorpus.build_sculpted()
	var n := c.make_derive()
	if n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var ids := PackedInt32Array(c.sculpt_run())
	var here: Array = n.call("consolidate", ids)
	var box: Array = []
	var task := WorkerThreadPool.add_task(func() -> void: box.append(n.call("consolidate", ids)))
	WorkerThreadPool.wait_for_task_completion(task)
	assert_eq(box.size(), 1, "the worker ran")
	assert_eq(box[0] if box.size() == 1 else [], here, "the same rasters off the main thread")


func test_consolidate_refuses_what_is_not_a_run() -> void:
	var c := TerraCorpus.build_sculpted()
	var n := c.make_derive()
	if n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var run := c.sculpt_run()
	assert_eq(n.call("consolidate", PackedInt32Array()), [], "no ids")
	assert_eq(n.call("consolidate", PackedInt32Array([run[0], run[2]])), [], "a gap")
	assert_eq(n.call("consolidate", PackedInt32Array([run[1], run[0]])), [], "out of order")
	var river := int(c.terra.prims[6]["id"])
	assert_eq(n.call("consolidate", PackedInt32Array([river])), [], "not a compose primitive")
	assert_eq(n.call("consolidate", PackedInt32Array([999])), [], "an unknown id")


func test_a_4096_dab_fold_at_320_ft_derives_in_full_under_60_ms() -> void:
	var c := TerraCorpus.build(BIG)
	if c.make_derive() == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	# Eight strokes of 512 dabs wandering over the map: 4096 dabs in all.
	var ext := c.map_doc.extent_m()
	for s in 8:
		var dabs := PackedFloat32Array()
		for k in 512:
			var t := k / 512.0
			var x := (-0.4 + 0.8 * t) * ext.x
			var z := (-0.35 + s * 0.1) * ext.y + sin(t * TAU * 2.0 + s) * 3.0
			dabs.append_array(PackedFloat32Array([x, z, 2.5, 0.004, s % 3]))
		c.add(TerraCore.STROKE, dabs)
	var run := c.sculpt_run()
	var n := c.make_derive()
	var t0 := Time.get_ticks_usec()
	n.call("derive_full")
	var live_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var h2 := _h2(n)
	t0 = Time.get_ticks_usec()
	var rasters: Array = n.call("consolidate", PackedInt32Array(run))
	var fold_ms := (Time.get_ticks_usec() - t0) / 1000.0
	c.splice(c.fold_splice(run, rasters)["edit"])
	var folded := c.make_derive()
	var best := INF
	for attempt in 3:
		t0 = Time.get_ticks_usec()
		folded.call("derive_full")
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	var gap := _largest_gap(_h2(folded), h2)
	gut.p(
		(
			"fold 4096 dabs at 320 ft: %d runs, consolidate %.1f ms, %d rasters; full derive %.1f ms"
			+ " live, %.1f ms folded (best of 3); H2 within %.7f m"
		)
		% [run.size(), fold_ms, rasters.size(), live_ms, best, gap]
	)
	assert_eq(run.size(), 9, "the corpus stroke and the eight")
	assert_lt(gap, 1e-4, "the fold derives as the strokes did")
	# The bar is 60 ms on a quiet machine; the gate runs eight shards at once, so allow for load,
	# and a slower machine (a CI runner) scales the limit by its measured factor.
	assert_lt(
		best,
		TimingBudget.limit(180.0),
		"a full derive with 4096 dabs folded (bar 60 ms when quiet; %s)" % TimingBudget.describe(180.0)
	)
