extends GutTest

## The painted trees' draw (PainterTrees, PainterTreeTones, PainterTreeMeshes, PainterTreeBrushes,
## the two tree shaders; docs/systems/painter.md "Trees"): both shaders compile against tt-sim's
## wind, sun and fade globals; a painted map's mapped tree rows become cells of five nodes and the
## GLB chunks hide; a paint and an erase add and remove exactly those trees; leaving Painted frees
## every node and shows the GLB chunks again, and coming back draws them again; the foliage AA
## swap never reaches a tree material; the tones and levels follow the spike's rules. Uses the
## built-in palette's temperate forest oak.

const OAK := "temperate_forest_summer_s1/Tree_Oak_v0"
const BUSH := "temperate_forest_summer_s1/Bush_Bush_v0_temperate_forest"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const INCLUDE := "res://painter/shaders/painter_tree.gdshaderinc"
## The stroke and block-in bodies each shader variant (in leaf, bare) includes.
const STROKE_BODY := "res://painter/shaders/painter_tree_stroke_body.gdshaderinc"
const BLOCKIN_BODY := "res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
const SHADERS: Array[String] = [
	PainterTrees.STROKE_SHADER,
	PainterTrees.BLOCKIN_SHADER,
	PainterTrees.STROKE_BARE_SHADER,
	PainterTrees.BLOCKIN_BARE_SHADER,
]

## The crown masses' discard-free camera variants (painter-perf-blockin; test_painter_tree_fast).
const FAST_SHADERS: Array[String] = [PainterTreeFast.SHADER, PainterTreeFast.BARE_SHADER]

var _container: Node3D = null
var _map: Node3D = null


## A tree shader's source with its body (the variants are a render mode and an include).
static func _code(path: String) -> String:
	var code := FileAccess.get_file_as_string(path)
	var body := STROKE_BODY if path.contains("stroke") else BLOCKIN_BODY
	return code + "\n" + FileAccess.get_file_as_string(body)


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
	for path: String in SHADERS + FAST_SHADERS:
		var names: Array = []
		for u: Dictionary in (load(path) as Shader).get_shader_uniform_list():
			names.append(u["name"])
		for wanted: String in ["palette", "role_params", "row_map", "mass_tex", "tree_tex"]:
			assert_has(names, wanted, "%s reads %s" % [path, wanted])
		for wanted: String in ["wind_strength", "cast_amount"]:
			assert_has(names, wanted, "%s has %s" % [path, wanted])
		for gone: String in [
			"wind_time", "wind_amp", "sun_dir", "e_far", "pspike_untone_mode", "enable_occlusion",
			"occlusion_tokens", "token_fade_strength"
		]:
			assert_does_not_have(names, gone, "%s has no %s" % [path, gone])
	var code := FileAccess.get_file_as_string(INCLUDE)
	for global_name: String in [
		"wind_dir", "wind_phase", "wind_gust", "foliage_sun", "canopy_fade_view", "canopy_cut"
	]:
		assert_true(code.contains("global uniform vec4 %s;" % global_name), global_name)
	for gone: String in ["canopy_fade_centre", "canopy_fade_shape", "TREE_FADE_START"]:
		assert_false(code.contains(gone), "the view-centre canopy window's %s is gone" % gone)
	assert_true(code.contains("screen_dither_include.gdshaderinc"), "the shared dither helpers")
	assert_false(code.contains("occlusion_fade_include"), "the token occlusion fade is gone")
	assert_false(code.contains("LIGHT_VERTEX"), "the shadow lookup never moves")


## painter-a2a5: the block-in wrote POSITION alone, so its fragment VERTEX was the mesh's unit
## sphere at the tree's foot. Every tree shader writes its own view-space VERTEX, so the canopy
## fade tests the fragment, not the foot. (The per-token fade that first needed this was removed
## 2026-11-15: a covered token is found through its ghost.)
func test_every_tree_shader_fades_the_canopy_at_its_own_fragment() -> void:
	for path: String in SHADERS:
		var code := _code(path)
		assert_true(code.contains("skip_vertex_transform"), "%s places VERTEX itself" % path)
		assert_true(
			code.contains("VERTEX = (VIEW_MATRIX * vec4("), "%s writes its view-space point" % path
		)
		assert_true(code.contains("tree_fades(VERTEX,"), "%s fades at its own fragment" % path)
	var inc := FileAccess.get_file_as_string(INCLUDE)
	for dead: String in [
		"occlusion_tiles_match(",
		"occlusion_token_count",
		"tree_thin_at(",
		"tree_thin_vertex(",
		"tree_token_near(",
		"token_fade_strength",
		"tree_token_stroke(",
		"tree_token_frag(",
	]:
		assert_false(inc.contains(dead), "no token fade left: %s" % dead)


