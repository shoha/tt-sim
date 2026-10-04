extends GutTest

## Waterfalls (phase 4c, P4c-3): the curtain, foam ring and mist geometry (WaterFallMesh)
## over a tier fall and the two hillside falls of a carved ramp, and what the falls add to
## the wet dressing (WaterDressing) and the flow bake (WaterFlowBaker) over their footprint.

const Fixtures := preload("res://tests/unit/water_fixtures.gd")
const EPSILON := 1e-3
## water.gdshader: FLOW_DEAD_ZONE and FLOW_MAX_VALID (test_water_flow_baker.gd).
const DEAD_ZONE := 0.02
const MAX_VALID := 1.1


## A 20 x 20 cell map (30.48 m, 123 samples a side, tier 1.524 m).
func _doc() -> MapDocument:
	return MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 5)


func _tier_doc() -> MapDocument:
	var doc := _doc()
	Fixtures.tier_fall(doc)
	return doc


func _ramp_doc() -> MapDocument:
	var doc := _doc()
	Fixtures.ramp_falls(doc)
	return doc


func _falls_of(doc: MapDocument) -> Dictionary:
	return WaterFallMesh.build(doc, WaterFalls.falls(doc))


## The vertex indices of `arrays` whose kind flag (COLOR.g) is `kind`.
func _of_kind(arrays: Array, kind: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colors.size():
		if absf(colors[i].g - kind) < 0.1:
			out.append(i)
	return out


## The fall of `falls` whose lower level is `bottom` (UV2.y), or {}.
func _fall_at(falls: Array[Dictionary], bottom: float) -> Dictionary:
	for fall in falls:
		if absf(float(fall.bottom) - bottom) < 1e-3:
			return fall
	return {}


func _dir3(fall: Dictionary) -> Vector3:
	var d: Vector2 = fall.dir
	return Vector3(d.x, 0.0, d.y)


# --- the curtain -----------------------------------------------------------------------------


func test_curtain_clears_the_rock_and_never_rises_over_the_upper_level() -> void:
	for doc in [_tier_doc(), _ramp_doc()]:
		var falls := WaterFalls.falls(doc)
		assert_gt(falls.size(), 0, "falls to build")
		var built := WaterFallMesh.build(doc, falls)
		var arrays: Array = built.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var curtain := _of_kind(arrays, WaterFallMesh.KIND_CURTAIN)
		assert_gt(curtain.size(), 50, "a curtain")
		var worst := INF
		for i in curtain:
			var p := vertices[i]
			var bottom := uv2s[i].y
			var top := bottom + uv2s[i].x
			var ground := WaterGeometry.ground_at(doc, Vector2(p.x, p.z))
			var floor_y := minf(top, ground + WaterFallMesh.FALL_CLEARANCE_M)
			worst = minf(worst, p.y - floor_y)
			assert_true(p.y <= top + EPSILON, "never above the upper level (%s)" % p)
		assert_true(
			worst >= -EPSILON,
			"every vertex the clearance in front of the rock or at the level (worst %.3f)" % worst
		)
		assert_eq(int(built.count), falls.size())


func test_bottom_row_ends_three_centimetres_under_the_pool() -> void:
	var doc := _ramp_doc()
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 2, "two hillside falls")
	var arrays: Array = _falls_of(doc).arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var lowest := {}
	var deepest_v := {}
	for i in _of_kind(arrays, WaterFallMesh.KIND_CURTAIN):
		var bottom := snappedf(uv2s[i].y, 1e-4)
		lowest[bottom] = minf(float(lowest.get(bottom, INF)), vertices[i].y)
		deepest_v[bottom] = maxf(float(deepest_v.get(bottom, 0.0)), uvs[i].y)
	assert_eq(lowest.keys().size(), 2, "one curtain per fall")
	for bottom: float in lowest:
		var end := bottom - WaterFallMesh.END_BELOW_M
		assert_almost_eq(float(lowest[bottom]), end, EPSILON, "the lowest row at the end")
		var fall := _fall_at(falls, bottom)
		var drop := float(fall.top) - float(fall.bottom)
		assert_almost_eq(float(deepest_v[bottom]), drop + WaterFallMesh.END_BELOW_M, EPSILON)
		# Every vertex of the last row is at the end: the whole row reaches the pool.
		for i in _of_kind(arrays, WaterFallMesh.KIND_CURTAIN):
			if absf(uv2s[i].y - bottom) < 1e-4 and absf(uvs[i].y - float(deepest_v[bottom])) < 1e-5:
				assert_almost_eq(vertices[i].y, end, EPSILON, "a last-row vertex at the end")


