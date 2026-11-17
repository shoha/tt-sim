extends GutTest

## Fire and the events under the Painted look (card painter-fire; docs/systems/painter.md "Fire and
## events"): an event takes a painted tree out of its cell for a pivot it moves and burns, and
## gives it back; the painted ground draws the persistent fire's bake and the burnt ground as its
## own role; Classic holds none of it.

const OAK := "temperate_forest_summer_s1/Tree_Oak_v0"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const BURN_SHADERS: Array[String] = [
	PainterTrees.STROKE_BURN_SHADER,
	PainterTrees.BLOCKIN_BURN_SHADER,
	PainterTrees.STROKE_BARE_BURN_SHADER,
	PainterTrees.BLOCKIN_BARE_BURN_SHADER,
]

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


func _scatter(points: Array) -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows(points)}})
	return scatter


func _paint() -> Array:
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := surfaces.trees() as PainterTrees
	trees.complete()
	return [surfaces, trees]


func _instances() -> int:
	var total := 0
	var root := _map.get_node_or_null(NodePath(PainterTrees.ROOT_NAME))
	for node in root.get_children():
		# (The masses' shadow twin shares node 0's MultiMesh: counted once.)
		var twin := (
			node is GeometryInstance3D
			and (node as GeometryInstance3D).cast_shadow
			== GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		)
		if not node.is_queued_for_deletion() and node is MultiMeshInstance3D and not twin:
			total += (node as MultiMeshInstance3D).multimesh.instance_count
	return total


func test_the_burn_shaders_parse_and_keep_the_tree_uniforms() -> void:
	for path: String in BURN_SHADERS:
		var names: Array = []
		for u: Dictionary in (load(path) as Shader).get_shader_uniform_list():
			names.append(u["name"])
		assert_has(names, "tree_tex", path)
		assert_has(names, "palette", path)
	for pair: Array in [[true, false], [true, true], [false, false], [false, true]]:
		var plain := PainterTrees.shader_path(pair[0], pair[1])
		var burning := PainterTrees.shader_path(pair[0], pair[1], true)
		assert_ne(plain, burning)
		assert_true(burning.ends_with("burn.gdshader"), burning)
	for path: String in [
		PainterTrees.STROKE_SHADER, PainterTrees.BLOCKIN_SHADER,
		PainterTrees.STROKE_BARE_SHADER, PainterTrees.BLOCKIN_BARE_SHADER
	]:
		var names: Array = []
		for u: Dictionary in (load(path) as Shader).get_shader_uniform_list():
			names.append(u["name"])
		assert_does_not_have(names, "burn", "%s carries no burn: Painted trees cost what they did" % path)


func test_a_tree_an_event_takes_leaves_its_cell_and_comes_back() -> void:
	var scatter := _scatter([Vector2(1, 1), Vector2(2, 1)])
	var made := _paint()
	var trees: PainterTrees = made[1]
	assert_eq(PainterTrees.of(scatter), trees, "the scatter names its painted host")
	var whole := _instances()
	var parent := Node3D.new()
	_map.add_child(parent)
	var actor := trees.take(Vector3(1, 0, 1), parent, false)
	assert_false(actor.is_empty(), "the painted tree is handed over")
	assert_eq(trees.held_count(), 1)
	var pivot: Node3D = actor["pivot"]
	assert_eq(pivot.get_parent(), parent)
	assert_eq(pivot.position, Vector3(1, 0, 1), "the pivot stands at the tree's foot")
	assert_eq(pivot.get_child_count(), 5, "its own five nodes")
	assert_eq(trees.take(Vector3(1, 0, 1), parent, false), {}, "no tree is taken twice")
	assert_eq(trees.take(Vector3(9, 0, 9), parent, false), {}, "nor one that is not drawn")
	var own := 0
	for node: MultiMeshInstance3D in pivot.get_children():
		own += node.multimesh.instance_count
		assert_eq(node.multimesh.get_instance_transform(0).origin, Vector3.ZERO, "about the pivot")
	assert_lt(_instances(), whole, "the cell no longer draws it")
	assert_eq(_instances() + own, whole, "its instances moved, none lost or doubled")
	trees.drop_all([actor])
	assert_eq(trees.held_count(), 0)
	assert_eq(_instances(), whole, "back in its cell")
	assert_true(pivot.is_queued_for_deletion())
	made[0].release()
	assert_null(PainterTrees.of(scatter), "Classic has no host")


