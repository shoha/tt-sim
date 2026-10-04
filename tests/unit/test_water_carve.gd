extends GutTest

## Carving water (phase 4, P4-3): the channel cross-section per depth class (shore and bank
## slopes, the bed, never raising ground, no bank steep enough to turn to rock), reach steps
## shaped as a crest and a riffle with the upper reach's water stopping at the crest, the
## pond basin, the wet dressing field, the rock policy, and the editor's carve, pond and
## erase: one history entry each, undo and redo exact, an erase leaving the ground carved.
## Waterfalls (phase 4c, P4c-2): the fall profile, a hillside face that reads as rock across
## the channel, the plunge pool, a tier crossing that leaves the tier's face outside the
## notch, and diagonal faces that do not saw.

const BIOME := "temperate_forest_summer_s1"
## Ground shapes (the tier band, the ramp) and the carve, shared with the falls tests.
const Fixtures := preload("res://tests/unit/water_fixtures.gd")

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


## Lets the water surface's worker land (AuthoredWater.refresh_map).
func _settle(editor: AuthoringEditor) -> void:
	editor.finish_height_work()
	var water := _map.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	if water != null:
		water.finish_refresh()


## A straight river along X at z = 0 with half-width `half`.
func _straight(doc: MapDocument, depth: WaterBody.Depth, half: float = 2.0) -> Array[WaterBody]:
	return WaterEdit.plan_river(
		doc,
		PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)]),
		PackedFloat32Array([half, half]),
		depth
	)


func _height(doc: MapDocument, p: Vector2) -> float:
	return WaterGeometry.ground_at(doc, p)


# --- cross-section -----------------------------------------------------------------------


func test_cross_section_per_depth_class() -> void:
	for depth in [WaterBody.Depth.ANKLE, WaterBody.Depth.WAIST, WaterBody.Depth.DEEP]:
		var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
		# A valley rising 1:1 to 3 m on either side, so the banks are cut to their slope.
		Fixtures.shape(doc, func(p: Vector2) -> float: return minf(absf(p.y), 3.0))
		var start := doc.heights.duplicate()
		var bodies := _straight(doc, depth)
		assert_eq(bodies.size(), 1, "flat along its line: one reach")
		var level := bodies[0].level_m
		assert_almost_eq(level, -WaterGeometry.FREEBOARD_M, 1e-4)
		Fixtures.carve(doc, WaterCarve.river_goals(doc, bodies, start))
		var d := WaterBody.depth_for(depth)
		var name := WaterBody.DEPTH_NAMES[depth]
		var hw := bodies[0].half_widths[0]
		assert_almost_eq(hw, maxf(2.0, WaterCarve.min_half_width(depth)), 1e-4, "%s: width" % name)
		assert_almost_eq(_height(doc, Vector2(0, 0)), level - d, 0.03, "%s: bed depth" % name)
		assert_almost_eq(_height(doc, Vector2(0, hw)), level, 0.08, "%s: waterline" % name)
		# The shore under the water is soft for wading water, steeper for deep (and for a
		# channel too narrow to reach its bed at the class's slope).
		var shore := (_height(doc, Vector2(0, hw - 0.1)) - _height(doc, Vector2(0, hw - 0.4))) / 0.3
		var expected := clampf(
			d / (hw * (1.0 - WaterCarve.BED_SHARE)),
			WaterCarve.SHORE_SLOPE[depth],
			WaterCarve.MAX_SHORE_SLOPE
		)
		assert_almost_eq(shore, expected, 0.1, "%s: shore slope" % name)
		# The bank's slope away from the water, then no steeper than the cliff rule starts.
		var bank := (_height(doc, Vector2(0, hw + 1.0)) - _height(doc, Vector2(0, hw + 0.5))) / 0.5
		assert_almost_eq(bank, WaterCarve.BANK_SLOPE[depth], 0.06, "%s: bank slope" % name)
		var steepest := 0.0
		for k in 60:
			var z := k * 0.1
			var rise := absf(_height(doc, Vector2(0, z + 0.1)) - _height(doc, Vector2(0, z)))
			steepest = maxf(steepest, rise / 0.1)
		assert_lt(steepest, tan(deg_to_rad(TerrainRules.CLIFF_START_DEG)), "%s: no rock" % name)
		for i in doc.sample_count():
			assert_true(doc.heights[i] <= start[i] + 1e-6, "%s never raises ground" % name)
			if doc.heights[i] > start[i] + 1e-6:
				break


func test_narrow_channels_widen_to_reach_their_depth() -> void:
	var start := _doc.heights.duplicate()
	var bodies := _straight(_doc, WaterBody.Depth.DEEP, 0.8)
	var narrowest := WaterCarve.min_half_width(WaterBody.Depth.DEEP)
	assert_almost_eq(bodies[0].half_widths[0], narrowest, 1e-4, "widened")
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	var bed := bodies[0].level_m - WaterBody.depth_for(WaterBody.Depth.DEEP)
	assert_almost_eq(_height(_doc, Vector2(0, 0)), bed, 0.06, "a deep river is deep")
	var shore := _height(_doc, Vector2(0, narrowest - 0.2)) - _height(_doc, Vector2(0, 1.0))
	shore /= narrowest - 1.2
	assert_lt(shore, WaterCarve.MAX_SHORE_SLOPE + 0.02, "and its shore is no rock face")


func test_carve_never_raises_uneven_ground() -> void:
	# Noisy ground under a flat stroke, and the same noise over a 35 degree ramp under a
	# stroke that falls twice (P4c-2: the fall profile and the plunge pool are cuts too).
	for falling in [false, true]:
		var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
		var shape_of := func(p: Vector2) -> float:
			var h := sin(p.x * 0.7) * 0.4 + cos(p.y * 1.3) * 0.3
			if falling:
				h += clampf(7.0 - 0.7 * (p.x + 5.0), 0.0, 7.0)
			return h
		Fixtures.shape(doc, shape_of)
		var start := doc.heights.duplicate()
		var bodies := _straight(doc, WaterBody.Depth.WAIST)
		if falling:
			assert_gt(WaterFalls.fall_flags(bodies).count(1), 0, "a stroke with falls")
		var goals := WaterCarve.river_goals(doc, bodies, start)
		var rect: Rect2i = goals.rect
		var raised := 0
		for j in rect.size.y:
			for i in rect.size.x:
				var goal: float = goals.goals[j * rect.size.x + i]
				var at := (rect.position.y + j) * doc.samples_x() + rect.position.x + i
				if not is_inf(goal) and goal > start[at]:
					raised += 1
		assert_eq(raised, 0, "falling %s: no goal above the ground" % str(falling))
		Fixtures.carve(doc, goals)
		for i in doc.sample_count():
			if doc.heights[i] > start[i] + 1e-6:
				fail_test("falling %s: sample %d raised" % [str(falling), i])
				break


