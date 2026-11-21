extends GutTest

## The painted ground's zone maps kept per edit (PainterZoneMaps, card painter-zone-dirty-rect;
## docs/systems/painter.md "Zone maps"): an update over an edited rectangle gives the bytes a whole
## rebuild gives, for an edit in the middle, at an edge, in each corner, two overlapping edits and a
## paint edit alone; a changed plan rebuilds whole; an edit keeps the texture objects, a map of
## another size gets textures of its own size; PainterSurfaces follows ground_edited with the rect
## and shares one texture between the ground and the skirt.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
## A forest, a savanna (dry), the badlands (earth); none dominant (the forest holds half the cells).
const BIOMES := ["temperate_forest_summer_s1", "savanna_summer_s1", "rocky_badlands_summer_s1"]
## A path, a cliff, a shore and an ash surface (the char map).
const SURFACES := ["dirt_road_packed", "cliff_rock", "sand_beach", "ash"]


## A painted document of `size` metres: biomes, densities, painted surfaces and wet dressing at
## random, from `seed`.
func _doc(size: Vector2i, seed: int) -> MapDocument:
	var doc := MapDocument.create_flat(size, "grass_meadow", "test", 7)
	var n := doc.samples_x() * doc.samples_z()
	doc.biome_ids = PackedStringArray(BIOMES)
	doc.surface_ids = PackedStringArray(SURFACES)
	doc.biome_slots.resize(n)
	doc.biome_density.resize(n)
	doc.surface_weights.resize(n * MapDocument.SURFACE_BYTES)
	doc.water_dressing.resize(n * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_scramble(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()), rng, true)
	return doc


## Rewrites every sample of `rect` at random: the painted surfaces, and with `everything` the biome
## masks and the wet dressing too (without, a Paint stroke's edit).
func _scramble(
	doc: MapDocument, area: Rect2i, rng: RandomNumberGenerator, everything: bool
) -> void:
	var sx := doc.samples_x()
	var n := sx * doc.samples_z()
	var rect := area.intersection(Rect2i(0, 0, sx, doc.samples_z()))
	var slots := doc.biome_slots
	var density := doc.biome_density
	var weights := doc.surface_weights
	var wet := doc.water_dressing
	# A terrain with no water keeps no dressing (AuthoredTerrain.create drops it).
	var has_wet := wet.size() == n * 4
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := z * sx + x
			if everything:
				var r := rng.randf()
				slots[i] = 1 if r < 0.5 else (2 if r < 0.65 else (3 if r < 0.8 else 0))
				density[i] = rng.randi_range(0, 255)
				if has_wet:
					wet[i * 4] = rng.randi_range(0, 255) if rng.randf() < 0.1 else 0
					wet[i * 4 + 1] = rng.randi_range(0, 255) if rng.randf() < 0.05 else 0
			for e in 4:
				weights[i * 4 + e] = rng.randi_range(0, SURFACES.size())
				weights[n * 4 + i * 4 + e] = rng.randi_range(0, 255) * (rng.randi() % 2)
	doc.biome_slots = slots
	doc.biome_density = density
	doc.surface_weights = weights
	doc.water_dressing = wet


func _whole_bytes(doc: MapDocument) -> Array:
	var char_map := PainterZoneMaps.char_image(doc)
	var biome := PainterZoneMaps.biome_zone_image(doc)
	return [
		PainterZoneMaps.zone_image(doc).get_data(),
		char_map.get_data() if char_map != null else null,
		biome.get_data() if biome != null else null,
	]


func _kept_bytes(maps: PainterZoneMaps) -> Array:
	return [
		maps.zone.get_data(),
		maps.char_map.get_data() if maps.char_map != null else null,
		maps.biome.get_data() if maps.biome != null else null,
	]


