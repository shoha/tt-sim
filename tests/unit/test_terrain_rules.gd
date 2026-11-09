extends GutTest

## TerrainRules: the automatic dressing's formulas against hand-computed values (slope tail,
## edge noise, lip, ramp, scree), the per-vertex fields (curvature and steepness nearby)
## against a brute-force box mean and hand values on a tier step, the barycentric field
## lookup, and that every rule constant the ground shader mirrors has the same value there.

const SHADER_PATH := "res://shaders/authored_ground.gdshaderinc"
## Constants that must exist in both TerrainRules and the shader (CLIFF_START_COS and
## CLIFF_END_COS are the shader's cosines of the degree constants).
const MIRRORED := [
	"CLIFF_EDGE_NOISE",
	"LIP_CURVATURE_START",
	"LIP_CURVATURE_END",
	"LIP_STRENGTH",
	"LIP_SHEER_TAIL",
	"RAMP_LOW",
	"RAMP_HIGH",
	"SCREE_CURVATURE_START",
	"SCREE_CURVATURE_END",
	"SCREE_NEAR_START",
	"SCREE_NEAR_END",
	"SCREE_EDGE_NOISE",
	"SCREE_BREAKUP_SCALE_M",
	"SCREE_FAN",
	"SCREE_BREAKUP_LOW",
	"SCREE_BREAKUP_HIGH",
	"RULE_NOISE_SCALE_M",
	"RULE_NOISE_LAYER_OFFSET",
	"PROJECTION_SHARPNESS",
	"PROJECTION_MIN_WEIGHT",
	"CLIFF_NOISE_OFFSET",
	"SCREE_NOISE_OFFSET",
	"SCREE_BREAKUP_OFFSET",
	"PAINT_EDGE_WARP_M",
	"PAINT_EDGE_SCALE_M",
	"PAINT_EDGE_NOISE",
	"PAINT_WARP_OFFSET_A",
	"PAINT_WARP_OFFSET_B",
	"PAINT_NOISE_OFFSET",
	"PAINT_CLIFF_YIELD",
	"PAINT_WATER_YIELD",
	"PAINT_FORD_START_M",
	"PAINT_FORD_END_M",
]
const STEP := Vector2(0.25, 0.25)
const EPS := 1e-4


func test_cliff_rule_matches_hand_values() -> void:
	# 50 degrees: tail (0.64279 - 0.71934) / (0.52992 - 0.71934) = 0.40414, no noise
	# (0.5 is the neutral value), ramp (0.40414 - 0.2) / 0.6 = 0.34023, smoothstep 0.26850.
	var fifty := cos(deg_to_rad(50.0))
	assert_almost_eq(TerrainRules.cliff_from(fifty, 0.0, 0.5), 0.268504, EPS)
	# 55 degrees: tail 0.76952 -> ramp 0.94921 -> 0.99252; a full convex lip keeps 0.4 of
	# the tail (0.30781) -> ramp 0.17968 -> 0.08526.
	var fifty_five := cos(deg_to_rad(55.0))
	assert_almost_eq(TerrainRules.cliff_from(fifty_five, 0.0, 0.5), 0.992520, EPS)
	assert_almost_eq(TerrainRules.cliff_from(fifty_five, 0.2, 0.5), 0.085256, EPS)
	# Edge noise moves the tail by up to CLIFF_EDGE_NOISE: at 50 degrees the tail 0.40414
	# becomes 0.75414 at noise 1 (ramp 0.92356 -> 0.98337).
	assert_almost_eq(TerrainRules.cliff_from(fifty, 0.0, 1.0), 0.983368, EPS)


