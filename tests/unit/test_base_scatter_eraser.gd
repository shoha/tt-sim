extends GutTest

## BaseScatterEraser (utils/base_scatter_eraser.gd): the live erase-mask filter for a
## dressed Blender map's own scatter must leave exactly what the loader's filter builds.
## Rows are in the GLB-root frame, which is the document's (centred on the origin).


## A scene shaped like a loaded terrain-paint GLB: templates plus tt_scatter_instances rows.
func _scatter_scene(species: Dictionary) -> Node3D:
	var scene := Node3D.new()
	scene.name = "LevelMap"
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


func _points(count: int, spread: float, offset: float) -> Array:
	var points: Array = []
	for i in count:
		points.append(
			Vector2(
				fmod(i * 3.71 + offset, spread) - spread * 0.5,
				fmod(i * 2.39, spread) - spread * 0.5
			)
		)
	return points


func _instances(scene: Node3D) -> int:
	var total := 0
	for child in scene.get_children():
		if child is MultiMeshInstance3D and not String(child.name).contains(ScatterShrink.INFIX):
			total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func _erase_disc(doc: MapDocument, centre: Vector2, radius: float) -> void:
	if doc.erase_mask.size() != doc.sample_count():
		var mask := PackedByteArray()
		mask.resize(doc.sample_count())
		doc.erase_mask = mask
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).distance_to(centre) <= radius:
				doc.erase_mask[doc.sample_index(x, z)] = 255


func _species() -> Dictionary:
	return {
		"Tree_Oak": _points(60, 28.0, 0.0),
		"Grass_Short": _points(200, 28.0, 1.3),
		"Rock_Small": [Vector2(1, 1), Vector2(2, 2)],
		# One cell: the loader names its chunk without a cell suffix.
		"Bush_One": [Vector2(12.5, 12.5), Vector2(13.0, 12.0)],
	}


func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "v", 5)
	doc.has_base_map = true
	return doc


## Loads the scene the way a player would with `doc`'s current erase mask.
func _loaded(doc: MapDocument) -> Node3D:
	var scene := _scatter_scene(_species())
	ScatterGlbUtils.process_scatter_instances(
		scene, {}, ScatterChunker.CHUNK_SIZE_WORLD_UNITS, doc.erase_filter()
	)
	return scene


func test_live_filter_matches_what_the_loader_builds() -> void:
	var doc := _doc()
	var authoring := _loaded(doc)
	add_child_autofree(authoring)
	var eraser := BaseScatterEraser.create(authoring, doc)
	assert_not_null(eraser)
	eraser.shrink_seconds = 0.0
	var start := _instances(authoring)
	_erase_disc(doc, Vector2(3, -2), 5.0)
	var counts := eraser.refresh(doc, Rect2(-8, -12, 16, 16))
	assert_gt(counts.x, 0, "the disc removed instances")
	var player := _loaded(doc)
	assert_eq(_instances(authoring), _instances(player), "what the author sees is what loads")
	assert_eq(eraser.kept_count(), _instances(player))
	assert_eq(start - counts.x, _instances(authoring))
	player.free()


func test_a_level_opened_with_an_erase_mask_indexes_what_was_built() -> void:
	var doc := _doc()
	_erase_disc(doc, Vector2(0, 0), 17.0)
	# Everything but the corners is erased at load (some species may be left in one cell and
	# named without a cell suffix, which the index must still find).
	var authoring := _loaded(doc)
	add_child_autofree(authoring)
	var eraser := BaseScatterEraser.create(authoring, doc)
	assert_eq(eraser.kept_count(), _instances(authoring))
	assert_not_null(authoring.get_node_or_null("Bush_One_MultiMesh"), "unsuffixed chunk")
	_erase_disc(doc, Vector2(12.5, 12.5), 0.3)
	eraser.shrink_seconds = 0.0
	eraser.refresh(doc, Rect2(11, 11, 3, 3))
	assert_eq(eraser.kept_count(), _instances(authoring), "the unsuffixed chunk was found")
	assert_eq(
		(authoring.get_node("Bush_One_MultiMesh") as MultiMeshInstance3D).multimesh.instance_count,
		1
	)
	# Chunks the loader never built stay unindexed: every indexed chunk is a built one.
	var indexed := 0
	for entry_list in eraser._cells.values():
		indexed += (entry_list as Array).size()
	var built := 0
	for child in authoring.get_children():
		if child is MultiMeshInstance3D and not String(child.name).contains(ScatterShrink.INFIX):
			built += 1
	assert_eq(indexed, built)


func test_undoing_an_erase_restores_the_instances() -> void:
	var doc := _doc()
	var authoring := _loaded(doc)
	add_child_autofree(authoring)
	var eraser := BaseScatterEraser.create(authoring, doc)
	eraser.shrink_seconds = 0.0
	var start := _instances(authoring)
	var before := doc.erase_mask.duplicate()
	_erase_disc(doc, Vector2(-4, 4), 6.0)
	eraser.refresh(doc, Rect2(-10, -2, 12, 12))
	assert_lt(_instances(authoring), start)
	doc.erase_mask = before
	var counts := eraser.refresh_all(doc)
	assert_gt(counts.y, 0)
	assert_eq(_instances(authoring), start)


func test_removed_instances_shrink_out_on_a_temporary_node() -> void:
	var doc := _doc()
	var authoring := _loaded(doc)
	add_child_autofree(authoring)
	var eraser := BaseScatterEraser.create(authoring, doc)
	_erase_disc(doc, Vector2(0, 0), 6.0)
	eraser.refresh(doc, Rect2(-7, -7, 14, 14))
	var shrinking := 0
	for child in authoring.get_children():
		if String(child.name).contains(ScatterShrink.INFIX):
			shrinking += 1
	assert_gt(shrinking, 0)


func test_no_scatter_rows_means_no_eraser() -> void:
	var scene := Node3D.new()
	assert_null(BaseScatterEraser.create(scene, _doc()))
	scene.free()
