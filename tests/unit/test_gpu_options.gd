extends GutTest

## The two GPU-cost options of card gpuoptions (2026-11-09): Shadow cascades (ShadowCascades) and
## Foliage edges (FoliageEdges). Both default to the game as it shipped before them, persist in
## settings.cfg's [graphics] section, and apply to the sun and the foliage materials.

const TMP_SETTINGS := "user://test_gpu_options_settings.cfg"
const MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")

var _saved_cascades: int
var _saved_edges: int
var _saved_eye: bool


func before_each() -> void:
	_saved_cascades = ShadowCascades.current
	_saved_edges = FoliageEdges.current
	_saved_eye = FoliageEdges.eye_smoothing


func after_each() -> void:
	ShadowCascades.current = _saved_cascades
	FoliageEdges.current = _saved_edges
	FoliageEdges.eye_smoothing = _saved_eye
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))


func test_defaults_are_the_shipped_look() -> void:
	assert_eq(ShadowCascades.DEFAULT, ShadowCascades.BLENDED)
	assert_eq(FoliageEdges.DEFAULT, FoliageEdges.SMOOTH)


func test_an_empty_settings_file_reads_the_defaults() -> void:
	var config := ConfigFile.new()
	assert_eq(ShadowCascades.stored(config), ShadowCascades.DEFAULT)
	assert_eq(FoliageEdges.stored(config), FoliageEdges.DEFAULT)


func test_a_stale_or_garbage_value_reads_the_default() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", ShadowCascades.KEY, 7)
	config.set_value("graphics", FoliageEdges.KEY, "fast")
	assert_eq(ShadowCascades.stored(config), ShadowCascades.DEFAULT)
	assert_eq(FoliageEdges.stored(config), FoliageEdges.DEFAULT)


func test_the_default_sun_is_the_sun_before_the_setting() -> void:
	var sun := DirectionalLight3D.new()
	ShadowCascades.apply_to(sun, ShadowCascades.DEFAULT)
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_eq(
		sun.directional_shadow_blend_splits, LevelEnvironmentManager.SUN_SHADOW_BLEND_SPLITS
	)
	sun.free()


func test_each_cascade_choice_sets_mode_and_blend() -> void:
	var sun := DirectionalLight3D.new()
	ShadowCascades.apply_to(sun, ShadowCascades.UNBLENDED)
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_false(sun.directional_shadow_blend_splits)
	ShadowCascades.apply_to(sun, ShadowCascades.SINGLE)
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_false(sun.directional_shadow_blend_splits)
	ShadowCascades.apply_to(sun, ShadowCascades.BLENDED)
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_true(sun.directional_shadow_blend_splits)
	sun.free()


func test_apply_in_reaches_the_suns_under_the_world_only() -> void:
	var world := Node3D.new()
	var sun := DirectionalLight3D.new()
	var lamp := OmniLight3D.new()
	world.add_child(sun)
	world.add_child(lamp)
	assert_eq(ShadowCascades.apply_in(world, ShadowCascades.SINGLE), 1)
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_eq(ShadowCascades.apply_in(null, ShadowCascades.SINGLE), 0)
	world.free()


func test_foliage_takes_the_antialiased_twin_only_when_smooth_under_msaa() -> void:
	assert_true(FoliageEdges.uses_antialiased_shader(Viewport.MSAA_4X, FoliageEdges.SMOOTH))
	assert_false(FoliageEdges.uses_antialiased_shader(Viewport.MSAA_4X, FoliageEdges.FAST))
	assert_false(
		FoliageEdges.uses_antialiased_shader(Viewport.MSAA_DISABLED, FoliageEdges.SMOOTH)
	)
	assert_false(FoliageEdges.uses_antialiased_shader(Viewport.MSAA_DISABLED, FoliageEdges.FAST))


func test_startup_reads_both_choices() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", ShadowCascades.KEY, ShadowCascades.UNBLENDED)
	config.set_value("graphics", FoliageEdges.KEY, FoliageEdges.FAST)
	SettingsGpuOptions.apply_startup(config)
	assert_eq(ShadowCascades.current, ShadowCascades.UNBLENDED)
	assert_eq(FoliageEdges.current, FoliageEdges.FAST)
	SettingsGpuOptions.apply_startup(ConfigFile.new())
	assert_eq(ShadowCascades.current, ShadowCascades.DEFAULT)
	assert_eq(FoliageEdges.current, FoliageEdges.DEFAULT)


func test_settings_menu_offers_saves_and_shows_both_choices() -> void:
	var menu: SettingsMenu = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	var cascades := menu.shadow_cascades_option
	var edges := menu.foliage_edges_option
	assert_eq(cascades.item_count, ShadowCascades.CHOICES.size())
	assert_eq(edges.item_count, FoliageEdges.CHOICES.size())
	for choice in ShadowCascades.CHOICES:
		assert_true(cascades.get_item_index(choice) >= 0, "cascades %d offered" % choice)
	for choice in FoliageEdges.CHOICES:
		assert_true(edges.get_item_index(choice) >= 0, "edges %d offered" % choice)
	assert_false(cascades.tooltip_text.is_empty(), "cascades tooltip")
	assert_false(edges.tooltip_text.is_empty(), "edges tooltip")
	SettingsGpuOptions.show_defaults(menu)
	assert_eq(cascades.get_selected_id(), ShadowCascades.DEFAULT)
	assert_eq(edges.get_selected_id(), FoliageEdges.DEFAULT)
	cascades.select(cascades.get_item_index(ShadowCascades.SINGLE))
	edges.select(edges.get_item_index(FoliageEdges.FAST))
	menu._save_settings(TMP_SETTINGS)
	var config := ConfigFile.new()
	assert_eq(config.load(TMP_SETTINGS), OK)
	assert_eq(config.get_value("graphics", ShadowCascades.KEY), ShadowCascades.SINGLE)
	assert_eq(config.get_value("graphics", FoliageEdges.KEY), FoliageEdges.FAST)
	SettingsGpuOptions.show_defaults(menu)
	SettingsGpuOptions.show_saved(menu, config)
	assert_eq(cascades.get_selected_id(), ShadowCascades.SINGLE)
	assert_eq(edges.get_selected_id(), FoliageEdges.FAST)
	SettingsGpuOptions.apply(menu, null)
	assert_eq(ShadowCascades.current, ShadowCascades.SINGLE)
	assert_eq(FoliageEdges.current, FoliageEdges.FAST)


