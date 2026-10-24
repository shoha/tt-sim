extends GutTest

## The token ghost (scenes/board_token/token_ghost.gd): dressing, stripping, the rules for
## hidden and covered-by-water tokens, the rim, the draw-call budget, the saved setting and the
## opacity constants. What the shader draws is judged from render-job captures
## (tools/render_jobs/jobs/token_ghost.json), not here.

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TEMP_PATH := "user://test_token_ghost_settings.cfg"

var _was_enabled := true


func before_each() -> void:
	_was_enabled = TokenGhost.enabled
	TokenGhost.enabled = true


func after_each() -> void:
	TokenGhost.enabled = _was_enabled
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


func test_the_opacity_constants_are_the_shaders_defaults() -> void:
	# Read from the source: the headless renderer reports no uniform defaults.
	assert_almost_eq(_shader_default("ghost_alpha"), TokenGhost.FILL_ALPHA, 0.0001)
	assert_almost_eq(_shader_default("rim_alpha"), TokenGhost.RIM_ALPHA, 0.0001)


func _shader_default(uniform_name: String) -> float:
	var regex := RegEx.create_from_string("uniform float %s[^=]*=\\s*([0-9.]+);" % uniform_name)
	var found := regex.search(TokenGhost.SHADER.code)
	assert_not_null(found, "uniform %s in the shader" % uniform_name)
	return float(found.get_string(1)) if found != null else -1.0


func test_the_fill_is_a_quarter_to_a_third_less_opaque_than_the_prototype() -> void:
	# The prototype filled at 0.78; the covered part of the ghost was asked to be less opaque.
	assert_between(TokenGhost.FILL_ALPHA / 0.78, 0.66, 0.76)
	assert_gte(TokenGhost.FILL_ALPHA + TokenGhost.RIM_ALPHA, 0.95, "the rim stays solid")


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
	assert_true(ghost.get_shader_parameter("use_palette"))
	assert_eq(ghost.get_shader_parameter("palette"), palette)
	assert_eq(ghost.get_shader_parameter("ghost_alpha"), TokenGhost.FILL_ALPHA)


func test_a_pack_part_is_dressed_with_its_albedo() -> void:
	var part := _pack_part(Color(0.75, 0.2, 0.15))
	var token := _token([part])
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(part)
	assert_not_null(ghost)
	assert_true(ghost.get_shader_parameter("use_albedo"))
	assert_eq(ghost.get_shader_parameter("albedo_col"), Color(0.75, 0.2, 0.15))


func test_dressing_twice_keeps_the_same_overlay() -> void:
	var part := _avatar_part(_palette())
	var token := _token([part])
	TokenGhost.dress(token)
	var first := TokenGhost.overlay_of(part)
	TokenGhost.dress(token)
	assert_same(TokenGhost.overlay_of(part), first)


func test_new_colours_rebuild_the_overlay() -> void:
	var part := _avatar_part(_palette())
	var token := _token([part])
	TokenGhost.dress(token)
	var first := TokenGhost.overlay_of(part)
	var fresh := _palette()
	(part.material_override as ShaderMaterial).set_shader_parameter("palette", fresh)
	TokenGhost.dress(token)
	assert_not_same(TokenGhost.overlay_of(part), first)
	assert_eq(TokenGhost.overlay_of(part).get_shader_parameter("palette"), fresh)


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


func test_the_rim_is_gold_while_highlighted() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(part)
	assert_ne(ghost.get_shader_parameter("rim_color"), TokenGhost.SELECTED_RIM)
	token.add_highlight()
	assert_eq(ghost.get_shader_parameter("rim_color"), TokenGhost.SELECTED_RIM)
	assert_eq(ghost.get_shader_parameter("rim_strength"), 1.0)
	token.remove_highlight()
	assert_ne(ghost.get_shader_parameter("rim_color"), TokenGhost.SELECTED_RIM)


func test_a_token_dressed_while_highlighted_starts_gold() -> void:
	var part := _pack_part(Color.RED)
	var token := _token([part])
	token.is_highlighted = true
	TokenGhost.dress(token)
	assert_eq(TokenGhost.overlay_of(part).get_shader_parameter("rim_color"), TokenGhost.SELECTED_RIM)


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


# --- the saved setting -------------------------------------------------------------------


func test_the_setting_defaults_on_and_the_canopy_fade_defaults_off() -> void:
	assert_true(TokenGhost.DEFAULT_ENABLED)
	assert_false(CanopyFade.DEFAULT_ENABLED)


func test_the_menu_saves_and_shows_the_three_options() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	menu.token_ghost_check.set_pressed_no_signal(false)
	menu.occlusion_fade_check.set_pressed_no_signal(false)
	menu.canopy_fade_check.set_pressed_no_signal(true)
	menu._save_settings(TEMP_PATH)
	var config := ConfigFile.new()
	assert_eq(config.load(TEMP_PATH), OK)
	assert_eq(config.get_value("graphics", "token_ghost_enabled"), false)
	assert_eq(config.get_value("graphics", "occlusion_fade_enabled"), false)
	assert_eq(config.get_value("graphics", "canopy_fade_enabled"), true)
	SettingsSeeThrough.show_defaults(menu)
	assert_true(menu.token_ghost_check.button_pressed)
	assert_true(menu.occlusion_fade_check.button_pressed)
	assert_false(menu.canopy_fade_check.button_pressed)
	SettingsSeeThrough.show_saved(menu, config)
	assert_false(menu.token_ghost_check.button_pressed)
	assert_false(menu.occlusion_fade_check.button_pressed)
	assert_true(menu.canopy_fade_check.button_pressed)


func test_the_options_have_tooltips_and_the_menu_row_labels() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	for check in [menu.token_ghost_check, menu.occlusion_fade_check, menu.canopy_fade_check]:
		assert_ne(check.tooltip_text, "")
	assert_eq(
		(menu.token_ghost_check.get_parent().get_node("Label") as Label).text, "Token ghost"
	)
	assert_eq(
		(menu.canopy_fade_check.get_parent().get_node("Label") as Label).text, "Canopy fade"
	)
