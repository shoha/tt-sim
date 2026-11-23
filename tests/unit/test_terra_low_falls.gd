extends GutTest
## A low fall of the terraforming core is a chute (card terraform-p2-chutes; terra_stages.h
## CHUTE_*, WaterFalls.chute_run): a step of FALL_MIN up to CHUTE_MAX_M, which the reaches rule
## gathers on an even slope (the corpus tributary's 1.4 m step on a 0.2 slope, four back to back
## on a 0.15 slope), is carved as a ramp of fast water with no fall record, its banks a grassy slope
## (the face carve cut 74 to 83 degrees beside it). Tall falls keep their records; the bridge draws
## a chute as a riffle over the same run the carve used, with broken white along it.

const CELLS := Vector2i(40, 40)
## The banks beside a chute stay under this (the probe measured 34 to 43 degrees).
const BANK_MAX_DEG := 45.0
## The bank is measured this far past the water's edge (metres).
const BANK_FROM_M := 0.3
const BANK_TO_M := 4.0
## The last metres of a joined river's line are left out: its banks there are the receiver's.
const JOIN_SKIP_M := 2.0

var _doc: MapDocument
var _derive: Object


func before_all() -> void:
	if not TerraCore.native_available():
		return
	var c := TerraCorpus.build(CELLS)
	_doc = c.map_doc
	_derive = TerraCache.derive_for(c.terra, _doc)
	_doc.heights = _derive.call("doc_heights")
	var water := TerraBridge.water_of(_derive, _doc)
	_doc.water_bodies = water["bodies"]
	_doc.pond_mask = water["pond_mask"]


func test_the_corpus_tributary_has_a_chute_and_no_low_fall_record() -> void:
	if _derive == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var r: Dictionary = (_derive.call("water_records") as Dictionary)["rivers"][1]
	var chutes := _chutes(r)
	assert_gt(chutes.size(), 0, "the tributary's 1.4 m step is a chute")
	assert_eq(int(r["falls"]), _tall_steps(r), "only tall steps are fall records")
	assert_gt(int(r["falls"]), 0, "the tributary's fall off the hill is still a fall")
	var falls: PackedFloat32Array = _derive.call("falls")
	for k in range(0, falls.size(), 7):
		assert_gte(falls[k + 4] - falls[k + 5], WaterFalls.CHUTE_MAX_M - 1e-4, "a record is tall")


func test_a_chute_s_banks_stay_under_45_degrees() -> void:
	if _derive == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var r: Dictionary = (_derive.call("water_records") as Dictionary)["rivers"][1]
	var worst := _steepest_bank(_derive, _doc, r)
	gut.p("corpus chute bank: %.1f deg" % worst)
	assert_gt(worst, 0.0, "the chute's banks were measured")
	assert_lt(worst, BANK_MAX_DEG, "the banks beside the chute are a slope, not a wall")


## The carve's level line ("chute") holds the level except down a chute, where it eases from the
## upper level to the lower over WaterFalls.chute_run of arc from the step's shared point.
func test_the_chute_line_ramps_over_the_shared_run() -> void:
	if _derive == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var r: Dictionary = (_derive.call("water_records") as Dictionary)["rivers"][1]
	var lv: PackedFloat32Array = r["level"]
	var line: PackedFloat32Array = r["chute"]
	var s := _arcs(r)
	assert_eq(line.size(), lv.size(), "one chute value per point")
	for c: Dictionary in _chutes(r):
		var k: int = c.k
		var s0 := (s[k - 1] + s[k]) * 0.5
		var run := WaterFalls.chute_run(float(c.drop), float(c.room))
		for j in range(k, lv.size()):
			var x := s[j] - s0
			if x >= run:
				assert_almost_eq(line[j], lv[j], 1e-5, "past the run the line is the level")
				break
			var want := lv[k] + float(c.drop) * (1.0 - smoothstep(0.0, run, x))
			assert_almost_eq(line[j], want, 1e-4, "on the ramp at %.2f m" % x)


