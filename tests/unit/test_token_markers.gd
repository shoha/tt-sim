extends GutTest

## The top-down token pin (TokenMarkers) and its portrait atlas (TokenPortraits): the rules that
## need no renderer. The fade with pitch is in test_camera_pitch.gd.


func _pin_mesh() -> ArrayMesh:
	# A "chunky" model: boxes with a colour per vertex, one tan, one blue.
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)]
	)
	var colours := PackedColorArray(
		[
			Color(0.62, 0.38, 0.22),
			Color(0.62, 0.38, 0.22),
			Color(0.62, 0.38, 0.22),
			Color(0.35, 0.45, 0.75),
			Color(0.35, 0.45, 0.75)
		]
	)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	return mesh


# --- the pin ---


func test_a_pin_is_never_drawn_for_a_token_the_players_cannot_see() -> void:
	assert_eq(TokenMarkers.pin_alpha(1.0, true, true, false), 1.0, "a visible token")
	assert_eq(TokenMarkers.pin_alpha(1.0, false, true, false), 0.0, "hidden, for a player")
	assert_eq(TokenMarkers.pin_alpha(1.0, false, false, false), 0.0, "hidden and not drawn")
	var dim := TokenMarkers.pin_alpha(1.0, false, true, true)
	assert_almost_eq(dim, 0.4, 0.0001, "hidden, the GM's dim")
	assert_eq(TokenMarkers.pin_alpha(1.0, true, false, true), 0.0, "a body that is not drawn")
	assert_almost_eq(TokenMarkers.pin_alpha(0.5, true, true, false), 0.5, 0.0001, "the fade-in")


func test_the_pin_head_keeps_its_pixel_size_at_every_zoom() -> void:
	# 20 m across 1000 px: 44 px is 0.88 m; twice the view, twice the metres.
	assert_almost_eq(TokenMarkers.head_metres(20.0, 1000.0), 0.88, 0.0001)
	assert_almost_eq(TokenMarkers.head_metres(40.0, 1000.0), 1.76, 0.0001)
	var px := TokenMarkers.HEAD_PX
	assert_almost_eq(TokenMarkers.head_metres(20.0, 1000.0) / 20.0 * 1000.0, px, 0.0001)
	assert_between(px, 40.0, 48.0, "the owner: much bigger than the 24 px that was unreadable")


# --- hover and click ---


func test_the_head_centre_stands_above_the_tip_on_screen() -> void:
	var tip := Vector2(300.0, 200.0)
	var centre := TokenMarkers.pin_head_centre(tip)
	assert_almost_eq(centre.x, 300.0, 0.0001)
	assert_almost_eq(tip.y - centre.y, TokenMarkers.HEAD_ABOVE_TIP * TokenMarkers.HEAD_PX, 0.0001)
	# The centre is where the shader's circle is: tip height + tip radius + tail length.
	assert_almost_eq(TokenMarkers.HEAD_ABOVE_TIP, 0.03 + 0.80, 0.0001)


func test_the_pointer_picks_the_pin_head_it_is_inside() -> void:
	var centres := PackedVector2Array([Vector2(100, 100), Vector2(400, 100)])
	var radii := PackedFloat32Array([22.0, 22.0])
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(110, 105)), 0)
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(400, 120)), 1)
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(250, 100)), -1, "between: none")
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(100, 123)), -1, "just outside the circle")
	# The quad's corner is not the pin: a click there is not a pin click.
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(100 + 21, 100 + 21)), -1)
	assert_eq(TokenMarkers.pick_pin(PackedVector2Array(), PackedFloat32Array(), Vector2.ZERO), -1)


func test_where_pins_overlap_the_nearest_head_centre_wins() -> void:
	var centres := PackedVector2Array([Vector2(100, 100), Vector2(120, 100), Vector2(140, 100)])
	var radii := PackedFloat32Array([22.0, 22.0, 22.0])
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(105, 100)), 0)
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(119, 100)), 1, "the middle one")
	assert_eq(TokenMarkers.pick_pin(centres, radii, Vector2(131, 100)), 2)
	var big := PackedFloat32Array([22.0, 22.0, 24.2])
	assert_eq(TokenMarkers.pick_pin(centres, big, Vector2(122, 100)), 1, "by distance, not size")


