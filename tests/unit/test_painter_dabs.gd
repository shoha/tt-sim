extends GutTest
## PainterDabs matching a set of sites it is handed to the dabs it holds (card
## painter-terrain-dabs-edit): a whole new set of the same stones builds nothing, an added, moved
## or removed stone builds that one alone, a ground edit builds the stones on what it moved, and
## what the host draws then equals a whole rebuild's bit for bit (each stone's patch and its
## outline in the lobes texture; only the slot's number and the turn in a cell may differ).


func _stage(doc: MapDocument) -> AuthoredTerrain:
	var map := Node3D.new()
	add_child_autofree(map)
	var terrain := AuthoredTerrain.new()
	terrain.name = "AuthoredTerrain"
	terrain.document = doc
	map.add_child(terrain)
	return terrain


## A rolling ground, so no two patches are alike.
func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "test", 7)
	var heights := doc.heights.duplicate()
	for j in doc.samples_z():
		for i in doc.samples_x():
			heights[j * doc.samples_x() + i] = 0.15 * sin(0.7 * i) * cos(0.45 * j)
	doc.heights = heights
	return doc


func _site(doc: MapDocument, x: float, z: float, r: float) -> Array:
	var grid := TerrainMeshBuilder.collision_heights(doc)
	var at := doc.world_to_sample(Vector2(x, z))
	var ground := ScatterGenerator.triangle_height(grid, doc.samples_x(), doc.samples_z(), at)
	return PainterSites.site(x, z, r, ground + 0.02, 0.1)


## What a host draws: each patch of each cell's mesh (a run of vertices with one slot) by its cell
## and the outline its slot holds in the lobes texture, with its vertices, uvs, custom floats (the
## slot zeroed) and its triangles counted from its first vertex.
func _drawn(dabs: PainterDabs) -> Dictionary:
	var out := {}
	var lobes := dabs.lobe_image()
	for node: Node in dabs.holder().get_children():
		var mesh := (node as MeshInstance3D).mesh
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM3]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var start := 0
		var t := 0
		while start < vertices.size():
			var tag := custom[start * 4 + 3]
			var end := start
			while end < vertices.size() and custom[end * 4 + 3] == tag:
				end += 1
			var slot := int(tag) - 1
			var own := PackedFloat32Array()
			for k in PainterDabs.LOBE_TEXELS:
				var c := lobes.get_pixel(
					PainterDabs.LOBE_TEXELS * (slot % PainterDabs.ROW) + k, slot / PainterDabs.ROW
				)
				own.append_array([c.r, c.g, c.b, c.a])
			var plain := custom.slice(start * 4, end * 4)
			for v in end - start:
				plain[v * 4 + 3] = 0.0
			var own_indices := PackedInt32Array()
			while t < indices.size() and indices[t] < end:
				own_indices.append(indices[t] - start)
				t += 1
			var key := "%s %s" % [node.name, var_to_str(own)]
			assert_false(out.has(key), "one patch a stone")
			out[key] = [vertices.slice(start, end), uvs.slice(start, end), plain, own_indices]
			start = end
	return out


func test_a_new_set_of_the_same_stones_builds_nothing_and_an_edit_builds_its_own() -> void:
	var doc := _doc()
	var terrain := _stage(doc)
	var map := terrain.get_parent() as Node3D
	var material := ShaderMaterial.new()
	var dabs := PainterDabs.new()
	# Two stones whose patches overlap, one beside them, one in another cell.
	var sites: Array = [
		_site(doc, 1.0, 1.0, 0.2),
		_site(doc, 1.35, 1.1, 0.15),
		_site(doc, 3.0, -2.0, 0.25),
		_site(doc, -9.0, 4.0, 0.2),
	]
	assert_eq(dabs.sync(map, terrain, material, sites), 4, "the first sync builds every site")
	var uploads := dabs.uploaded
	# The scatter made again (new Arrays, another order) and the terrain built again on the same
	# heights (a mark of the whole of it): nothing is built or uploaded.
	var again: Array = []
	for site: Array in sites:
		again.push_front(site.duplicate(true))
	dabs.mark(Rect2i())
	assert_eq(dabs.sync(map, terrain, material, again), 0, "the same stones: nothing built")
	assert_eq(dabs.uploaded, uploads, "nothing uploaded")
	# A stone added beside the touching pair: that one alone (its neighbours keep their patches).
	again = again.duplicate()
	again.append(_site(doc, 1.2, 1.4, 0.12))
	assert_eq(dabs.sync(map, terrain, material, again), 1, "the added stone alone")
	assert_eq(dabs.uploaded, uploads + 1, "its cell alone")
	# One moved (a new place): that one; one removed: none built, its cell put together again.
	again = again.duplicate()
	again[1] = _site(doc, 3.4, -1.6, 0.25)
	assert_eq(dabs.sync(map, terrain, material, again), 1, "the moved stone alone")
	again = again.duplicate()
	again.remove_at(2)
	assert_eq(dabs.sync(map, terrain, material, again), 0, "a removed stone builds nothing")
	assert_eq(dabs.counts(), Vector2i(4, 4))
	# The ground raised under the far stone in place, as a sculpt writes it (HeightStroke), the
	# whole terrain marked: it alone.
	var at := doc.world_to_sample(Vector2(-9.0, 4.0))
	var heights := doc.heights
	heights[floori(at.y) * doc.samples_x() + floori(at.x)] += 0.03
	dabs.mark(Rect2i())
	assert_eq(dabs.sync(map, terrain, material, again), 1, "the stone on the moved sample")
	# Its foot set again on the new ground (the scatter's own re-bedding): that stone again.
	again = again.duplicate()
	for k in again.size():
		if is_equal_approx(float(again[k][0]), -9.0):
			again[k] = _site(doc, -9.0, 4.0, 0.2)
	assert_eq(dabs.sync(map, terrain, material, again), 1, "the stone whose foot changed")
	# A stroke's step: a sample under the moved stone raised in place, its rect marked.
	var near := doc.world_to_sample(Vector2(3.4, -1.6))
	var sample := Vector2i(floori(near.x), floori(near.y))
	heights[sample.y * doc.samples_x() + sample.x] += 0.03
	dabs.mark(Rect2i(sample, Vector2i.ONE))
	assert_eq(dabs.sync(map, terrain, material, again), 1, "the stone on the stroke's step")
	assert_eq(dabs.sync(map, terrain, material, again), 0, "and nothing the sync after")
	# What it draws equals a whole rebuild of the same stones on the same ground.
	var fresh := PainterDabs.new()
	var other := _stage(doc)
	assert_eq(fresh.sync(other.get_parent(), other, ShaderMaterial.new(), again), 4)
	var mine := _drawn(dabs)
	var whole := _drawn(fresh)
	assert_eq(mine.size(), 4, "four patches")
	assert_eq(mine.keys().size(), whole.keys().size())
	for key: String in whole:
		assert_true(mine.has(key), "the same stone in the same cell with the same outline")
		assert_eq(mine.get(key, []), whole[key], "its patch bit for bit")
	dabs.clear()
	fresh.clear()
