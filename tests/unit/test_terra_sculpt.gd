extends GutTest
## The Sculpt tool on terrain primitives (card terraform-p2-sculpt; docs/systems/terraform.md
## "Tools"): with the core on, every tile and modifier (Raise, Lower, Smooth, Flatten, Tier, Tier
## cut, Terrace, Soften) through AuthoringEditor's stroke routes is one history entry whose undo
## returns the document, every derived digest and the bridged heights, and whose redo returns the
## stroke's; the ground record carries the followers; a session past CONSOLIDATE_DABS folds its
## oldest run inside the stroke's entry, the map's terrain section read back derives to the same
## digests and the fold's undo restores the run; a peer fed the ops as bytes matches; the pure
## parts (fold_run, Soften, the terrace dabs, compact of Soften's replaces) hold their rules.

const TerraceTool := preload("res://utils/terraform/kinds/terrace/terrace_tool.gd")
const StrokeKind := preload("res://utils/terraform/kinds/stroke/stroke_kind.gd")
## How far past a Soften ring the ground may move (metres): the smooth stage's own reach.
const SOFTEN_HALO_M := 1.5

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()


func _rig() -> TerraRig:
	TerraCore.switch_override = true
	var rig := await TerraRig.build(self)
	_rigs.append(rig)
	return rig


## One stroke of op `op` through the editor's routes, as SculptBrush makes it: the press's target,
## `frames` frames of 1/30 s along `path` (map XZ), then the release. True when recorded.
func _stroke(rig: TerraRig, op: int, path: Array, frames := 12, radius := 3.0) -> bool:
	var e := rig.editor
	var at := func(k: int) -> Vector3:
		var t := float(k) / float(frames)
		var a: Vector2 = path[0]
		var b: Vector2 = path[path.size() - 1]
		var p := a.lerp(b, t)
		var w := e.to_world(Vector3(p.x, 0.0, p.y))
		return Vector3(w.x, e.ground_height_at(w), w.z)
	var press: Vector3 = at.call(0)
	var target := 0.0
	if op == HeightBrush.FLATTEN:
		target = press.y
	elif HeightBrush.is_tier(op):
		target = e.tier_target(press, radius, op == HeightBrush.TIER_CUT).y
	if not e.begin_height_stroke(op, target):
		return false
	for k in frames:
		e.stroke_dab(at.call(k), at.call(k + 1), radius, 1.0 / 30.0)
		e.flush()
	return e.end_stroke()


func test_every_tile_and_modifier_is_one_entry_with_exact_undo() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	assert_true(rig.editor.terra.active(), "the core is active")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the load settles")
	var path := [Vector2(14.0, 18.0), Vector2(26.0, 22.0)]
	var ops := [
		HeightBrush.RAISE,
		SculptBrush.sculpt_op(HeightBrush.RAISE, true, false),
		SculptBrush.sculpt_op(HeightBrush.TIER, false, true),
		HeightBrush.FLATTEN,
		HeightBrush.TIER,
		SculptBrush.sculpt_op(HeightBrush.TIER, true, false),
		TerraSculpt.TERRACE,
		TerraSculpt.SOFTEN,
	]
	assert_eq(ops[1], HeightBrush.LOWER, "Ctrl lowers")
	assert_eq(ops[2], HeightBrush.SMOOTH, "Shift smooths any tile")
	assert_eq(ops[5], HeightBrush.TIER_CUT, "Ctrl cuts a tier")
	for op: int in ops:
		var what: String = TerraSculpt.LABELS[op]
		var count := rig.history.undo_count()
		var before := rig.digests()
		var heights := rig.doc.heights.duplicate()
		assert_true(_stroke(rig, op, path), what + ": recorded")
		assert_eq(rig.history.undo_count(), count + 1, what + ": one entry")
		assert_false(rig.editor.is_stroking(), what + ": the stroke ended")
		assert_true(await TerraRig.settle(get_tree(), [rig]), what + ": lands")
		var after := rig.digests()
		assert_ne(after.doc, before.doc, what + ": the document changed")
		assert_ne(after.arrays.H2, before.arrays.H2, what + ": and the ground")
		rig.history.undo()
		assert_true(await TerraRig.settle(get_tree(), [rig]), what + ": the undo lands")
		assert_eq(rig.digests(), before, what + ": undo returns every digest")
		assert_eq(rig.doc.heights, heights, what + ": and the heights")
		rig.history.redo()
		assert_true(await TerraRig.settle(get_tree(), [rig]), what + ": the redo lands")
		assert_eq(rig.digests(), after, what + ": redo returns the stroke's")
	assert_eq(rig.editor.terra.waits, 0, "no press, undo or redo waited for a derive")
	var fresh := TerraCache.derive_for(rig.doc.terra, rig.doc)
	assert_eq(rig.doc.heights, fresh.call("doc_heights"), "the heights equal a build")


