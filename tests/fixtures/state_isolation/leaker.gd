extends GutTest

## Half of the painter-test-reset proof (tests/unit/test_painter_test_isolation.gd runs it in a
## child GUT process, first, then checker.gd): a script that deliberately leaves the painter's
## process-wide state painted and does not clean up. It is not named test_*, so no config's
## directory scan collects it.


func test_leave_the_painted_state_behind() -> void:
	WaterGlbUtils.water_material().shader = load("res://painter/shaders/painter_water.gdshader")
	AuthoredWater.fall_material().shader = load("res://painter/shaders/painter_waterfall.gdshader")
	WaterGlbUtils.water_material().set_meta(PainterWater.META, true)
	FireLook.glow_mirrors.append(ShaderMaterial.new())
	FireVariants.painted = true
	TokenGhost.painted = true
	RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
	FoliageLight.last_sun = Vector4(0.5, 0.5, 0.5, 0.5)
	FoliageDensityController.fraction = 0.5
	PainterBuildings.hand_drawn = false
	assert_true(FireVariants.painted, "the leak is in place")
