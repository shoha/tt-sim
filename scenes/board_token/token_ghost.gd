class_name TokenGhost
extends RefCounted

## The token ghost: a token that foliage, a trunk, a rock or a wall covers is drawn a second
## time as a translucent silhouette in its own palette colours with an ink rim (gold while
## it is selected or hovered), only on the pixels the depth buffer says are covered
## (shaders/token_ghost.gdshader, a material_overlay on every mesh of the token). Nothing in
## the plants or the map changes, so nothing carves, moves or flickers as the camera pans, and
## it works for any occluder and both foliage libraries (it reads no foliage material).
## The token's own parts never count as the cover (a large creature's body over its far legs):
## each overlay carries the body's bounding cylinder (body_bounds) and the shader ignores
## whatever lies within it on the way to the camera (docs/PERFORMANCE.md "self-occlusion fix").
## Settings > Graphics > "Token ghost" (graphics/token_ghost_enabled, default on).
## The decision, captures and measurements: docs/PERFORMANCE.md "Token ghost" and
## D:/dev/plantgen/docs/ttsim_token_visibility.md.
##
## Dressing follows the token's life, not a timer: BoardTokenFactory._assemble_token (every
## token), BoardTokenFactory.apply_model_upgrade (a placeholder getting its model),
## AvatarTokenFactory.set_recipe (new parts or colours), BoardToken highlight and
## visibility changes, DraggableToken.set_submerged, and the Settings toggle (set_enabled).
## dress() is idempotent: it adds, keeps or rebuilds the overlays a token needs.
##
## Rules:
## - A token hidden from players (the GM sees it dithered or at 40 percent alpha) gets no ghost.
## - A token the water hides (its SubmergedMarker showing; TokenWater.update_cue re-dresses)
##   gets no ghost: the marker is its cue.
## - A dragged token keeps its ghost, which helps place it under a crown.
## - A placeholder (loading) model gets none; the upgrade dresses the real model.
## - A pack token with several materials ghosts in its first material's colour.
## - Cost: one extra draw call per mesh of an on-screen token (about 18 for an avatar). The
##   frustum culls the rest. Above BUDGET_TOKENS on-screen tokens the extra ones go
##   undressed (apply_budget): the selected and hovered first, then the nearest the screen
##   centre.

const DEFAULT_ENABLED := true
const SHADER := preload("res://shaders/token_ghost.gdshader")
## Meta on an overlay material we made, and on it the source (palette texture or material)
## its colours were read from, so a changed look rebuilds it.
const GHOST_META := &"token_ghost"
const SOURCE_META := &"token_ghost_source"
## Meta on a BoardToken the budget left undressed.
const TRIMMED_META := &"token_ghost_trimmed"
## Meta on a BoardToken made off the tree that waits to be dressed again once it is in it.
const PENDING_META := &"token_ghost_pending"
## Drawn after the foliage and the water.
const RENDER_PRIORITY := 8
## The rim of a selected or hovered token's ghost (the selection glow's gold).
const SELECTED_RIM := Color.GOLD
## The ghost's fill opacity where the token is covered, and how much the rim adds on top of
## it (the shader's ghost_alpha and rim_alpha defaults; a test keeps them equal). The fill was
## 0.78 in the first prototype; it is 0.54 since 2026-10-24 (the user asked for the covered part
## to be a bit less opaque), with the rim boost raised from 0.4 to 0.5 so the ink line stays
## as solid as before.
const FILL_ALPHA := 0.54
const RIM_ALPHA := 0.5
## At most this many on-screen tokens are dressed at once, and how often the budget looks.
const BUDGET_TOKENS := 16
const BUDGET_PERIOD_S := 0.5
## Height above a token's base the budget aims at (the figure's chest), metres.
const CHEST_HEIGHT_M := 0.9
## Child names that are not the token's body.
const SKIPPED_NAMES: Array[StringName] = [&"PlaceholderModel"]

static var enabled := DEFAULT_ENABLED
## The budget in force (BUDGET_TOKENS; a render probe changes it to measure the cost without it).
static var budget := BUDGET_TOKENS
static var _trimmed := false


## Turns the ghost on or off for every token under `tree` and for the tokens made later.
static func set_enabled(on: bool, tree: SceneTree) -> void:
	enabled = on
	_trimmed = false
	if tree != null:
		for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
			if node.has_meta(TRIMMED_META):
				node.remove_meta(TRIMMED_META)
		refresh_all(tree)


