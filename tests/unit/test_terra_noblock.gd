extends GutTest
## Never blocking (card terraform-p2-noblock; docs/systems/terraform.md "The editor"): with the
## switch on, a wall placed while the pad before it still derives, and an undo or a gesture pressed
## while a landing is pending, never wait for a derive (TerraEditor.waits stays 0, the session is
## still deriving when the call returns). Each landing lands on its own stage, in order, with the
## digests a serial run lands on; the final digests and heights equal a fresh build, and a peer
## following the entries through bytes ends with the same digests and MapFingerprint.

## The longest a press or an undo may take here (ms): the call itself, never a derive's wait.
const CALL_BOUND_MS := 50.0
## The first wall: across the north slope of the corpus's west hill (layout metres).
const WALL_A := [Vector2(10, 9), Vector2(18, 9)]
## The second: across the slope south of it.
const WALL_B := [Vector2(8, 16), Vector2(16, 18)]

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


## Places a stone wall along layout points `line` through the Wall tool's own calls, timed: the
## wall's id and the call's milliseconds.
func _place(rig: TerraRig, line: Array) -> Array:
	var a := rig.corpus.at(line[0].x, line[0].y)
	var b := rig.corpus.at(line[1].x, line[1].y)
	var started := Time.get_ticks_usec()
	assert_true(rig.editor.terra.begin_wall_edit(), "the Wall press goes on")
	var id := rig.editor.walls.place(
		Wall.Kind.STONE, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y)
	)
	return [id, (Time.get_ticks_usec() - started) / 1000.0]


## history.undo(), timed (ms).
func _undo(rig: TerraRig) -> float:
	var started := Time.get_ticks_usec()
	rig.history.undo()
	return (Time.get_ticks_usec() - started) / 1000.0


## Records each landing of `rig`: [redo, the settled digests].
func _watch(rig: TerraRig) -> Array:
	var seen: Array = []
	rig.editor.terra.landed.connect(
		func(redo: bool) -> void: seen.append([redo, rig.session().digests()])
	)
	return seen


## Asserts the call just made with a derive in flight did not wait for it.
func _no_wait(rig: TerraRig, what: String, ms: float) -> void:
	assert_eq(rig.editor.terra.waits, 0, what + ": nothing waited for a derive")
	assert_false(rig.session().is_ready(), what + ": the derive is still in flight")
	# waits == 0 above proves no wait; the time bound scales with a slower machine (a CI runner).
	assert_lt(
		ms,
		TimingBudget.limit(CALL_BOUND_MS),
		what + ": the call took %.2f ms (%s)" % [ms, TimingBudget.describe(CALL_BOUND_MS)]
	)


## The settled digests and heights of `rig` equal a fresh build of its document.
func _fresh(rig: TerraRig, what: String) -> void:
	var fresh := TerraCache.derive_for(rig.doc.terra, rig.doc)
	assert_eq(rig.session().digests(), TerraCache.digests_of(fresh), what + ": a fresh build")
	assert_eq(rig.doc.heights, fresh.call("doc_heights"), what + ": the heights of a build")


## `peer` follows `ops` (LiveEditCodec ops of the host's entries) through bytes; asserts every
## landing's check passed and the documents, digests and fingerprints equal `host`'s.
func _follow(host: TerraRig, peer: TerraRig, ops: Array[Dictionary], what: String) -> void:
	var checks: Array = []
	peer.editor.terra.landed.connect(
		func(_redo: bool) -> void: checks.append(peer.editor.terra.last_check.get("ok", false))
	)
	var queue := LiveEditCodec.Queue.new(peer.editor)
	for op in ops:
		assert_eq(queue.push(LiveEditCodec.encode(op)), "", what + ": the peer reads it")
	assert_true(await TerraRig.settle(get_tree(), [host, peer], queue), what + ": the peer lands")
	assert_false(checks.is_empty(), what + ": the peer landed terrain")
	assert_false(checks.has(false), what + ": every landing matched the host's (%s)" % str(checks))
	assert_eq(peer.digests(), host.digests(), what + ": the peer's documents and digests")
	var drift := MapFingerprint.diff(
		MapFingerprint.of(host.root, host.doc), MapFingerprint.of(peer.root, peer.doc)
	)
	assert_eq(drift, [] as Array[String], what + ": the fingerprints")


