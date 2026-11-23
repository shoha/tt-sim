extends GutTest
## The Water tool on terrain primitives (card terraform-p2-water; docs/systems/terraform.md
## "Tools"): PondOutline's trace, merge and clip, the river's reach bound and the erase's
## tributary rule (pure), then over the corpus map (TerraRig) with the switch on, through the
## tool's own calls (TerraEditor.carve_river, paint_pond_begin, erase_water_begin and the stroke
## routes): a river down the east hill joins the main river at its level and its steps are falls
## from FALL_MIN and riffles under it; one drawn uphill is flipped; one over a rise is wet along
## its whole line; one past the edge runs on beyond it; a pond painted, extended by a press inside
## it and shrunk by an erase; an erase of the main river takes its tributaries and its carve; one
## history entry per gesture whose undo returns every digest; a peer through bytes matches; two
## releases in one frame never wait.

## The derive's fall threshold (terraform.md "Flat reaches").
const FALL_MIN_M := 0.75
## The derive's smallest riffle, the dead band's floor (native/src/terra_stages.h).
const REACH_DEAD_BAND_M := 0.5
## Layout lines (metres on the corpus's 61 m drawing).
const EAST_FLANK := [Vector2(46, 11), Vector2(40, 10.5), Vector2(34, 11), Vector2(29, 12)]
const OVER_RISE := [Vector2(9, 41), Vector2(15, 40), Vector2(21, 40), Vector2(27, 40.5)]
const PAST_EDGE := [Vector2(53, 24), Vector2(58, 25), Vector2(66, 26)]
const NEW_POND := Vector2(8, 54)
const OLD_POND := Vector2(46, 34)

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
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the corpus map loads")
	return rig


