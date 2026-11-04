class_name EyeSky
extends RefCounted

## The painted sky and edge fog of the eye view (cards eyesky SR0b and SR6). While the eye view
## is the camera, the level's Environment gets the shader sky (shaders/street_sky.gdshader: a
## painted gradient, clouds and layered ridges that hide where the map ends) and a depth fog
## scaled to the map (it ramps up toward the map's far side and never nearer than 25 to 85 m:
## StreetSkyLook.fog_range) whose colour is the biome's foot colour; leaving puts every field back
## as it was.
## The orthographic and top-down views never see any of this: nothing here runs outside the eye.
##
## What the sky replaces is read from the Environment: a flat background colour (the default
## level) becomes the shader's flat_color, an HDRI (PanoramaSkyMaterial) its panorama and
## exposure. The shader returns exactly that in the pass that fills the radiance map, so ambient
## light and reflections are unchanged by construction (shaders/street_sky.gdshader header). A
## gradient (ProceduralSkyMaterial) or other sky is left alone: the eye view then keeps it and
## its own fog.
##
## The environment is re-applied live (the Sky pane, presets, weather), which writes the sky and
## fog fields again; sync() runs every frame the eye is on, notices that, takes the new values as
## the ones to restore and puts the painted sky back.
##
## The biome look is StreetSkyLook (per-biome table); MapViewFit tells this object the map's
## dominant biome and seed. The ground skirt and the water backdrop read the shader's foot_on
## and foot_color (SkirtBackdrop), so they fade to the same colour as the fog and the ridge foot.

const SHADER_PATH := "res://shaders/street_sky.gdshader"

## Probes switch the painted sky off to take a before still; the product never does.
static var enabled: bool = true

## Dominant biome id of the map and its seed (set at map load; "" and 0 for none).
var biome: String = ""
var map_seed: int = 0
## Metres added to the fog's begin and end while the camera is far from what it looks at (the
## glide between the orbit view and the eye, EyeGlide: the camera starts 974 m back); 0 at the eye.
var fog_offset: float = 0.0
## The eye's reach on the map (StreetSkyLook.map_reach, metres; 0 for no map), which EyeView sets
## every frame: the fog's begin and end scale with it (StreetSkyLook.fog_range).
var reach: float = 0.0

var _env: Environment = null
var _sky: Sky = null
var _material: ShaderMaterial = null
## The fields the level's environment manager writes (re-read when it re-applies).
var _saved: Dictionary = {}
## The fields it never writes (read once, on entering).
var _saved_fog_mode: Dictionary = {}
var _active: bool = false
var _last_sun: Vector3 = Vector3.ZERO
## The foot colour of the look of `_foot_biome` (_foot_color); `_foot_known` is false until read.
var _foot_color_cache: Color = Color.BLACK
var _foot_biome: String = ""
var _foot_known: bool = false


func is_active() -> bool:
	return _active


## The shader material while the sky is installed (null otherwise).
func material() -> ShaderMaterial:
	return _material if _active else null


## Sets the map's dominant biome id and seed (a new look takes effect on the next sync).
func set_map(biome_id: String, seed_value: int) -> void:
	biome = biome_id
	map_seed = seed_value


## Whether `env` has a sky this object can stand in for: a flat colour or an HDRI panorama.
static func can_paint(env: Environment) -> bool:
	if env == null:
		return false
	if env.background_mode == Environment.BG_COLOR:
		return true
	if env.background_mode != Environment.BG_SKY or env.sky == null:
		return false
	var material := env.sky.sky_material
	return material is PanoramaSkyMaterial and (material as PanoramaSkyMaterial).panorama != null


## Installs (or refreshes) the painted sky and fog on `env`, which the eye view calls every frame.
## `to_sun` is the unit direction toward the sun in world space (FoliageLight.last_sun).
func sync(env: Environment, to_sun: Vector3) -> void:
	if not enabled or env == null:
		return
	if _active and env != _env:
		leave()
	if _active and _still_ours(env, to_sun):
		_apply_fog_depth(env)
		return
	if not _active and not can_paint(env):
		return
	if not _active:
		_env = env
		_saved_fog_mode = {
			"fog_mode": env.fog_mode,
			"fog_depth_begin": env.fog_depth_begin,
			"fog_depth_end": env.fog_depth_end,
			"fog_depth_curve": env.fog_depth_curve,
			"fog_sky_affect": env.fog_sky_affect,
		}
		_active = true
	elif not _paintable_after_reapply(env):
		# The level now has a sky this cannot stand in for: leave it be.
		leave()
		return
	_saved = _read_applied(env)
	_install(env, to_sun)
	_apply_fog_depth(env)