func test_the_ground_record_carries_the_followers_and_a_cancel_takes_the_stroke_back() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var entries: Array[Dictionary] = []
	rig.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	assert_true(_stroke(rig, HeightBrush.RAISE, [Vector2(10.0, 10.0), Vector2(16.0, 12.0)]))
	var g: Dictionary = (entries.back().redo as Callable).get_bound_arguments()[0]
	for key in ["props_before", "props_after", "kept", "crossings", "walls", "structures"]:
		assert_true((g.ground as Dictionary).has(key), "the ground record has " + key)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var before := rig.digests()
	var count := rig.history.undo_count()
	var e := rig.editor
	var w := e.to_world(Vector3(18.0, 0.0, 18.0))
	assert_true(e.begin_height_stroke(HeightBrush.RAISE, 0.0))
	for k in 6:
		e.stroke_dab(w, w + Vector3(0.3, 0.0, 0.0), 3.0, 1.0 / 30.0)
		e.flush()
	assert_ne(rig.digests().doc, before.doc, "the held stroke changed the document")
	e.cancel_stroke()
	assert_false(e.is_stroking())
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	assert_eq(rig.history.undo_count(), count, "a cancelled stroke records nothing")
	assert_eq(rig.digests(), before, "and is taken back exactly")


func test_a_long_session_folds_its_oldest_run_and_reloads_equal() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var sculpt := rig.editor.terra.sculpt
	var t := rig.doc.terra as TerraDoc
	var dabs := 0
	var strokes := 0
	# Strokes of about 220 dabs (28 m at radius 0.5: a point every 0.125 m) until a fold.
	while sculpt.folds == 0 and strokes < 40:
		var z := 6.0 + float(strokes % 8) * 3.0
		var count_before := _dabs(t)
		assert_true(_stroke(rig, HeightBrush.RAISE, [Vector2(4.0, z), Vector2(32.0, z)], 30, 0.5))
		dabs += _dabs(t) - count_before
		strokes += 1
		assert_true(await TerraRig.settle(get_tree(), [rig]))
	assert_eq(sculpt.folds, 1, "a fold fired")
	gut.p(
		(
			"fold after %d strokes, %d dabs drawn: %s"
			% [strokes, dabs, str(sculpt.last_fold)]
		)
	)
	assert_gt(int(sculpt.last_fold.dabs), TerraSculpt.CONSOLIDATE_DABS, "past the dab limit")
	var rasters := 0
	for p in t.prims:
		rasters += 1 if int(p["kind"]) == TerraCore.SCULPT else 0
	assert_eq(rasters, int(sculpt.last_fold.rasters), "the rasters are in the document")
	var folded := rig.digests()
	var read: Dictionary = MapTerrainIO.decode(MapTerrainIO.encode(t))
	assert_not_null(read.terra, "the terrain section reads back")
	var reloaded := TerraCache.derive_for(read.terra, rig.doc)
	assert_eq(TerraCache.digests_of(reloaded), folded.arrays, "the reloaded map derives the same")
	rig.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var kinds: Array[int] = []
	for p in t.prims:
		kinds.append(int(p["kind"]))
	assert_false(TerraCore.SCULPT in kinds, "the fold's undo puts the run back")


## Every dab of the document's foldable primitives.
func _dabs(t: TerraDoc) -> int:
	var ids: Array[int] = []
	for p in t.prims:
		if TerraSculpt.FOLDABLE.has(int(p["kind"])):
			ids.append(int(p["id"]))
	return TerraSculpt.dab_count(t, ids)


