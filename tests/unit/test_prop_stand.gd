extends GutTest

## `blocks: stand` for the bulky village props (PropStand, AuthoredSettlements._add_stand,
## docs/systems/villages.md 3f): the pure box measurement from a variant's triangles, the placement
## of the boxes, and the layer's standing-surface bodies met by a token's landing cast
## (WaterSurface.landing_below) on a crate stack and a hay stack.

var _map: Node3D = null
var _layer: AuthoredSettlements = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	StructureRecipes.ensure_served()
	var ground := StaticBody3D.new()
	ground.collision_layer = WaterSurface.TERRAIN_LAYER
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	_map.add_child(ground)
	_layer = AuthoredSettlements.of_map(_map)


# --- pure: the box measurement ------------------------------------------------------------


## The triangles of a block over plan [x0, x1] x [z0, z1] from y = 0 to `top`: top and bottom
## quads and four sides (the sides are vertical and must be ignored).
func _block(
	x0: float, x1: float, z0: float, z1: float, top: float, base: float = 0.0
) -> PackedVector3Array:
	var out := PackedVector3Array()
	for y in [top, base]:
		var p00 := Vector3(x0, y, z0)
		var p10 := Vector3(x1, y, z0)
		var p11 := Vector3(x1, y, z1)
		var p01 := Vector3(x0, y, z1)
		out.append_array([p00, p10, p11, p00, p11, p01])
	var rise := Vector3(0, top - base, 0)
	for side in [[x0, z0, x1, z0], [x1, z0, x1, z1], [x1, z1, x0, z1], [x0, z1, x0, z0]]:
		var a := Vector3(side[0], base, side[1])
		var b := Vector3(side[2], base, side[3])
		out.append_array([a, b, b + rise, a, b + rise, a + rise])
	return out


func test_only_the_bulky_props_stand() -> void:
	for prop in ["crate_stack", "haystack", "barrel", "woodpile", "hand_cart", "farm_wagon"]:
		assert_eq(PropStand.kind_of(prop), PropStand.STAND, prop)
	for prop in ["lamp_post", "signpost", "laundry_line", "well", "bench", "market_stall", ""]:
		assert_eq(PropStand.kind_of(prop), PropStand.NONE, prop)
	assert_true(PropStand.boxes_of("lamp_post", _block(-1, 1, -1, 1, 1.0)).is_empty())
	assert_true(PropStand.boxes_of("crate_stack", PackedVector3Array()).is_empty())


func test_a_crate_is_one_box_at_its_top_floored_to_the_quantum() -> void:
	var boxes := PropStand.boxes_of("crate_stack", _block(-0.5, 0.5, -0.4, 0.4, 1.0))
	assert_eq(boxes.size(), 1)
	var box: Dictionary = boxes[0]
	assert_almost_eq(float(box["top"]), floorf(1.0 / PropStand.QUANT_M) * PropStand.QUANT_M, 0.001)
	assert_lte(float(box["top"]), 1.0, "never above the surface: a token sinks, never floats")
	var size: Vector2 = box["max"] - box["min"]
	assert_almost_eq(size.x, 1.0, PropStand.CELL_M)
	assert_almost_eq(size.y, 0.8, PropStand.CELL_M)


func test_a_stack_gives_a_box_per_level_and_ignores_what_is_too_low() -> void:
	var tris := _block(-1.0, 0.0, -0.4, 0.4, 0.5)
	tris.append_array(_block(0.0, 1.0, -0.4, 0.4, 1.0))
	var boxes := PropStand.boxes_of("crate_stack", tris)
	assert_eq(boxes.size(), 2)
	assert_ne(float(boxes[0]["top"]), float(boxes[1]["top"]))
	var low := PropStand.boxes_of("crate_stack", _block(-1, 1, -1, 1, PropStand.MIN_TOP_M * 0.5))
	assert_true(low.is_empty(), "a plank is walked over")