# --- reach steps ---------------------------------------------------------------------------


func test_reach_steps_are_a_crest_and_a_riffle() -> void:
	# Ground falling 0.12 m per metre along the river: several flat reaches.
	Fixtures.shape(_doc, func(p: Vector2) -> float: return -0.12 * p.x)
	var start := _doc.heights.duplicate()
	var bodies := _straight(_doc, WaterBody.Depth.WAIST)
	assert_gt(bodies.size(), 2, "the drop splits the stroke into reaches")
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	_doc.water_bodies = bodies
	# At each shared point the ground stands just under the upper level: its pool runs
	# shallow over the crest to the line where its area stops.
	for b in bodies.size() - 1:
		var joint: Vector2 = bodies[b].points[-1]
		assert_almost_eq(bodies[b + 1].points[0].distance_to(joint), 0.0, 1e-6)
		var crest := _height(_doc, joint)
		assert_gt(crest, bodies[b].level_m - 0.1, "crest %d just under the upper water" % b)
		assert_lt(crest, bodies[b].level_m + 0.02, "crest %d" % b)
	# The riffle below each crest carries a sheet of white water between the two levels.
	var sheets := WaterMeshBuilder.cascades(_doc)
	assert_false(sheets.is_empty(), "cascades over the riffles")
	var reach_levels := {}
	for body in bodies:
		reach_levels[snappedf(body.level_m, 1e-4)] = true
	for i: int in sheets:
		var sheet := float(sheets[i])
		# Over its ground, or clamped at a reach's level (buried under a crest there).
		var clamped := reach_levels.has(snappedf(sheet, 1e-4))
		assert_true(sheet > _doc.heights[i] or clamped, "a sheet over its ground")
		assert_lt(sheet, bodies[0].level_m + 1e-4, "and under the top level")
	# Down the centreline the bed never drops faster than a riffle, no vertical lip.
	var worst := 0.0
	for k in 80:
		var x := -10.0 + k * 0.25
		var drop := _height(_doc, Vector2(x, 0)) - _height(_doc, Vector2(x + 0.25, 0))
		worst = maxf(worst, drop / 0.25)
	assert_lt(worst, 2.0 * WaterCarve.RIFFLE_SLOPE, "riffles, not a lip (slope %.2f)" % worst)
	# The upper reach's area stops flush at the shared point: just below it, it is not wet.
	var levels := WaterGeometry.levels(_doc)
	var below: Vector2 = bodies[0].points[-1] + Vector2(1.0, 0)
	var s := _doc.world_to_sample(below).round()
	var level := levels[_doc.sample_index(int(s.x), int(s.y))]
	assert_lt(level, bodies[0].level_m - 0.01, "the upper water does not reach past its crest")


func test_a_riffle_sheet_meets_its_banks_on_a_smooth_line() -> void:
	# A river at 29 degrees to the sample grid over ground falling along it. Where the riffle's
	# sheet meets a bank (the mesh's triangles are the ground's, so the waterline is where the
	# two interpolated heights cross) it must follow the carve's waterline, not the grid's
	# staircase: cut off at the half-width, it drew 0.25 m teeth (P4-5).
	var dir := Vector2(11, 6).normalized()
	Fixtures.shape(_doc, func(p: Vector2) -> float: return -0.12 * p.dot(dir))
	var start := _doc.heights.duplicate()
	var half := 1.6
	var bodies := WaterEdit.plan_river(
		_doc,
		PackedVector2Array([Vector2(-11, -6), Vector2(11, 6)]),
		PackedFloat32Array([half, half]),
		WaterBody.Depth.WAIST
	)
	assert_gt(bodies.size(), 1, "reaches")
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	_doc.water_bodies = bodies
	var buried := {}
	var sheets := WaterMeshBuilder.cascades(_doc, buried)
	assert_false(buried.is_empty(), "the sheet sinks under the banks past the waterline")
	# The surface's height per sample as the mesh draws a sheet cell.
	var columns := _doc.samples_x()
	var rows := _doc.samples_z()
	var water := PackedFloat32Array()
	water.resize(_doc.sample_count())
	for i in water.size():
		water[i] = _doc.heights[i] - WaterMeshBuilder.CASCADE_TUCK_M
	for i: int in buried:
		water[i] = buried[i]
	var built := WaterMeshBuilder.build(_doc)
	for i in water.size():
		if built.wet[i] == 1:
			water[i] = built.levels[i]
	for i: int in sheets:
		water[i] = sheets[i]
	var joint: Vector2 = bodies[0].points[-1]
	var length := WaterCarve.riffle_length(
		bodies[0].level_m, bodies[1].level_m, bodies[1].depth_m()
	)
	var across := dir.orthogonal()
	# The edge's distance from the course every 5 cm down the riffle (past the crest, where
	# the edge curves out from the upper pool's), each side: a smooth line moves by a few
	# millimetres between neighbours, a staircase jumps by a good part of a sample (9.5 cm
	# with the sheet cut off at the waterline).
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var found := 0
	for side in [1.0, -1.0]:
		var previous := NAN
		var along := 0.8
		while along < length * 0.7:
			var s := half - 1.2
			var edge := NAN
			while s < half + 0.6:
				var p: Vector2 = joint + dir * along + across * s * side
				var at := _doc.world_to_sample(p)
				var w := ScatterGenerator.triangle_height(water, columns, rows, at)
				var g := ScatterGenerator.triangle_height(_doc.heights, columns, rows, at)
				if w <= g:
					edge = s
					found += 1
					break
				s += 0.005
			if not is_nan(edge) and not is_nan(previous) and absf(edge - previous) > worst:
				worst = absf(edge - previous)
				worst_at = Vector2(along, side)
			previous = edge
			along += 0.05
	assert_gt(found, 60, "the sheet's edge found along the riffle")
	assert_lt(worst, 0.03, "a smooth edge (worst step %.3f m at %s)" % [worst, worst_at])


