extends GutTest

## Build hitches round 3 (topic hitches3, docs/PERFORMANCE.md "Build hitches, round 3"): the
## structure warm-up's per-frame schedule (a material and its first draw never share a frame, a
## frame stops at its budget, a draw ends it, pause and resume, a map closed mid-way), and the
## ground's broad tint kept in place when a map's last painted surface slots are trimmed (clearing
## its last dressing), with the same bytes a full rebuild makes.

const STYLE := "temperate_forest_summer_s1"
const FRAME_LIMIT := 300


func _warmup() -> Array:
	StructureRecipes.ensure_served()
	var map := Node3D.new()
	add_child_autofree(map)
	var structures := AuthoredStructures.of_map(map)
	var node := StructureWarmup.warm(
		structures, PackedStringArray([STYLE]), PaletteLibrary.DEFAULT_ROOT
	)
	node.idle_frame_ms = INF
	return [map, structures, node]


func _run_out(node: StructureWarmup) -> void:
	for frame in FRAME_LIMIT:
		if not is_instance_valid(node):
			return
		await get_tree().process_frame


func test_a_material_and_its_draws_never_share_a_frame_and_a_draw_ends_one() -> void:
	var held := _warmup()
	var node: StructureWarmup = held[2]
	await _run_out(node)
	assert_false(is_instance_valid(node), "done and freed")
	var log := StructureWarmup.last_log
	assert_eq(log.size(), StructureWarmup.unit_count(), "every unit once")
	var made_in := {}
	var draws_in := {}
	for k in log.size():
		var entry: Dictionary = log[k]
		assert_eq(int(entry.combo), k / StructureWarmup.UNITS_PER_COMBO, "in COMBOS order")
		assert_eq(int(entry.phase), k % StructureWarmup.UNITS_PER_COMBO, "make, then draw")
		if int(entry.phase) == StructureWarmup.Phase.MAKE:
			made_in[int(entry.combo)] = int(entry.frame)
		else:
			assert_gt(int(entry.frame), int(made_in[int(entry.combo)]), "drawn a later frame")
			draws_in[int(entry.frame)] = int(draws_in.get(int(entry.frame), 0)) + 1
			if k + 1 < log.size():
				assert_gt(int(log[k + 1].frame), int(entry.frame), "a draw ends its frame")
	for frame: int in draws_in:
		assert_eq(int(draws_in[frame]), 1, "one draw a frame")
	var structures: AuthoredStructures = held[1]
	assert_null(StructureWarmup.warm(structures, PackedStringArray([STYLE]), ""), "once per map")


func test_a_spent_budget_ends_the_frame_after_one_unit() -> void:
	var held := _warmup()
	var node: StructureWarmup = held[2]
	node.budget_ms = 0.0
	await _run_out(node)
	var frames := {}
	for entry: Dictionary in StructureWarmup.last_log:
		assert_false(frames.has(int(entry.frame)), "one unit a frame")
		frames[int(entry.frame)] = true
	assert_eq(frames.size(), StructureWarmup.unit_count())


func test_a_busy_frame_is_waited_out_but_not_forever() -> void:
	var held := _warmup()
	var node: StructureWarmup = held[2]
	node.idle_frame_ms = -1.0
	await _run_out(node)
	assert_false(is_instance_valid(node), "a slow machine still warms")
	var log := StructureWarmup.last_log
	for k in range(1, log.size()):
		assert_gt(
			int(log[k].frame) - int(log[k - 1].frame),
			StructureWarmup.MAX_WAIT_FRAMES,
			"every unit waits its busy frames"
		)


func test_pause_holds_and_warm_or_resume_goes_on() -> void:
	var held := _warmup()
	var map: Node3D = held[0]
	var structures: AuthoredStructures = held[1]
	var node: StructureWarmup = held[2]
	for frame in 4:
		await get_tree().process_frame
	StructureWarmup.pause_map(map)
	assert_true(node.paused)
	var at := node.units_done
	for frame in 10:
		await get_tree().process_frame
	assert_eq(node.units_done, at, "nothing runs while paused")
	assert_eq(StructureWarmup.warm(structures, PackedStringArray([STYLE]), ""), node, "the same")
	assert_false(node.paused, "a second open resumes it")
	StructureWarmup.pause_map(map)
	StructureWarmup.resume_map(map)
	assert_false(node.paused, "the brush up again resumes it")
	await _run_out(node)
	assert_false(is_instance_valid(node))
	assert_eq(StructureWarmup.last_log.size(), StructureWarmup.unit_count(), "no unit twice")


func test_a_map_closed_mid_warm_up_frees_cleanly() -> void:
	StructureRecipes.ensure_served()
	var map := Node3D.new()
	add_child(map)
	var node := StructureWarmup.warm(
		AuthoredStructures.of_map(map), PackedStringArray([STYLE]), PaletteLibrary.DEFAULT_ROOT
	)
	await get_tree().process_frame
	map.free()
	assert_false(is_instance_valid(node), "gone with its map")
	await get_tree().process_frame
	# A map with no structures layer: pause and resume do nothing.
	var bare := Node3D.new()
	add_child_autofree(bare)
	StructureWarmup.pause_map(bare)
	StructureWarmup.resume_map(bare)
	assert_null(bare.get_node_or_null(AuthoredStructures.NODE_NAME), "never made here")


func test_trimmed_surface_slots_keep_the_broad_mirror_with_full_rebuild_bytes() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 11)
	doc.biome_ids = PackedStringArray(["temperate_forest_summer_s1"])
	var zeros := PackedByteArray()
	zeros.resize(doc.sample_count())
	doc.biome_slots = zeros
	doc.biome_density = zeros.duplicate()
	var cobble := doc.ensure_surface("cobblestone")
	var flag := doc.ensure_surface("flagstone")
	for z in range(0, 10):
		for x in range(0, 10):
			doc.set_surface_weight(doc.sample_index(x, z), cobble, 200)
	for z in range(40, 46):
		for x in range(40, 46):
			doc.set_surface_weight(doc.sample_index(x, z), flag, 255)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var mirror := terrain.get_broad_tint()
	var texture := terrain.get_broad_texture()
	# The last dressing's paving goes: its slot is left without weight and trimmed.
	for z in range(40, 46):
		for x in range(40, 46):
			doc.set_surface_weight(doc.sample_index(x, z), flag, 0)
	var ids := doc.surface_ids.duplicate()
	assert_eq(ids[ids.size() - 1], "flagstone", "the last slot")
	doc.trim_unused_surfaces()
	assert_eq(doc.surface_ids, ids.slice(0, ids.size() - 1), "flagstone trimmed")
	terrain.update_ground_region(Rect2i(38, 38, 10, 10))
	assert_eq(terrain.get_broad_tint(), mirror, "the mirror is updated in place, not rebuilt")
	assert_eq(terrain.get_broad_texture(), texture, "the same texture")
	var fresh := AuthoredTerrain.create(doc)
	add_child_autofree(fresh)
	assert_eq(
		terrain.get_broad_tint().get_data(),
		fresh.get_broad_tint().get_data(),
		"the bytes a full rebuild makes"
	)
	assert_eq(
		terrain.layer_binding().paint_tints,
		fresh.layer_binding().paint_tints,
		"the same tint table"
	)
	# A changed tint in the kept slots still rebuilds whole.
	doc.surface_ids[cobble] = "planks"
	terrain.update_ground_region(Rect2i(0, 0, 2, 2))
	assert_ne(terrain.get_broad_tint(), mirror, "a recoloured slot rebuilds the mirror")
