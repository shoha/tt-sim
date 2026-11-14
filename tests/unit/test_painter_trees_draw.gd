extends GutTest

## The painted trees' draw (PainterTrees, PainterTreeTones, PainterTreeMeshes, PainterTreeBrushes,
## the two tree shaders; docs/systems/painter.md "Trees"): both shaders compile against tt-sim's
## wind, sun and fade globals; a painted map's mapped tree rows become cells of five nodes and the
## GLB chunks hide; a paint and an erase add and remove exactly those trees; leaving Painted frees
## every node and shows the GLB chunks again, and coming back draws them again; the foliage AA
## swap never reaches a tree material; the tones and levels follow the spike's rules. Uses the
## built-in palette's temperate forest oak.

const OAK := "temperate_forest_summer_s1/Tree_Oak_v0"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const INCLUDE := "res://painter/shaders/painter_tree.gdshaderinc"

var _container: Node3D = null
var _map: Node3D = null


func before_each() -> void:
	PainterSheet.clear_cache()
	_container = Node3D.new()
	add_child_autofree(_container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)


func _rows(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p: Vector2 in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


func _scatter() -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	return scatter


func _glb_trees(scatter: AuthoredScatter) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for child in scatter.get_children():
		if child is MultiMeshInstance3D and str(child.name).contains("Tree_Oak"):
			out.append(child)
	return out


func _painted(surfaces: PainterSurfaces) -> PainterTrees:
	var trees := surfaces.trees() as PainterTrees
	trees.complete()
	return trees


func _node_count() -> int:
	var root := _map.get_node_or_null(NodePath(PainterTrees.ROOT_NAME))
	if root == null:
		return 0
	var live := func(n: Node) -> bool: return not n.is_queued_for_deletion()
	return root.get_children().filter(live).size()


func test_both_shaders_compile_against_the_wind_sun_and_fade_globals() -> void:
	for path: String in [PainterTrees.STROKE_SHADER, PainterTrees.BLOCKIN_SHADER]:
		var names: Array = []
		for u: Dictionary in (load(path) as Shader).get_shader_uniform_list():
			names.append(u["name"])
		for wanted: String in ["palette", "role_params", "row_map", "mass_tex", "tree_tex"]:
			assert_has(names, wanted, "%s reads %s" % [path, wanted])
		for wanted: String in ["wind_strength", "cast_amount", "enable_occlusion"]:
			assert_has(names, wanted, "%s has %s" % [path, wanted])
		for gone: String in ["wind_time", "wind_amp", "sun_dir", "e_far", "pspike_untone_mode"]:
			assert_does_not_have(names, gone, "%s has no spike %s" % [path, gone])
	var code := FileAccess.get_file_as_string(INCLUDE)
	for global_name: String in [
		"wind_dir", "wind_phase", "wind_gust", "foliage_sun", "canopy_fade_centre", "canopy_cut"
	]:
		assert_true(code.contains("global uniform vec4 %s;" % global_name), global_name)
	assert_true(code.contains("occlusion_fade_include.gdshaderinc"), "the token occlusion fade")
	assert_false(code.contains("LIGHT_VERTEX"), "the shadow lookup never moves")


## painter-a2a5: the block-in wrote POSITION alone, so its fragment VERTEX was the mesh's unit
## sphere at the tree's foot, and a token under a crown kept the masses and limbs over it. Every
## tree shader binds the token texture, writes its own view-space VERTEX and tests the tokens
## there; the include walks the screen tile's list and the plain loop.
func test_every_tree_shader_tests_the_tokens_at_its_own_fragment() -> void:
	for path: String in [PainterTrees.STROKE_SHADER, PainterTrees.BLOCKIN_SHADER]:
		var names: Array = []
		for u: Dictionary in (load(path) as Shader).get_shader_uniform_list():
			names.append(u["name"])
		for wanted: String in ["enable_occlusion", "occlusion_tokens"]:
			assert_has(names, wanted, "%s binds %s" % [path, wanted])
		var code := FileAccess.get_file_as_string(path)
		assert_true(code.contains("skip_vertex_transform"), "%s places VERTEX itself" % path)
		assert_true(
			code.contains("VERTEX = (VIEW_MATRIX * vec4("), "%s writes its view-space point" % path
		)
		assert_true(code.contains("tree_fades(VERTEX,"), "%s fades at its own fragment" % path)
	var inc := FileAccess.get_file_as_string(INCLUDE)
	for wanted: String in [
		"occlusion_tiles_match(view_matrix, projection_matrix)",
		"for (int i = first; i < end; i++)",
		"for (int i = 0; i < occlusion_token_count; i++)",
		"bool tree_token_frag(",
		"bool tree_token_stroke(",
	]:
		assert_true(inc.contains(wanted), "the token window: %s" % wanted)


## painter-token-window: a circular cut through every part read as a glass dome over the token.
## A stroke goes whole, decided in its vertex stage (never a ground shadow dab); the block-in is
## cut per fragment; no stroke is cut per fragment.
func test_the_token_window_takes_whole_strokes() -> void:
	var stroke := FileAccess.get_file_as_string(PainterTrees.STROKE_SHADER)
	assert_true(stroke.contains("!is_shadow && tree_token_stroke("), "strokes go whole, dabs stay")
	assert_true(stroke.contains("v_key, v_key < 0.0, true);"), "no per-fragment cut on a stroke")
	var block := FileAccess.get_file_as_string(PainterTrees.BLOCKIN_SHADER)
	assert_true(block.contains("key, kind10 > 0.5, false);"), "the block-in is cut per fragment")


func test_painted_rows_become_cells_and_hide_the_glb_trees() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(1, 1), Vector2(2, 1)])}})
	var glb := _glb_trees(scatter)
	assert_gt(glb.size(), 0, "the oak has GLB chunk nodes")
	var surfaces := PainterSurfaces.new()
	assert_true(surfaces.paint(_map, STATE))
	var trees := _painted(surfaces)

	assert_eq(trees.trees.size(), 2, "both oak rows painted")
	assert_eq(trees.cells.size(), 1, "both in one 5 m cell")
	assert_eq((trees.cells.values()[0]["nodes"] as Array).size(), 5, "five nodes a cell")
	assert_eq(_node_count(), 5)
	for node in glb:
		assert_false(node.visible, "GLB oak hidden")
	var nodes: Array = trees.cells.values()[0]["nodes"]
	assert_eq(
		(nodes[0] as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"the block-in casts"
	)
	assert_eq(
		(nodes[2] as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"strokes cast none"
	)
	surfaces.release()


func test_a_paint_and_an_erase_change_exactly_those_trees() -> void:
	var scatter := _scatter()
	var two := [Vector2(1, 1), Vector2(2, 1)]
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows(two)}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := _painted(surfaces)
	var before: Dictionary = trees.trees.duplicate()

	scatter.set_cells({Vector2i(0, 0): {OAK: _rows(two + [Vector2(8, 1)])}})
	trees.complete()
	assert_eq(trees.trees.size(), 3, "the painted row added")
	for key: Vector3i in before:
		assert_eq(trees.trees[key]["d"], before[key]["d"], "an old tree is the very same")
	assert_eq(trees.cells.size(), 2, "the new tree in its own cell")

	scatter.set_cells({Vector2i(0, 0): {OAK: _rows(two)}})
	trees.complete()
	assert_eq(trees.trees.keys(), before.keys(), "the erased row gone, the rest kept")
	assert_eq(trees.cells.size(), 1, "its emptied cell gone")
	surfaces.release()


func test_leaving_painted_restores_the_glb_trees_and_coming_back_draws_again() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(1, 1)])}})
	var glb := _glb_trees(scatter)
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := _painted(surfaces)
	assert_eq(trees.trees.size(), 1)

	surfaces.release()

	assert_false(trees.is_active())
	assert_eq(trees.trees.size(), 0)
	assert_eq(_node_count(), 0, "every painted node freed")
	for node in glb:
		assert_true(node.visible, "GLB oak shown again")

	surfaces.paint(_map, STATE)
	trees.complete()
	assert_eq(trees.trees.size(), 1, "drawn again")
	for node in glb:
		assert_false(node.visible, "hidden again")
	surfaces.release()


