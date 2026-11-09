extends GutTest

## A painted flower's shade floor and cast-shadow pull (card foliagefix, PERFORMANCE.md "Flowers
## in shade"): the core library's flowers author floors three times brighter than the painted
## shade's default, so a flower in a cast shadow stayed near white. FoliageLight.flower_shade eases
## the floor's luminance toward the default's keeping its hue, WindFoliage applies it (and
## flower_shadow_pull) to painted flowers only.

const DAISY := Vector3(0.431, 0.42, 0.513)
const BELL := Vector3(0.307, 0.3, 0.551)


func _lum(c: Vector3) -> float:
	return c.dot(Vector3(0.2126, 0.7152, 0.0722))


func _sat(c: Vector3) -> float:
	return (maxf(c.x, maxf(c.y, c.z)) - minf(c.x, minf(c.y, c.z))) / _lum(c)


func _painted_mesh() -> Mesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var extras := {FoliageLight.EXTRA_KEY: FoliageLight.PAINTED}
	extras[FoliageLight.SHADE_KEY] = [0.307, 0.3, 0.551]
	material.set_meta("extras", extras)
	var box := BoxMesh.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	mesh.surface_set_material(0, material)
	return mesh


func _built(category: String, flower: bool) -> ShaderMaterial:
	var mesh := _painted_mesh()
	WindFoliage.apply_material(mesh, category, {}, flower)
	return mesh.surface_get_material(0) as ShaderMaterial


func test_strength_zero_keeps_the_authored_floor() -> void:
	assert_eq(FoliageLight.flower_shade(DAISY, 0.0), DAISY)


func test_full_strength_caps_the_luminance_at_the_default() -> void:
	for floor_tone in [DAISY, BELL]:
		var capped := FoliageLight.flower_shade(floor_tone, 1.0)
		assert_almost_eq(_lum(capped), _lum(FoliageLight.SHADE_DEFAULT), 0.01, str(floor_tone))


func test_luminance_falls_monotonically_with_strength() -> void:
	var last := _lum(BELL)
	for s in [0.25, 0.5, 0.75, 1.0]:
		var now := _lum(FoliageLight.flower_shade(BELL, s))
		assert_lt(now, last, "strength %s" % s)
		last = now


func test_hue_and_saturation_are_kept_not_greyed() -> void:
	var capped := FoliageLight.flower_shade(BELL, 1.0)
	assert_gt(capped.z, capped.x, "a bluebell's shade stays blue")
	assert_gt(_sat(capped), _sat(BELL), "a darker tone of the same hue is pushed, not left grey")


func test_a_floor_already_darker_than_the_default_is_never_lightened() -> void:
	var dark := Vector3(0.02, 0.05, 0.03)
	assert_eq(FoliageLight.flower_shade(dark, 1.0), dark)


func test_shadow_pull_runs_from_the_shader_default_to_one() -> void:
	assert_almost_eq(FoliageLight.flower_shadow_pull(0.0), FoliageLight.PAINT_SHADOW_DEFAULT, 0.0001)
	assert_almost_eq(FoliageLight.flower_shadow_pull(1.0), 1.0, 0.0001)


func test_a_painted_flower_takes_the_cap_and_the_pull() -> void:
	var material := _built("grass", true)
	var shade := material.get_shader_parameter(FoliageLight.SHADE_UNIFORM) as Vector3
	assert_eq(shade, FoliageLight.flower_shade(BELL, FoliageLight.FLOWER_SHADE_STRENGTH))
	assert_almost_eq(
		float(material.get_shader_parameter("foliage_paint_shadow")),
		FoliageLight.flower_shadow_pull(FoliageLight.FLOWER_SHADE_STRENGTH),
		0.0001
	)


func test_painted_grass_and_trees_keep_their_authored_floor() -> void:
	for category in ["grass", "tree"]:
		var material := _built(category, false)
		assert_eq(
			material.get_shader_parameter(FoliageLight.SHADE_UNIFORM) as Vector3, BELL, category
		)
		assert_null(material.get_shader_parameter("foliage_paint_shadow"), category)
