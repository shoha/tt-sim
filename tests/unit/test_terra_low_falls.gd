extends GutTest
## A low fall of the terraforming core (card terraform-p2-river-polish round 3; terra_stages.h
## POOL_OPEN_M and LIP_*, WaterFieldStroke.SOFT_FALL_*): the corpus tributary's 1.4 m step, which
## the reaches rule gathers on an even 0.2 slope. Its banks come down beside the face instead of a
## sheer wall across the bank reach, its face keeps the stream's width (the pool opens below it),
## and the water field draws it as a soft fall while a tall fall keeps its white.

const CELLS := Vector2i(40, 40)

var _doc: MapDocument
var _derive: Object
var _step := {}


func before_all() -> void:
	var c := TerraCorpus.build(CELLS)
	_doc = c.map_doc
	_derive = TerraCache.derive_for(c.terra, _doc)
	_doc.heights = _derive.call("doc_heights")
	var water := TerraBridge.water_of(_derive, _doc)
	_doc.water_bodies = water["bodies"]
	_doc.pond_mask = water["pond_mask"]
	var r: Dictionary = (_derive.call("water_records") as Dictionary)["rivers"][1]
	var lv: PackedFloat32Array = r["level"]
	var pts: PackedFloat32Array = r["pts"]
	for k in range(1, lv.size()):
		var drop := lv[k - 1] - lv[k]
		if drop >= WaterFalls.FALL_MIN_DROP_M and drop < WaterFieldStroke.SOFT_FALL_M:
			var p0 := Vector2(pts[2 * k - 2], pts[2 * k - 1])
			var p1 := Vector2(pts[2 * k], pts[2 * k + 1])
			_step = {
				"k": k,
				"mid": (p0 + p1) * 0.5,
				"t": (p1 - p0).normalized(),
				"hw": float(r["hw"]),
				"hws": r["hws"],
			}
			break


func after_each() -> void:
	TerraCore.switch_override = null


func test_the_corpus_tributary_has_a_low_fall() -> void:
	assert_false(_step.is_empty(), "the tributary keeps its 1.4 m step")


func test_the_banks_beside_a_low_fall_are_no_wall() -> void:
	if _step.is_empty():
		return
	var mid: Vector2 = _step.mid
	var t: Vector2 = _step.t
	var nrm := Vector2(-t.y, t.x)
	var worst := 0.0
	for off in [-4.5, -4.0, -3.5, 3.5, 4.0, 4.5]:
		var above := _h(mid - t * 0.5 + nrm * off)
		var below := _h(mid + t * 0.5 + nrm * off)
		worst = maxf(worst, above - below)
	# Before: the lower reach's bank cut a 1.1 m wall here, a metre of arc across the step.
	assert_lt(worst, 0.5, "the bank beside the face falls %.2f m over a metre of arc" % worst)


func test_the_face_keeps_the_stream_width() -> void:
	if _step.is_empty():
		return
	var hws: PackedFloat32Array = _step.hws
	var k: int = _step.k
	assert_lt(hws[k], float(_step.hw) * 1.1, "the face's foot is the stream's width")
	var widest := 0.0
	for j in range(k, mini(k + 16, hws.size())):
		widest = maxf(widest, hws[j])
	assert_gt(widest, float(_step.hw) * 1.3, "the pool opens below the face")


func test_the_core_s_low_falls_are_soft_and_its_tall_falls_unchanged() -> void:
	var low := 0
	var tall := 0
	for chain in RiverProfile.strokes(_doc.water_bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		var profile := RiverProfile.for_doc(_doc, typed)
		if profile.falls.is_empty():
			continue
		var plain := WaterFieldStroke.table(profile, typed, false)
		var soft := WaterFieldStroke.table(profile, typed, true)
		for fall in profile.falls:
			var a := _peak(plain.core, float(fall.lip), float(fall.foot))
			var b := _peak(soft.core, float(fall.lip), float(fall.foot))
			if float(fall.drop) < WaterFieldStroke.SOFT_FALL_M:
				low += 1
				assert_almost_eq(b, a * WaterFieldStroke.SOFT_FALL_WHITE, 1e-5)
			else:
				tall += 1
				assert_eq(b, a, "a tall fall keeps its white")
	assert_gt(low, 0)
	assert_gt(tall, 0)


func test_the_field_draws_soft_falls_only_with_the_core_on() -> void:
	TerraCore.switch_override = false
	var off := WaterField.build(_doc)
	TerraCore.switch_override = true
	var on := WaterField.build(_doc)
	var lower := 0
	for i in on.energy.size():
		assert_true(on.energy[i] <= off.energy[i] + 1e-6)
		if on.energy[i] < off.energy[i] - 0.05:
			lower += 1
	assert_gt(lower, 0, "the low fall's white is softer with the core on")


func _peak(core: PackedFloat32Array, from: float, to: float) -> float:
	var out := 0.0
	var a := maxi(0, floori(from / WaterFieldStroke.TABLE_STEP))
	var b := mini(core.size() - 1, ceili(to / WaterFieldStroke.TABLE_STEP))
	for t in range(a, b + 1):
		out = maxf(out, core[t])
	return out


func _h(p: Vector2) -> float:
	var s := _doc.world_to_sample(p)
	var x := clampi(roundi(s.x), 0, _doc.samples_x() - 1)
	var z := clampi(roundi(s.y), 0, _doc.samples_z() - 1)
	return _doc.heights[_doc.sample_index(x, z)]