func test_tier_faces_are_rock_and_raised_hills_are_ground() -> void:
	# A tier face's shading normal is about 63 degrees (HeightBrush's soft profile): fully
	# rock whatever the noise. A sheer 70 degree face is at the end of the lip rule's reach
	# (tail 1.99, LIP_SHEER_TAIL 2), so a convex lip above it takes no rock back from it.
	var face := cos(deg_to_rad(63.0))
	var sheer := cos(deg_to_rad(70.0))
	# A hill raised with the Raise brush has 35 to 47 degree flanks: 40 degrees is ground
	# whatever the noise (P3-7: the rule started at 38 and left bare mounds in a forest).
	var hill := cos(deg_to_rad(40.0))
	for k in 11:
		var noise := k / 10.0
		assert_eq(TerrainRules.cliff_from(face, 0.0, noise), 1.0, "tier face at noise %s" % noise)
		assert_eq(TerrainRules.cliff_from(sheer, 0.3, noise), 1.0, "sheer face under a lip")
		assert_eq(TerrainRules.cliff_from(hill, 0.0, noise), 0.0, "40 degree hill at %s" % noise)
	assert_eq(TerrainRules.cliff_from(1.0, 0.0, 1.0), 0.0, "flat ground")


func test_scree_rule_matches_hand_values() -> void:
	# Concave 0.12 m: tail (0.12 - 0.02) / 0.1 = 1; steepness 0.1: tail 1; breakup 1: no gap.
	assert_almost_eq(TerrainRules.scree_from(-0.12, 0.1, 0.0, 0.5, 1.0), 1.0, EPS)
	assert_almost_eq(
		TerrainRules.scree_from(-0.12, 0.1, 0.25, 0.5, 1.0), 0.75, EPS, "not under rock"
	)
	# Breakup 0.39: the fan pulls the tail in by 0.11 * 1.6 (still saturated) and the gap
	# smoothstep (0.15 .. 0.45) is at 0.8, so 0.896.
	assert_almost_eq(TerrainRules.scree_from(-0.12, 0.1, 0.0, 0.5, 0.39), 0.896, EPS)
	# Steepness 0.065 is half its tail: m = 0.5, ramp (0.5 - 0.2) / 0.6 = 0.5 -> 0.5.
	assert_almost_eq(TerrainRules.scree_from(-0.12, 0.065, 0.0, 0.5, 1.0), 0.5, EPS)
	# Barely concave (tail -0.1): nothing at a neutral breakup; where the breakup is high the
	# fan reaches it (tail -0.1 + 0.8 = 0.7, ramp 0.833 -> 0.926).
	assert_eq(TerrainRules.scree_from(-0.01, 0.1, 0.0, 0.5, 0.5), 0.0, "barely concave")
	assert_almost_eq(TerrainRules.scree_from(-0.01, 0.1, 0.0, 0.5, 1.0), 0.925926, EPS, "a fan")
	assert_eq(TerrainRules.scree_from(-0.3, 0.0, 0.0, 1.0, 1.0), 0.0, "no steep ground near")
	assert_eq(TerrainRules.scree_from(0.2, 0.2, 0.0, 1.0, 1.0), 0.0, "convex")


func test_weights_skip_only_where_the_noise_cannot_reach() -> void:
	# The shortcut in weights() must never change a result: compare with the full formulas.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for _i in 300:
		var ny := rng.randf_range(0.2, 1.0)
		var fields := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.3))
		var xz := Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
		var y := rng.randf_range(-2.0, 4.0)
		var got := TerrainRules.weights(ny, fields, xz, y, 77)
		var cliff := TerrainRules.cliff_from(
			ny, fields.x, TerrainRules.rule_noise(xz, y, TerrainRules.CLIFF_NOISE_OFFSET, 77)
		)
		var scree := TerrainRules.scree_from(
			fields.x,
			fields.y,
			cliff,
			TerrainRules.rule_noise(xz, y, TerrainRules.SCREE_NOISE_OFFSET, 77),
			TerrainRules.scree_breakup(xz, 77)
		)
		# Vector2 holds single precision.
		assert_almost_eq(got.x, cliff, 1e-6)
		assert_almost_eq(got.y, scree, 1e-6)


