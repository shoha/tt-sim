extends GutTest

## The erase filter a map.ttmap applies to the Blender scatter of the map.glb it dresses:
## MapDocument.is_erased() / erase_filter(), and the filter threaded through
## ScatterGlbUtils.process_scatter_instances(). Rows are in the GLB-root frame, which is
## the document's frame (centred on the origin).


## A 20 x 20 cell document (30.48 m, 123 x 123 samples) whose erase mask erases the
## samples within `radius` metres of `centre`.
func _doc_with_erased_disc(centre: Vector2, radius: float) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 1)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).distance_to(centre) <= radius:
				mask[doc.sample_index(x, z)] = 255
	doc.erase_mask = mask
	return doc


## A scene carrying tt_scatter_instances rows for `species` (name -> Array of XZ Vector2),
## with one template MeshInstance3D per species, the shape a terrain-paint GLB loads as.
func _scatter_scene(species: Dictionary) -> Node3D:
	var scene := Node3D.new()
	var groups := {}
	for species_name in species:
		var template := MeshInstance3D.new()
		template.name = species_name
		template.mesh = BoxMesh.new()
		scene.add_child(template)
		var rows := []
		for xz in species[species_name]:
			rows.append([xz.x, 0.0, xz.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
		groups[species_name] = rows
	scene.set_meta(GlbUtils.SCENE_EXTRAS_META, {"tt_scatter_instances": groups})
	return scene


func _instances(scene: Node3D) -> int:
	var total := 0
	for child in scene.get_children():
		if child is MultiMeshInstance3D:
			total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func test_is_erased_reads_the_nearest_sample() -> void:
	var doc := _doc_with_erased_disc(Vector2(5, 5), 2.0)
	assert_true(doc.is_erased(Vector2(5, 5)))
	assert_true(doc.is_erased(Vector2(6.8, 5)))
	assert_false(doc.is_erased(Vector2(8, 5)))
	assert_false(doc.is_erased(Vector2(-5, -5)))
	# Off the map is never erased.
	assert_false(doc.is_erased(Vector2(500, 5)))


func test_no_mask_or_nothing_erased_gives_no_filter() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 1)
	assert_false(doc.erase_filter().is_valid())
	var zeros := PackedByteArray()
	zeros.resize(doc.sample_count())
	doc.erase_mask = zeros
	assert_false(doc.erase_filter().is_valid())
	assert_false(doc.is_erased(Vector2.ZERO))


func test_filter_agrees_with_is_erased_everywhere() -> void:
	var doc := _doc_with_erased_disc(Vector2(-3, 4), 3.3)
	var keep := doc.erase_filter()
	assert_true(keep.is_valid())
	var mismatches := 0
	for i in 400:
		var xz := Vector2(fmod(i * 7.31, 36.0) - 18.0, fmod(i * 3.77, 36.0) - 18.0)
		if keep.call(Vector3(xz.x, 1.0, xz.y)) == doc.is_erased(xz):
			mismatches += 1
	assert_eq(mismatches, 0)


func test_scatter_rows_on_erased_samples_are_dropped_exactly() -> void:
	var doc := _doc_with_erased_disc(Vector2(0, 0), 4.0)
	var points: Array = []
	for i in 30:
		points.append(Vector2(-12.0 + i * 0.8, 0.25 * i - 3.0))
	var expected_kept := 0
	for xz in points:
		if not doc.is_erased(xz):
			expected_kept += 1
	assert_between(expected_kept, 1, points.size() - 1, "the fixture straddles the disc")
	var scene := _scatter_scene({"Grass_Short": points})
	ScatterGlbUtils.process_scatter_instances(
		scene, {}, ScatterChunker.CHUNK_SIZE_WORLD_UNITS, doc.erase_filter()
	)
	assert_eq(_instances(scene), expected_kept)
	scene.free()


func test_no_document_leaves_every_row() -> void:
	var points := [Vector2(0, 0), Vector2(1, 1), Vector2(-4, 2)]
	var scene := _scatter_scene({"Grass_Short": points})
	ScatterGlbUtils.process_scatter_instances(scene)
	assert_eq(_instances(scene), 3)
	scene.free()


func test_a_fully_erased_species_builds_nothing_and_frees_its_template() -> void:
	var doc := _doc_with_erased_disc(Vector2(0, 0), 3.0)
	var scene := _scatter_scene(
		{"Rock_Small": [Vector2(0, 0), Vector2(1, -1)], "Grass_Short": [Vector2(10, 10)]}
	)
	ScatterGlbUtils.process_scatter_instances(
		scene, {}, ScatterChunker.CHUNK_SIZE_WORLD_UNITS, doc.erase_filter()
	)
	assert_eq(_instances(scene), 1)
	assert_null(scene.get_node_or_null("Rock_Small"), "erased species' template is freed")
	assert_null(scene.get_node_or_null("Grass_Short"), "built species' template is freed")
	scene.free()
