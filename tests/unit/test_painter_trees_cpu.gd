extends GutTest

## The painted trees' MultiMeshes keep their instance data readable on the CPU (MultiMeshCpu, card
## painter-mm-readback; docs/PERFORMANCE.md "Never read a MultiMesh back on the main thread"): the
## first avatar shade ray after a load walks every node (AvatarShadeCache), and a buffer-only
## MultiMesh answered it with a GPU readback, 11 to 19 ms in one frame in a window. That the reads
## cost no readback only a window can show; what holds everywhere is tested here: every node of a
## first paint and of a restroke holds exactly the rows its builder assembled
## (PainterTreePack.add_instances). In a window (this script through gut_cmdln.gd without
## --headless) each instance's transform and custom data also equal those rows and the answer of
## a buffer-only copy of the node (the readback the readers took before); the headless server
## answers get_instance_transform() with the identity, so there those asserts are skipped.

const OAK := "temperate_forest_summer_s1/Tree_Oak_v0"
const BUSH := "temperate_forest_summer_s1/Bush_Bush_v0_temperate_forest"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}

var _map: Node3D = null


func before_each() -> void:
	PainterSheet.clear_cache()
	var container := Node3D.new()
	add_child_autofree(container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	container.add_child(_map)


func _rows(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p: Vector2 in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


## Two oaks and a bush painted: the PainterTrees that draws them.
func _painted() -> Array:
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	var oaks := _rows([Vector2(1, 1), Vector2(2.5, 1.5)])
	scatter.set_cells({Vector2i(0, 0): {OAK: oaks, BUSH: _rows([Vector2(3, 3)])}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := surfaces.trees() as PainterTrees
	trees.complete()
	return [surfaces, trees]


## The rows node `k` of a cell drawing `keys` was built from (PainterTrees._make_nodes).
func _expected(trees: PainterTrees, keys: Array, k: int, bush: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var per_ell := PainterTrees.BUSH_ELL_PER_INST if bush else PainterTreePack.ELL_PER_INST
	var per_slot := PainterTrees.BUSH_SLOT_PER_INST if bush else PainterTreePack.SLOT_PER_INST
	for key: Vector3i in keys:
		var t: Dictionary = trees.trees[key]
		var d: Dictionary = t["d"]
		var xf := Transform3D(Basis.IDENTITY, t["pos"])
		if k == 0:
			PainterTreePack.add_instances(out, xf, t["row"], int(d["n_ell"]), per_ell)
		elif k == 1:
			PainterTreePack.add_instances(
				out, xf, t["row"], int(d["n_seg"]), PainterTreePack.SEG_PER_INST
			)
		else:
			PainterTreePack.add_instances(out, xf, t["row"], trees._slot_units(d), per_slot)
	return out


## `multimesh` holds `rows`, and in a window reads them back instance by instance, as a
## buffer-only copy of it does.
func _assert_holds(multimesh: MultiMesh, rows: PackedFloat32Array, label: String) -> void:
	assert_eq(multimesh.instance_count, rows.size() / 16, "%s: one instance per 16 floats" % label)
	assert_true(multimesh.buffer == rows, "%s: the buffer is the builder's rows" % label)
	if DisplayServer.get_name() == "headless":
		return
	var plain := MultiMesh.new()
	plain.transform_format = MultiMesh.TRANSFORM_3D
	plain.use_custom_data = true
	plain.mesh = multimesh.mesh
	plain.instance_count = multimesh.instance_count
	plain.buffer = rows
	for i in multimesh.instance_count:
		var r := rows.slice(i * 16, i * 16 + 16)
		var xf := Transform3D(
			Vector3(r[0], r[4], r[8]),
			Vector3(r[1], r[5], r[9]),
			Vector3(r[2], r[6], r[10]),
			Vector3(r[3], r[7], r[11])
		)
		var custom := Color(r[12], r[13], r[14], r[15])
		assert_eq(multimesh.get_instance_transform(i), xf, "%s: instance %d" % [label, i])
		assert_eq(multimesh.get_instance_custom_data(i), custom, "%s: custom %d" % [label, i])
		assert_eq(multimesh.get_instance_transform(i), plain.get_instance_transform(i))
		assert_eq(multimesh.get_instance_custom_data(i), plain.get_instance_custom_data(i))


func _assert_cells(trees: PainterTrees, from_level: int) -> int:
	var checked := 0
	for bush in [false, true]:
		var store: Dictionary = trees.bush_cells if bush else trees.cells
		for cell: Vector2i in store:
			var c: Dictionary = store[cell]
			var keys: Array = (c["keys"] as Dictionary).keys()
			var nodes: Array = c["nodes"]
			for k in range(from_level, 5):
				if nodes[k] == null:
					continue
				var mm := (nodes[k] as MultiMeshInstance3D).multimesh
				_assert_holds(mm, _expected(trees, keys, k, bush), "%s %s node %d" % [bush, cell, k])
				checked += 1
	return checked


func test_every_painted_node_holds_its_builders_rows() -> void:
	var painted := _painted()
	var trees: PainterTrees = painted[1]
	assert_eq(trees.cells.size(), 1, "the oaks' cell")
	assert_eq(trees.bush_cells.size(), 1, "the bush's cell")
	assert_eq(_assert_cells(trees, 0), 9, "five oak nodes and four bush nodes")
	(painted[0] as PainterSurfaces).release()


func test_a_restroke_keeps_the_rows_readable() -> void:
	var painted := _painted()
	var trees: PainterTrees = painted[1]
	trees.set_live_counts(not trees._live_counts)
	assert_eq(_assert_cells(trees, 2), 6, "three stroke levels a cell, rewritten in place")
	trees.set_live_counts(not trees._live_counts)
	assert_eq(_assert_cells(trees, 2), 6, "and back")
	(painted[0] as PainterSurfaces).release()
