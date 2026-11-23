extends GutTest
## The slope-scaled flat reaches (card terraform-p2-reaches; docs/systems/terraform.md "Flat
## reaches"): a river down a long even slope is a few long pools with riffles or small falls
## between, not a ladder of 0.25 m steps. On uniform slopes the steps keep at least MIN_REACH_M
## apart and their count falls as the band widens; the corpus tributary's fall stays one tall fall;
## a steep flank is one fall at its lip.

## The reach rule's numbers (native/src/terra_stages.h).
const MIN_REACH_M := 6.0
const DEAD_BAND_M := 0.5
const DEAD_BAND_MAX_M := 0.7
const FALL_MIN := 0.75
## The straight river laid down each slope: from x = +26 to -26 m (52 m), 1.4 m half width.
const HALF_LENGTH_M := 26.0


## A 200 ft map on a plane tilted `slope` along x, with one straight river down it (the plane's
## height rises with x, so the river runs from +x to -x).
func _slope_derive(slope: float) -> RefCounted:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 3)
	var terra := TerraDoc.new()
	terra.add(TerraCore.PLANE, PackedFloat32Array([5.0, slope, 0.0]))
	var line := PackedVector2Array([Vector2(HALF_LENGTH_M, 0.0), Vector2(-HALF_LENGTH_M, 0.0)])
	terra.add(TerraCore.RIVER, TerraWaterTools.river_data(line, PackedFloat32Array([1.4]), 0.6))
	return TerraCache.derive_for(terra, doc)


## One river's reaches: {"lengths" (arc metres, downstream), "steps" (metres between them)}.
static func _reaches(r: Dictionary) -> Dictionary:
	var lv: PackedFloat32Array = r["level"]
	var pts: PackedFloat32Array = r["pts"]
	var lengths: Array[float] = []
	var steps: Array[float] = []
	var run := 0.0
	for k in range(1, lv.size()):
		run += Vector2(pts[2 * k] - pts[2 * k - 2], pts[2 * k + 1] - pts[2 * k - 1]).length()
		var step := lv[k - 1] - lv[k]
		if step > 1e-6:
			lengths.append(run)
			steps.append(step)
			run = 0.0
	lengths.append(run)
	return {"lengths": lengths, "steps": steps}


func test_uniform_slopes_step_rarely() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var counts: Array[int] = []
	for slope: float in [0.02, 0.05, 0.1, 0.15, 0.3]:
		var rivers: Array = _slope_derive(slope).call("water_records")["rivers"]
		assert_eq(rivers.size(), 1, "one river on slope %.2f" % slope)
		var got := _reaches(rivers[0])
		var lengths: Array[float] = got["lengths"]
		var steps: Array[float] = got["steps"]
		counts.append(steps.size())
		# The inner reaches (the head and the tail run to the line's ends) are at least the minimum.
		for i in range(1, lengths.size() - 1):
			assert_gte(
				lengths[i], MIN_REACH_M - 0.3, "slope %.2f: reach %d is %.1f m" % [slope, i, lengths[i]]
			)
		# Never more steps than the widest band allows, and riffles at least the band's floor.
		var drop := 2.0 * HALF_LENGTH_M * slope
		var band := clampf(slope * 8.0, DEAD_BAND_M, DEAD_BAND_MAX_M)
		assert_lte(steps.size(), ceili(drop / band), "slope %.2f: %d steps" % [slope, steps.size()])
		for s in steps:
			assert_gte(s, DEAD_BAND_M - 0.051, "slope %.2f: no step under the band (%.2f)" % [slope, s])
		gut.p("slope %.2f: reaches %s, steps %s" % [slope, str(lengths), str(steps)])
	assert_lte(counts[0], 1, "a gentle slope (1 m over 52 m) is at most two reaches")
	assert_lt(counts[2], 10, "a 10% slope steps far less than every 0.25 m (20 steps before)")
	assert_lt(counts[4], counts[2] + 1, "a steep slope groups its drop in fewer, taller steps")


func test_corpus_rivers_are_few_long_reaches() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var n := TerraCorpus.build().make_derive()
	n.call("derive_full")
	var rivers: Array = n.call("water_records")["rivers"]
	var main := _reaches(rivers[0])
	var trib := _reaches(rivers[1])
	var main_steps: Array[float] = main["steps"]
	assert_lte(main_steps.size(), 6, "the main river (61 m) steps at most 6 times (11 before)")
	for s in main_steps:
		assert_lt(s, FALL_MIN, "the main river's steps are riffles")
	var trib_steps: Array[float] = trib["steps"]
	assert_gt(trib_steps.size(), 0, "the tributary steps")
	assert_gte(trib_steps[0], 4.5, "the tributary's fall off the hill stays one tall fall")
	assert_lte(trib_steps.size(), 3, "below its fall the tributary has a step or two, not a ladder")
	assert_eq(int(rivers[1]["falls"]), _count_falls(trib_steps), "every fall-sized step is a record")
	gut.p("corpus: main %s, tributary %s" % [str(main), str(trib)])


## A steep flank: a 5 m hill of 8 m radius (cone-like, profile 1; slope up to about 1) on a gentle
## plane, a river from near its top straight down and away. The flank's drop is one fall at its
## lip, not a stair down its face.
func test_steep_flank_is_one_fall() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 3)
	var terra := TerraDoc.new()
	terra.add(TerraCore.PLANE, PackedFloat32Array([5.0, 0.02, 0.0]))
	terra.add(TerraCore.HILL, PackedFloat32Array([16.0, 0.0, 5.0, 8.0, 1.0]))
	var line := PackedVector2Array([Vector2(15.0, 0.0), Vector2(-26.0, 0.0)])
	terra.add(TerraCore.RIVER, TerraWaterTools.river_data(line, PackedFloat32Array([1.4]), 0.6))
	var d := TerraCache.derive_for(terra, doc)
	var got := _reaches(d.call("water_records")["rivers"][0])
	var steps: Array[float] = got["steps"]
	gut.p("steep flank: %s" % str(got))
	assert_eq(_count_falls(steps), 1, "the hill's flank is one fall")
	assert_lte(steps.size(), 3, "a fall and a riffle or two")


static func _count_falls(steps: Array[float]) -> int:
	var n := 0
	for s in steps:
		n += 1 if s >= FALL_MIN - 1e-4 else 0
	return n
