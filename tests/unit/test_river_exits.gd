extends GutTest

## Rivers past the map edge (phase 6, P6-1): RiverExits (which ends leave the map and the
## course they run on), RiverExitMesh (the skirt's channel patch and the ribbon), the drawn
## course's storage (WaterBody.beyond, MapWaterIO) and the skirt that carries them
## (AuthoredTerrain, the opaque skirt shader, SkirtBackdrop).

const LEVEL := -0.15
const WIDTH := 1.5


## A flat 20 x 20 cell map (30.48 m) with a waist river planned and carved as the Water tool
## carves one, from `from` to `to` (map XZ).
func _river_doc(from: Vector2, to: Vector2, seed_value: int = 7) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", seed_value)
	var start := doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		doc,
		PackedVector2Array([from, (from + to) * 0.5, to]),
		PackedFloat32Array([WIDTH]),
		WaterBody.Depth.WAIST
	)
	var goals := WaterCarve.river_goals(doc, bodies, start)
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
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	return doc


func _half(doc: MapDocument) -> Vector2:
	return doc.extent_m() * 0.5


## A river from the middle to the near (+z) edge.
func _edge_doc(seed_value: int = 7) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", seed_value)
	var half := _half(doc)
	return _river_doc(Vector2(0.0, -4.0), Vector2(0.0, half.y - 0.2), seed_value)


func _parts(doc: MapDocument) -> Dictionary:
	return RiverExitMesh.build(
		doc,
		AuthoredTerrain.skirt_width_m(),
		AuthoredTerrain.SKIRT_FADE_M,
		AuthoredTerrain.SKIRT_WOBBLE
	)


# --- the course past the edge -----------------------------------------------------------


func test_a_river_not_touching_the_edge_gets_nothing() -> void:
	var doc := _river_doc(Vector2(-6.0, -4.0), Vector2(6.0, 3.0))
	assert_eq(RiverExits.exits(doc), [] as Array[Dictionary])
	assert_eq(_parts(doc), {})
	var parts := RiverExitMesh.skirt_parts(doc, AuthoredTerrain.skirt_width_m(), 24.0, 0.45)
	var plain := TerrainMeshBuilder.build_skirt_arrays(doc, AuthoredTerrain.skirt_width_m(), 24.0)
	assert_eq(parts.skirt[Mesh.ARRAY_INDEX], plain[Mesh.ARRAY_INDEX], "the skirt as it was")


func test_a_river_ending_at_the_edge_runs_on_out_of_the_map() -> void:
	var doc := _edge_doc()
	var exits := RiverExits.exits(doc)
	assert_eq(exits.size(), 1, "the downstream end at the edge")
	var found: Dictionary = exits[0]
	assert_eq(found.end, RiverExits.End.DOWN)
	assert_false(found.drawn, "derived")
	var course: PackedVector2Array = found.course
	var half := _half(doc)
	assert_between(
		RiverExits.outside_distance(course[-1], half),
		RiverExits.FADE_REACH_M,
		RiverExits.FADE_REACH_M + RiverExits.AUTO_STEP_M,
		"it runs on to where the skirt has faded, no further"
	)
	for i in range(1, course.size()):
		assert_gt(
			RiverExits.outside_distance(course[i], half),
			RiverExits.outside_distance(course[i - 1], half) - 1e-4,
			"it keeps heading away from the map"
		)
	var heading := (course[1] - course[0]).normalized()
	assert_gt(heading.dot(Vector2(0, 1)), 0.99, "it starts along the river's last heading")


func test_the_continuation_is_deterministic_from_the_seed() -> void:
	var a := RiverExits.exits(_edge_doc(7))[0].course as PackedVector2Array
	var b := RiverExits.exits(_edge_doc(7))[0].course as PackedVector2Array
	assert_eq(a, b, "same seed, same course")
	var bends := {}
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var course := RiverExits.exits(_edge_doc(seed_value))[0].course as PackedVector2Array
		var turn := (course[1] - course[0]).angle_to(course[-1] - course[-2])
		assert_between(
			absf(turn), RiverExits.AUTO_MIN_BEND_RAD - 0.05, RiverExits.AUTO_BEND_RAD + 0.05
		)
		bends[signf(turn)] = true
	assert_eq(bends.size(), 2, "the seed picks the side of the bend")