## Builds `doc`'s maps, edits `rects` (each scrambled, then one update over their merge, as
## PainterSurfaces sends it) and checks the kept maps against a whole rebuild.
func _edit_and_check(size: Vector2i, rects: Array, everything: bool, label: String) -> void:
	var doc := _doc(size, 11)
	var maps := PainterZoneMaps.new()
	maps.build(doc)
	assert_not_null(maps.char_map, "the doc has an ash surface")
	assert_not_null(maps.biome, "and dry biomes")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var dirty := Rect2i()
	for rect: Rect2i in rects:
		_scramble(doc, rect, rng, everything)
		dirty = dirty.merge(rect) if dirty.has_area() else rect
	assert_ne(_kept_bytes(maps), _whole_bytes(doc), "%s: the edit changed the maps" % label)
	maps.update(doc, dirty)
	assert_false(maps.last_whole, "%s: a partial update" % label)
	assert_eq(_kept_bytes(maps), _whole_bytes(doc), "%s: equals the whole rebuild" % label)


func test_a_centre_edit_equals_the_whole_rebuild() -> void:
	_edit_and_check(Vector2i(10, 10), [Rect2i(15, 12, 6, 5)], true, "centre")


func test_edge_edits_equal_the_whole_rebuild() -> void:
	var doc := _doc(Vector2i(10, 8), 1)
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	_edit_and_check(Vector2i(10, 8), [Rect2i(0, 10, 3, 6)], true, "left edge")
	_edit_and_check(Vector2i(10, 8), [Rect2i(sx - 2, 9, 2, 5)], true, "right edge")
	_edit_and_check(Vector2i(10, 8), [Rect2i(12, 0, 7, 1)], true, "top edge")
	_edit_and_check(Vector2i(10, 8), [Rect2i(8, sz - 3, 4, 3)], true, "bottom edge")


func test_corner_edits_equal_the_whole_rebuild() -> void:
	var doc := _doc(Vector2i(10, 8), 1)
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	_edit_and_check(Vector2i(10, 8), [Rect2i(0, 0, 4, 3)], true, "top left")
	_edit_and_check(Vector2i(10, 8), [Rect2i(sx - 1, 0, 1, 1)], true, "top right, one sample")
	_edit_and_check(Vector2i(10, 8), [Rect2i(0, sz - 5, 5, 5)], true, "bottom left")
	_edit_and_check(Vector2i(10, 8), [Rect2i(sx - 3, sz - 2, 3, 2)], true, "bottom right")


