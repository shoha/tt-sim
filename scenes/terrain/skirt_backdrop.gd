class_name SkirtBackdrop
extends Node

## Keeps the ground skirt's backdrop and fog uniforms (SKIRT in
## shaders/authored_ground.gdshaderinc) in step with the environment the camera renders under
## (phase 6, P6-1). The skirt is opaque and fades into the backdrop in colour, so it must know
## the colour the camera shows behind it: the environment's flat colour, or a panorama sky's
## colour in the view direction, mixed toward the fog colour as Godot fogs the background, and
## the fog itself, which the skirt computes as Godot's fog_process does. The environment
## changes live (the Sky pane, presets, weather fog tweening its density), so a child of the
## skirt reads it every frame and sets the uniforms only when something changed: a handful of
## property reads per frame. The water past the edge (the shared water material, when the map
## has a river exit) gets the same uniforms: its fade weighs the backdrop as the skirt's does
## (skirt_fade.gdshaderinc skirt_lit_share).
##
## Sky backdrops: a PanoramaSkyMaterial is sampled by the shader itself in the camera's view
## direction (MODE_SKY); a ProceduralSkyMaterial's colour there is computed here (its gradient,
## MODE_COLOR); any other sky material (physical, a map's own shader) falls back to the dither
## (MODE_DITHER), which needs no colour.

const NODE_NAME := "SkirtBackdrop"
const MODE_COLOR := 0
const MODE_SKY := 1
const MODE_DITHER := 2

## The materials kept in step: the skirt's, and the water's when a river runs past the edge.
var materials: Array[ShaderMaterial] = []

var _last: Dictionary = {}


func _ready() -> void:
	sync()


func _process(_delta: float) -> void:
	sync()


## Sets the materials' backdrop uniforms from the viewport's environment and camera now, when
## they changed.
func sync() -> void:
	if materials.is_empty() or not is_inside_tree():
		return
	var viewport := get_viewport()
	var world := viewport.find_world_3d() if viewport != null else null
	var camera := viewport.get_camera_3d() if viewport != null else null
	var forward := -camera.global_basis.z if camera != null else Vector3(0.0, -0.4, -1.0)
	var wanted := uniforms(world.environment if world != null else null, forward.normalized())
	if wanted == _last:
		return
	_last = wanted
	for material in materials:
		for key in wanted:
			material.set_shader_parameter(key, wanted[key])


## The skirt's backdrop and fog uniforms for environment `env` (null: the project's clear
## colour, no fog) seen along `forward` (world, unit). Pure.
static func uniforms(env: Environment, forward: Vector3) -> Dictionary:
	var out := {
		"skirt_backdrop_mode": MODE_COLOR,
		"skirt_backdrop": _linear(_clear_color(), 1.0),
		"skirt_sky_panorama": null,
		"skirt_sky_basis": Basis.IDENTITY,
		"skirt_sky_energy": 1.0,
		"skirt_fog": Vector4.ZERO,
		"skirt_fog_params": Vector4(0.01, 0.0, 0.0, 1.0),
		"skirt_fog_depth": Vector4(0.0, 10.0, 100.0, 1.0),
	}
	if env == null:
		return out
	var energy := env.background_energy_multiplier
	match env.background_mode:
		Environment.BG_COLOR:
			out.skirt_backdrop = _linear(env.background_color, energy)
		Environment.BG_CLEAR_COLOR:
			out.skirt_backdrop = _linear(_clear_color(), energy)
		Environment.BG_SKY:
			_sky(env, forward, energy, out)
		_:
			out.skirt_backdrop_mode = MODE_DITHER
	if env.fog_enabled:
		var fog := env.fog_light_color.srgb_to_linear() * env.fog_light_energy
		out.skirt_fog = Vector4(fog.r, fog.g, fog.b, 1.0)
		out.skirt_fog_params = Vector4(
			env.fog_density, env.fog_height, env.fog_height_density, env.fog_sky_affect
		)
		out.skirt_fog_depth = Vector4(
			1.0 if env.fog_mode == Environment.FOG_MODE_DEPTH else 0.0,
			env.fog_depth_begin,
			env.fog_depth_end,
			env.fog_depth_curve
		)
	return out


## The sky backdrop into `out` (see the header). The sky's frame: Godot turns the view
## direction by the inverse of the sky's orientation (sky_rotation) before sampling it.
static func _sky(env: Environment, forward: Vector3, energy: float, out: Dictionary) -> void:
	var sky_material: Material = env.sky.sky_material if env.sky != null else null
	var basis := Basis.from_euler(env.sky_rotation).inverse()
	if sky_material is PanoramaSkyMaterial and (sky_material as PanoramaSkyMaterial).panorama:
		var panorama := sky_material as PanoramaSkyMaterial
		out.skirt_backdrop_mode = MODE_SKY
		out.skirt_sky_panorama = panorama.panorama
		out.skirt_sky_basis = basis
		out.skirt_sky_energy = panorama.energy_multiplier * energy
	elif sky_material is ProceduralSkyMaterial:
		var color := procedural_color(sky_material as ProceduralSkyMaterial, basis * forward)
		out.skirt_backdrop = Vector3(color.r, color.g, color.b) * energy
	else:
		out.skirt_backdrop_mode = MODE_DITHER


## A ProceduralSkyMaterial's colour (linear) along `dir` (the sky's frame): its gradient as
## Godot's procedural sky shader computes it, without the sun disc (the camera looks down).
static func procedural_color(sky: ProceduralSkyMaterial, dir: Vector3) -> Color:
	var v_angle := acos(clampf(dir.y, -1.0, 1.0))
	var color: Color
	if dir.y >= 0.0:
		var c := 1.0 - v_angle / (PI * 0.5)
		var t := clampf(1.0 - pow(1.0 - c, 1.0 / maxf(sky.sky_curve, 1e-4)), 0.0, 1.0)
		color = (
			sky.sky_horizon_color.srgb_to_linear().lerp(sky.sky_top_color.srgb_to_linear(), t)
			* sky.sky_energy_multiplier
		)
	else:
		var c := (v_angle - PI * 0.5) / (PI * 0.5)
		var t := clampf(1.0 - pow(1.0 - c, 1.0 / maxf(sky.ground_curve, 1e-4)), 0.0, 1.0)
		color = (
			sky.ground_horizon_color.srgb_to_linear().lerp(
				sky.ground_bottom_color.srgb_to_linear(), t
			)
			* sky.ground_energy_multiplier
		)
	return color * sky.energy_multiplier


static func _clear_color() -> Color:
	return ProjectSettings.get_setting(
		"rendering/environment/defaults/default_clear_color", Color(0.3, 0.3, 0.3)
	)


static func _linear(color: Color, energy: float) -> Vector3:
	var lin := color.srgb_to_linear()
	return Vector3(lin.r, lin.g, lin.b) * energy