func test_the_foliage_aa_swap_never_reaches_a_tree_material() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(1, 1)])}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := _painted(surfaces)
	var shaders: Array = trees.materials().map(func(m: ShaderMaterial) -> Shader: return m.shader)
	var collected := WindFoliage.collect_foliage_shader_materials(_container)
	for m in trees.materials():
		assert_true(m.has_meta(WindFoliage.META_STAND_IN), "carries the stand-in mark")
		assert_does_not_have(collected, m, "never collected for a shader swap")
	assert_eq(
		trees.materials().map(func(m: ShaderMaterial) -> Shader: return m.shader), shaders, "kept"
	)
	surfaces.release()


## A table as the playing state makes one: a GameMap (never in the tree, no scene) whose map
## container holds a LevelMap with one scatter of two oaks.
func _table() -> Dictionary:
	var table: GameMap = GameMap.new()
	var container := Node3D.new()
	add_child(container)
	table.map_container = container
	var map := Node3D.new()
	map.name = "LevelMap"
	container.add_child(map)
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	map.add_child(scatter)
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(1, 1), Vector2(2, 1)])}})
	return {"table": table, "container": container, "map": map, "glb": _glb_trees(scatter)}


## painter-trees-fix: the second level of a process came out with no painted tree (a render job
## built a village, then a forest, both Painted). LevelEnvironmentManager lives on while every
## entry into play makes a new GameMap, and its PainterSurfaces still followed the first table's
## freed map container, so the second map was never painted. Both ways a second level comes: a
## new table (title, then play) and the same table with a new LevelMap (a level loaded in play).
func test_a_second_level_in_one_process_gets_its_painted_trees() -> void:
	var choice := RenderStyle.choice
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED
	for same_table: bool in [false, true]:
		var manager := LevelEnvironmentManager.new()
		var first := _table()
		manager.setup(first["table"])
		manager.set_look({"style": RenderStyle.PAINTED, "mood": "summer"})
		var surfaces := manager.get("_surfaces") as PainterSurfaces
		var trees := _painted(surfaces)
		assert_eq(trees.trees.size(), 2, "the first level painted (same table %s)" % same_table)
		manager.clear()
		for node: Node3D in first["glb"]:
			assert_true(node.visible, "the first level's GLB oaks shown again on unload")
		var second := first
		if same_table:
			(first["map"] as Node).queue_free()
			await wait_process_frames(1)
			var map := Node3D.new()
			map.name = "LevelMap"
			(first["container"] as Node).add_child(map)
			var scatter := AuthoredScatter.create()
			scatter.budget = 1_000_000_000
			scatter.grow_seconds = 0.0
			map.add_child(scatter)
			scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(4, 4), Vector2(6, 2)])}})
			second = {"map": map, "glb": _glb_trees(scatter)}
		else:
			(first["container"] as Node).free()
			(first["table"] as Node).free()
			second = _table()
			manager.setup(second["table"])
		manager.set_look({"style": RenderStyle.PAINTED, "mood": "summer"})
		trees = _painted(surfaces)
		assert_eq(manager.get("_surfaces"), surfaces, "one surfaces host for the process")
		assert_eq(trees.trees.size(), 2, "the second level painted (same table %s)" % same_table)
		assert_true(surfaces.is_active(), "the second level's ground and scatter painted")
		for node: Node3D in second["glb"]:
			assert_false(node.visible, "the second level's GLB oaks hidden")
		# A level loaded Painted hides its tree chunks before the fade manager's setup(); the
		# manager still registers them, so the painted trees take a live token binding from them.
		var collected: Array[MultiMeshInstance3D] = []
		OcclusionFadeManager._collect_tree_multimeshes(second["map"], collected)
		assert_eq(collected.size(), (second["glb"] as Array).size(), "hidden oaks still registered")
		RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
		manager.apply_render_style()
		assert_eq(trees.trees.size(), 0, "leaving Painted frees the second level's trees")
		for node: Node3D in second["glb"]:
			assert_true(node.visible, "the second level's GLB oaks shown again")
			assert_false(node.has_meta(OcclusionFadeManager.KEEP_HIDDEN_META), "the mark gone")
		RenderStyle.choice = RenderStyle.CHOICE_PAINTED
		manager.clear()
		var container: Node = (
			second["container"] if second.has("container") else first["container"]
		)
		container.free()
		if second.has("table"):
			(second["table"] as Node).free()
		elif is_instance_valid(first["table"]):
			(first["table"] as Node).free()
	RenderStyle.choice = choice


