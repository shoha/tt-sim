extends GutTest

## Card painter-wall-path: a path stroke's frame learns which path slots are painted from the rows
## that changed (PainterPathPresence) instead of a pass over every sample, and a first wall's
## masonry and materials are made when the Wall tool opens (WallWarmup). Both give exactly what the
## code they skip gives: the same painted slots, slot map and path_only for any weights, and the
## same material objects and meshes on the wall.

const IDS := ["grass_meadow", "cobblestone", "flagstone", "dirt_road_packed"]
const STYLE := "temperate_forest_summer_s1"

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_rng.seed = 4242


## A document painting IDS with no paint yet (rows wide enough that a span is found by halving).
func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 16), "grass_meadow", "test", 3)
	doc.surface_ids = PackedStringArray(IDS)
	var weights := PackedByteArray()
	weights.resize(doc.sample_count() * MapDocument.SURFACE_BYTES)
	doc.surface_weights = weights
	return doc


## `count` random entries: any index (also past the slots, and on zero weights), `painted_share` of
## them with a weight above 0.
func _scatter(doc: MapDocument, count: int, painted_share: float, max_index: int = 6) -> void:
	var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	var weights := doc.surface_weights
	for _k in count:
		var at := _rng.randi_range(0, n4 - 1)
		weights[at] = _rng.randi_range(0, max_index)
		weights[n4 + at] = _rng.randi_range(1, 255) if _rng.randf() < painted_share else 0
	doc.surface_weights = weights


## A rectangle of samples written as a dab would: index and weight per entry.
func _dab(doc: MapDocument, index: int, weight: int) -> void:
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	var x0 := _rng.randi_range(0, sx - 4)
	var z0 := _rng.randi_range(0, sz - 4)
	var weights := doc.surface_weights
	for z in range(z0, mini(z0 + _rng.randi_range(1, 6), sz)):
		for x in range(x0, mini(x0 + _rng.randi_range(1, 6), sx)):
			var e := _rng.randi_range(0, 3)
			var at := (z * sx + x) * 4 + e
			weights[at] = index
			weights[n4 + at] = weight
	doc.surface_weights = weights


## The slots whose weight plane the full pass fills (PainterGroundPaths._planes), in slot order.
func _reference(doc: MapDocument, ids: PackedStringArray) -> PackedInt32Array:
	var planes := PainterGroundPaths._planes(doc, ids)
	var out := PackedInt32Array()
	for k in planes.size():
		if not planes[k].is_empty():
			out.append(k)
	return out


func _check(presence: PainterPathPresence, doc: MapDocument, label: String) -> void:
	presence.update(doc)
	var ids := PainterGroundPaths.slots(doc)
	assert_eq(presence.painted_slots(doc, ids), _reference(doc, ids), label)


func test_painted_slots_equal_the_full_pass_through_random_edits() -> void:
	var doc := _doc()
	var presence := PainterPathPresence.new()
	_check(presence, doc, "all zero")
	_scatter(doc, 300, 0.2)
	_check(presence, doc, "scattered")
	for round in 80:
		match round % 5:
			0:
				_dab(doc, _rng.randi_range(0, 4), _rng.randi_range(1, 255))
			1:
				_dab(doc, _rng.randi_range(0, 4), 0)
			2:
				_scatter(doc, _rng.randi_range(1, 40), 0.5)
			3:
				# Erase one slot's paint everywhere: its pairs go to 0.
				var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
				var weights := doc.surface_weights
				var gone := _rng.randi_range(0, 3)
				for i in n4:
					if weights[i] == gone:
						weights[n4 + i] = 0
				doc.surface_weights = weights
			4:
				pass  # Nothing changed since the last update.
		_check(presence, doc, "round %d" % round)


