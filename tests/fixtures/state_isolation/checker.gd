extends GutTest

## The other half of the painter-test-reset proof: runs after leaker.gd in the same process and
## assumes a fresh painter state, by its own reads (not through PainterStateReset). It passes only
## when something put the state back between the two scripts.


func test_the_shared_water_materials_are_classic() -> void:
	var water := WaterGlbUtils.water_material()
	assert_eq(water.shader.resource_path, "res://shaders/water.gdshader")
	assert_false(water.has_meta(PainterWater.META))
	assert_eq(AuthoredWater.fall_material().shader.resource_path, "res://shaders/waterfall.gdshader")


func test_the_fire_and_token_flags_are_off_and_the_mirrors_empty() -> void:
	assert_true(FireLook.glow_mirrors.is_empty())
	assert_false(FireVariants.painted)
	assert_false(TokenGhost.painted)


func test_the_settings_statics_hold_their_defaults() -> void:
	assert_eq(RenderStyle.choice, RenderStyle.DEFAULT_CHOICE)
	assert_eq(FoliageLight.last_sun, Vector4(0.0, 1.0, 0.0, 1.0))
	assert_true(PainterBuildings.hand_drawn)
	assert_eq(FoliageDensityController.fraction, 1.0)
