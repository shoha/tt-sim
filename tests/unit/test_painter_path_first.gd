extends GutTest

## Card painter-path-first: the first dab of a path in a surface not yet painted on the map. The
## path slot map's planes are kept in step while fewer than two path slots are painted
## (PainterPathSlotMap.follow), so the second surface's first dab costs its spans; the skirt's edge
## surface is found in one walk; a picked built surface's mean colour is warmed with its layer
## (GroundLayerBinding.prepare). Each gives what the work it replaces gives.

const IDS := ["grass_meadow", "cobblestone", "flagstone", "dirt_road_packed"]
const MEADOW := 0
const COBBLE := 1
const FLAG := 2
const DIRT := 3

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_rng.seed = 777


func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(22, 18), "grass_meadow", "test", 3)
	doc.surface_ids = PackedStringArray(IDS)
	var weights := PackedByteArray()
	weights.resize(doc.sample_count() * MapDocument.SURFACE_BYTES)
	doc.surface_weights = weights
	return doc


## Meadow over most samples (entry 0), as a generated map's ground paint.
func _meadow(doc: MapDocument) -> void:
	var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	var weights := doc.surface_weights
	for i in doc.sample_count():
		if _rng.randf() < 0.8:
			weights[i * 4] = MEADOW
			weights[n4 + i * 4] = _rng.randi_range(40, 255)
	doc.surface_weights = weights


## A dab of `index` at `weight`: a small rectangle, one random entry a sample.
func _dab(doc: MapDocument, index: int, weight: int) -> void:
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	var x0 := _rng.randi_range(0, sx - 3)
	var z0 := _rng.randi_range(0, sz - 3)
	var weights := doc.surface_weights
	for z in range(z0, mini(z0 + _rng.randi_range(1, 5), sz)):
		for x in range(x0, mini(x0 + _rng.randi_range(1, 5), sx)):
			var at := (z * sx + x) * 4 + _rng.randi_range(0, 3)
			weights[at] = index
			weights[n4 + at] = weight
	doc.surface_weights = weights


## Binds `doc` with `presence` and with the full pass; checks every value is the same. Returns
## whether a slot map was bound.
func _bind_equal(presence: PainterPathPresence, doc: MapDocument, label: String) -> bool:
	var fast := ShaderMaterial.new()
	var full := ShaderMaterial.new()
	assert_eq(
		PainterGroundPaths.bind([fast], doc, true, presence),
		PainterGroundPaths.bind([full], doc, true),
		label
	)
	for uniform: StringName in [&"path_only", &"path_map_present"]:
		assert_eq(fast.get_shader_parameter(uniform), full.get_shader_parameter(uniform), label)
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


func test_the_second_surfaces_first_dab_takes_kept_planes() -> void:
	var doc := _doc()
	# A map as authored: the surface list holds only the meadow until a path is first painted.
	doc.surface_ids = PackedStringArray([IDS[MEADOW]])
	_meadow(doc)
	var presence := PainterPathPresence.new()
	var slot_map := presence.slot_map
	_bind_equal(presence, doc, "no path yet")
	assert_eq(slot_map.starts, 1, "the planes start at once, all 0")
	doc.surface_ids = PackedStringArray(IDS)
	for round in 6:
		_dab(doc, DIRT, _rng.randi_range(1, 255))
		assert_false(_bind_equal(presence, doc, "dirt %d" % round), "one path: no slot map")
	_dab(doc, COBBLE, 200)
	assert_true(_bind_equal(presence, doc, "the cobble's first dab"), "two paths: a slot map")
	assert_eq(slot_map.starts, 1, "the first dab of the second surface keeps the planes")
	assert_eq(slot_map.whole_builds, 0, "and builds nothing whole")
	_dab(doc, FLAG, 255)
	_bind_equal(presence, doc, "the third surface's first dab")
	# Erase the cobble and the flagstone: one path again, still followed, then a second again.
	var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	var weights := doc.surface_weights
	for i in n4:
		if weights[i] == COBBLE or weights[i] == FLAG:
			weights[n4 + i] = 0
	doc.surface_weights = weights
	assert_false(_bind_equal(presence, doc, "erased to one path"))
	for round in 20:
		var index: int = [MEADOW, COBBLE, FLAG, DIRT][_rng.randi_range(0, 3)]
		_dab(doc, index, 0 if round % 5 == 4 else _rng.randi_range(1, 255))
		_bind_equal(presence, doc, "round %d" % round)
	assert_eq(slot_map.starts, 1, "never started again")
	assert_eq(slot_map.whole_builds, 0)


