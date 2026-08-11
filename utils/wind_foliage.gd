class_name WindFoliage
extends RefCounted

## Wind-sway shader application for scattered foliage built by
## GlbUtils.process_scatter_instances() from terrain-paint's "tt_scatter_instances"
## glTF scene extras (see engine/scatter_instancing.py in the terrain-paint repo).
## Split out of glb_utils.gd (which was pushing gdlint's max-file-lines limit) rather
## than left inline, matching this directory's existing convention of small, focused
## utility files (scale_utils.gd, environment_presets.gd, etc.).
##
## Classification and preset tuning are entirely Godot-side, mirroring the "-water"
## suffix feature's own precedent (a shared, hardcoded ShaderMaterial with "no
## per-map tuning yet") -- there is no Blender-side authoring for this yet. If the
## keyword heuristic below proves unreliable on real biome content, the natural
## extension point is an optional per-object custom ID property on the Geoscatter
## instance-source object (e.g. "tt_wind_category"), read explicitly by
## terrain-paint's engine/scatter_instancing.py and folded into the same
## tt_scatter_instances JSON blob it already writes -- never via Blender's generic
## "Export Custom Properties" glTF option, which that repo's operators/baking.py
## deliberately avoids (it would also leak the addon's own internal tp_uid/layer
## ID properties onto every exported object).

# Checked in this order, deny-list first. A real scattered rock/stone must never
# sway, so it's excluded outright rather than relying on it simply failing to match a
# foliage keyword. Everything else defaults to the "grass" preset rather than "no
# sway": Geoscatter's real, documented asset-naming convention (e.g.
# "FP_Small_Plants_001", "GS Forest seedlings 01", "GS Nettle 01" -- see terrain-paint's
# docs/scatter-integration.md) has no consistent taxonomy keyword, so an
# allow-list-with-no-sway-default would silently leave most real foliage motionless.
const _DENY_KEYWORDS := ["rock", "stone", "boulder"]
const _TREE_KEYWORDS := ["tree", "oak", "pine", "birch", "branch", "canopy"]
const PRESETS := {
	"tree": {"sway_speed": 0.6, "sway_amplitude": 0.06, "sway_frequency": 0.15},
	"grass": {"sway_speed": 1.6, "sway_amplitude": 0.03, "sway_frequency": 0.4},
}

static var _shader: Shader = null
static var _shader_no_aa: Shader = null
static var _shader_debug_trivial: Shader = null
static var _shader_debug_unshaded: Shader = null
static var _shader_debug_cheap_lighting: Shader = null


## Merge a level's foliage_overrides onto a category's base preset. Only
## "<category>_sway_speed" / "<category>_sway_amplitude" keys are recognized --
## sway_frequency is not exposed for per-level tuning. Returns an empty dict for
## an unknown category, matching apply_material's own no-op-for-unknown-category
## behavior.
static func get_effective_preset(category: String, overrides: Dictionary) -> Dictionary:
	if not PRESETS.has(category):
		return {}
	var preset: Dictionary = PRESETS[category].duplicate()
	if overrides.has(category + "_sway_speed"):
		preset["sway_speed"] = overrides[category + "_sway_speed"]
	if overrides.has(category + "_sway_amplitude"):
		preset["sway_amplitude"] = overrides[category + "_sway_amplitude"]
	return preset


## Get the shared wind foliage Shader resource, building it once on first use --
## mirrors WaterGlbUtils._get_water_material()'s lazy-load-once pattern. Unlike water, each
## species still gets its own ShaderMaterial instance (see _build_shader_material):
## only the compiled Shader itself is shared, since the textures differ per species.
static func get_shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/wind_foliage.gdshader")
	return _shader


## Get the no-antialiasing variant Shader (plain ALPHA_SCISSOR cutout, no
## alpha_to_coverage / MSAA dependency) -- used by
## VisualEffectsController.apply_foliage_antialiasing() to swap foliage materials to
## the plain-cutout variant when the player's Antialiasing setting is set to None. See
## shaders/wind_foliage_no_aa.gdshader.
static func get_shader_no_aa() -> Shader:
	if _shader_no_aa == null:
		_shader_no_aa = load("res://shaders/wind_foliage_no_aa.gdshader")
	return _shader_no_aa