func test_two_overlapping_edits_equal_the_whole_rebuild() -> void:
	_edit_and_check(
		Vector2i(10, 10), [Rect2i(10, 10, 8, 6), Rect2i(14, 13, 9, 9)], true, "overlapping"
	)
	# And two updates in turn, each over its own rect.
	var doc := _doc(Vector2i(10, 10), 3)
	var maps := PainterZoneMaps.new()
	maps.build(doc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for rect: Rect2i in [Rect2i(5, 5, 10, 10), Rect2i(9, 2, 6, 20)]:
		_scramble(doc, rect, rng, true)
		maps.update(doc, rect)
	assert_false(maps.last_whole)
	assert_eq(_kept_bytes(maps), _whole_bytes(doc), "two updates in turn")


func test_a_paint_edit_alone_equals_the_whole_rebuild() -> void:
	_edit_and_check(Vector2i(10, 10), [Rect2i(20, 3, 7, 7)], false, "paint")


func test_an_edit_outside_the_changed_maps_reach_changes_nothing() -> void:
	# A sculpt step: ground_edited over the rule fields' reach, with no mask or paint change.
	var doc := _doc(Vector2i(10, 10), 2)
	var maps := PainterZoneMaps.new()
	maps.build(doc)
	var before := _kept_bytes(maps)
	maps.update(doc, Rect2i(10, 10, 12, 12))
	assert_eq(maps.last_rect, Rect2i(9, 9, 14, 14), "the rect grown by the blur's reach")
	assert_eq(_kept_bytes(maps), before)


func test_a_changed_plan_rebuilds_whole() -> void:
	var doc := _doc(Vector2i(10, 10), 4)
	var maps := PainterZoneMaps.new()
	maps.build(doc)
	maps.update(doc, Rect2i(1, 1, 2, 2))
	assert_false(maps.last_whole, "the same plan")
	# A new surface (a new role table) and a dominant savanna both change every texel's constants.
	doc.surface_ids.append("forest_floor_litter")
	maps.update(doc, Rect2i(1, 1, 2, 2))
	assert_true(maps.last_whole, "a new surface")
	assert_eq(_kept_bytes(maps), _whole_bytes(doc))
	var slots := doc.biome_slots
	slots.fill(2)
	doc.biome_slots = slots
	maps.update(doc, Rect2i(1, 1, 2, 2))
	assert_true(maps.last_whole, "the savanna now dominates")
	assert_eq(_kept_bytes(maps), _whole_bytes(doc))


func test_an_edit_keeps_the_texture_objects() -> void:
	var doc := _doc(Vector2i(10, 10), 6)
	var maps := PainterZoneMaps.new()
	maps.build(doc)
	var textures := [maps.zone_texture(), maps.char_texture(), maps.biome_texture()]
	var rng := RandomNumberGenerator.new()
	_scramble(doc, Rect2i(4, 4, 5, 5), rng, true)
	maps.update(doc, Rect2i(4, 4, 5, 5))
	maps.build(doc)
	var now := [maps.zone_texture(), maps.char_texture(), maps.biome_texture()]
	for k in 3:
		assert_not_null(now[k])
		assert_true(is_same(textures[k], now[k]), "texture %d kept, by an update and a build" % k)
	# What the texture uploaded is not readable headless (the dummy renderer keeps the first
	# image): the in-game identity check covers it.


func test_a_map_of_another_size_gets_textures_of_its_size() -> void:
	var maps := PainterZoneMaps.new()
	maps.build(_doc(Vector2i(10, 10), 7))
	var small := maps.zone_texture()
	var doc := _doc(Vector2i(14, 9), 8)
	maps.build(doc)
	var size := Vector2(doc.samples_x(), doc.samples_z())
	assert_false(is_same(small, maps.zone_texture()), "a new texture for a new size")
	for texture: ImageTexture in [maps.zone_texture(), maps.char_texture(), maps.biome_texture()]:
		assert_eq(texture.get_size(), size)
	assert_eq(_kept_bytes(maps), _whole_bytes(doc))
	# A map without the char and biome maps drops their textures.
	maps.build(MapDocument.create_flat(Vector2i(14, 9), "grass_meadow", "test", 7))
	assert_null(maps.char_texture())
	assert_null(maps.biome_texture())


func test_the_painted_ground_follows_an_edit_with_its_rect_and_shares_its_textures() -> void:
	var container := Node3D.new()
	add_child_autofree(container)
	var map := Node3D.new()
	map.name = "LevelMap"
	container.add_child(map)
	var doc := _doc(Vector2i(12, 12), 12)
	var terrain := AuthoredTerrain.create(doc)
	map.add_child(terrain)
	var surfaces := PainterSurfaces.new()
	assert_true(surfaces.paint(map, STATE))
	var ground := surfaces.ground_material()
	var skirt: ShaderMaterial = surfaces.ground_materials()[1]
	var texture: Variant = ground.get_shader_parameter(&"zone_map")
	assert_true(is_same(texture, skirt.get_shader_parameter(&"zone_map")), "one texture for both")
	var rng := RandomNumberGenerator.new()
	var rect := Rect2i(20, 8, 9, 7)
	_scramble(doc, rect, rng, true)
	terrain.ground_edited.emit(rect)
	surfaces._rebuild_zone()
	assert_false(surfaces.zones().last_whole, "the edit redid its rect")
	assert_true(is_same(texture, ground.get_shader_parameter(&"zone_map")), "the same texture")
	assert_true(is_same(texture, skirt.get_shader_parameter(&"zone_map")))
	assert_eq(_kept_bytes(surfaces.zones()), _whole_bytes(doc))
	# The path slot map follows a paint edit (the one path surface painted away: no path left).
	assert_eq(ground.get_shader_parameter(&"path_only"), 0, "the dirt road is the one path")
	var weights := doc.surface_weights
	var n := doc.samples_x() * doc.samples_z()
	for i in n * 4:
		if weights[i] == 0:
			weights[n * 4 + i] = 0
	doc.surface_weights = weights
	terrain.ground_edited.emit(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	surfaces._rebuild_zone()
	assert_eq(ground.get_shader_parameter(&"path_only"), -1, "no path painted now")
	assert_eq(_kept_bytes(surfaces.zones()), _whole_bytes(doc))
	surfaces.release()
