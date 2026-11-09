extends GutTest

## GroundSteepZones (steepzones): the GDScript mirrors of the steep faces' weight and height-layer
## blend (ground_steep_zones.gdshaderinc), the per-field layer lengths, the bake's size and the
## ground's uniforms. The pixels are checked by the steepzones render jobs.


## A merged look: GroundLook's defaults with three colours.
func _look() -> Dictionary:
	var look: Dictionary = GroundLook.BASE.duplicate(true)
	look.zones.colors_linear = [[0.27, 0.39, 0.05], [0.3, 0.4, 0.1], [0.2, 0.3, 0.1]]
	return look


func test_weight_is_exactly_zero_on_ground_gentler_than_29_5_degrees() -> void:
	for deg in [0.0, 5.0, 15.0, 25.0, 29.0, 29.5]:
		var a := deg_to_rad(deg)
		assert_eq(GroundSteepZones.weight(Vector3(sin(a), cos(a), 0.0)), 0.0, "%s deg" % deg)


func test_weight_is_one_on_faces_steeper_than_44_8_degrees() -> void:
	for deg in [44.8, 50.0, 70.0, 80.0, 90.0]:
		var a := deg_to_rad(deg)
		assert_almost_eq(GroundSteepZones.weight(Vector3(sin(a), cos(a), 0.0)), 1.0, 1e-6)


func test_weight_rises_with_the_slope() -> void:
	var last := -1.0
	for i in 91:
		var a := deg_to_rad(float(i))
		var w := GroundSteepZones.weight(Vector3(sin(a), cos(a), 0.0))
		assert_true(w >= last, "monotone at %d deg" % i)
		last = w


func test_weight_is_the_same_for_every_facing() -> void:
	var a := deg_to_rad(38.0)
	var expected := GroundSteepZones.weight(Vector3(sin(a), cos(a), 0.0))
	assert_true(expected > 0.0 and expected < 1.0, "38 degrees is in the blend")
	for k in 16:
		var turn := k * TAU / 16.0
		var n := Vector3(sin(a) * cos(turn), cos(a), sin(a) * sin(turn))
		assert_almost_eq(GroundSteepZones.weight(n), expected, 1e-6, "facing %d" % k)
	# Any length: the normal is normalised first.
	assert_almost_eq(GroundSteepZones.weight(Vector3(sin(a), cos(a), 0.0) * 3.0), expected, 1e-6)


func test_layer_weights_are_a_partition_of_unity() -> void:
	for i in 400:
		var h := -6.0 + i * 0.0371
		var w := GroundSteepZones.layer_weights(h)
		assert_eq(w.size(), GroundSteepZones.LAYERS)
		var total := 0.0
		for v in w:
			assert_true(v >= 0.0, "non-negative at %s" % h)
			total += v
		assert_almost_eq(total, 1.0, 1e-6, "sum at %s" % h)


func test_layer_weights_are_continuous_across_layer_planes() -> void:
	for k in range(-3, 4):
		var plane := float(k) - GroundSteepZones.PHASE
		var below := GroundSteepZones.layer_weights(plane - 1e-5)
		var above := GroundSteepZones.layer_weights(plane + 1e-5)
		for i in GroundSteepZones.LAYERS:
			assert_almost_eq(below[i], above[i], 1e-3, "layer %d at plane %d" % [i, k])
		# At the plane only one layer holds.
		var at := GroundSteepZones.layer_weights(plane)
		assert_almost_eq(at[posmod(k, GroundSteepZones.LAYERS)], 1.0, 1e-6)


func test_no_field_is_flat_in_height_at_height_zero() -> void:
	# The phase puts height 0 mid-layer, where two layers share the weight half and half.
	var w := GroundSteepZones.layer_weights(0.0)
	assert_almost_eq(w[0], 0.5, 1e-6)
	assert_almost_eq(w[1], 0.5, 1e-6)


