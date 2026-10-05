extends GutTest

## Ponds and lakes past the map edge (phase 6, P6-4): PondExits (which ponds reach the edge and
## the lobe their basin runs on in) and its part in RiverExitMesh (the skirt's patch, the water,
## the cache, a pond and a river leaving together).

const POND_ID := 1


## A flat 20 x 20 cell map (30.48 m) with a waist pond painted as a disc at `centre` of
## `radius` (map XZ), its level from its rim and its basin carved as the Water tool does.
func _pond_doc(centre: Vector2, radius: float, seed_value: int = 7) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", seed_value)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).distance_to(centre) <= radius:
				mask[doc.sample_index(x, z)] = POND_ID
	doc.pond_mask = mask
	var body := WaterBody.pond(
		POND_ID, WaterBody.Depth.WAIST, WaterGeometry.pond_rim_level(doc, POND_ID)
	)
	_carve(doc, WaterCarve.pond_goals(doc, body, doc.heights.duplicate()))
	doc.water_bodies = [body] as Array[WaterBody]
	return doc


func _carve(doc: MapDocument, goals: Dictionary) -> void:
	var rect: Rect2i = goals.rect
	var values: PackedFloat32Array = goals.goals
	var carved := doc.heights.duplicate()
	for j in rect.size.y:
		for i in rect.size.x:
			var goal := values[j * rect.size.x + i]
			var at := (rect.position.y + j) * doc.samples_x() + rect.position.x + i
			if not is_inf(goal):
				carved[at] = minf(carved[at], goal)
	doc.heights = carved


func _half(doc: MapDocument) -> Vector2:
	return doc.extent_m() * 0.5


## A wide pond against the near (+z) edge.
func _edge_doc(seed_value: int = 7) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", seed_value)
	return _pond_doc(Vector2(-2.0, _half(doc).y - 2.0), 6.0, seed_value)


func _built(doc: MapDocument, previous: Dictionary = {}) -> Dictionary:
	return RiverExitMesh.build(
		doc,
		AuthoredTerrain.skirt_width_m(),
		AuthoredTerrain.SKIRT_FADE_M,
		AuthoredTerrain.SKIRT_WOBBLE,
		previous
	)