func test_an_upstream_end_at_the_edge_comes_from_somewhere_too() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 3)
	var half := _half(doc)
	doc = _river_doc(Vector2(-half.x + 0.3, 2.0), Vector2(half.x - 0.3, -1.0), 3)
	var ends := RiverExits.exits(doc).map(func(e: Dictionary) -> int: return e.end)
	ends.sort()
	assert_eq(ends, [RiverExits.End.UP, RiverExits.End.DOWN], "both ends of an edge-to-edge river")


func test_a_line_drawn_past_the_edge_is_split_and_kept_on_the_river() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 7)
	var half := _half(doc)
	var line := PackedVector2Array(
		[
			Vector2(0, -2),
			Vector2(0, half.y - 2.0),
			Vector2(0, half.y + 6.0),
			Vector2(8, half.y + 14.0)
		]
	)
	var split := RiverExits.split_line(
		line, PackedFloat32Array([WIDTH]), half, AuthoredTerrain.skirt_width_m()
	)
	var inside: PackedVector2Array = split.inside
	assert_almost_eq(inside[-1].y, half.y - RiverExits.EDGE_INSET_M, 1e-3, "cut at the edge")
	assert_eq(inside.size(), 3)
	assert_eq((split.widths as PackedFloat32Array).size(), 3)
	assert_true((split.up as PackedVector2Array).is_empty())
	var down: PackedVector2Array = split.down
	assert_between(down.size(), 2, WaterBody.MAX_BEYOND_POINTS)
	assert_almost_eq(down[-1], Vector2(8, half.y + 14.0), Vector2.ONE * 1e-3, "to the last point")
	var bodies := WaterEdit.plan_river(doc, inside, split.widths, WaterBody.Depth.WAIST)
	RiverExits.attach(bodies, split)
	assert_eq(bodies[-1].beyond, down, "the downstream reach keeps the drawn course")
	assert_true(bodies[0].beyond_up.is_empty())
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	var exits := RiverExits.exits(doc)
	assert_eq(exits.size(), 1)
	assert_true(exits[0].drawn)
	var course: PackedVector2Array = exits[0].course
	assert_eq(course.slice(1, down.size() + 1), down, "the drawn course first")
	assert_gt(
		RiverExits.outside_distance(course[-1], half),
		RiverExits.FADE_REACH_M - 0.01,
		"carried on to where the skirt has faded"
	)


func test_a_drawn_course_round_trips_through_the_document() -> void:
	var doc := _edge_doc()
	var half := _half(doc)
	var drawn := PackedVector2Array([Vector2(1, half.y + 3), Vector2(4, half.y + 9)])
	doc.water_bodies[-1].beyond = drawn
	doc.water_bodies[0].beyond_up = PackedVector2Array([Vector2(-2, -half.y - 5)])
	var packed := MapDocumentIO.serialize(doc)
	assert_eq(packed["error"], "")
	var result := MapDocumentIO.parse(packed["entries"])
	assert_eq(result["warnings"], PackedStringArray())
	var bodies: Array[WaterBody] = result["document"].water_bodies
	assert_eq(bodies[-1].beyond, drawn)
	assert_eq(bodies[0].beyond_up, PackedVector2Array([Vector2(-2, -half.y - 5)]))
	var copy := bodies[-1].copy()
	assert_eq(copy.beyond, drawn, "copies keep it")


func test_a_malformed_course_is_dropped_and_the_river_kept() -> void:
	var doc := _edge_doc()
	var packed := MapDocumentIO.serialize(doc)
	var entries: Dictionary = packed["entries"]
	var data: Dictionary = JSON.parse_string(entries["splines.json"].get_string_from_utf8())
	data["bodies"][-1]["beyond"] = [[1, "x"], [2]]
	data["bodies"][0]["beyond_up"] = [[0, 9999]]
	entries["splines.json"] = JSON.stringify(data).to_utf8_buffer()
	var result := MapDocumentIO.parse(entries)
	var bodies: Array[WaterBody] = result["document"].water_bodies
	assert_eq(bodies.size(), doc.water_bodies.size(), "every river kept")
	assert_true(bodies[-1].beyond.is_empty())
	assert_true(bodies[0].beyond_up.is_empty())
	assert_eq(result["warnings"].size(), 2)
	doc.water_bodies[-1].beyond = PackedVector2Array([Vector2(0, 999)])
	assert_ne(MapWaterIO.problem(doc), "", "the writer refuses a course far off the map")


