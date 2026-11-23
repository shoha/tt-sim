extends GutTest
## Today's game never waits for the ground either (card noblock3; docs/systems/terraform.md "Never
## blocking"): with the terraforming core OFF, a structure, a crossing, a settlement, a fire laid
## and a fire put out, each pressed while a river carved on the Water tool's worker is still
## computing or landing (WaterEditor.use_worker), return without landing it (the water edit is
## still working), and once everything lands the map equals the one where the work was finished
## first and the press made after: the heights, the history, MapFingerprint and the saved bytes.
## Card noblock4 adds the Wall tool's edits, a street split and a river pressed behind a river.
## An undo behind the work takes the river back, and a save's settle mid-compute writes the bytes
## of a settled save. A structure build reads a snapshot of the ground that a landing writing the
## document's heights in place leaves alone (the race that kept structures waiting).

const EAST_FLANK := [Vector2(46, 11), Vector2(40, 10.5), Vector2(34, 11), Vector2(29, 12)]
const OVER_RISE := [Vector2(9, 41), Vector2(15, 40), Vector2(21, 40), Vector2(27, 40.5)]
const WEST_RUN := [Vector2(4, 30), Vector2(6, 22), Vector2(5, 14), Vector2(6, 6)]
const SAVE_A := "user://_noblock3_save_a.ttmap"
const SAVE_B := "user://_noblock3_save_b.ttmap"

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
	TerraCore.switch_override = false
	var rig := await TerraRig.build(self, false)
	_rigs.append(rig)
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the map loads")
	return rig


## A river along `pts` (corpus coordinates), on the Water tool's worker with `worker`.
func _river(rig: TerraRig, pts: Array, worker: bool) -> int:
	var line := PackedVector2Array()
	for p: Vector2 in pts:
		var w := _world(rig, p.x, p.y)
		line.append(Vector2(w.x, w.z))
	rig.editor.water.use_worker = worker
	var id := rig.editor.water.carve_river(line, PackedFloat32Array([1.4]), WaterBody.Depth.DEEP)
	rig.editor.water.use_worker = false
	return id


func _world(rig: TerraRig, x: float, z: float) -> Vector3:
	var p := rig.corpus.at(x, z)
	return rig.editor.to_world(Vector3(p.x, 0.0, p.y))


## Lays the river the crossing spans, the street the settlement dresses and, with `fire`, a fire.
func _ground(rig: TerraRig, fire: bool) -> void:
	assert_gt(_river(rig, EAST_FLANK, false), 0, "the standing river")
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
				assert_true(e.structures.add(lot) >= 0, "the cottage is placed (or queued)")
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
		# Card noblock4: the Wall tool's edits, a street split and a river pressed behind a river.
		"wall":
			assert_true(
				e.walls.place(Wall.Kind.STONE, _world(rig, 12, 4), _world(rig, 20, 4)) >= 0,
				"the wall is placed (or queued)"
			)
		"split":
			var row := -1
			for wall in e.document.walls:
				if wall.is_row():
					row = wall.id
			assert_true(e.walls.split_street(row) >= 0, "the street is split (or queued)")
		"river":
			assert_true(_river(rig, WEST_RUN, true) >= 0, "the second river (or queued)")


func _same_map(a: TerraRig, b: TerraRig) -> void:
	assert_eq(a.doc.heights, b.doc.heights, "the heights")
	assert_eq(a.history.undo_count(), b.history.undo_count(), "the history's size")
	assert_eq(a.history.next_undo_label(), b.history.next_undo_label(), "its newest")
	var print_a := MapFingerprint.of(a.root, a.doc)
	var drift := MapFingerprint.diff(print_a, MapFingerprint.of(b.root, b.doc))
	assert_eq(drift, [] as Array[String], "the fingerprints")
	assert_eq(MapDocumentIO.write(a.doc, SAVE_A), OK)
	assert_eq(MapDocumentIO.write(b.doc, SAVE_B), OK)
	assert_eq(
		FileAccess.get_file_as_bytes(SAVE_A), FileAccess.get_file_as_bytes(SAVE_B), "the saved bytes"
	)


