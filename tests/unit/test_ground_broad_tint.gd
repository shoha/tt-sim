extends GutTest

## The broad edge's one-map tint (ground layers card G4, GroundBroadTint): the tint plane's
## colour and weight per sample on a two-biome border, a trampled path and a three-biome
## junction, the shader's own-component subtraction through its CPU twin (tint_at), and that
## the shader's constants and defaults mirror the CPU's.

const SHADER_PATH := "res://shaders/authored_ground.gdshaderinc"
const FOREST := Color(0.1, 0.3, 0.05)
const TAIGA := Color(0.2, 0.12, 0.05)
const ALPINE := Color(0.3, 0.5, 0.1)
const PATH := Color(0.4, 0.35, 0.3)
const SIZE := 30


func _doc(slots: Callable) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(SIZE, SIZE), "grass", "test", 3)
	doc.biome_ids = PackedStringArray(["a", "b", "c"])
	var bytes := PackedByteArray()
	bytes.resize(doc.sample_count())
	doc.biome_slots = bytes
	doc.biome_density = bytes.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var slot: int = slots.call(x, z)
			doc.biome_slots[doc.sample_index(x, z)] = slot
			doc.biome_density[doc.sample_index(x, z)] = 255 if slot > 0 else 0
	return doc


func _biome_tints() -> PackedColorArray:
	return PackedColorArray(
		[
			Color(0, 0, 0, 0),
			Color(FOREST, 1.0),
			Color(TAIGA, 1.0),
			Color(ALPINE, 1.0),
		]
	)


func _whole(doc: MapDocument) -> Rect2i:
	return Rect2i(0, 0, doc.samples_x(), doc.samples_z())


## Sample (x, z) of a tint plane as a Color.
func _at(doc: MapDocument, plane: PackedFloat32Array, x: int, z: int) -> Color:
	var o := doc.sample_index(x, z) * GroundBroadTint.CHANNELS
	return Color(plane[o], plane[o + 1], plane[o + 2], plane[o + 3])


func _assert_color(actual: Color, expected: Color, message: String) -> void:
	for c in 4:
		assert_almost_eq(actual[c], expected[c], 1e-5, "%s (channel %d)" % [message, c])


func test_two_biome_border_tints_the_base_and_cancels_between_the_biomes() -> void:
	# Forest west of x = 10, taiga east of x = 20, the base between.
	var doc := _doc(func(x: int, _z: int) -> int: return 1 if x < 10 else (2 if x >= 20 else 0))
	var plane := GroundBroadTint.tint_plane(doc, _biome_tints(), PackedColorArray(), _whole(doc))
	_assert_color(_at(doc, plane, 3, 3), Color(FOREST, 1.0), "a forest sample")
	_assert_color(_at(doc, plane, 25, 3), Color(TAIGA, 1.0), "a taiga sample")
	_assert_color(_at(doc, plane, 15, 3), Color(0, 0, 0, 0), "the base holds no tint")
	# A filtered texel across a forest | taiga border: both, premultiplied.
	var border := Color(FOREST * 0.6 + TAIGA * 0.4, 1.0)
	border.a = 1.0
	var on_taiga := GroundBroadTint.tint_at(
		border, PackedColorArray([Color(TAIGA, 1.0)]), PackedFloat32Array([1.0])
	)
	assert_eq(on_taiga.a, 0.0, "a fully painted biome pixel is not tinted by its neighbour")
	var mixed := GroundBroadTint.tint_at(
		border,
		PackedColorArray([Color(TAIGA, 1.0), Color(FOREST, 1.0)]),
		PackedFloat32Array([0.5, 0.5])
	)
	assert_eq(mixed.a, 0.0, "nor is the frayed edge between them")
	# Beside the base: the forest's halo at the slot table's strength.
	var halo := Color(FOREST * 0.3, 0.3)
	var on_base := GroundBroadTint.tint_at(halo, PackedColorArray(), PackedFloat32Array())
	_assert_color(
		on_base,
		Color(FOREST, GroundBroadTint.STRENGTH * smoothstep(0.0, GroundBroadTint.FULL, 0.3)),
		"the base beside the forest recolours toward it"
	)


func test_a_trampled_path_tints_the_forest_it_crosses() -> void:
	var doc := _doc(func(_x: int, _z: int) -> int: return 1)
	var slot := doc.ensure_surface("cobblestone")
	for z in doc.samples_z():
		doc.set_surface_weight(doc.sample_index(14, z), slot, 255)
	var paints := PackedColorArray([Color(PATH, GroundBroadTint.TRAMPLE_WEIGHT)])
	var plane := GroundBroadTint.tint_plane(doc, _biome_tints(), paints, _whole(doc))
	var k := GroundBroadTint.TRAMPLE_WEIGHT
	_assert_color(
		_at(doc, plane, 14, 5),
		Color(FOREST.r + PATH.r * k, FOREST.g + PATH.g * k, FOREST.b + PATH.b * k, 1.0 + k),
		"on the path: the forest under it and the path"
	)
	_assert_color(_at(doc, plane, 2, 5), Color(FOREST, 1.0), "the forest beside it")
	# A filtered texel near the path (a quarter of it), on a forest pixel.
	var near := Color(
		FOREST.r + PATH.r * k * 0.25,
		FOREST.g + PATH.g * k * 0.25,
		FOREST.b + PATH.b * k * 0.25,
		1.0 + k * 0.25
	)
	var forest := GroundBroadTint.tint_at(
		near, PackedColorArray([Color(FOREST, 1.0)]), PackedFloat32Array([1.0])
	)
	_assert_color(
		forest,
		Color(PATH, GroundBroadTint.STRENGTH * smoothstep(0.0, GroundBroadTint.FULL, k * 0.25)),
		"the forest recolours toward the path"
	)
	var on_path := GroundBroadTint.tint_at(
		near, PackedColorArray([Color(FOREST, 1.0), Color(PATH, k)]), PackedFloat32Array([1.0, 1.0])
	)
	assert_eq(on_path.a, 0.0, "the path itself is not tinted toward itself")


