extends GutTest

## Crossings at runtime (phase 4b, P4b-1): the snapping rule (CrossingPlacement), the pure
## geometry (CrossingGeometry: the arch, the deck field, stones one stride apart, winding,
## collision, scatter clearance), the AuthoredCrossings node (layer-1 bodies the brushes can
## exclude, tokens landing on a deck, the grid's field raised to the deck), the load's worker
## part, and the scatter keeping off a crossing.

const RIVER_LEVEL := -0.2
const BED := -1.0
const EPSILON := 0.0001
## Ground shapes shared with the water tests (the tier fall, P4c-5).
const Fixtures := preload("res://tests/unit/water_fixtures.gd")

var _root: Node3D = null


func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = null


## A flat 20 x 20 cell map (30.48 m) with a straight channel carved to BED along X over
## -10..10 m, 1.5 m either side of Z = 0, holding a waist-deep river at RIVER_LEVEL.
func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 7)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 10.0 and absf(p.y) <= 1.5:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5, 1.5])
	doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, RIVER_LEVEL))
	return doc


func _placed(
	doc: MapDocument, kind: Crossing.Kind, from := Vector2(0.3, -1), to := Vector2(0, 1)
) -> Crossing:
	var placed := CrossingPlacement.place(doc, from, to, kind)
	assert_eq(placed.refusal, &"", "placed")
	var crossing: Crossing = placed.crossing
	if crossing != null:
		crossing.id = 1
		doc.crossings.append(crossing)
	return crossing


# --- placement ------------------------------------------------------------------------


func test_a_short_line_over_the_water_snaps_to_both_banks() -> void:
	var doc := _doc()
	var crossing := _placed(doc, Crossing.Kind.PLANK, Vector2(0, -0.5), Vector2(0, 0.5))
	assert_lt(crossing.start.y, -1.5, "starts on the near bank")
	assert_gt(crossing.end.y, 1.5, "ends on the far bank")
	assert_almost_eq(crossing.start.x, 0.0, EPSILON, "keeps the drawn line")
	for anchor in [crossing.start, crossing.end]:
		assert_false(WaterGeometry.is_wet_at(doc, anchor), "an anchor is on dry ground")
		assert_almost_eq(WaterGeometry.ground_at(doc, anchor), 0.0, EPSILON, "on the bank top")
	# Waterline (about 1.7 m out) plus the plank inset.
	assert_almost_eq(crossing.span_m(), 2.0 * (1.7 + 0.55), 0.2)
	assert_almost_eq(crossing.width_m, Crossing.DEFAULT_WIDTH_M[Crossing.Kind.PLANK], EPSILON)


func test_a_long_line_is_trimmed_to_the_banks_it_crosses() -> void:
	var doc := _doc()
	var short := CrossingPlacement.anchor(
		doc, Vector2(0, -0.5), Vector2(0, 0.5), Crossing.Kind.PLANK
	)
	var long := CrossingPlacement.anchor(doc, Vector2(0, -6), Vector2(0, 6), Crossing.Kind.PLANK)
	assert_true(long.start.is_equal_approx(short.start) and long.end.is_equal_approx(short.end))
	var reversed := CrossingPlacement.anchor(
		doc, Vector2(0, 6), Vector2(0, -6), Crossing.Kind.PLANK
	)
	assert_gt(reversed.start.y, 1.5, "the drawn direction is kept")


func test_levels_arch_over_the_water_and_stones_sit_just_above_it() -> void:
	var doc := _doc()
	var plank := CrossingPlacement.anchor(doc, Vector2(0, -1), Vector2(0, 1), Crossing.Kind.PLANK)
	var ends := 0.0 + CrossingGeometry.DECK_ABOVE_BANK_M
	assert_almost_eq(plank.levels.x, ends, EPSILON)
	assert_almost_eq(plank.levels.z, ends, EPSILON)
	assert_gt(plank.levels.y, ends + CrossingPlacement.MIN_RISE_M - EPSILON, "a gentle arch")
	assert_gt(plank.levels.y, RIVER_LEVEL + CrossingPlacement.DECK_CLEAR_M - EPSILON)
	var stones := CrossingPlacement.anchor(doc, Vector2(0, -1), Vector2(0, 1), Crossing.Kind.STONES)
	assert_almost_eq(stones.levels.y, RIVER_LEVEL + CrossingPlacement.STONE_FREEBOARD_M, EPSILON)
	assert_lt(stones.span_m(), plank.span_m(), "stones step off nearer the edge")