## Presses `kind` on one rig while a river carved on the worker is in flight and on another after
## finish_height_work(), and compares what both leave once everything has landed.
func _check_press(kind: String) -> void:
	var queued := await _rig()
	var at_once := await _rig()
	for rig in [queued, at_once]:
		_ground(rig, kind == "putout")
	assert_true(await TerraRig.settle(get_tree(), [queued, at_once]), "the ground stands")
	for rig in [queued, at_once]:
		assert_gt(_river(rig, OVER_RISE, true), 0, "a river computing on the worker")
	at_once.editor.finish_height_work()
	assert_true(queued.editor.water.is_working(), "the release is in flight")
	var started := Time.get_ticks_usec()
	_press(queued, kind)
	gut.p("%s press: %.2f ms" % [kind, (Time.get_ticks_usec() - started) / 1000.0])
	assert_true(queued.editor.water.is_working(), "the press landed nothing")
	_press(at_once, kind)
	assert_true(await TerraRig.settle(get_tree(), [queued, at_once]), "both idle")
	_same_map(queued, at_once)


func test_structure_press_waits_for_nothing() -> void:
	await _check_press("structure")


func test_crossing_press_waits_for_nothing() -> void:
	await _check_press("crossing")


func test_settlement_press_waits_for_nothing() -> void:
	await _check_press("settlement")


func test_fire_lay_waits_for_nothing() -> void:
	await _check_press("fire")


func test_fire_put_out_waits_for_nothing() -> void:
	await _check_press("putout")


func test_wall_press_waits_for_nothing() -> void:
	await _check_press("wall")


func test_street_split_waits_for_nothing() -> void:
	await _check_press("split")


func test_river_behind_a_river_waits_for_nothing() -> void:
	await _check_press("river")


## An undo pressed while the river computes waits for it (GroundPresses.defer) and takes it back,
## as an undo after finish_height_work() does.
func test_undo_behind_the_work_takes_the_river_back() -> void:
	var rig := await _rig()
	var bodies := rig.doc.water_bodies.size()
	var entries := rig.history.undo_count()
	assert_gt(_river(rig, OVER_RISE, true), 0, "a river computing on the worker")
	assert_true(rig.editor.presses.defer(rig.history.undo), "the undo waits behind it")
	assert_true(rig.editor.water.is_working(), "nothing landed at the press")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "idle")
	assert_eq(rig.doc.water_bodies.size(), bodies, "the river was carved and taken back")
	assert_eq(rig.history.undo_count(), entries, "its entry is undone")
	assert_true(rig.history.can_redo(), "its redo is there")


## A save mid-compute (settle_async, frames only) writes the document a save after
## finish_height_work() writes, byte for byte.
func test_save_mid_compute_equals_a_settled_save() -> void:
	var spread := await _rig()
	var at_once := await _rig()
	for rig in [spread, at_once]:
		assert_gt(_river(rig, OVER_RISE, true), 0, "a river computing on the worker")
	assert_true(spread.editor.water.is_working(), "in flight")
	var frames := Engine.get_process_frames()
	await spread.editor.presses.settle_async(get_tree())
	gut.p("settle_async: %d frames" % (Engine.get_process_frames() - frames))
	assert_gt(Engine.get_process_frames(), frames, "the work landed over frames")
	assert_false(spread.editor.has_height_work(), "settled")
	at_once.editor.finish_height_work()
	assert_true(await TerraRig.settle(get_tree(), [spread, at_once]), "both idle")
	_same_map(spread, at_once)


## The race: a structure build reads its ground on a worker while a landing writes the document's
## heights in place (TerraBridge.land writes `doc.heights` row by row). The snapshot taken when the
## build is queued must not see that write: a packed array assigned in GDScript is shared, so a
## snapshot that only assigned the document's arrays read the landing mid-write.
func test_a_build_snapshot_is_not_written_by_a_landing() -> void:
	var doc := MapDocument.create_flat(Vector2i(8, 8), "grass", "v", 3)
	doc.pond_mask.resize(doc.sample_count())
	var ground := StructureGeometry.ground_snapshot(doc)
	var heights_then := ground.heights.duplicate()
	var ponds_then := ground.pond_mask.duplicate()
	# The landing, between the queueing and the worker's read (the forced interleaving).
	var heights := doc.heights
	for i in heights.size():
		heights[i] += 1.5
	var ponds := doc.pond_mask
	for i in ponds.size():
		ponds[i] = 1
	assert_ne(doc.heights, heights_then, "the landing wrote the document")
	assert_eq(ground.heights, heights_then, "the build's heights are as queued")
	assert_eq(ground.pond_mask, ponds_then, "and its pond mask")