# --- the geometry ------------------------------------------------------------------------


func test_the_channel_meets_the_map_without_a_step() -> void:
	var doc := _edge_doc()
	var parts := _parts(doc)
	assert_false(parts.is_empty())
	var channel: Array = parts.channel
	var vertices: PackedVector3Array = channel[Mesh.ARRAY_VERTEX]
	var half := _half(doc)
	var mouth: Dictionary = parts.mouths[0]
	var on_edge := 0
	var near_edge := 0
	for v in vertices:
		var xz := Vector2(v.x, v.z)
		var d := RiverExits.outside_distance(xz, half)
		if d < 1e-4:
			# Ring 0 is the map's own boundary vertex.
			assert_almost_eq(v.y, WaterGeometry.ground_at(doc, xz), 1e-4, "boundary at %s" % xz)
			on_edge += 1
		elif d <= 0.51 and absf(xz.x) < WIDTH + 1.0:
			# Half a metre out the channel is the river's own cross-section at the edge.
			var u: float = (xz - mouth.mouth).dot(mouth.across)
			var section := RiverExitMesh.profile_at(mouth, u)
			assert_almost_eq(v.y, section, 0.03, "cross-section at %s" % xz)
			near_edge += 1
	assert_gt(on_edge, 10)
	assert_gt(near_edge, 5)
	var bed := WaterGeometry.ground_at(doc, mouth.mouth - Vector2(0, 0.3))
	assert_lt(bed, LEVEL - 0.5, "the channel is carved below the water")