## Get the debug-only trivial Shader (unshaded, albedo-only, no PBR/occlusion-fade
## math) used by DebugRenderToggles' "Trivial foliage shader" checkbox to isolate the
## real shader's fragment cost from plain geometry/overdraw cost. See
## shaders/wind_foliage_debug_trivial.gdshader.
static func get_shader_debug_trivial() -> Shader:
	if _shader_debug_trivial == null:
		_shader_debug_trivial = load("res://shaders/wind_foliage_debug_trivial.gdshader")
	return _shader_debug_trivial


## Get the debug-only unshaded-full-textures Shader (same albedo/ORM/normal texture
## sampling as the real shader, but no lighting) used by DebugRenderToggles' "Unshaded
## foliage (full textures)" checkbox to isolate texture-bandwidth cost from
## lighting/BRDF cost. See shaders/wind_foliage_debug_unshaded.gdshader.
static func get_shader_debug_unshaded() -> Shader:
	if _shader_debug_unshaded == null:
		_shader_debug_unshaded = load("res://shaders/wind_foliage_debug_unshaded.gdshader")
	return _shader_debug_unshaded


## Get the debug-only cheap-lighting Shader (identical PBR texture sampling to the
## real shader, but diffuse_lambert + specular_disabled instead of diffuse_burley +
## specular_schlick_ggx) used by DebugRenderToggles' "Cheap lighting foliage" checkbox
## to preview a candidate real fix for the lighting/BRDF cost confirmed by
## get_shader_debug_trivial()/get_shader_debug_unshaded(). See
## shaders/wind_foliage_debug_cheap_lighting.gdshader.
static func get_shader_debug_cheap_lighting() -> Shader:
	if _shader_debug_cheap_lighting == null:
		_shader_debug_cheap_lighting = load(
			"res://shaders/wind_foliage_debug_cheap_lighting.gdshader"
		)
	return _shader_debug_cheap_lighting


## Recursively collect every visible MultiMeshInstance3D tagged as wind foliage
## (either "tree" or "grass" category) under [param node]. Combines both categories
## in one traversal since foliage antialiasing applies to all wind foliage uniformly
## -- unlike DebugRenderToggles (scenes/states/playing/debug_render_toggles.gd),
## which tracks tree/grass separately for independent shadow toggles.
static func _collect_wind_foliage_multimeshes(
	node: Node, result: Array[MultiMeshInstance3D]
) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D and child.visible:
			var category: String = child.get_meta("wind_foliage_category", "")
			if category == "tree" or category == "grass":
				result.append(child as MultiMeshInstance3D)
		_collect_wind_foliage_multimeshes(child, result)


## Like _collect_wind_foliage_multimeshes, but does not filter on visibility --
## a hidden foliage multimesh's material still needs the correct shader applied for
## when it becomes visible again (e.g. after DebugRenderToggles' foliage-visibility
## checkbox or the F4 debug toggle hide it, then the player changes the Antialiasing
## setting while it's hidden).
static func _collect_all_wind_foliage_multimeshes(
	node: Node, result: Array[MultiMeshInstance3D]
) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var category: String = child.get_meta("wind_foliage_category", "")
			if category == "tree" or category == "grass":
				result.append(child as MultiMeshInstance3D)
		_collect_all_wind_foliage_multimeshes(child, result)


## Collect every ShaderMaterial used across all wind-foliage MultiMeshInstance3D
## surfaces under [param map_container] -- used by VisualEffectsController to swap
## every foliage material between the antialiased and plain-cutout shader variants
## when the player's Antialiasing setting changes. Returns an empty array if
## map_container is null or has no wind foliage.
static func collect_foliage_shader_materials(map_container: Node3D) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	if not map_container:
		return result
	var multimeshes: Array[MultiMeshInstance3D] = []
	_collect_all_wind_foliage_multimeshes(map_container, multimeshes)
	for mm_inst in multimeshes:
		if not mm_inst.multimesh or not mm_inst.multimesh.mesh:
			continue
		var mesh := mm_inst.multimesh.mesh
		for surface_idx in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface_idx)
			if mat is ShaderMaterial and mat not in result:
				result.append(mat as ShaderMaterial)
	return result


