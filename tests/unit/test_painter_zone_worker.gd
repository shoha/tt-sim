extends GutTest

## The zone maps' worker build (PainterZoneMaps.build_async, card painter-edit-hitch4;
## docs/systems/painter.md "Zone maps"): a worker build lands the bytes a synchronous build gives;
## an edit made while it runs never reaches its snapshot and is applied after the landing, so the
## settled maps equal a whole build of the edited document; PainterSurfaces sends a plan change to
## the worker, keeps drawing the maps it has until the landing and lands it on a later frame by
## itself; a map closed (or a maps object dropped) while a build runs drops it without a landing.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const BIOMES := ["temperate_forest_summer_s1", "savanna_summer_s1", "rocky_badlands_summer_s1"]
const SURFACES := ["dirt_road_packed", "cliff_rock", "sand_beach", "ash"]


## A painted document of `size` metres (biomes, densities, surfaces with an ash one, wet dressing).
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
	_scramble(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()), rng)
	return doc


## Rewrites every sample of `area` at random (biomes, surfaces, the dressing when there is one).
func _scramble(doc: MapDocument, area: Rect2i, rng: RandomNumberGenerator) -> void:
	var sx := doc.samples_x()
	var n := sx * doc.samples_z()
	var rect := area.intersection(Rect2i(0, 0, sx, doc.samples_z()))
	var slots := doc.biome_slots
	var density := doc.biome_density
	var weights := doc.surface_weights
	var wet := doc.water_dressing
	var has_wet := wet.size() == n * 4
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := z * sx + x
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


## A painted map of `doc` under a container freed with the test: [surfaces, terrain].
func _painted(doc: MapDocument) -> Array:
	var container := Node3D.new()
	add_child_autofree(container)
	var map := Node3D.new()
	map.name = "LevelMap"
	container.add_child(map)
	var terrain := AuthoredTerrain.create(doc)
	map.add_child(terrain)
	var surfaces := PainterSurfaces.new()
	assert_true(surfaces.paint(map, STATE))
	surfaces._rebuild_zone()
	return [surfaces, terrain]


## The first wet dressing on `doc`, every seventh sample wet.
func _first_water(doc: MapDocument) -> void:
	var n := doc.samples_x() * doc.samples_z()
	var wet := PackedByteArray()
	wet.resize(n * 4)
	for i in range(0, n, 7):
		wet[i * 4] = 200
	doc.water_dressing = wet


func test_a_worker_build_lands_the_bytes_of_a_synchronous_build() -> void:
	var doc := _doc(Vector2i(14, 10), 3)
	var maps := PainterZoneMaps.new()
	maps.build_async(doc)
	assert_true(maps.building())
	assert_null(maps.zone, "nothing kept before the landing")
	assert_true(maps.finish())
	assert_false(maps.building())
	assert_eq(maps.builds, 1)
	assert_eq(maps.async_starts, 1)
	assert_true(maps.last_whole)
	assert_eq(_kept_bytes(maps), _whole_bytes(doc))
	var size := Vector2(doc.samples_x(), doc.samples_z())
	for texture: ImageTexture in [maps.zone_texture(), maps.char_texture(), maps.biome_texture()]:
		assert_eq(texture.get_size(), size)
	assert_false(maps.finish(), "nothing left to land")
	# A taller map splits into row bands (one pool task each): their bytes are the whole build's.
	var tall := _doc(Vector2i(6, 40), 8)
	assert_gt(tall.samples_z(), PainterZoneMaps.BAND_ROWS * 3, "several bands")
	maps.build_async(tall)
	assert_true(maps.finish())
	assert_eq(_kept_bytes(maps), _whole_bytes(tall), "the bands make the whole build")


