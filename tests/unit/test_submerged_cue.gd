extends GutTest

## The submerged token cue (P4b-0): WaterSurface.is_submerged / submerged_surface (a token
## the water hides), SubmergedMarker's sizing and its shader constant, and DraggableToken
## showing the marker at the surface over a hidden token, at rest and at the predicted
## landing while it moves, and hiding it on dry ground or when the token stands clear.

const SURFACE := -0.2
const BED := -1.0
const BANK := 0.3
const EPSILON := 0.01

var _root: Node3D = null
var _scene_root: Node = null
var _original_scene: Node = null


func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = null
	if _scene_root != null:
		get_tree().current_scene = _original_scene
		_scene_root.free()
		_scene_root = null


func test_is_submerged_rule() -> void:
	var free := WaterSurface.SUBMERGED_FREEBOARD_M
	assert_false(WaterSurface.is_submerged(-1.0, -0.5, NAN), "no water")
	assert_true(WaterSurface.is_submerged(-1.0, -0.5, 0.0), "wholly under")
	assert_true(WaterSurface.is_submerged(-1.0, free * 0.5, 0.0), "a sliver above still counts")
	# The allowance grows with the token: a fifth of a 1.2 m token is 0.24 m.
	assert_true(WaterSurface.is_submerged(-1.0, 0.2, 0.0), "a tall token's crest")
	assert_false(WaterSurface.is_submerged(-1.0, 0.3, 0.0), "standing clear")
	assert_false(WaterSurface.is_submerged(-0.5, free * 1.5, 0.0), "a short token clear")
	assert_false(WaterSurface.is_submerged(0.2, 0.3, 0.0), "above the surface (a bank)")
	# A floating token rides with its base DRAFT_M under: hidden only when it is tiny.
	var draft := -WaterSurface.DRAFT_M
	assert_false(WaterSurface.is_submerged(draft, draft + 1.0, 0.0), "a floating token")
	assert_true(WaterSurface.is_submerged(draft, draft + 0.1, 0.0), "a tiny floating token")


func test_marker_radius_and_shader_ring_agree() -> void:
	assert_almost_eq(SubmergedMarker.radius_for(0.5), 0.5 * SubmergedMarker.FOOTPRINT_SCALE, 1e-6)
	assert_eq(SubmergedMarker.radius_for(0.01), SubmergedMarker.MIN_RADIUS_M, "small tokens")
	assert_eq(SubmergedMarker.radius_for(10.0), SubmergedMarker.MAX_RADIUS_M, "huge tokens")
	# A 0.5 m box raised 0.25 m (base at the body's origin), at scale 2.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.5, 0.6)
	shape.shape = box
	shape.position = Vector3(0, 0.25, 0)
	var scaled := SubmergedMarker.token_box(shape, Vector3(2, 2, 2))
	assert_almost_eq(scaled.position.y, 0.0, 1e-5, "base at the origin")
	assert_almost_eq(scaled.size.y, 1.0, 1e-5, "height scaled")
	assert_almost_eq(SubmergedMarker.radius_for_box(scaled), 0.6 * 1.15, 1e-5, "widest half")
	shape.free()
	assert_eq(SubmergedMarker.token_box(null, Vector3.ONE), AABB(), "no shape")
	var text := FileAccess.get_file_as_string("res://shaders/submerged_marker.gdshader")
	var regex := RegEx.new()
	regex.compile("const\\s+float\\s+RING_R\\s*=\\s*([^;]+);")
	var found := regex.search(text)
	assert_not_null(found, "RING_R in the shader")
	if found != null:
		assert_almost_eq(float(found.get_string(1)), SubmergedMarker.RING_R, 1e-6)


func test_marker_sizes_its_quad_to_the_ring() -> void:
	var marker := SubmergedMarker.new()
	add_child(marker)
	marker.set_radius(0.7)
	# The quad's half size is 1 unit scaled, and the ring sits at RING_R of it.
	var ring := marker.get_node("Ring") as MeshInstance3D
	assert_almost_eq(ring.scale.x * SubmergedMarker.RING_R, 0.7, 1e-5)
	assert_false(marker.visible, "hidden until shown")
	marker.show_at(Vector3(1, SURFACE, 2))
	assert_true(marker.is_shown())
	assert_true(marker.visible)
	assert_almost_eq(marker.global_position.y, SURFACE + SubmergedMarker.LIFT_M, 1e-5)
	marker.hide_marker(true)
	assert_false(marker.is_shown())
	assert_false(marker.visible)
	marker.free()