func test_the_hovered_pin_is_moved_to_the_end_of_the_draw_order() -> void:
	var pins: Array[Array] = [[3.0, 1], [2.0, 2], [1.0, 3]]
	var front := TokenMarkers.bring_to_front(pins, 1, 1)
	assert_eq(front.map(func(p: Array) -> int: return p[1]), [2, 3, 1], "drawn last, on top")
	assert_eq(pins.map(func(p: Array) -> int: return p[1]), [1, 2, 3], "the input is not changed")
	var mid := TokenMarkers.bring_to_front(pins, 2, 1)
	assert_eq(mid.map(func(p: Array) -> int: return p[1]), [1, 3, 2])
	var none := TokenMarkers.bring_to_front(pins, 0, 1)
	assert_eq(none.map(func(p: Array) -> int: return p[1]), [1, 2, 3], "no hover: unchanged")


func test_a_pin_is_a_target_only_when_drawn_and_solid_enough() -> void:
	assert_true(TokenMarkers.is_hittable(1.0, 1.0))
	assert_true(TokenMarkers.is_hittable(0.5, 0.2), "the GM's dim pin of a hidden token")
	assert_false(TokenMarkers.is_hittable(0.3, 0.3), "still fading in: it must not catch a click")
	assert_false(TokenMarkers.is_hittable(0.0, 0.0), "pitch below the fade: no pins, no targets")
	# A token hidden from a player has no pin alpha, so it is no target for them.
	var player_alpha := TokenMarkers.pin_alpha(1.0, false, true, false)
	assert_false(TokenMarkers.is_hittable(1.0, player_alpha), "hidden token, player")
	var gm_alpha := TokenMarkers.pin_alpha(1.0, false, true, true)
	assert_true(TokenMarkers.is_hittable(1.0, gm_alpha), "hidden token, the GM can pick it")


func test_a_press_on_a_pin_takes_the_same_path_as_one_on_the_body() -> void:
	var controller := DragController.new()
	add_child_autofree(controller)
	var object := Draggable3D.new()
	var body := StaticBody3D.new()
	object.add_child(body)
	add_child_autofree(object)
	await get_tree().process_frame
	assert_true(object.press_at(Vector2(50, 60)), "armed")
	controller.dragging_enabled = false
	assert_false(object.press_at(Vector2(50, 60)), "a tool in use: the press is refused")


func test_the_tip_stands_on_the_footprint_edge_from_above_and_the_head_from_the_side() -> void:
	var from_above := Vector3(0.0, 0.0, -1.0)
	assert_almost_eq(TokenMarkers.top_edge_metres(0.4, 0.9, from_above), 0.4, 0.0001, "pitch 90")
	var home_up := Vector3(0.0, cos(deg_to_rad(21.6)), -sin(deg_to_rad(21.6)))
	var home := TokenMarkers.top_edge_metres(0.4, 0.9, home_up)
	assert_almost_eq(home, 0.4 * sin(deg_to_rad(21.6)) + 0.9 * cos(deg_to_rad(21.6)), 0.0001)
	assert_gt(home, 0.8, "close to the figure's height at home")
	assert_almost_eq(
		TokenMarkers.top_edge_metres(2.0, 0.5, from_above), 2.0, 0.0001, "a large token: its edge"
	)