func test_the_tones_keep_each_species_and_follow_the_sheet() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var baked := PainterTreeTones.bake(sheet, "summer", 60.0)
	var palette: Image = baked["palette"]
	var params: Image = baked["params"]
	assert_eq(palette.get_size(), Vector2i(PainterTreeTones.TONES, 256))
	assert_eq(params.get_size(), Vector2i(PainterTreeTones.MAX_ROWS, PainterTreeTones.PARAM_ROWS))
	var table := PainterTreeTones.row_table()
	assert_true((table["spruce"] as Dictionary).has("evergreen"), "a conifer has needles")
	assert_eq(PainterTreeTones.role_rows("spruce")[8], table["spruce"]["evergreen"])
	assert_eq(PainterTreeTones.role_rows("oak")[6], PainterTreeTones.GROUND_ROW)
	# Summer at a high sun: the sheet's leaf stands lighter than the spike world's, so the
	# birch (painter-trees-polish: a yellow-green, the spike's lemon was the brightest thing on
	# the map) is lifted by as much and keeps its own hue.
	var birch_leaf: int = table["birch"]["leaf"]
	var mid := palette.get_pixel(15, birch_leaf * PainterTreeTones.VARIANTS + 1)
	var spike := PainterSheet.parse_color("oklch(0.68 0.118 131)")
	var got := PainterSheet.lch_of_color(mid)
	assert_almost_eq(got.z, spike.z, 6.0, "the birch's own hue")
	assert_gt(got.x, spike.x, "lifted with the sheet's lighter leaf")
	var oak_leaf: int = table["oak"]["leaf"]
	assert_ne(
		palette.get_pixel(15, oak_leaf * 4 + 1), mid, "the species do not share one green"
	)
	var dusk: Image = PainterTreeTones.bake(sheet, "dusk", 10.0)["palette"]
	assert_ne(dusk.get_pixel(15, birch_leaf * 4 + 1), mid, "the mood moves the colour")


