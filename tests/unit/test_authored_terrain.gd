extends GutTest

## AuthoredTerrain and TerrainMeshBuilder: chunk coverage of the map extent, shared chunk
## border vertices and normals, height round-trip into the mesh, collision alignment with
## the document's sample positions, chunk-local rebuilds, and the ground material's palette
## textures (with the missing-surface fallback). Geometry is checked on the pure mesh
## arrays: headless runs cannot be trusted to read GPU-side resources back.

const GRASS := "grass"
## Collision must hit the document surface within a centimetre.
const RAY_TOLERANCE_M := 0.01
const EPSILON := 1e-4


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


func _flat(cells: int) -> MapDocument:
	return MapDocument.create_flat(Vector2i(cells, cells), GRASS, "test", 7)


## A rolling field with slopes up to about 40 degrees, so normals and heights vary
## everywhere, including across every chunk border.
func _sine(cells: int) -> MapDocument:
	var doc := _flat(cells)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			doc.heights[doc.sample_index(x, z)] = sin(p.x * 0.4) * 1.5 + cos(p.y * 0.3) * 0.8
	return doc


## The document surface at a world point, interpolated over the same triangles the mesh
## and the HeightMapShape3D use (each quad split along its (1, 0)-(0, 1) diagonal).
func _surface_height(doc: MapDocument, p: Vector2) -> float:
	var s := doc.world_to_sample(p)
	var x := clampi(floori(s.x), 0, doc.samples_x() - 2)
	var z := clampi(floori(s.y), 0, doc.samples_z() - 2)
	var fx := s.x - x
	var fz := s.y - z
	var h00 := doc.heights[doc.sample_index(x, z)]
	var h10 := doc.heights[doc.sample_index(x + 1, z)]
	var h01 := doc.heights[doc.sample_index(x, z + 1)]
	var h11 := doc.heights[doc.sample_index(x + 1, z + 1)]
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


func _vertices(doc: MapDocument, cell: Vector2i) -> PackedVector3Array:
	return TerrainMeshBuilder.build_chunk_arrays(doc, cell)[Mesh.ARRAY_VERTEX]


func _normals(doc: MapDocument, cell: Vector2i) -> PackedVector3Array:
	return TerrainMeshBuilder.build_chunk_arrays(doc, cell)[Mesh.ARRAY_NORMAL]


func test_chunk_grid_covers_the_extent_exactly() -> void:
	for cells in [20, 30, 40]:
		var doc := _flat(cells)
		var chunk_cells := TerrainMeshBuilder.chunk_cells(doc)
		var xs := {}
		var zs := {}
		for cell in chunk_cells:
			xs[cell.x] = true
			zs[cell.y] = true
		assert_eq(chunk_cells.size(), xs.size() * zs.size(), "%d cells: full grid" % cells)
		for axis in 2:
			var keys: Array = (xs if axis == 0 else zs).keys()
			keys.sort()
			var samples := doc.samples_x() if axis == 0 else doc.samples_z()
			var expected_next := 0
			for key in keys:
				var cell := (
					Vector2i(key, zs.keys()[0]) if axis == 0 else Vector2i(xs.keys()[0], key)
				)
				var rect := TerrainMeshBuilder.chunk_sample_rect(doc, cell)
				var first := rect.position.x if axis == 0 else rect.position.y
				var last := rect.end.x if axis == 0 else rect.end.y
				assert_eq(first, expected_next, "%d cells axis %d: chunks chain" % [cells, axis])
				expected_next = last
			assert_eq(
				expected_next, samples - 1, "%d cells axis %d: ends on the edge" % [cells, axis]
			)
		var bounds := AABB()
		for i in chunk_cells.size():
			var aabb := TerrainMeshBuilder.build_chunk_mesh(doc, chunk_cells[i], null).get_aabb()
			bounds = aabb if i == 0 else bounds.merge(aabb)
		var half := doc.extent_m() * 0.5
		assert_almost_eq(bounds.position.x, -half.x, EPSILON, "%d cells: west edge" % cells)
		assert_almost_eq(bounds.position.z, -half.y, EPSILON, "%d cells: north edge" % cells)
		assert_almost_eq(bounds.end.x, half.x, EPSILON, "%d cells: east edge" % cells)
		assert_almost_eq(bounds.end.z, half.y, EPSILON, "%d cells: south edge" % cells)