func test_a_burning_tree_draws_with_the_burn_shaders_and_follows_a_retone() -> void:
	var scatter := _scatter([Vector2(1, 1)])
	var made := _paint()
	var trees: PainterTrees = made[1]
	var parent := Node3D.new()
	_map.add_child(parent)
	var actor := trees.take(Vector3(1, 0, 1), parent, true)
	assert_false(actor.is_empty())
	var materials: Array[ShaderMaterial] = []
	for node: MultiMeshInstance3D in (actor["pivot"] as Node3D).get_children():
		materials.append(node.material_override as ShaderMaterial)
	assert_eq(materials[0].shader.resource_path, PainterTrees.BLOCKIN_BURN_SHADER)
	assert_eq(materials[2].shader.resource_path, PainterTrees.STROKE_BURN_SHADER)
	assert_ne(materials[0], trees.materials()[0], "its own set, the cell's untouched")
	assert_eq(trees.materials()[0].shader.resource_path, PainterTrees.BLOCKIN_SHADER)
	trees.set_burn(actor, 0.9)
	var winter := PainterSheet.load_sheet("core")
	trees.retone(winter, "winter", 20.0)
	assert_eq(
		materials[0].shader.resource_path,
		PainterTrees.BLOCKIN_BARE_BURN_SHADER,
		"a bare season's burning tree takes the bare burn variant"
	)
	var palette: Variant = trees.materials()[0].get_shader_parameter(&"palette")
	assert_eq(materials[0].get_shader_parameter(&"palette"), palette)
	trees.drop_all([actor])
	made[0].release()


func test_a_held_tree_whose_row_left_is_erased_when_the_event_lets_go() -> void:
	var scatter := _scatter([Vector2(1, 1), Vector2(2, 1)])
	var made := _paint()
	var trees: PainterTrees = made[1]
	var parent := Node3D.new()
	_map.add_child(parent)
	var actor := trees.take(Vector3(1, 0, 1), parent, true)
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows([Vector2(2, 1)])}})
	trees.complete()
	assert_eq(trees.trees.size(), 2, "the held tree stays while the event plays")
	trees.drop_all([actor])
	assert_eq(trees.trees.size(), 1, "and goes with it")
	assert_eq(trees.held_count(), 0)
	made[0].release()


func test_the_ground_roles_know_burnt_ground() -> void:
	assert_eq(PainterGroundRoles.surface_role("ash"), "char", "the event fire's ash")
	assert_eq(
		PainterGroundRoles.biome_role("burnt_forest"), "ash", "its burnt biome is a biome ground"
	)
	assert_eq(PainterGroundRoles.biome_role("temperate_forest_summer_s1"), "floor")
	assert_eq(PainterGroundRoles.surface_role("forest_floor_litter"), "floor")
	assert_has(PainterGroundRoles.ROLES, "char")
	assert_eq(PainterGroundRoles.index("char"), 8, "the shader's role number, after the biome roles")
	assert_ne(PainterGroundRoles.index("char"), PainterGroundRoles.index("ash"))
	var burnt := PainterGroundRoles.char_of(Vector3(0.1, 0.3, 0.05))
	assert_gt(burnt.x, burnt.z, "warm, not the floor's green")
	assert_gt(burnt.x, burnt.y * 0.99, "red leads green")
	assert_lt(burnt.y, 0.3, "darker than the green it came from")
	var snow := PainterGroundRoles.char_of(Vector3(0.8, 0.85, 0.9))
	assert_lt(snow.x, 0.1, "the burnt patch on a snow floor stays dark")


func test_the_char_map_exists_only_for_a_document_with_burnt_ground() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "grass_meadow", "test", 7)
	assert_null(PainterSurfaces.char_image(doc), "a plain map has none")
	var n := doc.samples_x() * doc.samples_z()
	doc.biome_ids = PackedStringArray(["temperate_forest_summer_s1", "burnt_forest"])
	doc.biome_slots.resize(n)
	doc.biome_density.resize(n)
	for i in n:
		doc.biome_slots[i] = 2 if i < n / 2 else 0
		doc.biome_density[i] = 255
	assert_null(PainterSurfaces.char_image(doc), "a burnt biome alone is ash ground, not a scar")
	doc.surface_ids = PackedStringArray(["grass_meadow", "ash"])
	doc.surface_weights.resize(n * MapDocument.SURFACE_BYTES)
	doc.surface_weights.fill(0)
	for i in n:
		var burnt := i < n / 2
		doc.surface_weights[i * 4] = 1 if burnt else 0
		doc.surface_weights[n * 4 + i * 4] = 255
	var image := PainterSurfaces.char_image(doc)
	assert_not_null(image)
	assert_eq(image.get_size(), Vector2i(doc.samples_x(), doc.samples_z()))
	assert_gt(image.get_pixel(1, 1).r, 0.9, "scorched where the ash surface is")
	assert_eq(image.get_pixel(doc.samples_x() - 2, doc.samples_z() - 2).r, 0.0, "not elsewhere")


