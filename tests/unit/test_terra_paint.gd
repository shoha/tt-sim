extends GutTest
## Paint coats against SurfaceStroke (card terraform-p2-paint-path; docs/systems/terraform.md
## "Tools"): the same strokes as SurfaceStroke runs and as paint coats (kind 8) give the same
## surface_weights bytes at the document samples, five surfaces (the fifth drops the weakest) and
## erase coats included; a path's surface is a coat in document order; the table rides in
## prims.bin v2; the Paint tool through the editor is one history entry with exact undo and redo.

const PaintKind := preload("res://utils/terraform/kinds/paint/paint_kind.gd")
const PathKind := preload("res://utils/terraform/kinds/path/path_kind.gd")
const NAMES := ["dirt", "gravel", "cobblestone", "sand", "mud"]

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()


## The strokes: [surface name or "" for erase, [[from, to, radius, seconds] ...]], every value a
## float32, so SurfaceStroke and the coat see the same numbers.
func _strokes() -> Array:
	var a := Vector2(-6.5, -3.25)
	return [
		["dirt", [[a, a + Vector2(9, 2), 2.5, 0.5], [a + Vector2(9, 2), a + Vector2(10, 6), 2.5, 0.25]]],
		["gravel", [[a + Vector2(3, -1), a + Vector2(3, 4), 1.75, 0.5]]],
		["cobblestone", [[a + Vector2(5, 1), a + Vector2(6, 1.5), 2.0, 1.0]]],
		["sand", [[a + Vector2(4, 0.5), a + Vector2(4, 0.5), 3.0, 0.125]]],
		["mud", [[a + Vector2(4.5, 1), a + Vector2(5.5, 2), 2.25, 0.375]]],
		["", [[a + Vector2(7, 2), a + Vector2(9, 3), 1.5, 0.25]]],
		["gravel", [[a + Vector2(8, 4), a + Vector2(2, 3), 2.0, 0.75]]],
	]


func test_coats_equal_surface_stroke_at_the_document_samples() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var c := TerraCorpus.build(Vector2i(TerraCorpus.CELLS, TerraCorpus.CELLS), false)
	var doc := c.map_doc
	doc.surface_ids = PackedStringArray()
	doc.surface_weights = PackedByteArray()
	for s: Array in _strokes():
		var stroke := SurfaceStroke.begin(doc, s[0], s[0] == "")
		var coat := PackedFloat32Array([PaintKind.ERASE_SURFACE])
		if s[0] != "":
			if not c.terra.surfaces.has(s[0]):
				c.terra.surfaces.append(s[0])
			coat[0] = c.terra.surfaces.find(s[0])
		for d: Array in s[1]:
			stroke.dab(d[0], d[1], d[2], d[3])
			coat.append_array(PaintKind.dab(d[0], d[1], d[2], d[3]))
		stroke.finish()
		c.add(TerraCore.PAINT, coat)
	var derive := TerraCache.derive_for(c.terra, doc)
	var planes: PackedByteArray = derive.call("doc_surfaces", Rect2i())
	assert_eq(planes.size(), doc.surface_weights.size(), "the planes are the document's size")
	var differ := 0
	for i in planes.size():
		if planes[i] != doc.surface_weights[i]:
			differ += 1
	assert_eq(differ, 0, "coats equal SurfaceStroke byte for byte")
	assert_eq(c.terra.surfaces, doc.surface_ids, "the table is SurfaceStroke's slot list")
	var five := 0
	var plane := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	for i in doc.sample_count():
		if planes[plane + i * 4 + 3] != 0:
			five += 1
	assert_gt(five, 0, "some samples hold four surfaces")


func test_a_path_paints_its_surface_in_document_order() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var c := TerraCorpus.build(Vector2i(TerraCorpus.CELLS, TerraCorpus.CELLS), false)
	c.terra.surfaces = PackedStringArray(["dirt", "gravel"])
	var line := PackedVector2Array([Vector2(-8, 4), Vector2(8, 5)])
	var coat := PackedFloat32Array([1])
	coat.append_array(PaintKind.dab(Vector2(0, 4.5), Vector2(0, 4.5), 2.0, 2.0))
	c.add(TerraCore.PATH, PathKind.make(1.6, 0, line))
	var over := c.add(TerraCore.PAINT, coat)
	var at := _surface_at(c, Vector2(0, 4.5))
	assert_eq(at, Vector2i(1, 255), "the later coat wins over the path")
	c.terra.remove(over)
	c.terra.prims.insert(0, {"id": over, "kind": TerraCore.PAINT, "flags": 0, "data": coat})
	assert_eq(_surface_at(c, Vector2(0, 4.5)), Vector2i(0, 255), "the later path wins over the coat")
	assert_eq(_surface_at(c, Vector2(-4, 4.25)).x, 0, "the path's surface along its line")