func test_curtain_covers_the_wetted_crest() -> void:
	var doc := _tier_doc()
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 1)
	var fall: Dictionary = falls[0]
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	var across := dir.orthogonal()
	var top: float = fall.top
	var hw: float = fall.half_width
	# The wet extent along the lip line from the real ground, each side.
	var wet := Vector2.ZERO
	for side in 2:
		var sign_value := -1.0 if side == 0 else 1.0
		var w := 0.0
		while w < hw + 1.0 and WaterGeometry.ground_at(doc, lip + across * (w * sign_value)) < top:
			wet[side] = w
			w += 0.01
	assert_gt(wet.x, 0.5, "the crest is wet on the left (%.2f m)" % wet.x)
	assert_gt(wet.y, 0.5, "and on the right (%.2f m)" % wet.y)
	var widths := WaterFallMesh.crest_widths(doc, lip, dir, hw, top)
	assert_almost_eq(widths.x, wet.x, WaterFallMesh.WIDTH_SCAN_M, "the left width")
	assert_almost_eq(widths.y, wet.y, WaterFallMesh.WIDTH_SCAN_M, "the right width")
	var arrays: Array = _falls_of(doc).arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var left := INF
	var right := -INF
	var edge_fade := INF
	var middle_fade := 0.0
	for i in _of_kind(arrays, WaterFallMesh.KIND_CURTAIN):
		if uvs[i].y > 1e-6:
			continue
		var p := vertices[i]
		var w := (Vector2(p.x, p.z) - lip).dot(across)
		left = minf(left, w)
		right = maxf(right, w)
		assert_almost_eq(p.y, top, EPSILON, "the lip row rides the upper level")
		assert_almost_eq((Vector2(p.x, p.z) - lip).dot(dir), 0.0, EPSILON, "on the lip line")
		edge_fade = minf(edge_fade, colors[i].r)
		middle_fade = maxf(middle_fade, colors[i].r)
	assert_almost_eq(-left, wet.x, WaterFallMesh.WIDTH_SCAN_M + 1e-3, "covers the left")
	assert_almost_eq(right, wet.y, WaterFallMesh.WIDTH_SCAN_M + 1e-3, "covers the right")
	assert_true(right - left <= 2.0 * hw + 1e-3, "never wider than the channel")
	assert_lt(edge_fade, 0.01, "the side edges fade out")
	assert_gt(middle_fade, 0.99, "the middle is full")
	assert_true(
		WaterFallMesh.column_offsets(widths).size() >= ceili((widths.x + widths.y) / 0.2),
		"a column every 0.2 m"
	)


func test_normals_face_outward_and_triangles_wind_clockwise_from_the_front() -> void:
	var doc := _ramp_doc()
	var falls := WaterFalls.falls(doc)
	var arrays: Array = _falls_of(doc).arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in _of_kind(arrays, WaterFallMesh.KIND_CURTAIN):
		var fall := _fall_at(falls, uv2s[i].y)
		assert_false(fall.is_empty())
		assert_gt(normals[i].dot(_dir3(fall)), 0.0, "normal %d faces downstream" % i)
		assert_almost_eq(normals[i].length(), 1.0, 1e-4)
	var curtain_triangles := 0
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var b := indices[t + 1]
		var c := indices[t + 2]
		if colors[a].g > 0.25:
			continue
		var front := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		if front.length_squared() < 1e-10:
			continue
		curtain_triangles += 1
		var fall := _fall_at(falls, uv2s[a].y)
		assert_gt(front.dot(_dir3(fall)), 0.0, "triangle %d is clockwise from downstream" % t)
	assert_gt(curtain_triangles, 50)
	for i in _of_kind(arrays, WaterFallMesh.KIND_RING):
		assert_eq(normals[i], Vector3.UP)


