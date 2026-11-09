extends GutTest

## ScatterRows.chunk (card scatterload): a settled chunk node's row keys, instance order and
## MultiMesh buffer. The native call (TTScatterNative.chunk) against GDScript bit for bit, on a
## generated forest cell with its grass-mass anchors and on edge-case rows: its keys and order
## against chunk_gdscript's, its buffer against _reference_buffer, the per-instance path's
## transforms and custom data (what ScatterGlbUtils.build_multimesh is handed) laid out as Godot
## stores them; and AuthoredScatter's load building the same nodes either way. That this layout
## is the bytes the per-instance path leaves in a MultiMesh is checked on the real renderer by the
## foliage_perf `load` probe (`parity` line): a headless MultiMesh reads nothing back. Native
## checks pend where the library is not built.

const SIZE_FT := 200
const SEED := 1234
const BIOME := "temperate_forest_summer_s1"
const CELL := Vector2i(1, -1)
const STRIDE := MapDocument.ROW_STRIDE

var _generated: Dictionary = {}


func after_each() -> void:
	ScatterNative.force_gdscript_chunks = false


## Pends without the library; a loaded library must carry the chunk call (fails when stale).
func _skip_without_library() -> bool:
	if not ScatterNative.available():
		pending("the native library is not built (AGENTS.md Testing): GDScript path only")
		return true
	assert_string_contains(ScatterNative.version(), ScatterNative.CAPABILITY_CHUNK)
	return false


func test_native_chunk_equals_gdscript_on_a_generated_cell() -> void:
	if _skip_without_library():
		return
	var result := _generate()
	var chunks := 0
	var custom := 0
	var instances := 0
	for cell in result.rows_by_cell:
		for asset_id in result.rows_by_cell[cell]:
			var rows: PackedFloat32Array = result.rows_by_cell[cell][asset_id]
			var seed_value := ScatterRows.order_seed(AuthoredScatter.node_name_for(asset_id, cell))
			for table: Dictionary in [result.anchors, {}]:
				var native := _assert_same(rows, null, seed_value, table, "%s %s" % [asset_id, cell])
				custom += 1 if native.get("custom", false) else 0
			chunks += 1
			instances += rows.size() / STRIDE
	assert_gt(chunks, 3, "the cell holds several species")
	assert_gt(instances, 100, "and enough instances")
	assert_gt(custom, 0, "some chunks carry grass-mass custom data")


func test_native_chunk_equals_gdscript_on_edge_rows_and_chosen_indices() -> void:
	if _skip_without_library():
		return
	var rows := PackedFloat32Array()
	var anchors := {}
	for r in 40:
		var q := [0.0, 0.0, 0.0, 0.0] if r % 7 == 0 else [sin(r * 1.3), r * 0.25, -0.5, cos(r)]
		var s := -0.8 if r % 5 == 0 else 0.3 + r * 0.11
		rows.append_array(
			PackedFloat32Array([r * 0.37 - 7.0, -0.0 if r == 3 else r * 0.05, 1234.567 - r * 3.1])
		)
		rows.append_array(PackedFloat32Array(q))
		rows.append_array(PackedFloat32Array([s, s * 1.5, s]))
		if r % 3 == 0:
			var at := r * STRIDE
			anchors[Vector2(rows[at], rows[at + 2])] = Vector2(0.25 * r, -0.125 * r)
	var seed_value := ScatterRows.order_seed("Edge_MultiMesh_c0_0")
	var chosen := PackedInt32Array([39, 0, 14, 7, 21, 3, 30, 12, 1])
	for indices: Variant in [null, chosen, PackedInt32Array()]:
		for table: Dictionary in [anchors, {}]:
			_assert_same(rows, indices, seed_value, table, "%s, %d anchors" % [indices, table.size()])
	assert_eq(ScatterNative.chunk(rows, PackedInt32Array([40]), seed_value, {}), {}, "out of range")


## The GDScript path gives what the per-instance path was always given: row_keys, instance_order
## by the node name, and transforms_from_rows in that order; ScatterRows.chunk takes it when
## forced, and the caller's keys are used as they are.
func test_gdscript_chunk_is_the_per_instance_path() -> void:
	ScatterNative.force_gdscript_chunks = true
	var result := _generate()
	var checked := 0
	for cell in result.rows_by_cell:
		for asset_id in result.rows_by_cell[cell]:
			var rows: PackedFloat32Array = result.rows_by_cell[cell][asset_id]
			var name := AuthoredScatter.node_name_for(asset_id, cell)
			var built := ScatterRows.chunk(rows, null, name, result.anchors)
			var keys := ScatterRows.row_keys(rows.to_byte_array().to_int32_array())
			var order := ScatterRows.instance_order(keys, PackedInt32Array(range(keys.size())), name)
			assert_false(built.has("buffer"), "forced: no native buffer")
			assert_eq(built.keys, keys)
			assert_eq(built.order, order)
			assert_eq(built.transforms, ScatterRows.transforms_from_rows(rows, order))
			var some := PackedInt32Array([order[0]])
			var given := ScatterRows.chunk(rows, some, name, {}, keys)
			assert_same(given.keys, keys, "the caller's keys")
			checked += 1
	assert_gt(checked, 3)


