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


func test_pictures_are_cached_per_size() -> void:
	var biome := _biome("alpine_meadow_summer_s1")
	assert_eq(BiomeThumbnail.of(biome, 28), BiomeThumbnail.of(biome, 28))
	assert_ne(BiomeThumbnail.of(biome, 28), BiomeThumbnail.of(biome, 52))