func test_output_is_deterministic() -> void:
	var doc := _ramp_doc()
	var first := _falls_of(doc)
	var second := _falls_of(doc)
	var a: Array = first.arrays
	var b: Array = second.arrays
	assert_true((a[Mesh.ARRAY_VERTEX] as PackedVector3Array) == b[Mesh.ARRAY_VERTEX])
	assert_true((a[Mesh.ARRAY_NORMAL] as PackedVector3Array) == b[Mesh.ARRAY_NORMAL])
	assert_true((a[Mesh.ARRAY_TEX_UV] as PackedVector2Array) == b[Mesh.ARRAY_TEX_UV])
	assert_true((a[Mesh.ARRAY_TEX_UV2] as PackedVector2Array) == b[Mesh.ARRAY_TEX_UV2])
	assert_true((a[Mesh.ARRAY_COLOR] as PackedColorArray) == b[Mesh.ARRAY_COLOR])
	assert_true((a[Mesh.ARRAY_INDEX] as PackedInt32Array) == b[Mesh.ARRAY_INDEX])
	assert_eq(first.aabb, second.aabb)
	# And through the merged builder, which snapshots the document for its worker.
	var built := WaterMeshBuilder.build(WaterMeshBuilder.snapshot(doc))
	assert_true((built.falls[Mesh.ARRAY_VERTEX] as PackedVector3Array) == a[Mesh.ARRAY_VERTEX])


func test_rows_and_columns() -> void:
	var rows := WaterFallMesh.row_falls(1.5)
	assert_eq(rows[0], 0.0)
	assert_almost_eq(rows[1], WaterFallMesh.ROLL_ROW_FALL_M, 1e-6, "finer rows over the roll")
	assert_almost_eq(rows[-2], 1.5, 1e-6, "the pool level is a row")
	assert_almost_eq(rows[-1], 1.5 + WaterFallMesh.END_BELOW_M, 1e-6, "the end is the last")
	for k in rows.size() - 1:
		assert_gt(rows[k + 1] - rows[k], 0.01, "rows ascend")
		assert_true(rows[k + 1] - rows[k] <= WaterFallMesh.ROW_FALL_M + 1e-6, "every 0.12 m")
	var merged := WaterFallMesh.row_falls(1.2 + 0.005)
	assert_almost_eq(merged[-2], 1.205, 1e-6, "a row a hair past the pool merges into it")
	var columns := WaterFallMesh.column_offsets(Vector2(0.5, 0.7))
	assert_almost_eq(columns[0], -0.5, 1e-6)
	assert_almost_eq(columns[-1], 0.7, 1e-6)
	for i in columns.size() - 1:
		assert_true(columns[i + 1] - columns[i] <= WaterFallMesh.COLUMN_M + 1e-6)


# --- the ring and the mist -------------------------------------------------------------------


func test_foam_ring_sits_on_the_pool() -> void:
	var doc := _tier_doc()
	var fall: Dictionary = WaterFalls.falls(doc)[0]
	var bottom: float = fall.bottom
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	var arrays: Array = _falls_of(doc).arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var ring := _of_kind(arrays, WaterFallMesh.KIND_RING)
	assert_eq(ring.size(), WaterFallMesh.RING_SEGMENTS + 1, "a centre and the rim")
	var centre := Vector2.ZERO
	var farthest := 0.0
	for i in ring:
		assert_almost_eq(vertices[i].y, bottom + WaterFallMesh.RING_LIFT_M, 1e-5, "on the pool")
		if colors[i].r > 0.99:
			centre = Vector2(vertices[i].x, vertices[i].z)
	for i in ring:
		farthest = maxf(farthest, Vector2(vertices[i].x, vertices[i].z).distance_to(centre))
		assert_almost_eq(uv2s[i].y, bottom, 1e-5)
	var widths := WaterFallMesh.crest_widths(doc, lip, dir, fall.half_width, fall.top)
	var radius := WaterFallMesh.RING_WIDTH_FACTOR * (widths.x + widths.y) * 0.5
	assert_almost_eq(farthest, radius, 1e-3, "1.4 x the fall's width across")
	assert_almost_eq(uv2s[ring[0]].x, radius, 1e-5, "UV2.x carries the radius")
	var along := (centre - lip).dot(dir)
	assert_gt(along, 0.5, "downstream of the lip")
	assert_lt(along, WaterCarve.fall_foot(fall.top - bottom, 0.9) + radius, "at the plunge")
	assert_almost_eq((centre - lip).dot(dir.orthogonal()), 0.0, 1e-3, "on the course")