func test_refusals() -> void:
	var doc := _doc()
	var kind := Crossing.Kind.PLANK
	assert_eq(CrossingPlacement.place(doc, Vector2.ZERO, Vector2(0, 0.1), kind).refusal, &"short")
	assert_eq(
		CrossingPlacement.place(doc, Vector2(0, 5), Vector2(0, 7), kind).refusal,
		&"no_water",
		"dry ground"
	)
	# Along the river: the wet run reaches past the search on both sides.
	assert_eq(CrossingPlacement.place(doc, Vector2(-2, 0), Vector2(2, 0), kind).refusal, &"no_bank")
	# Water running off the map edge.
	var edge := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 7)
	var heights := edge.heights.duplicate()
	for z in edge.samples_z():
		for x in edge.samples_x():
			if edge.sample_to_world(Vector2(x, z)).y > 12.0:
				heights[edge.sample_index(x, z)] = BED
	edge.heights = heights
	var line := PackedVector2Array([Vector2(-10, 14), Vector2(10, 14)])
	edge.water_bodies.append(
		WaterBody.river(1, line, PackedFloat32Array([3, 3]), WaterBody.Depth.WAIST, RIVER_LEVEL)
	)
	assert_eq(
		CrossingPlacement.place(edge, Vector2(0, 11), Vector2(0, 14), kind).refusal, &"no_bank"
	)


func test_a_span_over_the_cap_is_refused() -> void:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "test", 7)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			if absf(doc.sample_to_world(Vector2(x, z)).y) <= 14.0:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	# Two wide rivers side by side: 28 m of water.
	for k in 2:
		var z := -6.5 if k == 0 else 6.5
		var line := PackedVector2Array([Vector2(-20, z), Vector2(20, z)])
		doc.water_bodies.append(
			WaterBody.river(
				k + 1, line, PackedFloat32Array([7, 7]), WaterBody.Depth.DEEP, RIVER_LEVEL
			)
		)
	var placed := CrossingPlacement.place(doc, Vector2(0, -14), Vector2(0, 14), Crossing.Kind.PLANK)
	assert_eq(placed.refusal, &"long")


func test_a_narrow_bar_mid_stream_is_part_of_the_water() -> void:
	var doc := _doc()
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.y) <= 0.2 and absf(p.x) <= 10.0:
				heights[doc.sample_index(x, z)] = 0.0
	doc.heights = heights
	var crossing := CrossingPlacement.anchor(
		doc, Vector2(0, -1), Vector2(0, -0.5), Crossing.Kind.PLANK
	)
	assert_gt(crossing.end.y, 1.5, "spans the bar to the far bank")


