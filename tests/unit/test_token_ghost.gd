extends GutTest

## The token ghost (scenes/board_token/token_ghost.gd): dressing, stripping, the rules for
## hidden and covered-by-water tokens, the rim, the draw-call budget, the saved setting and the
## opacity constants. What the shader draws is judged from render-job captures
## (tools/render_jobs/jobs/token_ghost.json), not here.

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TEMP_PATH := "user://test_token_ghost_settings.cfg"

var _was_enabled := true
var _was_painted := false
var _was_style := TokenGhost.Style.DOUBLE


func before_each() -> void:
	_was_enabled = TokenGhost.enabled
	_was_painted = TokenGhost.painted
	_was_style = TokenGhost.style
	TokenGhost.enabled = true
	TokenGhost.painted = false
	# The plain single line, whose colour is `line_colour` itself (a double stroke's is dark).
	TokenGhost.style = TokenGhost.Style.OUTLINE


func after_each() -> void:
	TokenGhost.enabled = _was_enabled
	TokenGhost.painted = _was_painted
	TokenGhost.style = _was_style
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _token(parts: Array[MeshInstance3D]) -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	for part in parts:
		body.add_child(part)
	add_child_autofree(token)
	return token


func _avatar_part(palette: Texture2D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	var mat := ShaderMaterial.new()
	mat.set_shader_parameter("palette", palette)
	part.material_override = mat
	return part


func _pack_part(colour: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	part.material_override = mat
	return part


func _palette() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))


# --- opacity constants -------------------------------------------------------------------


func test_the_style_constants_describe_an_outline() -> void:
	# The ghost is one line since painter-look-ghost2: about 2 px, and no fill at all.
	for style: int in TokenGhost.STYLE_PARAMS:
		var params: Dictionary = TokenGhost.STYLE_PARAMS[style]
		assert_between(
			(params.line_px as float) + (params.inner_px as float), 1.5, 4.5, "line width %d" % style
		)
		assert_false(params.has("fill_alpha"), "no fill, style %d" % style)
	assert_gt(TokenGhost.STYLE_PARAMS[TokenGhost.Style.DOUBLE].inner_px as float, 0.0)
	assert_false(TokenGhost.SHADER.code.contains("fill_alpha"), "the shader has no fill")


func _shader_default(uniform_name: String) -> float:
	var regex := RegEx.create_from_string("uniform float %s[^=]*=\\s*([0-9.]+);" % uniform_name)
	var found := regex.search(TokenGhost.SHADER.code)
	assert_not_null(found, "uniform %s in the shader" % uniform_name)
	return float(found.get_string(1)) if found != null else -1.0


func test_the_shader_declares_the_uniforms_the_ghost_sets() -> void:
	# Read from the source: the headless renderer reports no uniform defaults.
	for uniform_name in [
		"line_colour", "line_inner", "line_px", "inner_px", "wobble_px", "line_alpha"
	]:
		assert_true(
			TokenGhost.SHADER.code.contains(" %s" % uniform_name), "uniform %s" % uniform_name
		)


# --- dressing ----------------------------------------------------------------------------


func test_an_avatar_part_is_dressed_with_its_palette() -> void:
	var palette := _palette()
	var part := _avatar_part(palette)
	var token := _token([part])
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(part)
	assert_not_null(ghost)
	assert_eq(ghost.shader, TokenGhost.SHADER)
	assert_eq(ghost.render_priority, TokenGhost.RENDER_PRIORITY)
	assert_eq(ghost.get_meta(TokenGhost.SOURCE_META), palette, "dressed from its palette")
	var params: Dictionary = TokenGhost.STYLE_PARAMS[TokenGhost.style]
	assert_eq(ghost.get_shader_parameter("line_px"), params.line_px)


func test_a_pack_part_is_dressed_from_its_material() -> void:
	var part := _pack_part(Color(0.75, 0.2, 0.15))
	var token := _token([part])
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(part)
	assert_not_null(ghost)
	assert_eq(ghost.get_meta(TokenGhost.SOURCE_META), part.material_override)


