extends GutTest

## Painted swatches: sky gradients and preset swatches are the right size,
## cached per name, and never error for unknown names.


func test_sky_gradient_size_and_cache() -> void:
	var first := SwatchTextures.sky_gradient("clear_day")
	assert_eq(first.get_width(), SwatchTextures.SKY_SIZE)
	assert_eq(first.get_height(), SwatchTextures.SKY_SIZE)
	assert_same(first, SwatchTextures.sky_gradient("clear_day"), "cached per name")


func test_sky_gradient_top_and_ground_differ() -> void:
	var image := SwatchTextures.sky_gradient("night_sky").get_image()
	var top := image.get_pixel(0, 0)
	var bottom := image.get_pixel(0, SwatchTextures.SKY_SIZE - 1)
	assert_ne(top, bottom)


func test_hdri_keys_use_the_shipped_tile_and_preview() -> void:
	var tile := SwatchTextures.sky_gradient("clear_day")
	assert_eq(tile.get_width(), SwatchTextures.SKY_SIZE)
	assert_false(tile is ImageTexture, "shipped PNG, not painted")
	assert_same(tile, SwatchTextures.sky_gradient("clear_day"))
	var preview := SwatchTextures.sky_preview("clear_day")
	assert_eq(preview.get_width(), SwatchTextures.PREVIEW_WIDTH)
	assert_eq(preview.get_height(), SwatchTextures.PREVIEW_HEIGHT)
	assert_false(preview is ImageTexture)
	assert_same(preview, SwatchTextures.sky_preview("clear_day"))


func test_gradient_keys_paint_a_preview_strip() -> void:
	var preview := SwatchTextures.sky_preview("night_sky")
	assert_eq(preview.get_width(), SwatchTextures.PREVIEW_WIDTH)
	assert_eq(preview.get_height(), SwatchTextures.PREVIEW_HEIGHT)
	assert_true(preview is ImageTexture)
	var image := preview.get_image()
	assert_ne(image.get_pixel(0, 0), image.get_pixel(0, SwatchTextures.PREVIEW_HEIGHT - 1))
	assert_not_null(SwatchTextures.sky_preview("no_such_sky"))


func test_preset_swatch_size_and_cache() -> void:
	var first := SwatchTextures.preset_swatch("dungeon_dark")
	assert_eq(first.get_width(), SwatchTextures.SWATCH_SIZE)
	assert_same(first, SwatchTextures.preset_swatch("dungeon_dark"))


func test_unknown_names_produce_textures_without_errors() -> void:
	assert_not_null(SwatchTextures.sky_gradient("no_such_sky"))
	assert_not_null(SwatchTextures.preset_swatch("no_such_preset"))


func test_water_swatch_paints_deep_over_shallows_and_caches() -> void:
	var swatch := SwatchTextures.water_swatch("lagoon")
	assert_eq(swatch.get_width(), SwatchTextures.WATER_SWATCH_SIZE)
	assert_eq(swatch.get_height(), SwatchTextures.WATER_SWATCH_SIZE)
	var image := swatch.get_image()
	var deep: Color = WaterPresets.PALETTES["lagoon"]["water_color"]
	var shallows: Color = WaterPresets.PALETTES["lagoon"]["shore_color"]
	# RGBA8 pixels are 8-bit, so compare with the hex-quantisation tolerance.
	assert_true(
		WaterSettings.colors_match(image.get_pixel(2, 2), Color(deep.r, deep.g, deep.b, 1.0))
	)
	assert_true(
		WaterSettings.colors_match(
			image.get_pixel(2, SwatchTextures.WATER_SWATCH_SIZE - 3),
			Color(shallows.r, shallows.g, shallows.b, 1.0)
		)
	)
	assert_same(swatch, SwatchTextures.water_swatch("lagoon"), "cached per name")


func test_water_swatch_unknown_palette_is_grey() -> void:
	var image := SwatchTextures.water_swatch("no_such_palette").get_image()
	assert_true(WaterSettings.colors_match(image.get_pixel(0, 0), SwatchTextures.FALLBACK))