func test_painted_slots_follow_a_new_document_a_resize_and_cleared_paint() -> void:
	var presence := PainterPathPresence.new()
	var doc := _doc()
	_scatter(doc, 200, 0.3)
	_check(presence, doc, "first")
	var other := _doc()
	_dab(other, 1, 200)
	_check(presence, other, "another document")
	var big := MapDocument.create_flat(Vector2i(12, 9), "grass_meadow", "test", 3)
	big.surface_ids = PackedStringArray(IDS)
	var weights := PackedByteArray()
	weights.resize(big.sample_count() * MapDocument.SURFACE_BYTES)
	big.surface_weights = weights
	_check(presence, big, "a resized grid, no paint")
	_dab(big, 2, 90)
	_check(presence, big, "a resized grid, painted")
	big.surface_ids = PackedStringArray()
	big.surface_weights = PackedByteArray()
	_check(presence, big, "paint cleared")
	big.base_surface = "dirt_road_packed"
	_check(presence, big, "a path base")


func test_bind_with_presence_sets_what_the_full_pass_sets() -> void:
	var presence := PainterPathPresence.new()
	var doc := _doc()
	var cases: Array[String] = ["grass_meadow", "dirt_road_packed"]
	for base in cases:
		doc.base_surface = base
		for round in 12:
			if round % 3 == 0:
				_dab(doc, _rng.randi_range(0, 3), _rng.randi_range(0, 255))
			elif round % 3 == 1:
				_scatter(doc, 30, 0.4, 3)
			_assert_bind_equal(presence, doc, "%s round %d" % [base, round])


## Binds `doc` with `presence` and with the full pass and checks every value is the same; returns
## whether a slot map was bound.
func _assert_bind_equal(presence: PainterPathPresence, doc: MapDocument, label: String) -> bool:
	var fast := ShaderMaterial.new()
	var full := ShaderMaterial.new()
	var ids_fast := PainterGroundPaths.bind([fast], doc, true, presence)
	var ids_full := PainterGroundPaths.bind([full], doc, true)
	assert_eq(ids_fast, ids_full, label)
	assert_eq(fast.get_shader_parameter(&"path_only"), full.get_shader_parameter(&"path_only"), label)
	assert_eq(
		fast.get_shader_parameter(&"path_map_present"),
		full.get_shader_parameter(&"path_map_present"),
		label
	)
	var a: Variant = fast.get_shader_parameter(&"path_map")
	var b: Variant = full.get_shader_parameter(&"path_map")
	assert_eq(a == null, b == null, label + ": a slot map on both or neither")
	if a != null and b != null:
		assert_eq(
			(a as ImageTexture).get_image().get_data(),
			(b as ImageTexture).get_image().get_data(),
			label + ": slot map bytes"
		)
	return a != null


## Card painter-path-many: with several path surfaces painted the slot map is redone over the
## changed rows; through dabs (edges included), erasing, scatter, a new surface appended, a slot
## list reordered under paint, a path base, a new document and a resize it binds the full pass's
## bytes, kept across frames where it can be.
func test_the_slot_map_equals_the_full_pass_with_many_path_surfaces() -> void:
	var presence := PainterPathPresence.new()
	var doc := _doc()
	var maps := 0
	for round in 72:
		match round:
			0:
				# Broad paint: the first slot map is built whole; the new document at 50 from spans.
				_scatter(doc, 200, 0.6, 3)
			18:
				var ids := doc.surface_ids
				ids.append("gravel_sandstone")
				doc.surface_ids = ids
			30:
				doc.base_surface = "dirt_road_packed"
			40:
				var ids := doc.surface_ids
				ids.reverse()
				doc.surface_ids = ids
			50:
				doc.base_surface = "grass_meadow"
				var other := _doc()
				_dab(other, 1, 255)
				_dab(other, 2, 180)
				doc = other
			60:
				var small := MapDocument.create_flat(Vector2i(6, 5), "flagstone", "test", 3)
				small.surface_ids = PackedStringArray(IDS)
				var weights := PackedByteArray()
				weights.resize(small.sample_count() * MapDocument.SURFACE_BYTES)
				small.surface_weights = weights
				doc = small
		var top := doc.surface_ids.size() - 1
		match round % 4:
			0, 1:
				_dab(doc, _rng.randi_range(0, top), _rng.randi_range(1, 255))
			2:
				_dab(doc, _rng.randi_range(0, top + 1), 0 if _rng.randf() < 0.5 else 255)
			3:
				_scatter(doc, _rng.randi_range(1, 20), 0.5, top + 1)
		if _assert_bind_equal(presence, doc, "round %d" % round):
			maps += 1
	assert_gt(maps, 40, "most rounds bind a slot map")
	assert_lt(presence.slot_map.starts, 12, "and most of those keep the planes")
	assert_gt(presence.slot_map.whole_builds, 0, "a broadly painted start is built whole")
	assert_gt(presence.slot_map.starts, presence.slot_map.whole_builds, "a sparse one from spans")
	gut.p("slot maps %d, starts from zero %d" % [maps, presence.slot_map.starts])


