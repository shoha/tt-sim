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
const VERTICAL_BAND_HEIGHT := 0.6  # +/- 0.3 around the mesh's surface Y
const MIN_FOOTPRINT_SIZE := 0.0001  # below this, treat the mesh AABB as degenerate


## Build a WaterZone sized to mesh_node's AABB, or null if the mesh's XZ footprint is
## degenerate (zero/near-zero size -- an authoring mistake; there's nothing useful to
## detect against) or it has no mesh at all. A BoxShape3D approximates the footprint
## rather than the exact mesh trimesh -- a zero-thickness exact shape risks flaky
## touching-vs-overlapping detection right at the resting height where tokens sit; a
## thin slab guarantees real volume overlap. The caller is responsible for matching
## this node's transform to mesh_node's and adding it as a sibling (see
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
## token to register itself with water in advance.
func _on_body_entered(body: Node3D) -> void:
	WaterRippleRegistry.register(body.get_instance_id(), body)
	var token := body.get_parent() as DraggableToken
	if token:
		token.set_submerged(true)
	var splash := SplashBurst.create_at(body.global_position, true)
	body.get_viewport().add_child(splash)
	AudioManager.play_splash_enter()


## Handle a token's collision shape exiting the water zone -- mirrors
## _on_body_entered(). Guards against the body already being freed (e.g. deleted
## mid-drag) before this signal is processed.
func _on_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	WaterRippleRegistry.unregister(body.get_instance_id())
	var token := body.get_parent() as DraggableToken
	if token:
		token.set_submerged(false)
	var splash := SplashBurst.create_at(body.global_position, false)
	body.get_viewport().add_child(splash)
	AudioManager.play_splash_exit()


## Push every currently-submerged token's position (from every WaterZone, not just
## this one) onto the shared water material each frame. Redundant across multiple
## zones on the same map -- see WaterGlbUtils.push_disturbance_points().
func _process(_delta: float) -> void:
	WaterGlbUtils.push_disturbance_points(WaterRippleRegistry.build_disturbance_array())
