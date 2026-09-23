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
const SUBMERSION_DEPTH := 4.0  # how far below the surface the detection box reaches
const SURFACE_MARGIN := 0.05  # thin slab above the surface, so grazing it still counts
const MIN_FOOTPRINT_SIZE := 0.0001  # below this, treat the mesh AABB as degenerate


## Build a WaterZone sized to mesh_node's AABB, or null if the mesh's XZ footprint is
## degenerate (zero/near-zero size -- an authoring mistake; there's nothing useful to
## detect against) or it has no mesh at all. A BoxShape3D approximates the footprint
## rather than the exact mesh trimesh -- a zero-thickness exact shape risks flaky
## touching-vs-overlapping detection right at the resting height where tokens sit; a
## real slab guarantees real volume overlap.
##
## The slab hangs BELOW the surface (top at surface + SURFACE_MARGIN, bottom at
## surface - SUBMERSION_DEPTH) rather than straddling it, because a terrain-paint
## `-water` mesh is a single plane spanning the map's whole footprint -- the visible
## river or lake is simply wherever the terrain dips under that plane. A box centered
## on the surface therefore also swallows the dry banks standing above it: on the river
## map (banks at y = 0, water plane at y = -0.59) the earlier symmetric +/-2.0 band put
## every token inside the zone from the moment the level loaded, so no token ever
## crossed the boundary and neither the splash nor the ripple ever fired. Anything
## below the surface within the footprint is under water; anything above it is on dry
## land. SUBMERSION_DEPTH bounds how far down that claim reaches, so a water plane
## suspended over a valley does not claim tokens on the valley floor far beneath it.
##
## The caller is responsible for matching this node's transform to mesh_node's and
## adding it as a sibling (see WaterGlbUtils.process_water_meshes()). Both constants are
## in the mesh's local space, which is all this function can work in -- it runs before
## the mesh is in the scene tree, so there is no world transform or physics space to
## query yet.
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

	var slab_height := SUBMERSION_DEPTH + SURFACE_MARGIN
	var shape := BoxShape3D.new()
	shape.size = Vector3(aabb.size.x, slab_height, aabb.size.z)

	var centre := aabb.position + aabb.size / 2.0
	var surface_y := aabb.position.y + aabb.size.y
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = shape
	collision_shape.position = Vector3(
		centre.x, surface_y + SURFACE_MARGIN - slab_height / 2.0, centre.z
	)
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
## surface), not the token's collision height, which sits somewhere in the SUBMERSION_DEPTH
## of water below it.
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


## Ask WaterRippleRegistry to push the latest submerged-token disturbance state onto
## the shared water material, at most once per frame across every live WaterZone and
## only when it changed -- see WaterRippleRegistry.flush_disturbances().
func _process(_delta: float) -> void:
	WaterRippleRegistry.flush_disturbances()
