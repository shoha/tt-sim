class_name TokenGhost
extends RefCounted

## The token ghost: a token that foliage, a trunk, a rock or a wall covers is drawn a second
## time as an outline of its silhouette, a line of constant width in screen pixels in the token's
## own most vivid colour (gold while it is selected or hovered; see the Style variants), only on
## the pixels the depth buffer says are covered (shaders/token_ghost.gdshader, a
## material_overlay on every mesh of the token). Nothing in
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
## - Cost: two extra draw calls per mesh of an on-screen token since painter-look-ghost2 (the
##   mask pass and the line pass; was one, about 18 for an avatar, now about 36). The
##   frustum culls the rest. Above BUDGET_TOKENS on-screen tokens the extra ones go
##   undressed (apply_budget): the selected and hovered first, then the nearest the screen
##   centre.

## The outline variants (see STYLE_PARAMS).
enum Style { OUTLINE, DOUBLE, DRAWN }

const DEFAULT_ENABLED := true
const SHADER := preload("res://shaders/token_ghost.gdshader")
const MASK_SHADER := preload("res://shaders/token_ghost_mark.gdshader")
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
## The ghost is ONE line round the outer silhouette of the covered part (painter-look-ghost2,
## 2026-11-15; the owner: "just the outermost edges would be lined", no fill, no part edges, no
## translucent model): constant width in screen pixels (the shader's header says how the union
## of the token's meshes is outlined), in the token's own most vivid colour, gold while it is
## selected or hovered. The variants, all in STYLE_PARAMS: OUTLINE the plain single line, DOUBLE
## a dark outer line with a thin light one inside it (reads on pale snow and dark spruce alike),
## DRAWN the single line with a hand-drawn wander of its width. `style` is the one in force;
## docs/PERFORMANCE.md "Token ghost outline" has the captures and the reasons.
const STYLE_PARAMS := {
	Style.OUTLINE: {"line_px": 3.2, "inner_px": 0.0, "wobble_px": 0.0},
	Style.DOUBLE: {"line_px": 1.5, "inner_px": 2.7, "wobble_px": 0.0},
	Style.DRAWN: {"line_px": 3.2, "inner_px": 0.0, "wobble_px": 0.8},
}
## A selected or hovered token's line is this much wider.
const SELECTED_WIDTH := 1.35
## Meta on an overlay recording the look it was made for (a change of look or style rebuilds it).
const LOOK_META := &"token_ghost_look"
## At most this many on-screen tokens are dressed at once, and how often the budget looks.
const BUDGET_TOKENS := 16
const BUDGET_PERIOD_S := 0.5
## Height above a token's base the budget aims at (the figure's chest), metres.
const CHEST_HEIGHT_M := 0.9
## Child names that are not the token's body.
const SKIPPED_NAMES: Array[StringName] = [&"PlaceholderModel"]

static var enabled := DEFAULT_ENABLED
## Whether the level is drawn in the painted look (LevelEnvironmentManager sets it; see
## PAINTED_WOBBLE_PX). Static, so it outlives the manager and reaches tokens made later.
static var painted := false
## The outline variant in force (STYLE_PARAMS; a render probe switches it with set_style).
static var style: int = Style.DOUBLE
## The shared mask pass material (mask_material).
static var _mask: ShaderMaterial = null
## The budget in force (BUDGET_TOKENS; a render probe changes it to measure the cost without it).
static var budget := BUDGET_TOKENS
static var _trimmed := false
## What the last budget pass saw (_seen_by_budget): a pass that would see the same is skipped,
## since it would trim the same tokens (it cost 2 ms every BUDGET_PERIOD_S at 500 tokens).
static var _last_seen := PackedFloat64Array()


## Turns the ghost on or off for every token under `tree` and for the tokens made later.
static func set_enabled(on: bool, tree: SceneTree) -> void:
	enabled = on
	_trimmed = false
	_last_seen = PackedFloat64Array()
	if tree != null:
		for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
			if node.has_meta(TRIMMED_META):
				node.remove_meta(TRIMMED_META)
		refresh_all(tree)