## A 0.15 slope steps in four chutes back to back (spike terraform-low-falls-probe): no fall
## records, each chute's line continuous into the next (no jump past a riffle's), banks under 45
## degrees, and every wet sample at one body's level.
func test_back_to_back_chutes_on_a_slope() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 3)
	var terra := TerraDoc.new()
	terra.add(TerraCore.PLANE, PackedFloat32Array([5.0, 0.15, 0.0]))
	var line := PackedVector2Array([Vector2(26.0, 0.0), Vector2(-26.0, 0.0)])
	terra.add(TerraCore.RIVER, TerraWaterTools.river_data(line, PackedFloat32Array([1.4]), 0.6))
	var d := TerraCache.derive_for(terra, doc)
	var r: Dictionary = (d.call("water_records") as Dictionary)["rivers"][0]
	var chutes := _chutes(r)
	gut.p("slope 0.15: %d chutes %s" % [chutes.size(), str(chutes)])
	assert_gte(chutes.size(), 3, "the slope's steps are chutes")
	assert_eq(int(r["falls"]), 0, "no fall records")
	var lv: PackedFloat32Array = r["level"]
	var ramp: PackedFloat32Array = r["chute"]
	for k in range(1, ramp.size()):
		assert_lte(ramp[k - 1] - ramp[k], 0.7 + 1e-4, "the line never steps more than a riffle")
		assert_gte(ramp[k], lv[k] - 1e-6, "the line never stands under the level")
	var worst := _steepest_bank(d, doc, r)
	gut.p("slope 0.15 chute bank: %.1f deg" % worst)
	assert_lt(worst, BANK_MAX_DEG, "the banks beside the chutes are a slope")
	_assert_wet_at_levels(d)


## An edit beside a chute, derived incrementally, gives the bits of a full derive of the result
## (the update path compares the chute line, card terraform-p2-chutes).
func test_update_equals_build_beside_a_chute() -> void:
	if _derive == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var r: Dictionary = (_derive.call("water_records") as Dictionary)["rivers"][1]
	var chutes := _chutes(r)
	if chutes.is_empty():
		return
	var pts: PackedFloat32Array = r["pts"]
	var k: int = chutes[0].k
	var at := Vector2(pts[2 * k], pts[2 * k + 1])
	var c := TerraCorpus.build(CELLS)
	var live := c.make_derive()
	live.call("derive_full")
	# A low mound beside the chute's foot moves the ground the river reads there.
	var bump := PackedFloat32Array([at.x + 4.0, at.y + 3.0, 0.8, 4.0, 1.0])
	live.call("set_prim", 9001, TerraCore.HILL, bump)
	live.call("derive")
	var fresh := c.make_derive()
	fresh.call("set_prim", 9001, TerraCore.HILL, bump)
	fresh.call("derive_full")
	assert_eq(live.call("digests"), fresh.call("digests"), "update equals build")


