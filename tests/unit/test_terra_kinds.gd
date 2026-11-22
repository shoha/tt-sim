extends GutTest
## The kind registry (docs/systems/terraform.md "Kinds"): the GDScript registry (TerraKinds and the
## kind folders) and the native one (native/src/terra_kinds.h, each kernel self-registered) agree on
## every kind's id, name, stage, shape, header and stride; lookups go by id whatever order the
## kinds registered in; each kind accepts the corpus and refuses a bad layout; and both the map
## reader and TerraDerive.set_prim refuse a kind id nobody registered.

## A kind id in the reserved range, registered nowhere.
const UNKNOWN := 15


## A TerraDerive (only its registry is read), or null without the library.
func _native() -> RefCounted:
	if not TerraCore.native_available():
		return null
	return ClassDB.instantiate(TerraCore.CLASS_NAME)


## A sample every kind's layout accepts: the header and the fewest items, every float 1.
func _ones(k: GDScript) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(k.HEADER + k.MIN_ITEMS * k.STRIDE)
	out.fill(1.0)
	return out


func test_the_registry_is_sound() -> void:
	var ids := {}
	var names := {}
	for k: GDScript in TerraKinds.KINDS:
		assert_false(ids.has(k.ID), "id %d registered once" % k.ID)
		assert_false(names.has(k.NAME), "name %s registered once" % k.NAME)
		ids[k.ID] = true
		names[k.NAME] = true
		assert_true(k.ID <= 8 or k.ID >= 16, "%s: 9 to 15 are reserved" % k.NAME)
		assert_true(k.SHAPE in ["stamp", "line", "water"], "%s: a shape" % k.NAME)
		assert_ne(String(k.LABEL), "", "%s: a label" % k.NAME)
		assert_ne(k.describe(), "", "%s: a description" % k.NAME)
		assert_true(k.DEFAULTS is Dictionary, "%s: defaults" % k.NAME)
	var built_in := {
		TerraCore.PLANE: "plane",
		TerraCore.HILL: "hill",
		TerraCore.RIDGE: "ridge",
		TerraCore.STROKE: "stroke",
		TerraCore.RIVER: "river",
		TerraCore.POND: "pond",
		TerraCore.PATH: "path",
		TerraCore.WALL: "wall",
		TerraCore.PAINT: "paint",
	}
	for id: int in built_in:
		assert_eq(TerraKinds.name_of(id), built_in[id], "TerraCore's id %d" % id)
	var sorted := TerraKinds.ids()
	for i in range(1, sorted.size()):
		assert_lt(sorted[i - 1], sorted[i], "ids() ascends")
	assert_false(TerraKinds.has(UNKNOWN))
	assert_eq(TerraKinds.name_of(UNKNOWN), "")


func test_the_two_registries_agree() -> void:
	var n := _native()
	if n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	assert_eq(n.call("kind_conflicts"), 0, "no id registered twice")
	var native: Array = n.call("kinds")
	assert_eq(native, TerraKinds.table(), "id, name, stage, shape, header and stride")
	var stages := {}
	for s: Dictionary in n.call("stages"):
		stages[s["name"]] = s["shape"]
	var shape_of := {"rect": "stamp", "line_rect": "line", "graph": "water"}
	for k: Dictionary in native:
		assert_eq(shape_of.get(stages.get(k["stage"])), k["shape"], "%s: its stage's shape" % k["name"])