## The strongest entry at document point `p` of `c`'s derive: (surface, weight).
func _surface_at(c: TerraCorpus, p: Vector2) -> Vector2i:
	var doc := c.map_doc
	var derive := TerraCache.derive_for(c.terra, doc)
	var planes: PackedByteArray = derive.call("doc_surfaces", Rect2i())
	var s := Vector2i(doc.world_to_sample(p).round())
	var i := s.y * doc.samples_x() + s.x
	var plane := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	return Vector2i(planes[i * 4], planes[plane + i * 4])


func test_the_surface_table_reads_back() -> void:
	var t := TerraDoc.new()
	t.surfaces = PackedStringArray(["dirt", "gravel"])
	t.add(TerraCore.PAINT, PackedFloat32Array([1, 0, 0, 1, 1, 2.0, 0.5]))
	var read := MapTerrainIO.decode(MapTerrainIO.encode(t))
	var back: TerraDoc = read["terra"]
	assert_not_null(back, "a v2 section reads")
	assert_eq(back.surfaces, t.surfaces, "the table reads back")
	assert_eq(MapTerrainIO.encode(back), MapTerrainIO.encode(t), "bit for bit")
	var v1 := MapTerrainIO.encode(t)
	v1.encode_u16(4, 1)
	assert_null(MapTerrainIO.decode(v1)["terra"], "version 1 is refused")
	t.surfaces.append("dirt")
	assert_ne(t.problem(), "", "a repeated name is refused")


func test_the_paint_tool_is_one_entry_with_exact_undo_and_redo() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var rig := await TerraRig.build(self)
	_rigs.append(rig)
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the load settles")
	var e := rig.editor
	var before := rig.doc.surface_weights.duplicate()
	var ids_before := rig.doc.surface_ids.duplicate()
	var digest_before := (rig.doc.terra as TerraDoc).digest_for(rig.doc)
	var entries := rig.history.undo_count() if rig.history.has_method("undo_count") else -1
	assert_true(e.begin_surface_stroke("cobblestone", false), "the press opens a coat")
	var a := rig.corpus.at(20, 20)
	for k in 6:
		var p := e.to_world(Vector3(a.x + k, 0, a.y))
		e.stroke_dab(p, e.to_world(Vector3(a.x + k + 1, 0, a.y + 0.5)), 2.0, 1.0 / 30.0)
		e.flush()
		await get_tree().process_frame
	assert_true(e.end_stroke(), "the coat changed the ground")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "settles")
	if entries >= 0:
		assert_eq(rig.history.undo_count(), entries + 1, "one history entry")
	assert_true(rig.doc.surface_ids.has("cobblestone"), "the table took the name")
	var painted := rig.doc.surface_weights.duplicate()
	assert_ne(painted, before, "the planes moved")
	_assert_law(rig, "after the stroke")
	rig.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the undo settles")
	assert_eq(rig.doc.surface_ids, ids_before, "undo takes the name back")
	assert_eq((rig.doc.terra as TerraDoc).digest_for(rig.doc), digest_before, "undo: the digest")
	_assert_law(rig, "after the undo")
	rig.history.redo()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the redo settles")
	assert_eq(rig.doc.surface_weights, painted, "redo: the painted bytes")
	assert_true(e.begin_surface_stroke("", true), "Ctrl opens an erase coat")
	var q := e.to_world(Vector3(a.x + 2, 0, a.y))
	for k in 20:
		e.stroke_dab(q, q, 3.0, 0.1)
		e.flush()
	assert_true(e.end_stroke(), "the erase changed the ground")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "settles")
	_assert_law(rig, "after the erase")


## The bridge law for the planes: the document's surfaces are a fresh derive's.
func _assert_law(rig: TerraRig, what: String) -> void:
	var fresh := TerraCache.derive_for(rig.doc.terra, rig.doc)
	assert_eq(rig.doc.surface_ids, (rig.doc.terra as TerraDoc).surfaces, what + ": the table")
	assert_true(
		fresh.call("doc_surfaces", Rect2i()) == rig.doc.surface_weights,
		what + ": the planes are a fresh derive's"
	)
	assert_true(fresh.call("doc_heights") == rig.doc.heights, what + ": the heights too")