func test_value_noise_is_smooth_bounded_and_seeded() -> void:
	var a := TerrainRules.value_noise(Vector2(3.3, -7.1), 1)
	assert_between(a, 0.0, 1.0)
	assert_eq(TerrainRules.value_noise(Vector2(3.3, -7.1), 1), a, "deterministic")
	assert_ne(TerrainRules.value_noise(Vector2(3.3, -7.1), 2), a, "seeded")
	# Continuous across a lattice line.
	var left := TerrainRules.value_noise(Vector2(4.0 - 1e-6, 0.5), 1)
	var right := TerrainRules.value_noise(Vector2(4.0, 0.5), 1)
	assert_almost_eq(left, right, 1e-4)
	# 32-bit wrap: a seed near the int32 limit and negative lattice cells stay in range.
	assert_between(TerrainRules.value_noise(Vector2(-1234.5, 987.25), 0x7FFFFFFF), 0.0, 1.0)
	# Every lattice hash is an unsigned 32-bit value (a Vector2i return wrapped half of them
	# negative, so the noise left [0, 1] like the shader's uint never does).
	var low := 1.0
	var high := 0.0
	for k in 400:
		var n := TerrainRules.value_noise(Vector2(k * 0.37 - 70.0, k * 0.61 - 120.0), 21)
		low = minf(low, n)
		high = maxf(high, n)
	assert_true(low >= 0.0 and high <= 1.0, "noise within [0, 1]: %f .. %f" % [low, high])
	assert_lt(low, 0.2, "and it spans the range")
	assert_gt(high, 0.8)


func test_rule_noise_at_height_zero_is_the_plain_2d_noise() -> void:
	# Flat ground at height 0 keeps the rule noise it had before the noise went 3D, bit for
	# bit: the two-octave value noise of xz alone.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var offset := TerrainRules.SCREE_NOISE_OFFSET
	for _i in 200:
		var xz := Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
		var p := xz / TerrainRules.RULE_NOISE_SCALE_M + offset
		var plain := (
			TerrainRules.value_noise(p, 77) * 0.65
			+ TerrainRules.value_noise(p * 2.3 + Vector2(5.2, -1.7), 77) * 0.35
		)
		assert_eq(TerrainRules.rule_noise(xz, 0.0, offset, 77), plain, "at %s" % xz)


func test_rule_noise_is_continuous_and_bounded_across_layers() -> void:
	var xz := Vector2(3.7, -8.2)
	var offset := TerrainRules.CLIFF_NOISE_OFFSET
	var layer_m := TerrainRules.RULE_NOISE_SCALE_M
	for k in [-2, 1, 3]:
		var below := TerrainRules.rule_noise(xz, k * layer_m - 1e-6, offset, 77)
		var at := TerrainRules.rule_noise(xz, k * layer_m, offset, 77)
		assert_almost_eq(below, at, 1e-4, "layer %d" % k)
	var low := 1.0
	var high := 0.0
	for k in 600:
		var n := TerrainRules.rule_noise(Vector2(k * 0.31, -k * 0.17), k * 0.023 - 5.0, offset, 9)
		low = minf(low, n)
		high = maxf(high, n)
	assert_true(low >= 0.0 and high <= 1.0, "within [0, 1]: %f .. %f" % [low, high])
	assert_lt(low, 0.25, "and it spans the range")
	assert_gt(high, 0.75)


func test_rule_noise_patches_are_round_on_faces_of_every_facing() -> void:
	# The rule noise's structure tensor over a 50 degree face, in face coordinates (down the
	# dip, along the strike): sqrt(largest / smallest eigenvalue) is the patch elongation,
	# 1 for round patches. The height-sheared 2D domain it replaced measured about 130 on a
	# face turned to +X (its two map axes fold into one near 51 degrees) and 1.8 to -X.
	var slope := deg_to_rad(50.0)
	var elongation := {}
	for facing: float in [0.0, 90.0, 180.0, 270.0, 45.0]:
		var phi := deg_to_rad(facing)
		var dip := Vector3(cos(slope) * cos(phi), -sin(slope), cos(slope) * sin(phi))
		var strike := Vector3(-sin(phi), 0.0, cos(phi))
		elongation[facing] = _face_elongation(dip, strike)
		assert_lt(elongation[facing], 1.2, "face turned %d degrees" % facing)
	assert_almost_eq(elongation[0.0], elongation[270.0], 0.15, "+X like -Z")
	assert_almost_eq(elongation[0.0], elongation[180.0], 0.15, "+X like -X")