## Puts every field back as it was before the sky was installed. Safe to call when not active.
func leave() -> void:
	if not _active:
		return
	_active = false
	fog_offset = 0.0
	var env := _env
	_env = null
	if env == null:
		return
	# The fog mode first: Godot 4.7 resets fog_density when fog_mode is assigned.
	for key in _saved_fog_mode:
		env.set(key, _saved_fog_mode[key])
	for key in _saved:
		env.set(key, _saved[key])
	_material = null
	_sky = null
	_saved = {}


## A re-applied environment is paintable when it is a flat colour again, an HDRI, or already ours.
func _paintable_after_reapply(env: Environment) -> bool:
	return (env.sky != null and env.sky == _sky) or can_paint(env)


## The biome look's foot colour, looked up again only when the biome changed: sync() asks for it
## every frame, and StreetSkyLook.look_for builds the whole merged look each time.
func _foot_color() -> Color:
	if not _foot_known or _foot_biome != biome:
		_foot_color_cache = StreetSkyLook.look_for(biome)["foot_color"]
		_foot_biome = biome
		_foot_known = true
	return _foot_color_cache


func _still_ours(env: Environment, to_sun: Vector3) -> bool:
	return (
		_last_sun.is_equal_approx(to_sun)
		and env.background_mode == Environment.BG_SKY
		and env.sky == _sky
		and env.fog_enabled
		and env.fog_light_color.is_equal_approx(_foot_color())
		and env.fog_depth_curve == StreetSkyLook.FOG_CURVE
	)


## The fog's begin and end scaled to the map (reach), moved out by the camera's distance from
## what it looks at (fog_offset). Rewritten only when it moved by a few centimetres or more, so
## walking does not touch the environment every frame.
func _apply_fog_depth(env: Environment) -> void:
	var fog := StreetSkyLook.fog_range(reach)
	var begin := fog.x + fog_offset
	var end := fog.y + fog_offset
	if absf(env.fog_depth_end - end) >= 0.05 or absf(env.fog_depth_begin - begin) >= 0.05:
		env.fog_depth_begin = begin
		env.fog_depth_end = end


## The manager-written fields as they are now (the values to restore). Includes the sky and fog
## the manager wrote, but when `env` still holds our own sky the previous values are kept.
func _read_applied(env: Environment) -> Dictionary:
	if env.sky != null and env.sky == _sky and not _saved.is_empty():
		return _saved
	return {
		"background_mode": env.background_mode,
		"sky": env.sky,
		"fog_enabled": env.fog_enabled,
		"fog_light_color": env.fog_light_color,
		"fog_light_energy": env.fog_light_energy,
		"fog_density": env.fog_density,
		"fog_height_density": env.fog_height_density,
	}


func _install(env: Environment, to_sun: Vector3) -> void:
	_last_sun = to_sun
	var look := StreetSkyLook.look_for(biome)
	var sun := StreetSkyLook.sun_angles(to_sun, env.sky_rotation)
	var params := StreetSkyLook.shader_params(biome, map_seed, sun)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
		_sky = Sky.new()
		_sky.sky_material = _material
	_apply_replaced_sky(env)
	for key in params:
		_material.set_shader_parameter(key, params[key])
	_material.set_shader_parameter("foot_on", 1.0)
	env.background_mode = Environment.BG_SKY
	env.sky = _sky
	env.fog_enabled = true
	if env.fog_mode != Environment.FOG_MODE_DEPTH:
		env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = look["foot_color"]
	env.fog_light_energy = 1.0
	var fog := StreetSkyLook.fog_range(reach)
	env.fog_depth_begin = fog.x + fog_offset
	env.fog_depth_end = fog.y + fog_offset
	env.fog_depth_curve = StreetSkyLook.FOG_CURVE
	env.fog_sky_affect = 0.0
	env.fog_height_density = 0.0


## The panorama or flat colour the painted sky stands in for, from the values saved on entering.
func _apply_replaced_sky(env: Environment) -> void:
	var sky: Sky = _saved.get("sky")
	var material: Material = sky.sky_material if sky != null else null
	if material is PanoramaSkyMaterial and (material as PanoramaSkyMaterial).panorama != null:
		var panorama := material as PanoramaSkyMaterial
		_material.set_shader_parameter("use_panorama", true)
		_material.set_shader_parameter("source_panorama", panorama.panorama)
		_material.set_shader_parameter("exposure", panorama.energy_multiplier)
	else:
		_material.set_shader_parameter("use_panorama", false)
		_material.set_shader_parameter("flat_color", env.background_color)
		_material.set_shader_parameter("exposure", 1.0)
