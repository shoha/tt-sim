extends GutTest
## A river release's landing spread over frames (card terraform-p2-river-release;
## docs/systems/terraform.md "The bridge"): over the corpus map (TerraRig) with the switch on, two
## releases in one frame land through the bridge's worker water conversion, the budgeted height
## queue and TerraEditor's spread apply_ground, in stage order, with no wait; the document they
## leave (heights, water bodies, pond mask, wet dressing), the settled digests and the map's
## fingerprint equal those of the same releases landed at once by finish_height_work().

const EAST_FLANK := [Vector2(46, 11), Vector2(40, 10.5), Vector2(34, 11), Vector2(29, 12)]
const OVER_RISE := [Vector2(9, 41), Vector2(15, 40), Vector2(21, 40), Vector2(27, 40.5)]

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


func _river(rig: TerraRig, pts: Array) -> int:
	var line := PackedVector2Array()
	for p: Vector2 in pts:
		line.append(rig.corpus.at(p.x, p.y))
	return rig.editor.terra.carve_river(line, PackedFloat32Array([1.4]), 1)


## What the landings leave, for the comparison.
func _state(rig: TerraRig) -> Dictionary:
	return {
		"heights": rig.doc.heights,
		"bodies": rig.doc.water_bodies.size(),
		"pond_mask": rig.doc.pond_mask,
		"dressing": rig.doc.water_dressing,
		"digests": rig.digests(),
	}


func test_two_releases_land_spread_in_order_as_at_once() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var spread := await _rig()
	var at_once := await _rig()
	var stages: Array[int] = []
	spread.editor.terra.landed.connect(
		func(_redo: bool) -> void: stages.append(spread.session().settled_stage())
	)
	var waits := spread.editor.terra.waits
	var water_landings := int(spread.session().bridge.get("water_landings"))
	for rig in [spread, at_once]:
		assert_gt(_river(rig, EAST_FLANK), 0, "the first release")
		assert_gt(_river(rig, OVER_RISE), 0, "a second release in the same frame")
	at_once.editor.finish_height_work()
	assert_false(at_once.editor.has_height_work(), "finish_height_work lands everything at once")
	# Spread: frames only; the bridge's water lands from its worker, the ground within budgets.
	var saw_pending := false
	for i in TerraRig.MAX_FRAMES:
		var bridge := spread.session().bridge
		saw_pending = saw_pending or bool(bridge.call("water_pending"))
		if not spread.busy() and stages.size() == 2:
			break
		spread.editor.step_height_work()
		await get_tree().process_frame
	assert_true(saw_pending, "the water conversion ran on its worker")
	assert_eq(spread.editor.terra.waits, waits, "no landing waited for a derive")
	assert_eq(stages.size(), 2, "both releases landed")
	if stages.size() == 2:
		assert_lt(stages[0], stages[1], "in stage order")
	assert_gt(int(spread.session().bridge.get("water_landings")), water_landings, "water landed")
	assert_true(await TerraRig.settle(get_tree(), [spread, at_once]), "both idle")
	var a := _state(spread)
	var b := _state(at_once)
	for key in a:
		assert_eq(a[key], b[key], "%s: spread equals at once" % key)
	var same := 0
	for i in mini(spread.doc.water_bodies.size(), at_once.doc.water_bodies.size()):
		var x := spread.doc.water_bodies[i]
		var y := at_once.doc.water_bodies[i]
		same += 1 if x.id == y.id and TerraWaterBridge.same(x, y) else 0
	assert_eq(same, at_once.doc.water_bodies.size(), "every water body equal")
	var drift := MapFingerprint.diff(
		MapFingerprint.of(spread.root, spread.doc), MapFingerprint.of(at_once.root, at_once.doc)
	)
	assert_eq(drift, [] as Array[String], "the fingerprints")
