extends GutTest

## WaterFlowBaker: the terrain-paint flow field ported onto the map document, decoded end
## to end through a mirror of water.gdshader's water_flow() for the authored water mesh
## (identity transform, map-normalised UVs), so the texel, row and sign conventions are
## pinned against what the shader will read.

const BED := -1.0
const LEVEL := -0.2
## water.gdshader: FLOW_DEAD_ZONE and FLOW_MAX_VALID.
const DEAD_ZONE := 0.02
const MAX_VALID := 1.1


## A flat map of `cells` x `cells` cells (1.524 m each) with no water.
func _flat(cells: int) -> MapDocument:
	return MapDocument.create_flat(Vector2i(cells, cells), "", "", 0)


## Adds a river along `line` (constant `half_width`) and carves its channel to BED where
## the ground is within the half-width of its course.
@warning_ignore("integer_division")
func _add_river(
	doc: MapDocument, body_id: int, line: PackedVector2Array, half_width: float, speed: float
) -> WaterBody:
	var widths := PackedFloat32Array()
	for _p in line:
		widths.append(half_width)
	var river := WaterBody.river(body_id, line, widths, WaterBody.Depth.WAIST, LEVEL, speed)
	var course := WaterGeometry.river_course(river)
	var heights := doc.heights.duplicate()
	for i in WaterGeometry.body_area(doc, river):
		var p := doc.sample_to_world(Vector2(i % doc.samples_x(), i / doc.samples_x()))
		if WaterGeometry.nearest_on_polyline(course[0], p).x <= half_width:
			heights[i] = BED
	doc.heights = heights
	doc.water_bodies.append(river)
	return river


## The world-XZ flow direction times speed factor water_flow() computes at map point `xz`
## for the authored water mesh: identity MODEL_MATRIX, UV = ((x + W/2) / W, (z + H/2) / H),
## the map sampled with filter_linear and clamp to edge, f = rg * 2 - 1, the dead zone and
## the unbound-sampler guard, local (f.x, 0, -f.y) through the model matrix. Without
## flow_strength and FLOW_SPEED_UNITS_PER_SEC, which only scale it.
func _shader_flow(rg: PackedByteArray, size: Vector2i, extent: Vector2, xz: Vector2) -> Vector2:
	var uv := (xz + extent * 0.5) / extent
	var f := _sample_linear(rg, size, uv) * 2.0 - Vector2.ONE
	var speed := f.length()
	if speed <= DEAD_ZONE or speed > MAX_VALID:
		return Vector2.ZERO
	var local_dir := Vector3(f.x, 0.0, -f.y) / speed
	var world_dir := Vector2(local_dir.x, local_dir.z)
	return world_dir.normalized() * speed


## texture() with filter_linear and repeat_disable: texel centres at (i + 0.5) / size,
## row j of the image at v = (j + 0.5) / size.y. RG in 0..1.
func _sample_linear(rg: PackedByteArray, size: Vector2i, uv: Vector2) -> Vector2:
	var at := uv * Vector2(size) - Vector2(0.5, 0.5)
	var i0 := floori(at.x)
	var j0 := floori(at.y)
	var fx := at.x - i0
	var fy := at.y - j0
	var out := Vector2.ZERO
	for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var i := clampi(i0 + corner.x, 0, size.x - 1)
		var j := clampi(j0 + corner.y, 0, size.y - 1)
		var weight := (fx if corner.x == 1 else 1.0 - fx) * (fy if corner.y == 1 else 1.0 - fy)
		var k := (j * size.x + i) * 2
		out += Vector2(rg[k], rg[k + 1]) / 255.0 * weight
	return out


func _texel(rg: PackedByteArray, size: Vector2i, i: int, j: int) -> Vector2i:
	var k := (j * size.x + i) * 2
	return Vector2i(rg[k], rg[k + 1])


func _bake(doc: MapDocument) -> Dictionary:
	var size := WaterFlowBaker.resolution_for(doc.extent_m())
	return {"rg": WaterFlowBaker.bake(doc, size), "size": size}


# --- resolution -----------------------------------------------------------------------


func test_resolution() -> void:
	var two_hundred_feet := Vector2(40, 40) * 1.524
	assert_eq(WaterFlowBaker.resolution_for(two_hundred_feet), Vector2i(244, 244))
	assert_eq(WaterFlowBaker.resolution_for(Vector2(30, 15)), Vector2i(120, 60))
	assert_eq(WaterFlowBaker.resolution_for(Vector2(1, 500)), Vector2i(8, 512), "clamped")
	assert_eq(WaterFlowBaker.bank_fade_passes(Vector2i(512, 256)), 3)
	assert_eq(WaterFlowBaker.bank_fade_passes(Vector2i(244, 244)), 1)
	assert_eq(WaterFlowBaker.bank_fade_passes(Vector2i(8, 8)), 1)


