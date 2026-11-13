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
	# Summer at the reference sun paints the spike's own birch leaf as the middle tone.
	var birch_leaf: int = table["birch"]["leaf"]
	var mid := palette.get_pixel(15, birch_leaf * PainterTreeTones.VARIANTS + 1)
	var spike := PainterSheet.color_of_lch(PainterSheet.parse_color("oklch(0.76 0.135 124)"))
	assert_almost_eq(mid.g, spike.g, 0.08, "the birch's own green")
	var oak_leaf: int = table["oak"]["leaf"]
	assert_ne(
		palette.get_pixel(15, oak_leaf * 4 + 1), mid, "the species do not share one green"
	)
	var dusk: Image = PainterTreeTones.bake(sheet, "dusk", 10.0)["palette"]
	assert_ne(dusk.get_pixel(15, birch_leaf * 4 + 1), mid, "the mood moves the colour")


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
