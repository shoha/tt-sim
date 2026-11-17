extends GutTest

## The painted look's water (PainterWater, painter_water.gdshader and painter_waterfall.gdshader;
## docs/systems/painter.md "Water"): painting swaps the shader of the two shared materials (the
## water's and the fall's) and releasing puts Classic's shaders back with none of the sheet's
## parameters left; the parameters Classic reads (and the instance uniforms the network and
## Motion drive) survive the swap; a new elevation or mood re-tones the same materials; every
## tone is the sheet's; leaving Painted through PainterSurfaces restores everything.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}
const CLASSIC_WATER := "res://shaders/water.gdshader"
const CLASSIC_FALL := "res://shaders/waterfall.gdshader"

var _water_shader: Shader = null
var _fall_shader: Shader = null


func before_each() -> void:
	PainterStateReset.classic()
	PainterSheet.clear_cache()
	_water_shader = WaterGlbUtils.water_material().shader
	_fall_shader = AuthoredWater.fall_material().shader


func after_each() -> void:
	# A test that failed halfway leaves nothing swapped for the next one.
	WaterGlbUtils.water_material().shader = _water_shader
	AuthoredWater.fall_material().shader = _fall_shader


func test_painting_swaps_both_shared_materials_and_release_restores_them_exactly() -> void:
	var water := WaterGlbUtils.water_material()
	var fall := AuthoredWater.fall_material()
	assert_eq(water.shader.resource_path, CLASSIC_WATER, "Classic water to start from")
	assert_eq(fall.shader.resource_path, CLASSIC_FALL, "Classic fall to start from")
	var host := PainterWater.new()
	assert_true(host.paint(null, STATE))
	assert_true(host.is_active())
	assert_eq(water.shader.resource_path, PainterWater.SHADER)
	assert_eq(fall.shader.resource_path, PainterWater.FALL_SHADER)
	assert_true(water.has_meta(PainterWater.META))
	assert_true(fall.has_meta(PainterWater.META))
	assert_same(host.water_material(), water, "the very shared material, not a copy")
	assert_same(host.fall_material(), fall)
	host.release()
	assert_false(host.is_active())
	assert_eq(water.shader.resource_path, CLASSIC_WATER)
	assert_eq(fall.shader.resource_path, CLASSIC_FALL)
	assert_false(water.has_meta(PainterWater.META))
	assert_false(fall.has_meta(PainterWater.META))
	for uniform: StringName in PainterWater.tone_uniforms():
		assert_null(water.get_shader_parameter(uniform), "%s cleared on the water" % uniform)
		assert_null(fall.get_shader_parameter(uniform), "%s cleared on the fall" % uniform)


func test_a_missing_sheet_or_mood_paints_nothing() -> void:
	var host := PainterWater.new()
	assert_false(host.paint(null, {"sheet": "core", "mood": "no_such_mood"}))
	assert_false(host.is_active())
	assert_eq(WaterGlbUtils.water_material().shader.resource_path, CLASSIC_WATER)


func test_the_parameters_classic_reads_survive_a_swap_and_a_release() -> void:
	var water := WaterGlbUtils.water_material()
	water.set_shader_parameter(&"shimmer_strength", 0.77)
	var host := PainterWater.new()
	host.paint(null, STATE)
	assert_eq(float(water.get_shader_parameter(&"shimmer_strength")), 0.77, "kept while painted")
	host.release()
	assert_eq(float(water.get_shader_parameter(&"shimmer_strength")), 0.77, "kept after release")
	water.set_shader_parameter(&"shimmer_strength", null)


func test_painting_twice_keeps_the_first_classic_shaders() -> void:
	var host := PainterWater.new()
	host.paint(null, STATE)
	host.paint(null, {"sheet": "core", "mood": "dusk", "elevation": 8.0})
	host.release()
	assert_eq(WaterGlbUtils.water_material().shader.resource_path, CLASSIC_WATER)
	assert_eq(AuthoredWater.fall_material().shader.resource_path, CLASSIC_FALL)


func test_every_tone_is_the_sheets_and_a_new_elevation_retones_the_same_materials() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var host := PainterWater.new()
	host.paint(null, STATE)
	var water := host.water_material()
	var high := PainterWater.tones(sheet, "summer", 60.0)
	for uniform: StringName in high:
		assert_eq(water.get_shader_parameter(uniform), high[uniform], "%s is the sheet's" % uniform)
	host.paint(null, {"sheet": "core", "mood": "summer", "elevation": 6.0})
	assert_same(host.water_material(), water, "re-toned in place")
	var low := PainterWater.tones(sheet, "summer", 6.0)
	assert_eq(water.get_shader_parameter(&"p_mid"), low[&"p_mid"])
	assert_eq(water.get_shader_parameter(&"p_shade_mul"), low[&"p_shade_mul"])
	host.paint(null, {"sheet": "core", "mood": "dusk", "elevation": 6.0})
	var dusk := PainterWater.tones(sheet, "dusk", 6.0)
	assert_eq(water.get_shader_parameter(&"p_mid"), dusk[&"p_mid"], "a new mood re-tones too")
	assert_ne(dusk[&"p_mid"], high[&"p_mid"], "dusk's wash is not summer's")
	host.release()


func test_the_fall_follows_the_same_tones() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var host := PainterWater.new()
	host.paint(null, STATE)
	var tones := PainterWater.tones(sheet, "summer", 60.0)
	for uniform: StringName in PainterWater.FALL_UNIFORMS:
		assert_eq(host.fall_material().get_shader_parameter(uniform), tones[uniform], "%s" % uniform)
	host.release()


func test_the_shade_factor_is_a_soft_cooling_never_a_blackout() -> void:
	var sheet := PainterSheet.load_sheet("core")
	for mood in PainterSheet.MOODS:
		for elevation in [60.0, 6.0, -8.0]:
			var f := PainterWater.shade_factor(sheet, mood, elevation)
			for c in [f.x, f.y, f.z]:
				assert_between(c, 0.55, 1.0, "%s at %s" % [mood, elevation])


func test_winter_freezes_slow_water_and_summer_does_not() -> void:
	var sheet := PainterSheet.load_sheet("core")
	assert_eq(PainterWater.tones(sheet, "winter", 45.0)[&"p_ice_amt"], 1.0)
	assert_eq(PainterWater.tones(sheet, "summer", 45.0)[&"p_ice_amt"], 0.0)


func test_both_shaders_compile_with_the_uniforms_the_host_sets() -> void:
	for path: String in [PainterWater.SHADER, PainterWater.FALL_SHADER]:
		var shader := load(path) as Shader
		assert_not_null(shader, path)
		var names := PackedStringArray()
		for u: Dictionary in shader.get_shader_uniform_list():
			names.append(str(u["name"]))
		var wanted := PainterWater.tone_uniforms()
		if path == PainterWater.FALL_SHADER:
			wanted = PainterWater.FALL_UNIFORMS
		for uniform: StringName in wanted:
			assert_true(names.has(str(uniform)), "%s declares %s" % [path, uniform])


func test_the_surfaces_host_has_no_water_before_its_first_paint() -> void:
	var surfaces := PainterSurfaces.new()
	assert_null(surfaces.water(), "nothing before the first paint")
	surfaces.release()
	assert_eq(WaterGlbUtils.water_material().shader.resource_path, CLASSIC_WATER)