## CameraController.CANOPY_CLEARANCE stands over every painted tree at its oldest, strokes and
## sway included (the seeds below include the tallest painter-a2a3 found for poplar and lime
## among 60 per species).
func test_the_canopy_clearance_stands_over_the_tallest_painted_tree() -> void:
	var tallest := 0.0
	for species in PainterTreeSpecies.names():
		var arch := PainterTreeSpecies.architecture(species)
		for openness: float in [0.1, 0.5, 0.9]:
			for seed: int in [72271, 32676, 88109]:
				var cx := {"age": PainterTreeSpecies.AGE["hi"], "openness": openness}
				var conifer := PainterTreeSpecies.is_conifer(species)
				var masses := PainterTreeGrowth.tree(arch, cx, seed, conifer)
				var b: AABB = PainterTreePack.pack(masses, seed, 3.0, PainterTreeSpecies.wide())["aabb"]
				tallest = maxf(tallest, b.end.y)
	assert_gt(tallest, 15.0, "the tallest species is measured (poplar 16.74 m)")
	assert_lte(
		tallest + PainterTrees.BOUND_GROW,
		CameraController.CANOPY_CLEARANCE,
		"the clearance stands over a %.2f m tree" % tallest
	)


## painter-a2a3: the spike's shade pulls swung brown bark to maroon and cancelled a green crown
## to grey. painter-a2a4: a 0.2 pull still read red beside the lit side. Every stem's shade stays
## its own warm brown (or a near grey) in every mood and sun: within 12 degrees of its middle
## tone's hue (the 0.2 pull turned it 15 to 22), and never past red into maroon or violet
## (under 10; a pine's own red-orange at dusk and night moods sits at 17 to 30); and a summer
## crown's shade keeps most of its green, leaning teal.
func test_stems_shade_brown_and_crowns_shade_green() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var table := PainterTreeTones.row_table()
	for mood: String in PainterSheet.MOODS:
		for elevation: float in [60.0, 20.0, 3.0, -8.0]:
			var palette: Image = PainterTreeTones.bake(sheet, mood, elevation)["palette"]
			for species: String in table:
				var bark: int = table[species]["bark"]
				var shade := PainterSheet.lch_of_color(palette.get_pixel(3, bark * 4 + 1))
				var mid := PainterSheet.lch_of_color(palette.get_pixel(15, bark * 4 + 1))
				if shade.y > 0.02 and mid.y > 0.02:
					var where := "%s bark shade in %s at %.0f" % [species, mood, elevation]
					assert_between(shade.z, 10.0, 80.0, "%s is warm, not maroon (h %.0f)" % [where, shade.z])
					var turn := absf(fposmod(shade.z - mid.z + 180.0, 360.0) - 180.0)
					assert_lt(turn, 12.0, "%s keeps its middle tone's hue (%.0f off)" % [where, turn])
	var summer: Image = PainterTreeTones.bake(sheet, "summer", 60.0)["palette"]
	for species: String in table:
		var leaf: int = table[species]["leaf"]
		var shade := PainterSheet.lch_of_color(summer.get_pixel(3, leaf * 4 + 1))
		var mid := PainterSheet.lch_of_color(summer.get_pixel(15, leaf * 4 + 1))
		assert_gt(shade.y, mid.y * 0.6, "%s crown shade keeps its chroma" % species)
		assert_between(shade.z, 135.0, 200.0, "%s crown shade is green to teal" % species)