func test_a_peer_matches_the_sculpt_strokes_through_bytes() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var host := await TerraRig.build(self)
	var peer := await TerraRig.build(self)
	_rigs.append_array([host, peer])
	assert_true(await TerraRig.settle(get_tree(), [host, peer]))
	var entries: Array[Dictionary] = []
	host.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var queue := LiveEditCodec.Queue.new(peer.editor)
	var path := [Vector2(12.0, 14.0), Vector2(22.0, 20.0)]
	for op: int in [HeightBrush.RAISE, HeightBrush.TIER, TerraSculpt.SOFTEN]:
		assert_true(_stroke(host, op, path))
		assert_true(await TerraRig.settle(get_tree(), [host]))
		for o in LiveEditCodec.ops_of(entries.back(), host.editor, false):
			assert_eq(queue.push(LiveEditCodec.encode(o)), "", "the peer reads it")
		assert_true(await TerraRig.settle(get_tree(), [host, peer], queue))
		var what: String = TerraSculpt.LABELS[op]
		assert_eq(peer.digests(), host.digests(), what + ": every digest")
		assert_true(bool(peer.editor.terra.last_check.get("ok", false)), what + ": the check")
		var drift := MapFingerprint.diff(
			MapFingerprint.of(host.root, host.doc), MapFingerprint.of(peer.root, peer.doc)
		)
		assert_eq(drift, [] as Array[String], what + ": the fingerprints")


func test_fold_run_keeps_the_newest_live_and_folds_only_past_the_limit() -> void:
	var t := TerraDoc.new()
	t.add(TerraCore.PLANE, PackedFloat32Array([0.0, 0.0, 0.0]), 0)
	var dab := PackedFloat32Array([1.0, 1.0, 2.0, 0.1, 0.0])
	var big := PackedFloat32Array()
	for i in 300:
		big.append_array(dab)
	var ids: Array[int] = []
	for i in 22:
		ids.append(t.add(TerraCore.STROKE, big, 0))
	# 22 strokes of 300 dabs: the newest 8 stay live, the 14 before hold 4200 > 4096.
	assert_eq(TerraSculpt.fold_run(t), ids.slice(0, 14), "the oldest 14 fold")
	assert_eq(TerraSculpt.fold_run(t, 9), [] as Array[int], "13 x 300 = 3900 is not past the limit")
	var hill := t.add(TerraCore.HILL, PackedFloat32Array([0.0, 0.0, 1.0, 5.0, 2.0]), 0)
	t.move(hill, t.index_of(ids[2]))
	assert_eq(TerraSculpt.fold_run(t), [] as Array[int], "a hill breaks the run: 600 and 3600")
	assert_eq(TerraSculpt.fold_run(t, 8, 3000), ids.slice(2, 14), "the first run past the limit")


func test_soften_scales_drops_and_removes() -> void:
	var stroke := PackedFloat32Array([0.0, 0.0, 2.0, 0.2, 0.0, 10.0, 0.0, 2.0, 0.2, 0.0])
	var out := TerraSoften.frame(
		TerraCore.STROKE, stroke, PackedFloat32Array(), Vector2.ZERO, Vector2.ZERO, 3.0, 0.1
	)
	assert_eq((out.data as PackedFloat32Array).size(), 10, "both dabs kept")
	assert_almost_eq(out.data[3], 0.2 * exp(-TerraSoften.RATE * 0.1), 1e-6, "the centre scales")
	assert_almost_eq(out.data[8], 0.2, 1e-6, "a dab outside the ring keeps its strength")
	var long := TerraSoften.frame(
		TerraCore.STROKE, stroke, out.factors, Vector2.ZERO, Vector2.ZERO, 3.0, 2.0
	)
	assert_eq((long.data as PackedFloat32Array).size(), 5, "the softened dab goes under 5 %")
	var wide := PackedFloat32Array([0.0, 0.0, 4.0, 6.0, 2.0])
	assert_true(
		TerraSoften.frame(
			TerraCore.HILL, wide, PackedFloat32Array(), Vector2.ZERO, Vector2.ZERO, 3.0, 5.0
		).is_empty(),
		"a hill reaching past the ring is never scaled"
	)
	var on_wide := TerraSoften.smooths(
		{"id": 1, "kind": TerraCore.HILL, "flags": 0, "data": wide},
		Rect2(-3, -3, 6, 6),
		Vector2.ZERO,
		Vector2.ZERO,
		3.0
	)
	assert_true(on_wide, "so the ring smooths over it")
	var hill := PackedFloat32Array([0.0, 0.0, 4.0, 2.5, 2.0])
	var h := TerraSoften.frame(
		TerraCore.HILL, hill, PackedFloat32Array(), Vector2.ZERO, Vector2.ZERO, 3.0, 0.1
	)
	assert_lt(float(h.data[2]), 4.0, "a hill wholly inside the ring scales")
	var gone := TerraSoften.frame(
		TerraCore.HILL, hill, h.factors, Vector2.ZERO, Vector2.ZERO, 3.0, 5.0
	)
	assert_eq((gone.data as PackedFloat32Array).size(), 0, "and the hill goes")
	assert_true(
		TerraSoften.frame(
			TerraCore.STROKE, stroke, PackedFloat32Array(), Vector2(50, 50), Vector2(50, 50), 3.0, 1.0
		).is_empty(),
		"a ring that misses changes nothing"
	)