func test_flush_ends_only_where_a_reach_continues() -> void:
	var widths := PackedFloat32Array([1.0, 1.0])
	var ankle := WaterBody.Depth.ANKLE
	var a := WaterBody.river(
		1, PackedVector2Array([Vector2(0, 0), Vector2(4, 0)]), widths, ankle, 0.0
	)
	var b := WaterBody.river(
		2, PackedVector2Array([Vector2(4, 0), Vector2(8, 0)]), widths, ankle, -0.5
	)
	var bodies: Array[WaterBody] = [a, b]
	assert_eq(WaterGeometry.flush_ends(bodies, a), Vector2i(0, 1))
	assert_eq(WaterGeometry.flush_ends(bodies, b), Vector2i(1, 0))
	var alone: Array[WaterBody] = [a]
	assert_eq(WaterGeometry.flush_ends(alone, a), Vector2i.ZERO)


# --- falls (phase 4c, P4c-2) -----------------------------------------------------------------


## The falls of one stroke's reaches `bodies`: the index k of every step (bodies[k] into
## bodies[k + 1]) that WaterFalls.fall_flags marks as a fall, in order.
func _fall_steps(bodies: Array[WaterBody]) -> Array[int]:
	var out: Array[int] = []
	var flags := WaterFalls.fall_flags(bodies)
	for k in flags.size():
		if flags[k] != 0:
			out.append(k)
	return out


## The lips of those falls: the shared point below each.
func _fall_lips(bodies: Array[WaterBody]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in _fall_steps(bodies):
		out.append(bodies[k + 1].points[0])
	return out


## How far past its lip the face of the fall from `upper` into `lower` runs before the bank
## level has reached the lower level (WaterCarve.fall_shape): the part of the cut that is
## face across its whole width, above the plunge pool.
func _face_length(upper: WaterBody, lower: WaterBody) -> float:
	var x := 0.0
	while x < 10.0:
		var shaped := WaterCarve.fall_shape(x, upper.level_m, lower.level_m, lower.depth_m())
		if shaped.x <= lower.level_m + 1e-4:
			return x
		x += 0.01
	return x


func test_fall_profile_is_the_tier_face_with_a_harder_lip() -> void:
	var drop := 1.524
	var run := WaterCarve.fall_run(drop)
	assert_eq(WaterCarve.fall_profile(0.0, drop), 0.0, "nothing lost at the lip")
	assert_eq(WaterCarve.fall_profile(-1.0, drop), 0.0, "nor above it")
	assert_almost_eq(WaterCarve.fall_profile(run, drop), drop, 1e-6, "the whole drop at the foot")
	assert_almost_eq(WaterCarve.fall_profile(run + 2.0, drop), drop, 1e-6, "and beyond it")
	assert_lt(run, HeightBrush.tier_span(drop), "a harder lip: the face stands nearer the lip")
	assert_lt(
		WaterCarve.fall_profile(HeightBrush.TIER_SOFTEN_M, drop),
		WaterCarve.FALL_LIP_M,
		"the brink holds up to where the sharp lip begins"
	)
	# Monotonic and smooth (no kink between neighbouring 1 cm slopes), the face at the tier
	# angle after the tent (test_tier_goal_raises_a_face_a_rounded_lip_then_a_flat_top).
	var last := 0.0
	var last_slope := 0.0
	var steepest := 0.0
	var step := 0.01
	for i in range(1, int(run / step) + 10):
		var x := i * step
		var d := WaterCarve.fall_profile(x, drop)
		assert_true(d >= last - 1e-9, "never rises again at %.2f m" % x)
		var slope := (d - last) / step
		assert_lt(absf(slope - last_slope), 0.2, "no kink at %.2f m" % x)
		steepest = maxf(steepest, slope)
		last = d
		last_slope = slope
	assert_between(rad_to_deg(atan(steepest)), 62.0, 70.0, "a steep face")
	# The step shape of a fall is the full crest whatever the depth; a small step keeps its bar.
	var full := WaterCarve.step_shape(0.0, -0.8, 2.0, true)
	assert_almost_eq(full.x, WaterCarve.CREST_M, 1e-6, "a fall's crest is the full one")
	var small := WaterCarve.step_shape(0.0, -0.1, 2.0)
	assert_lt(small.x, -0.5, "a small step in deep water is a low bar")


func test_fall_walls_steepen_down_the_face_and_relax_past_the_pool() -> void:
	# The side-wall rule (P4c-2b, bed_line's gorge share): 0 along a flat reach, rising over the
	# pool tail to 1 at the lip, 1 down the face to the carved foot, back to 0 over the plunge
	# length; a riffle step never has it. At 1 the bank rises at FALL_BANK_SLOPE and the cut
	# reaches FALL_BANK_REACH_M; at 0 section() and blend_with_ground() are exactly the
	# ordinary ones (the riffle carve is byte-identical).
	var depth := WaterBody.depth_for(WaterBody.Depth.ANKLE)
	var drop := 3.0
	var bounds := PackedFloat32Array([10.0])
	var levels := PackedFloat32Array([drop, 0.0])
	var taper := Vector2i.ZERO
	var fall := PackedByteArray([1])
	var riffle := PackedByteArray([0])
	var tail := WaterCarve.step_shape(drop, 0.0, depth, true).y
	var foot := WaterCarve.fall_foot(drop, depth)
	var length := WaterFalls.plunge_length(drop)
	var at := func(s: float, flags: PackedByteArray) -> float:
		return WaterCarve.bed_line(s, bounds, levels, depth, 20.0, taper, flags).z
	assert_eq(at.call(10.0 - tail - 0.5, fall), 0.0, "the flat reach above the pool tail")
	assert_between(at.call(10.0 - tail * 0.5, fall), 0.3, 0.7, "rising over the pool tail")
	assert_almost_eq(at.call(10.0, fall), 1.0, 1e-6, "at the lip")
	assert_almost_eq(at.call(10.0 + foot * 0.5, fall), 1.0, 1e-6, "down the face")
	assert_almost_eq(at.call(10.0 + foot, fall), 1.0, 1e-6, "at the foot")
	assert_between(at.call(10.0 + foot + length * 0.5, fall), 0.3, 0.7, "fading over the pool")
	assert_eq(at.call(10.0 + foot + length + 0.1, fall), 0.0, "the pool's ordinary banks")
	assert_almost_eq(WaterCarve.fall_gorge(foot + length * 0.5, drop, depth), 0.5, 1e-6)
	for s in [2.0, 10.0 - tail * 0.5, 10.0, 11.0, 14.0]:
		assert_eq(at.call(s, riffle), 0.0, "a riffle at %.1f m" % s)
	var level := 0.0
	var bed := level - depth
	var ankle := WaterBody.Depth.ANKLE
	assert_eq(
		WaterCarve.section(1.0, level, bed, ankle, 0.55, 0.0),
		WaterCarve.section(1.0, level, bed, ankle, 0.55),
		"no gorge: the ordinary section"
	)
	var steep := WaterCarve.section(2.0, level, bed, ankle, 0.55, 1.0)
	var ordinary := WaterCarve.section(2.0, level, bed, ankle, 0.55)
	assert_almost_eq(steep - WaterCarve.section(1.0, level, bed, ankle, 0.55, 1.0), 1.4, 1e-6)
	assert_almost_eq(steep, level + 2.0 * WaterCarve.FALL_BANK_SLOPE, 1e-6, "the gorge wall")
	assert_almost_eq(ordinary, level + 2.0 * WaterCarve.BANK_SLOPE[ankle], 1e-6, "the bank")
	assert_eq(
		WaterCarve.blend_with_ground(-1.0, 0.0, 5.0, 0.0),
		WaterCarve.blend_with_ground(-1.0, 0.0, 5.0),
		"no gorge: the ordinary reach"
	)
	assert_lt(WaterCarve.blend_with_ground(-1.0, 0.0, 5.0), 0.0, "cut at 5 m from the bank")
	assert_eq(WaterCarve.blend_with_ground(-1.0, 0.0, 5.0, 1.0), 0.0, "not from a gorge")
	assert_lt(
		WaterCarve.blend_with_ground(-1.0, 0.0, WaterCarve.FALL_BANK_REACH_M - 0.5, 1.0),
		0.0,
		"the gorge's cut fades out at its own reach"
	)


func test_hillside_fall_face_is_rock_across_the_channel() -> void:
	# A 35 degree ramp (no rock by the cliff rule) with a waist river down it: two falls
	# (test_water_falls). Before the carve the ground has no cliff-steep face, so the runtime
	# rule sees none; after it every fall's face is full rock across the channel by the shading
	# normals, as test_tier_face_is_rock_at_the_default_spacing reads a tier's, and
	# WaterFalls.falls() sees both.
	Fixtures.ramp(_doc)
	var start := _doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		_doc,
		PackedVector2Array([Vector2(-14, 0), Vector2(14, 0)]),
		PackedFloat32Array([1.5, 1.5]),
		WaterBody.Depth.WAIST
	)
	var lips := _fall_lips(bodies)
	assert_eq(lips.size(), 2, "two falls planned")
	_doc.water_bodies = bodies
	assert_eq(WaterFalls.falls(_doc).size(), 0, "no cliff-steep face before the carve")
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	assert_eq(WaterFalls.falls(_doc).size(), lips.size(), "the carve made the faces")
	var hw := bodies[0].half_widths[0]
	for lip in lips:
		var across := -(hw - 0.4)
		while across <= hw - 0.4 + 1e-6:
			var lowest_ny := 1.0
			var x := 0.5
			while x < 3.0:
				var s := _doc.world_to_sample(Vector2(lip.x + x, across)).round()
				var normal := TerrainMeshBuilder.sample_normal(_doc, int(s.x), int(s.y))
				lowest_ny = minf(lowest_ny, normal.y)
				x += 0.05
			assert_gt(
				TerrainRules.cliff_from(lowest_ny, 0.0, 0.0),
				0.999,
				"full rock below lip %s, %.1f m across" % [str(lip), across]
			)
			across += 0.1


