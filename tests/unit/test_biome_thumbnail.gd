extends GutTest

## BiomeThumbnail: a biome's tile picture is a painted place, not the grey studio square the
## palette thumbnail is: sky at the top, the biome's own luminous ground at the foot, the
## assets kept between.


func _biome(id: String) -> Dictionary:
	return PaletteLibrary.biome(id)


func _chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


func test_the_picture_is_sky_over_ground_not_grey() -> void:
	var texture := BiomeThumbnail.of(_biome("temperate_forest_summer_s1"), 64)
	assert_not_null(texture)
	var image := texture.get_image()
	assert_eq(image.get_size(), Vector2i(64, 64))
	var sky := image.get_pixel(2, 2)
	assert_gt(sky.b, sky.r, "the top corner is sky blue")
	assert_gt(_chroma(sky), 0.1, "and not studio grey")
	var foot := image.get_pixel(2, 61)
	assert_gt(_chroma(foot), 0.1, "the foot is painted ground, not studio grey")


## A dull ground surface lifts into a luminous one at its own hue.
func test_the_ground_is_the_biomes_own_and_luminous() -> void:
	var savanna := BiomeThumbnail.ground_colour(_biome("savanna_summer_s1"))
	var meadow := BiomeThumbnail.ground_colour(_biome("grassland_meadow_summer_s1"))
	for ground in [savanna, meadow]:
		assert_true(ground.ok_hsl_l >= BiomeThumbnail.GROUND_LIGHTNESS.x - 0.01)
		assert_true(ground.ok_hsl_s >= BiomeThumbnail.GROUND_SATURATION - 0.01)
	assert_gt(meadow.g, meadow.r, "grass paints green")
	assert_gt(savanna.r, savanna.b, "savanna paints golden")


## The new-map dialog's strip: the landscape across a wide picture, rounded at its corners.
func test_a_strip_is_a_wide_landscape_with_rounded_corners() -> void:
	var size := Vector2i(168, 56)
	var image := BiomeThumbnail.strip(_biome("temperate_forest_summer_s1"), size).get_image()
	assert_eq(image.get_size(), size)
	assert_eq(image.get_pixel(0, 0).a, 0.0, "the corner is cut round")
	var sky := image.get_pixel(4, 4)
	assert_eq(sky.a, 1.0)
	assert_gt(sky.b, sky.r, "sky at the top of the strip's far end")
	assert_gt(_chroma(image.get_pixel(160, 52)), 0.1, "painted ground at its foot")


## Bare ground is the same landscape with nothing on it, its ground the bare surface's own:
## no raw noise swatch.
func test_bare_ground_is_a_painted_strip_with_nothing_on_it() -> void:
	var surfaces := PaletteLibrary.surfaces()
	var bare: Dictionary = surfaces.get(NewMap.BARE_SURFACE, {})
	var image := BiomeThumbnail.bare_strip(bare, Vector2i(168, 56)).get_image()
	var sky := image.get_pixel(84, 3)
	assert_gt(sky.b, sky.r, "sky above")
	var foot := image.get_pixel(84, 52)
	var row_beside := image.get_pixel(40, 52)
	assert_gt(_chroma(foot), 0.1, "luminous ground")
	assert_almost_eq(foot.g, row_beside.g, 0.05, "plain ground, not noise")


func test_pictures_are_cached_per_size() -> void:
	var biome := _biome("alpine_meadow_summer_s1")
	assert_eq(BiomeThumbnail.of(biome, 28), BiomeThumbnail.of(biome, 28))
	assert_ne(BiomeThumbnail.of(biome, 28), BiomeThumbnail.of(biome, 52))