func _pond_ribbons(parts: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece: Dictionary in (parts.pieces as Dictionary).values():
		if piece.has("outline"):
			out.append(piece)
	return out


func test_a_pond_touching_the_edge_gets_an_exit_and_one_inside_none() -> void:
	var inside := _pond_doc(Vector2(0.0, 0.0), 5.0)
	assert_eq(PondExits.exits(inside, AuthoredTerrain.SKIRT_FADE_M), [] as Array[Dictionary])
	assert_false(RiverExitMesh.has_exits(inside))
	assert_eq(_built(inside), {}, "no exit, no patch")
	var doc := _edge_doc()
	var exits := PondExits.exits(doc, AuthoredTerrain.SKIRT_FADE_M)
	assert_eq(exits.size(), 1, "one wet span on the near edge")
	var found: Dictionary = exits[0]
	assert_eq(found.dir, Vector2(0, 1))
	assert_eq((found.mouth as Vector2).y, _half(doc).y, "the mouth on the edge")
	assert_true(RiverExitMesh.has_exits(doc))
	var parts := _built(doc)
	assert_eq((parts.windows as Array).size(), 1)
	assert_false((parts.ribbon as Array).is_empty(), "water past the edge")
	assert_eq(_pond_ribbons(parts).size(), 1)


func test_the_lobe_is_deterministic_from_the_seed() -> void:
	var a: Dictionary = _built(_edge_doc(7)).mouths[0]
	var b: Dictionary = _built(_edge_doc(7)).mouths[0]
	assert_eq(a.length, b.length)
	assert_eq(a[PondExits.WIDTHS], b[PondExits.WIDTHS], "the same shore, bit for bit")
	var lengths := {}
	for seed_value in [1, 2, 3, 4, 5, 6, 8, 9]:
		var mouth: Dictionary = _built(_edge_doc(seed_value)).mouths[0]
		var half_width: float = mouth.half_width
		var length: float = mouth.length
		var open := RiverExits.FADE_REACH_M + half_width
		assert_true(
			(length >= half_width and length < AuthoredTerrain.SKIRT_FADE_M) or length == open,
			"a cove between its half-span and the fade, or an open lake (%f)" % length
		)
		lengths[length] = true
	assert_gt(lengths.size(), 1, "the seed picks the length")


func test_the_lobe_starts_as_the_edge_span_and_closes() -> void:
	var mouth: Dictionary = _built(_edge_doc()).mouths[0]
	var wet: Vector2 = mouth.wet
	assert_eq(PondExits.width_at(mouth, 0.0, 0), wet.y, "the left shore on the edge's")
	assert_eq(PondExits.width_at(mouth, 0.0, 1), -wet.x, "the right shore on the edge's")
	assert_eq(PondExits.width_at(mouth, float(mouth.length) + 0.3, 0), 0.0, "closed past its end")


func test_the_seam_rows_match_bit_for_bit() -> void:
	var doc := _edge_doc()
	var half := _half(doc)
	var parts := _built(doc)
	var level := doc.water_bodies[0].level_m
	var water: PackedVector3Array = _pond_ribbons(parts)[0].vertices
	var first := 0
	for v in water:
		if absf(v.z - half.y) < 1e-5:
			assert_eq(v.y, float(PackedFloat32Array([level])[0]), "the first row at the level")
			first += 1
	assert_gt(first, 2, "the water's first row lies on the edge")
	# The in-map water meets it at the same height on the edge, across the wet span.
	var mouth: Dictionary = parts.mouths[0]
	var wet: Vector2 = mouth.wet
	var inner: PackedVector3Array = WaterMeshBuilder.build(doc).arrays[Mesh.ARRAY_VERTEX]
	var met := 0
	for v in inner:
		var across := absf(v.x - (mouth.mouth as Vector2).x)
		if absf(v.z - half.y) < 1e-5 and across < minf(-wet.x, wet.y) - 0.3:
			assert_eq(v.y, water[0].y, "the in-map water's edge row at the same height")
			met += 1
	assert_gt(met, 0)
	# The patch's first column: the map's boundary heights.
	var patch: PackedVector3Array = parts.channel[Mesh.ARRAY_VERTEX]
	var boundary := 0
	for v in patch:
		var xz := Vector2(v.x, v.z)
		if RiverExits.outside_distance(xz, half) > 1e-6:
			continue
		var s := doc.world_to_sample(xz).round()
		assert_eq(v.y, doc.heights[doc.sample_index(int(s.x), int(s.y))], "boundary height")
		boundary += 1
	assert_gt(boundary, 10)


func test_the_water_past_the_edge_is_at_the_pond_level_over_its_basin() -> void:
	var doc := _edge_doc()
	var half := _half(doc)
	var level := doc.water_bodies[0].level_m
	var parts := _built(doc)
	for v: Vector3 in _pond_ribbons(parts)[0].vertices:
		assert_almost_eq(v.y, level, 1e-4, "a flat map's skirt keeps the level")
	# The basin is carved under it past the edge: deepest a few metres out near the axis.
	var mouth: Dictionary = parts.mouths[0]
	var deepest := INF
	var patch: PackedVector3Array = parts.channel[Mesh.ARRAY_VERTEX]
	for v in patch:
		var xz := Vector2(v.x, v.z)
		var out := RiverExits.outside_distance(xz, half)
		if out > 1.0 and out < 3.0:
			deepest = minf(deepest, v.y)
	assert_lt(deepest, level - 0.3, "the basin runs on under the water")
	assert_gt(float(mouth.length), 0.0)


func test_an_edit_away_from_a_pond_exit_rebuilds_nothing() -> void:
	var doc := _edge_doc()
	var first := _built(doc)
	assert_eq(_built(doc, first).built, 0, "nothing changed, nothing rebuilt")
	doc.heights[doc.sample_index(15, 3)] -= 0.4
	var away := _built(doc, first)
	assert_eq(away.built, 0, "an edit away from the pond's exit rebuilds none")
	var mouth: Vector2 = (first.mouths[0] as Dictionary).mouth
	var s := doc.world_to_sample(mouth + Vector2(1.0, 0.0)).round()
	doc.heights[doc.sample_index(int(s.x), int(s.y))] -= 0.2
	var near := _built(doc, away)
	assert_gt(near.built, 0, "an edit on its span rebuilds it")


## A pond on the near edge with a river leaving through it, both wet on the edge.
func _shared_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 7)
	var start := doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		doc,
		PackedVector2Array([Vector2(-1.0, -8.0), Vector2(0.0, 2.0), Vector2(0.0, 15.04)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.WAIST
	)
	_carve(doc, WaterCarve.river_goals(doc, bodies, start))
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	# The pond at the flat ground's level (its rim would be the river's channel).
	var id := doc.next_water_id()
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).distance_to(Vector2(2.0, 13.24)) <= 6.0:
				mask[doc.sample_index(x, z)] = id
	doc.pond_mask = mask
	var pond := WaterBody.pond(id, WaterBody.Depth.WAIST, -WaterGeometry.FREEBOARD_M)
	_carve(doc, WaterCarve.pond_goals(doc, pond, start))
	var all: Array[WaterBody] = doc.water_bodies.duplicate()
	all.append(pond)
	doc.water_bodies = all
	return doc