func test_a_crossing_keeps_clear_of_a_waterfall() -> void:
	# P4c-5: a waist river over a tier (one fall at the brink, flowing +Z). A line beside the
	# fall, over its plunge pool, is refused with the fall's own message; one across the face
	# is refused too (level_at has no flush cut at the lip, so the face reads the upper pool's
	# level and is "wet": the fall message says more than "no water" would); a line 2 m
	# upstream of the lip and one 2 m downstream of the foam ring cross calm water.
	var doc := MapDocument.create_flat(Vector2i(30, 30), "grass", "test", 5)
	Fixtures.tier_fall(doc)
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 1, "the tier makes one fall")
	var fall: Dictionary = falls[0]
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	assert_almost_eq(dir.y, 1.0, 0.05, "falls toward +Z")
	var kind := Crossing.Kind.PLANK
	var foot := lip + dir * WaterFalls.face_foot(doc, fall)
	var beside := CrossingPlacement.place(
		doc, foot + Vector2(-0.5, 0.5), foot + Vector2(0.5, 0.5), kind
	)
	assert_eq(beside.refusal, CrossingPlacement.REFUSED_FALL, "over the plunge pool")
	assert_eq(
		BridgeBrush.refusal_text(beside.refusal, 1.524, 5.0, "ft"),
		"Too close to the waterfall. Bridges cross calm water."
	)
	var mid := lip + dir * 0.6
	var face := CrossingPlacement.place(doc, mid + Vector2(-3, 0), mid + Vector2(3, 0), kind)
	assert_eq(face.refusal, CrossingPlacement.REFUSED_FALL, "across the face")
	var up := lip - dir * 2.0
	var upstream := CrossingPlacement.place(doc, up + Vector2(-0.5, 0), up + Vector2(0.5, 0), kind)
	assert_eq(upstream.refusal, &"", "2 m upstream of the lip: calm water")
	var radius := WaterFallMesh.ring_radius(2.0 * float(fall.half_width))
	var centre := WaterFallMesh.ring_centre(lip, dir, WaterFalls.face_foot(doc, fall), radius)
	var down := centre + dir * (radius + 2.0)
	var downstream := CrossingPlacement.place(
		doc, down + Vector2(-0.5, 0), down + Vector2(0.5, 0), kind
	)
	assert_eq(downstream.refusal, &"", "2 m downstream of the ring: calm water")
	var crossing: Crossing = downstream.crossing
	assert_false(
		CrossingPlacement.fall_near(doc, crossing.start, crossing.end, crossing.width_m),
		"the placed deck is clear of the fall"
	)
	assert_true(
		CrossingPlacement.fall_near(doc, foot + Vector2(-3, 0.5), foot + Vector2(3, 0.5), 1.5),
		"a strip over the pool is not"
	)


func test_style_at_reads_the_biome_mask() -> void:
	var doc := _doc()
	assert_eq(CrossingPlacement.style_at(doc, Vector2.ZERO), "", "no biomes")
	doc.biome_ids = PackedStringArray(["a_biome", "b_biome"])
	assert_eq(CrossingPlacement.style_at(doc, Vector2.ZERO), "a_biome", "the first biome")
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(2)
	doc.biome_slots = slots
	doc.biome_density = slots.duplicate()
	assert_eq(CrossingPlacement.style_at(doc, Vector2.ZERO), "b_biome")


# --- geometry -------------------------------------------------------------------------


func test_deck_profile_passes_through_the_three_levels() -> void:
	var levels := Vector3(0.2, 0.7, 0.4)
	assert_almost_eq(CrossingGeometry.deck_y(levels, 0.0), 0.2, EPSILON)
	assert_almost_eq(CrossingGeometry.deck_y(levels, 0.5), 0.7, EPSILON)
	assert_almost_eq(CrossingGeometry.deck_y(levels, 1.0), 0.4, EPSILON)
	var crossing := Crossing.make(
		1, Crossing.Kind.PLANK, Vector2(-2, 0), Vector2(2, 0), levels, 1.5
	)
	var top := CrossingGeometry.deck_top(crossing)
	assert_gte(top, 0.7)
	for k in 101:
		assert_lte(CrossingGeometry.deck_y(levels, k / 100.0), top + EPSILON)
	var h := 1e-4
	var numeric := (
		(CrossingGeometry.deck_y(levels, 0.3 + h) - CrossingGeometry.deck_y(levels, 0.3 - h))
		/ (2 * h)
	)
	assert_almost_eq(CrossingGeometry.deck_slope(levels, 0.3), numeric, 1e-3)