## The bridge draws a chute as a riffle: the profile's chute run is the carve's, no fall entry,
## and the chute's white is broken lumps (energy varying along it), not one even value.
func test_the_profile_draws_the_chute_with_broken_white() -> void:
	if _derive == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var found := 0
	for chain in RiverProfile.strokes(_doc.water_bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		var profile := RiverProfile.for_doc(_doc, typed)
		for k in profile.chute_runs.size():
			var run := profile.chute_runs[k]
			if run <= 0.0:
				continue
			found += 1
			for fall in profile.falls:
				assert_ne(int(fall.step), k, "a chute is no fall")
			var drop := profile.levels[k] - profile.levels[k + 1]
			assert_lte(run, drop / WaterFalls.CHUTE_SLOPE + 1e-4, "the run is chute_run's")
			var table := WaterFieldStroke.table(profile, typed)
			var en: PackedFloat32Array = table.energy
			var lo := INF
			var hi := 0.0
			var a := ceili((profile.bounds[k] + WaterFieldStroke.CHUTE_IN_M) / 0.05)
			var b := floori((profile.bounds[k] + run) / 0.05)
			for t in range(a, mini(b, en.size() - 1) + 1):
				lo = minf(lo, en[t])
				hi = maxf(hi, en[t])
			gut.p("chute %d: run %.2f m, energy %.2f..%.2f" % [k, run, lo, hi])
			assert_gt(hi, 0.55, "the chute has bold white")
			assert_lte(hi, WaterFieldStroke.CHUTE_WHITE_HI + 1e-4, "never an opaque sheet")
			assert_gt(hi - lo, 0.2, "the white is broken along the chute")
	assert_gt(found, 0, "the corpus tributary has a chute")


## The chute's white stays on the water (card chute-foam): the calm sheet a bank sheds beside the
## corpus chute (spill past the channel, its wash hidden under a few centimetres) holds no white,
## while the channel keeps its white.
func test_the_chute_white_stays_inside_the_water() -> void:
	if _derive == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var f := WaterField.build(_doc)
	var calm := 0
	var white_on_calm := 0
	var channel_hi := 0.0
	for i in f.energy.size():
		if not f.depth[i] > 0.0:
			continue
		if f.calm[i] == 1:
			calm += 1
			if f.energy[i] > 0.0:
				white_on_calm += 1
		else:
			channel_hi = maxf(channel_hi, f.energy[i])
	gut.p("calm %d, with white %d; channel white %.2f" % [calm, white_on_calm, channel_hi])
	assert_gt(calm, 0, "the corpus has bank spill beside its rivers")
	assert_eq(white_on_calm, 0, "no white on the bank's calm sheet")
	assert_gt(channel_hi, 0.5, "the channel keeps its white")


## A crossing of any kind over a chute's run is refused as a fall (owner, 2026-11-23, GAP-C1), and a
## plank just past the run is placed. The 0.15 slope's last chute.
func test_a_crossing_over_a_chute_is_refused() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 3)
	var terra := TerraDoc.new()
	terra.add(TerraCore.PLANE, PackedFloat32Array([5.0, 0.15, 0.0]))
	var line := PackedVector2Array([Vector2(26.0, 0.0), Vector2(-26.0, 0.0)])
	terra.add(TerraCore.RIVER, TerraWaterTools.river_data(line, PackedFloat32Array([1.4]), 0.6))
	var d := TerraCache.derive_for(terra, doc)
	doc.heights = d.call("doc_heights")
	var water := TerraBridge.water_of(d, doc)
	doc.water_bodies = water["bodies"]
	doc.pond_mask = water["pond_mask"]
	var chains := RiverProfile.strokes(doc.water_bodies)
	assert_eq(chains.size(), 1, "one stroke")
	var typed: Array[WaterBody] = []
	typed.assign(chains[0])
	var profile := RiverProfile.for_doc(doc, typed)
	var last := -1
	for k in profile.chute_runs.size():
		if profile.chute_runs[k] > 0.0:
			last = k
	assert_gt(last, -1, "the slope has a chute")
	if last < 0:
		return
	var s0 := profile.bounds[last]
	var run := profile.chute_runs[last]
	for kind in [Crossing.Kind.PLANK, Crossing.Kind.STONES, Crossing.Kind.ARCH, Crossing.Kind.FORD]:
		for share in [0.1, 0.5, 0.9]:
			var placed := _across(doc, profile, s0 + run * share, kind)
			assert_null(placed.crossing, "kind %d at %.1f of the chute is refused" % [kind, share])
	var mid := _across(doc, profile, s0 + run * 0.5, Crossing.Kind.PLANK)
	assert_eq(mid.refusal, CrossingPlacement.REFUSED_FALL, "refused as a fall")
	var past := _across(doc, profile, s0 + run + 1.5, Crossing.Kind.PLANK)
	gut.p("chute run %.2f m; past the run: %s" % [run, str(past.refusal)])
	assert_not_null(past.crossing, "a plank 1.5 m past the chute's run is placed")


## CrossingPlacement.place of `kind` on a line 3 m either side of `profile`'s course at arc `s`.
func _across(doc: MapDocument, profile: RiverProfile, s: float, kind: Crossing.Kind) -> Dictionary:
	var p := profile.point_at(s)
	var dir := (profile.point_at(s + 0.2) - profile.point_at(s - 0.2)).normalized()
	var side := Vector2(-dir.y, dir.x) * 3.0
	return CrossingPlacement.place(doc, p - side, p + side, kind)