func _covers(piece: Dictionary, p: Vector2) -> bool:
	var verts: PackedVector3Array = piece.vertices
	var indices: PackedInt32Array = piece.indices
	for f in indices.size() / 3:
		var a := verts[indices[f * 3]]
		var b := verts[indices[f * 3 + 1]]
		var c := verts[indices[f * 3 + 2]]
		if Geometry2D.point_is_inside_triangle(
			p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)
		):
			return true
	return false


func test_a_pond_and_a_river_sharing_an_edge_window_do_not_overlap() -> void:
	var doc := _shared_doc()
	assert_eq(RiverExits.exits(doc).size(), 1, "the river leaves the map")
	assert_eq(PondExits.exits(doc, AuthoredTerrain.SKIRT_FADE_M).size(), 1, "and the pond")
	var parts := _built(doc)
	assert_eq((parts.windows as Array).size(), 1, "in one window")
	var pond: Dictionary = _pond_ribbons(parts)[0]
	var river: Dictionary = {}
	for piece: Dictionary in (parts.pieces as Dictionary).values():
		if not piece.has("outline") and not piece.has("wets"):
			river = piece
	assert_false(river.is_empty())
	var outline: PackedVector2Array = pond.outline
	var box := WaterGeometry.bounds(outline, 0.0)
	var overlaps := 0
	var cut := 0
	var whole := (
		RiverExitMesh
		. _ribbon_piece(
			doc,
			parts.mouths[0],
			{
				"half": _half(doc),
				"fall": AuthoredTerrain.SKIRT_FADE_M,
				"wobble": AuthoredTerrain.SKIRT_WOBBLE,
				"seed": doc.map_seed & 0x7FFFFFFF,
			}
		)
	)
	for j in 40:
		for i in 40:
			var p := box.position + box.size * Vector2((i + 0.5) / 40.0, (j + 0.5) / 40.0)
			if not _covers(pond, p):
				continue
			if _covers(river, p):
				overlaps += 1
			if _covers(whole, p):
				cut += 1
	assert_gt(cut, 0, "the river's water would have run over the pond's")
	assert_eq(overlaps, 0, "no two water surfaces overlap")