func test_dressing_twice_keeps_the_same_overlay() -> void:
	var part := _avatar_part(_palette())
	var token := _token([part])
	TokenGhost.dress(token)
	var first := TokenGhost.overlay_of(part)
	TokenGhost.dress(token)
	assert_same(TokenGhost.overlay_of(part), first)


# --- the token's own bounds (a part of the token in front is not an occluder) --------------


func _offset_part(offset: Vector3, size: Vector3) -> MeshInstance3D:
	var part := _pack_part(Color.RED)
	(part.mesh as BoxMesh).size = size
	part.position = offset
	return part


func test_the_bounds_are_the_cylinder_round_every_part_in_the_bodys_frame() -> void:
	var a := _offset_part(Vector3(-1, 0.5, 0), Vector3(1, 1, 1))
	var b := _offset_part(Vector3(1, 1.5, 0), Vector3(1, 1, 1))
	var token := _token([a, b])
	token.rigid_body.position = Vector3(5, 0, 3)
	token.rigid_body.rotation.y = 1.0
	var bounds := TokenGhost.body_bounds(token.rigid_body, TokenGhost.meshes_of(token.rigid_body))
	assert_almost_eq(bounds.center as Vector3, Vector3(0, 1.0, 0), Vector3.ONE * 0.001)
	assert_almost_eq(bounds.half_height as float, 1.0, 0.001, "y from 0 to 2")
	# Farthest corner: (+-1.5, ., +-0.5) from the centre.
	assert_almost_eq(bounds.radius as float, sqrt(1.5 * 1.5 + 0.5 * 0.5), 0.001)


func test_every_mesh_carries_the_bounds_in_its_own_space() -> void:
	var a := _offset_part(Vector3(-1, 0.5, 0), Vector3(1, 1, 1))
	var b := _offset_part(Vector3(1, 1.5, 0), Vector3(1, 1, 1))
	b.scale = Vector3(2, 2, 2)
	var token := _token([a, b])
	TokenGhost.dress(token)
	for part in [a, b]:
		var ghost := TokenGhost.overlay_of(part)
		var extent: Vector2 = ghost.get_shader_parameter("bound_extent")
		assert_gt(extent.x, 0.0)
		assert_gt(extent.y, 0.0)
		# Back through the mesh's transform the centre and the body's up axis land where the
		# body's own frame says (a unit of body up is a unit long in the world here).
		var world_centre: Vector3 = part.global_transform * ghost.get_shader_parameter("bound_center")
		var bounds := TokenGhost.body_bounds(
			token.rigid_body, TokenGhost.meshes_of(token.rigid_body)
		)
		var body_centre: Vector3 = token.rigid_body.global_transform * (bounds.center as Vector3)
		assert_almost_eq(world_centre, body_centre, Vector3.ONE * 0.001)
		var up: Vector3 = part.global_transform.basis * ghost.get_shader_parameter("bound_up")
		assert_almost_eq(up.length(), 1.0, 0.001, "the body's scale, whatever the mesh's own")


func test_the_bounds_follow_the_body_not_its_scale() -> void:
	var part := _offset_part(Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	var token := _token([part])
	token.rigid_body.scale = Vector3(1.5, 1.5, 1.5)
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(part)
	var up: Vector3 = part.global_transform.basis * ghost.get_shader_parameter("bound_up")
	assert_almost_eq(up.length(), 1.5, 0.001, "world metres per body metre")
	var extent: Vector2 = ghost.get_shader_parameter("bound_extent")
	assert_almost_eq(extent.y, 0.5, 0.001, "the extent stays in body metres")


func test_a_token_made_off_the_tree_gets_its_bounds_once_it_enters_it() -> void:
	var part := _offset_part(Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.rigid_body = body
	body.add_child(part)
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(part)
	assert_not_null(ghost, "dressed at once")
	assert_eq(ghost.get_shader_parameter("bound_extent"), Vector2.ZERO, "no bounds yet")
	token.add_child(body)
	add_child_autofree(token)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt((ghost.get_shader_parameter("bound_extent") as Vector2).x, 0.0)
	assert_false(token.has_meta(TokenGhost.PENDING_META))


func test_the_margin_with_bounds_is_smaller_than_the_one_without() -> void:
	assert_lt(_shader_default("bound_gap"), _shader_default("min_gap"))


func test_the_ground_plane_is_the_least_squares_fit_of_the_hits() -> void:
	var points := PackedVector3Array()
	for p in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(-1, -1), Vector2(2, 3)]:
		points.append(Vector3(p.x, 0.3 * p.x - 0.2 * p.y + 1.5, p.y))
	points.append(Vector3.INF)  # a ray that missed the terrain
	var plane := TokenGhost.ground_plane(points)
	assert_almost_eq(plane.x, 0.3, 1e-5)
	assert_almost_eq(plane.y, -0.2, 1e-5)
	assert_almost_eq(plane.z, 1.5, 1e-5)
	assert_eq(plane.w, 1.0, "known")


func test_no_ground_plane_from_too_few_or_collinear_hits() -> void:
	var two := PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3.INF])
	assert_eq(TokenGhost.ground_plane(two), Vector4.ZERO)
	var line := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(2, 2, 2)])
	assert_eq(TokenGhost.ground_plane(line), Vector4.ZERO)