## Dresses every token under `tree` to match the current setting (after a map load).
static func refresh_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
		dress(node as BoardToken)


## Whether `token` gets no ghost right now (see the rules above).
static func suppressed(token: BoardToken) -> bool:
	if not token.is_visible_to_players or token.has_meta(TRIMMED_META):
		return true
	var draggable := token.get_dragging_object()
	return draggable != null and draggable.is_submerged_cue_shown()


## Puts the ghost on every mesh of `token`'s body, or takes it off, as the setting and the
## rules say; the rim follows the token's highlight. Safe to call at any time and often.
static func dress(token: BoardToken) -> void:
	if token == null or token.rigid_body == null:
		return
	var on := enabled and not suppressed(token)
	var meshes := meshes_of(token.rigid_body)
	var bounds := body_bounds(token.rigid_body, meshes) if on else {}
	if on and not token.rigid_body.is_inside_tree():
		# Made off the tree (the factories): the bounds need world transforms, so dress again
		# once the body enters it.
		if not token.has_meta(PENDING_META):
			token.set_meta(PENDING_META, true)
			token.rigid_body.tree_entered.connect(
				func() -> void:
					if is_instance_valid(token):
						token.remove_meta(PENDING_META)
						dress(token),
				CONNECT_ONE_SHOT | CONNECT_DEFERRED
			)
	for mi in meshes:
		if on:
			_dress_mesh(mi, token.is_highlighted, bounds)
		else:
			_strip_mesh(mi)


## The token body's bounding cylinder in the body's own frame and metres: {"center": Vector3,
## "radius": float (horizontal, from the centre to the farthest corner, so a turn of the token
## does not change it), "half_height": float}; empty when no mesh is in the tree yet. The
## shader measures how far a view ray runs inside it (see the shader's header).
static func body_bounds(body: Node3D, meshes: Array[MeshInstance3D]) -> Dictionary:
	if not body.is_inside_tree():
		return {}
	var to_body := body.global_transform.affine_inverse()
	var corners := PackedVector3Array()
	for mi in meshes:
		if not mi.is_inside_tree():
			continue
		var aabb := mi.get_aabb()
		var rel := to_body * mi.global_transform
		for i in 8:
			corners.append(rel * aabb.get_endpoint(i))
	if corners.is_empty():
		return {}
	var lo := corners[0]
	var hi := corners[0]
	for p in corners:
		lo = lo.min(p)
		hi = hi.max(p)
	var centre := (lo + hi) * 0.5
	var radius := 0.0
	for p in corners:
		radius = maxf(radius, Vector2(p.x - centre.x, p.z - centre.z).length())
	return {"center": centre, "radius": radius, "half_height": (hi.y - lo.y) * 0.5}


## Hands `bounds` (body_bounds) to one mesh's overlay in that mesh's own space, which is where
## the shader reads them: the centre moved into the mesh's frame, and the body's up axis in
## it, whose length through the mesh's world transform is the body's world scale (exact
## whatever scale the mesh itself carries).
static func _set_bounds(ghost: ShaderMaterial, mi: MeshInstance3D, bounds: Dictionary) -> void:
	var body: Node = mi.get_parent()
	while body != null and not body is RigidBody3D:
		body = body.get_parent()
	if bounds.is_empty() or body == null:
		ghost.set_shader_parameter("bound_extent", Vector2.ZERO)
		return
	var to_mesh := mi.global_transform.affine_inverse() * (body as Node3D).global_transform
	ghost.set_shader_parameter("bound_center", to_mesh * (bounds.center as Vector3))
	ghost.set_shader_parameter("bound_up", to_mesh.basis * Vector3.UP)
	ghost.set_shader_parameter(
		"bound_extent", Vector2(bounds.radius as float, bounds.half_height as float)
	)