func test_the_pin_quad_puts_its_tip_at_the_given_point() -> void:
	var basis := Basis.from_euler(Vector3(-deg_to_rad(70.0), deg_to_rad(45.0), 0.0))
	var tip := Vector3(3.0, 1.0, -2.0)
	var head := 0.5
	var xform := TokenMarkers.pin_transform(tip, head, basis)
	# The quad's bottom edge is TIP_Y head diameters below the tip along the screen's up.
	var bottom := xform * Vector3(0.0, -0.5, 0.0)
	assert_almost_eq(bottom.distance_to(tip), TokenMarkers.TIP_Y * head, 0.0001)
	assert_lt((bottom - tip).dot(basis.y), 0.0, "below the tip on screen")
	# The head is one diameter across: the quad is QUAD_W diameters wide.
	assert_almost_eq(xform.basis.x.length(), TokenMarkers.QUAD_W * head, 0.0001)
	assert_almost_eq(xform.basis.y.length(), TokenMarkers.QUAD_H * head, 0.0001)


func test_the_footprint_is_the_collision_box_not_the_mesh() -> void:
	var body := RigidBody3D.new()
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape_node.shape = capsule
	shape_node.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(shape_node)
	add_child_autofree(body)
	body.global_position = Vector3(2.0, 0.0, 3.0)
	var box := TokenMarkers.shape_box(body)
	assert_almost_eq(box.size.x, 0.6, 0.0001, "the capsule's width")
	assert_almost_eq(box.size.y, 1.6, 0.0001)
	assert_almost_eq(box.get_center().y, 0.8, 0.0001)
	assert_almost_eq(box.get_center().x, 2.0, 0.0001, "in the world")
	assert_false(TokenMarkers.shape_box(autofree(Node3D.new())).has_volume(), "no shape: empty")
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.5
	cylinder.height = 2.0
	assert_almost_eq(TokenMarkers.shape_extent(cylinder).size.y, 2.0, 0.0001)


# --- the colour ---


func test_the_pin_colour_is_the_most_vivid_and_readable() -> void:
	var palette := PackedColorArray(
		[Color.WHITE, Color(0.1, 0.1, 0.1), Color(0.9, 0.2, 0.15), Color(0.5, 0.45, 0.4)]
	)
	var colour := TokenMarkers.vivid(palette)
	assert_gt(colour.s, 0.5)
	assert_almost_eq(colour.h, Color(0.9, 0.2, 0.15).h, 0.01, "the red, not the white")
	var dark := TokenMarkers.vivid(PackedColorArray([Color(0.2, 0.2, 0.2)]))
	assert_gte(dark.v, 0.7, "never a dark pin")
	var none := TokenMarkers.vivid(PackedColorArray())
	assert_eq(none, TokenMarkers.NO_COLOUR, "no colour at all: the soft periwinkle")
	assert_lt(none.s, 0.5)
	assert_gt(none.s, 0.15, "not white and not grey")
	var grey := TokenMarkers.vivid(PackedColorArray([Color(0.5, 0.5, 0.5)]))
	assert_lt(grey.s, 0.15, "a grey token keeps a grey pin")


func test_a_vertex_coloured_model_gets_its_own_colour_not_white() -> void:
	# The white pin of camera-2: this material's albedo is plain white (the colour is in the mesh),
	# and the old lookup read the albedo only. White is skipped as no colour, so the pin fell back
	# to near-white.
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	var mesh := _pin_mesh()
	var markers := TokenMarkers.new()
	var old_route := markers._colours_of(material, null)
	assert_eq(old_route, PackedColorArray([Color.WHITE]), "without the mesh: only the white albedo")
	assert_eq(TokenMarkers.vivid(old_route), TokenMarkers.NO_COLOUR, "which gave no colour")
	var colours := markers._colours_of(material, mesh)
	assert_gt(colours.size(), 1, "the mesh's vertex colours are read")
	var colour := TokenMarkers.vivid(colours)
	assert_gt(colour.s, 0.4, "a real colour")
	var blue_gap := absf(colour.h - Color(0.35, 0.45, 0.75).h)
	var tan_gap := absf(colour.h - Color(0.62, 0.38, 0.22).h)
	assert_true(blue_gap < 0.03 or tan_gap < 0.03, "the model's blue or its tan")
	markers.free()


