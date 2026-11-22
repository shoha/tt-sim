extends GutTest
## Walls on the terraforming core (card terraform-p2-walls; docs/systems/terraform.md "Tools"):
## TerraWallSync mirrors the wall list as wall primitives (stone and fence; a street row adds
## none), and with the switch on every WallEditor edit and its sync's splice are one history
## group. Over the corpus map (TerraRig): a wall across the hill's slope stands on a pad (H2 level
## across its footprint within PAD_TOLERANCE_M), one undo takes the wall and its pad back to the
## digests before, a wall across the river opens there in the derive's walls(), and a peer
## following the group through bytes ends with the same documents, digests and MapFingerprint.

## How level the ground across a wall's footprint must be (metres).
const PAD_TOLERANCE_M := 0.02
## How far off the line the footprint is sampled (inside the stone pad's exact band, half its
## 0.45 m thickness plus 0.15 m, less a sample of bilinear reach).
const ACROSS_M := 0.15
## The hill wall: tangential on the north slope of the corpus's west hill (layout metres).
const HILL_WALL := [Vector2(10, 9), Vector2(18, 9)]
## The river wall: the corpus's own wall line, across the main river.
const RIVER_WALL := [Vector2(22, 36), Vector2(40, 38)]

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


## Places a wall of `kind` along layout points `line` through the Wall tool's own call.
func _place(rig: TerraRig, kind: Wall.Kind, line: Array) -> int:
	var a := rig.corpus.at(line[0].x, line[0].y)
	var b := rig.corpus.at(line[1].x, line[1].y)
	return rig.editor.walls.place(kind, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y))


## The largest step of H2 across `wall`'s footprint (ACROSS_M each side of the line) at stations
## from 10 % to 90 % along it.
func _cross_step(rig: TerraRig, wall: Wall) -> float:
	var s := rig.session()
	var a := wall.points[0]
	var b := wall.points[wall.points.size() - 1]
	var t := (b - a).normalized()
	var n := Vector2(-t.y, t.x) * ACROSS_M
	var worst := 0.0
	for k in range(1, 10):
		var p := a.lerp(b, k / 10.0)
		worst = maxf(worst, absf(s.height_at(p.x + n.x, p.y + n.y) - s.height_at(p.x - n.x, p.y - n.y)))
	return worst


func _make(id: int, kind: Wall.Kind, pts: Array, closed := false) -> Wall:
	return Wall.make(id, kind, PackedVector2Array(pts), closed, 1.1)


func test_the_sync_mirrors_the_wall_list() -> void:
	var doc := MapDocument.create_flat(Vector2i(24, 24), "grass", "v", 3)
	var terra := TerraDoc.new()
	doc.terra = terra
	var hill := terra.add(TerraCore.HILL, PackedFloat32Array([0, 0, 2, 3, 2]))
	var orphan := terra.add(TerraCore.WALL, PackedFloat32Array([1, 0.5, 0, 0, 4, 0]))
	var stone := _make(1, Wall.Kind.STONE, [Vector2(-4, 0), Vector2(4, 1)])
	var row := _make(2, Wall.Kind.ROW, [Vector2(-8, 6), Vector2(8, 6)])
	var fence := _make(3, Wall.Kind.FENCE, [Vector2(0, -6), Vector2(4, -6), Vector2(4, -2)], true)
	doc.walls = [stone, row, fence] as Array[Wall]
	assert_true(TerraWallSync.data_of(row).is_empty(), "a street row makes no primitive")
	var change := TerraWallSync.sync(doc)
	assert_eq(change.get("op"), "splice")
	assert_eq(change.remove, [orphan], "a pad with no wall behind it goes")
	assert_eq((change.insert as Array).size(), 2, "one primitive per stone wall and fence")
	var fence_data: PackedFloat32Array = change.insert[1].data
	assert_almost_eq(fence_data[1], WallGeometry.FENCE_THICKNESS_M, 1e-6, "the fence's footprint")
	assert_eq(fence_data.size(), 2 + 2 * 4, "a closed wall repeats its first point")
	assert_almost_eq(float(change.insert[0].data[1]), WallGeometry.STONE_THICKNESS_M, 1e-6)
	assert_true(terra.splice(change.remove, change.insert, change.at, change.next_id))
	assert_eq(TerraWallSync.sync(doc), {}, "in sync: no edit")
	assert_eq(terra.prims[0].id, hill, "the hill keeps its place")
	var first := int(change.insert[0].id)
	fence.points[1] = Vector2(5, -6)
	var moved := TerraWallSync.sync(doc)
	assert_eq(moved.remove, [int(change.insert[1].id)], "only the moved fence is rebuilt")
	assert_eq(moved.at, terra.index_of(int(change.insert[1].id)), "in its place")
	assert_true(terra.splice(moved.remove, moved.insert, moved.at, moved.next_id))
	assert_eq(terra.index_of(first), 1, "the stone wall is untouched")
	doc.walls = [row] as Array[Wall]
	var bare := TerraWallSync.sync(doc)
	assert_true(terra.splice(bare.remove, bare.insert, bare.at, bare.next_id))
	assert_eq(TerraWallSync.wall_prims(terra).size(), 0, "a row alone leaves no pad")
	doc.terra = null
	assert_eq(TerraWallSync.sync(doc), {}, "no terrain section: nothing to sync")