@warning_ignore("integer_division")
func test_mist_is_three_to_five_packed_billboards_inside_the_grown_bounds() -> void:
	for doc in [_tier_doc(), _ramp_doc()]:
		var falls := WaterFalls.falls(doc)
		var built := WaterFallMesh.build(doc, falls)
		var arrays: Array = built.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var mist := _of_kind(arrays, WaterFallMesh.KIND_MIST)
		assert_eq(mist.size() % 4, 0, "quads")
		var puffs := mist.size() / 4
		assert_between(
			puffs, WaterFallMesh.MIST_MIN * falls.size(), WaterFallMesh.MIST_MAX * falls.size()
		)
		var largest := 0.0
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for v in vertices:
			bounds = bounds.expand(v)
		for q in puffs:
			var first := mist[q * 4]
			var centre := vertices[first]
			var half := absf(uv2s[first].x)
			assert_between(half, WaterFallMesh.MIST_HALF_MIN_M, WaterFallMesh.MIST_HALF_MAX_M)
			largest = maxf(largest, half)
			var seed_value := colors[first].b
			for k in 4:
				var i := mist[q * 4 + k]
				assert_eq(vertices[i], centre, "packed at the centre")
				assert_almost_eq(absf(uv2s[i].x), half, 1e-5, "a square offset")
				assert_almost_eq(absf(uv2s[i].y), half, 1e-5)
				assert_true(uvs[i].x == 0.0 or uvs[i].x == 1.0, "corner UVs")
				assert_almost_eq(colors[i].b, seed_value, 1e-6, "one seed per puff")
			# Inside the fall's channel, over the pool and under the lip.
			var nearest: Dictionary = {}
			var nearest_d := INF
			for fall in falls:
				var d := Vector2(centre.x, centre.z).distance_to(fall.lip)
				if d < nearest_d:
					nearest_d = d
					nearest = fall
			var lip: Vector2 = nearest.lip
			var dir: Vector2 = nearest.dir
			var offset := Vector2(centre.x, centre.z) - lip
			assert_gt(offset.dot(dir), 0.0, "set back from the pool toward the lip, past it")
			assert_lt(
				absf(offset.dot(dir.orthogonal())), float(nearest.half_width), "in the channel"
			)
			assert_gt(centre.y, float(nearest.bottom), "over the pool")
			assert_true(centre.y <= float(nearest.top) + half, "no higher than the lip")
		var grown: AABB = built.aabb
		assert_almost_eq(
			grown.position, bounds.position - Vector3.ONE * largest, Vector3.ONE * 1e-4
		)
		assert_almost_eq(grown.end, bounds.end + Vector3.ONE * largest, Vector3.ONE * 1e-4)


func test_no_fall_builds_nothing() -> void:
	var doc := _doc()
	Fixtures.river(doc, Vector2(-10, 0), Vector2(10, 0), 1.5)
	assert_eq(WaterFalls.falls(doc).size(), 0)
	var built := WaterMeshBuilder.build(doc)
	assert_true((built.falls as Array).is_empty())
	assert_false((built.arrays as Array).is_empty(), "the flat river is still there")
	var empty := WaterFallMesh.build(doc, [] as Array[Dictionary])
	assert_true((empty.arrays as Array).is_empty())
	assert_eq(int(empty.count), 0)