func test_lookups_never_depend_on_registration_order() -> void:
	var n := _native()
	if n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var native: Array = n.call("kinds")
	for i in range(1, native.size()):
		assert_lt(int(native[i - 1]["id"]), int(native[i]["id"]), "kinds() ascends by id")
	var order := PackedInt32Array()
	for i in native.size():
		order.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	for attempt in 6:
		var shuffled := order.duplicate()
		if attempt == 0:
			shuffled.reverse()
		else:
			for i in range(shuffled.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t := shuffled[i]
				shuffled[i] = shuffled[j]
				shuffled[j] = t
		assert_eq(n.call("debug_kinds_in_order", shuffled), native, "order %s" % shuffled)


func test_each_kind_accepts_the_corpus() -> void:
	var seen := {}
	for c: TerraCorpus in [TerraCorpus.build(), TerraCorpus.build_terraced()]:
		for p in c.terra.prims:
			var kind := int(p["kind"])
			seen[kind] = true
			var k := TerraKinds.script_for(kind)
			assert_true(k.validate(p["data"]), "%s accepts the corpus" % k.NAME)
		assert_eq(c.terra.problem(), "")
	for k: GDScript in TerraKinds.KINDS:
		assert_true(seen.has(k.ID), "the corpus holds a %s" % k.NAME)
		assert_true(k.validate(_ones(k)), "%s: its fewest items" % k.NAME)


func test_each_kind_rejects_a_bad_layout() -> void:
	for k: GDScript in TerraKinds.KINDS:
		var good := _ones(k)
		var short := good.slice(0, good.size() - 1)
		assert_false(k.validate(short), "%s: a float short" % k.NAME)
		var long := good.duplicate()
		long.append(1.0)
		assert_false(k.validate(long), "%s: a float over (a partial item)" % k.NAME)
		if k.STRIDE > 0 and k.MIN_ITEMS > 0:
			var few := good.slice(0, good.size() - k.STRIDE)
			assert_false(k.validate(few), "%s: too few items" % k.NAME)
		for bad: float in [NAN, INF, 1e6]:
			var b := good.duplicate()
			b[b.size() - 1] = bad
			assert_false(k.validate(b), "%s: %s" % [k.NAME, bad])
			assert_ne(TerraKinds.problem(k.ID, b), "")
	var ranges := [
		[TerraCore.HILL, [1.0, 2.0, 3.0, 0.0, 2.0], "radius"],
		[TerraCore.RIDGE, [1.0, 0.0, 1.5, 0, 0, 1, 1], "width"],
		[TerraCore.STROKE, [0, 0, 2.5, 0.1, 3], "mode"],
		[TerraCore.STROKE, [0, 0, 2.5, 0.1, 0.5], "mode not whole"],
		[TerraCore.STROKE, [0, 0, -1.0, 0.1, 0], "radius"],
		[TerraCore.RIVER, [0.0, 0.5, 0, 0, 5, 5], "width"],
		[TerraCore.PATH, [-1.6, 0, 0, 3, 3], "width"],
		[TerraCore.WALL, [1.2, 0.0, 0, 0, 4, 0], "thickness"],
		[TerraCore.PAINT, [0, 0, 2.0, 256], "surface"],
		[TerraCore.PAINT, [0, 0, 2.0, -1], "surface below 0"],
	]
	for r: Array in ranges:
		var data := PackedFloat32Array(r[1])
		assert_false(TerraKinds.script_for(r[0]).validate(data), r[2])
		assert_string_contains(TerraKinds.problem(r[0], data), "range")
	assert_string_contains(TerraKinds.problem(UNKNOWN, PackedFloat32Array([1.0])), "unknown kind")


func test_bounds_agree_with_the_native_kernels() -> void:
	var n := _native()
	if n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	for p in TerraCorpus.build_terraced().terra.prims:
		var k := TerraKinds.script_for(int(p["kind"]))
		var mine: Rect2 = k.bounds(p["data"])
		var theirs: Rect2 = n.call("kind_bounds", p["kind"], p["data"])
		assert_almost_eq(mine.position, theirs.position, Vector2(1e-3, 1e-3), "%s box" % k.NAME)
		assert_almost_eq(mine.size, theirs.size, Vector2(1e-3, 1e-3), "%s box size" % k.NAME)
	assert_eq(n.call("kind_bounds", UNKNOWN, PackedFloat32Array([1.0])), Rect2())


func test_set_prim_refuses_an_unknown_kind() -> void:
	var c := TerraCorpus.build()
	var n := c.make_derive()
	if n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	n.call("derive_full")
	var before: Dictionary = n.call("digests")
	assert_false(n.call("set_prim", 999, UNKNOWN, PackedFloat32Array([0, 0, 5, 1, 1])))
	assert_false(n.call("set_prim", 999, -1, PackedFloat32Array([1.0])))
	assert_false(n.call("set_prim", 999, 1 << 40, PackedFloat32Array([1.0])))
	n.call("derive")
	assert_eq(n.call("digests"), before, "an unknown kind changes nothing")
	var hill := c.find(int(c.terra.prims[2]["id"]))
	assert_true(n.call("set_prim", hill["id"], hill["kind"], hill["data"]), "a known kind is taken")


func test_the_map_reader_refuses_an_unknown_kind() -> void:
	var t := TerraDoc.new()
	t.add(TerraCore.PLANE, PackedFloat32Array([0.0, 0.0, 0.0]))
	t.add(UNKNOWN, PackedFloat32Array([1.0]))
	assert_string_contains(t.problem(), "unknown kind")
	var read := MapTerrainIO.decode(MapTerrainIO.encode(t))
	assert_null(read["terra"], "the whole section is refused")
	assert_string_contains(" ".join(read["warnings"]), MapTerrainIO.NEWER)
