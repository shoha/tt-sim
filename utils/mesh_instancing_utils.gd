class_name MeshInstancingUtils
extends RefCounted

## Load-time draw-call optimisation for maps: collapses groups of identical,
## separately-placed MeshInstance3D nodes into MultiMeshInstance3D nodes. Extracted
## from GlbUtils to keep both files under this repo's gdlint max-file-lines gate,
## the same way WaterGlbUtils was. See utils/glb_utils.gd for GLB loading in general.

# Defaults for process_duplicate_mesh_instancing() -- see its docstring for why each
# guard exists. Both are deliberately conservative: the cost of skipping a group that
# would have been fine is one extra draw call, the cost of converting one that wasn't
# is a silently broken behaviour somewhere else in the scene.
const DUPLICATE_INSTANCING_MIN_COUNT := 25
const DUPLICATE_INSTANCING_MAX_EXTENT := 2.0


## Collapse each group of identical, separately-placed MeshInstance3D nodes (Blender
## linked duplicates -- Shift+D, or a Place Helper scatter brush stroke) into a single
## MultiMeshInstance3D, turning N draw calls into one. Returns the number of groups
## converted.
##
## Verified empirically before this was written: Blender exports linked duplicates as
## ONE glTF mesh referenced by N nodes, and Godot's importer then hands all N
## MeshInstance3Ds the same Mesh resource instance (an object whose mesh data was
## fully copied instead gets its own). A shared Mesh is therefore a reliable "these
## came from one source object" signal.
##
## That is the whole reason this lives here rather than in terrain-paint: it needs
## nothing from the authoring tool, so it also optimises maps uploaded by users who
## have never run that addon. ScatterGlbUtils.process_scatter_instances() cannot work this
## way and still needs its export-side extras -- Geoscatter instances are Geometry
## Nodes output, not real objects, so there is nothing in the file for a load-time
## scan to find.
##
## MUST run after GlbUtils.process_collision_meshes() and
## WaterGlbUtils.process_water_meshes(): it relies on the former having already
## hidden or freed collision indicator meshes, and on the latter having already
## claimed water planes with a material_override.
##
## Deliberately NOT converted, each for a behaviour that would otherwise break
## silently:
## - Groups smaller than `min_instances`. A MultiMesh is culled as one AABB, so the
##   per-instance frustum culling given up is only worth trading for a real draw-call
##   saving.
## - Meshes whose largest world-space extent exceeds `max_extent`. Anything big enough
##   to hide a token behind it needs OcclusionFadeManager, which only fades real
##   MeshInstance3D surfaces (and wind-foliage MultiMeshes, which carry the fade logic
##   in their own shader). Pass 0.0 to disable this guard.
## - Skinned meshes: they deform per-instance, which a MultiMesh cannot express.
## - Nodes an AnimationPlayer drives: their transform is not static.
## - Nodes carrying a material_override / material_overlay / surface override, since
##   two nodes sharing a Mesh can still render differently through those. This is also
##   what keeps water planes out, without duplicating WaterGlbUtils' suffix here.
## - Collision-suffixed and hidden nodes.
##
## Nodes with children keep existing with `mesh = null` rather than being freed -- see
## _retire_instanced_source_node for why that matters for collision.
##
## Known limitations and the worked-out path past each (occlusion fade, single-AABB
## culling, per-instance picking, tunable thresholds, copied-mesh duplicates) are
## recorded in docs/ARCHITECTURE.md under "Known limitations and future iterations"
## -- read that before extending this, rather than re-deriving why a guard exists.
static func process_duplicate_mesh_instancing(
	scene: Node3D,
	min_instances: int = DUPLICATE_INSTANCING_MIN_COUNT,
	max_extent: float = DUPLICATE_INSTANCING_MAX_EXTENT
) -> int:
	if not scene:
		return 0

	var animated_ids := {}
	_collect_animated_node_ids(scene, animated_ids)

	var groups := {}
	var group_order: Array = []
	_collect_instancing_candidates(scene, animated_ids, groups, group_order)

	var converted := 0
	for key in group_order:
		var nodes: Array = groups[key]
		if nodes.size() < min_instances:
			continue

		var representative := nodes[0] as MeshInstance3D
		var transforms: Array[Transform3D] = []
		var largest_scale := 0.0
		for node in nodes:
			var xform := transform_relative_to(node as Node3D, scene)
			transforms.append(xform)
			var node_scale := xform.basis.get_scale().abs()
			largest_scale = maxf(largest_scale, node_scale[node_scale.max_axis_index()])

		if max_extent > 0.0:
			var extent: Vector3 = representative.mesh.get_aabb().size
			if extent[extent.max_axis_index()] * largest_scale > max_extent:
				continue

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = representative.mesh
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])

		# Sits directly under scene with an identity transform, for the same reason
		# ScatterGlbUtils._build_multimesh_from_transforms' node does: every instance
		# transform above is already relative to scene, so any local transform here
		# would double-apply.
		var multimesh_instance := MultiMeshInstance3D.new()
		multimesh_instance.name = String(representative.name) + "_MultiMesh"
		multimesh_instance.multimesh = multimesh
		multimesh_instance.cast_shadow = representative.cast_shadow
		scene.add_child(multimesh_instance)

		for node in nodes:
			_retire_instanced_source_node(node as MeshInstance3D)
		converted += 1

	return converted