func test_hillside_fall_cuts_a_notch_not_a_quarry() -> void:
	# An ankle stream (half-width 0.55) down the 35 degree ramp: two falls of about 3.5 m. From
	# each lip to the foot of its face the carved ground outside the water reaches no further
	# than two channel widths from the waterline either side (P4c-2b: at the ordinary bank slope
	# the face swept sideways cut a rock wall 8 m wide for this 1.1 m stream), the wall at the
	# foot rises at FALL_BANK_SLOPE, and at the lip itself the shoulders are barely touched.
	Fixtures.ramp(_doc)
	var start := _doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		_doc,
		PackedVector2Array([Vector2(-14, 0), Vector2(14, 0)]),
		PackedFloat32Array([0.55, 0.55]),
		WaterBody.Depth.ANKLE
	)
	var steps := _fall_steps(bodies)
	assert_eq(steps.size(), 2, "two falls")
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	var hw := bodies[0].half_widths[0]
	assert_almost_eq(hw, 0.55, 1e-4, "the stroke's width")
	var channel := 2.0 * hw
	var columns := _doc.samples_x()
	var rows := _doc.samples_z()
	var cut_beyond := func(p: Vector2, side: float) -> float:
		# How far past the waterline on `side` the ground at `p` along the course is carved.
		var farthest := 0.0
		var e := hw
		while e < hw + WaterCarve.BANK_REACH_M:
			var q := _doc.world_to_sample(p + Vector2(0, e * side))
			var was := ScatterGenerator.triangle_height(start, columns, rows, q)
			var now := ScatterGenerator.triangle_height(_doc.heights, columns, rows, q)
			if was - now > 0.02:
				farthest = e - hw
			e += 0.05
		return farthest
	for k in steps:
		var upper := bodies[k]
		var lower := bodies[k + 1]
		var lip: Vector2 = lower.points[0]
		var drop := upper.level_m - lower.level_m
		assert_gt(drop, 3.0, "fall %d: about half the hill" % k)
		var foot := WaterCarve.fall_foot(drop, lower.depth_m())
		var widest := 0.0
		var x := 0.0
		while x <= foot + 1e-6:
			for side in [1.0, -1.0]:
				widest = maxf(widest, cut_beyond.call(lip + Vector2(x, 0), side))
			x += 0.25
		assert_lt(
			widest,
			2.0 * channel,
			(
				"fall %d: the rock outside the water reaches %.2f m (channel %.2f m)"
				% [k, widest, channel]
			)
		)
		assert_gt(widest, 0.5 * channel, "fall %d: a notch is cut (%.2f m)" % [k, widest])
		var shoulder := maxf(cut_beyond.call(lip, 1.0), cut_beyond.call(lip, -1.0))
		assert_lt(shoulder, 0.5, "fall %d: the shoulders at the lip stand (%.2f m)" % [k, shoulder])
		var wall := (
			(
				_height(_doc, lip + Vector2(foot, hw + 0.7))
				- _height(_doc, lip + Vector2(foot, hw + 0.3))
			)
			/ 0.4
		)
		assert_almost_eq(wall, WaterCarve.FALL_BANK_SLOPE, 0.2, "fall %d: the wall at the foot" % k)


