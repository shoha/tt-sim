class_name PainterScene
extends RefCounted

## The painted look's scene host: while a level is drawn in the Painted style it owns the light of
## the level's Environment and sun, from the sheet's tones for the level's mood at the sun's
## elevation (docs/systems/painter.md). LevelEnvironmentManager owns one and drives it from its
## apply paths (level load, preset, sun, rendering toggles, the Settings Look row): events, never a
## per-frame poll. It loads by path on first use (LevelEnvironmentManager.PAINTER_SCENE), so the
## start-up compiles none of the painter.
##
## Ownership. Painted takes the sun's colour and energy, the sky (painter_sky.gdshader), the
## ambient light, the tonemap (linear, exposure 1, so sheet colours reach the screen as written),
## glow, SSAO and colour adjustments (off), the fog's colour (the mood's haze; whether there is
## fog stays the preset's and the weather's), and a softer shadow filter (shadow_blur 1.0: at the
## level sun's 2.0 the soft filter detaches the shadow of a thin overhang by about 0.25 m, the
## spike's eave probe, 2026-11-12). The sun's direction, its shadows on or off, softness and
## darkness, the time of day and the preset's fog stay the level's.
##
## Exact restore. take() remembers every property it is about to write, once per Environment and
## per sun, and release_env() / release_sun() put those values back. The manager releases before
## each classic write and takes again after it, so what is remembered is always the Classic state
## and leaving Painted restores it to the bit (test_painter_scene.gd).

const SKY_SHADER := "res://painter/shaders/painter_sky.gdshader"
## The sun's shadow_blur under Painted (the level's is LevelEnvironmentManager's 2.0).
const SHADOW_BLUR := 1.0
## How far the far ground's tone (the sky below the horizon) is pulled into the haze, in OKLab.
const FOOT_HAZE := 0.45
## The sky's glow toward the sun at a full-energy sun.
const GLOW_AMOUNT := 0.35
## Environment properties Painted writes (and restores).
const ENV_PROPS: Array[StringName] = [
	&"background_mode",
	&"background_color",
	&"sky",
	&"ambient_light_source",
	&"ambient_light_color",
	&"ambient_light_energy",
	&"tonemap_mode",
	&"tonemap_exposure",
	&"tonemap_white",
	&"glow_enabled",
	&"ssao_enabled",
	&"adjustment_enabled",
	&"fog_light_color",
]
## Sun properties Painted writes (and restores).
const SUN_PROPS: Array[StringName] = [&"light_color", &"light_energy", &"shadow_blur"]

## What the last take() drew: {"sheet", "mood", "elevation", "tones"} ({} while released).
var applied: Dictionary = {}

var _env: Environment = null
var _env_saved: Dictionary = {}
var _sun: DirectionalLight3D = null
var _sun_saved: Dictionary = {}
var _sky: Sky = null
var _material: ShaderMaterial = null


## Draws [param env] and [param sun] (either may be null) in [param mood] of sheet
## [param sheet_id] for a sun [param elevation] degrees above the horizon. False, touching
## nothing, when the sheet or the mood is missing.
func take(
	env: Environment, sun: DirectionalLight3D, sheet_id: String, mood: String, elevation: float
) -> bool:
	var sheet: Dictionary = PainterSheet.load_sheet(sheet_id)
	if not sheet.has(mood):
		push_warning("PainterScene: sheet '%s' has no mood '%s'" % [sheet_id, mood])
		return false
	var tones := PainterSheet.tones(sheet, mood, elevation)
	if env != null:
		if env != _env:
			release_env()
			_env = env
		if _env_saved.is_empty():
			_env_saved = _snapshot(env, ENV_PROPS)
		_apply_env(env, tones, sheet, mood, elevation)
	if sun != null:
		if sun != _sun:
			release_sun()
			_sun = sun
		if _sun_saved.is_empty():
			_sun_saved = _snapshot(sun, SUN_PROPS)
		_apply_sun(sun, tones)
	applied = {"sheet": sheet_id, "mood": mood, "elevation": elevation, "tones": tones}
	return true


## Puts the Environment back as it was before the first take() since the last release.
func release_env() -> void:
	if is_instance_valid(_env) and not _env_saved.is_empty():
		_restore(_env, _env_saved)
	_env_saved = {}
	_env = null
	if _sun_saved.is_empty():
		applied = {}


## Puts the sun back as it was before the first take() since the last release.
func release_sun() -> void:
	if is_instance_valid(_sun) and not _sun_saved.is_empty():
		_restore(_sun, _sun_saved)
	_sun_saved = {}
	_sun = null
	if _env_saved.is_empty():
		applied = {}


## Leaves the Painted style: the Environment and the sun as Classic left them.
func release() -> void:
	release_env()
	release_sun()


## Whether Painted holds the Environment or the sun.
func is_active() -> bool:
	return not _env_saved.is_empty() or not _sun_saved.is_empty()


## The painted sky's material (null before the first take()).
func sky_material() -> ShaderMaterial:
	return _material


func _apply_env(
	env: Environment, tones: Dictionary, sheet: Dictionary, mood: String, elevation: float
) -> void:
	var sky := _painted_sky()
	_material.set_shader_parameter(&"zenith_color", tones["sky"])
	_material.set_shader_parameter(&"horizon_color", tones["horizon"])
	_material.set_shader_parameter(&"glow_color", tones["sun"])
	_material.set_shader_parameter(&"foot_color", foot_color(sheet, mood, elevation))
	_material.set_shader_parameter(
		&"glow_amount", GLOW_AMOUNT * clampf(float(tones["sun-energy"]), 0.0, 1.0)
	)
	env.background_mode = Environment.BG_SKY
	env.background_color = tones["horizon"]
	if env.sky != sky:
		env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = tones["ambient"]
	env.ambient_light_energy = float(tones["ambient-energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.glow_enabled = false
	env.ssao_enabled = false
	env.adjustment_enabled = false
	env.fog_light_color = tones["haze"]


func _apply_sun(sun: DirectionalLight3D, tones: Dictionary) -> void:
	sun.light_color = tones["sun"]
	sun.light_energy = float(tones["sun-energy"])
	sun.shadow_blur = SHADOW_BLUR


## The far ground's tone: the mood's ground pulled toward its haze (OKLab), what the sky shows
## below the horizon and the ground skirt fades into.
static func foot_color(sheet: Dictionary, mood: String, elevation: float) -> Color:
	var ground := PainterSheet.oklab_of(PainterSheet.tone_lch(sheet, mood, "ground", elevation))
	var haze := PainterSheet.oklab_of(PainterSheet.tone_lch(sheet, mood, "haze", elevation))
	var lab := ground.lerp(haze, FOOT_HAZE)
	var lch := Vector3(
		lab.x, Vector2(lab.y, lab.z).length(), fposmod(rad_to_deg(atan2(lab.z, lab.y)), 360.0)
	)
	return PainterSheet.color_of_lch(lch)


func _painted_sky() -> Sky:
	if _sky == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SKY_SHADER) as Shader
		_material.set_meta(&"painter_sky", true)
		_sky = Sky.new()
		_sky.sky_material = _material
		_sky.radiance_size = Sky.RADIANCE_SIZE_128
	return _sky


static func _snapshot(target: Object, props: Array[StringName]) -> Dictionary:
	var out := {}
	for prop in props:
		out[prop] = target.get(prop)
	return out


static func _restore(target: Object, saved: Dictionary) -> void:
	for prop: StringName in saved:
		target.set(prop, saved[prop])
