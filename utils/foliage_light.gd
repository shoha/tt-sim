class_name FoliageLight
extends RefCounted

## The painted foliage light: how a tree's leaf material is chosen for it and how the sun
## reaches it. The model and contract are docs/ASSET_PIPELINE.md section 6 "Painted foliage
## light": treecube writes the glTF material extra {"tt_foliage_light": "painted"} on the leaf
## material of its round 5 clump-style broadleaf trees and bushes (each clump's cards painted
## one flat tone, the clump's light carried by its normals) and of its pines' drooping roof
## fronds (treecube 12fee28), and Godot keeps it as the
## material's "extras" metadata through both the palette's editor import and a runtime
## GLTFDocument load. WindFoliage.apply_material() builds such a surface's wind material on
## the painted variant (shaders/wind_foliage_painted.gdshader, or its no-AA twin under
## Antialiasing None) instead of the plain one; every other surface keeps today's shader. The
## variant's terms and defaults live in wind_foliage_include.gdshaderinc's
## FOLIAGE_PAINTED_LIGHT blocks; no material sets them, except the shade floor: a painted
## material may also carry {"tt_foliage_shade": [r, g, b]} (section 6 "Painted shade floor",
## treecube 83d9e06), which shade_floor() validates as untrusted input and the wind material
## takes as its own foliage_paint_shade. Each source material gets its own ShaderMaterial, so
## two species with different floors keep them apart.
##
## The variant's albedo ramp and ambient follow the sun through one global shader parameter,
## foliage_sun (project.godot [shader_globals]): the direction toward the sun and its weight.
## LevelEnvironmentManager calls publish_sun() whenever it configures the sun (map load, the
## Sun pane, time of day, every live or networked apply), so all painted crowns turn at once.
##
## A burning tree swaps to wind_foliage_burn.gdshader (FireSweep), which has no painted light,
## so a painted crown changes shading when it catches (docs/PERFORMANCE.md "Painted foliage
## light and round 5 crowns", which also holds the cost and the low-sun weighting).

## The material extra and its value (docs/ASSET_PIPELINE.md section 6).
const EXTRA_KEY := "tt_foliage_light"
const PAINTED := "painted"
## The optional painted shade floor extra (section 6 "Painted shade floor"): three linear 0-1
## floats a painted material takes as its foliage_paint_shade uniform, the shade end of the
## sun ramp, so a warm or grey species keeps its own shade instead of the shared green one.
const SHADE_KEY := "tt_foliage_shade"
## The uniform the shade floor sets (wind_foliage_include.gdshaderinc, FOLIAGE_PAINTED_LIGHT).
const SHADE_UNIFORM := &"foliage_paint_shade"
## Metadata on a wind ShaderMaterial built on the painted variant, so the antialiasing swap
## (WindFoliage.shader_for) keeps it painted.
const META_PAINTED := "foliage_painted"
## The global shader parameter: xyz the unit direction toward the sun (world), w its weight.
const GLOBAL_SUN := &"foliage_sun"
## Published when no sun lights the map (sun off and no map light): straight up, weight 0.
const NO_SUN := Vector4(0.0, 1.0, 0.0, 0.0)
## shadow_caster_push (metres) on a tree's alpha-scissor leaf cards, painted or not: at the
## shader's 0.6 the small round 5 cards and the pines' needle cards still showed a fine shadow
## stipple over their lit sides (treecube docs/looks/soft_crowns_probe.md, round 5). Costs a
## bush some of its ground contact shadow.
const LEAF_SHADOW_PUSH := 2.0
## The sun's height (the up component of the direction toward it, about 30 degrees) from
## which it weighs fully. A low sun lights a crown's tops edge-on, so its sun term gives little
## more than the shade floor; its weight, and with it the cut to the cards' ambient, fades to
## nothing at the horizon so a dusk crown keeps the ambient that carries it (2026-10-12 dusk
## capture: at weight 0.47 and 4 degrees up the crowns read dark olive and muddy).
const SUN_HIGH := 0.5

static var _shader: Shader = null
static var _shader_no_aa: Shader = null
## The last value publish_sun() wrote. RenderingServer.global_shader_parameter_get() is
## editor-only (it returns null in a running project), so tests read this instead.
static var last_sun := Vector4(0.0, 1.0, 0.0, 1.0)


## The painted variant (alpha-to-coverage cutout), loaded once.
static func get_shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/wind_foliage_painted.gdshader")
	return _shader


## The painted variant's plain-cutout twin for Antialiasing None, loaded once.
static func get_shader_no_aa() -> Shader:
	if _shader_no_aa == null:
		_shader_no_aa = load("res://shaders/wind_foliage_painted_no_aa.gdshader")
	return _shader_no_aa


## True when `source` (an imported material) carries the extra tt_foliage_light "painted".
static func is_painted(source: Material) -> bool:
	if source == null or not source.has_meta("extras"):
		return false
	var extras: Variant = source.get_meta("extras")
	if not extras is Dictionary:
		return false
	return String((extras as Dictionary).get(EXTRA_KEY, "")) == PAINTED


## The shade floor `source` asks for: its tt_foliage_shade extra as a Vector3 clamped to 0..1,
## or null when it has none, is not painted (the plain shader has no painted light), or the
## value is not exactly three finite numbers (ignored with a warning; out-of-range channels
## are clamped with one). The extra is untrusted input: a palette or a shared map GLB.
static func shade_floor(source: Material) -> Variant:
	if not is_painted(source):
		return null
	var extras := source.get_meta("extras") as Dictionary
	if not extras.has(SHADE_KEY):
		return null
	var value: Variant = extras[SHADE_KEY]
	var where := source.resource_name if source.resource_name != "" else str(source)
	if not (value is Array or value is PackedFloat32Array or value is PackedFloat64Array):
		push_warning("FoliageLight: %s on %s is not a list; ignored" % [SHADE_KEY, where])
		return null
	var channels: Array = Array(value)
	if channels.size() != 3:
		push_warning("FoliageLight: %s on %s needs 3 numbers; ignored" % [SHADE_KEY, where])
		return null
	var shade := Vector3.ZERO
	for i in 3:
		var channel: Variant = channels[i]
		if not (channel is float or channel is int) or not is_finite(float(channel)):
			push_warning(
				"FoliageLight: %s on %s is not 3 finite numbers; ignored" % [SHADE_KEY, where]
			)
			return null
		shade[i] = float(channel)
	var clamped := shade.clamp(Vector3.ZERO, Vector3.ONE)
	if clamped != shade:
		push_warning("FoliageLight: %s on %s clamped to 0..1" % [SHADE_KEY, where])
	return clamped


## The foliage_sun value for `light`: the unit direction toward it (its +Z axis in world
## space) and its weight, its energy clamped to 0..1 times how high it stands (0 at the
## horizon, full from SUN_HIGH up), or 0 while it is hidden. A null light gives NO_SUN. Pure
## apart from reading the node.
static func sun_value(light: DirectionalLight3D) -> Vector4:
	if light == null:
		return NO_SUN
	var basis := light.global_basis if light.is_inside_tree() else light.basis
	var to_sun := basis.z.normalized()
	var weight := 0.0
	if light.visible:
		weight = clampf(light.light_energy, 0.0, 1.0) * smoothstep(0.0, SUN_HIGH, to_sun.y)
	return Vector4(to_sun.x, to_sun.y, to_sun.z, weight)


## Publishes `light` (or NO_SUN for null) as the foliage_sun global.
static func publish_sun(light: DirectionalLight3D) -> void:
	last_sun = sun_value(light)
	RenderingServer.global_shader_parameter_set(GLOBAL_SUN, last_sun)