# --- direction ------------------------------------------------------------------------


func test_straight_river_flows_the_way_it_was_drawn() -> void:
	var doc := _flat(20)
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)])
	_add_river(doc, 1, line, 1.5, 0.8)
	var baked := _bake(doc)
	var flow := _shader_flow(baked["rg"], baked["size"], doc.extent_m(), Vector2(0, 0))
	assert_almost_eq(flow.x, 0.8, 0.02, "downstream is +X at the drawn speed")
	assert_almost_eq(flow.y, 0.0, 0.01)
	var reversed := _flat(20)
	var back := PackedVector2Array([Vector2(10, 0), Vector2(-10, 0)])
	_add_river(reversed, 1, back, 1.5, 0.8)
	var baked_back := _bake(reversed)
	var flow_back := _shader_flow(
		baked_back["rg"], baked_back["size"], reversed.extent_m(), Vector2(0, 0)
	)
	assert_almost_eq(flow_back.x, -0.8, 0.02, "drawing it the other way reverses it")


func test_river_along_z_encodes_minus_z_in_green() -> void:
	var doc := _flat(20)
	var line := PackedVector2Array([Vector2(0, -10), Vector2(0, 10)])
	_add_river(doc, 1, line, 1.5, 1.0)
	var baked := _bake(doc)
	var size: Vector2i = baked["size"]
	var centre := _texel(baked["rg"], size, size.x >> 1, size.y >> 1)
	assert_almost_eq(centre.x, 128, 1, "no X flow")
	assert_lt(centre.y, 10, "flow +Z is local -y: G near 0 at full speed")
	var flow := _shader_flow(baked["rg"], size, doc.extent_m(), Vector2(0.3, 2.0))
	assert_almost_eq(flow.normalized().y, 1.0, 0.01, "the shader reads it back as +Z")
	assert_almost_eq(flow.length(), 1.0, 0.02)


func test_curved_river_follows_its_tangent() -> void:
	var doc := _flat(20)
	var line := PackedVector2Array()
	for k in 25:
		var angle := -PI / 2.0 + PI / 2.0 * k / 24.0
		line.append(Vector2(cos(angle), sin(angle)) * 8.0)
	_add_river(doc, 1, line, 1.5, 1.0)
	var baked := _bake(doc)
	for degrees in [-70.0, -45.0, -20.0]:
		var angle := deg_to_rad(degrees)
		var point := Vector2(cos(angle), sin(angle)) * 8.0
		var tangent := Vector2(-sin(angle), cos(angle))
		var flow := _shader_flow(baked["rg"], baked["size"], doc.extent_m(), point)
		assert_gt(flow.normalized().dot(tangent), 0.995, "along the arc at %s" % degrees)
		assert_almost_eq(flow.length(), 1.0, 0.03)


func test_confluence_weakens_toward_still_water() -> void:
	var doc := _flat(20)
	_add_river(doc, 1, PackedVector2Array([Vector2(-10, 0.4), Vector2(10, 0.4)]), 1.5, 1.0)
	_add_river(doc, 2, PackedVector2Array([Vector2(10, -0.4), Vector2(-10, -0.4)]), 1.5, 1.0)
	var baked := _bake(doc)
	var flow := _shader_flow(baked["rg"], baked["size"], doc.extent_m(), Vector2(0, 0))
	assert_lt(flow.length(), 0.1, "opposing rivers cancel between them, not renormalised")


# --- where there is no flow -----------------------------------------------------------


func test_ponds_are_still() -> void:
	var doc := _flat(20)
	var heights := doc.heights.duplicate()
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for z in range(30, 90):
		for x in range(30, 90):
			heights[doc.sample_index(x, z)] = BED
			mask[doc.sample_index(x, z)] = 4
	doc.heights = heights
	doc.pond_mask = mask
	doc.water_bodies.append(WaterBody.pond(4, WaterBody.Depth.DEEP, LEVEL))
	assert_gt(WaterGeometry.wet_samples(doc, doc.water_body(4)).size(), 3000, "wet")
	var baked := _bake(doc)
	assert_eq(baked["rg"].count(WaterFlowBaker.STILL), baked["rg"].size(), "all still")