func test_deck_field_covers_the_deck_only() -> void:
	var doc := _doc()
	var crossing := _placed(doc, Crossing.Kind.PLANK)
	var field := CrossingGeometry.deck_field(doc, doc.crossings)
	assert_eq(field.size(), doc.sample_count())
	var middle := doc.world_to_sample((crossing.start + crossing.end) * 0.5).round()
	var at := doc.sample_index(int(middle.x), int(middle.y))
	assert_almost_eq(field[at], crossing.levels.y, 0.02, "the arch's top at the middle")
	var far := doc.world_to_sample(Vector2(5, 0)).round()
	assert_eq(field[doc.sample_index(int(far.x), int(far.y))], CrossingGeometry.NONE)
	var covered := 0
	for value in field:
		covered += 1 if value > CrossingGeometry.NONE else 0
	var pad := 2.0 * CrossingGeometry.DECK_FIELD_PAD_M
	var area := (crossing.span_m() + pad) * (crossing.width_m + pad)
	var step := doc.sample_step()
	assert_almost_eq(covered * step.x * step.y, area, area * 0.2, "about the padded deck")
	var stones := _doc()
	_placed(stones, Crossing.Kind.STONES)
	assert_true(CrossingGeometry.deck_field(stones, stones.crossings).is_empty(), "no deck")


func test_plank_bridge_parts() -> void:
	var doc := _doc()
	var crossing := _placed(doc, Crossing.Kind.PLANK)
	var parts := CrossingGeometry.build_one(doc, crossing)
	assert_false((parts.wood as Array).is_empty())
	assert_true((parts.stone as Array).is_empty())
	assert_almost_eq(float(parts.top), CrossingGeometry.deck_top(crossing), EPSILON)
	var faces: PackedVector3Array = parts.collision
	assert_eq(faces.size() % 3, 0)
	for v in faces:
		var uv := CrossingGeometry.local_of(crossing, Vector2(v.x, v.z))
		var expected := CrossingGeometry.deck_y(crossing.levels, uv.x / crossing.span_m())
		assert_almost_eq(v.y, expected, 0.001, "the collision is the walking surface")
	# The planks' tops are the walking surface, and nothing inside the rails stands above it.
	var vertices: PackedVector3Array = parts.wood[Mesh.ARRAY_VERTEX]
	var plank_tops := 0
	var half := crossing.width_m * 0.5
	for v in vertices:
		var uv := CrossingGeometry.local_of(crossing, Vector2(v.x, v.z))
		if uv.x < 0.3 or uv.x > crossing.span_m() - 0.3 or absf(uv.y) > half + 0.1:
			continue
		var deck := CrossingGeometry.deck_y(crossing.levels, uv.x / crossing.span_m())
		if absf(uv.y) < half - 0.1:
			assert_lte(v.y, deck + 0.01, "nothing stands above the deck on the path")
		if absf(v.y - deck) < 0.015:
			plank_tops += 1
	assert_gt(plank_tops, 40, "plank tops on the walking surface")


func test_every_triangle_faces_its_normal_clockwise() -> void:
	var doc := _doc()
	for kind in [Crossing.Kind.PLANK, Crossing.Kind.STONES]:
		var crossing := CrossingPlacement.anchor(doc, Vector2(0, -1), Vector2(0, 1), kind)
		crossing.id = 3
		var parts := CrossingGeometry.build_one(doc, crossing)
		var arrays: Array = parts.wood if kind == Crossing.Kind.PLANK else parts.stone
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var wrong := 0
		for t in range(0, indices.size(), 3):
			var a := vertices[indices[t]]
			var cross := (vertices[indices[t + 1]] - a).cross(vertices[indices[t + 2]] - a)
			if cross.length() > 1e-9 and cross.dot(normals[indices[t]]) >= 0.0:
				wrong += 1
		assert_eq(wrong, 0, "kind %d: clockwise from the front" % kind)
		for n in normals:
			assert_almost_eq(n.length(), 1.0, 1e-3)