func test_plunge_pool_sits_plunge_depth_below_the_bed() -> void:
	# A waist river straight over a tier, 2.5 m wide to the side (wide enough that the narrow
	# channel's steepened shore does not lift the middle of the bed): the crest at the lip, the
	# face down from it, the deepest bed at its foot WaterFalls.plunge_depth() under the lower
	# bed, and the bed back at its depth past the plunge pool.
	Fixtures.tier_band(_doc)
	var start := _doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		_doc,
		PackedVector2Array([Vector2(0, -12), Vector2(0, 12)]),
		PackedFloat32Array([2.5, 2.5]),
		WaterBody.Depth.WAIST
	)
	assert_eq(bodies.size(), 2, "the pool on the top and the pool below")
	assert_eq(WaterFalls.fall_flags(bodies), PackedByteArray([1]))
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	var upper := bodies[0]
	var lower := bodies[1]
	var lip: Vector2 = lower.points[0]
	var depth := lower.depth_m()
	var drop := upper.level_m - lower.level_m
	var plunge := WaterFalls.plunge_depth(drop)
	var crest := upper.level_m + WaterCarve.CREST_M
	assert_almost_eq(_height(_doc, lip), crest, 0.05, "the crest at the lip")
	var deepest := INF
	var deepest_at := 0.0
	var s := 0.0
	while s < 6.0:
		var h := _height(_doc, lip + Vector2(0, s))
		if h < deepest:
			deepest = h
			deepest_at = s
		s += 0.05
	var plunge_bed := lower.level_m - depth - plunge
	assert_almost_eq(deepest, plunge_bed, 0.06, "the plunge bed")
	var foot := WaterCarve.fall_run(crest - plunge_bed)
	assert_almost_eq(deepest_at, foot, 0.4, "deepest at the foot of the face")
	var past := foot + WaterFalls.plunge_length(drop) + 1.0
	assert_almost_eq(_height(_doc, lip + Vector2(0, past)), lower.level_m - depth, 0.06, "the bed")
	var mid := _height(_doc, lip + Vector2(0, foot * 0.5))
	assert_true(mid < crest - 0.2 and mid > plunge_bed + 0.2, "the face between (%.2f)" % mid)


func test_a_tier_crossing_changes_the_face_only_in_the_notch() -> void:
	# Over a Tier cliff the lip is at the brink and the fall profile lies along the tier's own
	# face, so the carve cuts the notch (the channel and its banks) and leaves the face either
	# side as it was.
	Fixtures.tier_band(_doc)
	var before := _doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		_doc,
		PackedVector2Array([Vector2(0, -12), Vector2(0, 12)]),
		PackedFloat32Array([1.0, 1.0]),
		WaterBody.Depth.WAIST
	)
	assert_eq(WaterFalls.fall_flags(bodies), PackedByteArray([1]))
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, before))
	var widest := 0.0
	for w in bodies[1].half_widths:
		widest = maxf(widest, w)
	var notch := widest + WaterGeometry.RIVER_BANK_M
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var cut := 0
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var i := _doc.sample_index(x, z)
			var p := _doc.sample_to_world(Vector2(x, z))
			var change := absf(_doc.heights[i] - before[i])
			if absf(p.x) > notch:
				if change > worst:
					worst = change
					worst_at = p
			elif change > 0.05:
				cut += 1
	assert_lt(
		worst, 0.05, "the face outside the notch stands (worst %.3f m at %s)" % [worst, worst_at]
	)
	assert_gt(cut, 20, "the notch is cut")
	var lip: Vector2 = bodies[1].points[0]
	for across in [-0.8, 0.0, 0.8]:
		assert_almost_eq(
			_height(_doc, lip + Vector2(across, 0)),
			bodies[0].level_m + WaterCarve.CREST_M,
			0.05,
			"the notch's crest across the channel at %.1f" % across
		)