func test_chunks_are_scatter_chunker_cells() -> void:
	var doc := _flat(40)
	for cell in TerrainMeshBuilder.chunk_cells(doc):
		var rect := TerrainMeshBuilder.chunk_sample_rect(doc, cell)
		# Every sample a chunk owns except its shared last row and column lies in its cell.
		var inner := doc.sample_to_world(Vector2(rect.end - Vector2i.ONE))
		var first := doc.sample_to_world(Vector2(rect.position))
		for p in [first, inner]:
			var owner := ScatterChunker.cell_for(Vector3(p.x, 0.0, p.y), 10.0)
			assert_eq(owner, cell, "sample at %s belongs to its chunk's cell" % p)


func test_neighbouring_chunks_share_border_vertices_exactly() -> void:
	var doc := _sine(40)
	var checked := 0
	for cell in TerrainMeshBuilder.chunk_cells(doc):
		var rect := TerrainMeshBuilder.chunk_sample_rect(doc, cell)
		var columns := rect.size.x + 1
		var rows := rect.size.y + 1
		var verts := _vertices(doc, cell)
		var norms := _normals(doc, cell)
		var east := cell + Vector2i(1, 0)
		if TerrainMeshBuilder.chunk_sample_rect(doc, east).size != Vector2i.ZERO:
			var east_columns := TerrainMeshBuilder.chunk_sample_rect(doc, east).size.x + 1
			var east_verts := _vertices(doc, east)
			var east_norms := _normals(doc, east)
			for row in rows:
				assert_eq(east_verts[row * east_columns], verts[row * columns + columns - 1])
				assert_eq(east_norms[row * east_columns], norms[row * columns + columns - 1])
				checked += 1
		var south := cell + Vector2i(0, 1)
		if TerrainMeshBuilder.chunk_sample_rect(doc, south).size != Vector2i.ZERO:
			var south_verts := _vertices(doc, south)
			var south_norms := _normals(doc, south)
			for column in columns:
				assert_eq(south_verts[column], verts[(rows - 1) * columns + column])
				assert_eq(south_norms[column], norms[(rows - 1) * columns + column])
				checked += 1
	assert_gt(checked, 1000, "enough border vertices compared")


func test_normals_are_continuous_across_chunk_borders() -> void:
	# A border vertex's normal comes from the whole-document grid, so it equals the
	# central difference that straddles the border, not a one-sided chunk-local estimate.
	var doc := _sine(40)
	var cell := Vector2i(0, 0)
	var rect := TerrainMeshBuilder.chunk_sample_rect(doc, cell)
	var columns := rect.size.x + 1
	var norms := _normals(doc, cell)
	var step := doc.sample_step()
	var worst := 0.0
	for row in rect.size.y + 1:
		var sx := rect.end.x
		var sz := rect.position.y + row
		var slope_x := (
			(doc.heights[doc.sample_index(sx + 1, sz)] - doc.heights[doc.sample_index(sx - 1, sz)])
			/ (2.0 * step.x)
		)
		var z0 := maxi(sz - 1, 0)
		var z1 := mini(sz + 1, doc.samples_z() - 1)
		var slope_z := (
			(doc.heights[doc.sample_index(sx, z1)] - doc.heights[doc.sample_index(sx, z0)])
			/ ((z1 - z0) * step.y)
		)
		var expected := Vector3(-slope_x, 1.0, -slope_z).normalized()
		worst = maxf(worst, (norms[row * columns + columns - 1] - expected).length())
	assert_lt(worst, EPSILON, "border normals use neighbours across the border")
	# And the step in normal across the border is no larger than one step inside a chunk.
	var east := TerrainMeshBuilder.chunk_sample_rect(doc, cell + Vector2i(1, 0))
	var east_norms := _normals(doc, cell + Vector2i(1, 0))
	var east_columns := east.size.x + 1
	var across := (east_norms[1] - norms[columns - 1]).length()
	var inside := (norms[columns - 1] - norms[columns - 2]).length()
	assert_lt(across, inside * 1.5 + EPSILON, "no normal jump at the border")


func test_heights_round_trip_into_mesh_vertices() -> void:
	var doc := _sine(30)
	var worst := 0.0
	for cell in TerrainMeshBuilder.chunk_cells(doc):
		var rect := TerrainMeshBuilder.chunk_sample_rect(doc, cell)
		var columns := rect.size.x + 1
		var arrays := TerrainMeshBuilder.build_chunk_arrays(doc, cell)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in verts.size():
			var sx := rect.position.x + i % columns
			var sz := rect.position.y + i / columns
			var expected := TerrainMeshBuilder.sample_position(doc, sx, sz)
			worst = maxf(worst, (verts[i] - expected).length())
			worst = maxf(worst, (uvs[i] - Vector2(verts[i].x, verts[i].z)).length())
	assert_lt(worst, EPSILON, "every vertex sits on its document sample, UV = world XZ")


