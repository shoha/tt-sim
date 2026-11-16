class_name PainterWater
extends RefCounted

## The painted look's water: while a level is drawn Painted, the shared water material and the
## shared waterfall material draw with the painter's shaders (painter/shaders/painter_water.gdshader
## and painter_waterfall.gdshader; docs/systems/painter.md "Water"), coloured from the sheet.
##
## PainterSurfaces makes one (loaded by path on the first painted map, as PainterBuildings) and
## drives it from LevelEnvironmentManager.painted_look_changed: paint() swaps or re-tones, release()
## puts everything back.
##
## What it swaps, and the exact restore. The SHADER of the two shared materials, not a per-mesh
## override: WaterGlbUtils.water_material() reaches every water mesh (the authored surface, a
## Blender plane, the river ribbon past the edge, every later rebuild) and
## AuthoredWater.fall_material() every fall, and process_water_meshes() would undo a per-mesh
## override. A ShaderMaterial keeps its
## parameters (and a mesh its instance uniforms) across a shader swap (probe, 2026-11-15), so the
## flow map, the disturbance points, the skirt's uniforms and the level's Motion keys keep working
## under the painted shader (it declares Classic's names for them) and come back untouched. The
## sheet's colours go under p_ names the Classic shader does not read, so apply_water_settings()
## (which pushes water_color, shore_color and foam_color by name) cannot fight the sheet; release()
## clears them, so the materials are as they were.
##
## Tones. Every colour is the sheet's: the water-* roles, the horizon for the sky tint, the water
## numbers, and the ground's own ramp ratio for what a cast shadow does to the wash. A new elevation
## re-tones the same materials.

const SHADER := "res://painter/shaders/painter_water.gdshader"
const FALL_SHADER := "res://painter/shaders/painter_waterfall.gdshader"
## Metadata on both materials while they are painted.
const META := &"painter_water"
## The sheet's colour roles and the (LINEAR vec3) uniform each sets.
const ROLE_UNIFORMS: Dictionary = {
	"water-shallow": &"p_shallow",
	"water-mid": &"p_mid",
	"water-deep": &"p_deep",
	"water-lit": &"p_lit",
	"water-shade": &"p_shade",
	"water-foam": &"p_foam",
	"water-glint": &"p_glint",
	"water-ice": &"p_ice",
	"horizon": &"p_sky",
}
## The sheet's numbers and the (float) uniform each sets.
const NUMBER_UNIFORMS: Dictionary = {
	"water-strokes": &"p_strokes",
	"water-stroke-len": &"p_stroke_len",
	"water-boil": &"p_boil",
	"water-glints": &"p_glints",
	"water-opacity": &"p_opacity",
	"water-foam-width": &"p_foam_w",
	"ice-over": &"p_ice_amt",
}
## The uniform of what a cast shadow does to the wash (a colour factor).
const SHADE_UNIFORM := &"p_shade_mul"
## The ground role whose ramp gives the shadow factor.
const SHADE_ROLE := "ground"
## How much of the ground's lit-to-shade ratio the water takes (0 none, 1 all of it).
const SHADE_SHARE := 0.55
## The uniforms the fall shader reads of the sheet's.
const FALL_UNIFORMS: Array[StringName] = [&"p_shallow", &"p_mid", &"p_lit", &"p_foam", &"p_sky"]

## What is drawn now: {"sheet", "mood", "elevation"}, {} while nothing is painted.
var applied: Dictionary = {}

var _water: ShaderMaterial = null
var _fall: ShaderMaterial = null
var _water_classic: Shader = null
var _fall_classic: Shader = null


## Paints the shared water and fall materials in `state` ({"sheet", "mood", "elevation"}), or
## re-tones them when they are already painted. `map` is unused (the materials are shared by every
## map). False, touching nothing, when the sheet or the mood is missing.
func paint(_map: Node3D, state: Dictionary) -> bool:
	var sheet := PainterSheet.load_sheet(str(state.get("sheet", "")))
	if not sheet.has(str(state.get("mood", ""))):
		return false
	applied = {
		"sheet": str(state["sheet"]),
		"mood": str(state["mood"]),
		"elevation": float(state.get("elevation", 45.0))
	}
	_swap()
	_retone(sheet)
	return true