## World XZ of layout points `pts`.
func _line(rig: TerraRig, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(rig.corpus.at(p.x, p.y))
	return out


## A river release through the tool's call (half-width `hw` world metres).
func _river(rig: TerraRig, pts: Array, hw := 1.4) -> int:
	return rig.editor.terra.carve_river(_line(rig, pts), PackedFloat32Array([hw]), 1)


## A pond or erase stroke of dabs along layout points `pts` (radius `r` world metres).
func _stroke(rig: TerraRig, pts: Array, r: float, erase := false) -> bool:
	var first := rig.corpus.at(pts[0].x, pts[0].y)
	var began: bool = (
		rig.editor.terra.erase_water_begin()
		if erase
		else rig.editor.terra.paint_pond_begin(1, Vector3(first.x, 0.0, first.y))
	)
	if not began:
		return false
	var last := Vector3(first.x, 0.0, first.y)
	for p: Vector2 in pts:
		var w := rig.corpus.at(p.x, p.y)
		var at := Vector3(w.x, 0.0, w.y)
		rig.editor.stroke_dab(last, at, r, 0.1)
		last = at
	rig.editor.flush()
	return rig.editor.end_stroke()


## The settled derive's record of river primitive `id`, or {}.
func _record(rig: TerraRig, id: int) -> Dictionary:
	for r: Dictionary in rig.session().settled_derive().call("water_records").rivers:
		if int(r.id) == id:
			return r
	return {}


func _pond_level(rig: TerraRig, id: int) -> float:
	for p: Dictionary in rig.session().settled_derive().call("water_records").ponds:
		if int(p.id) == id:
			return float(p.level)
	return NAN


# ============================================================================
# Pure
# ============================================================================


func test_a_traced_dab_is_its_disc_and_a_ring_fills() -> void:
	var disc := PondOutline.trace(PackedFloat32Array([0, 0, 0, 0, 3.0]))
	var area := PondOutline.area(disc)
	assert_almost_eq(area, PI * 9.0, PI * 9.0 * 0.02, "a dab's outline holds its disc (%.2f)" % area)
	var worst := 0.0
	for p in disc:
		worst = maxf(worst, absf(p.length() - 3.0))
	assert_lt(worst, 0.06, "the edge within the simplify tolerance (%.3f m)" % worst)
	assert_lt(disc.size(), 80, "simplified (%d points)" % disc.size())
	var ring := PackedFloat32Array()
	for k in 24:
		var a := Vector2.RIGHT.rotated(TAU * k / 24.0) * 6.0
		var b := Vector2.RIGHT.rotated(TAU * (k + 1) / 24.0) * 6.0
		ring.append_array([a.x, a.y, b.x, b.y, 1.5])
	var filled := PondOutline.trace(ring)
	assert_gt(PondOutline.area(filled), PI * 7.0 * 7.0 * 0.9, "a ring's hole is filled")
	var bigger := PondOutline.merged(disc, PondOutline.trace(PackedFloat32Array([3, 0, 6, 0, 2])))
	assert_gt(PondOutline.area(bigger), area * 1.3, "merged with a stroke inside it")
	var cut := PondOutline.clipped(disc, PondOutline.trace(PackedFloat32Array([-3, 0, -3, 0, 3])))
	assert_between(PondOutline.area(cut), area * 0.3, area * 0.8, "clipped by an erase")
	assert_true(PondOutline.clipped(disc, filled).is_empty(), "covered whole: nothing left")
	assert_true(PondOutline.trace(PackedFloat32Array()).is_empty())


func test_the_reach_bound_and_the_tributary_rule() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(40, 0)])
	assert_eq(TerraWaterTools.reach_bound(line, PackedFloat32Array([8.0, 0.0])), 21, "by length")
	assert_eq(TerraWaterTools.reach_bound(line, PackedFloat32Array([1.0, 0.0])), 6, "by drop")
	var terra := TerraDoc.new()
	var main := terra.add(TerraCore.RIVER, PackedFloat32Array([2, 0.9, 0, 0, 10, 0]))
	var trib := terra.add(TerraCore.RIVER, PackedFloat32Array([2, 0.9, 5, 9, 5, 1]))
	var twig := terra.add(TerraCore.RIVER, PackedFloat32Array([2, 0.9, 9, 9, 6, 9]))
	var other := terra.add(TerraCore.RIVER, PackedFloat32Array([2, 0.9, 0, 30, 10, 30]))
	var records := [
		{"id": main, "pts": PackedFloat32Array([0, 0, 10, 0]), "hw": 1.0, "recv_river": -1},
		{"id": trib, "pts": PackedFloat32Array([5, 9, 5, 1]), "hw": 1.0, "recv_river": main},
		{"id": twig, "pts": PackedFloat32Array([9, 9, 6, 9]), "hw": 1.0, "recv_river": trib},
		{"id": other, "pts": PackedFloat32Array([0, 30, 10, 30]), "hw": 1.0, "recv_river": -1},
	]
	var dab := PackedFloat32Array([2, 0, 2, 0, 0.5])
	assert_eq(
		TerraWaterTools.erased_rivers(terra, records, dab), [main, trib, twig] as Array[int],
		"the river and every tributary ending in it"
	)
	var on_twig := PackedFloat32Array([8, 9, 8, 9, 0.5])
	assert_eq(TerraWaterTools.erased_rivers(terra, records, on_twig), [twig] as Array[int])


# ============================================================================
# On the corpus map
# ============================================================================