## Round 3's Soften defect: one drag over a mound removed a whole landform hill, and a cliff and a
## waterfall appeared well outside the brush. A Soften drag across the corpus's east hill (radius
## about 6.6 m, far wider than the 2 m ring) keeps every non-sculpt primitive as it was, lays one
## smooth stroke instead, and changes the ground only within the ring plus the smooth's halo.
func test_soften_changes_only_the_ground_under_its_ring() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the load settles")
	var e := rig.editor
	var centre := rig.corpus.at(47.0, 18.0)
	var ends := [Vector2(centre.x - 1.5, centre.y), Vector2(centre.x + 1.5, centre.y)]
	var path := []
	for w: Vector2 in ends:
		path.append(e.to_map_xz(Vector3(w.x, 0.0, w.y)))
	var radius := 2.0
	var kept := func() -> Array:
		var out := []
		for p in (rig.doc.terra as TerraDoc).prims:
			if not int(p["kind"]) in [TerraCore.STROKE, TerraSoften.TERRACE, TerraSoften.LEVEL]:
				out.append([int(p["id"]), int(p["kind"]), p["data"]])
		return out
	var prims_before: Array = kept.call()
	var count := (rig.doc.terra as TerraDoc).prims.size()
	var before := rig.doc.heights.duplicate()
	assert_true(_stroke(rig, TerraSculpt.SOFTEN, path, 12, radius), "the drag is recorded")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "it lands")
	assert_eq(kept.call(), prims_before, "no landform, water or path primitive changed or went")
	var prims := (rig.doc.terra as TerraDoc).prims
	assert_eq(prims.size(), count + 1, "one primitive more")
	assert_eq(int(prims.back()["kind"]), TerraCore.STROKE, "the smooth stroke")
	var data: PackedFloat32Array = prims.back()["data"]
	assert_eq(int(data[4]), StrokeKind.SMOOTH, "in smooth mode")
	var changed := 0
	var farthest := 0.0
	var nx := rig.doc.samples_x()
	for k in before.size():
		if absf(rig.doc.heights[k] - before[k]) <= 1e-5:
			continue
		changed += 1
		var w := rig.doc.sample_to_world(Vector2(k % nx, k / nx))
		var q := Geometry2D.get_closest_point_to_segment(w, ends[0], ends[1])
		farthest = maxf(farthest, w.distance_to(q))
	assert_gt(changed, 0, "the ground under the ring softened")
	assert_lt(farthest, radius + SOFTEN_HALO_M, "nothing outside the ring and its halo moved")
	gut.p("Soften: %d samples changed, the farthest %.2f m from the path" % [changed, farthest])


func test_terrace_dabs_follow_the_path_and_compact_merges_softens() -> void:
	var first := TerraceTool.frame_dabs(Vector2.ZERO, Vector2.ZERO, 4.0, 0.5, Vector2.INF)
	assert_eq((first.data as PackedFloat32Array).size(), 5, "a press is one dab")
	var still := TerraceTool.frame_dabs(Vector2.ZERO, Vector2.ZERO, 4.0, 0.5, first.last)
	assert_eq((still.data as PackedFloat32Array).size(), 0, "a still brush adds nothing")
	var moved := TerraceTool.frame_dabs(Vector2.ZERO, Vector2(4.0, 0.0), 4.0, 0.5, first.last)
	assert_eq((moved.data as PackedFloat32Array).size(), 20, "4 m at 1 m apart: four dabs")
	var a := PackedFloat32Array([1.0])
	var b := PackedFloat32Array([2.0])
	var edits := [
		{"op": "replace", "id": 3, "data": a},
		{"op": "replace", "id": 4, "data": a},
		{"op": "replace", "id": 3, "data": b},
		{"op": "remove", "id": 4},
		{"op": "replace", "id": 3, "data": a},
	]
	var c := TerraEditor.compact(edits)
	assert_eq(c.size(), 4, "the second replace of 3 merged into the first")
	assert_eq(c[0].data, b)
	assert_eq(c[3].data, a, "a replace past a remove stays its own")