func test_the_patch_replaces_the_skirt_columns_it_covers_without_a_crack() -> void:
	var doc := _edge_doc()
	var width := AuthoredTerrain.skirt_width_m()
	var parts := RiverExitMesh.skirt_parts(doc, width, AuthoredTerrain.SKIRT_FADE_M, 0.45)
	var plain := TerrainMeshBuilder.build_skirt_arrays(doc, width, AuthoredTerrain.SKIRT_FADE_M)
	var windows: Array = parts.exits.windows
	assert_eq(windows.size(), 1)
	var window: Vector2i = windows[0]
	var count := TerrainMeshBuilder.boundary_samples(doc).size()
	var removed: int = (
		(plain[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		- (parts.skirt[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	)
	assert_eq(removed, window.y * TerrainMeshBuilder.SKIRT_RINGS * 6, "the window's quads go")
	# The patch's first column lies on the skirt's own: its vertices at the skirt's rings are
	# the skirt's, and the extra ones lie on the skirt's edges between them.
	var main: PackedVector3Array = plain[Mesh.ARRAY_VERTEX]
	var patch: PackedVector3Array = parts.exits.channel[Mesh.ARRAY_VERTEX]
	var dists := RiverExitMesh.ring_distances(width, width)
	var rings := patch.size() / (window.y + 1)
	assert_gt(rings, TerrainMeshBuilder.SKIRT_RINGS + 10, "a finer ring near the river")
	var r := 0
	var inner := Vector2(patch[0].x, patch[0].z)
	for k in rings:
		var v := patch[k]
		var out := Vector2(v.x, v.z).distance_to(inner)
		var own := -1
		for g in TerrainMeshBuilder.SKIRT_RINGS + 1:
			if absf(RiverExitMesh.skirt_distance(width, g) - out) < 1e-3:
				own = g
		if own >= 0:
			assert_eq(v, main[own * count + window.x], "ring %d is the skirt's vertex" % own)
			r = own
		else:
			var a := main[r * count + window.x]
			var b := main[(r + 1) * count + window.x]
			var on := Geometry3D.get_closest_point_to_segment(v, a, b)
			assert_almost_eq(v.distance_to(on), 0.0, 1e-4, "extra ring on the skirt's edge")
	assert_true(dists.size() > TerrainMeshBuilder.SKIRT_RINGS + 1)


func test_the_ribbon_is_at_the_river_level_and_flows_from_the_edge() -> void:
	var doc := _edge_doc()
	var parts := _parts(doc)
	var ribbon: Array = parts.ribbon
	assert_false(ribbon.is_empty())
	var vertices: PackedVector3Array = ribbon[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = ribbon[Mesh.ARRAY_TEX_UV]
	var level := doc.water_bodies[-1].level_m
	var half := _half(doc)
	var texels := WaterFlowBaker.resolution_for(doc.extent_m())
	for i in RiverExitMesh.RIBBON_ACROSS:
		assert_almost_eq(vertices[i].y, level, 1e-3, "the mouth row at the reach's level")
		assert_almost_eq(vertices[i].z, half.y, 1e-3, "starts on the edge")
	for uv in uvs:
		assert_lt(uv.y, 1.0 - 1.4 / texels.y, "flow read inside the still border texels")
	var deepest := INF
	for v in vertices:
		deepest = minf(deepest, v.y)
	assert_almost_eq(deepest, level, 0.05, "a flat map's skirt keeps the level")


func test_the_water_stays_at_its_level_out_to_the_edge() -> void:
	var doc := _edge_doc()
	var level := doc.water_bodies[-1].level_m
	var sheets := WaterMeshBuilder.cascades(doc)
	var at_edge := 0
	for i: int in sheets:
		var p := doc.sample_to_world(Vector2(i % doc.samples_x(), i / doc.samples_x()))
		if RiverExits.edge_distance(p, _half(doc)) < 0.6:
			assert_almost_eq(float(sheets[i]), level, 1e-4, "flat at the edge, no run-out fall")
			at_edge += 1
	assert_gt(at_edge, 0, "the end's last samples carry the water to the edge")


func test_a_terrain_draws_the_exit_and_drops_it_when_the_river_goes() -> void:
	var doc := _edge_doc()
	var terrain := AuthoredTerrain.create(doc)
	var skirt := terrain.get_skirt()
	var channel := skirt.get_node_or_null(NodePath(SkirtExits.CHANNEL_NAME)) as MeshInstance3D
	var ribbon := skirt.get_node_or_null(NodePath(SkirtExits.RIBBON_NAME)) as MeshInstance3D
	assert_not_null(channel)
	assert_not_null(ribbon)
	assert_eq(channel.mesh.surface_get_material(0), skirt.mesh.surface_get_material(0))
	assert_true(channel.has_meta(Constants.BOUNDS_EXEMPT_META))
	assert_eq(ribbon.material_override, WaterGlbUtils.water_material())
	assert_true(ribbon.get_instance_shader_parameter(SkirtExits.WATER_SKIRT_FADE_PARAM))
	var material := skirt.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(material.get_shader_parameter("skirt_channel"), 1, "the channel's dressing on")
	assert_not_null(skirt.get_node_or_null(NodePath(SkirtBackdrop.NODE_NAME)))
	doc.water_bodies = [] as Array[WaterBody]
	terrain.apply_river_exits({})
	skirt = terrain.get_skirt()
	assert_null(skirt.get_node_or_null(NodePath(SkirtExits.CHANNEL_NAME)))
	assert_eq(skirt.mesh.surface_get_material(0), material, "the same material")
	assert_true(terrain.river_exits().is_empty())
	terrain.free()


func test_the_load_worker_builds_the_exits() -> void:
	var doc := _edge_doc()
	var prepared := AuthoredLoadPrep.compute(doc)
	var parts: Dictionary = prepared[AuthoredLoadPrep.SKIRT]
	assert_false((parts.exits as Dictionary).is_empty())
	var terrain := AuthoredTerrain.create(doc, PaletteLibrary.DEFAULT_ROOT, true, prepared)
	var plain := AuthoredTerrain.create(doc)
	var path := NodePath(SkirtExits.CHANNEL_NAME)
	var a := (terrain.get_skirt().get_node(path) as MeshInstance3D).mesh.surface_get_arrays(0)
	var b := (plain.get_skirt().get_node(path) as MeshInstance3D).mesh.surface_get_arrays(0)
	assert_eq(a[Mesh.ARRAY_VERTEX], b[Mesh.ARRAY_VERTEX], "same channel either way")
	terrain.free()
	plain.free()


# --- the opaque skirt and its backdrop ---------------------------------------------------


func test_the_skirt_shader_is_opaque_and_instances() -> void:
	var shader: Shader = AuthoredTerrain.SKIRT_SHADER
	assert_true(shader.code.contains("depth_draw_opaque"))
	assert_false(shader.code.contains("blend_mix"), "not alpha blended")
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in SkirtBackdrop.uniforms(null, Vector3.FORWARD):
		material.set_shader_parameter(key, SkirtBackdrop.uniforms(null, Vector3.FORWARD)[key])
	assert_true(material.get_rid().is_valid(), "the material instances")
	var include := FileAccess.get_file_as_string("res://shaders/authored_ground.gdshaderinc")
	for needed in ["EMISSION = skirt_backdrop_color", "FOG = skirt_fog_at", "ALBEDO *= skirt_a"]:
		assert_true(include.contains(needed), needed)
	var water := FileAccess.get_file_as_string("res://shaders/water.gdshader")
	assert_true(water.contains("instance uniform bool water_skirt_fade"))


func test_the_backdrop_follows_the_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.7)
	env.background_energy_multiplier = 2.0
	var flat := SkirtBackdrop.uniforms(env, Vector3(0, -0.4, -1).normalized())
	var lin := Color(0.5, 0.6, 0.7).srgb_to_linear()
	assert_eq(flat.skirt_backdrop_mode, SkirtBackdrop.MODE_COLOR)
	assert_almost_eq(flat.skirt_backdrop, Vector3(lin.r, lin.g, lin.b) * 2.0, Vector3.ONE * 1e-5)
	assert_eq(flat.skirt_fog.w, 0.0, "no fog")
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.8, 0.9)
	env.fog_light_energy = 0.5
	env.fog_density = 0.02
	env.fog_height_density = 0.3
	var fogged := SkirtBackdrop.uniforms(env, Vector3.FORWARD)
	var fog := Color(0.8, 0.8, 0.9).srgb_to_linear() * 0.5
	assert_almost_eq(fogged.skirt_fog, Vector4(fog.r, fog.g, fog.b, 1.0), Vector4.ONE * 1e-5)
	assert_almost_eq(fogged.skirt_fog_params.x, 0.02, 1e-6)
	assert_almost_eq(fogged.skirt_fog_params.z, 0.3, 1e-6)
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = GroundPalette.solid_texture(Color.WHITE)
	env.sky.sky_material = panorama
	assert_eq(
		SkirtBackdrop.uniforms(env, Vector3.FORWARD).skirt_backdrop_mode, SkirtBackdrop.MODE_SKY
	)
	env.sky.sky_material = PhysicalSkyMaterial.new()
	var other := SkirtBackdrop.uniforms(env, Vector3.FORWARD)
	assert_eq(
		other.skirt_backdrop_mode, SkirtBackdrop.MODE_DITHER, "dither where no colour is known"
	)
	var gradient := ProceduralSkyMaterial.new()
	env.sky.sky_material = gradient
	var below := SkirtBackdrop.uniforms(env, Vector3(0, -1, 0))
	var bottom := gradient.ground_bottom_color.srgb_to_linear() * gradient.ground_energy_multiplier
	assert_eq(below.skirt_backdrop_mode, SkirtBackdrop.MODE_COLOR)
	assert_almost_eq(below.skirt_backdrop.x, bottom.r * 2.0, 1e-4, "the gradient's ground below")


func test_the_cpu_fade_matches_the_skirt_rule() -> void:
	var half := Vector2(15, 15)
	assert_eq(RiverExits.skirt_alpha(Vector2(3, 4), half, 24.0, 0.45, 9), 1.0, "1 on the map")
	assert_eq(RiverExits.skirt_alpha(Vector2(15, 70), half, 24.0, 0.45, 9), 0.0, "0 far out")
	var mid := RiverExits.skirt_alpha(Vector2(15, 27), half, 24.0, 0.0, 9)
	assert_almost_eq(mid, 0.5, 1e-5, "halfway without wobble")