## Every MeshInstance3D of a token's body: not the selection glow, the submerged marker or a
## loading placeholder.
static func meshes_of(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if (
			child is SelectionGlowRenderer
			or child is SubmergedMarker
			or SKIPPED_NAMES.has(child.name)
		):
			continue
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			out.append(child as MeshInstance3D)
		out.append_array(meshes_of(child))
	return out


## The overlay on `mi` when it is one of ours, else null.
static func overlay_of(mi: MeshInstance3D) -> ShaderMaterial:
	var current := mi.material_overlay
	if current is ShaderMaterial and current.has_meta(GHOST_META):
		return current as ShaderMaterial
	return null


static func _strip_mesh(mi: MeshInstance3D) -> void:
	if overlay_of(mi) != null:
		mi.material_overlay = null


static func _dress_mesh(mi: MeshInstance3D, highlighted: bool, bounds: Dictionary) -> void:
	var source: Variant = _source_of(mi)
	var ghost := overlay_of(mi)
	if ghost == null or ghost.get_meta(SOURCE_META) != source:
		ghost = _make_ghost(source)
		mi.material_overlay = ghost
	_set_rim(ghost, highlighted)
	_set_bounds(ghost, mi, bounds)


## What a mesh's colours come from: an avatar part's palette texture, or a pack mesh's
## material (its first surface's), or null for neither.
static func _source_of(mi: MeshInstance3D) -> Variant:
	var own := mi.material_override
	if own is ShaderMaterial:
		var palette: Variant = (own as ShaderMaterial).get_shader_parameter("palette")
		if palette != null:
			return palette
	var src: Material = own
	if src == null:
		src = mi.get_surface_override_material(0)
	if src == null and mi.mesh != null:
		src = mi.mesh.surface_get_material(0)
	return src if src is BaseMaterial3D else null


static func _make_ghost(source: Variant) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = RENDER_PRIORITY
	mat.set_meta(GHOST_META, true)
	mat.set_meta(SOURCE_META, source)
	mat.set_shader_parameter("ghost_alpha", FILL_ALPHA)
	mat.set_shader_parameter("rim_alpha", RIM_ALPHA)
	if source is Texture2D:
		mat.set_shader_parameter("use_palette", true)
		mat.set_shader_parameter("palette", source)
	elif source is BaseMaterial3D:
		var base := source as BaseMaterial3D
		mat.set_shader_parameter("use_albedo", true)
		mat.set_shader_parameter("albedo_col", base.albedo_color)
		if base.albedo_texture != null:
			mat.set_shader_parameter("albedo_tex", base.albedo_texture)
	return mat


## A selected or hovered token's rim is the selection glow's gold (the glow disc itself is
## hidden by the foliage); otherwise the shader's own ink rim (null puts the default back).
static func _set_rim(ghost: ShaderMaterial, highlighted: bool) -> void:
	ghost.set_shader_parameter("rim_color", SELECTED_RIM if highlighted else null)
	ghost.set_shader_parameter("rim_strength", 1.0 if highlighted else null)


## Which of `candidates` ({id, highlighted: bool, distance: float}, the distance from the
## screen centre) stay dressed under a budget of `budget`: the highlighted first, then the
## nearest. Returns {id: true}.
static func allowed(candidates: Array[Dictionary], budget: int) -> Dictionary:
	var order := candidates.duplicate()
	order.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.highlighted != b.highlighted:
				return a.highlighted
			return a.distance < b.distance
	)
	var out := {}
	for i in mini(budget, order.size()):
		out[order[i].id] = true
	return out


## Keeps the on-screen dressed tokens within BUDGET_TOKENS (the off-screen ones cost nothing:
## the frustum culls their overlays). Does nothing, and costs one group read, while the count
## is within the budget. Run every BUDGET_PERIOD_S by VisualEffectsController.
static func apply_budget(tree: SceneTree, camera: Camera3D) -> void:
	if not enabled or tree == null or camera == null:
		return
	var tokens := tree.get_nodes_in_group(BoardToken.GROUP_NAME)
	if tokens.size() <= budget and not _trimmed:
		return
	var centre := camera.get_viewport().get_visible_rect().size * 0.5
	var candidates: Array[Dictionary] = []
	var by_id := {}
	for node in tokens:
		var token := node as BoardToken
		if token.rigid_body == null:
			continue
		var chest := token.rigid_body.global_position + Vector3.UP * CHEST_HEIGHT_M
		if not camera.is_position_in_frustum(chest):
			by_id[token.get_instance_id()] = token
			continue
		by_id[token.get_instance_id()] = token
		candidates.append(
			{
				"id": token.get_instance_id(),
				"highlighted": token.is_highlighted,
				"distance": camera.unproject_position(chest).distance_to(centre),
			}
		)
	var keep := allowed(candidates, budget)
	var on_screen := {}
	for c in candidates:
		on_screen[c.id] = true
	_trimmed = false
	for id in by_id:
		var token: BoardToken = by_id[id]
		var trim: bool = on_screen.has(id) and not keep.has(id)
		_trimmed = _trimmed or trim
		if trim != token.has_meta(TRIMMED_META):
			if trim:
				token.set_meta(TRIMMED_META, true)
			else:
				token.remove_meta(TRIMMED_META)
			dress(token)
