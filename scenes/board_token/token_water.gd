@tool
class_name TokenWater
extends RefCounted

## A DraggableToken's water behaviour, split out of the token so the drag code stays readable.
## The token owns one (DraggableToken.water) and calls in at the moments that matter: a
## landing, a synced move settling, every frame of a drag, WaterZone entering or leaving.
##
## Four parts, all purely visual except the landing:
## - Landing: where a drop settles (WaterSurface.landing_below): the bed in wadeable water, the
##   surface less the token's draft in floating water. The settle tween moves the rigid body
##   there, so this is the one part that decides a synced position.
## - Draft: how deep the token rides in floating water (WaterSurface.draft_for); an avatar
##   swims (its chest at the surface), any other token floats just under its top.
## - Sink and bob: the visual children sink SUBMERGE_SINK_AMOUNT while WaterZone says the token
##   stands in water, and bob while it rests at a floating height. Neither touches the rigid
##   body, which the settle tween and network interpolation own.
## - Cue: the SubmergedMarker at the water surface while the water hides the token, where it
##   rests or, while it moves, where it would land.
## Every peer decides sink, bob and cue for its own copy.

const SUBMERGE_SINK_AMOUNT: float = 0.04  # How far visuals sink while standing in water
const SUBMERGE_TWEEN_DURATION: float = 0.25
## A moving token re-checks its submerged cue once it has moved this far (metres, XZ).
const SUBMERGED_CUE_STEP: float = 0.03

## Whether WaterZone has the token standing in water (set_submerged()).
var submerged: bool = false
## The sink tween set_submerged() last started (tests compare it).
var submerge_tween: Tween = null
## Loops while the token floats in deep water (update_floating()).
var bob_tween: Tween = null

var _token: DraggableToken
## The cue at the water surface while the water hides the token (update_cue()).
var _marker: SubmergedMarker = null
## Where a moving token last checked its cue (Vector3.INF: check on the next move).
var _cue_checked_at: Vector3 = Vector3.INF


func _init(token: DraggableToken) -> void:
	_token = token


## Adds the marker under the rigid body so it hides with the token; it is top_level and left
## out of the visual children (see SubmergedMarker).
func setup_marker() -> void:
	_marker = SubmergedMarker.new()
	_marker.set_radius(SubmergedMarker.radius_for_box(cue_box()))
	_token.rigid_body.add_child(_marker)


## A new size or shape moves the marker's ring and may lift the token out of the water.
func refresh_marker() -> void:
	if _marker == null:
		return
	_marker.set_radius(SubmergedMarker.radius_for_box(cue_box()))
	if not _token.is_being_dragged():
		update_cue(false)


## A drag starts: the bob stops (the visuals come back to the sink alone) and the next move
## checks the cue.
func on_drag_started() -> void:
	if bob_tween != null:
		_kill_bob_tween()
		_apply_bob(0.0)
	_cue_checked_at = Vector3.INF


## Kills both tweens (the token is leaving the tree).
func stop() -> void:
	_kill_submerge_tween()
	_kill_bob_tween()


## Find where the token should land by raycasting down from its top, so a token whose
## bottom ended up just below the ground (a drag that snapped it onto a higher tier before
## it finished rising, a scroll-lowered drag) still lands on that ground instead of
## staying where it is. Starting at the top rather than above the whole map keeps an
## overhang above the token (a bridge, a roof on a Blender map) out of the cast.
## In water the float rule applies (WaterSurface.landing_below): the bed in wadeable water,
## the surface less a small draft in deep water; the water cast starts higher than the
## token's top, which can be under the surface of deep water.
## Returns Vector3 or null if no surface is found.
func landing_position() -> Variant:
	var rigid_body := _token.rigid_body
	var collision_shape := _token.collision_shape
	if not rigid_body or not collision_shape or not collision_shape.shape:
		return null
	var aabb = collision_shape.shape.get_debug_mesh().get_aabb()
	var scaled_top_y = (collision_shape.position.y + aabb.end.y) * rigid_body.scale.y
	return landing_from(rigid_body.global_position.y + scaled_top_y)


## landing_position() cast from world height `from_y` instead of the token's top: for a token
## buried by ground raised over it, which has no ground under its top (TokenGrounding).
## Returns Vector3 or null if no surface is found.
func landing_from(from_y: float) -> Variant:
	var rigid_body := _token.rigid_body
	var collision_shape := _token.collision_shape
	if not rigid_body or not collision_shape or not collision_shape.shape:
		return null

	var aabb = collision_shape.shape.get_debug_mesh().get_aabb()
	var scaled_bottom_y = (collision_shape.position.y + aabb.position.y) * rigid_body.scale.y
	var from := Vector3(rigid_body.global_position.x, from_y, rigid_body.global_position.z)

	# Terrain and water only (layers 1 and WaterSurface.LAYER), never other tokens.
	var ground := WaterSurface.landing_below(
		_token.get_world_3d().direct_space_state, from, from_y, draft()
	)
	if ground == Vector3.INF:
		return null

	# Place token so its bottom sits on the landing ground
	var landing_y = ground.y - scaled_bottom_y
	return Vector3(rigid_body.global_position.x, landing_y, rigid_body.global_position.z)


