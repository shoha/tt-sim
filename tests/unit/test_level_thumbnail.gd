extends GutTest

## Thumbnails are 320x180 whatever the source: wide frames are scaled to height
## and cropped at the sides, tall frames are scaled to width and cropped at the
## top and bottom, and the centre of the source ends up at the centre.


func _gradient(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	for y in range(height):
		for x in range(width):
			image.set_pixel(x, y, Color(float(x) / width, float(y) / height, 0.0))
	return image


func test_tall_source_is_cropped_to_16_by_9_around_the_centre() -> void:
	var out := LevelThumbnail.fit(_gradient(1920, 2043))
	assert_eq(out.get_size(), Vector2i(320, 180))
	assert_eq(out.get_format(), Image.FORMAT_RGB8)
	var centre := out.get_pixel(160, 90)
	assert_almost_eq(centre.r, 0.5, 0.02, "horizontal centre kept")
	assert_almost_eq(centre.g, 0.5, 0.02, "vertical centre kept")
	assert_lt(out.get_pixel(160, 0).g, 0.35, "top rows come from inside the source")


func test_wide_source_is_cropped_at_the_sides() -> void:
	var out := LevelThumbnail.fit(_gradient(2400, 600))
	assert_eq(out.get_size(), Vector2i(320, 180))
	assert_gt(out.get_pixel(0, 90).r, 0.15, "left columns come from inside the source")


func test_exact_aspect_only_scales() -> void:
	var out := LevelThumbnail.fit(_gradient(1280, 720))
	assert_eq(out.get_size(), Vector2i(320, 180))
	assert_almost_eq(out.get_pixel(0, 0).r, 0.0, 0.02)
