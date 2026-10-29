extends SceneTree

## Cross-platform determinism report for the structure pipeline (card S9, the "Determinism"
## workflow .github/workflows/determinism.yml; docs/systems/structures.md "Determinism").
##
##   godot --headless --path <project> --script res://tools/determinism_report.gd
##
## Rebuilds, on THIS machine, every pinned structure and compares the digest with the pin that was
## taken on Windows: procgen's building and street cases
## (procgen/tests/expected_building_digests.txt), the two self-check samples, and tt-sim's starter
## set (tests/fixtures/structure_digests.txt). One compact line per case:
##
##   MATCH procgen stone_gable 280f1cd1... 3296
##   DIFF  procgen stone_hip   got <md5> <tris>  pinned <md5> <tris>
##         parts: v=<md5 of the vertex bytes, 8 hex> vq=<same, rounded to 1 mm> vf=<same, noise
##         floor flushed to 0> tiny=<count of vertex floats that are not 0 but under 1e-9> ...
##
## A DIFF also prints the digest's parts one by one, each also quantised to a millimetre (q) and,
## for the vertices, with the noise floor flushed (f), so a log shows whether a case moved by libm
## noise (raw part differs, q or f part agrees with the Windows run's line) or by real geometry
## (all differ). Measured 2026-10-28 on Linux: the only moved floats are values that are 0 in
## exact arithmetic and come out near 1e-17 (cos of a quarter turn), differing by a few hundred
## float ulps of that tiny size, i.e. 4e-22 m. Exits 1 when any case differs, so the workflow
## step shows red; the workflow job is not a release dependency.

const BUILDING_PINS := "res://procgen/tests/expected_building_digests.txt"
const STRUCTURE_PINS := "res://tests/fixtures/structure_digests.txt"

var _diffs: int = 0
var _cases: int = 0
## `-- --parts`: print the parts line of every case, not only of a DIFF (to compare two machines).
var _all_parts: bool = OS.get_cmdline_user_args().has("--parts")


func _initialize() -> void:
	_run()
	print("")
	print("determinism: %d cases, %d differ from the Windows pins" % [_cases, _diffs])
	quit(1 if _diffs > 0 else 0)


func _run() -> void:
	print(
		(
			"platform: %s %s, Godot %s, %s precision"
			% [
				OS.get_name(),
				Engine.get_architecture_name(),
				Engine.get_version_info().string,
				"double" if OS.has_feature("double") else "single"
			]
		)
	)
	_self_checks()
	_procgen_cases()
	_structure_cases()


# --- procgen's self-check samples ---------------------------------------------------------------


func _self_checks() -> void:
	var sample := ProcgenSelfCheck.run(ProcgenSelfCheck.pinned_digest())
	_report_check("selfcheck sample", sample)
	if not sample.is_empty() or _all_parts:
		print("      parts: %s" % _sample_parts())
	var bridge := ProcgenSelfCheck.run_bridge(ProcgenSelfCheck.pinned_bridge_digest())
	_report_check("selfcheck bridge", bridge)


## The parts of the self-check sample's mesh (the vertices of every LOD), as for a building.
func _sample_parts() -> String:
	var reg := ProcgenSelfCheck.registry()
	var plant: Variant = PlantGraphEvaluator.new(reg).evaluate_plant(
		ProcgenSelfCheck.sample_document(reg)
	)
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for geometry: PlantGeometry in plant["lods"]:
		for s in geometry.surfaces:
			v.append_array(s.vertices)
			idx.append_array(s.indices)
	return _parts_line(
		v,
		PackedVector3Array(),
		PackedVector2Array(),
		PackedColorArray(),
		idx,
		PackedVector3Array(),
		"",
		""
	)


func _report_check(label: String, failures: PackedStringArray) -> void:
	_cases += 1
	if failures.is_empty():
		print("MATCH %s" % label)
	else:
		_diffs += 1
		print("DIFF  %s: %s" % [label, "; ".join(failures)])


# --- procgen's building and street cases --------------------------------------------------------


func _procgen_cases() -> void:
	var pinned := _read_pins(BUILDING_PINS)
	for c: Dictionary in ProcgenBuildingCases.all():
		_cases += 1
		var name: String = c["name"]
		var made: Dictionary = ProcgenBuildingCases.evaluate(c)
		var geometry: PlantGeometry = made["geometry"]
		if geometry == null:
			_diff_line("procgen", name, "none 0", pinned.get(name, "(not pinned)"))
			continue
		var got := "%s %d" % [ProcgenBuildingCases.digest(geometry), geometry.triangle_count()]
		var want: String = pinned.get(name, "(not pinned)")
		if got == want:
			print("MATCH procgen %s %s" % [name, got])
			if _all_parts:
				print("      parts: %s" % _procgen_parts(geometry))
		else:
			_diff_line("procgen", name, got, want)
			print("      parts: %s" % _procgen_parts(geometry))