# --- WallWarmup ----------------------------------------------------------------------------


func _walls_map() -> Array:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	return [map, AuthoredWalls.of_map(map)]


func _stone_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var line := PackedVector2Array([Vector2(-3, 0), Vector2(1, 0), Vector2(1, 3)])
	var list: Array[Wall] = [
		Wall.make(1, Wall.Kind.STONE, line, false, Wall.DEFAULT_HEIGHT_M[Wall.Kind.STONE], STYLE)
	]
	doc.walls = list
	return doc


func _run(warm: WallWarmup) -> void:
	for _frame in 64:
		if warm.done:
			return
		warm.step()


func test_the_warm_up_makes_the_materials_the_first_wall_then_wears() -> void:
	MasonryTextures.textures()
	var made: Array = _walls_map()
	var walls: AuthoredWalls = made[1]
	var styles := PackedStringArray([STYLE])
	var warm := WallWarmup.start(walls, styles)
	assert_not_null(warm)
	_run(warm)
	assert_true(warm.done, "the warm-up ends")
	var listed := walls.warm_list(styles)
	assert_eq(warm.warmed, listed.size(), "every material asked for its RID")
	var doc := _stone_doc()
	walls.refresh(doc)
	var stone := walls.get_wall_node(1).get_node("Stone") as MeshInstance3D
	assert_true(listed.has(stone.mesh.surface_get_material(0)), "the wall takes a warmed material")
	# A wall built with no warm-up is the same wall.
	var cold: Array = _walls_map()
	var cold_walls: AuthoredWalls = cold[1]
	cold_walls.refresh(doc)
	var warm_node := walls.get_wall_node(1)
	var cold_node := cold_walls.get_wall_node(1)
	assert_eq(warm_node.get_child_count(), cold_node.get_child_count())
	for child in warm_node.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var other := cold_node.get_node(NodePath(child.name)) as MeshInstance3D
		assert_eq(mesh_instance.mesh.get_surface_count(), other.mesh.get_surface_count())
		for s in mesh_instance.mesh.get_surface_count():
			assert_eq(
				mesh_instance.mesh.surface_get_arrays(s),
				other.mesh.surface_get_arrays(s),
				"%s surface %d" % [child.name, s]
			)
			var a := mesh_instance.mesh.surface_get_material(s) as BaseMaterial3D
			var b := other.mesh.surface_get_material(s) as BaseMaterial3D
			assert_eq(a.albedo_color, b.albedo_color)
			assert_eq(a.albedo_texture, b.albedo_texture, "the same texture objects")
			assert_eq(a.normal_texture, b.normal_texture)
			assert_eq(a.uv1_scale, b.uv1_scale)
			assert_eq(a.uv1_triplanar, b.uv1_triplanar)


func test_a_stopped_warm_up_makes_nothing_and_a_freed_map_ends_it() -> void:
	var made: Array = _walls_map()
	var warm := WallWarmup.start(made[1], PackedStringArray([STYLE]))
	warm.stop()
	_run(warm)
	assert_true(warm.done)
	assert_eq(warm.warmed, 0, "stopped before any material")
	var second: Array = _walls_map()
	var walls: AuthoredWalls = second[1]
	var orphan := WallWarmup.start(walls, PackedStringArray())
	walls.free()
	_run(orphan)
	assert_true(orphan.done, "its map gone: it ends")
	assert_eq(orphan.warmed, 0)