## Eye view smoothing (card autoquality, 2026-11-10): on by default, saved and shown by the menu,
## and off keeps the eye view at the saved Antialiasing level instead of raising it to 4x.
func test_eye_smoothing_is_saved_and_off_keeps_the_saved_level() -> void:
	assert_true(FoliageEdges.EYE_DEFAULT, "the eye view raised MSAA before the setting")
	assert_true(FoliageEdges.stored_eye_smoothing(ConfigFile.new()))
	var garbage := ConfigFile.new()
	garbage.set_value("graphics", FoliageEdges.EYE_KEY, 3)
	assert_true(FoliageEdges.stored_eye_smoothing(garbage), "a non-bool reads the default")
	var menu: SettingsMenu = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	var check := menu.get_node("%EyeSmoothingCheck") as CheckButton
	assert_false(check.tooltip_text.is_empty(), "eye smoothing tooltip")
	SettingsGpuOptions.show_defaults(menu)
	assert_true(check.button_pressed)
	check.set_pressed_no_signal(false)
	menu._save_settings(TMP_SETTINGS)
	var config := ConfigFile.new()
	assert_eq(config.load(TMP_SETTINGS), OK)
	assert_eq(config.get_value("graphics", FoliageEdges.EYE_KEY), false)
	SettingsGpuOptions.show_defaults(menu)
	SettingsGpuOptions.show_saved(menu, config)
	assert_false(check.button_pressed, "the saved choice is shown")
	SettingsGpuOptions.apply(menu, null)
	assert_false(FoliageEdges.eye_smoothing)
	var vfx := VisualEffectsController.new()
	vfx._foliage_antialiasing_level = Viewport.MSAA_DISABLED
	vfx._eye_view_active = true
	assert_eq(vfx.effective_antialiasing_level(), Viewport.MSAA_DISABLED, "off: the saved level")
	FoliageEdges.eye_smoothing = true
	assert_eq(vfx.effective_antialiasing_level(), Viewport.MSAA_4X, "on: raised to 4x")
	vfx._foliage_antialiasing_level = Viewport.MSAA_8X
	assert_eq(vfx.effective_antialiasing_level(), Viewport.MSAA_8X, "a setting above 4x is kept")
	vfx.free()
	SettingsGpuOptions.apply_startup(config)
	assert_false(FoliageEdges.eye_smoothing, "startup reads the saved choice")


func test_ground_detail_is_a_saved_level_cap_with_an_off() -> void:
	var saved := GroundClipmapSetting.current
	assert_eq(GroundClipmapSetting.DEFAULT, 5, "every level by default")
	assert_eq(GroundClipmapSetting.stored(ConfigFile.new()), GroundClipmapSetting.DEFAULT)
	var config := ConfigFile.new()
	config.set_value("graphics", GroundClipmapSetting.KEY, 3)
	assert_eq(GroundClipmapSetting.stored(config), 3)
	config.set_value("graphics", GroundClipmapSetting.KEY, 9)
	assert_eq(GroundClipmapSetting.stored(config), GroundClipmapSetting.DEFAULT, "a stale value")
	var menu: SettingsMenu = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	var option := menu.ground_detail_option
	assert_eq(option.item_count, GroundClipmapSetting.CHOICES.size())
	for choice in GroundClipmapSetting.CHOICES:
		assert_true(option.get_item_index(choice) >= 0, "ground detail %d offered" % choice)
	assert_false(option.tooltip_text.is_empty())
	option.select(option.get_item_index(GroundClipmapSetting.OFF))
	menu._save_settings(TMP_SETTINGS)
	var file := ConfigFile.new()
	assert_eq(file.load(TMP_SETTINGS), OK)
	assert_eq(file.get_value("graphics", GroundClipmapSetting.KEY), GroundClipmapSetting.OFF)
	SettingsGpuOptions.apply(menu, null)
	assert_eq(GroundClipmapSetting.current, GroundClipmapSetting.OFF)
	GroundClipmapSetting.current = saved


func test_fast_edges_put_foliage_on_the_plain_cutout_under_msaa() -> void:
	var game_map: GameMap = preload("res://scenes/states/playing/game_map.tscn").instantiate()
	add_child_autofree(game_map)
	await wait_physics_frames(1)
	var vfx: VisualEffectsController = game_map.get("_visual_effects")
	var mat := ShaderMaterial.new()
	mat.shader = WindFoliage.get_shader_no_aa()
	var materials: Array[ShaderMaterial] = [mat]
	vfx._foliage_antialiasing_level = Viewport.MSAA_4X
	FoliageEdges.current = FoliageEdges.SMOOTH
	vfx._apply_antialiasing_variant(materials)
	assert_eq(mat.shader, WindFoliage.get_shader(), "smooth: the antialiased twin")
	FoliageEdges.current = FoliageEdges.FAST
	vfx._apply_antialiasing_variant(materials)
	assert_eq(mat.shader, WindFoliage.get_shader_no_aa(), "fast: the plain cutout")