## Classifies a Geoscatter instance-source object's name into a PRESETS key, or "" for
## "never sway" -- pure and case-insensitive so it's directly unit-testable against
## real documented Geoscatter asset names. Deny-list (rocks/stones) is checked before
## the tree keywords so a hypothetical "Rock Garden Tree" name can't slip through --
## not a real case today, but the check is free either way.
static func classify_category(instance_name: String) -> String:
	var lower_name := instance_name.to_lower()
	for keyword in _DENY_KEYWORDS:
		if lower_name.contains(keyword):
			return ""
	for keyword in _TREE_KEYWORDS:
		if lower_name.contains(keyword):
			return "tree"
	return "grass"


## Builds a fresh ShaderMaterial for one species: harvests albedo/normal/ORM textures
## off `source` (the material terrain-paint baked and Blender's glTF exporter/Godot's
## glTF importer already resolved onto the source mesh's surface) and applies the
## given category's wind preset. Not cached beyond the shared Shader resource (see
## get_shader) -- each call's harvested textures are per-map Texture2D resources
## parsed fresh on every load_glb call, so a static ShaderMaterial cache would only
## ever accumulate stale per-map texture references for no benefit, since this runs
## once per unique instance_name per load anyway.
static func _build_shader_material(
	source: BaseMaterial3D, preset: Dictionary, category: String
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = get_shader()
	# Tagged so LevelEnvironmentManager.store_wind_materials() can find and re-tune
	# this exact material instance later without re-walking or reloading the scene.
	material.set_meta("wind_category", category)
	material.set_shader_parameter("albedo_texture", source.albedo_texture)
	if source is ORMMaterial3D and source.orm_texture:
		material.set_shader_parameter("orm_texture", source.orm_texture)
	elif source is StandardMaterial3D and source.metallic_texture:
		# Godot's glTF importer does not create ORMMaterial3D for terrain-paint's
		# packed R=Occlusion/G=Roughness/B=Metallic bake -- it imports as
		# StandardMaterial3D with ao_texture/metallic_texture/roughness_texture
		# all pointing at the same shared packed image. metallic_texture is as
		# good a handle on that shared image as any of the three.
		material.set_shader_parameter("orm_texture", source.metallic_texture)
	if source.normal_enabled and source.normal_texture:
		material.set_shader_parameter("normal_texture", source.normal_texture)
		material.set_shader_parameter("has_normal_texture", true)
	for param_name in preset.keys():
		material.set_shader_parameter(param_name, preset[param_name])
	return material


## Applies the wind-sway shader to every surface of `mesh` independently, by mutating
## each surface's OWN material directly (mesh.surface_set_material) -- confirmed via a
## real headless probe that MultiMeshInstance3D has no set_surface_override_material
## method at all (unlike MeshInstance3D, it does not extend that class -- it only
## inherits GeometryInstance3D's single, whole-mesh material_override). Mutating the
## Mesh resource in place is safe here: by the time this runs, mesh_node (the only
## other thing that referenced it) is about to be freed, and this Mesh resource isn't
## shared with anything else in the scene.
##
## Deliberately per-surface, not a single material_override -- a real Geoscatter asset
## can have multiple materials on disjoint faces of one mesh (terrain-paint's docs
## document "GS Forest seedlings 01" as leaf+stem materials on one object), and
## material_override would apply whichever surface's texture set got harvested to
## every surface, silently painting the wrong texture onto the others. No-op if
## category is "" (the mesh keeps its own imported static material, e.g. a scattered
## rock). Optional `overrides` allows per-level tuning of sway speed and amplitude.
static func apply_material(mesh: Mesh, category: String, overrides: Dictionary = {}) -> void:
	if category == "" or not PRESETS.has(category):
		return
	var preset := get_effective_preset(category, overrides)
	for i in mesh.get_surface_count():
		var source_material := mesh.surface_get_material(i)
		if not source_material is BaseMaterial3D:
			continue
		var wind_material := _build_shader_material(source_material, preset, category)
		mesh.surface_set_material(i, wind_material)