func test_collision_matches_the_document_surface() -> void:
	var doc := _sine(40)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var body := terrain.get_collision_body()
	assert_eq(body.collision_layer, 1, "terrain layer 1, like GLB map bodies")
	assert_eq(body.collision_mask, 1)
	assert_false(body.input_ray_pickable, "not pickable, like GLB map bodies")
	await wait_physics_frames(2)
	var half := doc.extent_m() * 0.5 - Vector2(0.001, 0.001)
	var points: Array[Vector2] = [
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(-half.x, half.y),
		Vector2(half.x, half.y),
		Vector2.ZERO,
		Vector2(1.2345, -7.891),
		Vector2(-20.013, 17.771),
		Vector2(12.3, 4.56),
	]
	_assert_rays_hit_surface(terrain, doc, points)
	# update_collision() follows edited heights.
	for i in doc.heights.size():
		doc.heights[i] += 2.0
	terrain.update_collision()
	await wait_physics_frames(2)
	_assert_rays_hit_surface(terrain, doc, points)


func _assert_rays_hit_surface(terrain: Node3D, doc: MapDocument, points: Array[Vector2]) -> void:
	var space := terrain.get_world_3d().direct_space_state
	for p in points:
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(p.x, 100.0, p.y), Vector3(p.x, -100.0, p.y), 1
		)
		var hit := space.intersect_ray(query)
		assert_false(hit.is_empty(), "ray at %s hits the terrain" % p)
		if not hit.is_empty():
			assert_almost_eq(hit.position.y, _surface_height(doc, p), RAY_TOLERANCE_M, "at %s" % p)


func test_rebuild_chunks_touches_only_the_given_chunks() -> void:
	var doc := _flat(40)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var before := {}
	for cell in terrain.chunk_cells():
		before[cell] = terrain.get_chunk(cell).mesh
	var target := Vector2i(0, 0)
	var rect := TerrainMeshBuilder.chunk_sample_rect(doc, target)
	var centre := (rect.position + rect.end) / 2
	doc.heights[doc.sample_index(centre.x, centre.y)] = 3.0
	terrain.rebuild_chunks([target] as Array[Vector2i])
	for cell in terrain.chunk_cells():
		var mesh: Mesh = terrain.get_chunk(cell).mesh
		if cell == target:
			assert_ne(mesh, before[cell], "the given chunk was rebuilt")
			assert_almost_eq(mesh.get_aabb().end.y, 3.0, EPSILON, "with the new height")
		else:
			assert_eq(mesh, before[cell], "chunk %s untouched" % cell)
	assert_eq(terrain.chunk_cells().size(), before.size(), "no chunks added or removed")


func test_chunks_are_named_by_cell() -> void:
	var terrain := AuthoredTerrain.create(_flat(20))
	add_child_autofree(terrain)
	assert_eq(terrain.get_chunk(Vector2i(-1, 0)).name, &"TerrainChunk_c-1_0")


func test_material_binds_the_palette_surface() -> void:
	var surface: Dictionary = PaletteLibrary.surfaces()[GRASS]
	var terrain := AuthoredTerrain.create(_flat(20))
	add_child_autofree(terrain)
	var material := terrain.get_material()
	assert_eq(material.shader.resource_path, "res://shaders/authored_ground.gdshader")
	for key in ["albedo", "normal", "orm", "height"]:
		var texture: Texture2D = material.get_shader_parameter(key + "_tex")
		assert_not_null(texture, "%s bound" % key)
		if texture != null:
			assert_eq(texture.resource_path, PaletteLibrary.DEFAULT_ROOT.path_join(surface[key]))
	assert_almost_eq(
		float(material.get_shader_parameter("tile_m")), float(surface["tile_m"]), EPSILON
	)
	assert_false(material.has_meta(AuthoredTerrain.FALLBACK_META))
	for cell in terrain.chunk_cells():
		assert_eq(terrain.get_chunk(cell).mesh.surface_get_material(0), material)


