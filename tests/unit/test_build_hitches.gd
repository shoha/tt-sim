extends GutTest

## The build-hitch pass (topic hitches, docs/PERFORMANCE.md "Build hitches, round 1"): the speed-ups
## must not change an output. The decor triangle count read from the index length equals the one
## read from a copy of the arrays, the cached exposure table of a stroke equals a fresh one (and so
## does the paint it lays), and a refresh of the settlement layer over an unchanged ground leaves
## the standing rows and the counters as they were, while a changed ground stands them again.

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _mesh(indexed_surfaces: int, loose_surfaces: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in indexed_surfaces + loose_surfaces:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
		)
		if s < indexed_surfaces:
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _arrays_count(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var index: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
		if index is PackedInt32Array:
			total += (index as PackedInt32Array).size() / 3
	return total


func test_triangle_count_from_the_index_length_matches_the_arrays() -> void:
	assert_eq(StructureDecor.triangles_of(null), 0)
	for shape: Array in [[1, 0], [3, 0], [2, 2], [0, 2], [0, 0]]:
		var mesh := _mesh(shape[0], shape[1])
		assert_eq(StructureDecor.triangles_of(mesh), _arrays_count(mesh), "shape %s" % [shape])
	assert_eq(StructureDecor.triangles_of(_mesh(3, 0)), 6, "two triangles a quad, three surfaces")


func test_triangle_count_of_a_primitive_mesh_still_reads_its_arrays() -> void:
	var quad := QuadMesh.new()
	assert_eq(StructureDecor.triangles_of(quad), _arrays_count(quad))
	assert_gt(StructureDecor.triangles_of(quad), 0)


func _laid(clear_tables: bool) -> PackedByteArray:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	if clear_tables:
		SurfaceStroke._tables.clear()
	var stroke := SurfaceStroke.begin(doc, "dirt", false)
	for k in 6:
		stroke.dab(Vector2(-8 + k, -2), Vector2(8, 1 + k * 0.5), 1.5 + 0.25 * k, 0.4 + 0.1 * (k % 3))
	assert_false(stroke.finish().is_empty())
	return doc.surface_weights


func test_cached_exposure_tables_lay_the_same_paint() -> void:
	var fresh := _laid(true)
	var warm := _laid(false)
	assert_eq(warm, fresh, "a stroke reading cached tables writes the bytes a fresh one does")
	assert_lte(SurfaceStroke._tables.size(), SurfaceStroke.MAX_TABLES)
	var erase := SurfaceStroke.begin(_doc, "dirt", true)
	assert_null(erase, "nothing painted: nothing to erase")


func test_exposure_tables_differ_by_exposure_and_by_erasing() -> void:
	SurfaceStroke._tables.clear()
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var paint := SurfaceStroke.begin(doc, "dirt", false)
	var short := paint._amount_table(0.2)
	var long := paint._amount_table(1.0)
	assert_ne(short, long)
	assert_same(paint._amount_table(0.2), short, "the same exposure reads the kept table")
	assert_eq(short[0], 0.0)
	assert_gt(long[SurfaceStroke.AMOUNT_STEPS - 1], short[SurfaceStroke.AMOUNT_STEPS - 1])
	assert_true(paint.finish().is_empty())


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _rows_text(layer: AuthoredSettlements, id: int) -> String:
	var lines := PackedStringArray()
	for row in layer.standing(id):
		var at: Vector2 = row["item"]["position"]
		lines.append("%s %s %.4f %.4f" % [row["item"]["slot"], row["ref"], at.x, float(row["y"])])
	return "\n".join(lines)


func test_a_refresh_over_unchanged_ground_keeps_the_rows_and_counters() -> void:
	var editor := _editor()
	var street := editor.walls.place(
		Wall.Kind.ROW, Vector3(-12, 0, 0), Vector3(12, 0, 0), -1.0, {"seed": 5, "side": 2, "preset": 3}
	)
	# Part of the street is steep, so the skipped counter has something to hold.
	for z in _doc.samples_z():
		for x in range(_doc.samples_x() / 2, _doc.samples_x()):
			_doc.heights[_doc.sample_index(x, z)] = float(x - _doc.samples_x() / 2) * 3.0
	var id := editor.settlements.dress(street, "market_town")
	var layer := _map.get_node(NodePath(AuthoredSettlements.NODE_NAME)) as AuthoredSettlements
	layer.flush()
	var rows := _rows_text(layer, id)
	var skipped := layer.skipped_ground
	var placed := layer.placed
	assert_gt(skipped, 0, "steep ground skipped some placements")
	assert_ne(rows, "")
	layer.refresh(_doc)
	assert_eq(_rows_text(layer, id), rows, "the same ground: the same rows")
	assert_eq(layer.skipped_ground, skipped, "the skipped count carries over")
	assert_eq(layer.placed, placed)
	# Flatten the ground: the rows are stood again and nothing is skipped.
	_doc.heights.fill(0.0)
	layer.refresh(_doc)
	layer.flush()
	assert_eq(layer.skipped_ground, 0)
	assert_gt(layer.standing(id).size(), (rows.split("\n").size()), "the flat ground holds more")
