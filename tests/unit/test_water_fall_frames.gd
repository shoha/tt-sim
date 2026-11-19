extends GutTest

## The fall frames (WaterFallFrames, card painter-fall-frame-foam): one frame per fall with the
## curtain's own numbers, a pseudo-arc continuous over the lip and over the foot, the window a
## vertex takes its frame from, and the two meshes that carry the frames in CUSTOM0 and CUSTOM1.

const Fixtures := preload("res://tests/unit/water_fixtures.gd")


func _tier_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 5)
	Fixtures.tier_fall(doc)
	return doc


func _ramp_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 5)
	Fixtures.ramp_falls(doc)
	return doc


## A frame with only the fields the window and the channels read.
func _bare(lip: Vector2, dir: Vector2, x_pool: float) -> Dictionary:
	return {"lip": lip, "dir": dir, "widths": Vector2(1.0, 1.0), "x_pool": x_pool, "drop": 1.5}


func _channels_at(arrays: Array, i: int) -> Array[float]:
	var c0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var c1: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var out: Array[float] = []
	for k in 4:
		out.append(c0[i * 4 + k])
	for k in 4:
		out.append(c1[i * 4 + k])
	return out


func test_one_frame_per_fall_with_the_curtains_numbers() -> void:
	for doc in [_tier_doc(), _ramp_doc()]:
		var falls := WaterFalls.falls(doc)
		var frames := WaterFallFrames.frames(doc, falls)
		assert_gt(falls.size(), 0, "falls to frame")
		assert_eq(frames.size(), falls.size(), "one frame per fall")
		for frame in frames:
			var fall: Dictionary = frame.fall
			var lip: Vector2 = frame.lip
			var dir: Vector2 = frame.dir
			var widths := WaterFallMesh.crest_widths(doc, lip, dir, fall.half_width, fall.top)
			assert_almost_eq(frame.widths, widths, Vector2.ONE * 1e-6, "the crest widths")
			assert_almost_eq(float(frame.drop), float(fall.top) - float(fall.bottom), 1e-6)
			var offsets: PackedFloat32Array = frame.offsets
			var columns: Array = frame.columns
			assert_eq(columns.size(), offsets.size(), "a trajectory per column")
			# x_pool: where the column nearest the course meets the pool level.
			var middle := 0
			for i in offsets.size():
				if absf(offsets[i]) < absf(offsets[middle]):
					middle = i
			var rows: PackedFloat32Array = frame.rows
			var at_pool: Vector3 = (columns[middle] as PackedVector3Array)[rows.size() - 2]
			assert_almost_eq(at_pool.y, float(fall.bottom), 1e-4, "the pool row is at the level")
			var x_pool := (Vector2(at_pool.x, at_pool.z) - lip).dot(dir)
			assert_almost_eq(float(frame.x_pool), x_pool, 1e-6)
			assert_gt(float(frame.x_pool), 0.0, "the curtain lands downstream of the lip")


func test_the_arc_is_continuous_over_the_lip_and_over_the_foot() -> void:
	for doc in [_tier_doc(), _ramp_doc()]:
		for frame in WaterFallFrames.frames(doc, WaterFalls.falls(doc)):
			var lip: Vector2 = frame.lip
			var dir: Vector2 = frame.dir
			var x_pool: float = frame.x_pool
			var a_pool := x_pool + float(frame.drop)
			# Over the lip: the river just upstream and the curtain's first row meet at 0.
			var river := WaterFallFrames.water_arc(frame, lip - dir * 1e-4)
			var brink := WaterFallFrames.curtain_arc(frame, lip, 0.0)
			assert_almost_eq(river, 0.0, 1e-3, "the river reaches the lip at 0")
			assert_almost_eq(brink, 0.0, 1e-6, "the curtain leaves it at 0")
			# Over the foot: the middle column's pool row and the pool at that point meet at a_pool.
			var at_pool := lip + dir * x_pool
			var curtain := WaterFallFrames.curtain_arc(frame, at_pool, float(frame.drop))
			var pool := WaterFallFrames.water_arc(frame, at_pool)
			assert_almost_eq(curtain, a_pool, 1e-5, "the curtain lands at a_pool")
			assert_almost_eq(pool, a_pool, 1e-5, "the pool starts at a_pool")
			# Down every column the arc only grows (one coordinate down the fall).
			var rows: PackedFloat32Array = frame.rows
			for column: PackedVector3Array in frame.columns:
				var last := -INF
				for k in rows.size() - 1:
					var p := column[k]
					var arc := WaterFallFrames.curtain_arc(frame, Vector2(p.x, p.z), rows[k])
					assert_true(arc >= last - 1e-6, "the arc grows down a column")
					last = arc


