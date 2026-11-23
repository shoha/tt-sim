extends GutTest
## The other tools' presses and the saves never wait for the ground (card terraform-p2-noblock2;
## docs/systems/terraform.md "The editor"): over the corpus map (TerraRig) with the switch on, a
## structure, a crossing, a settlement, a fire laid and a fire put out, each pressed while a
## river's derive and landing are still in flight, return without finishing any work (the editor
## still has height work, TerraEditor.waits unchanged), and once everything lands the map equals
## the one where the work was finished first and the press made after (GroundPresses queues the
## presses that read the ground; the rest need nothing landed). A save's settle
## (GroundPresses.settle_async) lets the work land over frames: a save taken
## mid-derive writes the same document as one taken after finish_height_work().

const EAST_FLANK := [Vector2(46, 11), Vector2(40, 10.5), Vector2(34, 11), Vector2(29, 12)]
const OVER_RISE := [Vector2(9, 41), Vector2(15, 40), Vector2(21, 40), Vector2(27, 40.5)]
const SAVE_A := "user://_terraform-p2-noblock2_save_a.ttmap"
const SAVE_B := "user://_terraform-p2-noblock2_save_b.ttmap"

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()
	for path in [SAVE_A, SAVE_B]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


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


func _world(rig: TerraRig, x: float, z: float) -> Vector3:
	var p := rig.corpus.at(x, z)
	return rig.editor.to_world(Vector3(p.x, 0.0, p.y))


## Lays the river the crossing spans, the street the settlement dresses and, with `fire`, a fire.
func _ground(rig: TerraRig, fire: bool) -> void:
	assert_gt(_river(rig, EAST_FLANK), 0, "the standing river")
	rig.editor.walls.place(
		Wall.Kind.ROW,
		_world(rig, 8, 24),
		_world(rig, 26, 24),
		-1.0,
		{"seed": 5, "side": 2, "preset": 3}
	)
	if fire:
		_fire(rig, false)


func _fire(rig: TerraRig, put_out: bool) -> bool:
	var e := rig.editor
	var p := _world(rig, 30, 30)
	if not e.begin_fire_stroke(0.0 if put_out else 0.8, put_out):
		return false
	e.stroke_dab(p, p, 3.0, 0.5)
	e.flush()
	return e.end_stroke()


## The press of `kind` (see the header).
func _press(rig: TerraRig, kind: String) -> void:
	var e := rig.editor
	match kind:
		"structure":
			var c := rig.corpus.at(24, 33)
			var plan := PackedVector2Array(
				[c + Vector2(-2, -2), c + Vector2(2, -2), c + Vector2(2, 2), c + Vector2(-2, 2)]
			)
			var lot := e.structures.lot("core:cottage", plan, 100)
			assert_not_null(lot, "a cottage lot")
			if lot != null:
				assert_true(e.structures.add(lot) >= 0, "the cottage is placed")
		"crossing":
			assert_true(
				e.crossings.place(Crossing.Kind.PLANK, _world(rig, 40, 8), _world(rig, 40, 13)) >= 0,
				"the plank bridge is placed (or queued)"
			)
		"settlement":
			var street := -1
			for wall in e.document.walls:
				if wall.is_row():
					street = wall.id
			assert_true(e.settlements.dress(street, "farming_hamlet") >= 0, "the street is dressed")
		"fire":
			assert_true(_fire(rig, false), "fire laid")
		"putout":
			assert_true(_fire(rig, true), "fire put out")


