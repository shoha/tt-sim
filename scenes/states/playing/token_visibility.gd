class_name TokenVisibility
extends RefCounted

## Prototype switchboard for the token visibility options (topic tokenvis, all off by default).
## The close-zoom canopy fade carves a window of thinned plants round the screen centre; these
## options let a token show in heavy foliage without it. The write-up and captures are in
## D:/dev/plantgen/docs/ttsim_token_visibility.md. Three options, each reachable from the F3
## panel (DebugRenderToggles) and from the render-job probe `tokenvis.gd mode`:
## - ghost: a see-through silhouette of the token drawn over whatever hides it
##   (shaders/token_ghost.gdshader, a material_overlay on the token's meshes);
## - window: the occlusion fade's per-token zone dissolved card by card, bold shapes instead
##   of a stipple (wind_foliage_include `token_window`);
## - anchor: the canopy window moved from the screen centre onto the selected or hovered
##   token, small and steady (CanopyFade.anchor_*).

const GHOST_SHADER := preload("res://shaders/token_ghost.gdshader")
const GHOST_META := &"tokenvis_ghost"
## The anchored canopy window: inner and outer radius and the depth band, metres.
const ANCHOR_SHAPE := Vector4(1.3, 3.2, 4.0, 0.0)
## The rim of a selected or hovered token's ghost (the selection glow's gold).
const SELECTED_RIM := Color.GOLD


## Sets the prototype state from a render-job step (probes/tokenvis.gd `mode`):
## - `reset`: the shipped state (canopy fade and occlusion fade on, every prototype off).
## - `canopy` (bool): the centre-anchored close-zoom canopy fade (CanopyFade.enabled).
## - `occlusion` (bool): the OcclusionFadeManager's per-token fade (map geometry, tree cards).
## - `ghost` (bool) with optional `ghost_params` ({uniform: value}); `window` (bool) with
##   `scale` and `core`; `anchor` (bool) with `inner`, `outer`, `band`.
static func set_mode(gm: GameMap, step: Dictionary) -> String:
	var log := PackedStringArray()
	if bool(step.get("reset", false)):
		gm.set_occlusion_fade_enabled(true)
		CanopyFade.enabled = true
		set_ghost(gm, false)
		set_window(gm, false)
		set_anchor(gm, false)
		log.append("reset")
	if step.has("occlusion"):
		gm.set_occlusion_fade_enabled(bool(step.occlusion))
		log.append("occlusion %s" % str(step.occlusion))
	if step.has("canopy"):
		CanopyFade.enabled = bool(step.canopy)
		log.append("canopy %s" % str(step.canopy))
	if step.has("ghost"):
		set_ghost(gm, bool(step.ghost), step.get("ghost_params", {}), bool(step.get("gate", false)))
		log.append("ghost %s" % str(step.ghost))
	if step.has("window"):
		set_window(gm, bool(step.window), float(step.get("scale", 1.4)), float(step.get("core", 0.6)))
		log.append("window %s" % str(step.window))
	if step.has("anchor"):
		var shape := Vector4(
			float(step.get("inner", ANCHOR_SHAPE.x)),
			float(step.get("outer", ANCHOR_SHAPE.y)),
			float(step.get("band", ANCHOR_SHAPE.z)),
			0.0
		)
		set_anchor(gm, bool(step.anchor), shape)
		log.append("anchor %s" % str(step.anchor))
	return ", ".join(log)


static func driver(gm: GameMap) -> TokenVisibilityDriver:
	var existing := gm.get_node_or_null(TokenVisibilityDriver.NAME) as TokenVisibilityDriver
	if existing != null:
		return existing
	var made := TokenVisibilityDriver.new()
	gm.add_child(made)
	made.setup(gm)
	return made


static func set_ghost(
	gm: GameMap, on: bool, params: Dictionary = {}, gate: bool = false
) -> void:
	var d := driver(gm)
	d.ghost = on
	d.gate = gate
	# JSON gives colours as arrays; the shader wants Colors.
	var coerced := {}
	for key in params:
		var v: Variant = params[key]
		coerced[key] = _colour_of(v) if v is Array else v
	d.ghost_params = coerced
	# A fresh overlay per call, so a parameter change shows.
	d.dress_all(false)
	d.dress_all(on)


## A probe's `[r, g, b, a]` (0 to 1) as a Color.
static func _colour_of(v: Array) -> Color:
	var alpha: float = v[3] if v.size() > 3 else 1.0
	return Color.from_rgba8(
		roundi(float(v[0]) * 255.0),
		roundi(float(v[1]) * 255.0),
		roundi(float(v[2]) * 255.0),
		roundi(alpha * 255.0)
	)


static func set_window(gm: GameMap, on: bool, scale: float = 1.4, core: float = 0.6) -> void:
	var fade := gm.occlusion_fade as OcclusionFadeManager
	if fade != null:
		fade.set_token_window(on, scale, core)


static func set_anchor(gm: GameMap, on: bool, shape: Vector4 = ANCHOR_SHAPE) -> void:
	var d := driver(gm)
	d.anchor = on
	CanopyFade.anchor_on = on
	CanopyFade.anchor_shape = shape
	CanopyFade.anchor_has_point = false


## Puts the ghost overlay on (or takes it off) every mesh of `token`'s body, leaving the
## selection glow and the submerged marker alone. A part keeps its overlay once dressed.
static func dress_token(token: BoardToken, on: bool, params: Dictionary = {}) -> void:
	if token.rigid_body == null:
		return
	# A selected or hovered token's ghost takes the selection glow's gold on its rim, so the
	# cue the foliage hides on the ground (the glow disc) still shows.
	var look := params.duplicate()
	if token.is_highlighted:
		look["rim_color"] = SELECTED_RIM
		look["rim_strength"] = 1.0
	else:
		look.erase("highlight_rim")
	for mi in _meshes(token.rigid_body):
		var current := mi.material_overlay
		if not on:
			if current != null and current.has_meta(GHOST_META):
				mi.material_overlay = null
			continue
		if current != null and current.has_meta(GHOST_META):
			var ghost := current as ShaderMaterial
			if token.is_highlighted:
				for key in look:
					ghost.set_shader_parameter(String(key), look[key])
			else:
				# Null puts the shader's own default back.
				for key in ["rim_color", "rim_strength"]:
					ghost.set_shader_parameter(String(key), params.get(key))
			continue
		mi.material_overlay = _ghost_for(mi, look)


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is SelectionGlowRenderer or child is SubmergedMarker:
			continue
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			out.append(child as MeshInstance3D)
		out.append_array(_meshes(child))
	return out


static func _ghost_for(mi: MeshInstance3D, params: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GHOST_SHADER
	mat.render_priority = 8
	mat.set_meta(GHOST_META, true)
	var own := mi.material_override
	if own is ShaderMaterial and (own as ShaderMaterial).get_shader_parameter("palette") != null:
		mat.set_shader_parameter("use_palette", true)
		mat.set_shader_parameter("palette", (own as ShaderMaterial).get_shader_parameter("palette"))
	else:
		var src: Material = own
		if src == null:
			src = mi.get_surface_override_material(0)
		if src == null and mi.mesh != null:
			src = mi.mesh.surface_get_material(0)
		if src is BaseMaterial3D:
			var base := src as BaseMaterial3D
			mat.set_shader_parameter("use_albedo", true)
			mat.set_shader_parameter("albedo_col", base.albedo_color)
			if base.albedo_texture != null:
				mat.set_shader_parameter("albedo_tex", base.albedo_texture)
	for key in params:
		mat.set_shader_parameter(String(key), params[key])
	return mat
