extends GutTest

## FireLook's drawing of the persistent fire: the fire book (and the smoke's book with it) is asked
## for only once a field in the tree has fire, bound once it lands and let go when the last field
## leaves the tree; a chunk's
## bounds hold every corner of every quad at fire_flames.gdshader's jitter maxima (the quad's
## numbers read from the shader's own source, so the bounds cannot drift from it); the instance
## buffer draws back to front and carries each fire's integer seed.

const FORWARDS: Array[Vector3] = [
	FireLook.DEFAULT_FORWARD, Vector3(-0.5, -0.7, -0.5), Vector3(0.3, -0.2, -0.9)
]


func before_each() -> void:
	FireLook.release_book()


func after_all() -> void:
	FireLook.release_book()


func _doc(heat: int) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 5)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	mask.fill(heat)
	doc.fire_mask = mask
	return doc


func test_the_book_loads_with_fire_and_goes_with_the_last_field() -> void:
	var doc := _doc(0)
	var field := FireField.create(doc)
	add_child(field)
	assert_eq(FireLook.live_fields(), 1)
	assert_eq(FireLook.book_state(), FireLook.Book.NONE, "no fire: no book")
	var mask := doc.fire_mask.duplicate()
	mask.fill(160)
	doc.fire_mask = mask
	field.refresh(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	assert_gt(field.flame_count(), 0)
	assert_eq(FireLook.book_state(), FireLook.Book.LOADING, "asked for with the first fire")
	assert_eq(FireFieldSmoke.book_state(), FireLook.Book.LOADING, "the smoke's with it")
	var other := FireField.create(_doc(160))
	assert_eq(FireLook.live_fields(), 1, "a field out of the tree is not counted")
	add_child(other)
	assert_eq(FireLook.live_fields(), 2)
	assert_true(FireLook.finish_book(), "the book lands")
	var material := FireLook.material()
	assert_not_null(material.get_shader_parameter("flipbook"), "bound")
	assert_eq(material.get_shader_parameter("drawings"), 48)
	assert_eq(material.get_shader_parameter("tear_layer"), 384)
	var bounds: PackedVector4Array = material.get_shader_parameter("seq_bounds")
	assert_eq(bounds.size(), FireLook.BOOK_SEQUENCES, "padded to the shader's array")
	assert_eq(material.get_shader_parameter("class_first"), Vector4i(0, 3, 5, 8))
	var smoke := FireFieldSmoke.material()
	assert_not_null(smoke.get_shader_parameter("smoke_book"), "the smoke's book is bound too")
	assert_eq(smoke.get_shader_parameter("frames"), 24)
	var timings := FireLook.book_timings()
	assert_gt(float(timings.load_ms), 0.0)
	field.free()
	assert_eq(FireLook.book_state(), FireLook.Book.READY, "a field is still in the tree")
	assert_not_null(FireLook.book_texture())
	other.free()
	assert_eq(FireLook.live_fields(), 0)
	assert_eq(FireLook.book_state(), FireLook.Book.NONE, "the last field's exit lets go")
	assert_null(FireLook.book_texture())
	assert_null(material.get_shader_parameter("flipbook"), "the sampler is null")
	assert_eq(material.get_shader_parameter("drawings"), 0, "and nothing draws")
	assert_eq(FireFieldSmoke.book_state(), FireLook.Book.NONE, "the smoke's goes with it")
	assert_null(smoke.get_shader_parameter("smoke_book"))
	assert_eq(smoke.get_shader_parameter("frames"), 0, "and no column draws")


func test_a_fieldless_fire_is_not_loaded_and_a_cold_field_asks_nothing() -> void:
	var lit := FireField.create(_doc(160))
	assert_gt(lit.flame_count(), 0)
	assert_eq(FireLook.book_state(), FireLook.Book.NONE, "planned out of the tree: no load")
	lit.free()
	var cold := FireField.create(_doc(0))
	add_child(cold)
	assert_eq(FireLook.book_state(), FireLook.Book.NONE)
	cold.free()


func test_the_bounds_hold_every_quad_at_the_jitter_maxima() -> void:
	var tall := FireFires.largest_height_m()
	var blaze := FireField.BLAZE_HEIGHT_M * FireField.BIG_SCALE.y * FireFires.SIM_BLAZE_SCALE
	var spark := FireField.SPARK_SIZE_M
	var plan := PackedFloat32Array()
	plan.append_array([0.0, 1.0, 0.0, 0.7, 0.3, tall, tall * FireFires.FIRE_WIDTH.y, 0.0])
	plan.append_array([3.0, 0.5, -2.0, 1.0, 0.6, blaze, blaze * FireFires.SIM_BLAZE_SHARE, 0.0])
	plan.append_array([-2.0, 0.0, 2.5, 0.5, 0.1, 0.9, 0.5, FireField.FLAME])
	plan.append_array([1.0, 0.2, 3.0, 0.2, 0.9, spark, spark, FireField.SPARK])
	var count := plan.size() / FireField.STRIDE
	var wind := FireLook.wind_for(1234)
	var outside := 0
	var corners := 0
	for forward in FORWARDS:
		var box := FireLook.bounds(plan, count, forward).grow(1e-4)
		for k in count:
			for corner in _corners(plan, k, forward, wind):
				corners += 1
				if not box.has_point(corner):
					outside += 1
	assert_gt(corners, 1000)
	assert_eq(outside, 0, "every corner inside its chunk's bounds")
	# Not much more than that: the tallest fire's box stays within its reach.
	var reach := FireLook.bounds(plan, 1, FireLook.DEFAULT_FORWARD)
	assert_lt(reach.size.y, tall * 3.2, "about 2.97 heights up, at most")
	assert_lt(maxf(reach.size.x, reach.size.z), tall * 5.0)


func test_the_buffer_draws_back_to_front_with_each_fires_seed() -> void:
	var plan := FireField.plan_block(_doc(255), Vector2i(1, 1))
	var count := plan.size() / FireField.STRIDE
	assert_gt(count, 10)
	var forward := FireLook.DEFAULT_FORWARD.normalized()
	var buffer := FireLook.instance_buffer(plan, count, forward)
	assert_eq(buffer.size(), count * FireLook.INSTANCE_FLOATS)
	var last := INF
	var ordered := true
	var whole := true
	var seeds := {}
	for slot in count:
		var i := slot * FireLook.INSTANCE_FLOATS
		var depth := Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11]).dot(forward)
		ordered = ordered and depth <= last + 1e-4
		last = depth
		var fire := buffer[i + 15]
		whole = whole and fire == floorf(fire) and fire == FireLook.fire_seed(buffer[i + 12])
		whole = whole and fire >= 0.0 and fire < FireLook.SEED_RANGE
		seeds[fire] = true
	assert_true(ordered, "the far flames first")
	assert_true(whole, "each custom w is its plan seed's integer seed, exact in a float")
	assert_eq(seeds.size(), count, "every fire its own seed")