## Switches the ghost between the Classic and the painted parameter set for every token under
## `tree` and the tokens made later; does nothing when the look did not change.
static func set_painted(on: bool, tree: SceneTree) -> void:
	if on == painted:
		return
	painted = on
	refresh_all(tree)


## Switches the outline variant (Style) for every token under `tree` and the tokens made later.
static func set_style(new_style: int, tree: SceneTree) -> void:
	if new_style == style:
		return
	style = new_style
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
	var vivid := TokenColours.vivid_of_meshes(meshes, true) if on else Color.WHITE
	if on and not token.rigid_body.is_inside_tree():
		# Made off the tree (the factories): the bounds need world transforms, so dress again
		# once the body enters it.
		if not token.has_meta(PENDING_META):
			token.set_meta(PENDING_META, true)
			token.rigid_body.tree_entered.connect(
				_dress_entered.bind(token.get_instance_id()), CONNECT_ONE_SHOT | CONNECT_DEFERRED
			)
	for mi in meshes:
		if on:
			_dress_mesh(mi, token.is_highlighted, bounds, vivid)
		else:
			_strip_mesh(mi)


## The deferred second dressing of a token made off the tree (by instance id: the token may be
## gone by then, and a bound object that was freed is an engine error).
static func _dress_entered(id: int) -> void:
	var token := instance_from_id(id) as BoardToken
	if token != null:
		token.remove_meta(PENDING_META)
		dress(token)


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


static func _dress_mesh(
	mi: MeshInstance3D, highlighted: bool, bounds: Dictionary, vivid: Color
) -> void:
	var source: Variant = source_of(mi)
	var ghost := overlay_of(mi)
	# A mesh with no material has a null source, which set_meta stores as no meta at all (and
	# get_meta with a null default still reports a missing key)
	var had: Variant = null
	if ghost != null and ghost.has_meta(SOURCE_META):
		had = ghost.get_meta(SOURCE_META)
	if ghost == null or had != source or ghost.get_meta(LOOK_META, -1) != look_key():
		ghost = _make_ghost(source)
		mi.material_overlay = ghost
	_set_stroke(ghost, highlighted, vivid)
	_set_bounds(ghost, mi, bounds)


## What a mesh's colours come from: an avatar part's palette texture, or a pack mesh's
## material (its first surface's), or null for neither.
static func source_of(mi: MeshInstance3D) -> Variant:
	var own := mi.material_override
	# An avatar's baked figure (AvatarTokenView) carries its parts' materials as surface
	# overrides; every part of a figure shares its palette.
	var first: Material = own
	if first == null and mi.get_surface_override_material_count() > 0:
		first = mi.get_surface_override_material(0)
	if first is ShaderMaterial:
		var palette: Variant = (first as ShaderMaterial).get_shader_parameter("palette")
		if palette != null:
			return palette
	var src: Material = own
	if src == null:
		# A painted mesh (TokenToon) shows a ShaderMaterial; its colours are the original's.
		src = TokenToon.source_of(mi, 0)
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
	mat.set_meta(LOOK_META, look_key())
	# The mask pass (one material for every mesh) is drawn first, by priority.
	mat.next_pass = mask_material()
	return mat


## The shared mask pass: writes the nearest depth on every pixel a token's meshes cover, so the
## outline pass (shaders/token_ghost.gdshader) draws only outside their union.
static func mask_material() -> ShaderMaterial:
	if _mask == null:
		_mask = ShaderMaterial.new()
		_mask.shader = MASK_SHADER
		_mask.render_priority = RENDER_PRIORITY - 1
	return _mask


## What an overlay was made for: the look and the outline variant (a change rebuilds it).
static func look_key() -> int:
	return (10 if painted else 0) + style


## `colour` made readable as a line on the board: at least 60 percent saturated (a grey stays
## grey) and bright.
static func readable(colour: Color) -> Color:
	var saturation := colour.s if colour.s < 0.15 else maxf(colour.s, 0.6)
	return Color.from_hsv(colour.h, saturation, maxf(colour.v, 0.92))