## Starts or stops the floating bob (WaterSurface.BOB_M over BOB_PERIOD_S on the visual
## children, on top of the submerge sink) by whether the token now rests at a floating
## height (WaterSurface.floats_at). Called when a landing or a synced move settles, so every
## peer bobs its own copy; purely visual, the synced position is untouched.
func update_floating() -> void:
	if not _token.rigid_body or not _token.rigid_body.is_inside_tree():
		return
	var floating := WaterSurface.floats_at(
		_token.get_world_3d().direct_space_state, base_position(), 0.05, draft()
	)
	if floating == (bob_tween != null):
		return
	_kill_bob_tween()
	if not floating:
		_apply_bob(0.0)
		return
	bob_tween = _token.create_tween().set_loops()
	bob_tween.tween_method(_apply_bob, 0.0, TAU, WaterSurface.BOB_PERIOD_S)


## Shows or hides the SubmergedMarker by whether the water hides the token
## (WaterSurface.submerged_surface): where it rests, or with `moving` where it would land
## (a drag or a synced move in flight), so the cue follows a token dragged along a river and
## says before the drop that it will go under. A moving token checks again only once it has
## moved SUBMERGED_CUE_STEP. Purely visual; every peer decides for its own copy.
func update_cue(moving: bool) -> void:
	var rigid_body := _token.rigid_body
	if _marker == null or not rigid_body or not rigid_body.is_inside_tree():
		return
	var box := cue_box()
	var at: Variant = rigid_body.global_position
	if moving:
		var flat := Vector2(at.x - _cue_checked_at.x, at.z - _cue_checked_at.z)
		if flat.length() < SUBMERGED_CUE_STEP:
			return
		_cue_checked_at = at
		at = landing_position()
	else:
		_cue_checked_at = Vector3.INF
	var surface := NAN
	if at != null:
		at = (at as Vector3) + Vector3(0, box.position.y, 0)
		var space := _token.get_world_3d().direct_space_state
		surface = WaterSurface.submerged_surface(
			space, at, box.size.y, WaterSurface.submerged_share_for(_swims())
		)
	if is_nan(surface):
		_marker.hide_marker()
	else:
		_marker.show_at(Vector3(at.x, surface, at.z), _swims())


## How deep the token rides in floating water (WaterSurface.draft_for: avatars swim).
func draft() -> float:
	return WaterSurface.draft_for(cue_box().size.y, _swims())


## Whether the submerged cue is showing.
func is_cue_shown() -> bool:
	return _marker != null and _marker.is_shown()


## The token's collision box in the rigid body's frame at BoardToken's logical scale (not a
## spawn animation's near-zero one): position.y is the base's offset, size.y the height.
func cue_box() -> AABB:
	var board_token := _token.get_parent() as BoardToken
	var token_scale := board_token.get_logical_scale() if board_token else _token.rigid_body.scale
	return SubmergedMarker.token_box(_token.collision_shape, token_scale)


## WaterZone's entry and exit (DraggableToken.set_submerged). Tweens the visual children down
## slightly to read as "standing in water"; a token at rest also re-checks its cue (a zone
## replaced under it, water appearing or leaving).
func set_submerged(value: bool) -> void:
	if value == submerged:
		return
	submerged = value
	if not _token.is_being_dragged() and not _token.is_network_interpolating():
		update_cue(false)

	_kill_submerge_tween()
	submerge_tween = _token.create_tween()
	submerge_tween.set_parallel(true)
	var target_y := -SUBMERGE_SINK_AMOUNT if value else 0.0
	for child in _token.get_visual_children():
		if is_instance_valid(child):
			submerge_tween.tween_property(child, "position:y", target_y, SUBMERGE_TWEEN_DURATION)


## The world position of the token's base (the bottom of its collision shape).
func base_position() -> Vector3:
	var rigid_body := _token.rigid_body
	var collision_shape := _token.collision_shape
	var bottom := 0.0
	if collision_shape and collision_shape.shape:
		var aabb := collision_shape.shape.get_debug_mesh().get_aabb()
		bottom = (collision_shape.position.y + aabb.position.y) * rigid_body.scale.y
	return rigid_body.global_position + Vector3(0, bottom, 0)


## Whether the swim rule applies (an avatar figure).
func _swims() -> bool:
	var board_token := _token.get_parent() as BoardToken
	return board_token != null and board_token.is_avatar()


func _apply_bob(phase: float) -> void:
	var sink := -SUBMERGE_SINK_AMOUNT if submerged else 0.0
	for child in _token.get_visual_children():
		if is_instance_valid(child):
			child.position.y = sink + sin(phase) * WaterSurface.BOB_M


func _kill_bob_tween() -> void:
	if bob_tween and bob_tween.is_valid():
		bob_tween.kill()
	bob_tween = null


func _kill_submerge_tween() -> void:
	if submerge_tween and submerge_tween.is_valid():
		submerge_tween.kill()
	submerge_tween = null