## Chutes back to back do not repeat: each of a stroke's chutes draws its own lump length and white
## peak, inside the CHUTE_*_VARY ranges, the same on every call.
func test_back_to_back_chutes_vary_their_white() -> void:
	var lumps := {}
	for seed in [1, 7, 40]:
		for k in 4:
			var s := WaterFieldStroke.chute_shape(seed, k)
			assert_eq(s, WaterFieldStroke.chute_shape(seed, k), "a chute's shape is seeded")
			var lump_lo := WaterFieldStroke.CHUTE_LUMP_M * WaterFieldStroke.CHUTE_LUMP_VARY.x
			var lump_hi := WaterFieldStroke.CHUTE_LUMP_M * WaterFieldStroke.CHUTE_LUMP_VARY.y
			assert_between(s.x, lump_lo - 1e-4, lump_hi + 1e-4, "the lump length is in range")
			var peak_lo := WaterFieldStroke.CHUTE_WHITE_HI * WaterFieldStroke.CHUTE_PEAK_VARY.x
			assert_between(s.y, peak_lo - 1e-4, WaterFieldStroke.CHUTE_WHITE_HI + 1e-4, "peak in range")
			lumps[snappedf(s.x, 0.01)] = true
	assert_gt(lumps.size(), 8, "twelve chutes draw mostly different lump lengths")


