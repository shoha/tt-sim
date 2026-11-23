extends GutTest
## TerraEditor (card terraform-p2-editor; docs/systems/terraform.md "The editor"): one gesture of
## terrain session edits is one history entry whose undo and redo put the document and every
## derived array back bit for bit; a redo pressed before its undo has landed waits for it; the
## inverse builder and the splice restore ids, order and next_id; with the switch off a map with a
## terrain section refuses every ground tool, naming the switch, and nothing changes, while a map
## without one takes today's routes.

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()


func _rig(switch_on: bool, with_section := true) -> TerraRig:
	TerraCore.switch_override = switch_on
	var rig := await TerraRig.build(self, with_section)
	_rigs.append(rig)
	return rig


func test_undo_and_redo_of_a_gesture_return_every_digest() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig(true)
	assert_true(rig.editor.terra.active(), "the core is active on the corpus map")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the load settles")
	var before := rig.digests()
	var heights_before := rig.doc.heights.duplicate()
	var g := rig.scripted_gesture()
	assert_false(g.is_empty(), "the gesture is recorded")
	assert_eq(rig.history.undo_count(), 1, "one entry for the whole gesture")
	assert_eq((g.edits as Array).size(), 3, "add and its appends fold into one edit")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the gesture lands")
	var after := rig.digests()
	assert_ne(after.doc, before.doc, "the gesture changed the document")
	assert_ne(after.arrays.H2, before.arrays.H2, "and the ground")
	assert_eq(g.doc_digest, after.doc)
	assert_eq(g.digest_before, before.doc)
	assert_eq(g.digests_after, TerraEditor.checked_digests(rig.session()))
	rig.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the undo lands")
	assert_eq(rig.digests(), before, "undo: the document and every derived digest as before")
	assert_eq(rig.doc.heights, heights_before, "undo: the bridged heights as before")
	assert_eq((rig.doc.terra as TerraDoc).next_id, rig.corpus.terra.next_id, "next_id back")
	rig.history.redo()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the redo lands")
	assert_eq(rig.digests(), after, "redo: every digest as after the gesture")
	var fresh := TerraCache.derive_for(rig.doc.terra, rig.doc)
	assert_eq(rig.doc.heights, fresh.call("doc_heights"), "the heights equal a build")


func test_a_redo_before_the_undo_lands_queues() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig(true)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var before := rig.digests()
	rig.scripted_gesture()
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var after := rig.digests()
	var seen: Array = []
	var t := rig.doc.terra as TerraDoc
	var note := func(redo: bool) -> void:
		seen.append([redo, t.digest_for(rig.doc), rig.session().digests()])
	rig.editor.terra.landed.connect(note)
	rig.history.undo()
	assert_false(rig.session().is_ready(), "the undo's derive is in flight")
	rig.history.redo()
	assert_true(rig.editor.terra.has_work(), "the redo waits")
	assert_eq(t.digest_for(rig.doc), before.doc, "the redo's edits are not applied yet")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "both land")
	assert_eq(seen.size(), 2, "two landings")
	if seen.size() == 2:
		assert_eq([seen[0][0], seen[1][0]], [false, true], "the undo lands first, then the redo")
		assert_eq(seen[0][1], before.doc, "the undo landed on the document before the gesture")
		assert_eq(seen[0][2], before.arrays, "with every derived digest as before")
		assert_eq(seen[1][2], after.arrays, "the redo landed on the gesture's digests")
	assert_eq(rig.digests(), after)


func test_the_inverse_builder_and_the_splice_restore_the_document() -> void:
	var c := TerraCorpus.build(TerraRig.CELLS)
	var t := c.terra
	var key := MapTerrainIO.encode(t)
	var hill := t.prims[3]["id"] as int
	var muted := PackedFloat32Array([2, 2, 1, 2, 2])
	var edits: Array[Dictionary] = [
		{"op": "add", "kind": TerraCore.HILL, "data": PackedFloat32Array([0, 0, 2, 3, 2])},
		{"op": "replace", "id": hill, "data": PackedFloat32Array([1, 1, 2, 3, 2])},
		{"op": "mute", "id": hill},
		{"op": "move", "id": hill, "to": 0},
		{"op": "remove", "id": t.prims[5]["id"]},
		{
			"op": "splice",
			"remove": [t.prims[1]["id"], t.prims[7]["id"]],
			"insert": [{"id": t.next_id + 1, "kind": TerraCore.HILL, "flags": 1, "data": muted}],
			"at": 2,
			"next_id": t.next_id + 2,
		},
	]
	var inverse: Array = []
	for change in edits:
		var back := TerraEditor.inverse_of(t, change)
		assert_false(back.is_empty(), "%s has an inverse" % change.op)
		assert_true(_apply(t, change), "%s applies" % change.op)
		inverse = back + inverse
	assert_ne(MapTerrainIO.encode(t), key)
	for change in inverse:
		assert_true(_apply(t, change), "the inverse's %s applies" % change.op)
	assert_eq(MapTerrainIO.encode(t), key, "ids, order, flags, floats and next_id restored")
	assert_false(t.splice([9999], [], 0), "a missing id refuses the splice")
	var taken := {"id": hill, "kind": TerraCore.HILL, "data": PackedFloat32Array([0, 0, 1, 1, 2])}
	assert_false(t.splice([], [taken], 0), "an id in use refuses it")
	assert_false(t.splice([], [], 0, 2), "a next_id at or below a kept id refuses it")
	assert_eq(MapTerrainIO.encode(t), key, "a refused splice changes nothing")


