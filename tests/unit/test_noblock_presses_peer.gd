extends GutTest
## Presses that queued on the host reach a peer as the host made them (card noblock4; docs/systems/
## terraform.md "Never blocking"). With the terraforming core OFF (today's game), a river is carved
## on the Water tool's worker and, while it computes, a structure, a crossing, a settlement, a
## fire, a wall and a second river are pressed: each waits (GroundPresses) and runs once the river
## has landed. Every history entry the host recorded then crosses as LiveEditCodec bytes into a
## peer's queue, and the peer ends with the host's heights, water, walls, structures and crossings,
## the same MapFingerprint and the same saved bytes.
##
## The edits after the queued ones (a wall and a river pressed behind other work) are the presses
## card noblock4 routed through GroundPresses (WallEditor, WaterEditor.carve_river).

const EAST_FLANK := [Vector2(46, 11), Vector2(40, 10.5), Vector2(34, 11), Vector2(29, 12)]
const OVER_RISE := [Vector2(9, 41), Vector2(15, 40), Vector2(21, 40), Vector2(27, 40.5)]
const WEST_RUN := [Vector2(4, 30), Vector2(6, 22), Vector2(5, 14), Vector2(6, 6)]
const SAVE_HOST := "user://_noblock4_peer_host.ttmap"
const SAVE_PEER := "user://_noblock4_peer_peer.ttmap"

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()
	for path in [SAVE_HOST, SAVE_PEER]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _world(rig: TerraRig, x: float, z: float) -> Vector3:
	var p := rig.corpus.at(x, z)
	return rig.editor.to_world(Vector3(p.x, 0.0, p.y))


func _line(rig: TerraRig, pts: Array) -> PackedVector2Array:
	var line := PackedVector2Array()
	for p: Vector2 in pts:
		var w := _world(rig, p.x, p.y)
		line.append(Vector2(w.x, w.z))
	return line


## Every entry from `from` on, as LiveEditCodec bytes (each part a redo).
func _payloads(rig: TerraRig, from: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for entry: Dictionary in (rig.history.get("_undo") as Array).slice(from):
		var ops := LiveEditCodec.ops_of(entry, rig.editor)
		var parts: int = (entry.get("parts", [entry]) as Array).size()
		assert_eq(ops.size(), parts, "%s: every part an op" % entry.get("label", ""))
		for op in ops:
			out.append(LiveEditCodec.encode(op))
	return out


func test_queued_presses_reach_a_peer_as_the_host_made_them() -> void:
	TerraCore.switch_override = false
	var host := await TerraRig.build(self, false)
	var peer := await TerraRig.build(self, false)
	_rigs.append_array([host, peer])
	assert_true(await TerraRig.settle(get_tree(), [host, peer]), "both load")
	var e := host.editor
	# The standing ground: a river the crossing spans and a street the settlement dresses.
	var start := host.history.undo_count()
	assert_gt(
		e.water.carve_river(
			_line(host, EAST_FLANK), PackedFloat32Array([1.4]), WaterBody.Depth.DEEP
		),
		0,
		"the standing river"
	)
	assert_gt(
		e.walls.place(
			Wall.Kind.ROW,
			_world(host, 8, 24),
			_world(host, 26, 24),
			-1.0,
			{"seed": 5, "side": 2, "preset": 3}
		),
		-1,
		"the street"
	)
	assert_true(await TerraRig.settle(get_tree(), [host]), "the ground stands")
	# A river on the worker, and every press behind it.
	e.water.use_worker = true
	assert_gt(
		e.water.carve_river(_line(host, OVER_RISE), PackedFloat32Array([1.2]), WaterBody.Depth.DEEP),
		0,
		"a river computing on the worker"
	)
	assert_true(e.water.is_working(), "in flight")
	var queued_before := e.presses.queued_count
	var c := host.corpus.at(24, 33)
	var plan := PackedVector2Array(
		[c + Vector2(-2, -2), c + Vector2(2, -2), c + Vector2(2, 2), c + Vector2(-2, 2)]
	)
	var lot := e.structures.lot("core:cottage", plan, 100)
	assert_not_null(lot, "a cottage lot")
	assert_eq(e.structures.add(lot), StructureEditor.QUEUED, "the cottage waits")
	assert_eq(
		e.crossings.place(Crossing.Kind.PLANK, _world(host, 40, 8), _world(host, 40, 13)),
		CrossingEditor.QUEUED,
		"the bridge waits"
	)
	var street := -1
	for wall in host.doc.walls:
		if wall.is_row():
			street = wall.id
	e.settlements.dress(street, "farming_hamlet")
	var p := _world(host, 30, 30)
	assert_true(e.begin_fire_stroke(0.8, false), "fire")
	e.stroke_dab(p, p, 3.0, 0.5)
	e.flush()
	assert_true(e.end_stroke(), "the fire is laid, its entry waits")
	assert_eq(
		e.walls.place(Wall.Kind.STONE, _world(host, 12, 4), _world(host, 20, 4)),
		WallEditor.QUEUED,
		"the wall waits"
	)
	assert_eq(
		e.water.carve_river(_line(host, WEST_RUN), PackedFloat32Array([1.0]), WaterBody.Depth.WAIST),
		WaterEditor.QUEUED,
		"the second river waits"
	)
	assert_true(e.water.is_working(), "nothing landed at the presses")
	assert_eq(e.presses.queued_count - queued_before, 6, "six presses waited")
	assert_true(await TerraRig.settle(get_tree(), [host]), "the host lands everything")
	e.water.use_worker = false
	assert_gt(host.doc.walls.size(), 1, "the street and the wall")
	assert_gt(host.doc.structures.size(), 0, "the cottage")
	assert_gt(host.doc.crossings.size(), 0, "the bridge")
	var queue := LiveEditCodec.Queue.new(peer.editor)
	for bytes in _payloads(host, start):
		assert_eq(queue.push(bytes), "", "the peer reads it")
	assert_true(await TerraRig.settle(get_tree(), [host, peer], queue), "the peer lands them")
	assert_eq(peer.doc.heights, host.doc.heights, "the heights")
	assert_eq(peer.doc.water_bodies.size(), host.doc.water_bodies.size(), "the water")
	assert_eq(peer.doc.walls.size(), host.doc.walls.size(), "the walls")
	assert_eq(peer.doc.structures.size(), host.doc.structures.size(), "the structures")
	assert_eq(peer.doc.crossings.size(), host.doc.crossings.size(), "the crossings")
	var drift := MapFingerprint.diff(
		MapFingerprint.of(host.root, host.doc), MapFingerprint.of(peer.root, peer.doc)
	)
	assert_eq(drift, [] as Array[String], "the fingerprints")
	assert_eq(MapDocumentIO.write(host.doc, SAVE_HOST), OK)
	assert_eq(MapDocumentIO.write(peer.doc, SAVE_PEER), OK)
	assert_eq(
		FileAccess.get_file_as_bytes(SAVE_HOST),
		FileAccess.get_file_as_bytes(SAVE_PEER),
		"the saved bytes"
	)