## The tall falls stay falls for the bridge (the hilltop crown fall and the tributary's off the
## hill): every profile fall is CHUTE_MAX_M or more.
func test_tall_falls_stay_falls() -> void:
	if _derive == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var tall := 0
	for chain in RiverProfile.strokes(_doc.water_bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		for fall in RiverProfile.for_doc(_doc, typed).falls:
			tall += 1
			assert_gte(float(fall.drop), WaterFalls.CHUTE_MAX_M - 1e-4, "a fall is tall")
	assert_gt(tall, 0, "the corpus keeps its tall fall")


## The chutes of record `r`: {"k" (the step's lower point), "drop", "room" (arc from the step's
## shared point to the next step's, or to the line's end)} each.
func _chutes(r: Dictionary) -> Array[Dictionary]:
	var lv: PackedFloat32Array = r["level"]
	var s := _arcs(r)
	var steps: Array[int] = []
	for k in range(1, lv.size()):
		if lv[k - 1] - lv[k] > 1e-6:
			steps.append(k)
	var out: Array[Dictionary] = []
	for q in steps.size():
		var k := steps[q]
		var drop := lv[k - 1] - lv[k]
		if drop < WaterFalls.FALL_MIN_DROP_M - 1e-4 or drop >= WaterFalls.CHUTE_MAX_M - 1e-4:
			continue
		var s0 := (s[k - 1] + s[k]) * 0.5
		var end := s[-1]
		if q + 1 < steps.size():
			end = (s[steps[q + 1] - 1] + s[steps[q + 1]]) * 0.5
		out.append({"k": k, "drop": drop, "room": end - s0})
	return out


func _tall_steps(r: Dictionary) -> int:
	var lv: PackedFloat32Array = r["level"]
	var n := 0
	for k in range(1, lv.size()):
		n += 1 if lv[k - 1] - lv[k] >= WaterFalls.CHUTE_MAX_M - 1e-4 else 0
	return n


## The arc length of each point of record `r`'s line.
func _arcs(r: Dictionary) -> PackedFloat64Array:
	var pts: PackedFloat32Array = r["pts"]
	var s := PackedFloat64Array([0.0])
	for k in range(1, pts.size() / 2):
		var d := Vector2(pts[2 * k] - pts[2 * k - 2], pts[2 * k + 1] - pts[2 * k - 1]).length()
		s.append(s[-1] + d)
	return s


## The steepest ground (degrees, H2) BANK_FROM_M to BANK_TO_M past the water's edge on either side
## of every point on a chute of record `r` (the derive `d` of document `doc`).
func _steepest_bank(d: Object, doc: MapDocument, r: Dictionary) -> float:
	var h2: PackedFloat32Array = (d.call("array_bytes", "H2") as PackedByteArray).to_float32_array()
	var w := 2 * (doc.samples_x() - 1) + 1
	var h := 2 * (doc.samples_z() - 1) + 1
	var ext := doc.extent_m()
	var step := Vector2(ext.x / (w - 1), ext.y / (h - 1))
	var pts: PackedFloat32Array = r["pts"]
	var s := _arcs(r)
	var hw := float(r["hw"])
	var joined := int(r["recv_river"]) >= 0 or int(r["recv_pond"]) >= 0
	var worst := 0.0
	for c: Dictionary in _chutes(r):
		var k: int = c.k
		var s0 := (s[k - 1] + s[k]) * 0.5
		var run := WaterFalls.chute_run(float(c.drop), float(c.room))
		for j in range(k, s.size() - 1):
			# Near a joined end the banks are the receiver's (the corpus tributary's chute ends 1.5 m
			# from the main river, whose bank 3.8 m off its line stands at 53 degrees).
			if s[j] - s0 > run or (joined and s[-1] - s[j] < JOIN_SKIP_M):
				break
			var p := Vector2(pts[2 * j], pts[2 * j + 1])
			var t := Vector2(pts[2 * j + 2], pts[2 * j + 3]) - p
			var nrm := Vector2(-t.y, t.x).normalized()
			var off := hw + BANK_FROM_M
			while off <= hw + BANK_TO_M:
				for side in [-1.0, 1.0]:
					var q: Vector2 = p + nrm * off * side
					var g := _gradient(h2, w, h, ext, step, q)
					worst = maxf(worst, rad_to_deg(atan(g)))
				off += 0.25
	return worst


## The gradient's magnitude of grid `f` (w x h over `ext`, centred) at world `p`: central
## differences one grid step either side.
func _gradient(
	f: PackedFloat32Array, w: int, h: int, ext: Vector2, step: Vector2, p: Vector2
) -> float:
	var gx := (
		(_bilinear(f, w, h, ext, step, p + Vector2(step.x, 0.0))
		- _bilinear(f, w, h, ext, step, p - Vector2(step.x, 0.0))) / (2.0 * step.x)
	)
	var gz := (
		(_bilinear(f, w, h, ext, step, p + Vector2(0.0, step.y))
		- _bilinear(f, w, h, ext, step, p - Vector2(0.0, step.y))) / (2.0 * step.y)
	)
	return Vector2(gx, gz).length()


func _bilinear(
	f: PackedFloat32Array, w: int, h: int, ext: Vector2, step: Vector2, p: Vector2
) -> float:
	var g := ((p + ext * 0.5) / step).clamp(Vector2.ZERO, Vector2(w - 1.001, h - 1.001))
	var i := floori(g.x)
	var j := floori(g.y)
	var fx := g.x - i
	var fz := g.y - j
	var a := lerpf(f[j * w + i], f[j * w + i + 1], fx)
	var b := lerpf(f[(j + 1) * w + i], f[(j + 1) * w + i + 1], fx)
	return lerpf(a, b, fz)


## Every wet sample of derive `d` (WL over H2) stands at one body's level.
func _assert_wet_at_levels(d: Object) -> void:
	var records: Dictionary = d.call("water_records")
	var levels := {}
	for r: Dictionary in records["rivers"]:
		for v in (r["level"] as PackedFloat32Array):
			levels[v] = true
	for p: Dictionary in records["ponds"]:
		levels[float(p["level"])] = true
	var wl: PackedFloat32Array = (d.call("array_bytes", "WL") as PackedByteArray).to_float32_array()
	var h2: PackedFloat32Array = (d.call("array_bytes", "H2") as PackedByteArray).to_float32_array()
	var wet := 0
	var stray := 0
	for i in wl.size():
		if wl[i] > h2[i]:
			wet += 1
			stray += 0 if levels.has(wl[i]) else 1
	assert_gt(wet, 100, "the river has water")
	assert_eq(stray, 0, "every wet sample stands at one body's level")