## Stop a source node rendering, without disturbing anything hanging off it.
##
## A node with children keeps existing with `mesh = null` instead of being freed:
## GlbUtils._process_single_collision_node() parents each StaticBody3D it builds under
## the collision mesh node's PARENT, which for the common authoring shape (a "-col"
## mesh parented under the visual mesh it belongs to) is exactly the node being
## retired here. Freeing it would take that prop's collision with it. Leaving the node
## in place costs nothing to render and keeps child transforms in the same frame.
##
## Uses immediate free() rather than queue_free() for the same reason
## GlbUtils.process_collision_meshes() does: the scene may be cached as a template and
## duplicated before a queued free would run.
static func _retire_instanced_source_node(node: MeshInstance3D) -> void:
	if node.get_child_count() > 0:
		node.mesh = null
		return

	var parent := node.get_parent()
	if parent:
		parent.remove_child(node)
	node.free()


## Group every eligible MeshInstance3D under `node` by the instance id of the Mesh
## resource it shares. `group_order` keeps iteration deterministic (Dictionary key
## order in GDScript is insertion order, but relying on that implicitly in a loop that
## mutates the scene tree is the kind of thing that breaks quietly).
static func _collect_instancing_candidates(
	node: Node, animated_ids: Dictionary, groups: Dictionary, group_order: Array
) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst := child as MeshInstance3D
			if _is_instancing_candidate(mesh_inst, animated_ids):
				var key := str(mesh_inst.mesh.get_instance_id())
				if not groups.has(key):
					groups[key] = []
					group_order.append(key)
				groups[key].append(mesh_inst)
		_collect_instancing_candidates(child, animated_ids, groups, group_order)


static func _is_instancing_candidate(mesh_inst: MeshInstance3D, animated_ids: Dictionary) -> bool:
	if not mesh_inst.mesh or not mesh_inst.visible:
		return false
	if mesh_inst.skin:
		return false
	if mesh_inst.material_override or mesh_inst.material_overlay:
		return false
	if animated_ids.has(mesh_inst.get_instance_id()):
		return false
	if _has_collision_suffix(mesh_inst.name):
		return false
	for surface_idx in mesh_inst.get_surface_override_material_count():
		if mesh_inst.get_surface_override_material(surface_idx):
			return false
	return true


static func _has_collision_suffix(node_name: String) -> bool:
	var name_lower := node_name.to_lower()
	for suffix in GlbUtils.COLLISION_SUFFIXES:
		if name_lower.ends_with(suffix):
			return true
	return false


## Accumulate `node`'s transform up to (but excluding) `root`, by walking parents
## rather than reading global_transform -- these scenes are processed before ever
## being added to the SceneTree, and this keeps the result independent of that.
##
## Public purely so it can be tested directly, for the reason
## ScatterGlbUtils._row_to_transform already documents: under the headless/dummy rendering
## driver MultiMesh.get_instance_transform() always reads back identity regardless of
## what was set, so asserting on a built MultiMesh's contents is a dead end and the
## transform math has to be checked on its own.
static func transform_relative_to(node: Node3D, root: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## Instance ids of every node any AnimationPlayer in the scene drives, so a duplicated
## animated prop (30 copies of one windmill) is not frozen into a static MultiMesh.
static func _collect_animated_node_ids(scene: Node, out_ids: Dictionary) -> void:
	var players: Array[Node] = []
	_find_animation_players(scene, players)

	for player_node in players:
		var player := player_node as AnimationPlayer
		var anim_root := player.get_node_or_null(player.root_node)
		if not anim_root:
			continue
		for lib_name in player.get_animation_library_list():
			var lib := player.get_animation_library(lib_name)
			if not lib:
				continue
			for anim_name in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				if not anim:
					continue
				for track_idx in anim.get_track_count():
					# A track path is "Node/Path:property" -- the property subname is
					# not part of the node path, and an empty path targets the
					# AnimationPlayer's own root node.
					var node_path := String(anim.track_get_path(track_idx)).get_slice(":", 0)
					var target: Node = (
						anim_root if node_path.is_empty() else anim_root.get_node_or_null(node_path)
					)
					if target:
						out_ids[target.get_instance_id()] = true


static func _find_animation_players(node: Node, result: Array[Node]) -> void:
	if node is AnimationPlayer:
		result.append(node)
	for child in node.get_children():
		_find_animation_players(child, result)