func _procgen_parts(geometry: PlantGeometry) -> String:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for s in geometry.surfaces:
		v.append_array(s.vertices)
		n.append_array(s.normals)
		uv.append_array(s.uvs)
		col.append_array(s.colors)
		idx.append_array(s.indices)
	var boxes: Array[Dictionary] = []
	for box in geometry.openings:
		var shape := box.duplicate()
		for key: String in ["path", "symbol", "index", "total"]:
			shape.erase(key)
		boxes.append(shape)
	return _parts_line(v, n, uv, col, idx, geometry.collision, str(geometry.top), str(boxes))


# --- tt-sim's starter set -----------------------------------------------------------------------


func _structure_cases() -> void:
	var pinned := _read_pins(STRUCTURE_PINS)
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()
	var plan := PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])
	for ref in StructureRecipes.core_refs():
		_cases += 1
		var parts := StructureGeometry.build_one(doc, Structure.make(1, ref, plan, 5))
		var got := (
			"%s %d" % [StructureGeometry.digest_of(parts), StructureGeometry.triangle_count(parts)]
		)
		var want: String = pinned.get(ref, "(not pinned)")
		if got == want:
			print("MATCH structure %s %s" % [ref, got])
			if _all_parts:
				print("      parts: %s" % _structure_parts(parts))
		else:
			_diff_line("structure", ref, got, want)
			print("      parts: %s" % _structure_parts(parts))


func _structure_parts(parts: Dictionary) -> String:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for mesh: Dictionary in parts.get("meshes", []):
		var arrays: Array = mesh.arrays
		v.append_array(arrays[Mesh.ARRAY_VERTEX])
		n.append_array(arrays[Mesh.ARRAY_NORMAL])
		uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
		col.append_array(arrays[Mesh.ARRAY_COLOR])
		idx.append_array(arrays[Mesh.ARRAY_INDEX])
	var collision: PackedVector3Array = parts.get("collision", PackedVector3Array())
	return _parts_line(v, n, uv, col, idx, collision, str(parts.get("top", "")), "")


# --- helpers ------------------------------------------------------------------------------------


## "name digest triangles" lines (or "name digest") of a pin file as name -> "digest triangles".
func _read_pins(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var parts := line.strip_edges().split(" ")
		if parts.size() == 3:
			out[parts[0]] = "%s %s" % [parts[1], parts[2]]
	return out


func _diff_line(kind: String, name: String, got: String, want: String) -> void:
	_diffs += 1
	print("DIFF  %s %s got %s pinned %s" % [kind, name, got, want])


## The parts of a digest, each as 8 hex of its md5: raw, and with every float rounded to a
## millimetre ("q"). A raw part that differs while its "q" agrees moved by a last bit only.
func _parts_line(
	v: PackedVector3Array,
	n: PackedVector3Array,
	uv: PackedVector2Array,
	col: PackedColorArray,
	idx: PackedInt32Array,
	collision: PackedVector3Array,
	top: String,
	boxes: String
) -> String:
	return (
		(
			"v=%s vq=%s vf=%s tiny=%d n=%s nq=%s uv=%s uvq=%s c=%s i=%s coll=%s collq=%s top=%s"
			+ " open=%s | verts=%d"
		)
		% [
			_h(v.to_byte_array()),
			_h(_quantise(_floats3(v))),
			_h(_flush(_floats3(v)).to_byte_array()),
			_tiny(_floats3(v)),
			_h(n.to_byte_array()),
			_h(_quantise(_floats3(n))),
			_h(uv.to_byte_array()),
			_h(_quantise(_floats2(uv))),
			_h(col.to_byte_array()),
			_h(idx.to_byte_array()),
			_h(collision.to_byte_array()),
			_h(_quantise(_floats3(collision))),
			top,
			_h(boxes.to_utf8_buffer()),
			v.size()
		]
	)


func _floats3(a: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in a:
		out.append(p.x)
		out.append(p.y)
		out.append(p.z)
	return out


func _floats2(a: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in a:
		out.append(p.x)
		out.append(p.y)
	return out


## `a` with every float under 1e-9 in magnitude set to 0: the libm noise floor of values that are
## 0 in exact arithmetic (sin(pi), cos of a quarter turn).
func _flush(a: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	for k in out.size():
		if absf(out[k]) < 1e-9:
			out[k] = 0.0
	return out


## How many floats of `a` are not 0 but under 1e-9 in magnitude.
func _tiny(a: PackedFloat32Array) -> int:
	var count := 0
	for x in a:
		if x != 0.0 and absf(x) < 1e-9:
			count += 1
	return count


func _quantise(a: PackedFloat32Array) -> PackedByteArray:
	var out := PackedInt32Array()
	out.resize(a.size())
	for k in a.size():
		out[k] = roundi(a[k] * 1000.0)
	return out.to_byte_array()


func _h(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, 8)