func test_missing_surface_falls_back_to_a_plain_ground() -> void:
	var doc := _flat(20)
	doc.base_surface = "no_such_surface"
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	assert_engine_error(1, "one warning naming the missing surface")
	var material := terrain.get_material()
	assert_true(material.get_meta(AuthoredTerrain.FALLBACK_META, false), "flagged as fallback")
	var albedo: Texture2D = material.get_shader_parameter("albedo_tex")
	assert_true(albedo is ImageTexture, "flat fallback albedo")
	var pixel := albedo.get_image().get_pixel(0, 0)
	var expected := AuthoredTerrain.FALLBACK_ALBEDO
	# One 8-bit step of slack for the byte round-trip.
	for channel in 3:
		assert_almost_eq(pixel[channel], expected[channel], 1.0 / 255.0, "channel %d" % channel)
	assert_eq(
		terrain.chunk_cells().size(), TerrainMeshBuilder.chunk_cells(doc).size(), "still built"
	)
	assert_not_null(terrain.get_collision_body(), "still collidable")


func test_skirt_rings_the_map_from_its_boundary_vertices() -> void:
	var doc := _sine(30)
	var width := 12.0
	var arrays := TerrainMeshBuilder.build_skirt_arrays(doc, width)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var loop := TerrainMeshBuilder.boundary_samples(doc)
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	var rings := TerrainMeshBuilder.SKIRT_RINGS
	assert_eq(loop.size(), 2 * (last.x + last.y), "every boundary sample once")
	assert_eq(vertices.size(), loop.size() * (rings + 1))
	var half := doc.extent_m() * 0.5
	var misplaced := 0
	for i in loop.size():
		var inner := vertices[i]
		var expected := TerrainMeshBuilder.sample_position(doc, loop[i].x, loop[i].y)
		var outer := vertices[rings * loop.size() + i]
		var past := Vector2(absf(outer.x) - half.x, absf(outer.z) - half.y)
		if (
			not inner.is_equal_approx(expected)
			or absf(maxf(past.x, past.y) - width) > 1e-3
			or not is_zero_approx(outer.y)
		):
			misplaced += 1
	assert_eq(
		misplaced, 0, "inner edge = the chunks' boundary vertices, outer edge width out at base"
	)
	var mismatched_uvs := 0
	for i in vertices.size():
		if not uvs[i].is_equal_approx(Vector2(vertices[i].x, vertices[i].z)):
			mismatched_uvs += 1
	assert_eq(mismatched_uvs, 0, "UVs are world XZ like the chunks'")
	var downward := 0
	for t in range(0, indices.size(), 3):
		var a := vertices[indices[t]]
		var facing := (vertices[indices[t + 1]] - a).cross(vertices[indices[t + 2]] - a).y
		if facing >= 0.0:
			downward += 1
	assert_eq(downward, 0, "every triangle faces up (clockwise from above)")


