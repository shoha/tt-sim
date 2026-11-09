extends GutTest

## An avatar token draws its figure baked into one static mesh (AvatarFigureBake, perf audit
## F-tokens-2): one surface per part with the part's own material, the figure's pose and
## proportions baked in, shared between equal figures, rebaked on a stance or parts change,
## re-dressed on a colour change, and carrying the hidden fade and the shade.

const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}

var _old_scene: Node = null
var _scene: Node = null


## DraggingObject3D waits on the current scene when it enters the tree: a bare node stands in.
func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "AvatarBakeTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()


func _token(recipe: Dictionary = RECIPE) -> BoardToken:
	var token := AvatarTokenFactory.create(recipe, "Plum")
	_scene.add_child(token)
	return token


func _mesh_of(token: BoardToken) -> MeshInstance3D:
	return AvatarTokenFactory.view_of(token).figure_mesh()


func test_the_token_draws_one_mesh_with_a_surface_per_part() -> void:
	var token := _token()
	var view := AvatarTokenFactory.view_of(token)
	var meshes := TokenGhost.meshes_of(token.rigid_body)
	assert_eq(meshes.size(), 1, "one MeshInstance3D draws the figure")
	var mi := view.figure_mesh()
	assert_same(meshes[0], mi)
	assert_false(view.figure.is_inside_tree(), "the skinned figure stays off the tree")
	var parts := AvatarKit.figure_parts(view.figure)
	assert_eq(mi.mesh.get_surface_count(), parts.size(), "one surface per part")
	for i in mi.mesh.get_surface_count():
		var part_name := (mi.mesh as ArrayMesh).surface_get_name(i)
		var part := view.figure.find_child(part_name, true, false) as MeshInstance3D
		assert_not_null(part, part_name)
		assert_same(mi.get_surface_override_material(i), part.material_override, part_name)
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "keeps its shadow")


func test_the_bake_stands_on_the_ground_at_figure_height() -> void:
	var box := _mesh_of(_token()).mesh.get_aabb()
	assert_almost_eq(box.position.y, 0.0, 0.03, "soles on the origin (the ground rule)")
	assert_between(box.end.y, 1.4, 1.9, "height %.3f" % box.end.y)
	assert_lt(maxf(absf(box.position.x), box.end.x), 0.6, "arms down beside the body")


func test_equal_figures_share_the_bake_and_a_colour_change_keeps_it() -> void:
	var a := _token()
	var b := _token()
	assert_same(_mesh_of(a).mesh, _mesh_of(b).mesh, "same parts, proportions and stance")
	var mesh := _mesh_of(a).mesh
	var recolour := RECIPE.duplicate(true)
	recolour.colours.primary = 5
	AvatarTokenFactory.set_recipe(a, recolour)
	assert_same(_mesh_of(a).mesh, mesh, "a colour change keeps the geometry")
	var view := AvatarTokenFactory.view_of(a)
	var part := AvatarKit.figure_parts(view.figure)[0]
	var i := 0
	while (_mesh_of(a).mesh as ArrayMesh).surface_get_name(i) != String(part.name):
		i += 1
	assert_same(_mesh_of(a).get_surface_override_material(i), part.material_override)
	assert_ne(
		_mesh_of(a).get_surface_override_material(i),
		_mesh_of(b).get_surface_override_material(i),
		"the new colours are drawn"
	)


func test_a_stance_or_proportions_change_rebakes() -> void:
	var token := _token()
	var before := _mesh_of(token).mesh
	var sneaky := RECIPE.duplicate(true)
	sneaky.stance = "stance_sneaky"
	AvatarTokenFactory.set_recipe(token, sneaky)
	var crouched := _mesh_of(token).mesh
	assert_ne(crouched, before, "a new pose, a new bake")
	assert_lt(crouched.get_aabb().end.y, before.get_aabb().end.y, "a crouch is shorter")
	var taller := sneaky.duplicate(true)
	taller.proportions.height = 0.95
	AvatarTokenFactory.set_recipe(token, taller)
	assert_ne(_mesh_of(token).mesh, crouched, "new proportions, a new bake")


func test_hidden_fade_and_shade_reach_the_baked_mesh() -> void:
	var token := _token()
	token.set_visible_to_players(false)
	var mi := _mesh_of(token)
	assert_almost_eq(
		float(mi.get_instance_shader_parameter("hidden_fade")), AvatarTokenView.HIDDEN_FADE, 0.001
	)
	var changed := RECIPE.duplicate(true)
	changed.proportions.build = 0.9
	AvatarTokenFactory.set_recipe(token, changed)
	assert_almost_eq(
		float(_mesh_of(token).get_instance_shader_parameter("hidden_fade")),
		AvatarTokenView.HIDDEN_FADE,
		0.001,
		"a rebuilt figure keeps it"
	)
	token.set_visible_to_players(true)
	assert_almost_eq(float(_mesh_of(token).get_instance_shader_parameter("hidden_fade")), 0.0, 0.001)
	AvatarKit.set_shade(AvatarTokenFactory.view_of(token), 1.0)
	assert_almost_eq(float(_mesh_of(token).get_instance_shader_parameter("shade")), 1.0, 0.001)


func test_the_ghost_takes_the_figure_palette() -> void:
	var mi := _mesh_of(_token())
	var palette: Variant = TokenGhost.source_of(mi)
	assert_true(palette is Texture2D, "the avatar ghost reads the figure's palette")


func test_bake_matches_the_skinned_vertex_count() -> void:
	var kit := AvatarTokenFactory.kit()
	var figure := kit.build_figure(RECIPE)
	var baked := AvatarFigureBake.bake(figure)
	var i := 0
	for part in AvatarKit.figure_parts(figure):
		var count := 0
		for s in part.mesh.get_surface_count():
			count += part.mesh.surface_get_array_len(s)
		assert_eq(baked.surface_get_array_len(i), count, String(part.name))
		i += 1
	figure.free()