## One edit on a bare document, as TerraSession.apply does it (no derive).
func _apply(t: TerraDoc, change: Dictionary) -> bool:
	match String(change.op):
		"add":
			return t.add(change.kind, change.data) > 0
		"replace":
			return t.replace(change.id, change.data)
		"mute", "unmute":
			t.set_muted(change.id, change.op == "mute")
		"move":
			t.move(change.id, change.to)
		"remove":
			t.remove(change.id)
		"splice":
			return t.splice(change.remove, change.insert, change.at, change.get("next_id", -1))
	return true


func test_switch_off_refuses_every_ground_tool_and_changes_nothing() -> void:
	var made := TerraCore.derives_made
	var rig := await _rig(false)
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var e := rig.editor
	var print_before := MapFingerprint.of(rig.root, rig.doc)
	assert_null(rig.session(), "no session with the switch off")
	assert_false(e.terra.active())
	assert_eq(e.terra.refusal(), TerraEditor.SWITCH_OFF)
	assert_string_contains(TerraEditor.SWITCH_OFF, TerraCore.SWITCH_SETTING, "the toast names it")
	assert_false(e.begin_height_stroke(HeightBrush.RAISE), "Sculpt refused")
	assert_eq(e.terra.last_refusal, TerraEditor.SWITCH_OFF)
	assert_false(e.is_sculpting(), "no HeightStroke began")
	assert_eq(e.surface_refusal("dirt"), TerraEditor.SWITCH_OFF, "Paint's reason")
	assert_false(e.begin_surface_stroke("dirt", false), "Paint refused")
	var line := PackedVector2Array([Vector2(-5, 0), Vector2(5, 0)])
	assert_eq(e.terra.carve_river(line, PackedFloat32Array([1.0]), 1), -1, "River refused")
	assert_false(e.terra.paint_pond_begin(1, Vector3.ZERO), "Pond refused")
	assert_false(e.terra.erase_water_begin(), "Water erase refused")
	assert_false(e.terra.begin_wall_edit(), "Wall refused")
	assert_eq(e.terra.last_refusal, TerraEditor.SWITCH_OFF)
	var water := WaterBrush.new()
	assert_false(water.begin(e, false, Vector3.ZERO), "the Water press")
	assert_eq(water.refusal(), TerraEditor.SWITCH_OFF, "names the switch")
	assert_true(await TerraRig.settle(get_tree(), [rig]))
	var drift := MapFingerprint.diff(print_before, MapFingerprint.of(rig.root, rig.doc))
	assert_eq(drift, [] as Array[String], "nothing changed")
	assert_eq(rig.history.undo_count(), 0, "nothing recorded")
	assert_eq(TerraCore.derives_made, made, "no TerraDerive made")


func test_switch_off_without_a_section_takes_todays_routes() -> void:
	var rig := await _rig(false, false)
	var e := rig.editor
	assert_eq(e.terra.refusal(), "", "nothing to refuse")
	assert_true(e.begin_height_stroke(HeightBrush.RAISE), "Sculpt runs HeightStroke")
	assert_true(e.heights.is_sculpting())
	e.cancel_stroke()
	assert_true(e.terra.begin_wall_edit(), "Wall goes on to WallEditor")
	assert_eq(e.surface_refusal("dirt"), SurfaceStroke.slot_refusal(rig.doc, "dirt"))
	assert_eq(e.terra.landings, 0, "the terrain editor did nothing")


func test_switch_on_routes_refuse_until_their_cards_land() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rig := await _rig(true)
	var e := rig.editor
	assert_eq(e.terra.refusal(), "")
	# Sculpt is on primitives (card terraform-p2-sculpt): its stroke is TerraSculpt's.
	assert_true(e.begin_height_stroke(HeightBrush.RAISE))
	assert_eq(e.terra.last_refusal, "")
	assert_true(e.terra.is_stroking(), "the core's stroke")
	assert_false(e.heights.is_sculpting(), "never today's stroke on a primitives map")
	e.cancel_stroke()
	# Paint is on primitives (card terraform-p2-paint-path): its stroke is TerraPaint's coat.
	assert_true(e.begin_surface_stroke("dirt", false))
	assert_eq(e.terra.last_refusal, "")
	assert_true(e.terra.paint.is_stroking(), "the core's coat")
	e.cancel_stroke()
	# Wall is on primitives (card terraform-p2-walls): its press goes on to WallEditor.
	assert_true(e.terra.begin_wall_edit())
	assert_eq(e.terra.last_refusal, "")
	# Water is on primitives (card terraform-p2-water): a line under 2 m makes nothing, unsaid.
	var line := PackedVector2Array([Vector2.ZERO, Vector2.ONE])
	assert_eq(e.terra.carve_river(line, PackedFloat32Array([1.0]), 1), -1)
	assert_eq(e.terra.last_refusal, "")
	var bridge := rig.session().bridge as TerraBridge
	assert_not_null(bridge._editor, "the bridge's editor is set")