func test_stones_one_stride_apart_above_the_water_and_rooted() -> void:
	var doc := _doc()
	var crossing := _placed(doc, Crossing.Kind.STONES)
	var stones := CrossingGeometry.stone_layout(doc, crossing)
	assert_gte(stones.size(), 2)
	for k in stones.size():
		var stone: Dictionary = stones[k]
		assert_gt(float(stone.top), RIVER_LEVEL + 0.05, "a dry top over WaterZone's slab")
		assert_lt(float(stone.top), RIVER_LEVEL + 0.2, "just above the water")
		if k > 0:
			var gap := (stone.at as Vector2).distance_to(stones[k - 1].at)
			assert_almost_eq(gap, doc.cell_size_m, 0.35, "about one grid square per step")
	var parts := CrossingGeometry.build_one(doc, crossing)
	var vertices: PackedVector3Array = parts.stone[Mesh.ARRAY_VERTEX]
	var lowest := INF
	for v in vertices:
		lowest = minf(lowest, v.y)
	assert_lt(lowest, BED, "the roots reach under the bed")
	assert_false((parts.collision as PackedVector3Array).is_empty())
	assert_true(CrossingGeometry.deck_field(doc, doc.crossings).is_empty())


func test_build_is_deterministic() -> void:
	var a := _doc()
	var b := _doc()
	_placed(a, Crossing.Kind.PLANK)
	_placed(b, Crossing.Kind.PLANK)
	var first := CrossingGeometry.build(a)
	var second := CrossingGeometry.build(b)
	var wa: Array = first.crossings[0].wood
	var wb: Array = second.crossings[0].wood
	assert_true(wa[Mesh.ARRAY_VERTEX] == wb[Mesh.ARRAY_VERTEX], "every peer builds the same")
	b.map_seed = 8
	var reseeded: Array = CrossingGeometry.build(b).crossings[0].wood
	assert_false(wa[Mesh.ARRAY_VERTEX] == reseeded[Mesh.ARRAY_VERTEX], "the seed varies it")


func test_clearance_clears_the_footprint_and_bank_landings() -> void:
	var doc := _doc()
	var crossing := _placed(doc, Crossing.Kind.PLANK)
	var middle := (crossing.start + crossing.end) * 0.5
	assert_eq(CrossingGeometry.clearance(doc.crossings, middle), 0.0, "under the deck")
	var landing := crossing.end + crossing.direction() * 0.5
	assert_eq(CrossingGeometry.clearance(doc.crossings, landing), 0.0, "on the bank landing")
	assert_eq(CrossingGeometry.clearance(doc.crossings, Vector2(6, 6)), 1.0, "far away")
	var beside := middle + Vector2(1, 0) * (crossing.width_m * 0.5 + 0.35 + 0.25)
	var partial := CrossingGeometry.clearance(doc.crossings, beside)
	assert_true(partial > 0.0 and partial < 1.0, "a soft edge")
	assert_true(CrossingGeometry.clear_bounds(crossing).has_point(landing))
	var tree_extra := CrossingGeometry.CLEAR_TREE_M
	assert_eq(
		CrossingGeometry.clearance(doc.crossings, beside, tree_extra), 0.0, "trees keep back more"
	)
	var past_landing := crossing.end + crossing.direction() * 1.8
	assert_eq(CrossingGeometry.clearance(doc.crossings, past_landing), 1.0)
	assert_eq(CrossingGeometry.clearance(doc.crossings, past_landing, tree_extra), 0.0)
	assert_true(CrossingGeometry.clear_bounds(crossing).has_point(past_landing))


func test_scatter_ground_keeps_plants_off_a_crossing() -> void:
	var doc := _doc()
	var crossing := _placed(doc, Crossing.Kind.PLANK)
	var grid := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	var landing := crossing.end + crossing.direction() * 0.5
	var sampler := ScatterGround.sampler(doc, doc.heights, grid, PackedStringArray())
	assert_eq(sampler.call(landing, ScatterGround.ROLE_COVER).x, 0.0, "cleared at the landing")
	assert_eq(sampler.call(landing, ScatterGround.ROLE_ROCK).x, 0.0, "rocks too")
	doc.crossings.clear()
	var bare := ScatterGround.sampler(doc, doc.heights, grid, PackedStringArray())
	assert_gt(bare.call(landing, ScatterGround.ROLE_COVER).x, 0.5, "grows without the crossing")