func test_two_walls_back_to_back_never_wait_and_land_in_order() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	# The serial run: each wall placed once the one before has landed.
	var serial := await _rig()
	var serial_seen := _watch(serial)
	assert_gt(int(_place(serial, WALL_A)[0]), 0)
	assert_true(await TerraRig.settle(get_tree(), [serial]))
	assert_gt(int(_place(serial, WALL_B)[0]), 0)
	assert_true(await TerraRig.settle(get_tree(), [serial]))
	# Back to back: the second wall in the same frame as the first, its pad still deriving.
	var rig := await _rig()
	var entries: Array[Dictionary] = []
	rig.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var seen := _watch(rig)
	var first := _place(rig, WALL_A)
	assert_gt(int(first[0]), 0, "the first wall is laid")
	assert_false(rig.session().is_ready(), "the first pad derives")
	var second := _place(rig, WALL_B)
	assert_gt(int(second[0]), 0, "the second wall is laid")
	_no_wait(rig, "the second wall", second[1])
	assert_eq(rig.editor.terra.landings, 0, "nothing landed meanwhile")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "both pads land")
	assert_eq(rig.editor.terra.waits, 0, "nothing waited while they landed")
	assert_eq(seen.size(), 2, "one landing per wall")
	assert_eq(seen, serial_seen, "each lands on the digests the serial run landed on")
	assert_eq(rig.digests(), serial.digests(), "the same documents and digests")
	_fresh(rig, "two walls")
	gut.p("place ms: first %.2f, second %.2f" % [first[1], second[1]])
	var peer := await _rig()
	var ops: Array[Dictionary] = []
	for entry in entries:
		ops.append_array(LiveEditCodec.ops_of(entry, rig.editor))
	await _follow(rig, peer, ops, "two walls")


func test_a_gesture_an_undo_and_a_gesture_in_flight_never_wait() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var serial := await _rig()
	var serial_seen := _watch(serial)
	assert_gt(int(_place(serial, WALL_A)[0]), 0)
	assert_true(await TerraRig.settle(get_tree(), [serial]))
	serial.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [serial]))
	assert_gt(int(_place(serial, WALL_B)[0]), 0)
	assert_true(await TerraRig.settle(get_tree(), [serial]))
	var rig := await _rig()
	var before := rig.digests()
	var entries: Array[Dictionary] = []
	rig.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var seen := _watch(rig)
	var first := _place(rig, WALL_A)
	assert_gt(int(first[0]), 0, "the wall is laid")
	assert_false(rig.session().is_ready(), "its pad derives")
	var undo_ms := _undo(rig)
	_no_wait(rig, "the undo", undo_ms)
	assert_true(rig.editor.terra.has_work(), "the undo queues behind the pad")
	assert_eq(rig.doc.walls.size(), 0, "the wall itself is gone at once")
	var second := _place(rig, WALL_B)
	assert_gt(int(second[0]), 0, "the second wall is laid")
	_no_wait(rig, "the gesture after the undo", second[1])
	assert_eq(rig.editor.terra.landings, 0, "nothing landed meanwhile")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "all three land")
	assert_eq(rig.editor.terra.waits, 0, "nothing waited while they landed")
	assert_eq(seen.size(), 3, "the pad, its undo, the second pad")
	var order: Array = seen.map(func(s: Array) -> bool: return s[0])
	assert_eq(order, [true, false, true], "in order")
	if seen.size() == 3:
		assert_eq(seen[1][1], before.arrays, "the undo landed on the digests before the wall")
	assert_eq(seen, serial_seen, "each lands on the digests the serial run landed on")
	assert_eq(rig.digests(), serial.digests(), "the same documents and digests")
	assert_eq(rig.doc.walls.size(), 1, "the second wall alone")
	_fresh(rig, "wall, undo, wall")
	gut.p("ms: place %.2f, undo %.2f, place %.2f" % [first[1], undo_ms, second[1]])
	var peer := await _rig()
	var ops: Array[Dictionary] = []
	ops.append_array(LiveEditCodec.ops_of(entries[0], rig.editor))
	ops.append_array(LiveEditCodec.ops_of(entries[0], rig.editor, true))
	ops.append_array(LiveEditCodec.ops_of(entries[1], rig.editor))
	await _follow(rig, peer, ops, "wall, undo, wall")