func test_a_wall_on_a_slope_stands_on_a_pad_and_undo_takes_it_back() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	var entries: Array[Dictionary] = []
	rig.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var before := rig.digests()
	assert_true(rig.editor.terra.begin_wall_edit(), "the Wall press goes on")
	var id := _place(rig, Wall.Kind.STONE, HILL_WALL)
	assert_gt(id, 0, "the wall is laid")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the pad lands")
	var wall := rig.doc.wall(id)
	assert_eq(entries.size(), 1, "one history entry")
	assert_eq((entries[0].get("parts", []) as Array).size(), 2, "the wall and its pad, grouped")
	assert_eq(_terra_parts(entries[0]), 1, "the pad is one terrain gesture")
	var prims := TerraWallSync.wall_prims(rig.doc.terra)
	assert_eq(prims.size(), 1, "one wall primitive: the corpus's own wall had no wall behind it")
	var padded := _cross_step(rig, wall)
	assert_lt(padded, PAD_TOLERANCE_M, "level across the footprint (%.4f m)" % padded)
	var after := rig.digests()
	rig.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the undo lands")
	assert_eq(rig.doc.walls.size(), 0, "the wall is gone")
	assert_eq(rig.digests(), before, "the document and every digest as before")
	var slope := _cross_step(rig, wall)
	assert_gt(slope, 0.1, "the hill's slope is back under the line (%.3f m)" % slope)
	rig.history.redo()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the redo lands")
	assert_eq(rig.digests(), after, "the pad again")
	gut.p("pad: %.4f m across the footprint; the slope there %.3f m" % [padded, slope])


func test_a_river_crossing_opens_the_wall() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	var id := _place(rig, Wall.Kind.STONE, RIVER_WALL)
	assert_gt(id, 0)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var walls: Array = rig.session().settled_derive().call("walls")
	assert_eq(walls.size(), 1, "the placed wall alone")
	var pts: PackedFloat32Array = walls[0]["pts"]
	var gaps := 0
	for k in range(3, pts.size(), 4):
		if pts[k] < 0.5:
			gaps += 1
	assert_gt(gaps, 0, "an opening where the river crosses")
	assert_lt(gaps, pts.size() / 4, "the wall stands elsewhere")
	gut.p("river wall: %d of %d line points open" % [gaps, pts.size() / 4])


func test_a_street_row_adds_no_primitive() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig()
	assert_gt(_place(rig, Wall.Kind.FENCE, HILL_WALL), 0)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var prims := TerraWallSync.wall_prims(rig.doc.terra)
	var digest: String = rig.digests().doc
	var entries: Array[Dictionary] = []
	rig.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var row := rig.editor.walls.place(
		Wall.Kind.ROW, Vector3(-16, 0, 15), Vector3(-6, 0, 15), -1.0, {"seed": 3}
	)
	assert_gt(row, 0, "the row is laid (%s)" % rig.editor.walls.last_refusal)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	assert_eq(TerraWallSync.wall_prims(rig.doc.terra), prims, "the fence's primitive alone")
	assert_eq(rig.digests().doc, digest, "the terrain document is unchanged")
	assert_eq(entries.size(), 1)
	assert_eq(_terra_parts(entries[0]), 0, "a row's entry holds no terrain gesture")


## How many of `entry`'s parts (or the entry itself) are TerraEditor gestures.
func _terra_parts(entry: Dictionary) -> int:
	var count := 0
	for part: Dictionary in entry.get("parts", [entry]):
		var undo: Callable = part.get("undo", Callable())
		if undo.is_valid() and undo.get_method() == &"undo_gesture":
			count += 1
	return count


func test_a_peer_follows_a_wall_and_its_undo() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var host := await _rig()
	var peer := await _rig()
	var entries: Array[Dictionary] = []
	host.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var queue := LiveEditCodec.Queue.new(peer.editor)
	for undo in [false, true]:
		var what := "the undo" if undo else "the wall"
		if undo:
			host.history.undo()
		else:
			assert_gt(_place(host, Wall.Kind.STONE, HILL_WALL), 0)
		assert_true(await TerraRig.settle(get_tree(), [host]), what + ": the host lands")
		var ops := LiveEditCodec.ops_of(entries[0], host.editor, undo)
		var kinds: Array = ops.map(func(op: Dictionary) -> String: return op.kind)
		assert_eq(kinds.size(), 2, what + ": the walls op and the terra op (%s)" % str(kinds))
		for op in ops:
			assert_eq(queue.push(LiveEditCodec.encode(op)), "", what + ": the peer reads it")
		assert_true(await TerraRig.settle(get_tree(), [host, peer], queue), what + ": both land")
		assert_eq(peer.doc.walls.size(), host.doc.walls.size(), what + ": the walls")
		assert_eq(peer.digests(), host.digests(), what + ": the documents and digests")
		assert_true(bool(peer.editor.terra.last_check.get("ok", false)), what + ": the check")
		var drift := MapFingerprint.diff(
			MapFingerprint.of(host.root, host.doc), MapFingerprint.of(peer.root, peer.doc)
		)
		assert_eq(drift, [] as Array[String], what + ": the fingerprints")
