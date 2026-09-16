extends GutTest

## Painted swatches: sky gradients and preset swatches are the right size,
## cached per name, and never error for unknown names.


func test_sky_gradient_size_and_cache() -> void:
	var first := SwatchTextures.sky_gradient("clear_day")
	assert_eq(first.get_width(), SwatchTextures.SKY_SIZE)
	assert_eq(first.get_height(), SwatchTextures.SKY_SIZE)
	assert_same(first, SwatchTextures.sky_gradient("clear_day"), "cached per name")


func test_sky_gradient_top_and_ground_differ() -> void:
	var image := SwatchTextures.sky_gradient("sunset").get_image()
	var top := image.get_pixel(0, 0)
	var bottom := image.get_pixel(0, SwatchTextures.SKY_SIZE - 1)
	assert_ne(top, bottom)


func test_preset_swatch_size_and_cache() -> void:
	var first := SwatchTextures.preset_swatch("dungeon_dark")
	assert_eq(first.get_width(), SwatchTextures.SWATCH_SIZE)
	assert_same(first, SwatchTextures.preset_swatch("dungeon_dark"))


func test_unknown_names_produce_textures_without_errors() -> void:
	assert_not_null(SwatchTextures.sky_gradient("no_such_sky"))
	assert_not_null(SwatchTextures.preset_swatch("no_such_preset"))
