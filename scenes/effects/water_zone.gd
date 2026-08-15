class_name WaterZone
extends Area3D

## Auto-generated per `-water` mesh by WaterGlbUtils.process_water_meshes(), mirroring
## how GlbUtils._process_single_collision_node() adds a sibling StaticBody3D for
## collision meshes -- same "one node per source mesh, mapmaker does zero setup"
## convention, just Area3D instead of StaticBody3D since this only needs to detect
## token overlap, not provide real collision.
##
## Detects tokens (RigidBody3D on collision layer 2, see board_token_factory.gd)
## entering/exiting the water's footprint and drives the splash/ripple/submersion
## interactions -- see the design spec
## (docs/superpowers/specs/2026-08-15-water-token-interaction-design.md).

const TOKEN_COLLISION_LAYER_MASK := 2
const VERTICAL_BAND_HEIGHT := 4.0  # +/- 2.0 around the mesh's surface Y
const MIN_FOOTPRINT_SIZE := 0.0001  # below this, treat the mesh AABB as degenerate


## Build a WaterZone sized to mesh_node's AABB, or null if the mesh's XZ footprint is
## degenerate (zero/near-zero size -- an authoring mistake; there's nothing useful to
## detect against) or it has no mesh at all. A BoxShape3D approximates the footprint
## rather than the exact mesh trimesh -- a zero-thickness exact shape risks flaky
## touching-vs-overlapping detection right at the resting height where tokens sit; a
## thin slab guarantees real volume overlap. VERTICAL_BAND_HEIGHT is generous (+/- 2.0)
## because a token's resting collision height relative to the water mesh's own Y isn't
## guaranteed to be close -- verified directly against a real map where a flat,
## disconnected collision proxy sits 0.59 units above the water mesh, and a future
## well-authored map could equally plausibly have collision *below* the water mesh's Y
## at the bottom of a carved basin. The wide, symmetric margin tolerates that mismatch
## in either direction without needing to query live physics at construction time,
## which this function can't do anyway -- it runs before the mesh is in the scene tree,
## before any physics space exists for it. The caller is responsible for matching this
## node's transform to mesh_node's and adding it as a sibling (see
## WaterGlbUtils.process_water_meshes()).
static func create_for_mesh(mesh_node: MeshInstance3D) -> WaterZone:
	if not mesh_node.mesh:
		return null
	var aabb := mesh_node.mesh.get_aabb()
	if aabb.size.x <= MIN_FOOTPRINT_SIZE or aabb.size.z <= MIN_FOOTPRINT_SIZE:
		return null

	var zone := WaterZone.new()
	zone.name = mesh_node.name + "_zone"
	zone.collision_layer = 0
	zone.collision_mask = TOKEN_COLLISION_LAYER_MASK
	zone.monitoring = true
	zone.monitorable = false

	var shape := BoxShape3D.new()
	shape.size = Vector3(aabb.size.x, VERTICAL_BAND_HEIGHT, aabb.size.z)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = shape
	collision_shape.position = aabb.position + aabb.size / 2.0
	zone.add_child(collision_shape)

	return zone


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Handle a token's collision shape entering the water zone -- registers it for the
## persistent ripple, sinks its visuals, and spawns an entry splash. See the design
## spec's "Token water detection" section for why this is safe to key purely off
## body.get_parent() (the documented DraggableToken hierarchy) rather than needing the
## token to register itself with water in advance. The registry is refcounted (see
## WaterRippleRegistry.register()), so entering a second, overlapping WaterZone while
## already submerged is a no-op here -- only the true 0->1 transition sinks visuals and
## spawns a splash. The splash spawns at the token's XZ but this zone's own Y (the water
## surface), not the token's collision height, which can sit well above/below the
## surface within VERTICAL_BAND_HEIGHT's generous tolerance.
func _on_body_entered(body: Node3D) -> void:
	var first_entry := WaterRippleRegistry.register(body.get_instance_id(), body)
	if not first_entry:
		return
	var token := body.get_parent() as DraggableToken
	if token:
		token.set_submerged(true)
	var splash := SplashBurst.create_at(
		Vector3(body.global_position.x, global_position.y, body.global_position.z), true
	)
	body.get_viewport().add_child(splash)
	AudioManager.play_splash_enter()


## Handle a token's collision shape exiting the water zone -- mirrors
## _on_body_entered(). Two guards: (1) the body may already be freed (e.g. deleted
## mid-drag) before this signal is processed, in which case there's nothing to read from
## it at all; (2) even when valid, Godot also emits body_exited when a body leaves the
## scene tree (not only when it leaves the detection volume), e.g. token deletion or
## level teardown while submerged -- in that case body.get_viewport() would be a
## viewport that's being torn down, so visual/audio side-effects are skipped. Both cases
## still unregister from WaterRippleRegistry so it doesn't leak an entry for a token
## that's gone. The registry is refcounted, so exiting one of several overlapping zones
## is also a no-op here unless this was the token's last active zone (true 1->0
## transition).
func _on_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var fully_exited := WaterRippleRegistry.unregister(body.get_instance_id())
	if not fully_exited or not body.is_inside_tree():
		return
	var token := body.get_parent() as DraggableToken
	if token:
		token.set_submerged(false)
	var splash := SplashBurst.create_at(
		Vector3(body.global_position.x, global_position.y, body.global_position.z), false
	)
	body.get_viewport().add_child(splash)
	AudioManager.play_splash_exit()


## Push every currently-submerged token's position (from every WaterZone, not just
## this one) onto the shared water material each frame. Redundant across multiple
## zones on the same map -- see WaterGlbUtils.push_disturbance_points().
func _process(_delta: float) -> void:
	WaterGlbUtils.push_disturbance_points(WaterRippleRegistry.build_disturbance_array())
