extends GutTest
## TerraDoc (utils/terraform/terra_doc.gd): the primitive list's edits and caps, each built-in
## kind's provisional layout check, the copy-on-write duplicate and the digest (stable for one
## document, moved by one float, the order, a mute or the grid). The section's bytes are in
## test_map_terrain_io.gd.

const GRID := Vector2i(81, 97)
const EXTENT := Vector2(12.192, 14.6304)


func _hill(x := 1.0) -> PackedFloat32Array:
	return PackedFloat32Array([x, 2.0, 3.0, 4.0, 2.0])


func test_edits_keep_order_and_never_reuse_ids() -> void:
	var t := TerraDoc.new()
	var a := t.add(TerraCore.PLANE, PackedFloat32Array([1.0, 0.0, 0.0]))
	var b := t.add(TerraCore.HILL, _hill())
	var c := t.add(TerraCore.STROKE, PackedFloat32Array([0, 0, 1, 0.1, 0]))
	assert_eq([a, b, c], [1, 2, 3])
	assert_true(t.append(c, PackedFloat32Array([1, 1, 1, 0.1, 1])))
	assert_eq((t.find(c)["data"] as PackedFloat32Array).size(), 10)
	assert_true(t.replace(b, _hill(5.0)))
	assert_eq(t.find(b)["data"][0], 5.0)
	t.remove(b)
	assert_eq(t.index_of(b), -1)
	assert_eq(t.add(TerraCore.HILL, _hill()), 4, "a removed id is not reused")
	t.move(4, 0)
	assert_eq(int(t.prims[0]["id"]), 4, "moved to the front of the order")
	t.set_muted(a, true)
	assert_true(TerraDoc.is_muted(t.find(a)))
	t.set_muted(a, false)
	assert_false(TerraDoc.is_muted(t.find(a)))
	assert_false(t.append(99, PackedFloat32Array([1])), "no primitive 99")
	assert_eq(t.problem(), "")


func test_the_caps_refuse_an_edit() -> void:
	var t := TerraDoc.new()
	for i in MapDocument.MAX_TERRA_PRIMS:
		t.add(TerraCore.PLANE, PackedFloat32Array([0.0, 0.0, 0.0]))
	assert_eq(t.add(TerraCore.PLANE, PackedFloat32Array([0.0, 0.0, 0.0])), -1, "prim cap")
	assert_eq(t.prims.size(), MapDocument.MAX_TERRA_PRIMS)
	var big := PackedFloat32Array()
	big.resize(MapDocument.MAX_TERRA_FLOATS_PER_PRIM)
	var u := TerraDoc.new()
	var id := u.add(TerraCore.STROKE, big)
	assert_gt(id, 0)
	assert_false(u.append(id, PackedFloat32Array([0, 0, 1, 1, 0])), "per-primitive cap")
	assert_eq(u.add(TerraCore.STROKE, big + PackedFloat32Array([0])), -1)
	var per := 16
	assert_eq(MapDocument.MAX_TERRA_FLOATS, per * MapDocument.MAX_TERRA_FLOATS_PER_PRIM)
	for i in per - 1:
		assert_gt(u.add(TerraCore.STROKE, big), 0)
	assert_eq(u.float_count(), MapDocument.MAX_TERRA_FLOATS)
	assert_eq(u.add(TerraCore.PLANE, PackedFloat32Array([0.0, 0.0, 0.0])), -1, "float cap")
	assert_false(u.replace(id, big + PackedFloat32Array([0])), "replace past the cap")


func test_problem_names_ids_flags_and_bad_primitives() -> void:
	var t := TerraDoc.new()
	t.add(TerraCore.HILL, _hill())
	t.prims[0]["flags"] = 2
	assert_string_contains(t.problem(), "reserved flag")
	t.prims[0]["flags"] = 0
	t.prims.append(t.prims[0].duplicate(true))
	assert_string_contains(t.problem(), "repeated")
	t.prims.pop_back()
	t.prims[0]["id"] = 5
	assert_string_contains(t.problem(), "out of range")
	t.prims[0]["id"] = 1
	t.prims[0]["data"] = PackedFloat32Array([NAN, 2.0, 3.0, 4.0, 2.0])
	assert_string_contains(t.problem(), "NaN")


func test_duplicate_is_copy_on_write() -> void:
	var t := TerraCorpus.build().terra
	var before := MapTerrainIO.encode(t)
	var copy := t.duplicate()
	var stroke := -1
	for p in t.prims:
		if p["kind"] == TerraCore.STROKE:
			stroke = p["id"]
	t.append(stroke, PackedFloat32Array([0, 0, 1, 0.2, 0]))
	(t.prims[1]["data"] as PackedFloat32Array).set(0, 123.0)
	t.replace(t.prims[2]["id"], _hill(9.0))
	t.set_muted(t.prims[3]["id"], true)
	t.remove(t.prims[4]["id"])
	t.add(TerraCore.HILL, _hill())
	t.move(t.prims[0]["id"], 5)
	assert_eq(MapTerrainIO.encode(copy), before, "no edit of the original reaches the copy")
	copy.append(stroke, PackedFloat32Array([0, 0, 1, 0.2, 0]))
	assert_eq(t.find(stroke)["data"].size(), copy.find(stroke)["data"].size())
	copy.append(stroke, PackedFloat32Array([0, 0, 1, 0.2, 0]))
	assert_ne(t.find(stroke)["data"].size(), copy.find(stroke)["data"].size(), "nor back")


func test_the_digest_is_stable_and_moves_with_any_change() -> void:
	var t := TerraCorpus.build().terra
	var d := t.digest(GRID, EXTENT)
	assert_eq(d.length(), 64)
	assert_eq(t.digest(GRID, EXTENT), d, "same document, same digest")
	assert_eq(t.duplicate().digest(GRID, EXTENT), d, "a copy has the same digest")
	assert_eq(TerraCorpus.build().terra.digest(GRID, EXTENT), d, "a rebuilt corpus too")
	# One float, by its lowest bit.
	var one := t.duplicate()
	var data: PackedFloat32Array = one.prims[2]["data"]
	var bytes := data.to_byte_array()
	bytes[0] ^= 1
	one.prims[2]["data"] = bytes.to_float32_array()
	assert_ne(one.digest(GRID, EXTENT), d, "one float's lowest bit")
	var order := t.duplicate()
	order.move(order.prims[3]["id"], 4)
	assert_ne(order.digest(GRID, EXTENT), d, "the order")
	var muted := t.duplicate()
	muted.set_muted(muted.prims[3]["id"], true)
	assert_ne(muted.digest(GRID, EXTENT), d, "a mute")
	assert_ne(t.digest(GRID + Vector2i(2, 0), EXTENT), d, "the grid's size")
	assert_ne(t.digest(GRID, EXTENT * 1.0001), d, "the grid's step")


func test_digest_for_uses_the_documents_derive_grid() -> void:
	var c := TerraCorpus.build(Vector2i(40, 48))
	var grid := TerraCore.grid_for(c.map_doc)
	assert_eq(c.terra.digest_for(c.map_doc), c.terra.digest(grid["size"], grid["extent"]))