## Ground on the terrain layer (a bed at BED under x < 0, a bank at BANK for x >= 0) and a
## water surface at SURFACE over the bed only, as authored and Blender maps both provide.
func _world() -> void:
	_root = Node3D.new()
	add_child(_root)
	for part in [
		[Vector3(-4, BED - 0.5, 0), Vector3(8, 1, 8)], [Vector3(4, BANK - 0.5, 0), Vector3(8, 1, 8)]
	]:
		var body := StaticBody3D.new()
		body.collision_layer = WaterSurface.TERRAIN_LAYER
		var box := BoxShape3D.new()
		box.size = part[1]
		var shape := CollisionShape3D.new()
		shape.shape = box
		body.add_child(shape)
		body.position = part[0]
		_root.add_child(body)
	var faces := PackedVector3Array(
		[
			Vector3(-8, SURFACE, -4),
			Vector3(0, SURFACE, -4),
			Vector3(0, SURFACE, 4),
			Vector3(-8, SURFACE, -4),
			Vector3(0, SURFACE, 4),
			Vector3(-8, SURFACE, 4),
		]
	)
	_root.add_child(WaterSurface.make_body("Test-water_surface", faces, null))


## A token with a box collision `size` tall (its origin at the box centre), base at `base`.
## DraggableToken's _ready() reads get_tree().current_scene (see test_water_zone.gd).
func _token(base: Vector3, size: float) -> DraggableToken:
	if _scene_root == null:
		_original_scene = get_tree().current_scene
		_scene_root = Node.new()
		get_tree().root.add_child(_scene_root)
		get_tree().current_scene = _scene_root
	var rigid_body := RigidBody3D.new()
	rigid_body.collision_layer = 2
	rigid_body.collision_mask = 0
	rigid_body.gravity_scale = 0.0
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, size, 0.6)
	collision_shape.shape = box
	rigid_body.add_child(collision_shape)
	rigid_body.add_child(Node3D.new())
	var token := DraggableToken.new()
	token.rigid_body = rigid_body
	token.collision_shape = collision_shape
	token.add_child(rigid_body)
	_root.add_child(token)
	rigid_body.global_position = base + Vector3(0, size * 0.5, 0)
	return token


func test_space_query_finds_the_hiding_surface() -> void:
	_world()
	await get_tree().physics_frame
	var space := _root.get_world_3d().direct_space_state
	var hidden := WaterSurface.submerged_surface(space, Vector3(-3, BED, 0.3), 0.5)
	assert_almost_eq(hidden, SURFACE, EPSILON, "a small token on the bed")
	assert_true(is_nan(WaterSurface.submerged_surface(space, Vector3(-3, BED, 0.3), 1.5)), "tall")
	assert_true(is_nan(WaterSurface.submerged_surface(space, Vector3(3, BANK, 0.3), 0.2)), "dry")


func test_token_shows_the_cue_at_rest_and_hides_it_on_the_bank() -> void:
	_world()
	var small := _token(Vector3(-3, BED, 0.3), 0.5)
	var tall := _token(Vector3(-5, BED, -1.0), 1.5)
	await get_tree().physics_frame
	small._update_submerged_cue(false)
	tall._update_submerged_cue(false)
	assert_true(small.is_submerged_cue_shown(), "hidden by the water")
	assert_false(tall.is_submerged_cue_shown(), "stands clear of the water")
	var marker := small.rigid_body.get_node(SubmergedMarker.NODE_NAME) as SubmergedMarker
	assert_not_null(marker)
	assert_almost_eq(marker.global_position.y, SURFACE + SubmergedMarker.LIFT_M, EPSILON)
	assert_almost_eq(marker.global_position.x, -3.0, EPSILON, "above the token")
	assert_false(marker in small.get_visual_children(), "not moved by sink, bob or lean")
	# Onto the bank: gone.
	small.rigid_body.global_position = Vector3(3, BANK + 0.25, 0.3)
	small._update_submerged_cue(false)
	assert_false(small.is_submerged_cue_shown(), "dry ground")


func test_a_moving_token_shows_the_cue_where_it_will_land() -> void:
	_world()
	# Held high over the water: its landing is the bed, where the water hides it.
	var token := _token(Vector3(-3, 2.0, 0.3), 0.5)
	await get_tree().physics_frame
	token._update_submerged_cue(true)
	assert_true(token.is_submerged_cue_shown(), "the drop would put it under")
	# Carried over the bank: the drop would leave it dry, so the cue goes.
	token.rigid_body.global_position = Vector3(3, 2.25, 0.3)
	token._update_submerged_cue(true)
	assert_false(token.is_submerged_cue_shown(), "over the bank the drop keeps it dry")