func test_an_edit_made_while_a_build_runs_waits_for_its_landing() -> void:
	var doc := _doc(Vector2i(16, 12), 5)
	var before := _whole_bytes(doc)
	var maps := PainterZoneMaps.new()
	maps.build_async(doc)
	# The edit lands while the worker reads its snapshot: in place and by assignment.
	var rect := Rect2i(9, 4, 6, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	_scramble(doc, rect, rng)
	doc.water_dressing[0] = 255
	rect = rect.merge(Rect2i(0, 0, 1, 1))
	assert_true(maps.finish())
	assert_eq(_kept_bytes(maps), before, "the snapshot is the document when the build started")
	assert_false(maps.wants_whole(doc, rect), "a small edit after the landing is an update")
	maps.update(doc, rect)
	assert_eq(_kept_bytes(maps), _whole_bytes(doc), "settled: a whole build of the edited document")


func test_an_update_during_a_build_lands_it_first() -> void:
	var doc := _doc(Vector2i(14, 10), 7)
	var maps := PainterZoneMaps.new()
	maps.build(doc)
	var texture := maps.zone_texture()
	doc.surface_ids = PackedStringArray(SURFACES + ["grass_meadow"])
	assert_true(maps.wants_whole(doc, Rect2i(1, 1, 2, 2)), "a changed plan builds whole")
	maps.build_async(doc)
	var rect := Rect2i(2, 2, 3, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	_scramble(doc, rect, rng)
	maps.update(doc, rect)
	assert_false(maps.building())
	assert_eq(maps.builds, 2, "the worker build landed")
	assert_eq(_kept_bytes(maps), _whole_bytes(doc))
	assert_true(is_same(texture, maps.zone_texture()), "the same size keeps the texture object")


func test_a_rect_about_the_whole_grid_wants_the_worker() -> void:
	var doc := _doc(Vector2i(14, 10), 2)
	var maps := PainterZoneMaps.new()
	maps.build(doc)
	var grid := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	assert_true(maps.wants_whole(doc, grid))
	assert_false(maps.wants_whole(doc, Rect2i(1, 1, 3, 3)))
	assert_true(PainterZoneMaps.new().wants_whole(doc, Rect2i(1, 1, 3, 3)), "nothing built yet")


func test_the_surfaces_build_a_first_water_on_the_worker_and_land_it_by_themselves() -> void:
	var doc := MapDocument.create_flat(Vector2i(12, 12), "grass_meadow", "test", 7)
	var pair := _painted(doc)
	var surfaces: PainterSurfaces = pair[0]
	var terrain: AuthoredTerrain = pair[1]
	var ground := surfaces.ground_material()
	var texture: Variant = ground.get_shader_parameter(&"zone_map")
	var builds := surfaces.zones().builds
	var old := surfaces.zones().zone.get_data()
	_first_water(doc)
	terrain.ground_edited.emit(Rect2i(4, 4, 6, 5))
	terrain.refresh_water_dressing()
	surfaces._rebuild_zone()
	assert_true(surfaces.zones().building(), "the plan changed: the worker builds")
	assert_eq(surfaces.zones().builds, builds)
	assert_eq(surfaces.zones().zone.get_data(), old, "the ground draws the maps it had")
	assert_true(is_same(texture, ground.get_shader_parameter(&"zone_map")))
	# An edit while it runs waits for the landing.
	var wet := doc.water_dressing
	wet[(5 * doc.samples_x() + 5) * 4 + 1] = 90
	doc.water_dressing = wet
	terrain.ground_edited.emit(Rect2i(5, 5, 1, 1))
	surfaces._rebuild_zone()
	assert_true(surfaces.zones().building(), "still the one build")
	var frames := 0
	while surfaces.zones().building() and frames < 240:
		await get_tree().process_frame
		frames += 1
	# The landing queues the zone rebuild (deferred) that applies the waiting edit.
	await get_tree().process_frame
	assert_false(surfaces.zones().building(), "landed within %d frames" % frames)
	assert_eq(surfaces.zones().builds, builds + 1, "one whole build for the first water")
	assert_eq(surfaces.zones().async_starts, 1)
	assert_eq(surfaces.zones().zone.get_data(), PainterZoneMaps.zone_image(doc).get_data())
	assert_true(is_same(texture, ground.get_shader_parameter(&"zone_map")), "updated in place")
	surfaces.release()


func test_a_map_closed_while_a_build_runs_drops_it() -> void:
	var doc := MapDocument.create_flat(Vector2i(12, 12), "grass_meadow", "test", 7)
	var pair := _painted(doc)
	var surfaces: PainterSurfaces = pair[0]
	var terrain: AuthoredTerrain = pair[1]
	var builds := surfaces.zones().builds
	_first_water(doc)
	terrain.refresh_water_dressing()
	surfaces._rebuild_zone()
	assert_true(surfaces.zones().building())
	surfaces.release()
	assert_false(surfaces.zones().building(), "release waits for the task and drops it")
	for _i in 3:
		await get_tree().process_frame
	assert_eq(surfaces.zones().builds, builds, "nothing landed after the close")
	assert_false(surfaces.finish_zones())
	# A maps object dropped while its build runs waits for the task as it goes.
	var maps := PainterZoneMaps.new()
	maps.build_async(_doc(Vector2i(14, 10), 1))
	maps = null
	assert_null(maps)