func test_a_mound_is_coarsened_to_the_box_budget_and_never_over_its_apex() -> void:
	# A cone of nested drums, one step every 8 cm in height.
	var tris := PackedVector3Array()
	var apex := 1.6
	for step in 20:
		var r := 1.0 - 0.05 * step
		tris.append_array(_block(-r, r, -r, r, apex - 0.08 * (19 - step), 0.0))
	var boxes := PropStand.boxes_of("haystack", tris)
	assert_gt(boxes.size(), 1)
	assert_lte(boxes.size(), int(PropStand.STANDING["haystack"]["max"]))
	var highest := 0.0
	for box in boxes:
		assert_lte(float(box["top"]), apex + 0.001)
		highest = maxf(highest, float(box["top"]))
	assert_gt(highest, apex * 0.7, "the middle is not flattened to the foot of the mound")


func test_the_same_prop_gives_the_same_boxes() -> void:
	var tris := _block(-0.9, 0.9, -0.5, 0.5, 0.7)
	assert_eq(PropStand.boxes_of("woodpile", tris), PropStand.boxes_of("woodpile", tris))


func test_shapes_are_placed_with_the_yaw_and_scaled_into_their_size() -> void:
	var boxes: Array[Dictionary] = [{"min": Vector2(0, -0.5), "max": Vector2(1, 0.5), "top": 1.0}]
	var placement := Transform3D(
		Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * 2.0), Vector3(10, 0.5, 20)
	)
	var shapes := PropStand.shapes_of(boxes, placement)
	assert_eq(shapes.size(), 1)
	var size: Vector3 = shapes[0]["size"]
	assert_almost_eq(size.x, 2.0, 0.001, "1 m wide at scale 2")
	assert_almost_eq(size.z, 2.0, 0.001)
	assert_almost_eq(size.y, (1.0 + PropStand.FOOT_M) * 2.0, 0.001)
	var at: Vector3 = (shapes[0]["transform"] as Transform3D).origin
	# Local centre (0.5, _, 0) turned a quarter to (0, _, -0.5) and doubled: 1 m along -z.
	assert_almost_eq(at.x, 10.0, 0.001)
	assert_almost_eq(at.z, 19.0, 0.001)
	# The top face sits at origin y + top * scale.
	assert_almost_eq(at.y + size.y * 0.5, 0.5 + 2.0, 0.001)
	assert_almost_eq(
		((shapes[0]["transform"] as Transform3D).basis.get_scale()).x, 1.0, 0.001, "no scale on the shape"
	)


# --- the layer's bodies and the landing cast ------------------------------------------------


func _cell(prop: String, seed_value: int, at: Vector2, yaw: float, scale: float) -> Dictionary:
	var row := LibraryStructureStore.prop(prop, seed_value)
	assert_false(row.is_empty(), "%s is served" % prop)
	return {
		"name": "S1_0_0",
		"key": "k",
		"settlement": 1,
		"items":
		[
			{
				"item":
				{
					"slot": "t/%s" % prop,
					"prop": prop,
					"seed": seed_value,
					"position": at,
					"yaw": yaw,
					"scale": scale,
				},
				"y": 0.0,
				"normal": Vector3.UP,
				"ref": String(row["ref"]),
			}
		],
	}


func _land(at: Vector2, from_y: float = 6.0) -> float:
	await get_tree().physics_frame
	var space := _map.get_world_3d().direct_space_state
	var hit := WaterSurface.landing_below(space, Vector3(at.x, from_y, at.y), from_y)
	return hit.y