func test_vertex_colours_are_spread_and_tinted() -> void:
	var many := PackedColorArray()
	for i in 1000:
		many.append(Color(float(i) / 1000.0, 0.0, 0.0))
	var sampled := TokenMarkers.sample_colours(many, Color(1.0, 0.5, 1.0), 50)
	assert_lte(sampled.size(), 100)
	assert_gte(sampled.size(), 50)
	assert_almost_eq(sampled[0].g, 0.0, 0.0001)
	assert_gt(sampled[sampled.size() - 1].r, 0.9, "spread to the end")


# --- the portrait atlas ---


func test_the_visible_rect_ignores_faint_pixels_and_scales_back() -> void:
	var image := Image.create(240, 320, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(80, 20, 80, 240), Color(1, 0, 0, 1))
	image.fill_rect(Rect2i(20, 270, 200, 40), Color(0, 0, 0, 0.2))
	var rect := TokenPortraits.visible_rect(image)
	assert_almost_eq(float(rect.position.x), 80.0, 8.0)
	assert_almost_eq(float(rect.position.y), 20.0, 8.0)
	assert_almost_eq(float(rect.size.x), 80.0, 10.0, "the faint floor is not the figure")
	assert_almost_eq(float(rect.size.y), 240.0, 10.0)
	assert_eq(TokenPortraits.visible_rect(Image.create(20, 20, false, Image.FORMAT_RGBA8)), Rect2i())


func test_a_standing_figure_is_cropped_to_head_and_chest_and_an_animal_kept_whole() -> void:
	var size := Vector2i(128, 128)
	var person := TokenPortraits.portrait_rect(Rect2i(44, 10, 40, 108), size)
	assert_eq(person.size.x, 50, "under half the figure's height (HEAD_FRACTION)")
	assert_eq(person.size.y, 50)
	assert_lt(person.position.y, 12, "from the top: the head is in")
	assert_lt(person.end.y, 66, "and the legs are not")
	assert_almost_eq(float(person.get_center().x), 64.0, 1.0, "centred on the figure")
	var horse := TokenPortraits.portrait_rect(Rect2i(10, 30, 108, 70), size)
	assert_eq(horse.size.x, 112, "a wide figure: whole, with air")
	assert_true(Rect2i(Vector2i.ZERO, size).encloses(horse), "inside the picture")
	var empty := TokenPortraits.portrait_rect(Rect2i(), size)
	assert_eq(empty, Rect2i(Vector2i.ZERO, size), "no content: the whole picture")


func test_cells_tile_the_atlas_and_the_picture_sits_in_the_middle() -> void:
	assert_eq(TokenPortraits.cell_origin(0), Vector2i.ZERO)
	assert_eq(TokenPortraits.cell_origin(1), Vector2i(64, 0))
	assert_eq(TokenPortraits.cell_origin(16), Vector2i(0, 64))
	assert_eq(TokenPortraits.cell_origin(255), Vector2i(960, 960))
	var uv := TokenPortraits.picture_uv(17)
	assert_almost_eq(uv.x, (64.0 + 4.0) / 1024.0, 0.00001)
	assert_almost_eq(uv.y, (64.0 + 4.0) / 1024.0, 0.00001)
	var side := float(TokenPortraits.PICTURE_PX) / float(TokenPortraits.ATLAS_PX)
	assert_almost_eq(side, 0.0546875, 0.0000001, "the shader's picture_uv default")


func test_a_picture_is_kept_by_the_tokens_identity() -> void:
	var recipe_a := {"parts": {"hair": "a", "torso": "b"}, "colours": {"skin": "#ffcc99"}}
	var recipe_b := {"colours": {"skin": "#ffcc99"}, "parts": {"torso": "b", "hair": "a"}}
	var a := TokenPortraits.identity_key("", "", "", recipe_a, 5)
	assert_true(a.begins_with("avatar:"))
	var b := TokenPortraits.identity_key("", "", "", recipe_b, 9)
	assert_eq(a, b, "the order of keys does not matter")
	var pack := TokenPortraits.identity_key("folk", "villager_man", "default", {}, 5)
	assert_eq(pack, "pack:folk/villager_man/default")
	assert_ne(pack, TokenPortraits.identity_key("folk", "villager_man", "red", {}, 5))
	var mesh_key := TokenPortraits.identity_key("", "", "", {}, 77)
	assert_eq(mesh_key, "mesh:77", "an imported model: its mesh")


