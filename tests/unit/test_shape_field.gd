extends GutTest

## ShapeField (scenes/ui/primitives/shape_field.gd): the one Shape field every two-shape brush
## pane builds. A TileField captioned "Shape" over two tiles at TILE_SIZE, the line shape first
## with the river's icon and the area shape second with the pond's, each with its tooltip; the
## Water and Fire panes both build theirs with it, so they cannot drift, and each pane's tiles
## follow its mode's shape without re-emitting.


func _tiles(field: TileField) -> Array[Button]:
	var out: Array[Button] = []
	for child in field.tiles.get_children():
		if child is Button:
			out.append(child as Button)
	return out


func test_the_field_is_a_shape_caption_over_line_then_area() -> void:
	var line := {"id": &"x_line", "label": "Line", "tooltip": "Draw one"}
	var area := {"id": &"x_area", "label": "Area", "tooltip": "Paint one"}
	var field := ShapeField.build("XShapeField", line, area)
	add_child_autofree(field)
	assert_eq(field.name, &"XShapeField")
	assert_eq(field.caption, ShapeField.CAPTION)
	assert_eq(field.tiles.columns, 2, "one row of two")
	var tiles := _tiles(field)
	assert_eq(tiles.size(), 2)
	assert_eq(tiles[0].name, &"x_line", "the line shape first")
	assert_eq(tiles[1].name, &"x_area")
	assert_eq(tiles[0].icon, IconButton.load_icon(ShapeField.LINE_ICON), "the river's picture")
	assert_eq(tiles[1].icon, IconButton.load_icon(ShapeField.AREA_ICON), "the pond's")
	assert_eq(tiles[0].tooltip_text, "Draw one")
	assert_eq(tiles[1].tooltip_text, "Paint one")
	for tile in tiles:
		assert_eq(tile.custom_minimum_size, ShapeField.TILE_SIZE)
	assert_eq(field.tiles.selected, &"", "the pane selects its mode's shape")


func test_water_and_fire_build_the_same_field() -> void:
	var water := WaterToolPane.new()
	var fire := FireToolPane.new()
	add_child_autofree(water)
	add_child_autofree(fire)
	var water_tiles := _tiles(water.shape_field)
	var fire_tiles := _tiles(fire.shape_field)
	assert_eq(water_tiles[0].name, &"water_river", "Water: River, the line shape, first")
	assert_eq(fire_tiles[0].name, &"fire_line", "Fire: Line first")
	for k in 2:
		assert_eq(water_tiles[k].icon, fire_tiles[k].icon, "tile %d: one picture" % k)
		assert_eq(water_tiles[k].custom_minimum_size, fire_tiles[k].custom_minimum_size)
	assert_eq(water.shape_field.caption, fire.shape_field.caption)
	assert_eq(water.shape_field.tiles.selected, &"water_river", "Water starts on River")
	assert_eq(fire.shape_field.tiles.selected, &"fire_area", "Fire starts on Area")


func test_a_pane_follows_tab_without_re_emitting() -> void:
	var fire := FireToolPane.new()
	add_child_autofree(fire)
	watch_signals(fire)
	fire.select_shape(FireBrush.Shape.LINE)
	assert_eq(fire.shape_field.tiles.selected, &"fire_line")
	assert_signal_not_emitted(fire, "shape_selected")
	fire.shape_field.tiles.selection_changed.emit(&"fire_area")
	assert_signal_emitted_with_parameters(fire, "shape_selected", [FireBrush.Shape.AREA])
