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


func _on_body_entered(_body: Node3D) -> void:
	pass  # filled in once WaterRippleRegistry/DraggableToken.set_submerged exist (Task 7)


func _on_body_exited(_body: Node3D) -> void:
	pass  # filled in once WaterRippleRegistry/DraggableToken.set_submerged exist (Task 7)