## painter-a2a4: the stems read dark chocolate beside Classic's mid brown. On a summer midday a
## brown stem's middle tone is a mid brown and its lit side a light one, and its shade is no
## darker than a step under the middle.
func test_summer_stems_are_mid_brown() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var table := PainterTreeTones.row_table()
	var palette: Image = PainterTreeTones.bake(sheet, "summer", 60.0)["palette"]
	for species: String in table:
		var bark: int = table[species]["bark"]
		var mid := PainterSheet.lch_of_color(palette.get_pixel(15, bark * 4 + 1))
		if mid.y < 0.03:
			continue
		var shade := PainterSheet.lch_of_color(palette.get_pixel(3, bark * 4 + 1))
		var lit := PainterSheet.lch_of_color(palette.get_pixel(28, bark * 4 + 1))
		assert_gte(mid.x, 0.44, "%s bark middle is a mid brown (L %.2f)" % [species, mid.x])
		assert_gte(lit.x, 0.58, "%s bark lit side is a light brown (L %.2f)" % [species, lit.x])
		assert_gte(shade.x, mid.x * 0.7, "%s bark shade is a step under the middle" % species)


func test_the_shared_meshes_and_brushes() -> void:
	assert_eq(PainterTreeMeshes.block().get_surface_count(), 1)
	var quads := PainterTreePack.SLOT_PER_INST * PainterTreePack.ROOTS
	var arrays := PainterTreeMeshes.strokes(1).surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), quads * 4 * 4)
	var ribbon := PainterTreeMeshes.ribbon().surface_get_arrays(0)
	assert_eq(
		(ribbon[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
		PainterTreePack.SEG_PER_INST * PainterTreeMeshes.RIBBON_SUB * 6
	)
	var images := PainterTreeBrushes.images()
	assert_eq(images.size(), PainterTreeBrushes.LAYERS)
	for img in images:
		assert_eq(img.get_width(), PainterTreeBrushes.SIZE)
		assert_true(img.has_mipmaps())


func test_stroke_levels_follow_the_camera_size() -> void:
	assert_almost_eq(PainterTrees.lod_for(PainterTrees.HOME_SIZE), 1.0, 1e-5, "home: level 1")
	assert_almost_eq(PainterTrees.lod_for(PainterTrees.HOME_SIZE * 2.0), 0.0, 1e-5)
	assert_true(PainterTrees.level_shown(1.0, 1))
	assert_false(PainterTrees.level_shown(1.0, 0))
	assert_true(PainterTrees.level_shown(0.5, 0) and PainterTrees.level_shown(0.5, 1), "a blend")
	assert_true(PainterTrees.level_shown(-3.0, 0), "far: level 0 only")