# --- nodes ----------------------------------------------------------------------------


## An authored root in the tree: terrain collision (layer 1), the water and the crossings.
func _authored_in_tree(doc: MapDocument) -> AuthoredCrossings:
	_root = Node3D.new()
	_root.add_child(AuthoredTerrain.create(doc))
	add_child(_root)
	MapSourceLoader.add_authored_water(_root, doc, false)
	return MapSourceLoader.add_authored_crossings(_root, doc, false)


func test_nodes_bodies_and_exclusion() -> void:
	var doc := _doc()
	_placed(doc, Crossing.Kind.PLANK)
	var stones := CrossingPlacement.anchor(doc, Vector2(4, -1), Vector2(4, 1), Crossing.Kind.STONES)
	stones.id = 2
	doc.crossings.append(stones)
	var node := _authored_in_tree(doc)
	assert_not_null(node)
	assert_eq(node.name, AuthoredCrossings.NODE_NAME)
	assert_not_null(node.get_crossing_node(1).get_node("Wood"))
	assert_not_null(node.get_crossing_node(2).get_node("Stones"))
	for crossing_id in [1, 2]:
		var body := node.get_crossing_node(crossing_id).get_node("Collision") as StaticBody3D
		assert_eq(body.collision_layer, WaterSurface.TERRAIN_LAYER)
		assert_eq(body.collision_mask, 0)
		assert_false(body.input_ray_pickable)
		assert_eq(body.get_meta(AuthoredCrossings.CROSSING_META), crossing_id)
	assert_eq(AuthoredCrossings.exclude_of(_root).size(), 2)
	assert_true(node.has_decks())
	assert_almost_eq(node.top_y, CrossingGeometry.deck_top(doc.crossings[0]), EPSILON)
	remove_child(_root)


func test_no_node_without_crossings_unless_asked() -> void:
	var doc := _doc()
	_root = Node3D.new()
	assert_null(MapSourceLoader.add_authored_crossings(_root, doc, false))
	var always := MapSourceLoader.add_authored_crossings(_root, doc, true)
	assert_not_null(always)
	assert_false(always.has_decks())
	assert_eq(always.top_y, -INF)


func test_tokens_land_on_the_deck_and_stones_and_brushes_see_the_bed() -> void:
	var doc := _doc()
	var plank := _placed(doc, Crossing.Kind.PLANK)
	var stones := CrossingPlacement.anchor(doc, Vector2(5, -1), Vector2(5, 1), Crossing.Kind.STONES)
	stones.id = 2
	doc.crossings.append(stones)
	_authored_in_tree(doc)
	await get_tree().physics_frame
	var space := _root.get_world_3d().direct_space_state
	var middle := (plank.start + plank.end) * 0.5
	var over := Vector3(middle.x, 0.0, middle.y)
	var landing := WaterSurface.landing_below(space, over, 3.0)
	var deck := CrossingGeometry.deck_y(
		plank.levels, CrossingGeometry.local_of(plank, middle).x / plank.span_m()
	)
	assert_almost_eq(landing.y, deck, 0.01, "a token stands on the deck")
	var stone: Dictionary = CrossingGeometry.stone_layout(doc, doc.crossings[1])[0]
	var at: Vector2 = stone.at
	var on_stone := WaterSurface.landing_below(space, Vector3(at.x, 0, at.y), 3.0)
	assert_almost_eq(on_stone.y, float(stone.top), 0.03, "a token stands on a stone")
	var bed := WaterSurface.cast_down(
		space, over, 3.0, WaterSurface.TERRAIN_LAYER, AuthoredCrossings.exclude_of(_root)
	)
	assert_almost_eq((bed.position as Vector3).y, BED, 0.01, "a brush ray sees the bed")
	remove_child(_root)