func test_no_flow_outside_the_water() -> void:
	var doc := _flat(20)
	_add_river(doc, 1, PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)]), 1.5, 1.0)
	var baked := _bake(doc)
	var extent := doc.extent_m()
	for xz in [Vector2(0, 6), Vector2(0, -3.5), Vector2(13, 0), Vector2(-14, 10)]:
		var flow := _shader_flow(baked["rg"], baked["size"], extent, xz)
		assert_eq(flow, Vector2.ZERO, "still at %s" % xz)
	var dry := _flat(20)
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5])
	dry.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, LEVEL))
	var uncarved := _bake(dry)
	assert_eq(
		uncarved["rg"].count(WaterFlowBaker.STILL),
		uncarved["rg"].size(),
		"a river over ground above its level has no wet texels, so no flow"
	)


func test_border_is_still() -> void:
	var doc := _flat(20)
	var half := doc.extent_m().x * 0.5
	_add_river(doc, 1, PackedVector2Array([Vector2(-half, 0), Vector2(half, 0)]), 2.0, 1.0)
	var baked := _bake(doc)
	var rg: PackedByteArray = baked["rg"]
	var size: Vector2i = baked["size"]
	var row := size.y >> 1
	assert_eq(_texel(rg, size, 0, row), Vector2i(128, 128), "left edge on the river")
	assert_eq(_texel(rg, size, size.x - 1, row), Vector2i(128, 128), "right edge")
	assert_gt(_texel(rg, size, 1, row).x, 200, "one texel in, it flows")
	for i in size.x:
		assert_eq(_texel(rg, size, i, 0), Vector2i(128, 128))
		assert_eq(_texel(rg, size, i, size.y - 1), Vector2i(128, 128))


# --- conventions ----------------------------------------------------------------------


## The byte layout of the baked data is Image's: row j is get_pixel(_, j), which Godot
## samples at v = (j + 0.5) / height; and it ships through the PNG entry unchanged.
func test_rows_are_image_rows() -> void:
	var doc := _flat(20)
	_add_river(doc, 1, PackedVector2Array([Vector2(-5, -8), Vector2(5, -8)]), 1.5, 1.0)
	var baked := _bake(doc)
	var size: Vector2i = baked["size"]
	var image := WaterFlowBaker.to_image(baked["rg"], size)
	var z := -8.0
	var j := int((z + doc.extent_m().y * 0.5) / doc.extent_m().y * size.y)
	var i := size.x >> 1
	assert_almost_eq(image.get_pixel(i, j).r * 255.0, 255.0, 3.0, "row j holds z = -8")
	assert_eq(_texel(baked["rg"], size, i, size.y - 1 - j), Vector2i(128, 128), "not flipped")
	var decoded := Image.new()
	assert_eq(decoded.load_png_from_buffer(image.save_png_to_buffer()), OK)
	decoded.convert(Image.FORMAT_RG8)
	assert_true(decoded.get_data() == baked["rg"], "the PNG round trip is lossless")


func test_encoding_quantisation() -> void:
	var doc := _flat(20)
	_add_river(doc, 1, PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)]), 1.5, 0.5)
	var baked := _bake(doc)
	var size: Vector2i = baked["size"]
	var centre := _texel(baked["rg"], size, size.x >> 1, size.y >> 1)
	assert_eq(centre, Vector2i(roundi(0.75 * 255.0), 128), "R = 0.5 * 0.5 + 0.5, G still")


func test_bake_is_deterministic() -> void:
	var doc := _flat(20)
	var line := PackedVector2Array([Vector2(-10, -4), Vector2(0, 3), Vector2(9, -2)])
	_add_river(doc, 1, line, 1.5, 1.0)
	_add_river(doc, 2, PackedVector2Array([Vector2(-3, 12), Vector2(0, 3)]), 1.0, 0.6)
	var first := _bake(doc)
	var second := _bake(doc)
	assert_true(first["rg"] == second["rg"], "same document, same bytes")


# --- cost -----------------------------------------------------------------------------


## A 200 ft map (40 cells, 61 m) with three winding rivers of 40 control points each.
func test_bake_time_for_a_200_ft_map() -> void:
	var doc := _flat(40)
	var half := doc.extent_m().x * 0.5
	for r in 3:
		var line := PackedVector2Array()
		for k in 40:
			var x := -half + 1.0 + (2.0 * half - 2.0) * k / 39.0
			line.append(Vector2(x, -18.0 + 18.0 * r + sin(k * 0.4 + r) * 4.0))
		_add_river(doc, r + 1, line, 1.0 + r * 0.75, 1.0)
	var size := WaterFlowBaker.resolution_for(doc.extent_m())
	var start := Time.get_ticks_usec()
	var rg := WaterFlowBaker.bake(doc, size)
	var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0
	gut.p("flow bake, 200 ft map, 3 rivers, %s texels: %.0f ms" % [size, elapsed_ms])
	assert_eq(rg.size(), size.x * size.y * 2)
	assert_lt(elapsed_ms, 5000.0, "a bake on stroke release stays interactive")