## A held Raise of `frames` frames along `path` (map XZ) right after whatever is in flight: each
## frame dabs, flushes, steps the height work and waits a process frame, as a hand's press does.
func _held_raise(rig: TerraRig, path: Array, frames: int) -> bool:
	var e := rig.editor
	if not e.begin_height_stroke(HeightBrush.RAISE, 0.0):
		return false
	for k in frames:
		var a: Vector2 = (path[0] as Vector2).lerp(path[1], float(k) / frames)
		var b: Vector2 = (path[0] as Vector2).lerp(path[1], float(k + 1) / frames)
		e.stroke_dab(e.to_world(Vector3(a.x, 0, a.y)), e.to_world(Vector3(b.x, 0, b.y)), 3.0, 1.0 / 30.0)
		e.flush()
		e.step_height_work()
		await get_tree().process_frame
	return e.end_stroke()


## Card terraform-p2-river-release's spread landing meets a sculpt press: a Raise pressed in the
## frame after a river release lands after the river, in stage order, with no wait (TerraEditor and
## TerraSculpt), and leaves the document, the settled digests and the fingerprint of the same river
## and stroke landed at once.
func test_sculpt_after_a_river_release_lands_in_order_as_at_once() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var spread := await _rig()
	var at_once := await _rig()
	assert_true(await TerraRig.settle(get_tree(), [spread, at_once]), "the loads settle")
	var stages: Array[int] = []
	spread.editor.terra.landed.connect(
		func(_redo: bool) -> void: stages.append(spread.session().settled_stage())
	)
	var waits := spread.editor.terra.waits
	var flank := [Vector2(46, 11), Vector2(40, 10.5), Vector2(34, 11), Vector2(29, 12)]
	var path := [Vector2(14.0, 18.0), Vector2(26.0, 22.0)]
	for rig in [spread, at_once]:
		var line := PackedVector2Array()
		for p: Vector2 in flank:
			line.append(rig.corpus.at(p.x, p.y))
		assert_gt(rig.editor.terra.carve_river(line, PackedFloat32Array([1.4]), 1), 0, "released")
	# Pressed in the release's frame, so the river still derives while the stroke's add is held
	# behind its cut and its appends grow the document's array (the round 3 defect: the held add
	# then told those floats twice).
	assert_true(spread.session().attaching() or not spread.session().is_ready(), "river in flight")
	assert_true(await _held_raise(spread, path, 24), "the stroke pressed after the release")
	at_once.editor.finish_height_work()
	assert_true(await _held_raise(at_once, path, 24), "the at-once stroke")
	at_once.editor.finish_height_work()
	for i in TerraRig.MAX_FRAMES:
		if not spread.busy() and stages.size() == 2:
			break
		spread.editor.step_height_work()
		await get_tree().process_frame
	assert_eq(spread.editor.terra.waits, waits, "no landing waited")
	assert_eq(spread.editor.terra.sculpt.waits, 0, "the stroke never waited to begin")
	assert_eq(stages.size(), 2, "the river and the stroke landed")
	if stages.size() == 2:
		assert_lt(stages[0], stages[1], "in stage order")
	assert_true(await TerraRig.settle(get_tree(), [spread, at_once]), "both idle")
	var sizes := func(rig: TerraRig) -> Array:
		var out := []
		for p in (rig.doc.terra as TerraDoc).prims:
			out.append([int(p["kind"]), (p["data"] as PackedFloat32Array).size()])
		return out
	assert_eq(sizes.call(spread), sizes.call(at_once), "the same primitives")
	assert_eq(
		(spread.doc.terra as TerraDoc).digest_for(spread.doc),
		(at_once.doc.terra as TerraDoc).digest_for(at_once.doc),
		"the terrain section"
	)
	var da: Dictionary = spread.digests().arrays
	var db: Dictionary = at_once.digests().arrays
	for name in db:
		assert_eq(da.get(name), db[name], "settled %s" % name)
	var fresh_a := TerraCache.derive_for(spread.doc.terra, spread.doc)
	var fresh_b := TerraCache.derive_for(at_once.doc.terra, at_once.doc)
	assert_true(
		fresh_a.call("doc_heights") == spread.doc.heights, "spread heights = a fresh derive's"
	)
	assert_true(
		fresh_b.call("doc_heights") == at_once.doc.heights, "at-once heights = a fresh derive's"
	)
	assert_true(spread.doc.heights == at_once.doc.heights, "heights")
	assert_eq(spread.doc.water_bodies.size(), at_once.doc.water_bodies.size(), "water bodies")
	assert_true(spread.doc.pond_mask == at_once.doc.pond_mask, "pond mask")
	var drift := MapFingerprint.diff(
		MapFingerprint.of(spread.root, spread.doc), MapFingerprint.of(at_once.root, at_once.doc)
	)
	assert_eq(drift, [] as Array[String], "the fingerprints")
