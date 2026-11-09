extends GutTest

## WorldView (utils/world_view.gd): the world viewport is sized in output pixels while every
## position stays in canvas units (the 2D size override).


func _window(size: Vector2i, factor: float = 1.0) -> Window:
	var window := Window.new()
	window.content_scale_size = Vector2i(1920, 1080)
	window.content_scale_factor = factor
	window.size = size
	return window


func test_viewport_follows_the_output_from_1080p_to_4k() -> void:
	assert_eq(WorldView.pixel_size(Vector2(1920, 1080)), Vector2i(1920, 1080))
	assert_eq(WorldView.pixel_size(Vector2(2560, 1440)), Vector2i(2560, 1440))
	assert_eq(WorldView.pixel_size(Vector2(3840, 2160)), Vector2i(3840, 2160))
	# An ultrawide keeps the window's own pixels.
	assert_eq(WorldView.pixel_size(Vector2(3440, 1440)), Vector2i(3440, 1440))


func test_viewport_is_clamped_at_4k() -> void:
	assert_eq(WorldView.pixel_size(Vector2(5120, 2880)), Vector2i(3840, 2160))
	assert_eq(WorldView.pixel_size(Vector2(7680, 4320)), Vector2i(3840, 2160))


func test_small_windows_keep_the_1080p_class_render() -> void:
	# Under 1080p the window shows fewer pixels than are rendered, as before rendersize.
	assert_eq(WorldView.pixel_size(Vector2(1280, 720)), Vector2i(1920, 1080))
	# Interface size 1.4 shrinks the canvas, the render keeps its 1920x1080.
	assert_eq(WorldView.pixel_size(Vector2(1280, 720), 1.4), Vector2i(1920, 1080))
	assert_almost_eq(WorldView.canvas_units(Vector2(1280, 720), 1.4).x, 1371.4, 0.1)


func test_canvas_units_are_the_base_canvas_on_16_9() -> void:
	for size in [Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3840, 2160)]:
		assert_eq(WorldView.canvas_units(size), Vector2(1920, 1080), str(size))
	assert_eq(WorldView.canvas_units(Vector2(3440, 1440)).round(), Vector2(2580, 1080))


func test_pixel_scale_is_the_height_over_1080() -> void:
	assert_eq(WorldView.px_scale_for(1080.0), 1.0)
	assert_eq(WorldView.px_scale_for(1440.0), 4.0 / 3.0)
	assert_eq(WorldView.px_scale_for(2160.0), 2.0)


func test_layout_at_1080p_is_the_plain_viewport() -> void:
	var window := _window(Vector2i(1920, 1080))
	var container := SubViewportContainer.new()
	var viewport := SubViewport.new()
	container.add_child(viewport)
	add_child_autofree(container)
	WorldView.apply_layout(container, viewport, window)
	assert_eq(viewport.size, Vector2i(1920, 1080))
	assert_eq(viewport.size_2d_override, Vector2i.ZERO)
	assert_eq(container.scale, Vector2.ONE)
	assert_eq(WorldView.canvas_size(viewport), Vector2(1920, 1080))
	window.free()


func test_layout_at_4k_keeps_canvas_coordinates() -> void:
	var window := _window(Vector2i(3840, 2160))
	var container := SubViewportContainer.new()
	var viewport := SubViewport.new()
	container.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position = Vector3(0, 0, 5)
	viewport.add_child(camera)
	add_child_autofree(container)
	WorldView.apply_layout(container, viewport, window)
	assert_eq(viewport.size, Vector2i(3840, 2160))
	assert_eq(viewport.size_2d_override, Vector2i(1920, 1080))
	assert_true(viewport.size_2d_override_stretch)
	assert_eq(container.size, Vector2(3840, 2160))
	assert_almost_eq(container.scale.x, 0.5, 1e-6)
	# Positions, unprojection and the pixel scale: canvas units and 2 on the shaders' side.
	assert_eq(WorldView.canvas_size(viewport), Vector2(1920, 1080))
	assert_eq(camera.unproject_position(Vector3.ZERO), Vector2(960, 540))
	assert_eq(WorldView.px_scale(viewport), 2.0)
	window.free()


func test_layout_follows_a_window_resize() -> void:
	var window := _window(Vector2i(2560, 1440))
	var container := SubViewportContainer.new()
	var viewport := SubViewport.new()
	container.add_child(viewport)
	add_child_autofree(container)
	WorldView.apply_layout(container, viewport, window)
	assert_eq(viewport.size, Vector2i(2560, 1440))
	window.size = Vector2i(1920, 1080)
	WorldView.apply_layout(container, viewport, window)
	assert_eq(viewport.size, Vector2i(1920, 1080))
	assert_eq(viewport.size_2d_override, Vector2i.ZERO)
	assert_eq(container.scale, Vector2.ONE)
	window.free()