## painter-perf-strokes: a dropped mark leaves before the wind and the placement, and the triangle
## block's corner outside the unit square is discarded; the strokes and the block-in carry no
## token thinning (it was removed 2026-11-15).
func test_the_stroke_and_blockin_shaders_carry_no_token_thinning() -> void:
	var stroke := _code(PainterTrees.STROKE_SHADER)
	assert_true(stroke.contains("float rnd2h = fract(rnd * 11.13 + 0.31);"), "early density test")
	assert_true(stroke.contains("v_uv.x > 1.0 || v_uv.y > 1.0"), "the triangle's spare corner")
	var block := _code(PainterTrees.BLOCKIN_SHADER)
	for code: String in [stroke, block]:
		assert_false(code.contains("tree_thin"), "no thinning call")
		assert_false(code.contains("TREE_THIN"), "no thinning constant")
		assert_false(code.contains("occlusion_token"), "no token binding")
		assert_false(code.contains("enable_occlusion"), "no token binding switch")


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
	assert_eq((trees.cells.values()[0]["nodes"] as Array).size(), 6, "five nodes and a shadow twin")
	assert_eq(_node_count(), 6)
	for node in glb:
		assert_false(node.visible, "GLB oak hidden")
	var nodes: Array = trees.cells.values()[0]["nodes"]
	assert_eq(
		(nodes[1] as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"the limbs cast"
	)
	assert_eq(
		(nodes[0] as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the camera masses cast none: their twin does"
	)
	assert_eq(
		(nodes[2] as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"strokes cast none"
	)
	surfaces.release()


## painter-bushes: a card-built bush's row is drawn as a crown-only tree in a bush cell (smaller
## blocks, no limb ribbon), its GLB chunk hides, and its tree-table row marks it a bush (texel 3 w
## 2); the texel stays (a bush is flagged by it).
func test_a_bush_row_is_drawn_as_a_crown_and_hides_its_glb() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {BUSH: _rows([Vector2(1, 1)]), OAK: _rows([Vector2(3, 1)])}})
	var glb: Array[MultiMeshInstance3D] = []
	for child in scatter.get_children():
		if child is MultiMeshInstance3D and str(child.name).contains("Bush_Bush"):
			glb.append(child)
	assert_gt(glb.size(), 0, "the bush has GLB chunk nodes")
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := _painted(surfaces)
	assert_eq(trees.trees.size(), 2, "the oak and the bush")
	assert_eq(trees.cells.size(), 1, "the oak's cell")
	assert_eq(trees.bush_cells.size(), 1, "the bush's cell")
	var nodes: Array = trees.bush_cells.values()[0]["nodes"]
	assert_eq(nodes.size(), 6)
	assert_null(nodes[1], "a bush cell has no limb ribbon")
	var block := (nodes[0] as MultiMeshInstance3D).multimesh
	assert_eq(block.mesh, PainterTreeMeshes.block(PainterTrees.BUSH_ELL_PER_INST, true))
	assert_eq(_node_count(), 11, "six tree nodes and five bush nodes")
	for node in glb:
		assert_false(node.visible, "GLB bush hidden")
	for key: Vector3i in trees.trees:
		var t: Dictionary = trees.trees[key]
		if t["bush"]:
			var row := PainterTreePack.tree_row(t["d"], 0, 0, 0, 0.0, 0.0, 0.0, 0.0)
			assert_eq(row[15], 2.0, "the bush's crown flag")
	surfaces.release()
	for node in glb:
		assert_true(node.visible, "GLB bush shown again")


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
		RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
		manager.apply_render_style()
		assert_eq(trees.trees.size(), 0, "leaving Painted frees the second level's trees")
		for node: Node3D in second["glb"]:
			assert_true(node.visible, "the second level's GLB oaks shown again")
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


## painter-winter-trees2: a bare season's kept leaf clumps shaded near-black (oak #070304: the
## dry-shade-lift was taken off the share of the lightness the shade keeps). A dry leaf's shade
## keeps most of its lightness and its warm hue.
func test_a_bare_seasons_dry_leaf_shades_warm_never_black() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var table := PainterTreeTones.row_table()
	var winter: Image = PainterTreeTones.bake(sheet, "winter", 20.0)["palette"]
	for species: String in ["oak", "lime", "rowan", "willow", "birch"]:
		var leaf: int = table[species]["leaf"]
		var shade := PainterSheet.lch_of_color(winter.get_pixel(0, leaf * 4 + 1))
		var mid := PainterSheet.lch_of_color(winter.get_pixel(15, leaf * 4 + 1))
		assert_gt(shade.x, mid.x * 0.7, "%s dry shade keeps its lightness" % species)
		assert_gt(shade.y, 0.03, "%s dry shade keeps a colour" % species)
		assert_between(shade.z, 15.0, 110.0, "%s dry shade stays warm (%.0f)" % [species, shade.z])


## painter-winter-trees2: the leaf drop's code in every season cost the summer eye view 0.23 ms.
## A bare season draws with the TREE_BARE variants and its bare uniforms; leaf with the plain ones
## and the leaf values.
func test_a_bare_season_swaps_to_the_bare_variants_and_back() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(1, 1)])}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := _painted(surfaces)
	var sheet := PainterSheet.load_sheet("core")
	for mood: String in ["winter", "summer", "autumn"]:
		trees.retone(sheet, mood, 20.0)
		var is_bare := mood == "winter"
		var mats: Array = trees.get("_materials")
		assert_eq(mats.size(), 5)
		for i in mats.size():
			var m: ShaderMaterial = mats[i]
			var want := PainterTrees.shader_path(i < 2, is_bare)
			assert_eq(m.shader.resource_path, want, "%s material %d" % [mood, i])
			var snow: float = m.get_shader_parameter(&"limb_snow17")
			assert_eq(snow, 1.0 if is_bare else 0.0, "%s limb snow" % mood)
		var fast := trees.fast_material
		assert_eq(fast.shader.resource_path, PainterTreeFast.shader_path(is_bare, false), mood)
		assert_eq(fast.get_shader_parameter(&"limb_snow17"), 1.0 if is_bare else 0.0, mood)
	surfaces.release()


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
	# One triangle a stroke (UV 0..2: the unit square lies inside it; the fragment cuts the rest).
	var arrays := PainterTreeMeshes.strokes(1).surface_get_arrays(0)
	var uv := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), quads * 4 * 3)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), quads * 4 * 3)
	assert_eq(uv[0], Vector2(0.0, 0.0))
	assert_eq(uv[1], Vector2(2.0, 0.0))
	assert_eq(uv[2], Vector2(0.0, 2.0))
	assert_eq((arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[5].x, 1.0, "UV2.x is the stroke")
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


## painter-perf-veg: a level 2 root draws L2_CHILDREN of its 16 children, the mesh and the shader
## agree on the count, and the count splits into four equal quarters (the shader reads the child's
## parent quarter as `wi / (per_root / 4)`).
func test_level_two_draws_twelve_children() -> void:
	assert_eq(PainterTreeMeshes.L2_CHILDREN, 12)
	assert_eq(PainterTreeMeshes.L2_CHILDREN % 4, 0, "four equal quarters")
	var slots := PainterTreePack.SLOT_PER_INST * PainterTreePack.ROOTS
	var arrays := PainterTreeMeshes.strokes(2).surface_get_arrays(0)
	assert_eq(
		(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		slots * PainterTreeMeshes.L2_CHILDREN * 3,
		"a triangle a child"
	)
	var body := FileAccess.get_file_as_string(
		"res://painter/shaders/painter_tree_stroke_body.gdshaderinc"
	)
	assert_true(
		body.contains("const int L2_CHILDREN = %d;" % PainterTreeMeshes.L2_CHILDREN),
		"the shader's constant is the mesh's"
	)


func test_stroke_levels_follow_the_camera_size() -> void:
	assert_almost_eq(PainterTrees.lod_for(PainterTrees.HOME_SIZE), 1.0, 1e-5, "home: level 1")
	assert_almost_eq(PainterTrees.lod_for(PainterTrees.HOME_SIZE * 2.0), 0.0, 1e-5)
	assert_true(PainterTrees.level_shown(1.0, 1))
	assert_false(PainterTrees.level_shown(1.0, 0))
	assert_true(PainterTrees.level_shown(0.5, 0) and PainterTrees.level_shown(0.5, 1), "a blend")
	assert_true(PainterTrees.level_shown(-3.0, 0), "far: level 0 only")


## painter-errors-fix: an event that takes every tree of a cell leaves the cell's entry with no
## nodes until it lets them go; a zoom change then (a new stroke level) must still reach the other
## cells and the event's own trees. It indexed the empty cell's nodes: an out-of-bounds error at
## every zoom change during a fire, which left the rest showing the old level.
func test_a_zoom_change_mid_event_reaches_every_cell_and_held_tree() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(1, 1), Vector2(8, 1)])}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := _painted(surfaces)
	var parent := Node3D.new()
	_map.add_child(parent)
	var actor := trees.take(Vector3(1, 0, 1), parent, false)
	assert_false(actor.is_empty(), "the tree is taken")
	var drawn: Array = [actor["nodes"]]
	var emptied := 0
	for cell: Vector2i in trees.cells:
		var nodes: Array = trees.cells[cell]["nodes"]
		if nodes.is_empty():
			emptied += 1
		else:
			drawn.append(nodes)
	assert_eq(emptied, 1, "its cell keeps its entry with no nodes while the event holds the tree")
	assert_eq(drawn.size(), 2, "the held tree and the other cell")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = PainterTrees.HOME_SIZE * 2.0
	_map.add_child(camera)
	camera.make_current()
	trees.call("_on_frame")
	var lod := PainterTrees.lod_for(camera.size)
	for nodes: Array in drawn:
		for k in range(2, 5):
			assert_eq(
				(nodes[k] as Node3D).visible,
				PainterTrees.level_shown(lod, k - 2),
				"stroke level %d at the new zoom" % (k - 2)
			)
	trees.drop_all([actor])
	surfaces.release()