func test_the_atlas_stores_each_picture_once_and_fails_an_empty_one() -> void:
	var portraits := TokenPortraits.new()
	assert_eq(portraits.cell_of("x"), -1, "nothing yet: the disc")
	var red := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	red.fill(Color(1.0, 0.0, 0.0, 1.0))
	assert_true(portraits.store("red", red))
	assert_eq(portraits.cell_of("red"), 0)
	var green := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	green.fill(Color(0.0, 1.0, 0.0, 1.0))
	assert_true(portraits.store("green", green))
	assert_eq(portraits.cell_of("green"), 1)
	assert_false(portraits.store("none", Image.new()))
	assert_eq(portraits.cell_of("none"), -1)
	assert_true(portraits.knows("none"), "a failed key is not asked for again")
	portraits.request("none", {"kind": TokenPortraits.Kind.ICON, "path": "res://missing.png"})
	assert_eq(portraits._queue.size(), 0, "no second job for a known key")
	portraits.request("red", {"kind": TokenPortraits.Kind.ICON, "path": "res://missing.png"})
	assert_eq(portraits._queue.size(), 0, "nor for a pictured one")
	portraits.request("blue", {"kind": TokenPortraits.Kind.ICON, "path": "res://missing.png"})
	portraits.request("blue", {"kind": TokenPortraits.Kind.ICON, "path": "res://missing.png"})
	assert_eq(portraits._queue.size(), 1, "one job however often it is asked")
	portraits.flush()
	# The texture itself reads back empty under the dummy renderer, so the image behind it.
	var image := portraits._image
	assert_eq(image.get_size(), Vector2i(1024, 1024))
	var in_red := image.get_pixel(4 + 28, 4 + 28)
	assert_gt(in_red.r, 0.95, "the red picture is in cell 0")
	assert_lt(in_red.g, 0.05)
	var in_green := image.get_pixel(64 + 4 + 28, 4 + 28)
	assert_gt(in_green.g, 0.95, "the green picture is in cell 1")
	assert_eq(image.get_pixel(1, 1).a, 0.0, "the gutter is clear")
	portraits.free()


func test_a_failed_job_leaves_the_disc_and_a_missing_icon_file_fails() -> void:
	var portraits := TokenPortraits.new()
	add_child_autofree(portraits)
	portraits.request("gone", {"kind": TokenPortraits.Kind.ICON, "path": "res://no/such/icon.png"})
	portraits._process(0.0)
	assert_eq(portraits.cell_of("gone"), -1)
	assert_true(portraits.knows("gone"))


func test_a_builtin_pack_icon_makes_a_picture() -> void:
	var portraits := TokenPortraits.new()
	add_child_autofree(portraits)
	var path := "res://builtin_packs/folk/icons/villager_man.png"
	portraits.request("icon", {"kind": TokenPortraits.Kind.ICON, "path": path})
	portraits._process(0.0)
	assert_eq(portraits.cell_of("icon"), 0, "the shipped roster icon decodes and is stored")
	var image := portraits._image
	var rect := image.get_region(Rect2i(4, 4, 56, 56))
	assert_true(rect.get_used_rect().has_area(), "the picture has content")


func test_a_full_atlas_fails_instead_of_overwriting() -> void:
	var portraits := TokenPortraits.new()
	var tiny := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tiny.fill(Color.RED)
	for i in TokenPortraits.GRID * TokenPortraits.GRID:
		assert_true(portraits.store("k%d" % i, tiny))
	assert_false(portraits.store("one more", tiny), "256 pictures fit, the next does not")
	portraits.request("another", {"kind": TokenPortraits.Kind.ICON, "path": "x"})
	assert_eq(portraits._queue.size(), 0, "and it is not even queued")
	assert_eq(portraits.cell_of("k255"), 255)
	portraits.free()