func test_explicit_zero_flags_carve_the_v0_1_29_riffle_over_a_tier() -> void:
	# river_goals with explicit zero flags is the v0.1.29 carve (every step a riffle), used to
	# build fixtures of documents that build made: over a tier the riffle's goal sits above
	# the face, so the face is left standing and no notch or plunge pool is cut, where the
	# derived flags cut the notch (test_a_tier_crossing_changes_the_face_only_in_the_notch).
	Fixtures.tier_band(_doc)
	var before := _doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		_doc,
		PackedVector2Array([Vector2(0, -12), Vector2(0, 12)]),
		PackedFloat32Array([1.0, 1.0]),
		WaterBody.Depth.WAIST
	)
	var zeros := PackedByteArray()
	zeros.resize(bodies.size() - 1)
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, before, zeros))
	# The face: samples standing between the two levels (0.2 m in from each) before the carve.
	var upper := bodies[0].level_m - 0.2
	var lower := bodies[1].level_m + 0.2
	var face_cut_old := 0.0
	for i in _doc.sample_count():
		if before[i] < upper and before[i] > lower:
			face_cut_old = maxf(face_cut_old, before[i] - _doc.heights[i])
	assert_lt(face_cut_old, 0.05, "the face stands under the riffle carve (%.3f m)" % face_cut_old)
	var lip: Vector2 = bodies[1].points[0]
	var foot_x := WaterCarve.fall_foot(bodies[0].level_m - bodies[1].level_m, 0.9)
	var plunge := _height(_doc, lip + Vector2(0, foot_x + 0.5))
	assert_true(plunge >= bodies[1].level_m - 0.9 - 0.06, "no plunge pool (%.2f)" % plunge)
	_doc.heights = before.duplicate()
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, before))
	var face_cut_new := 0.0
	for i in _doc.sample_count():
		if before[i] < upper and before[i] > lower:
			face_cut_new = maxf(face_cut_new, before[i] - _doc.heights[i])
	# The fall profile lies along the tier's own face, so the notch cuts the face itself by
	# decimetres (the plunge bed below the lower level is where it cuts a metre).
	assert_gt(face_cut_new, 0.2, "the derived flags cut the notch (%.2f m)" % face_cut_new)


func test_diagonal_fall_faces_do_not_saw() -> void:
	# The sample grid draws each quad as two triangles on a fixed diagonal; a fall carved across
	# it at any angle must come out straight across its channel (the tier's rule,
	# test_diagonal_tier_faces_do_not_saw). A waist river straight down a 35 degree ramp at each
	# angle: along every line across the channel's flat bed (TOE_SOFT_M in from the waterline's
	# shelf, whose rounding curls the bed up a few centimetres) over the carved face (from
	# where the cut is a full TOP_SOFT_M deep to where the bank level reaches the lower pool;
	# below it the channel's shore shelves to the plunge bed) the drawn height varies by a few
	# centimetres at most. Above that line the face emerges from the hillside in a crease,
	# min(ground, goal), which blend_with_ground rounds over 0.3 m of cut, about a tenth of a
	# metre of run against a 35 degree slope: narrower than a grid cell, so its line is
	# grid-sampled and zigzags by up to 0.14 m off the grid axes (measured; a judgment-set
	# item, not the face's teeth, which this test guards).
	for degrees in [0.0, 10.0, 22.5, 30.0, 45.0, 60.0, -15.0, -30.0, -45.0, -60.0]:
		var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
		var along := Vector2.from_angle(deg_to_rad(degrees))
		var across := along.orthogonal()
		Fixtures.ramp(doc, along)
		var start := doc.heights.duplicate()
		var half := 1.5
		var bodies := WaterEdit.plan_river(
			doc,
			PackedVector2Array([-along * 13.0, along * 13.0]),
			PackedFloat32Array([half, half]),
			WaterBody.Depth.WAIST
		)
		var steps := _fall_steps(bodies)
		assert_gt(steps.size(), 0, "falls at %s deg" % degrees)
		Fixtures.carve(doc, WaterCarve.river_goals(doc, bodies, start))
		var worst := 0.0
		var columns := doc.samples_x()
		var rows := doc.samples_z()
		var measured := 0.0
		for k in steps:
			var lip: Vector2 = bodies[k + 1].points[0]
			var face := _face_length(bodies[k], bodies[k + 1])
			assert_gt(face, 1.0, "a face to check at %s deg" % degrees)
			var offset := 0.0
			var full_cut := INF
			while offset < face:
				var centre := doc.world_to_sample(lip + along * offset)
				var was := ScatterGenerator.triangle_height(start, columns, rows, centre)
				var now := ScatterGenerator.triangle_height(doc.heights, columns, rows, centre)
				if was - now >= WaterCarve.TOP_SOFT_M + 0.05:
					full_cut = minf(full_cut, offset)
				if offset >= full_cut:
					var low := INF
					var high := -INF
					var inset := half - 3.0 * WaterCarve.TOE_SOFT_M
					var t := -inset
					while t <= inset + 1e-6:
						var p := lip + along * offset + across * t
						var h := ScatterGenerator.triangle_height(
							doc.heights, columns, rows, doc.world_to_sample(p)
						)
						low = minf(low, h)
						high = maxf(high, h)
						t += 0.05
					worst = maxf(worst, high - low)
					measured += 0.05
				offset += 0.05
		assert_gt(measured, 1.5, "face measured at %s deg: %.2f m in all" % [degrees, measured])
		assert_lt(worst, 0.08, "fall at %s deg: teeth %.3f m" % [degrees, worst])


# --- ponds -----------------------------------------------------------------------------------


func test_pond_basin_is_a_bowl_with_a_soft_shore() -> void:
	var mask := PackedByteArray()
	mask.resize(_doc.sample_count())
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			if _doc.sample_to_world(Vector2(x, z)).length() < 7.0:
				mask[_doc.sample_index(x, z)] = 3
	_doc.pond_mask = mask
	var level := WaterGeometry.pond_rim_level(_doc, 3)
	var body := WaterBody.pond(3, WaterBody.Depth.WAIST, level)
	var start := _doc.heights.duplicate()
	Fixtures.carve(_doc, WaterCarve.pond_goals(_doc, body, start))
	var d := body.depth_m()
	var centre := _height(_doc, Vector2.ZERO)
	assert_lt(centre, level - d, "deeper than the depth class in the middle")
	assert_gt(centre, level - d * (1.0 + WaterCarve.POND_CENTRE_EXTRA) - 0.05)
	assert_lt(centre, _height(_doc, Vector2(4.5, 0)), "a bowl: shallower toward the shore")
	assert_almost_eq(_height(_doc, Vector2(7.0, 0)), level, 0.1, "the waterline at the rim")
	assert_almost_eq(_height(_doc, Vector2(9.5, 0)), 0.0, 1e-6, "the ground beyond untouched")


# --- dressing --------------------------------------------------------------------------------