func test_a_map_opened_with_one_path_builds_on_a_worker() -> void:
	var doc := _doc()
	_meadow(doc)
	_dab(doc, DIRT, 255)
	var presence := PainterPathPresence.new()
	var slot_map := presence.slot_map
	assert_false(_bind_equal(presence, doc, "opened with a road"))
	assert_eq(slot_map.starts, 0, "planes with paint under them are not built in the bind")
	assert_eq(slot_map.async_starts, 1, "but on a worker")
	assert_true(slot_map.building())
	assert_true(slot_map.finish(), "landed")
	_dab(doc, COBBLE, 255)
	assert_true(_bind_equal(presence, doc, "the second surface"))
	assert_eq(slot_map.async_lands, 1, "the second surface's first dab took the worker's planes")
	assert_eq(slot_map.starts, 1, "built once, by the worker")
	_dab(doc, COBBLE, 90)
	_bind_equal(presence, doc, "kept after")
	assert_eq(slot_map.starts, 1)


## The kept planes of `slot_map` against a slot map built from zero on `doc` now.
func _assert_planes_fresh(slot_map: PainterPathSlotMap, doc: MapDocument, label: String) -> void:
	var fresh := PainterPathSlotMap.new()
	fresh._rebuild(doc, PainterGroundPaths.slots(doc))
	assert_true(slot_map._valid, label + ": planes kept")
	assert_eq(slot_map._slot_of, fresh._slot_of, label + ": slots")
	assert_eq(slot_map._plane, fresh._plane, label + ": weight planes")
	assert_eq(slot_map._tmp, fresh._tmp, label + ": horizontal pass")
	assert_eq(slot_map._blur, fresh._blur, label + ": blurred planes")
	assert_eq(slot_map._bytes, fresh._bytes, label + ": slot bytes")


func test_the_loaded_maps_planes_equal_fresh_ones_after_edits_during_the_build() -> void:
	for round in 6:
		var doc := _doc()
		_meadow(doc)
		for k in 4:
			_dab(doc, DIRT, _rng.randi_range(1, 255))
		var presence := PainterPathPresence.new()
		var slot_map := presence.slot_map
		_bind_equal(presence, doc, "opened %d" % round)
		# Dabs of the one path while the worker runs (or after it landed): the same build is kept,
		# and the rows they changed are applied when it is adopted.
		for k in round:
			_dab(doc, DIRT, 0 if k == 2 else _rng.randi_range(1, 255))
			assert_false(_bind_equal(presence, doc, "dirt %d.%d" % [round, k]), "one path")
		assert_eq(slot_map.async_starts, 1, "one build for the whole session")
		slot_map.finish()
		_dab(doc, COBBLE if round % 2 == 0 else FLAG, 220)
		assert_true(_bind_equal(presence, doc, "second surface %d" % round))
		assert_eq(slot_map.async_lands, 1, "adopted")
		_assert_planes_fresh(slot_map, doc, "round %d" % round)


