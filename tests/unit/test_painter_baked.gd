extends GutTest

## The painted look's baked textures (PainterBaked, painter/baked/*.res): every file holds the base
## images its generator draws (so the mipmaps cut from them are the generator's too), and a changed
## brush or layout fails here until tools/bake_painter.gd is run again.


func test_every_baked_file_is_what_its_generator_draws() -> void:
	for array_name in PainterBaked.names():
		var path := PainterBaked.file_path(array_name)
		assert_true(ResourceLoader.exists(path), "%s has a baked file" % array_name)
		var strip := load(path) as Image if ResourceLoader.exists(path) else null
		if strip == null:
			continue
		var drawn := PainterBaked.generate(array_name)
		var want := PainterBaked.stack(drawn)
		assert_eq(strip.get_size(), want.get_size(), "%s: size" % array_name)
		assert_eq(strip.get_format(), want.get_format(), "%s: format" % array_name)
		assert_eq(strip.get_data(), want.get_data(), "%s: run tools/bake_painter.gd" % array_name)


func test_a_layer_cut_from_the_strip_has_the_generators_mipmaps() -> void:
	var drawn := PainterBaked.generate(PainterBaked.TREE_BRUSHES)
	var strip := PainterBaked.stack(drawn)
	var size := strip.get_width()
	for layer in [0, 5, drawn.size() - 1]:
		var image := strip.get_region(Rect2i(0, layer * size, size, size))
		image.generate_mipmaps()
		assert_eq(image.get_data(), drawn[layer].get_data(), "layer %d with its mipmaps" % layer)


func test_a_baked_array_loads_with_the_layers_of_its_generator() -> void:
	for array_name in PainterBaked.names():
		var baked := PainterBaked.load_array(array_name)
		assert_not_null(baked, array_name)
		if baked == null:
			continue
		var drawn := PainterBaked.generate(array_name)
		assert_eq(baked.get_layers(), drawn.size(), "%s: layers" % array_name)
		assert_eq(baked.get_width(), drawn[0].get_width(), "%s: size" % array_name)
		assert_eq(baked.get_format(), drawn[0].get_format(), "%s: format" % array_name)


func test_the_tuft_names_cover_every_aspect_the_atlas_rounds_to() -> void:
	var names := PainterBaked.names()
	for half_w in [0.7, 0.8, 1.0, 1.3, 1.8, 2.2, 2.5]:
		var drawn := PainterTuftAtlas.drawn_width(half_w)
		assert_true(
			names.has(PainterBaked.tuft_name(drawn)), "half width %.2f has a baked layout" % half_w
		)


func test_a_name_without_a_file_is_drawn_not_loaded() -> void:
	assert_null(PainterBaked.load_array("not_baked"))
	assert_eq(PainterBaked.generate("not_baked").size(), 0)