## AuthoredScatter's load (begin_build, build_cells, end_build) builds the same nodes, orders
## and keys natively and with the chunks forced into GDScript.
func test_load_builds_the_same_nodes_native_and_in_gdscript() -> void:
	if _skip_without_library():
		return
	var result := _generate()
	var native := _load(result)
	ScatterNative.force_gdscript_chunks = true
	var gdscript := _load(result)
	assert_gt((native.nodes as Dictionary).size(), 3)
	assert_eq(native.nodes, gdscript.nodes)
	assert_eq(native.orders, gdscript.orders)
	assert_eq(native.keys, gdscript.keys)


## One generated forest cell at full density: ScatterRegen.run's rows_by_cell and anchors.
func _generate() -> Dictionary:
	if not _generated.is_empty():
		return _generated
	var doc := NewMap.create(SIZE_FT, BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, StartingLandform.FLAT)
	var slot := doc.biome_ids.find(BIOME) + 1
	var rect := Rect2(Vector2(CELL) * 10.0, Vector2(10.0, 10.0)).grow(2.0)
	var first := Vector2i(doc.world_to_sample(rect.position).ceil())
	var last := Vector2i(doc.world_to_sample(rect.end).floor())
	var columns := doc.samples_x()
	for z in range(maxi(first.y, 0), mini(last.y, doc.samples_z() - 1) + 1):
		for x in range(maxi(first.x, 0), mini(last.x, columns - 1) + 1):
			doc.biome_slots[z * columns + x] = slot
			doc.biome_density[z * columns + x] = 255
	var species := PaletteLibrary.species(BIOME)
	var cells_by_species: Array = []
	for _s in species.size():
		cells_by_species.append([CELL])
	var work := {
		BIOME:
		{
			"species": species,
			"cells_by_species": cells_by_species,
			"window": Rect2(Vector2(CELL) * 10.0, Vector2(10.0, 10.0)).grow(12.0),
			"built": PackedStringArray(PaletteLibrary.surfaces_with_role("built")),
			"cliff": PackedStringArray(PaletteLibrary.surfaces_with_role("cliff")),
		}
	}
	_generated = ScatterRegen.run(doc, work)
	return _generated


## The settled nodes a load builds from `result`: {"nodes": name -> [instances, custom data],
## "orders", "keys"}.
func _load(result: Dictionary) -> Dictionary:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var scatter := AuthoredScatter.create()
	scatter.warm_pipelines = false
	parent.add_child(scatter)
	scatter.begin_build()
	scatter.mass_anchors = (result.anchors as Dictionary).duplicate()
	for cell in result.rows_by_cell:
		scatter.build_cells({cell: result.rows_by_cell[cell]})
	scatter.end_build()
	var nodes := {}
	for node: MultiMeshInstance3D in scatter.find_children("*", "MultiMeshInstance3D", false, false):
		nodes[String(node.name)] = [node.multimesh.instance_count, node.multimesh.use_custom_data]
	return {"nodes": nodes, "orders": scatter.get("_orders"), "keys": scatter.get("_keys")}


## The native chunk of `rows` against GDScript: keys and order as chunk_gdscript gives them, the
## buffer as _reference_buffer lays out its transforms. Returns the native chunk.
func _assert_same(
	rows: PackedFloat32Array, indices: Variant, seed_value: int, anchors: Dictionary, label: String
) -> Dictionary:
	var native := ScatterNative.chunk(rows, indices, seed_value, anchors)
	assert_false(native.is_empty(), "%s ran natively" % label)
	if native.is_empty():
		return native
	var gdscript := ScatterRows.chunk_gdscript(rows, indices, seed_value)
	var reference := _reference_buffer(gdscript.transforms, anchors)
	assert_eq(native.keys, gdscript.keys, "%s keys" % label)
	assert_eq(native.order, gdscript.order, "%s order" % label)
	assert_eq(native.custom, reference.custom, "%s custom" % label)
	assert_true(
		(native.buffer as PackedFloat32Array).to_byte_array() == reference.buffer.to_byte_array(),
		"%s buffer bytes" % label
	)
	return native


## The MultiMesh buffer (TRANSFORM_3D) build_multimesh leaves for `transforms` under `anchors`:
## per instance three basis rows each followed by the origin's component, then, when any
## instance is anchored (ScatterMass.custom_data), its custom data, Color(0, 0, 0, 0) for one
## without. {"buffer", "custom"}.
func _reference_buffer(transforms: Array[Transform3D], anchors: Dictionary) -> Dictionary:
	var data := ScatterMass.custom_data(anchors, transforms)
	var stride := 16 if not data.is_empty() else 12
	var out := PackedFloat32Array()
	out.resize(transforms.size() * stride)
	for i in transforms.size():
		var t := transforms[i]
		var o := i * stride
		var values := [
			t.basis.x.x,
			t.basis.y.x,
			t.basis.z.x,
			t.origin.x,
			t.basis.x.y,
			t.basis.y.y,
			t.basis.z.y,
			t.origin.y,
			t.basis.x.z,
			t.basis.y.z,
			t.basis.z.z,
			t.origin.z
		]
		if not data.is_empty():
			var c: Color = data[i] if data[i] != null else Color(0, 0, 0, 0)
			values.append_array([c.r, c.g, c.b, c.a])
		for k in values.size():
			out[o + k] = values[k]
	return {"buffer": out, "custom": not data.is_empty()}