func test_skirt_is_decoration_outside_the_map_bounds() -> void:
	var doc := _flat(20)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var skirt := terrain.get_skirt()
	assert_not_null(skirt)
	assert_true(skirt.has_meta(Constants.BOUNDS_EXEMPT_META))
	assert_eq(skirt.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var material := skirt.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(material.shader, AuthoredTerrain.SKIRT_SHADER)
	assert_eq(material.get_shader_parameter("layer_count"), 0, "no layers")
	assert_eq(
		material.get_shader_parameter("albedo_tex"),
		terrain.get_material().get_shader_parameter("albedo_tex"),
		"the base surface continues"
	)
	var bounds := LevelEnvironmentManager.compute_map_bounds(terrain)
	assert_almost_eq(bounds.size.x, doc.extent_m().x, 0.01, "the skirt does not widen the map")
	terrain.build(doc)
	var skirts := terrain.get_children().filter(
		func(child: Node) -> bool: return String(child.name).begins_with(AuthoredTerrain.SKIRT_NAME)
	)
	assert_eq(skirts.size(), 1, "a rebuild replaces the skirt")


func test_flat_chunks_cast_no_shadow_sculpted_ones_do() -> void:
	var flat := AuthoredTerrain.create(_flat(20))
	add_child_autofree(flat)
	var off := 0
	for cell in flat.chunk_cells():
		if flat.get_chunk(cell).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			off += 1
	assert_eq(off, flat.chunk_cells().size(), "flat ground only shadows itself")
	var hills := AuthoredTerrain.create(_sine(20))
	add_child_autofree(hills)
	for cell in hills.chunk_cells():
		assert_eq(
			hills.get_chunk(cell).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"sculpted chunk %s casts" % cell
		)


func test_skirt_falls_back_to_the_base_level() -> void:
	assert_almost_eq(TerrainMeshBuilder.skirt_height(2.0, 0.0, 24.0), 2.0, EPSILON)
	assert_almost_eq(TerrainMeshBuilder.skirt_height(2.0, 12.0, 24.0), 1.0, EPSILON, "halfway")
	assert_almost_eq(TerrainMeshBuilder.skirt_height(2.0, 30.0, 24.0), 0.0, EPSILON)
	assert_almost_eq(TerrainMeshBuilder.skirt_height(-1.0, 6.0, 24.0), -0.84375, EPSILON)
	# A map raised along one edge and sunk along another: every ring heads back to 0.
	var doc := _flat(20)
	for z in doc.samples_z():
		doc.heights[doc.sample_index(doc.samples_x() - 1, z)] = 2.0
		doc.heights[doc.sample_index(0, z)] = -1.0
	var fall := 24.0
	var arrays := TerrainMeshBuilder.build_skirt_arrays(doc, 40.0, fall)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var count := TerrainMeshBuilder.boundary_samples(doc).size()
	var rising := 0
	var tilted_wrong := 0
	for i in count:
		for r in TerrainMeshBuilder.SKIRT_RINGS:
			var here := vertices[r * count + i]
			var next := vertices[(r + 1) * count + i]
			if absf(next.y) > absf(here.y) + 1e-6 or signf(next.y) * signf(here.y) < 0.0:
				rising += 1
		var edge := vertices[i]
		var outward := Vector2(vertices[count + i].x - edge.x, vertices[count + i].z - edge.z)
		var mid := normals[2 * count + i]
		# A raised edge falls outward, so its normal leans out; a sunken one leans in.
		if absf(edge.y) > 0.5 and signf(Vector2(mid.x, mid.z).dot(outward)) != signf(edge.y):
			tilted_wrong += 1
	assert_eq(rising, 0, "heights only ever head back toward the base level")
	assert_eq(tilted_wrong, 0, "normals follow the fall-off")
	for i in count:
		assert_eq(vertices[TerrainMeshBuilder.SKIRT_RINGS * count + i].y, 0.0, "outer ring at base")


func test_skirt_updates_in_place_like_a_rebuild() -> void:
	var doc := _sine(20)
	var width := AuthoredTerrain.skirt_width_m()
	var fall := AuthoredTerrain.SKIRT_FADE_M
	# The copy's layout is the engine's (positions, then normal and tangent pairs).
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, TerrainMeshBuilder.build_skirt_arrays(doc, width, fall)
	)
	var engine: PackedByteArray = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)["vertex_data"]
	var mirror := TerrainMeshBuilder.skirt_vertex_mirror(doc, width, fall)
	var expected: PackedByteArray = (
		mirror.positions.to_byte_array() + mirror.normals.to_byte_array()
	)
	assert_eq(expected.size(), engine.size())
	assert_eq(
		expected.slice(0, mirror.positions.size() * 4), engine.slice(0, mirror.positions.size() * 4)
	)
	# An edit on two edges, one of them at the loop's start corner.
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	var edits := [Rect2i(0, 0, 12, 9), Rect2i(last.x - 5, 30, 6, 10)]
	for rect: Rect2i in edits:
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				doc.heights[doc.sample_index(x, z)] += 1.5
		terrain.queue_heights(rect)
		terrain.process_heights(-1)
	var kept: Dictionary = terrain.get("_skirt_mirror")
	var fresh := TerrainMeshBuilder.skirt_vertex_mirror(doc, width, fall)
	assert_false(kept.is_empty(), "the edge edit made a vertex copy")
	assert_eq(kept.positions, fresh.positions, "every rewritten vertex matches a rebuild")
	assert_eq(kept.normals, fresh.normals)


## A map with a sharp 1.524 m step across the middle, so the rule fields vary everywhere
## near chunk borders.
func _tiered(cells: int) -> MapDocument:
	var doc := _sine(cells)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.x + 0.3 * p.y > 1.0:
				doc.heights[doc.sample_index(x, z)] += 1.524
	return doc