## The stroke colours for a token whose most vivid colour is `vivid`: {"line", "inner"}. A single
## stroke is the readable colour itself; a double one is a deep dark of the hue outside and the
## readable colour lightened inside. A selected or hovered token's is the selection glow's gold
## (the glow disc itself is hidden by the foliage), whatever its own colour.
static func stroke_colours(vivid: Color, highlighted: bool, double: bool) -> Dictionary:
	var base := SELECTED_RIM if highlighted else readable(vivid)
	if not double:
		return {"line": base, "inner": base}
	var dark := Color.from_hsv(base.h, minf(base.s + 0.15, 1.0), 0.22)
	# A leaf-green token seen through leaves: its light core goes near white, the one tone the
	# foliage does not have.
	var leafy := (
		base.s > 0.25
		and base.h > TokenColours.FOLIAGE_HUE_MIN
		and base.h < TokenColours.FOLIAGE_HUE_MAX
	)
	return {"line": dark, "inner": base.lerp(Color.WHITE, 0.85 if leafy else 0.6)}


## Sets the overlay's stroke: colours and widths from the style and the token's highlight.
static func _set_stroke(ghost: ShaderMaterial, highlighted: bool, vivid: Color) -> void:
	var params: Dictionary = STYLE_PARAMS[style]
	var inner_px: float = params.inner_px
	var colours := stroke_colours(vivid, highlighted, inner_px > 0.0)
	var width := SELECTED_WIDTH if highlighted else 1.0
	ghost.set_shader_parameter("line_colour", colours.line)
	ghost.set_shader_parameter("line_inner", colours.inner)
	ghost.set_shader_parameter("line_px", (params.line_px as float) * width)
	ghost.set_shader_parameter("inner_px", inner_px * width)
	ghost.set_shader_parameter("wobble_px", params.wobble_px)


## Which of `candidates` ({id, highlighted: bool, distance: float}, the distance from the
## screen centre) stay dressed under a budget of `limit`: the highlighted first, then the
## nearest. Returns {id: true}.
static func allowed(candidates: Array[Dictionary], limit: int) -> Dictionary:
	var order := candidates.duplicate()
	order.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.highlighted != b.highlighted:
				return a.highlighted
			return a.distance < b.distance
	)
	var out := {}
	for i in mini(limit, order.size()):
		out[order[i].id] = true
	return out


## Keeps the on-screen dressed tokens within BUDGET_TOKENS (the off-screen ones cost nothing:
## the frustum culls their overlays). Does nothing, and costs one group read, while the count
## is within the budget, or when the camera and every token are where the last pass saw them.
## Run every BUDGET_PERIOD_S by VisualEffectsController.
static func apply_budget(tree: SceneTree, camera: Camera3D) -> void:
	if not enabled or tree == null or camera == null:
		return
	var tokens := tree.get_nodes_in_group(BoardToken.GROUP_NAME)
	if tokens.size() <= budget and not _trimmed:
		return
	var seen := _seen_by_budget(tokens, camera)
	if seen == _last_seen:
		return
	_last_seen = seen
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


## What a budget pass depends on, as numbers: the camera's transform and lens, the view's size,
## the budget, and per token its id (the low 32 bits), its body's place and its highlight.
static func _seen_by_budget(tokens: Array[Node], camera: Camera3D) -> PackedFloat64Array:
	var xf := camera.global_transform
	var view := camera.get_viewport().get_visible_rect().size
	var b := xf.basis
	var head := [xf.origin.x, xf.origin.y, xf.origin.z, b.x.x, b.x.y, b.x.z, b.y.x, b.y.y]
	head.append_array([b.y.z, b.z.x, b.z.y, b.z.z, camera.fov, camera.size, view.x, view.y])
	head.append(budget)
	var out := PackedFloat64Array(head)
	var i := out.size()
	out.resize(i + tokens.size() * 5)
	for node in tokens:
		var token := node as BoardToken
		var at := token.rigid_body.global_position if token.rigid_body else Vector3.INF
		out[i] = token.get_instance_id() & 0xFFFFFFFF
		out[i + 1] = at.x
		out[i + 2] = at.y
		out[i + 3] = at.z
		out[i + 4] = 1.0 if token.is_highlighted else 0.0
		i += 5
	return out
