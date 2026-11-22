extends GutTest
## Terrain gestures as live edits (card terraform-p2-editor; docs/systems/terraform.md "The
## editor"): a host and a peer load the same corpus map with the switch on; every gesture, undo and
## redo on the host crosses as bytes (LiveEditCodec "terra": one side's edits, its ground side and
## the host's digests) into the peer's LiveEditCodec.Queue, which applies it through
## TerraEditor.apply_edits. After each the two documents, every checked digest and the two maps'
## MapFingerprints are equal, and the peer's own check agrees. Malformed ops are refused by the
## reader, and a "terra_check" op checks the digests alone.

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()


## A second gesture: mute a hill and move the ridge to the end of the order.
func _mute_and_move(rig: TerraRig) -> void:
	var terra := rig.editor.terra
	terra.begin_gesture()
	terra.edit({"op": "mute", "id": rig.prim_of(TerraCore.HILL, 0)})
	terra.edit({"op": "move", "id": rig.prim_of(TerraCore.RIDGE), "to": 99})
	terra.end_gesture("Mute and move")


func _same(host: TerraRig, peer: TerraRig, what: String) -> void:
	assert_eq(peer.digests().doc, host.digests().doc, what + ": the documents")
	var mine := TerraEditor.checked_digests(peer.session())
	assert_eq(mine, TerraEditor.checked_digests(host.session()), what + ": the digests")
	assert_eq(peer.digests().arrays, host.digests().arrays, what + ": every derived digest")
	assert_true(bool(peer.editor.terra.last_check.get("ok", false)), what + ": the peer's check")
	var drift := MapFingerprint.diff(
		MapFingerprint.of(host.root, host.doc), MapFingerprint.of(peer.root, peer.doc)
	)
	assert_eq(drift, [] as Array[String], what + ": the fingerprints")


func test_a_peer_follows_every_gesture_undo_and_redo_through_bytes() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var host := await TerraRig.build(self)
	var peer := await TerraRig.build(self)
	_rigs.append_array([host, peer])
	assert_true(await TerraRig.settle(get_tree(), [host, peer]), "both load")
	var loaded := MapFingerprint.diff(
		MapFingerprint.of(host.root, host.doc), MapFingerprint.of(peer.root, peer.doc)
	)
	assert_eq(loaded, [] as Array[String], "the two loads agree")
	var entries: Array[Dictionary] = []
	host.history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var queue := LiveEditCodec.Queue.new(peer.editor)
	var steps := [
		["the gesture", func() -> void: host.scripted_gesture(), false, 0],
		["a second gesture", func() -> void: _mute_and_move(host), false, 1],
		["its undo", func() -> void: host.history.undo(), true, 1],
		["the first's undo", func() -> void: host.history.undo(), true, 0],
		["the first's redo", func() -> void: host.history.redo(), false, 0],
	]
	for step: Array in steps:
		var what: String = step[0]
		(step[1] as Callable).call()
		assert_true(await TerraRig.settle(get_tree(), [host]), what + ": the host lands")
		var ops := LiveEditCodec.ops_of(entries[step[3]], host.editor, step[2])
		assert_eq(ops.size(), 1, what + ": one op")
		for op in ops:
			assert_eq(op.kind, "terra")
			assert_eq(op.redo, not step[2], what + ": the side")
			assert_eq(queue.push(LiveEditCodec.encode(op)), "", what + ": the peer reads it")
		assert_true(await TerraRig.settle(get_tree(), [host, peer], queue), what + ": both land")
		_same(host, peer, what)
	var check := LiveEditCodec.terra_check_op(host.editor)
	assert_eq(check.get("kind"), "terra_check")
	assert_eq(queue.push(LiveEditCodec.encode(check)), "", "the check reads")
	assert_true(await TerraRig.settle(get_tree(), [peer], queue))
	assert_true(bool(peer.editor.terra.last_check.get("ok", false)), "the digests alone agree")
	# A peer told other digests reports it, naming the arrays.
	var wrong: Dictionary = check.duplicate(true)
	wrong.args[1]["H2"] = int(wrong.args[1]["H2"]) + 1
	assert_eq(queue.push(LiveEditCodec.encode(wrong)), "")
	assert_true(await TerraRig.settle(get_tree(), [peer], queue))
	assert_eq(peer.editor.terra.last_check.get("arrays"), ["H2"], "a mismatch names H2")
	assert_engine_error(1, "warned once")


func _bytes(kind: String, args: Array, redo := true) -> PackedByteArray:
	return var_to_bytes({"v": LiveEditCodec.VERSION, "kind": kind, "args": args, "redo": redo})


func _terra(edits: Variant, digest: Variant = "", digests: Variant = {}) -> PackedByteArray:
	return _bytes("terra", [edits, {}, digest, digests])


func test_malformed_terrain_ops_are_refused() -> void:
	var doc := MapDocument.create_flat(TerraRig.CELLS, "grass", "v", 3)
	doc.terra = TerraCorpus.build(TerraRig.CELLS).terra
	var hill := PackedFloat32Array([0, 0, 2, 3, 2])
	var good := [{"op": "add", "kind": TerraCore.HILL, "data": hill}, {"op": "remove", "id": 3}]
	var read := LiveEditCodec.decode(_terra(good), doc)
	assert_eq(read.problem, "", "a sound op reads")
	assert_eq((read.op.args[0] as Array).size(), 2)
	var nan := PackedFloat32Array([0, 0, NAN, 3, 2])
	var cases := {
		"an unknown op": _terra([{"op": "explode", "id": 3}]),
		"edits not a list": _terra("edits"),
		"NaN floats": _terra([{"op": "add", "kind": TerraCore.HILL, "data": nan}]),
		"a short hill": _terra([{"op": "add", "kind": TerraCore.HILL, "data": hill.slice(0, 2)}]),
		"an unknown kind": _terra([{"op": "add", "kind": 12, "data": hill}]),
		"a reserved flag": _terra([{"op": "add", "kind": TerraCore.HILL, "flags": 2, "data": hill}]),
		"id 0": _terra([{"op": "replace", "id": 0, "data": hill}]),
		"a float id": _terra([{"op": "remove", "id": 3.0}]),
		"a bad next_id": _terra([{"op": "splice", "remove": [], "insert": [], "next_id": -5}]),
		"a repeated removal": _terra([{"op": "splice", "remove": [3, 3], "insert": []}]),
		"a bad digest": _terra([], "zz"),
		"bad digests": _terra([], "", {1: 2}),
		"a short argument list": _bytes("terra", [[], {}]),
		"a sided check": _bytes("terra_check", ["", {}], false),
	}
	for what: String in cases:
		assert_ne(LiveEditCodec.decode(cases[what], doc).problem, "", what + " is refused")
	var bare := MapDocument.create_flat(TerraRig.CELLS, "grass", "v", 3)
	assert_ne(LiveEditCodec.decode(_terra(good), bare).problem, "", "no section: refused")
	assert_ne(LiveEditCodec.decode(_bytes("terra_check", ["", {}]), bare).problem, "", "check too")