func test_another_surface_list_starts_the_build_again() -> void:
	# Index 1 the road, then the cobble appended as index 2 (a surface list only grows).
	var doc := _doc()
	doc.surface_ids = PackedStringArray([IDS[MEADOW], IDS[DIRT]])
	_meadow(doc)
	_dab(doc, 1, 255)
	var presence := PainterPathPresence.new()
	var slot_map := presence.slot_map
	_bind_equal(presence, doc, "opened")
	# A list change while the build runs: a build for the new list, the old one let go (or, when
	# it landed first, adopted and kept as any kept planes are).
	doc.surface_ids = PackedStringArray([IDS[MEADOW], IDS[DIRT], IDS[COBBLE]])
	_dab(doc, 1, 100)
	_bind_equal(presence, doc, "the list grew while the build ran")
	assert_lte(slot_map.async_starts, 2)
	slot_map.finish()
	# A list grown again after the build landed (painted nowhere yet): kept, then adopted.
	doc.surface_ids = PackedStringArray([IDS[MEADOW], IDS[DIRT], IDS[COBBLE], IDS[FLAG]])
	_dab(doc, 3, 200)
	assert_true(_bind_equal(presence, doc, "second"))
	assert_eq(slot_map.async_lands, 1, "adopted")
	_assert_planes_fresh(slot_map, doc, "after the list grew")


## A document large enough that its build takes a while on a worker.
func _large_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(64, 64), "grass_meadow", "test", 3)
	doc.surface_ids = PackedStringArray(IDS)
	var weights := PackedByteArray()
	weights.resize(doc.sample_count() * MapDocument.SURFACE_BYTES)
	var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	for i in doc.sample_count():
		weights[i * 4] = MEADOW
		weights[n4 + i * 4] = 200
		weights[i * 4 + 1] = DIRT
		weights[n4 + i * 4 + 1] = (i * 37) % 256
	doc.surface_weights = weights
	return doc


func test_a_load_closed_mid_build_lets_the_task_go() -> void:
	var doc := _large_doc()
	var presence := PainterPathPresence.new()
	PainterGroundPaths.bind([ShaderMaterial.new()], doc, true, presence)
	assert_true(presence.slot_map.building(), "a build started")
	var running: bool = presence.slot_map._task >= 0
	var before := PainterPathSlotMap.abandoned_count()
	var t0 := Time.get_ticks_usec()
	presence.slot_map.cancel()
	assert_false(presence.slot_map.building(), "let go")
	PainterGroundPaths.bind([ShaderMaterial.new()], doc, true, presence)
	# The map closed: the slot map and its presence freed with the build in flight.
	presence = null
	var closed_ms := (Time.get_ticks_usec() - t0) / 1000.0
	gut.p("in flight %s, let go and freed in %.2f ms" % [running, closed_ms])
	assert_lt(closed_ms, 20.0, "closing never waits for the build")
	assert_gte(PainterPathSlotMap.abandoned_count(), before, "the tasks wait to be reaped")
	for frame in 600:
		if PainterPathSlotMap.abandoned_count() == 0:
			break
		await get_tree().process_frame
	assert_eq(PainterPathSlotMap.abandoned_count(), 0, "every task let go was reaped")


func test_a_path_base_and_a_new_document_follow_too() -> void:
	var presence := PainterPathPresence.new()
	var doc := _doc()
	doc.base_surface = "dirt_road_packed"
	_bind_equal(presence, doc, "a path base, no paint")
	_dab(doc, COBBLE, 255)
	_bind_equal(presence, doc, "a path base and cobble")
	var other := _doc()
	_meadow(other)
	_bind_equal(presence, other, "another document, no path")
	_dab(other, FLAG, 120)
	_bind_equal(presence, other, "its first path")
	_dab(other, DIRT, 255)
	assert_true(_bind_equal(presence, other, "its second"))