func test_a_river_down_the_flank_joins_and_steps_by_the_rule() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	var entries: Array[Dictionary] = []
	rig.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var before := rig.digests()
	var id := _river(rig, EAST_FLANK)
	assert_gt(id, 0, "the river is added (%s)" % rig.editor.terra.last_refusal)
	assert_true(await TerraRig.settle(get_tree(), [rig]), "it lands")
	assert_eq(entries.size(), 1, "one history entry")
	var r := _record(rig, id)
	var main := rig.prim_of(TerraCore.RIVER, 0)
	assert_eq(int(r.get("recv_river", -1)), main, "it joins the main river")
	var lv: PackedFloat32Array = r.level
	var recv := _record(rig, main)
	var end := Vector2(r.pts[-2], r.pts[-1])
	var at_join := _level_near(recv, end)
	assert_almost_eq(lv[-1], at_join, 0.051, "its end at the receiver's level")
	var small := 0
	var falls := 0
	for i in lv.size() - 1:
		var d := lv[i] - lv[i + 1]
		assert_true(d >= -1e-5, "the water never climbs")
		# The join's last step is the receiver's level, off the lattice; the rest are reach steps.
		if d > 1e-4 and d < REACH_DEAD_BAND_M - 0.051 and i < lv.size() - 2:
			small += 1
		if d >= FALL_MIN_M - 1e-4:
			falls += 1
	assert_eq(int(r.falls), falls, "every step of FALL_MIN or more is a fall, smaller ones riffles")
	assert_eq(small, 0, "no riffle under the dead band: a short flank is a reach or two")
	var bodies := rig.doc.water_bodies.filter(func(b: WaterBody) -> bool: return b.is_river())
	assert_gt(bodies.size(), 2, "its reaches are today's bodies")
	var g: Dictionary = (entries[0].undo as Callable).get_bound_arguments()[0]
	assert_true(bool((g.get("water", {}) as Dictionary).get("landed", false)), "the water side")
	var after := rig.digests()
	rig.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	assert_eq(rig.digests(), before, "undo: every digest as before")
	rig.history.redo()
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	assert_eq(rig.digests(), after, "redo: the river again")
	gut.p("flank river: %d points, %d falls, end %.3f at join %.3f" % [
		lv.size(), falls, lv[-1], at_join])


## The receiver record `r`'s level at its point nearest `p`.
func _level_near(r: Dictionary, p: Vector2) -> float:
	var pts: PackedFloat32Array = r.pts
	var best := INF
	var level := NAN
	for k in range(0, pts.size() - 1, 2):
		var d := p.distance_to(Vector2(pts[k], pts[k + 1]))
		if d < best:
			best = d
			level = (r.level as PackedFloat32Array)[k / 2]
	return level


func test_uphill_flips_a_rise_is_cut_and_the_edge_runs_on() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	var up := EAST_FLANK.duplicate()
	up.reverse()
	var id := _river(rig, up)
	assert_gt(id, 0)
	var rise := _river(rig, OVER_RISE)
	assert_gt(rise, 0)
	var edge := _river(rig, PAST_EDGE)
	assert_gt(edge, 0)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var r := _record(rig, id)
	var hill_end := rig.corpus.at(46, 11)
	var first := Vector2(r.pts[0], r.pts[1])
	assert_lt(first.distance_to(hill_end), 2.0, "drawn uphill, it runs from the hill")
	var s := rig.session()
	var over := _record(rig, rise)
	var pts: PackedFloat32Array = over.pts
	var dry := 0
	var top := -INF
	for k in range(0, pts.size() - 1, 2):
		top = maxf(top, s.height_at(pts[k], pts[k + 1]))
		if s.water_at(pts[k], pts[k + 1]) <= s.height_at(pts[k], pts[k + 1]) + 1e-3:
			dry += 1
	var start_level: float = (over.level as PackedFloat32Array)[0]
	assert_eq(dry, 0, "wet along its whole line: the rise is cut")
	gut.p("over the rise: start level %.2f, highest bed %.2f" % [start_level, top])
	var beyond := 0
	for body in rig.doc.water_bodies:
		beyond += body.beyond.size() + body.beyond_up.size()
	assert_gt(beyond, 0, "the line past the edge runs on into the skirt")