## Patch elongation of the cliff rule noise over a 30 m square of the plane through
## (2, 4, -3) spanned by unit vectors `dip` and `strike` (see the test above).
func _face_elongation(dip: Vector3, strike: Vector3) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var offset := TerrainRules.CLIFF_NOISE_OFFSET
	var h := 0.02
	var g := Vector3.ZERO
	for _i in 400:
		var p := Vector3(2.0, 4.0, -3.0)
		p += dip * rng.randf_range(-15.0, 15.0) + strike * rng.randf_range(-15.0, 15.0)
		var c := _rule_at(p, offset)
		var a := (_rule_at(p + dip * h, offset) - c) / h
		var b := (_rule_at(p + strike * h, offset) - c) / h
		g += Vector3(a * a, b * b, a * b)
	var half_trace := (g.x + g.y) * 0.5
	var spread := sqrt(maxf(half_trace * half_trace - (g.x * g.y - g.z * g.z), 0.0))
	return sqrt((half_trace + spread) / maxf(half_trace - spread, 1e-9))


func _rule_at(p: Vector3, offset: Vector2) -> float:
	return TerrainRules.rule_noise(Vector2(p.x, p.z), p.y, offset, 77)


func _step_grid(columns: int, rows: int, at: int, height: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(columns * rows)
	for z in rows:
		for x in range(at, columns):
			heights[z * columns + x] = height
	return heights


## Brute-force twin of TerrainRules.sample_fields for one sample.
func _brute_fields(heights: PackedFloat32Array, columns: int, rows: int, x: int, z: int) -> Vector2:
	var r := TerrainRules.radius_samples(STEP.x)
	var sum_h := 0.0
	var sum_t := 0.0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var sx := clampi(x + dx, 0, columns - 1)
			var sz := clampi(z + dz, 0, rows - 1)
			sum_h += heights[sz * columns + sx]
			var n := ScatterGenerator.vertex_normal(heights, columns, rows, sx, sz, STEP)
			sum_t += TerrainRules.slope_tail(n.y)
	var area := float((2 * r + 1) * (2 * r + 1))
	var ny := ScatterGenerator.vertex_normal(heights, columns, rows, x, z, STEP).y
	return Vector2((heights[z * columns + x] - sum_h / area) * ny, sum_t / area)


func test_fields_match_a_brute_force_box_mean_and_hand_values() -> void:
	var columns := 30
	var rows := 30
	var heights := _step_grid(columns, rows, 15, 1.524)
	var all := TerrainRules.sample_fields(heights, columns, rows, STEP, Rect2i(0, 0, columns, rows))
	var curvature := PackedFloat32Array()
	var steep := PackedFloat32Array()
	curvature.resize(columns * rows)
	steep.resize(columns * rows)
	TerrainRules.store_fields(all, columns, curvature, steep)
	var worst := 0.0
	for z in [0, 3, 15, 29]:
		for x in range(0, columns):
			var expected := _brute_fields(heights, columns, rows, x, z)
			var i: int = z * columns + x
			worst = maxf(worst, maxf(absf(curvature[i] - expected.x), absf(steep[i] - expected.y)))
	assert_lt(worst, 1e-5, "sliding sums match the brute-force box mean, edges clamped")
	# Hand values (radius 6 samples, 13 x 13 box), row 15, far from the grid's top and bottom:
	# the foot sample x = 14 sees 6 high columns of 13 (mean 0.703385) and has n.y 0.311735.
	assert_almost_eq(curvature[15 * columns + 14], -0.219270, EPS, "the foot is concave")
	assert_gt(curvature[15 * columns + 15], 0.0, "the lip is convex")
	# x = 10: 2 high columns of 13 (mean 0.234462), flat itself (n.y 1); the two face
	# columns (14, 15) are fully steep, so 2 / 13 of its box.
	assert_almost_eq(curvature[15 * columns + 10], -0.234462, EPS)
	assert_almost_eq(steep[15 * columns + 10], 2.0 / 13.0, EPS)
	assert_eq(steep[15 * columns + 2], 0.0, "nothing steep within reach")
	# A sub-rectangle computes the same values as the whole grid.
	var part := TerrainRules.sample_fields(heights, columns, rows, STEP, Rect2i(9, 12, 8, 5))
	var matches := true
	for oz in 5:
		for ox in 8:
			var i := (12 + oz) * columns + 9 + ox
			matches = matches and is_equal_approx(part.curvature[oz * 8 + ox], curvature[i])
			matches = matches and is_equal_approx(part.steep[oz * 8 + ox], steep[i])
	assert_true(matches, "region-independent")


func test_flat_and_planar_ground_have_no_curvature() -> void:
	var columns := 25
	var rows := 25
	var heights := PackedFloat32Array()
	heights.resize(columns * rows)
	for z in rows:
		for x in columns:
			heights[z * columns + x] = 0.1 * x
	var fields := TerrainRules.sample_fields(heights, columns, rows, STEP, Rect2i(8, 8, 9, 9))
	for value in fields.curvature:
		assert_almost_eq(value, 0.0, 1e-5)
	for value in fields.steep:
		assert_eq(value, 0.0, "a 22 degree plane is not steep")


func test_field_at_interpolates_on_the_terrain_triangles() -> void:
	var columns := 3
	var rows := 3
	var curvature := PackedFloat32Array([0, 1, 2, 3, 4, 5, 6, 7, 8])
	var steep := PackedFloat32Array([8, 7, 6, 5, 4, 3, 2, 1, 0])
	assert_eq(TerrainRules.field_at(curvature, steep, columns, rows, Vector2(1, 1)), Vector2(4, 4))
	# Lower triangle (a, a+1, a+cols) of quad (0, 0): (0.25, 0.25) -> 0 * 0.5 + 1 * 0.25 + 3 * 0.25.
	var low := TerrainRules.field_at(curvature, steep, columns, rows, Vector2(0.25, 0.25))
	assert_almost_eq(low.x, 1.0, EPS)
	# Upper triangle (a+1, a+cols+1, a+cols): (0.75, 0.75) -> 4 * 0.5 + 3 * 0.25 + 1 * 0.25.
	var high := TerrainRules.field_at(curvature, steep, columns, rows, Vector2(0.75, 0.75))
	assert_almost_eq(high.x, 3.0, EPS)
	assert_almost_eq(high.y, 5.0, EPS)


## `const float NAME = value;` and `const vec2 NAME = vec2(a, b);` lines of the shader.
func _shader_constants() -> Dictionary:
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	var found := {}
	var regex := RegEx.new()
	regex.compile("const\\s+(float|vec2)\\s+(\\w+)\\s*=\\s*([^;]+);")
	for m in regex.search_all(text):
		var value := m.get_string(3).strip_edges()
		if m.get_string(1) == "vec2":
			var inner := value.trim_prefix("vec2(").trim_suffix(")").split(",")
			found[m.get_string(2)] = Vector2(float(inner[0]), float(inner[1]))
		else:
			found[m.get_string(2)] = float(value)
	return found


func test_shader_constants_mirror_the_rules() -> void:
	var shader := _shader_constants()
	var rules: Dictionary = TerrainRules.new().get_script().get_script_constant_map()
	for constant_name in MIRRORED:
		assert_true(rules.has(constant_name), "%s in TerrainRules" % constant_name)
		assert_true(shader.has(constant_name), "%s in the shader" % constant_name)
		if not rules.has(constant_name) or not shader.has(constant_name):
			continue
		var cpu: Variant = rules[constant_name]
		if cpu is Vector2:
			assert_true(
				(shader[constant_name] as Vector2).is_equal_approx(cpu),
				"%s: %s vs %s" % [constant_name, shader[constant_name], cpu]
			)
		else:
			assert_almost_eq(float(shader[constant_name]), float(cpu), 1e-6, constant_name)
	assert_almost_eq(shader.get("CLIFF_START_COS", 0.0), TerrainRules.cliff_start_cos(), 1e-6)
	assert_almost_eq(shader.get("CLIFF_END_COS", 0.0), TerrainRules.cliff_end_cos(), 1e-6)
	assert_almost_eq(shader.get("WATER_DEPTH_SCALE", 0.0), WaterDressing.DEPTH_SCALE, 1e-6)


## A slope normal `deg` degrees from horizontal, facing `azimuth_deg` from +X toward +Z.
func _slope_normal(deg: float, azimuth_deg: float) -> Vector3:
	var t := deg_to_rad(deg)
	var a := deg_to_rad(azimuth_deg)
	return Vector3(sin(t) * cos(a), cos(t), sin(t) * sin(a))


## The slope projection weights (slopesmear): a partition of unity everywhere; exactly
## top-down on gentle ground in every facing, so flat ground draws as before and skips the
## side code; the least stretched projection (1 / |n . axis|) leads on every slope.
func test_projection_weights_partition_and_lead() -> void:
	for deg in range(0, 91, 3):
		for azimuth in range(0, 360, 15):
			var n := _slope_normal(float(deg), float(azimuth))
			var w := TerrainRules.projection_weights(n)
			assert_almost_eq(w.x + w.y + w.z, 1.0, 1e-5, "sum at %d / %d" % [deg, azimuth])
			assert_true(w.x >= 0.0 and w.y >= 0.0 and w.z >= 0.0, "non-negative")
			var dots := Vector3(absf(n.x), absf(n.y), absf(n.z))
			var lead := 0 if dots.x >= maxf(dots.y, dots.z) else (1 if dots.y >= dots.z else 2)
			var heavy := 0 if w.x >= maxf(w.y, w.z) else (1 if w.y >= w.z else 2)
			if dots[lead] - dots[(lead + 1) % 3] > 0.02 and dots[lead] - dots[(lead + 2) % 3] > 0.02:
				assert_eq(heavy, lead, "least stretched leads at %d / %d" % [deg, azimuth])
			if deg <= 33:
				assert_eq(w, Vector3(0.0, 1.0, 0.0), "top-down alone at %d / %d" % [deg, azimuth])


## The crossover a face turned to X or Z meets at 45 degrees (top and side equally stretched,
## 1.41) shares the weight evenly; at 50 degrees (the valley wall) the side plane leads.
func test_projection_weights_crossover() -> void:
	var w45 := TerrainRules.projection_weights(_slope_normal(45.0, 0.0))
	assert_almost_eq(w45.x, w45.y, 1e-5)
	assert_eq(w45.z, 0.0)
	var w50 := TerrainRules.projection_weights(_slope_normal(50.0, 180.0))
	assert_gt(w50.x, 0.7)
	assert_eq(TerrainRules.projection_weights(Vector3.UP), Vector3(0.0, 1.0, 0.0))


## The cliff-face and water rules are written the same way in the shader as in
## compose_water(): painted ground and built weight scaled by 1 - PAINT_CLIFF_YIELD * rule.x
## and 1 - the ford (PAINT_WATER_YIELD * bed, faded in with the depth: paths yield at faces
## and in deeper water), painted rock held, the yielded parts added to the rock and the bed,
## scree and shore over the unpainted ground only. Each line below is compose_water()'s,
## word for word.
func test_shader_composes_paint_like_compose_water() -> void:
	var text := FileAccess.get_file_as_string(SHADER_PATH).replace(" ", "")
	var cpu := (
		FileAccess
		. get_file_as_string("res://utils/terrain_rules.gd")
		. replace(" ", "")
		. replace(":=", "=")
	)
	for line in [
		"cliff_scale=1.0-PAINT_CLIFF_YIELD*rule.x",
		"fording=smoothstep(PAINT_FORD_START_M,PAINT_FORD_END_M,water_depth)",
		"ford=PAINT_WATER_YIELD*water.x*fording",
		"paint_scale=cliff_scale*(1.0-ford)",
		"cliff=unpainted*rule.x+yielding*(1.0-cliff_scale)",
		"dry=1.0-water.x",
		"bed=water.x*unpainted*(1.0-rule.x)+yielding*cliff_scale*ford",
		"scree=unpainted*rule.y*dry",
		"shore=unpainted*(1.0-rule.x-rule.y)*dry*water.y",
		"keep=unpainted*(1.0-rule.x-rule.y)*dry*(1.0-water.y)",
	]:
		assert_true(text.contains("float" + line + ";"), "the shader has: %s" % line)
		assert_true(cpu.contains(line), "compose_water has: %s" % line)
	assert_true(text.contains("vec4cw=held_w+(pw-held_w)*paint_scale;"), "per candidate")