## Every corner the shader can give entry `k` of `plan` along `forward` under `wind`, at the
## ends of every pick (a hot fire's full jitter; a spark's whole life).
func _corners(
	plan: PackedFloat32Array, k: int, forward: Vector3, wind: Vector2
) -> Array[Vector3]:
	var o := k * FireField.STRIDE
	var foot := Vector3(plan[o], plan[o + 1], plan[o + 2])
	var h := plan[o + FireField.HEIGHT]
	var w := plan[o + FireField.WIDTH]
	var frame := FireLook.view_frame(forward)
	var right := frame.x
	var up := frame.y
	var toward := frame.z * (_const("TOWARD_CAMERA_M")[0] + _const("TOWARD_CAMERA")[0] * 0.5 * w)
	var out: Array[Vector3] = []
	if plan[o + FireField.KIND] == FireField.SPARK:
		var drift := Vector3(wind.x, 0.0, wind.y).normalized() * _const("SPARK_DRIFT_M")[0]
		var rise: float = _const("SPARK_RISE_M")[0]
		for life: float in [0.0, 1.0]:
			var centre := foot + drift * life + Vector3.UP * life * rise
			var grow := 1.0 - 0.5 * life
			for wobble: float in [-0.08, 0.08]:
				for x: float in [-0.5, 0.5]:
					for y: float in [-0.5, 0.5]:
						var quad := (right * x + up * y) * w * grow
						out.append(centre + right * wobble + quad + toward)
		return out
	var room: float = _const("ROOM")[0]
	var tile_w: float = _const("TILE_ASPECT")[0] * room * h
	var jitter := _const("SHAPE_JITTER")
	var reach: float = _const("LEAN_REACH")[0]
	# The wind's lean at its gust's and its own draw's tops: (0.85 + 0.3) x (0.9 + 0.2).
	var lean := wind.length() * h * 1.15 * 1.1
	for grow: float in _const("SIZE_JITTER"):
		for u: float in [0.0, 1.0]:
			for v: float in [0.0, room]:
				for wide: float in [1.0 - jitter[1], 1.0 + jitter[1]]:
					for tall: float in [1.0 - jitter[0], 1.0 + jitter[0]]:
						for tilt: float in [-jitter[2] * h, jitter[2] * h]:
							for side: float in [-lean, lean]:
								var a: float = (
									(u - 0.5) * tile_w * wide + (side + tilt) * minf(v * v, reach)
								)
								var b: float = v * h * tall
								out.append(foot + (right * a + up * b) * grow + toward)
	return out


## The numbers of fire_flames.gdshader's constant `name` (a float or a vector), from its source.
func _const(const_name: String) -> Array[float]:
	var regex := RegEx.create_from_string(
		"const\\s+(?:float|vec2|vec3|vec4)\\s+%s\\s*=\\s*([^;]+);" % const_name
	)
	var found := regex.search(FireLook.FLAMES_SHADER.code)
	assert_not_null(found, "the shader holds %s" % const_name)
	var text := found.get_string(1) if found != null else "0"
	var open := text.find("(")
	if open >= 0:
		text = text.substr(open + 1, text.rfind(")") - open - 1)
	var out: Array[float] = []
	for part in text.split(","):
		out.append(float(part.strip_edges()))
	return out