# --- dressing and flow over the footprint ---------------------------------------------------


func test_dressing_is_bed_and_wet_over_the_footprint() -> void:
	var doc := _tier_doc()
	var footprint := WaterFalls.footprint(doc)
	assert_gt(footprint.size(), 10)
	var field := WaterDressing.field_of(doc)
	assert_eq(field.size(), doc.sample_count() * WaterDressing.CHANNELS)
	var fall: Dictionary = WaterFalls.falls(doc)[0]
	var dry_face := 0
	for i in footprint:
		assert_eq(field[i * WaterDressing.CHANNELS], 255, "bed on face sample %d" % i)
		assert_eq(field[i * WaterDressing.CHANNELS + 3], 255, "wet line on face sample %d" % i)
		if doc.heights[i] > float(fall.bottom):
			dry_face += 1
	assert_gt(dry_face, 5, "the footprint has samples above the pool (the face itself)")
	# Without the falls' footprint the face is dry rock between the two pools.
	var channel := PackedByteArray()
	channel.resize(doc.sample_count())
	for i: int in WaterMeshBuilder.cascades(doc):
		channel[i] = 1
	var without := WaterDressing.compute(doc, WaterGeometry.levels(doc), channel)
	var bare := 0
	for i in footprint:
		if doc.heights[i] > float(fall.bottom) and without[i * WaterDressing.CHANNELS] < 128:
			bare += 1
	assert_gt(bare, 0, "the footprint is what dresses the face")


## test_water_flow_baker.gd's mirror of water.gdshader's water_flow() for the authored mesh.
func _shader_flow(rg: PackedByteArray, size: Vector2i, extent: Vector2, xz: Vector2) -> Vector2:
	var uv := (xz + extent * 0.5) / extent
	var at := uv * Vector2(size) - Vector2(0.5, 0.5)
	var i0 := floori(at.x)
	var j0 := floori(at.y)
	var fx := at.x - i0
	var fy := at.y - j0
	var sampled := Vector2.ZERO
	for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var i := clampi(i0 + corner.x, 0, size.x - 1)
		var j := clampi(j0 + corner.y, 0, size.y - 1)
		var weight := (fx if corner.x == 1 else 1.0 - fx) * (fy if corner.y == 1 else 1.0 - fy)
		var k := (j * size.x + i) * 2
		sampled += Vector2(rg[k], rg[k + 1]) / 255.0 * weight
	var f := sampled * 2.0 - Vector2.ONE
	var speed := f.length()
	if speed <= DEAD_ZONE or speed > MAX_VALID:
		return Vector2.ZERO
	return Vector2(f.x, -f.y).normalized() * speed


@warning_ignore("integer_division")
func test_flow_runs_through_the_lip_and_down_the_face() -> void:
	var doc := _tier_doc()
	var fall: Dictionary = WaterFalls.falls(doc)[0]
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	var size := WaterFlowBaker.resolution_for(doc.extent_m())
	var rg := WaterFlowBaker.bake(doc, size)
	var foot := WaterCarve.fall_foot(fall.top - fall.bottom, 0.9)
	var weakest := INF
	var s := -1.0
	while s <= foot + 1.0:
		var flow := _shader_flow(rg, size, doc.extent_m(), lip + dir * s)
		weakest = minf(weakest, flow.length())
		assert_gt(flow.normalized().dot(dir), 0.9, "downstream at %.2f m" % s)
		s += 0.1
	assert_gt(weakest, 0.5, "continuous through the lip (weakest %.2f)" % weakest)
	# Wet over the whole footprint: no face sample within the channel is still.
	var still := 0
	var columns := doc.samples_x()
	for i in WaterFalls.footprint(doc):
		var p := doc.sample_to_world(Vector2(i % columns, i / columns))
		if absf((p - lip).dot(dir.orthogonal())) > float(fall.half_width) * 0.5:
			continue
		if _shader_flow(rg, size, doc.extent_m(), p).length() < 0.3:
			still += 1
	assert_eq(still, 0, "the flow bake is wet over the footprint")