func test_a_drop_on_a_crate_stack_lands_on_its_top_and_beside_it_on_the_ground() -> void:
	var cell := _cell("crate_stack", 0, Vector2(4, 3), 0.7, 1.3)
	_layer._build_variant(String(cell["items"][0]["ref"]))
	_layer._bake_cell(cell)
	var body := _layer.get_node_or_null(NodePath("Stand_S1_0_0")) as StaticBody3D
	assert_not_null(body, "the cell has a standing body")
	assert_eq(body.collision_layer, WaterSurface.TERRAIN_LAYER)
	assert_eq(body.collision_mask, 0)
	assert_false(body.input_ray_pickable)
	assert_eq(int(body.get_meta(AuthoredSettlements.STAND_META)), 1)
	assert_lte(body.get_child_count(), PropStand.MAX_BOXES, "cheap: a few boxes")
	var boxes := AuthoredSettlements.stand_boxes(String(cell["items"][0]["ref"]), "crate_stack")
	assert_false(boxes.is_empty())
	var top := 0.0
	for box in boxes:
		var inside: bool = (
			Vector2(box["min"]).x <= 0.0
			and Vector2(box["max"]).x >= 0.0
			and Vector2(box["min"]).y <= 0.0
			and Vector2(box["max"]).y >= 0.0
		)
		if inside:
			top = maxf(top, float(box["top"]))
	# One level of the braced crates is 0.46 * 0.82 = 0.38 m, floored to the box quantum.
	assert_gt(top, 0.3, "the middle of a crate stack is a crate")
	var landed := await _land(Vector2(4, 3))
	# The mesh is drawn larger than the record's scale (SettlementBake.visual_scale); so is the box.
	var drawn := SettlementBake.visual_scale(cell["items"][0]["item"])
	assert_gt(drawn, 1.3 - 0.001)
	assert_almost_eq(landed, top * drawn, 0.02, "on the top face, at the drawn scale")
	assert_almost_eq(await _land(Vector2(9, 3)), 0.0, 0.001, "beside it: the ground")


func test_a_drop_on_a_hay_stack_lands_on_the_mound_not_the_ground() -> void:
	var cell := _cell("haystack", 0, Vector2(-5, 2), 1.9, 1.0)
	_layer._build_variant(String(cell["items"][0]["ref"]))
	_layer._bake_cell(cell)
	assert_not_null(_layer.get_node_or_null(NodePath("Stand_S1_0_0")))
	var landed := await _land(Vector2(-5, 2))
	assert_gt(landed, 0.5, "the top of the mound at its middle")
	assert_lt(landed, 3.0)
	assert_almost_eq(await _land(Vector2(-5, 8)), 0.0, 0.001, "beside it: the ground")


func test_a_token_standing_inside_a_prop_with_its_top_under_the_prop_is_not_lifted() -> void:
	var cell := _cell("crate_stack", 0, Vector2(4, 3), 0.0, 1.0)
	_layer._build_variant(String(cell["items"][0]["ref"]))
	_layer._bake_cell(cell)
	# A cast that starts inside the box meets no face of it: the ground is the landing.
	assert_almost_eq(await _land(Vector2(4, 3), 0.2), 0.0, 0.001)


func test_the_bodies_are_listed_for_exclusion_and_freed_with_their_cell() -> void:
	var cell := _cell("barrel", 1, Vector2(2, 2), 0.0, 1.0)
	_layer._build_variant(String(cell["items"][0]["ref"]))
	_layer._bake_cell(cell)
	var rids := AuthoredSettlements.exclude_of(_map)
	assert_eq(rids.size(), 1)
	await get_tree().physics_frame
	var space := _map.get_world_3d().direct_space_state
	var ground := WaterSurface.cast_down(
		space, Vector3(2, 5, 2), 5.0, WaterSurface.TERRAIN_LAYER, rids
	)
	assert_almost_eq((ground.position as Vector3).y, 0.0, 0.001, "excluded, a ray finds the ground")
	_layer._free_cell("S1_0_0")
	assert_eq(AuthoredSettlements.exclude_of(_map).size(), 0)
	assert_null(_layer.get_node_or_null(NodePath("Stand_S1_0_0")))
	assert_eq(AuthoredSettlements.exclude_of(null).size(), 0)


func test_a_walk_through_prop_has_no_body() -> void:
	var cell := _cell("lamp_post", 0, Vector2(0, 0), 0.0, 1.0)
	_layer._build_variant(String(cell["items"][0]["ref"]))
	_layer._bake_cell(cell)
	assert_null(_layer.get_node_or_null(NodePath("Stand_S1_0_0")))
	assert_eq(AuthoredSettlements.exclude_of(_map).size(), 0)