func test_three_biome_junction_leaves_each_biome_its_own_colour() -> void:
	var doc := _doc(func(x: int, z: int) -> int: return 3 if z >= 15 else (1 if x < 15 else 2))
	var plane := GroundBroadTint.tint_plane(doc, _biome_tints(), PackedColorArray(), _whole(doc))
	_assert_color(_at(doc, plane, 20, 25), Color(ALPINE, 1.0), "the third biome")
	# The junction texel: a box over the three, then each biome's pixel in it.
	var sum := Color(0, 0, 0, 0)
	for z in range(8, 22):
		for x in range(8, 22):
			sum += _at(doc, plane, x, z)
	var texel := sum / 196.0
	assert_almost_eq(texel.a, 1.0, 1e-5, "every sample is one biome")
	for own in [FOREST, TAIGA, ALPINE]:
		var tint := GroundBroadTint.tint_at(
			texel, PackedColorArray([Color(own, 1.0)]), PackedFloat32Array([1.0])
		)
		assert_eq(tint.a, 0.0, "no cast of the other two on %s" % own)
	# The base beside the junction (the same mix, half covered): their weighted mean.
	var half := texel * 0.5
	var on_base := GroundBroadTint.tint_at(half, PackedColorArray(), PackedFloat32Array())
	var mean := Color(texel.r, texel.g, texel.b)
	for c in 3:
		assert_almost_eq(on_base[c], mean[c], 1e-5, "the base tints toward the mean")
	# Snow painted on the base there keeps its colour: painted weight wins.
	var snow := GroundBroadTint.tint_at(half, PackedColorArray(), PackedFloat32Array(), 1.0)
	assert_eq(snow.a, 0.0, "a painted stroke holds its colour")
	var thin := GroundBroadTint.tint_at(half, PackedColorArray(), PackedFloat32Array(), 0.5)
	assert_almost_eq(thin.a, on_base.a * 0.5, 1e-5, "half painted, half the tint")


func test_the_broad_image_filters_premultiplied_into_half_floats() -> void:
	var doc := _doc(func(x: int, _z: int) -> int: return 1 if x < doc_half() else 0)
	var size := Vector2i(doc.samples_x(), doc.samples_z())
	var plane := GroundBroadTint.tint_plane(doc, _biome_tints(), PackedColorArray(), _whole(doc))
	var mirror := GroundBroadTint.plane_image(size, plane)
	assert_eq(mirror.get_format(), Image.FORMAT_RGBAF)
	var broad := GroundBroadTint.broad_image(mirror)
	assert_eq(broad.get_format(), Image.FORMAT_RGBAH)
	assert_eq(broad.get_size(), GroundBroadTint.broad_size(size))
	var west := broad.get_pixel(0, 1)
	assert_gt(west.a, 0.6, "the forest's texel")
	assert_almost_eq(west.g / west.a, FOREST.g, 0.01, "its colour, un-premultiplied")
	assert_lt(broad.get_pixel(broad.get_width() - 1, 1).a, 0.4, "the base's texel")


## Half the test document's samples on an axis.
func doc_half() -> int:
	return SIZE * 2


func test_shader_mirrors_the_tint_constants() -> void:
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	var constant := func(const_name: String) -> float:
		var regex := RegEx.create_from_string("const float %s = ([0-9.]+);" % const_name)
		var m := regex.search(text)
		return float(m.get_string(1)) if m != null else -1.0
	var default := func(uniform_name: String) -> float:
		var regex := RegEx.create_from_string("uniform float %s [^=]*= ([0-9.]+);" % uniform_name)
		var m := regex.search(text)
		return float(m.get_string(1)) if m != null else -1.0
	assert_almost_eq(constant.call("BROAD_OWN_START"), GroundBroadTint.OWN_START, 1e-6)
	assert_almost_eq(constant.call("BROAD_OWN_END"), GroundBroadTint.OWN_END, 1e-6)
	assert_almost_eq(default.call("biome_broad_strength"), GroundBroadTint.STRENGTH, 1e-6)
	assert_almost_eq(default.call("biome_broad_full"), GroundBroadTint.FULL, 1e-6)
	assert_string_contains(text, "uniform vec4 layer_tint[%d];" % GroundLayers.MAX_LAYERS)
	assert_false(text.contains("layer_broad_b"), "one map, not the slot table's two")