## Puts both materials back as they were before the first paint(): Classic's shaders, none of the
## sheet's parameters.
func release() -> void:
	if _water != null and _water_classic != null:
		_restore(_water, _water_classic)
	if _fall != null and _fall_classic != null:
		_restore(_fall, _fall_classic)
	_water = null
	_fall = null
	_water_classic = null
	_fall_classic = null
	applied = {}


## Whether anything is painted.
func is_active() -> bool:
	return not applied.is_empty()


## The shared water material while painted (null otherwise).
func water_material() -> ShaderMaterial:
	return _water


## The shared fall material while painted (null otherwise).
func fall_material() -> ShaderMaterial:
	return _fall


## Every uniform the sheet's tones set, by name (the clear on release, the tests).
static func tone_uniforms() -> Array[StringName]:
	var out: Array[StringName] = [SHADE_UNIFORM]
	for key: String in ROLE_UNIFORMS:
		out.append(ROLE_UNIFORMS[key])
	for key: String in NUMBER_UNIFORMS:
		out.append(NUMBER_UNIFORMS[key])
	return out


## What a cast shadow does to the wash: the shade colour of the ground's ramp over its lit colour
## per channel (LINEAR), so the water darkens and cools as the ground beside it does. Pure.
static func shade_factor(sheet: Dictionary, mood: String, elevation: float) -> Vector3:
	var ramp := PainterTones.ramp(sheet, mood, SHADE_ROLE, elevation, "ground-")
	var lit := PainterTones.linear(ramp[2])
	var shade := PainterTones.linear(ramp[0])
	var raw := Vector3(
		clampf(shade.x / maxf(lit.x, 0.001), 0.2, 1.0),
		clampf(shade.y / maxf(lit.y, 0.001), 0.2, 1.0),
		clampf(shade.z / maxf(lit.z, 0.001), 0.2, 1.0)
	)
	# Water is a wash over a bright bed, so a cast shadow dims it less than it dims the ground.
	return Vector3.ONE.lerp(raw, SHADE_SHARE)


## The sheet's tone uniforms for `mood` at `elevation` as {uniform: value}. Pure.
static func tones(sheet: Dictionary, mood: String, elevation: float) -> Dictionary:
	var out := {}
	for role: String in ROLE_UNIFORMS:
		out[ROLE_UNIFORMS[role]] = PainterTones.linear(PainterSheet.tone(sheet, mood, role, elevation))
	for prop: String in NUMBER_UNIFORMS:
		out[NUMBER_UNIFORMS[prop]] = PainterSheet.number(sheet, mood, prop, elevation)
	out[SHADE_UNIFORM] = shade_factor(sheet, mood, elevation)
	return out


func _swap() -> void:
	if _water == null:
		_water = WaterGlbUtils.water_material()
		_water_classic = _water.shader
		_water.shader = load(SHADER) as Shader
		_water.set_meta(META, true)
	if _fall == null:
		_fall = AuthoredWater.fall_material()
		_fall_classic = _fall.shader
		_fall.shader = load(FALL_SHADER) as Shader
		_fall.set_meta(META, true)


func _restore(material: ShaderMaterial, classic: Shader) -> void:
	material.shader = classic
	material.remove_meta(META)
	for uniform in tone_uniforms():
		material.set_shader_parameter(uniform, null)


func _retone(sheet: Dictionary) -> void:
	var values := tones(sheet, applied["mood"], applied["elevation"])
	for uniform: StringName in values:
		_water.set_shader_parameter(uniform, values[uniform])
		if uniform in FALL_UNIFORMS:
			_fall.set_shader_parameter(uniform, values[uniform])