func test_blend_at_a_layer_plane_is_that_layer() -> void:
	var v := PackedFloat32Array([0.62, 0.41, 0.55])
	for k in range(-3, 4):
		var plane := float(k) - GroundSteepZones.PHASE
		var expected := v[posmod(k, GroundSteepZones.LAYERS)]
		assert_almost_eq(GroundSteepZones.blend(v, plane), expected, 1e-5, "plane %d" % k)


func test_blend_keeps_the_spread_of_independent_layers() -> void:
	# Mixing two fields half and half would halve the variance; the blend restores it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sum2 := 0.0
	var n := 4000
	for i in n:
		var v := PackedFloat32Array(
			[rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7)]
		)
		var d := GroundSteepZones.blend(v, 0.0) - 0.5
		sum2 += d * d
	var expected := 0.4 * 0.4 / 12.0
	assert_almost_eq(sum2 / n, expected, expected * 0.1)


func test_each_field_takes_its_own_layer_length() -> void:
	var look := _look()
	look.zones.scale_m = [12.0, 7.0, 5.0]
	look.zones.rag_m = 1.2
	look.light.scale_m = 6.0
	var lengths := GroundSteepZones.layer_lengths(look)
	assert_eq(lengths.fields, Vector4(12.0, 7.0, 5.0, 6.0))
	assert_almost_eq(float(lengths.rag), 1.2, 1e-6)
	look.zones.nest = 1.0
	assert_eq(GroundSteepZones.layer_lengths(look).fields.z, 7.0, "a nested third zone")


func test_atlas_size_and_bytes() -> void:
	# A 100 ft map: its bake rect is the map plus 24 m each side.
	var rect := Vector4(-39.24, -39.24, 78.48, 78.48)
	var cell := GroundSteepZones.cell_px(rect)
	assert_eq(cell, Vector2i(393, 393))
	assert_eq(GroundSteepZones.atlas_px(cell, 1), Vector2i(1179, 786))
	assert_eq(GroundSteepZones.atlas_bytes(rect, 1), 1179 * 786 * 4)
	# The cell is capped, so four slots on the largest map stay within 16384 px.
	var huge := Vector4(-200.0, -200.0, 400.0, 400.0)
	var px := GroundSteepZones.atlas_px(GroundSteepZones.cell_px(huge), 4)
	assert_eq(px, Vector2i(3072, 8192))


func test_params_pack_each_slot() -> void:
	var look := _look()
	look.zones.colors_linear = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6], [0.7, 0.8, 0.9], [0.2, 0.2, 0.2]]
	look.zones.cover = [0.3, 0.2, 0.1]
	var ref := Color(0.25, 0.35, 0.05)
	var p := GroundSteepZones.params([look], [ref])
	assert_eq(p.size(), GroundLookUniforms.SLOTS * GroundSteepZones.PARAMS)
	assert_eq(p[1], Vector4(0.4, 0.5, 0.6, look.zones.rag))
	assert_eq(p[4], Vector4(0.3, 0.2, 0.1, look.light.key))
	assert_eq(p[6], GroundSteepZones.layer_lengths(look).fields)
	assert_almost_eq(p[10].x, 0.25, 1e-6, "the raw reference, as the bake's")
	assert_eq(p[GroundSteepZones.PARAMS], Vector4.ZERO, "an unused slot")


func test_ground_tables_carry_the_steep_bake() -> void:
	var look := _look()
	look.zones.colors_linear = [[0.1, 0.2, 0.3]]
	var rows := [{"biome": "b", "ground": 0}]
	var the_plan := GroundLookUniforms.plan(rows, {"b": look}, func(_s: String) -> int: return -1)
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var rect := Vector4(-39.24, -39.24, 78.48, 78.48)
	var tables := GroundLookUniforms.ground_tables(
		the_plan, [look], [Color(0.2, 0.3, 0.1)], [null], rect, tex
	)
	assert_eq(tables.look_steep, tex)
	assert_eq(tables.look_steep_atlas, Vector4(1.0, 393.0, 393.0, 0.0))
	assert_eq((tables.look_steep_params as PackedVector4Array).size(), 48)
