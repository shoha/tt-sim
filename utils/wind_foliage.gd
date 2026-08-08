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
## mirrors GlbUtils._get_water_material()'s lazy-load-once pattern. Unlike water, each
## species still gets its own ShaderMaterial instance (see _build_shader_material):
## only the compiled Shader itself is shared, since the textures differ per species.
static func get_shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/wind_foliage.gdshader")
	return _shader


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
	if source is ORMMaterial3D:
		material.set_shader_parameter("orm_texture", source.orm_texture)
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
