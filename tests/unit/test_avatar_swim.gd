extends GutTest

## The swim rule (WaterSurface.draft_for, SWIM_DEPTH_SHARE): an avatar figure in floating
## water sinks until the surface crosses its chest and shows the submerged cue; in wadeable
## water it stands on the bed as before; every other token keeps the float rule.

const HEIGHT := 1.6


func test_a_swimmer_rides_chest_deep_in_floating_water() -> void:
	var draft := WaterSurface.draft_for(HEIGHT, true)
	assert_almost_eq(draft, WaterSurface.SWIM_DEPTH_SHARE * HEIGHT, 0.0001)
	# Deep water: bed at -2, surface at 0.
	var base := WaterSurface.landing_y(-2.0, 0.0, true, draft)
	assert_almost_eq(base, -draft, 0.0001, "base sits a draft under the surface")
	var out_of_water := base + HEIGHT - 0.0
	assert_almost_eq(out_of_water / HEIGHT, 1.0 - WaterSurface.SWIM_DEPTH_SHARE, 0.0001)


func test_a_swimmer_in_wadeable_water_stands_on_the_bed() -> void:
	var draft := WaterSurface.draft_for(HEIGHT, true)
	assert_eq(WaterSurface.landing_y(-0.9, 0.0, false, draft), -0.9, "waist-deep: the bed")


func test_a_swimmer_near_the_shallow_edge_stands_on_the_bed() -> void:
	var draft := WaterSurface.draft_for(HEIGHT, true)
	# Floating water whose bed rises above the swim height: walk out onto the bed.
	assert_eq(WaterSurface.landing_y(-0.5, 0.0, true, draft), -0.5)


func test_other_tokens_keep_the_float_rule() -> void:
	assert_eq(WaterSurface.draft_for(0.7, false), WaterSurface.DRAFT_M)
	assert_almost_eq(
		WaterSurface.landing_y(-2.0, 0.0, true), -WaterSurface.DRAFT_M, 0.0001, "default draft"
	)
	assert_eq(WaterSurface.submerged_share_for(false), WaterSurface.SUBMERGED_SHARE)


func test_the_cue_shows_for_a_swimmer_and_not_for_a_wader() -> void:
	var share := WaterSurface.submerged_share_for(true)
	var draft := WaterSurface.draft_for(HEIGHT, true)
	var swim_base := -draft
	assert_true(WaterSurface.is_submerged(swim_base, swim_base + HEIGHT, 0.0, share), "swimming")
	# Waist-deep wading (0.6 m of water over the bed): most of the figure is out.
	assert_false(WaterSurface.is_submerged(-0.6, -0.6 + HEIGHT, 0.0, share), "wading")
	# The same swimmer under the default share would not count: the rule is the swimmer's.
	assert_false(WaterSurface.is_submerged(swim_base, swim_base + HEIGHT, 0.0))


func test_an_avatar_token_takes_the_swim_draft() -> void:
	var old_scene := get_tree().current_scene
	var scene := Node.new()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	var token := AvatarTokenFactory.create(AvatarPresets.recipe(0), "Plum")
	scene.add_child(token)
	var drag := token.get_dragging_object()
	assert_almost_eq(
		drag.water_draft(), WaterSurface.SWIM_DEPTH_SHARE * drag.cue_box().size.y, 0.0001
	)
	assert_gt(drag.water_draft(), 1.0, "a 1.6 m figure sinks over a metre")
	get_tree().current_scene = old_scene
	scene.free()


## The drag target (DragAndDrop3D.resolve_target_ground through the dragged object's
## drag_resolver) carries the token's own draft, so a dragged avatar shows its swim depth over
## deep water, not the ordinary float height it would leave on the drop.
func test_a_dragged_avatar_resolves_at_its_swim_depth() -> void:
	var old_scene := get_tree().current_scene
	var scene := Node.new()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	var token := AvatarTokenFactory.create(AvatarPresets.recipe(0), "Plum")
	scene.add_child(token)
	var drag := token.get_dragging_object()
	# GameMap's resolver over deep water (surface at 0, bed far below): the float height.
	var deep_water := func(point: Vector3, draft: float = WaterSurface.DRAFT_M) -> Vector3:
		return Vector3(point.x, WaterSurface.landing_y(-3.0, 0.0, true, draft), point.z)
	var hit := Vector3(2.0, 0.0, -1.0)
	var target := DragAndDrop3D.resolve_target_ground(
		hit, false, 1.0, Vector2.ZERO, drag.drag_resolver(deep_water)
	)
	assert_almost_eq(target.y, -drag.water_draft(), 0.0001, "the avatar's swim depth")
	assert_lt(target.y, -WaterSurface.DRAFT_M - 0.5, "well below the float height")
	var plain := DraggingObject3D.new()
	var shared := DragAndDrop3D.resolve_target_ground(
		hit, false, 1.0, Vector2.ZERO, plain.drag_resolver(deep_water)
	)
	assert_almost_eq(shared.y, -WaterSurface.DRAFT_M, 0.0001, "the shared resolver floats")
	plain.free()
	get_tree().current_scene = old_scene
	scene.free()