func test_dressing_beds_the_water_and_fades_the_shore() -> void:
	assert_true(WaterDressing.refresh(_doc).is_empty(), "no water, no dressing")
	var start := _doc.heights.duplicate()
	var bodies := _straight(_doc, WaterBody.Depth.WAIST)
	Fixtures.carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	_doc.water_bodies = bodies
	var field := WaterDressing.refresh(_doc)
	assert_eq(field.size(), _doc.sample_count() * WaterDressing.CHANNELS)
	assert_eq(_doc.water_dressing, field)
	var at := func(p: Vector2) -> Vector3:
		return WaterDressing.sample(
			field, _doc.samples_x(), _doc.samples_z(), _doc.world_to_sample(p)
		)
	var middle: Vector3 = at.call(Vector2(0, 0))
	assert_almost_eq(middle.x, 1.0, 0.01, "bed under the water")
	assert_almost_eq(middle.z, WaterBody.depth_for(WaterBody.Depth.WAIST) + 0.0, 0.05, "depth")
	var bank: Vector3 = at.call(Vector2(0, 2.8))
	assert_lt(bank.x, 0.05, "no bed on the bank")
	assert_gt(bank.y, 0.5, "the wet shore just above the water")
	var field_side: Vector3 = at.call(Vector2(0, 6.0))
	assert_eq(field_side, Vector3.ZERO, "the biome ground farther out")
	var fading := [
		at.call(Vector2(0, 2.4)).y, at.call(Vector2(0, 3.4)).y, at.call(Vector2(0, 4.4)).y
	]
	assert_true(fading[0] >= fading[1] and fading[1] >= fading[2], "fading out: %s" % str(fading))


func test_compose_water_shares_and_paths_yield_to_the_bed() -> void:
	for yielding in [0.0, 0.4, 1.0]:
		for held in [0.0, 0.3]:
			if yielding + held > 1.0:
				continue
			for rule in [Vector2.ZERO, Vector2(0.5, 0.1)]:
				for water in [Vector2.ZERO, Vector2(0.6, 0.5), Vector2(1.0, 1.0)]:
					for depth in [0.0, 0.2, 1.0]:
						var s := TerrainRules.compose_water(yielding, held, rule, water, depth)
						var total: float = s[0] + s[1] + s[2] + s[4] + s[5] + yielding * s[3] + held
						assert_almost_eq(total, 1.0, 1e-5, "shares add up")
	var under := TerrainRules.compose_water(1.0, 0.0, Vector2.ZERO, Vector2(1.0, 0.0), 0.5)
	assert_almost_eq(under[3], 0.0, 1e-6, "a path under deeper water keeps nothing")
	assert_almost_eq(under[4], 1.0, 1e-6, "the bed shows")
	# P4b-0: at the waterline the path holds (a ford), fading to the bed with the depth.
	var edge := TerrainRules.compose_water(1.0, 0.0, Vector2.ZERO, Vector2(1.0, 0.0), 0.02)
	assert_almost_eq(edge[3], 1.0, 1e-6, "a path at the waterline stays a path")
	assert_almost_eq(edge[4], 0.0, 1e-6, "no bed over it yet")
	var mid := TerrainRules.compose_water(1.0, 0.0, Vector2.ZERO, Vector2(1.0, 0.0), 0.2)
	assert_almost_eq(mid[3], 0.5, 1e-6, "half way through the ford")
	assert_almost_eq(mid[3] + mid[4], 1.0, 1e-6, "path and bed share it")
	var rock := TerrainRules.compose_water(0.0, 1.0, Vector2.ZERO, Vector2(1.0, 0.0))
	assert_almost_eq(rock[4], 0.0, 1e-6, "painted rock holds under water")
	var dry := TerrainRules.compose_water(0.5, 0.0, Vector2(0.3, 0.1), Vector2.ZERO)
	var paint := TerrainRules.compose_paint(0.5, 0.0, Vector2(0.3, 0.1))
	assert_eq(Vector4(dry[0], dry[1], dry[2], dry[3]), paint, "no water: compose_paint")


# --- rocks -----------------------------------------------------------------------------------


func test_rock_policy_keeps_rocks_breaking_the_surface() -> void:
	var row := func(y: float, scale: float) -> PackedFloat32Array:
		return PackedFloat32Array([0, y, 0, 0, 0, 0, 1, scale, scale, scale])
	var level := 0.0
	assert_true(WaterCarve.keeps_rock(row.call(0.2, 1.0), 0.5, 0.3, level, 4.0), "on the bank")
	assert_true(WaterCarve.keeps_rock(row.call(-0.3, 1.0), 0.6, 0.3, level, 4.0), "edge foam")
	assert_false(WaterCarve.keeps_rock(row.call(-0.9, 1.0), 0.6, 0.3, level, 4.0), "submerged")
	assert_false(WaterCarve.keeps_rock(row.call(-0.3, 1.0), 1.5, 1.2, level, 4.0), "blocking")
	assert_true(WaterCarve.keeps_rock(row.call(-0.3, 1.0), 1.5, 1.2, level, 0.0), "a pond's")
	assert_true(WaterCarve.keeps_rock(row.call(-5.0, 1.0), 0.5, 0.3, WaterGeometry.DRY, 0.0))


# --- editor ----------------------------------------------------------------------------------


func _model(doc: MapDocument) -> Array:
	var out := []
	for body in doc.water_bodies:
		out.append([body.id, body.kind, body.depth, body.level_m, body.points, body.half_widths])
	return [out, doc.pond_mask]


func test_carve_river_is_one_entry_and_undoes_exactly() -> void:
	var editor := _editor()
	var start := _doc.heights.duplicate()
	var start_model := _model(_doc)
	var id := editor.water.carve_river(
		PackedVector2Array([Vector2(-10, -3), Vector2(0, 2), Vector2(10, -1)]),
		PackedFloat32Array([1.5]),
		WaterBody.Depth.WAIST
	)
	_settle(editor)
	assert_gt(id, 0)
	assert_eq(_history.undo_count(), 1)
	assert_ne(_doc.heights, start, "carved")
	assert_false(_doc.water_bodies.is_empty())
	assert_false(_doc.water_dressing.is_empty(), "dressed")
	assert_not_null(editor.terrain.get_water_texture())
	var carved := _doc.heights.duplicate()
	var carved_model := _model(_doc)
	var water := _map.get_node(AuthoredWater.NODE_NAME) as AuthoredWater
	assert_true(water.has_water(), "the surface is built")
	_history.undo()
	_settle(editor)
	assert_eq(_doc.heights, start, "undo restores the ground")
	assert_eq(_model(_doc), start_model, "and the water model")
	assert_true(_doc.water_dressing.is_empty())
	assert_false(water.has_water())
	_history.redo()
	_settle(editor)
	assert_eq(_doc.heights, carved, "redo")
	assert_eq(_model(_doc), carved_model)
	assert_true(water.has_water())