func test_rule_fields_ride_in_uv2_and_match_across_chunk_borders() -> void:
	var doc := _tiered(30)
	var fields := TerrainMeshBuilder.grid_fields(doc)
	var mismatched := 0
	var local_mismatched := 0
	for cell in TerrainMeshBuilder.chunk_cells(doc):
		var right := cell + Vector2i(1, 0)
		var rect := TerrainMeshBuilder.chunk_sample_rect(doc, cell)
		var arrays := TerrainMeshBuilder.build_chunk_arrays(doc, cell, fields)
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var local: PackedVector2Array = TerrainMeshBuilder.build_chunk_arrays(doc, cell)[
			Mesh.ARRAY_TEX_UV2
		]
		for i in uv2.size():
			if not uv2[i].is_equal_approx(local[i]):
				local_mismatched += 1
		var right_rect := TerrainMeshBuilder.chunk_sample_rect(doc, right)
		if right_rect.size == Vector2i.ZERO:
			continue
		var right_uv2: PackedVector2Array = (
			TerrainMeshBuilder.build_chunk_arrays(doc, right, fields)[Mesh.ARRAY_TEX_UV2]
		)
		var columns := rect.size.x + 1
		var right_columns := right_rect.size.x + 1
		for row in rect.size.y + 1:
			if uv2[row * columns + columns - 1] != right_uv2[row * right_columns]:
				mismatched += 1
	assert_eq(mismatched, 0, "shared border vertices carry the same curvature and steepness")
	assert_eq(local_mismatched, 0, "a chunk built alone computes the same fields")
	var any_curved := false
	for value in fields.curvature:
		any_curved = any_curved or absf(value) > 0.1
	assert_true(any_curved, "the step is curved")


func test_attribute_mirror_matches_the_engine_layout() -> void:
	var doc := _tiered(20)
	var cell := Vector2i(0, -1)
	var mesh := TerrainMeshBuilder.build_chunk_mesh(doc, cell, null)
	var surface := RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var mirror := TerrainMeshBuilder.chunk_vertex_mirror(doc, cell)
	var bytes := TerrainMeshBuilder.attribute_rows_bytes(mirror, 0, int(mirror.rows) - 1)
	assert_eq(bytes.attribute_offset, 0)
	assert_eq(
		bytes.attributes, surface["attribute_data"], "UV then UV2, interleaved, 16 bytes a vertex"
	)


func test_in_place_updates_rewrite_the_rule_fields() -> void:
	var doc := _sine(30)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	# Touch every chunk once so each keeps a vertex mirror, then cut a tier into the middle.
	terrain.queue_heights(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	terrain.process_heights(-1)
	var edit := Rect2i(40, 40, 30, 20)
	for z in range(edit.position.y, edit.end.y):
		for x in range(edit.position.x, edit.end.x):
			doc.heights[doc.sample_index(x, z)] += 1.524
	terrain.queue_heights(edit)
	terrain.process_heights(-1)
	assert_true(terrain.has_unsettled_chunks(), "the fields wait for the settle")
	terrain.settle_heights()
	terrain.process_heights(-1)
	assert_false(terrain.has_unsettled_chunks())
	var fresh := TerrainMeshBuilder.grid_fields(doc)
	var kept: Dictionary = terrain.get_rule_fields()
	var worst := 0.0
	for i in fresh.curvature.size():
		worst = maxf(worst, absf(kept.curvature[i] - fresh.curvature[i]))
		worst = maxf(worst, absf(kept.steep[i] - fresh.steep[i]))
	assert_lt(worst, 1e-6, "the kept fields match a full recompute")
	var mirrors: Dictionary = terrain.get("_mirrors")
	var stale := 0
	for cell in mirrors:
		var rebuilt: PackedFloat32Array = (
			TerrainMeshBuilder.chunk_vertex_mirror(doc, cell).attributes
		)
		var kept_attributes: PackedFloat32Array = (mirrors[cell] as Dictionary).attributes
		for i in rebuilt.size():
			# Sliding sums started elsewhere may round the last float32 bit differently.
			if absf(rebuilt[i] - kept_attributes[i]) > 1e-6:
				stale += 1
				break
	assert_gt(mirrors.size(), 0)
	assert_eq(stale, 0, "every in-place chunk carries the fields a rebuild would")


func test_zoom_out_recentres_only_near_the_whole_map_view() -> void:
	var fit := 50.0
	assert_eq(CameraController.recentre_weight(20.0, fit), 0.0, "play zoom pans freely")
	assert_eq(CameraController.recentre_weight(fit, fit), 1.0, "whole map: centred")
	var partial := CameraController.recentre_weight(fit * 0.8, fit)
	assert_between(partial, 0.01, 0.99)
	assert_eq(CameraController.recentre_weight(fit, INF), 0.0, "unknown fit")