## Presses `kind` on one rig while a river's derive is in flight and on another after
## finish_height_work(), and compares what both leave once everything has landed.
func _check_press(kind: String) -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var queued := await _rig()
	var at_once := await _rig()
	for rig in [queued, at_once]:
		_ground(rig, kind == "putout")
	assert_true(await TerraRig.settle(get_tree(), [queued, at_once]), "the ground stands")
	for rig in [queued, at_once]:
		assert_gt(_river(rig, OVER_RISE), 0, "a river released")
	at_once.editor.finish_height_work()
	var waits := queued.editor.terra.waits
	assert_true(queued.editor.has_height_work(), "the release is in flight")
	_press(queued, kind)
	assert_true(queued.editor.has_height_work(), "the press finished nothing")
	assert_eq(queued.editor.terra.waits, waits, "the press waited for no derive")
	_press(at_once, kind)
	assert_true(await TerraRig.settle(get_tree(), [queued, at_once]), "both idle")
	assert_eq(queued.editor.terra.waits, waits, "nothing waited while landing")
	assert_eq(queued.digests(), at_once.digests(), "the digests")
	assert_eq(queued.doc.heights, at_once.doc.heights, "the heights")
	assert_eq(queued.history.undo_count(), at_once.history.undo_count(), "the history's size")
	assert_eq(queued.history.next_undo_label(), at_once.history.next_undo_label(), "its newest")
	var drift := MapFingerprint.diff(
		MapFingerprint.of(queued.root, queued.doc), MapFingerprint.of(at_once.root, at_once.doc)
	)
	assert_eq(drift, [] as Array[String], "the fingerprints")


## Not yet: a structure press still finishes the work first (StructureEditor._change). Run without
## the wait, its build worker read MapDocument.heights while the landing wrote them (an
## out-of-bounds read in WaterGeometry.ground_at), so it stays blocking until the build reads a
## snapshot.
func test_structure_press_still_finishes_first() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	assert_gt(_river(rig, OVER_RISE), 0, "a river released")
	_press(rig, "structure")
	assert_false(rig.editor.has_height_work(), "the structure press landed the work first")


func test_crossing_press_waits_for_nothing() -> void:
	await _check_press("crossing")


func test_settlement_press_waits_for_nothing() -> void:
	await _check_press("settlement")


func test_fire_lay_waits_for_nothing() -> void:
	await _check_press("fire")


func test_fire_put_out_waits_for_nothing() -> void:
	await _check_press("putout")


## An undo pressed while a press waits runs after it: the press is taken back, as at once.
func test_undo_behind_a_queued_press_takes_it_back() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	_ground(rig, false)
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the ground stands")
	var crossings := rig.doc.crossings.size()
	assert_gt(_river(rig, OVER_RISE), 0, "a river released")
	_press(rig, "crossing")
	assert_true(rig.editor.presses.is_waiting(), "the crossing waits for the ground")
	assert_true(rig.editor.presses.defer(rig.history.undo), "the undo queues behind it")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "idle")
	assert_eq(rig.doc.crossings.size(), crossings, "the crossing was placed and taken back")
	assert_true(rig.history.can_redo(), "its redo is there")


## A save mid-derive (settle_async, frames only) writes the document a save after
## finish_height_work() writes, byte for byte.
func test_save_mid_derive_equals_a_settled_save() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var spread := await _rig()
	var at_once := await _rig()
	for rig in [spread, at_once]:
		assert_gt(_river(rig, OVER_RISE), 0, "a river released")
	var waits := spread.editor.terra.waits
	assert_true(spread.editor.has_height_work(), "in flight")
	var started := Time.get_ticks_usec()
	var frames := Engine.get_process_frames()
	# The rig has no controller stepping it: settle_async's frames step it as the controller would.
	await spread.editor.presses.settle_async(get_tree())
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	gut.p("settle_async: %d frames, %.1f ms" % [Engine.get_process_frames() - frames, ms])
	assert_gt(Engine.get_process_frames(), frames, "the work landed over frames")
	assert_eq(spread.editor.terra.waits, waits, "the save's settle waited for no derive")
	assert_false(spread.editor.has_height_work(), "settled")
	at_once.editor.finish_height_work()
	assert_true(await TerraRig.settle(get_tree(), [spread, at_once]), "both idle")
	assert_eq(MapDocumentIO.write(spread.doc, SAVE_A), OK)
	assert_eq(MapDocumentIO.write(at_once.doc, SAVE_B), OK)
	assert_eq(
		FileAccess.get_file_as_bytes(SAVE_A), FileAccess.get_file_as_bytes(SAVE_B), "the saved bytes"
	)
	assert_false(MapDocumentIO.read(SAVE_A).is_empty(), "the save reads back")
