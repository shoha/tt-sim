extends GutTest

## Unit tests for GameMap.compute_aspect_corrected_size.
## Verifies that narrower-than-16:9 viewports produce a larger camera.size
## so the visible world width matches the 16:9 reference extent.


func test_reference_16_9_unchanged() -> void:
	var result = GameMap.compute_aspect_corrected_size(13.85, Vector2i(1920, 1080), 16.0 / 9.0)
	assert_almost_eq(result, 13.85, 0.001)


func test_wider_than_reference_unchanged() -> void:
	# 21:9 ultrawide — wider than 16:9, no correction needed
	var result = GameMap.compute_aspect_corrected_size(13.85, Vector2i(2560, 1080), 16.0 / 9.0)
	assert_almost_eq(result, 13.85, 0.001)


func test_4_3_scales_up() -> void:
	# 4:3: correction = (16/9) / (4/3) = 4/3
	var expected = 13.85 * (16.0 / 9.0) / (4.0 / 3.0)
	var result = GameMap.compute_aspect_corrected_size(13.85, Vector2i(1280, 960), 16.0 / 9.0)
	assert_almost_eq(result, expected, 0.001)


func test_16_10_scales_up() -> void:
	# 16:10: correction = (16/9) / (16/10) = 10/9
	var expected = 13.85 * 10.0 / 9.0
	var result = GameMap.compute_aspect_corrected_size(13.85, Vector2i(1920, 1200), 16.0 / 9.0)
	assert_almost_eq(result, expected, 0.001)


func test_zero_height_returns_input() -> void:
	var result = GameMap.compute_aspect_corrected_size(13.85, Vector2i(1920, 0), 16.0 / 9.0)
	assert_almost_eq(result, 13.85, 0.001)


func test_zero_width_returns_input() -> void:
	var result = GameMap.compute_aspect_corrected_size(13.85, Vector2i(0, 1080), 16.0 / 9.0)
	assert_almost_eq(result, 13.85, 0.001)


func test_narrow_viewport_preserves_horizontal_extent() -> void:
	# The visible world width = camera.size * aspect must be equal for 16:9 and 4:3
	var size_16_9 = GameMap.compute_aspect_corrected_size(13.85, Vector2i(1920, 1080), 16.0 / 9.0)
	var size_4_3 = GameMap.compute_aspect_corrected_size(13.85, Vector2i(1280, 960), 16.0 / 9.0)
	var width_16_9 = size_16_9 * (1920.0 / 1080.0)
	var width_4_3 = size_4_3 * (1280.0 / 960.0)
	assert_almost_eq(width_16_9, width_4_3, 0.01)