func test_a_vertex_takes_the_frame_whose_window_holds_it() -> void:
	var frame := _bare(Vector2(2.0, 3.0), Vector2(0.0, 1.0), 1.5)
	var frames: Array[Dictionary] = [frame]
	var own := WaterFallFrames.channels(frame)
	assert_eq(own, [2.0, 3.0, 0.0, 1.0, 1.0, 1.0, 1.5, 1.5] as Array[float])
	assert_eq(WaterFallFrames.vertex_frame(frames, Vector2(2.0, 3.0)), own, "the lip")
	var up := Vector2(2.0, 3.0 - WaterFallFrames.WINDOW_UP_M + 0.05)
	assert_eq(WaterFallFrames.vertex_frame(frames, up), own, "just inside upstream")
	var past := Vector2(2.0, 3.0 - WaterFallFrames.WINDOW_UP_M - 0.05)
	assert_eq(WaterFallFrames.vertex_frame(frames, past), WaterFallFrames.NONE, "past upstream")
	var down := Vector2(2.0, 3.0 + 1.5 + WaterFallFrames.WINDOW_DOWN_M - 0.05)
	assert_eq(WaterFallFrames.vertex_frame(frames, down), own, "just inside downstream")
	var side := 1.0 * WaterFallFrames.WINDOW_SIDE + WaterFallFrames.WINDOW_SIDE_M
	assert_eq(WaterFallFrames.vertex_frame(frames, Vector2(2.0 + side - 0.05, 4.0)), own, "beside")
	var off := Vector2(2.0 + side + 0.05, 4.0)
	assert_eq(WaterFallFrames.vertex_frame(frames, off), WaterFallFrames.NONE, "past the side")


func test_overlapping_windows_give_the_nearer_fall() -> void:
	var a := _bare(Vector2(0.0, 0.0), Vector2(0.0, 1.0), 1.0)
	var b := _bare(Vector2(1.5, 0.0), Vector2(0.0, 1.0), 1.0)
	var frames: Array[Dictionary] = [a, b]
	var near_a := WaterFallFrames.vertex_frame(frames, Vector2(0.5, 0.5))
	var near_b := WaterFallFrames.vertex_frame(frames, Vector2(1.2, 0.5))
	assert_eq(near_a, WaterFallFrames.channels(a))
	assert_eq(near_b, WaterFallFrames.channels(b))


func test_the_water_surface_carries_the_frames() -> void:
	var doc := _tier_doc()
	var frames := WaterFallFrames.frames(doc, WaterFalls.falls(doc))
	assert_eq(frames.size(), 1)
	var own := WaterFallFrames.channels(frames[0])
	var arrays: Array = WaterMeshBuilder.build(doc)["arrays"]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq((arrays[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).size(), vertices.size() * 4)
	assert_eq((arrays[Mesh.ARRAY_CUSTOM1] as PackedFloat32Array).size(), vertices.size() * 4)
	var framed := 0
	var plain := 0
	for i in vertices.size():
		var held := WaterFallFrames.window_distance(frames[0], Vector2(vertices[i].x, vertices[i].z))
		var expected := own if held >= 0.0 else WaterFallFrames.NONE
		assert_eq(_channels_at(arrays, i), expected, "vertex %d" % i)
		if held >= 0.0:
			framed += 1
		else:
			plain += 1
	assert_gt(framed, 20, "the water round the fall carries its frame")
	assert_gt(plain, 20, "the water away from it carries none")
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, WaterFallFrames.FORMAT)
	var format := mesh.surface_get_format(0)
	assert_true(format & Mesh.ARRAY_FORMAT_CUSTOM0 != 0, "CUSTOM0 in the surface")
	assert_true(format & Mesh.ARRAY_FORMAT_CUSTOM1 != 0, "CUSTOM1 in the surface")


func test_the_curtain_carries_its_frame_and_the_ring_and_mist_none() -> void:
	var doc := _tier_doc()
	var frames := WaterFallFrames.frames(doc, WaterFalls.falls(doc))
	var own := WaterFallFrames.channels(frames[0])
	var arrays: Array = WaterFallMesh.from_frames(frames).arrays
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var curtain := 0
	for i in colors.size():
		var is_curtain := absf(colors[i].g - WaterFallMesh.KIND_CURTAIN) < 0.1
		var expected := own if is_curtain else WaterFallFrames.NONE
		assert_eq(_channels_at(arrays, i), expected, "vertex %d" % i)
		if is_curtain:
			curtain += 1
	assert_gt(curtain, 20, "a curtain")
	assert_lt(curtain, colors.size(), "and a ring and mist besides")


func test_build_and_from_frames_make_the_same_mesh() -> void:
	var doc := _ramp_doc()
	var falls := WaterFalls.falls(doc)
	var built := WaterFallMesh.build(doc, falls)
	var framed := WaterFallMesh.from_frames(WaterFallFrames.frames(doc, falls))
	assert_eq(built.arrays, framed.arrays)
	assert_eq(built.aabb, framed.aabb)


func test_no_frames_no_channels() -> void:
	var vertices := PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	var channels := WaterFallFrames.vertex_channels([] as Array[Dictionary], vertices)
	assert_eq(channels[0], PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0]))
	assert_eq(channels[1], PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0]))