func test_grid_field_runs_across_the_deck() -> void:
	var doc := _doc()
	var plank := _placed(doc, Crossing.Kind.PLANK)
	_authored_in_tree(doc)
	var terrain := _root.get_node("AuthoredTerrain") as AuthoredTerrain
	var field := GroundHeightField.from_terrain(terrain)
	assert_true(field.has_decks())
	var middle := (plank.start + plank.end) * 0.5
	assert_almost_eq(field.world_height_at(middle), plank.levels.y, 0.02, "on the deck")
	assert_almost_eq(field.world_height_at(Vector2(6, 0)), RIVER_LEVEL, EPSILON, "on the water")
	assert_almost_eq(field.world_height_at(Vector2(6, 8)), 0.0, EPSILON, "on dry ground")
	# The height texture keeps the water under the deck; the deck is its own texture.
	var image := field.get_texture().get_image()
	var s := Vector2i(doc.world_to_sample(middle).round())
	assert_almost_eq(image.get_pixelv(s).r, RIVER_LEVEL, EPSILON, "the water under the deck")
	assert_eq(image.get_pixelv(s).g, 1.0, "still flagged water")
	var decks := field.get_deck_texture()
	assert_not_null(decks)
	var deck_image := decks.get_image()
	assert_almost_eq(deck_image.get_pixelv(s).r, plank.levels.y, 0.02, "the deck's texel")
	var river := Vector2i(doc.world_to_sample(Vector2(6, 0)).round())
	assert_eq(deck_image.get_pixelv(river).r, GroundHeightField.NO_DECK, "no deck on the river")
	# A rebuild recomposes.
	doc.crossings.clear()
	AuthoredCrossings.refresh_map(_root, doc)
	assert_false(field.has_decks())
	assert_null(field.get_deck_texture())
	assert_almost_eq(field.world_height_at(middle), RIVER_LEVEL, EPSILON, "deck gone")
	remove_child(_root)


func test_a_terrain_with_decks_but_no_water_composes() -> void:
	var doc := _doc()
	var plank := _placed(doc, Crossing.Kind.PLANK)
	doc.water_bodies.clear()
	_authored_in_tree(doc)
	var terrain := _root.get_node("AuthoredTerrain") as AuthoredTerrain
	var field := GroundHeightField.from_terrain(terrain)
	assert_false(field.has_water())
	assert_ne(field.get_texture(), terrain.get_height_texture())
	var middle := (plank.start + plank.end) * 0.5
	assert_almost_eq(field.world_height_at(middle), plank.levels.y, 0.02)
	remove_child(_root)


func test_raise_to_decks_and_deck_image_are_pure() -> void:
	var heights := PackedFloat32Array([0.0, -0.2, 0.5])
	var decks := PackedFloat32Array([CrossingGeometry.NONE, 0.4, 0.3])
	assert_eq(GroundHeightField.raise_to_decks(heights, decks), PackedFloat32Array([0.0, 0.4, 0.5]))
	assert_eq(heights, PackedFloat32Array([0.0, -0.2, 0.5]), "input untouched")
	var image := GroundHeightField.deck_image(decks, 3, 1)
	assert_eq(image.get_format(), Image.FORMAT_RF)
	assert_eq(image.get_pixel(0, 0).r, GroundHeightField.NO_DECK, "no deck: a finite marker")
	assert_almost_eq(image.get_pixel(1, 0).r, 0.4, EPSILON)


func test_load_prep_builds_crossings_on_a_worker() -> void:
	var doc := _doc()
	_placed(doc, Crossing.Kind.PLANK)
	var prep := AuthoredLoadPrep.start(doc)
	var merged := prep.finish()
	assert_true(merged.has(AuthoredLoadPrep.CROSSINGS))
	var built: Dictionary = merged[AuthoredLoadPrep.CROSSINGS]
	var here := CrossingGeometry.build(doc)
	assert_true(built.deck == here.deck, "the worker's deck field is the same")
	var node := AuthoredCrossings.create(doc, built)
	assert_not_null(node.get_crossing_node(1))
	node.free()
	var dry := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 7)
	assert_false(AuthoredLoadPrep.compute(dry).has(AuthoredLoadPrep.CROSSINGS))
