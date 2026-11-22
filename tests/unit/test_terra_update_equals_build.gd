extends GutTest
## Update equals build (docs/systems/terraform.md): a document edited step by step through dirty
## tile derives must hold exactly the bits of a fresh whole-map derive of the final document, for
## every derived array and record list (TerraDerive.digests()). Each edit kind is one step: the
## corpus added one primitive at a time, a held raise across both rivers, smooth, lower, an undone
## hill, a moved wall, and a river landing derived on the worker thread.


func _check_same(n: RefCounted, c: TerraCorpus, label: String) -> void:
	var fresh := c.make_derive()
	fresh.call("derive_full")
	var da: Dictionary = n.call("digests")
	var db: Dictionary = fresh.call("digests")
	var bad: Array = []
	for k in db:
		if da.get(k) != db[k]:
			bad.append(k)
	assert_eq(bad, [], "%s: arrays that differ from a full build" % label)
	assert_eq(da.size(), db.size(), "%s: the same digest set" % label)


func _edit(n: RefCounted, c: TerraCorpus, type: int, data: PackedFloat32Array) -> int:
	var id := c.add(type, data)
	n.call("set_prim", id, type, data)
	return id


func test_update_equals_build() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var final := TerraCorpus.build()
	var c := TerraCorpus.build(Vector2i(TerraCorpus.CELLS, TerraCorpus.CELLS), false)
	var n := c.make_derive()
	n.call("derive_full")
	# The rest of the corpus, one primitive and one derive at a time.
	for p in final.terra.prims.slice(c.terra.prims.size()):
		_edit(n, c, p["kind"], p["data"])
		n.call("derive")
	_check_same(n, c, "corpus added one by one")
	# A held raise stroke, one dab per derive, across the tributary and the main river.
	var a := c.at(20.0, 22.0)
	var stroke := _edit(n, c, TerraCore.STROKE, PackedFloat32Array([a.x, a.y, 2.0, 0.15, 0]))
	n.call("derive")
	for k in 40:
		var p := c.at(20.0 + k * 0.35, 22.0 + k * 0.2)
		var dab := PackedFloat32Array([p.x, p.y, 2.0, 0.15, 0])
		c.append(stroke, dab)
		n.call("append_dabs", stroke, dab)
		n.call("derive")
	_check_same(n, c, "held raise across the rivers")
	# A smooth stroke, a lower stroke, an undo of a hill, a moved wall.
	var s0 := c.at(19.0, 46.0)
	var s1 := c.at(20.0, 46.5)
	var smooth := PackedFloat32Array([s0.x, s0.y, 3.0, 0.8, 2, s1.x, s1.y, 3.0, 0.8, 2])
	_edit(n, c, TerraCore.STROKE, smooth)
	n.call("derive")
	var lo := c.at(31.0, 37.0)
	_edit(n, c, TerraCore.STROKE, PackedFloat32Array([lo.x, lo.y, 2.5, 0.5, 1]))
	n.call("derive")
	var hill_id := int(c.terra.prims[3]["id"])
	c.remove(hill_id)
	n.call("remove_prim", hill_id)
	n.call("derive")
	for p in c.terra.prims:
		if p["kind"] == TerraCore.WALL:
			var moved := c.line([1.2, 0.5], [22, 34, 40, 40])
			c.replace(p["id"], moved)
			n.call("set_prim", p["id"], TerraCore.WALL, moved)
	n.call("derive")
	_check_same(n, c, "smooth, lower, undo, moved wall")
	# A river landing derived on the worker thread (the release path).
	_edit(n, c, TerraCore.RIVER, c.line([2.0, 0.5], [55, 4, 50, 30, 44, 58]))
	n.call("derive_async")
	var res: Dictionary = {}
	var waited := 0
	while res.is_empty() and waited < 20000:
		OS.delay_usec(500)
		waited += 1
		res = n.call("take_result")
	assert_false(res.is_empty(), "the async derive returned a result")
	assert_false(n.call("is_busy"), "the async derive has finished")
	_check_same(n, c, "river landing derived async")