func test_a_pond_is_painted_extended_and_shrunk() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	var entries: Array[Dictionary] = []
	rig.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var terra := rig.doc.terra as TerraDoc
	var ponds := func() -> int:
		return terra.prims.filter(func(p: Dictionary) -> bool: return p.kind == TerraCore.POND).size()
	var count: int = ponds.call()
	assert_true(_stroke(rig, [NEW_POND, NEW_POND + Vector2(4, 0)], 1.8), "a new pond")
	assert_eq(ponds.call(), count + 1, "one pond added")
	var old := rig.prim_of(TerraCore.POND, 0)
	var old_area := PondOutline.area(PondOutline.of_data(terra.find(old).data))
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var level := _pond_level(rig, old)
	assert_true(_stroke(rig, [OLD_POND, OLD_POND + Vector2(8, 0)], 1.5), "a press inside extends")
	assert_eq(ponds.call(), count + 1, "no pond added")
	var grown := PondOutline.area(PondOutline.of_data(terra.find(old).data))
	assert_gt(grown, old_area * 1.05, "the pond grew (%.1f to %.1f m2)" % [old_area, grown])
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var extended := _pond_level(rig, old)
	# The derive solves the level from the new outline's rim alone (no memory of the old level):
	# it may move either way by the rim's change, here within millimetres (terraform.md "Tools").
	var moved := extended - level
	assert_lt(moved, 0.005, "the level re-solves to the new rim (%.4f to %.4f)" % [level, extended])
	var west := OLD_POND - Vector2(3, 0)
	assert_true(_stroke(rig, [west, west + Vector2(0, 1)], 2.0, true), "Ctrl shrinks it")
	var shrunk := PondOutline.area(PondOutline.of_data(terra.find(old).data))
	assert_lt(shrunk, grown * 0.95, "the pond is smaller (%.1f m2)" % shrunk)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var settled := _pond_level(rig, old)
	assert_false(is_nan(settled), "its level settles to the new rim (%.3f)" % settled)
	assert_eq(entries.size(), 3, "one entry per gesture")
	gut.p("pond: %.1f -> %.1f -> %.1f m2, level %.3f -> %.3f -> %.3f" % [
		old_area, grown, shrunk, level, extended, settled])


func test_an_erase_takes_the_tributaries_and_the_carve() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	var joined := _river(rig, EAST_FLANK)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var main := rig.prim_of(TerraCore.RIVER, 0)
	var trib := rig.prim_of(TerraCore.RIVER, 1)
	var s := rig.session()
	var bed := rig.corpus.at(33, 42)
	var carved := s.height_at(bed.x, bed.y)
	var digest_before := rig.digests()
	assert_true(_stroke(rig, [Vector2(33, 42)], 1.0, true), "the erase lands a gesture")
	var terra := rig.doc.terra as TerraDoc
	for id in [main, trib, joined]:
		assert_true(terra.find(id).is_empty(), "river %d is gone" % id)
	assert_false(terra.find(rig.prim_of(TerraCore.POND, 0)).is_empty(), "the pond stays")
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var ground := s.height_at(bed.x, bed.y)
	assert_gt(ground, carved + 0.2, "the carve goes (%.2f to %.2f)" % [carved, ground])
	var rivers := rig.doc.water_bodies.filter(func(b: WaterBody) -> bool: return b.is_river())
	assert_eq(rivers.size(), 0, "no river water left")
	rig.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	assert_eq(rig.digests(), digest_before, "undo: the rivers and their carve again")


func test_a_peer_follows_a_river_and_two_releases_never_wait() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var host := await _rig()
	var peer := await _rig()
	var entries: Array[Dictionary] = []
	host.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var waits := host.editor.terra.waits
	assert_gt(_river(host, EAST_FLANK), 0)
	assert_gt(_river(host, OVER_RISE), 0, "a second release in the same frame")
	assert_eq(host.editor.terra.waits, waits, "neither release waited for a derive")
	assert_false(host.session().is_ready(), "still deriving on return")
	assert_true(await TerraRig.settle(get_tree(), [host]))
	assert_eq(entries.size(), 2)
	var queue := LiveEditCodec.Queue.new(peer.editor)
	for entry in entries:
		for op in LiveEditCodec.ops_of(entry, host.editor, false):
			assert_eq(queue.push(LiveEditCodec.encode(op)), "", "the peer reads it")
	assert_true(await TerraRig.settle(get_tree(), [host, peer], queue), "both land")
	assert_eq(peer.digests(), host.digests(), "the documents and digests")
	assert_true(bool(peer.editor.terra.last_check.get("ok", false)), "the check")
	var drift := MapFingerprint.diff(
		MapFingerprint.of(host.root, host.doc), MapFingerprint.of(peer.root, peer.doc)
	)
	assert_eq(drift, [] as Array[String], "the fingerprints")