func test_pond_stroke_carves_a_basin_and_undoes_exactly() -> void:
	var editor := _editor()
	var start := _doc.heights.duplicate()
	var start_model := _model(_doc)
	assert_true(editor.water.paint_pond_begin(WaterBody.Depth.DEEP, Vector3(0, 0, 0)))
	editor.stroke_dab(Vector3(-2, 0, 0), Vector3(2, 0, 0), 3.0, 0.1)
	editor.flush()
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_eq(_history.undo_count(), 1)
	assert_eq(_doc.water_bodies.size(), 1)
	var pond := _doc.water_bodies[0]
	assert_false(pond.is_river())
	assert_eq(pond.depth, WaterBody.Depth.DEEP)
	assert_gt(_doc.pond_mask.count(pond.id), 100)
	# A small deep pond is a bowl whose shores meet before the full depth (its soft beach,
	# P4-4, takes a little more of it; still deeper than waist-deep water).
	var middle := _height(_doc, Vector2.ZERO)
	assert_lt(middle, pond.level_m - 0.7 * pond.depth_m(), "a deep basin")
	var carved := _doc.heights.duplicate()
	var carved_model := _model(_doc)
	_history.undo()
	_settle(editor)
	assert_eq(_doc.heights, start)
	assert_eq(_model(_doc), start_model)
	_history.redo()
	_settle(editor)
	assert_eq(_doc.heights, carved)
	assert_eq(_model(_doc), carved_model)
	# A second stroke from inside the pond extends it.
	assert_true(editor.water.paint_pond_begin(WaterBody.Depth.DEEP, Vector3(3, 0, 0)))
	editor.stroke_dab(Vector3(3, 0, 0), Vector3(6, 0, 0), 2.0, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_eq(_doc.water_bodies.size(), 1, "the same pond, larger")


func test_erase_water_leaves_the_ground_carved() -> void:
	var editor := _editor()
	# Ground falling along the river: several flat reaches.
	Fixtures.shape(_doc, func(p: Vector2) -> float: return -0.12 * p.x)
	editor.terrain.queue_heights(Rect2i(0, 0, _doc.samples_x(), _doc.samples_z()))
	editor.finish_height_work()
	editor.water.carve_river(
		PackedVector2Array([Vector2(-11, 0), Vector2(13, 0)]),
		PackedFloat32Array([1.5]),
		WaterBody.Depth.ANKLE
	)
	_settle(editor)
	var reaches := _doc.water_bodies.size()
	assert_gt(reaches, 2, "a stroke over sloped ground makes several reaches")
	# A second river, its own stroke, across the slope.
	editor.water.carve_river(
		PackedVector2Array([Vector2(-11, 9), Vector2(-11, 13)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.ANKLE
	)
	_settle(editor)
	var other: WaterBody = _doc.water_bodies[-1]
	var carved := _doc.heights.duplicate()
	var carved_model := _model(_doc)
	# A small dab on one reach in the middle of the first river.
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(-1, 0, -3), Vector3(-1, 0, 3), 0.3, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_eq(_doc.heights, carved, "the channel stays")
	assert_eq(_doc.water_bodies.size(), 1, "the touched river goes, every reach of it")
	assert_eq(_doc.water_bodies[0].id, other.id, "the other river stays")
	assert_eq(_doc.water_bodies[0].points, other.points, "untouched")
	var erased_model := _model(_doc)
	_history.undo()
	_settle(editor)
	assert_eq(_model(_doc), carved_model, "undo brings the river back")
	assert_eq(_doc.heights, carved)
	_history.redo()
	_settle(editor)
	assert_eq(_model(_doc), erased_model)
	# Erasing everything leaves no water and no dressing.
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(-14, 0, 11), Vector3(-8, 0, 11), 1.0, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_true(_doc.water_bodies.is_empty())
	assert_true(_doc.water_dressing.is_empty())
	assert_eq(_doc.heights, carved)


func test_carving_refused_without_authored_ground() -> void:
	var editor := AuthoringEditor.create(_doc, _map, _history)
	var id := editor.water.carve_river(
		PackedVector2Array([Vector2(-5, 0), Vector2(5, 0)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.WAIST
	)
	assert_eq(id, -1)
	assert_false(editor.water.paint_pond_begin(WaterBody.Depth.WAIST, Vector3.ZERO))
	assert_eq(_history.undo_count(), 0)


func test_placed_rocks_under_the_water_go_and_come_back_on_undo() -> void:
	var editor := _editor()
	var rule := editor.species_rule(BIOME, "boulder")
	if rule.is_empty():
		pending("no boulder in the palette")
		return
	var handle := editor.place_prop(rule, Vector3(0, 0, 0), Vector3.UP)
	editor.commit_prop_edit()
	var far := editor.place_prop(rule, Vector3(8, 0, 8), Vector3.UP)
	editor.commit_prop_edit()
	var before := editor.props.rows_by_asset()
	editor.water.carve_river(
		PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)]),
		PackedFloat32Array([3.0]),
		WaterBody.Depth.DEEP
	)
	_settle(editor)
	var rows: PackedFloat32Array = editor.props.rows_by_asset().get(
		handle.asset_id, PackedFloat32Array()
	)
	var near_left := false
	for r in rows.size() / MapDocument.ROW_STRIDE:
		if Vector2(rows[r * 10], rows[r * 10 + 2]).length() < 0.5:
			near_left = true
	assert_false(near_left, "the boulder in the deep channel is gone")
	assert_true(editor.prop_at(Vector3(8, 0, 8)).size() > 0 or far.is_empty(), "the far one stays")
	_history.undo()
	_settle(editor)
	assert_eq(editor.props.rows_by_asset(), before, "undo puts it back")