func test_a_painted_building_can_be_taken_and_burned_and_let_go() -> void:
	StructureRecipes.ensure_served()
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var plan := PackedVector2Array(
		[Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)]
	)
	doc.structures.append(Structure.make(1, "core:stone_house", plan, 5))
	var structures := AuthoredStructures.create(doc)
	_map.add_child(structures)
	var buildings := PainterBuildings.new()
	assert_true(buildings.paint(_map, STATE))
	var actor := buildings.take(structures.get_child(0))
	assert_false(actor.is_empty(), "a painted house hands over its painted parts")
	var nodes: Array = actor["nodes"]
	assert_gt(nodes.size(), 3)
	buildings.set_burn(actor, 0.8)
	for mi: MeshInstance3D in nodes:
		assert_eq(mi.get_instance_shader_parameter(&"burn"), 0.8, "%s burns" % mi.name)
	buildings.drop(actor)
	for mi: MeshInstance3D in nodes:
		assert_eq(mi.get_instance_shader_parameter(&"burn"), 0.0)
	assert_eq(buildings.take(autofree(Node3D.new())), {}, "an unpainted node hands over nothing")
	buildings.release()
	assert_eq(buildings.take(structures.get_child(0)), {}, "released: nothing painted")


func test_every_painted_fire_edit_still_finds_its_text() -> void:
	for path: String in FireVariants.EDITS:
		var code := FileAccess.get_file_as_string(path)
		for edit: Array in FireVariants.EDITS[path]:
			assert_true(code.contains(edit[0]), "%s still has: %s" % [path, edit[0]])


func test_classic_draws_the_original_fire_shaders_and_painted_the_variants() -> void:
	FireVariants.set_painted(false)
	for path: String in FireVariants.EDITS:
		assert_eq(FireVariants.shader_for(path), load(path), "Classic keeps %s" % path)
	FireVariants.set_painted(true)
	for path: String in FireVariants.EDITS:
		var variant := FireVariants.shader_for(path)
		var original := load(path) as Shader
		assert_ne(variant.code, original.code, "%s differs" % path)
		var names: Array = []
		for u: Dictionary in variant.get_shader_uniform_list():
			names.append(u["name"])
		var want: Array = []
		for u: Dictionary in original.get_shader_uniform_list():
			want.append(u["name"])
		assert_eq(names, want, "%s keeps its uniforms" % path)
	assert_true(FireVariants.variant(FireVariants.PUFF).code.contains(FireVariants.STEPPED))
	FireVariants.set_painted(false)


func test_the_painted_ground_mirrors_the_terrains_fire_bake_and_lets_go() -> void:
	PainterStateReset.classic()
	var terrain := ShaderMaterial.new()
	var painted := ShaderMaterial.new()
	var bake := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	FireLook.bind_glow(terrain, bake, Vector4(1, 2, 3, 4))
	FireLook.mirror_glow(painted, terrain)
	assert_eq(painted.get_shader_parameter("fire_present"), 1, "it takes the bake the terrain holds")
	assert_eq(painted.get_shader_parameter("fire_sim_rect"), Vector4(1, 2, 3, 4))
	FireLook.bind_glow(terrain, null, Vector4.ZERO)
	assert_eq(painted.get_shader_parameter("fire_present"), 0, "and follows the field letting go")
	FireLook.bind_glow(terrain, bake, Vector4(5, 6, 7, 8))
	assert_eq(painted.get_shader_parameter("fire_sim_rect"), Vector4(5, 6, 7, 8), "and a new bake")
	FireLook.unmirror_glow(painted)
	FireLook.bind_glow(terrain, bake, Vector4(9, 9, 9, 9))
	assert_eq(painted.get_shader_parameter("fire_sim_rect"), Vector4(5, 6, 7, 8), "no longer after")
	assert_true(FireLook.glow_mirrors.is_empty(), "Classic's bind_glow loops over nothing")