## TerrainSkirt.edge_surface as it read before, one walk per slot.
func _edge_reference(doc: MapDocument) -> int:
	var slots := doc.surface_ids.size()
	if slots == 0 or doc.surface_weights.is_empty():
		return -1
	var edge := PackedInt32Array()
	var last_x := doc.samples_x() - 1
	var last_z := doc.samples_z() - 1
	for x in last_x + 1:
		edge.append(doc.sample_index(x, 0))
		edge.append(doc.sample_index(x, last_z))
	for z in range(1, last_z):
		edge.append(doc.sample_index(0, z))
		edge.append(doc.sample_index(last_x, z))
	var best := -1
	var best_mean := TerrainSkirt.EDGE_SURFACE_SHARE * 255.0
	for slot in slots:
		var total := 0
		for i in edge:
			total += doc.surface_weight(i, slot)
		var mean := float(total) / maxf(edge.size(), 1.0)
		if mean >= best_mean:
			best_mean = mean
			best = slot
	return best


func test_the_edge_surface_in_one_walk_reads_as_one_walk_a_slot() -> void:
	var seen := {}
	for round in 40:
		var doc := _doc()
		var n4 := doc.sample_count() * MapDocument.SURFACE_CHANNELS
		var weights := doc.surface_weights
		var heavy := _rng.randi_range(0, 4)
		for at in n4:
			# On half the maps one index heavy in every first entry (it passes the share); else and
			# in the other entries any index, duplicates and indices past the list included.
			if at % 4 == 0 and round % 2 == 0:
				weights[at] = heavy
				weights[n4 + at] = _rng.randi_range(170, 255)
				continue
			weights[at] = _rng.randi_range(0, 5)
			weights[n4 + at] = _rng.randi_range(0, 255) if _rng.randf() < 0.8 else 0
		doc.surface_weights = weights
		var got := TerrainSkirt.edge_surface(doc)
		assert_eq(got, _edge_reference(doc), "round %d" % round)
		seen[got] = true
	assert_gt(seen.size(), 1, "both a surface and none were found: %s" % [seen.keys()])
	var empty := _doc()
	empty.surface_weights = PackedByteArray()
	assert_eq(TerrainSkirt.edge_surface(empty), _edge_reference(empty), "no weights")


# --- the warmed colour ----------------------------------------------------------------------


func _terrain() -> AuthoredTerrain:
	var doc := MapDocument.create_flat(Vector2i(30, 30), "grass_birch", "test", 5)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	return terrain


func _paint(terrain: AuthoredTerrain, surface: String) -> void:
	var doc := terrain.document
	var id := doc.ensure_surface(surface)
	for z in 6:
		for x in 6:
			doc.set_surface_weight(doc.sample_index(x, z), id, 200)
	terrain.update_ground_region(Rect2i(0, 0, 6, 6))


func _ground(terrain: AuthoredTerrain) -> Array:
	var material := terrain.get_material()
	var out := []
	for uniform in ["layer_tint", "broad_present", "paint_layer", "layer_flags", "layer_tile_m"]:
		out.append(material.get_shader_parameter(uniform))
	out.append(terrain.layer_binding().tint_mirror.get_data())
	out.append(terrain.ground_layers())
	return out


func test_a_warmed_built_surface_draws_as_a_cold_one() -> void:
	var surface := "cobblestone"
	var entry: Dictionary = PaletteLibrary.surfaces(PaletteLibrary.DEFAULT_ROOT).get(surface, {})
	assert_eq(String(entry.get("role", "")), "built", "the cobble is a built surface")
	var key := PaletteLibrary.DEFAULT_ROOT + "|" + surface
	GroundBroadTint._colors.erase(key)
	var cold := _terrain()
	_paint(cold, surface)
	var cold_ground := _ground(cold)
	GroundBroadTint._colors.erase(key)
	var warm := _terrain()
	var binding := warm.layer_binding()
	warm.prepare_surfaces(PackedStringArray([surface]))
	var steps := 0
	while binding.is_preparing() and steps < 50:
		binding.prepare_step()
		steps += 1
	assert_true(GroundBroadTint._colors.has(key), "the prepare warmed the colour")
	_paint(warm, surface)
	assert_eq(_ground(warm), cold_ground, "the same tables, tints and layers as a cold start")