func test_the_ground_is_refitted_once_the_body_moves() -> void:
	var part := _offset_part(Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	var token := _token([part])
	TokenGhost.dress(token)
	var fitted: Dictionary = token.get_meta(TokenGhost.GROUND_META)
	assert_eq(fitted.at, token.rigid_body.global_position, "fitted where it was dressed")
	assert_eq(
		TokenGhost.overlay_of(part).get_shader_parameter("ground_plane"),
		Vector4.ZERO,
		"no terrain under it: unknown"
	)
	token.rigid_body.global_position += Vector3(TokenGhost.GROUND_REFIT_M * 0.5, 0, 0)
	TokenGhost.refresh_ground(get_tree())
	assert_eq(token.get_meta(TokenGhost.GROUND_META).at, fitted.at, "a nudge keeps the fit")
	token.rigid_body.global_position += Vector3(2, 0, 0)
	TokenGhost.refresh_ground(get_tree())
	assert_eq(
		token.get_meta(TokenGhost.GROUND_META).at,
		token.rigid_body.global_position,
		"a move refits"
	)


func test_the_feet_band_is_lower_than_the_cover_band() -> void:
	assert_true(TokenGhost.SHADER.code.contains("uniform vec4 ground_plane"))
	assert_gt(_shader_default("feet_band"), 0.0)
	assert_lt(_shader_default("feet_band"), _shader_default("ground_band"))


func test_new_colours_rebuild_the_overlay() -> void:
	var part := _avatar_part(_palette())
	var token := _token([part])
	TokenGhost.dress(token)
	var first := TokenGhost.overlay_of(part)
	var fresh := _palette()
	(part.material_override as ShaderMaterial).set_shader_parameter("palette", fresh)
	TokenGhost.dress(token)
	assert_not_same(TokenGhost.overlay_of(part), first)
	assert_eq(TokenGhost.overlay_of(part).get_meta(TokenGhost.SOURCE_META), fresh)


func test_a_part_of_someone_elses_overlay_is_left_alone() -> void:
	var part := _pack_part(Color.RED)
	var own := ShaderMaterial.new()
	part.material_overlay = own
	_token([part])
	TokenGhost.set_enabled(false, get_tree())
	assert_same(part.material_overlay, own, "only our own overlays are stripped")
	assert_null(TokenGhost.overlay_of(part))


func test_the_glow_the_marker_and_a_placeholder_are_not_dressed() -> void:
	var glow := SelectionGlowRenderer.new()
	var marker := SubmergedMarker.new()
	var placeholder := Node3D.new()
	placeholder.name = "PlaceholderModel"
	var holder := _pack_part(Color.BLUE)
	placeholder.add_child(holder)
	var body := RigidBody3D.new()
	body.add_child(glow)
	body.add_child(marker)
	body.add_child(placeholder)
	var found := TokenGhost.meshes_of(body)
	assert_does_not_have(found, holder)
	body.free()


# --- rules -------------------------------------------------------------------------------


func test_turning_the_setting_off_strips_and_on_dresses_every_token() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	TokenGhost.dress(token)
	assert_not_null(TokenGhost.overlay_of(part))
	TokenGhost.set_enabled(false, get_tree())
	assert_null(TokenGhost.overlay_of(part), "off strips the overlay")
	assert_false(TokenGhost.enabled)
	TokenGhost.set_enabled(true, get_tree())
	assert_not_null(TokenGhost.overlay_of(part), "on dresses the token again")


func test_a_token_made_while_the_setting_is_off_is_not_dressed() -> void:
	TokenGhost.enabled = false
	var part := _pack_part(Color.RED)
	var token := _token([part])
	TokenGhost.dress(token)
	assert_null(TokenGhost.overlay_of(part))


func test_a_token_hidden_from_players_has_no_ghost_until_shown() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	TokenGhost.dress(token)
	token.is_visible_to_players = false
	TokenGhost.dress(token)
	assert_null(TokenGhost.overlay_of(part), "hidden: no ghost")
	token.is_visible_to_players = true
	TokenGhost.dress(token)
	assert_not_null(TokenGhost.overlay_of(part), "shown again: the ghost returns")


func test_a_trimmed_token_has_no_ghost() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	token.set_meta(TokenGhost.TRIMMED_META, true)
	TokenGhost.dress(token)
	assert_null(TokenGhost.overlay_of(part))


func test_the_line_is_gold_while_highlighted() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(part)
	assert_ne(ghost.get_shader_parameter("line_colour"), TokenGhost.SELECTED_RIM)
	var plain_width: float = ghost.get_shader_parameter("line_px")
	token.add_highlight()
	assert_eq(ghost.get_shader_parameter("line_colour"), TokenGhost.SELECTED_RIM)
	assert_gt(ghost.get_shader_parameter("line_px") as float, plain_width, "a selected line is wider")
	token.remove_highlight()
	assert_ne(ghost.get_shader_parameter("line_colour"), TokenGhost.SELECTED_RIM)
	assert_eq(ghost.get_shader_parameter("line_px"), plain_width)


func test_a_token_dressed_while_highlighted_starts_gold() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	token.is_highlighted = true
	TokenGhost.dress(token)
	assert_eq(
		TokenGhost.overlay_of(part).get_shader_parameter("line_colour"), TokenGhost.SELECTED_RIM
	)


# --- the line's colour (the token's own most vivid colour) ----------------------------------


func test_the_line_takes_the_hue_of_the_tokens_most_vivid_colour() -> void:
	var part := _pack_part(Color(0.1, 0.2, 0.8))
	var token := _token([part])
	TokenGhost.dress(token)
	var line: Color = TokenGhost.overlay_of(part).get_shader_parameter("line_colour")
	assert_almost_eq(line.h, Color(0.1, 0.2, 0.8).h, 0.02, "the token's blue")
	assert_gte(line.v, 0.92, "bright enough to read")
	assert_gte(line.s, 0.6, "and saturated")


func test_every_part_of_a_token_shares_one_line_colour() -> void:
	var red := _pack_part(Color(0.9, 0.1, 0.1))
	var grey := _pack_part(Color(0.5, 0.5, 0.5))
	var token := _token([red, grey])
	TokenGhost.dress(token)
	assert_eq(
		TokenGhost.overlay_of(red).get_shader_parameter("line_colour"),
		TokenGhost.overlay_of(grey).get_shader_parameter("line_colour"),
		"the vivid red stands for the whole token"
	)


func test_a_double_stroke_is_a_dark_outer_line_over_a_light_inner_one() -> void:
	var colours := TokenGhost.stroke_colours(Color(0.2, 0.7, 0.3), false, true)
	assert_lt((colours.line as Color).v, 0.4, "the outer line is dark")
	assert_gt((colours.inner as Color).v, 0.9, "the inner line is light")
	assert_gt((colours.inner as Color).s, 0.0)
	var gold := TokenGhost.stroke_colours(Color(0.2, 0.7, 0.3), true, true)
	assert_almost_eq((gold.inner as Color).h, TokenGhost.SELECTED_RIM.h, 0.02, "gold stays gold")


func test_the_line_avoids_the_leaf_green_when_the_token_has_another_vivid_colour() -> void:
	var green := Color(0.1, 0.95, 0.1)
	var colours := PackedColorArray([green, Color(0.9, 0.25, 0.5)])
	var plain := TokenColours.vivid(colours)
	var line := TokenColours.vivid(colours, true)
	assert_almost_eq(plain.h, green.h, 0.02, "the pin keeps the green")
	assert_almost_eq(line.h, Color(0.9, 0.25, 0.5).h, 0.02, "the line takes the pink")
	var only_green := TokenColours.vivid(PackedColorArray([green]), true)
	assert_almost_eq(only_green.h, green.h, 0.02, "a green token stays green")


func test_a_grey_token_keeps_a_grey_line() -> void:
	var line := TokenGhost.readable(Color(0.5, 0.5, 0.5))
	assert_lt(line.s, 0.15)
	assert_gte(line.v, 0.92)


# --- the outline variants ---------------------------------------------------------------------


func test_each_variant_sets_its_own_line() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	TokenGhost.set_style(TokenGhost.Style.DOUBLE, get_tree())
	TokenGhost.dress(token)
	assert_gt(TokenGhost.overlay_of(part).get_shader_parameter("inner_px") as float, 0.0)
	TokenGhost.set_style(TokenGhost.Style.OUTLINE, get_tree())
	var plain := TokenGhost.overlay_of(part)
	assert_eq(plain.get_shader_parameter("inner_px"), 0.0, "one plain line")
	assert_eq(plain.get_shader_parameter("wobble_px"), 0.0)
	TokenGhost.set_style(TokenGhost.Style.DRAWN, get_tree())
	assert_gt(TokenGhost.overlay_of(part).get_shader_parameter("wobble_px") as float, 0.0)


# --- the mask pass (one line round the union of the meshes) -------------------------------------


func test_every_overlay_carries_the_shared_mask_pass_drawn_before_it() -> void:
	var a := _pack_part(Color.RED)
	var b := _pack_part(Color.BLUE)
	var token := _token([a, b])
	TokenGhost.dress(token)
	var first := TokenGhost.overlay_of(a)
	var second := TokenGhost.overlay_of(b)
	assert_not_null(first.next_pass, "the mask pass")
	assert_same(first.next_pass, second.next_pass, "one material for every mesh")
	assert_same(first.next_pass, TokenGhost.mask_material())
	assert_lt(
		(first.next_pass as Material).render_priority, first.render_priority, "the mask comes first"
	)
	assert_eq((first.next_pass as ShaderMaterial).shader, TokenGhost.MASK_SHADER)
	assert_true(TokenGhost.MASK_SHADER.code.contains("DEPTH"), "it writes depth")
	assert_true(TokenGhost.SHADER.code.contains("DEPTH"), "and the line stays just short of it")


# --- the draw-call budget ----------------------------------------------------------------


func test_the_budget_keeps_the_highlighted_then_the_nearest() -> void:
	var candidates: Array[Dictionary] = [
		{"id": 1, "highlighted": false, "distance": 10.0},
		{"id": 2, "highlighted": false, "distance": 500.0},
		{"id": 3, "highlighted": true, "distance": 900.0},
		{"id": 4, "highlighted": false, "distance": 20.0},
	]
	var kept := TokenGhost.allowed(candidates, 2)
	assert_eq(kept.keys().size(), 2)
	assert_true(kept.has(3), "the highlighted token always stays")
	assert_true(kept.has(1), "then the nearest the screen centre")
	assert_eq(TokenGhost.allowed(candidates, 10).keys().size(), 4, "within budget: all stay")


func test_the_budget_trims_the_extra_tokens_on_screen_and_restores_them() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 40.0
	add_child_autofree(camera)
	camera.global_position = Vector3(0, 10, 10)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var tokens: Array[BoardToken] = []
	var extra := 4
	for i in TokenGhost.BUDGET_TOKENS + extra:
		var token := _token([_pack_part(Color.RED)])
		token.rigid_body.position = Vector3(float(i % 8) - 4.0, 0.0, float(i / 8) - 1.0)
		tokens.append(token)
	TokenGhost.refresh_all(get_tree())
	TokenGhost.apply_budget(get_tree(), camera)
	var trimmed := 0
	for token in tokens:
		if token.has_meta(TokenGhost.TRIMMED_META):
			trimmed += 1
	assert_eq(trimmed, extra, "only the tokens past the budget go undressed")
	for token in tokens:
		var part := TokenGhost.meshes_of(token.rigid_body)[0]
		assert_eq(
			TokenGhost.overlay_of(part) == null, token.has_meta(TokenGhost.TRIMMED_META)
		)
	for i in extra:
		tokens[i].remove_from_group(BoardToken.GROUP_NAME)
	await get_tree().process_frame
	TokenGhost.apply_budget(get_tree(), camera)
	for token in tokens.slice(extra):
		assert_false(token.has_meta(TokenGhost.TRIMMED_META), "back within budget: all dressed")


## A pass that would see what the last one saw (camera, tokens, highlights) is skipped: a mark
## cleared by hand stays cleared until the camera or a token moves (perfaudit F-tokens-6).
func test_the_budget_skips_a_pass_when_nothing_moved() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 40.0
	add_child_autofree(camera)
	camera.global_position = Vector3(0, 10, 10)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var tokens: Array[BoardToken] = []
	for i in TokenGhost.BUDGET_TOKENS + 2:
		var token := _token([_pack_part(Color.RED)])
		token.rigid_body.position = Vector3(float(i % 8) - 4.0, 0.0, float(i / 8) - 1.0)
		tokens.append(token)
	TokenGhost.apply_budget(get_tree(), camera)
	var trimmed := func(t: BoardToken) -> bool: return t.has_meta(TokenGhost.TRIMMED_META)
	var marked := tokens.filter(trimmed)
	assert_eq(marked.size(), 2, "setup: two past the budget")
	marked[0].remove_meta(TokenGhost.TRIMMED_META)
	TokenGhost.apply_budget(get_tree(), camera)
	assert_false(marked[0].has_meta(TokenGhost.TRIMMED_META), "nothing moved: the pass is skipped")
	camera.global_position += Vector3(0.01, 0, 0)
	TokenGhost.apply_budget(get_tree(), camera)
	assert_true(marked[0].has_meta(TokenGhost.TRIMMED_META), "the camera moved: the pass runs")
	marked[0].remove_meta(TokenGhost.TRIMMED_META)
	tokens[0].rigid_body.position += Vector3(0.0, 0.0, 0.01)
	TokenGhost.apply_budget(get_tree(), camera)
	assert_true(marked[0].has_meta(TokenGhost.TRIMMED_META), "a token moved: the pass runs")


# --- the saved setting -------------------------------------------------------------------


func test_the_setting_defaults_on() -> void:
	assert_true(TokenGhost.DEFAULT_ENABLED)


func test_the_menu_saves_and_shows_the_option() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	menu.token_ghost_check.set_pressed_no_signal(false)
	menu._save_settings(TEMP_PATH)
	var config := ConfigFile.new()
	assert_eq(config.load(TEMP_PATH), OK)
	assert_eq(config.get_value("graphics", "token_ghost_enabled"), false)
	assert_false(config.has_section_key("graphics", "occlusion_fade_enabled"), "key retired")
	assert_false(config.has_section_key("graphics", "canopy_fade_enabled"), "key retired")
	SettingsSeeThrough.show_defaults(menu)
	assert_true(menu.token_ghost_check.button_pressed)
	SettingsSeeThrough.show_saved(menu, config)
	assert_false(menu.token_ghost_check.button_pressed)


func test_a_settings_file_with_the_retired_fade_keys_still_loads() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	var config := ConfigFile.new()
	config.set_value("graphics", "occlusion_fade_enabled", false)
	config.set_value("graphics", "canopy_fade_enabled", true)
	config.set_value("graphics", "token_ghost_enabled", false)
	SettingsSeeThrough.show_saved(menu, config)
	assert_false(menu.token_ghost_check.button_pressed)
	assert_false(menu.has_node("%OcclusionFadeCheck"), "no row for the retired fade")
	assert_false(menu.has_node("%CanopyFadeCheck"), "no row for the canopy window")


func test_the_option_has_a_tooltip_and_the_menu_row_label() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	assert_ne(menu.token_ghost_check.tooltip_text, "")
	assert_eq(
		(menu.token_ghost_check.get_parent().get_node("Label") as Label).text, "Token ghost"
	)
