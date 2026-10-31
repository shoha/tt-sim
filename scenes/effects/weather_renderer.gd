class_name WeatherRenderer
extends Node3D

## Manages weather particle effects and fog overlay.
## Lives inside the SubViewport as a sibling of MapContainer.
## Call apply_weather() to set intensities; transitions are automatic.

const TRANSITION_DURATION := 1.0
const EMISSION_MARGIN := 1.25  # 25% beyond visible area to prevent pop-in at edges
const RAIN_VELOCITY_MIN := 12.0
const RAIN_VELOCITY_MAX := 16.0
const WIND_ALPHA := 0.4  # wind streak colour alpha in a lull; brightens with gustiness
const FOG_DENSITY_PER_INTENSITY := 0.05  # density added at base per unit of fog intensity

# Baseline (local-space) visibility_aabb half-extents, matching the AABB each
# emitter is created with. _grow_visibility_aabb() never shrinks below these.
const BASE_VISIBILITY_HALF_EXTENT := 30.0
const BASE_VISIBILITY_HALF_HEIGHT := 15.0

## Number of times the wind was written to the materials (tests and the perf probe read it).
var wind_apply_count := 0

# Intensity targets (0.0-1.0)
var _rain_intensity := 0.0
var _snow_intensity := 0.0
var _fog_intensity := 0.0
var _wind_intensity := 0.0

# Global wind (docs/systems/wind.md phase b): the particles follow Wind, sampled at the view
# centre and written to the process materials at most WindParticles.UPDATE_INTERVAL apart, only
# when the smoothed value moved.
var _view_center := Vector3.ZERO
var _wind_accum := 0.0
var _wind_primed := false
var _wind_smooth := Vector3.ZERO
var _gust_smooth := 0.0
var _wind_applied := Vector3.ZERO
var _gust_applied := 0.0

# Particle emitters
var _rain_emitter: GPUParticles3D = null
var _snow_emitter: GPUParticles3D = null
var _wind_emitter: GPUParticles3D = null

# Rain collision
var _rain_collision: GPUParticlesCollisionHeightField3D = null

# References
var _camera: Camera3D = null
var _environment_manager: LevelEnvironmentManager = null

# Fog baseline (captured when weather is first applied)
var _base_fog_density := 0.0
var _base_fog_enabled := false
var _has_base_fog := false

# Tweens for smooth transitions (keyed by emitter name)
var _emitter_tweens: Dictionary = {}
var _fog_tween: Tween = null


func _ready() -> void:
	set_process(false)


func setup(camera: Camera3D, environment_manager: LevelEnvironmentManager) -> void:
	_camera = camera
	_environment_manager = environment_manager
	_create_emitters()
	_refresh_process_state()


func _process(delta: float) -> void:
	if not _camera or not is_instance_valid(_camera):
		return
	_update_emitter_positions()
	if wind_due(delta):
		var state: WindState = Wind.state
		var motion: float = Wind.motion_scale()
		var gust := WindModel.gust_at(state, _view_center, Wind.clock())
		step_wind(
			Wind.wind_at(_view_center) * motion, state.gust_amp * gust * motion
		)


## Accumulates [param delta] and says whether the wind should be sampled now: at once when the
## particles were just switched on, else every WindParticles.UPDATE_INTERVAL.
func wind_due(delta: float) -> bool:
	_wind_accum += delta
	if _wind_primed and _wind_accum < WindParticles.UPDATE_INTERVAL:
		return false
	return true


## Feeds one wind sample (already scaled by the player's motion scale) through the smoothing and
## the change rule; writes the materials only when it moved. Returns whether it wrote.
func step_wind(wind: Vector3, gustiness: float) -> bool:
	var dt := _wind_accum
	_wind_accum = 0.0
	if not _wind_primed:
		_wind_primed = true
		_wind_smooth = wind
		_gust_smooth = gustiness
	else:
		_wind_smooth = WindParticles.smooth_toward(_wind_smooth, wind, dt)
		_gust_smooth = WindParticles.smooth_scalar(_gust_smooth, gustiness, dt)
		var moved := WindParticles.changed_enough(
			_wind_applied, _wind_smooth, _gust_applied, _gust_smooth
		)
		if not moved:
			return false
	_write_wind(_wind_smooth, _gust_smooth)
	return true


## Enable _process only while at least one emitter is actively emitting -- called
## whenever an emitter's `emitting` flag changes (see _transition_emitter()) so idle
## weather (all intensities at zero) costs nothing per frame.
func _refresh_process_state() -> void:
	var any_active := (
		(_rain_emitter and _rain_emitter.emitting)
		or (_snow_emitter and _snow_emitter.emitting)
		or (_wind_emitter and _wind_emitter.emitting)
	)
	set_process(any_active)


func _create_emitters() -> void:
	_rain_emitter = _create_rain_emitter()
	add_child(_rain_emitter)

	_snow_emitter = _create_snow_emitter()
	add_child(_snow_emitter)

	_wind_emitter = _create_wind_emitter()
	add_child(_wind_emitter)

	_rain_collision = GPUParticlesCollisionHeightField3D.new()
	_rain_collision.size = Vector3(40, 20, 40)
	_rain_collision.follow_camera_enabled = true
	add_child(_rain_collision)


func _create_rain_emitter() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "RainEmitter"
	emitter.emitting = false
	emitter.amount = 1000
	emitter.lifetime = 1.2
	emitter.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 3.0
	mat.initial_velocity_min = RAIN_VELOCITY_MIN
	mat.initial_velocity_max = RAIN_VELOCITY_MAX
	mat.gravity = Vector3(0, -9.8, 0)
	mat.damping_min = 0.0
	mat.damping_max = 0.0
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(0.7, 0.75, 0.85, 0.5)
	# Align Y axis to velocity so rain streaks orient along fall direction
	mat.particle_flag_align_y = true

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(15, 0.5, 15)

	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.1, 0.8))
	curve.add_point(Vector2(0.8, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve

	# Hide particles on contact with map geometry
	mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT

	emitter.process_material = mat

	# Thin elongated quad — visible as a rain streak
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.3, 0.02)
	var rain_mat := StandardMaterial3D.new()
	rain_mat.albedo_color = Color(0.7, 0.78, 0.9, 0.5)
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Note: billboard conflicts with particle_flag_align_y, so omitted
	mesh.material = rain_mat
	emitter.draw_pass_1 = mesh

	emitter.amount_ratio = 0.0
	return emitter


func _create_snow_emitter() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "SnowEmitter"
	emitter.emitting = false
	emitter.amount = 600
	emitter.lifetime = 4.0
	emitter.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -WindParticles.SNOW_BASE_FALL, 0)
	mat.damping_min = 0.5
	mat.damping_max = 1.5
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 1.0
	mat.turbulence_noise_speed_random = 0.3
	mat.turbulence_noise_scale = 4.0
	mat.scale_min = 0.03
	mat.scale_max = 0.07
	mat.color = Color(0.95, 0.95, 1.0, 0.7)

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(15, 0.5, 15)

	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 0.7))
	curve.add_point(Vector2(0.7, 0.7))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve

	# Hide particles on contact with map geometry
	mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT

	emitter.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 4
	mesh.rings = 2
	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.95, 0.95, 1.0, 0.6)
	snow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = snow_mat
	emitter.draw_pass_1 = mesh

	emitter.amount_ratio = 0.0
	return emitter


func _create_wind_emitter() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "WindEmitter"
	emitter.emitting = false
	emitter.amount = 200
	emitter.lifetime = 2.5
	emitter.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))

	var mat := ParticleProcessMaterial.new()
	# Direction, speed and brightness follow the global wind (_write_wind); this is the default.
	mat.direction = WindPresets.default_direction()
	mat.spread = 15.0
	mat.initial_velocity_min = WindParticles.streak_speed(0.0) * 0.8
	mat.initial_velocity_max = WindParticles.streak_speed(0.0) * 1.2
	mat.gravity = Vector3(0, -0.3, 0)
	mat.damping_min = 0.0
	mat.damping_max = 0.5
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	mat.color = Color(0.85, 0.85, 0.8, WIND_ALPHA)
	# Align Y axis to velocity so streaks elongate along travel direction
	mat.particle_flag_align_y = true

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(15, 3, 15)

	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 0.5))
	curve.add_point(Vector2(0.7, 0.4))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve

	emitter.process_material = mat

	# Elongated streak visible as a wind wisp
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.5, 0.03)
	var wind_mat := StandardMaterial3D.new()
	wind_mat.albedo_color = Color(0.9, 0.9, 0.85, 0.35)
	wind_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wind_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Note: billboard conflicts with particle_flag_align_y, so omitted
	mesh.material = wind_mat
	emitter.draw_pass_1 = mesh

	emitter.amount_ratio = 0.0
	return emitter


func _update_emitter_positions() -> void:
	# Orthographic: camera holder position is the view center on the ground plane
	var holder := _camera.get_parent() as Node3D
	if not holder:
		return
	var center: Vector3 = holder.global_position
	_view_center = center
	var rain_pos := Vector3(center.x, center.y + 10.0, center.z)
	var snow_pos := Vector3(center.x, center.y + 8.0, center.z)
	var wind_pos := Vector3(center.x, center.y + 2.0, center.z)

	if _rain_emitter:
		_rain_emitter.global_position = rain_pos
	if _snow_emitter:
		_snow_emitter.global_position = snow_pos
	if _wind_emitter:
		_wind_emitter.global_position = wind_pos

	var viewport_size: Vector2i = _camera.get_viewport().size
	var aspect := float(viewport_size.x) / float(viewport_size.y)
	var half_h := _camera.size * 0.5
	var half_w := half_h * aspect
	var half_extent := maxf(half_w, half_h) * EMISSION_MARGIN
	_update_emission_extents(_rain_emitter, Vector3(half_extent, 0.5, half_extent))
	_update_emission_extents(_snow_emitter, Vector3(half_extent, 0.5, half_extent))
	_update_emission_extents(_wind_emitter, Vector3(half_extent, 3.0, half_extent))

	# Grow (never shrink below) each emitter's visibility_aabb to cover the current
	# emission box, so particles aren't culled when zoomed out on a wide aspect ratio.
	_grow_visibility_aabb(_rain_emitter, half_extent)
	_grow_visibility_aabb(_snow_emitter, half_extent)
	_grow_visibility_aabb(_wind_emitter, half_extent)

	if _rain_collision:
		var collision_extent := half_extent * 2.0
		_rain_collision.size = Vector3(collision_extent, 20, collision_extent)


## Grow (never shrink) an emitter's local-space visibility_aabb so its horizontal
## half-extent covers at least [param horizontal_half_extent]. Keeps culling from
## kicking in when the dynamic emission box (see _update_emitter_positions()) grows
## past the fixed AABB the emitter was created with, e.g. zoomed out on a wide aspect.
func _grow_visibility_aabb(emitter: GPUParticles3D, horizontal_half_extent: float) -> void:
	if not emitter:
		return
	var target_half := maxf(BASE_VISIBILITY_HALF_EXTENT, horizontal_half_extent)
	emitter.visibility_aabb = AABB(
		Vector3(-target_half, -BASE_VISIBILITY_HALF_HEIGHT, -target_half),
		Vector3(target_half * 2.0, BASE_VISIBILITY_HALF_HEIGHT * 2.0, target_half * 2.0)
	)


func _update_emission_extents(emitter: GPUParticles3D, extents: Vector3) -> void:
	if not emitter or not emitter.process_material:
		return
	var mat := emitter.process_material as ParticleProcessMaterial
	if mat:
		mat.emission_box_extents = extents


func apply_weather(overrides: Dictionary) -> void:
	var rain := float(overrides.get("rain_intensity", _rain_intensity))
	var snow := float(overrides.get("snow_intensity", _snow_intensity))
	var fog := float(overrides.get("fog_intensity", _fog_intensity))
	var wind := float(overrides.get("wind_intensity", _wind_intensity))

	_transition_emitter("rain", _rain_emitter, _rain_intensity, rain)
	_transition_emitter("snow", _snow_emitter, _snow_intensity, snow)
	# The streaks are a view of the global wind: the tile only says how many show (the amount
	# ratio); direction, speed and brightness come from Wind (see _write_wind).
	_transition_emitter(
		"wind",
		_wind_emitter,
		WindParticles.streak_ratio(_wind_intensity),
		WindParticles.streak_ratio(wind)
	)
	_transition_fog(fog)

	_rain_intensity = rain
	_snow_intensity = snow
	_fog_intensity = fog
	_wind_intensity = wind


## Writes the (smoothed, motion-scaled) wind to the three process materials: rain leans and
## speeds up, snow drifts and swirls, the streaks point and speed along the wind. Only the
## materials change; nothing runs per particle.
func _write_wind(wind: Vector3, gustiness: float) -> void:
	wind_apply_count += 1
	_wind_applied = wind
	_gust_applied = gustiness
	var speed := wind.length()
	var rain := _material_of(_rain_emitter)
	if rain:
		rain.direction = WindParticles.rain_direction(wind)
		rain.gravity = WindParticles.rain_gravity(wind)
		var launch_scale := WindParticles.rain_speed_scale(wind)
		rain.initial_velocity_min = RAIN_VELOCITY_MIN * launch_scale
		rain.initial_velocity_max = RAIN_VELOCITY_MAX * launch_scale
	var snow := _material_of(_snow_emitter)
	if snow:
		snow.gravity = WindParticles.snow_gravity(wind)
		snow.turbulence_noise_strength = WindParticles.snow_turbulence(speed, gustiness)
		snow.turbulence_noise_speed = WindParticles.snow_swirl(wind)
	var streak := _material_of(_wind_emitter)
	if streak:
		streak.direction = WindParticles.horizontal_direction(wind)
		var streak_speed := WindParticles.streak_speed(speed)
		streak.initial_velocity_min = streak_speed * 0.8
		streak.initial_velocity_max = streak_speed * 1.2
		streak.color = Color(0.85, 0.85, 0.8, WIND_ALPHA * (0.7 + 0.6 * clampf(gustiness, 0.0, 1.0)))
		# Reduced motion (wind sample 0) hides the streaks; rain and snow keep falling.
		_wind_emitter.visible = speed > 1e-3


func _material_of(emitter: GPUParticles3D) -> ParticleProcessMaterial:
	if not emitter:
		return null
	return emitter.process_material as ParticleProcessMaterial


func _transition_emitter(
	emitter_name: String, emitter: GPUParticles3D, from: float, to: float
) -> void:
	if not emitter or is_equal_approx(from, to):
		return

	if from <= 0.0 and to > 0.0:
		emitter.amount_ratio = 0.0
		emitter.emitting = true
		_wind_primed = false  # sample the wind at once for the emitter that just switched on
		_refresh_process_state()

	var existing_tween: Tween = _emitter_tweens.get(emitter_name)
	if existing_tween and existing_tween.is_valid():
		existing_tween.kill()

	var tween := create_tween()
	tween.tween_property(emitter, "amount_ratio", to, TRANSITION_DURATION)
	tween.tween_callback(
		func() -> void:
			if to <= 0.0:
				emitter.emitting = false
				_refresh_process_state()
	)
	_emitter_tweens[emitter_name] = tween


func _transition_fog(target_intensity: float) -> void:
	if not _environment_manager:
		return
	if is_equal_approx(_fog_intensity, target_intensity):
		return

	var env := _environment_manager.get_world_environment()
	if not env or not env.environment:
		return

	if not _has_base_fog:
		_base_fog_density = env.environment.fog_density
		_base_fog_enabled = env.environment.fog_enabled
		_has_base_fog = true

	if _fog_tween and _fog_tween.is_valid():
		_fog_tween.kill()

	# Intensity 1.0 adds FOG_DENSITY_PER_INTENSITY to base density (substantial visible fog)
	var target_density := _base_fog_density + target_intensity * FOG_DENSITY_PER_INTENSITY

	if target_intensity > 0.0:
		env.environment.fog_enabled = true

	_fog_tween = create_tween()
	_fog_tween.tween_property(env.environment, "fog_density", target_density, TRANSITION_DURATION)
	_fog_tween.tween_callback(
		func() -> void:
			if target_intensity <= 0.0:
				env.environment.fog_enabled = _base_fog_enabled
	)


## Re-read the environment's fog as the new base and re-add this renderer's
## contribution immediately. Call after the environment has been (re)applied
## from config: EnvironmentPresets writes fog_density/fog_enabled unconditionally,
## which discards the weather delta, and _transition_fog() would not restore it
## because the commanded intensity is unchanged.
func rebase_fog() -> void:
	if not _environment_manager:
		return
	var env := _environment_manager.get_world_environment()
	if not env or not env.environment:
		return
	if _fog_tween and _fog_tween.is_valid():
		_fog_tween.kill()
	_base_fog_density = env.environment.fog_density
	_base_fog_enabled = env.environment.fog_enabled
	_has_base_fog = true
	if _fog_intensity > 0.0:
		env.environment.fog_enabled = true
		env.environment.fog_density = _base_fog_density + _fog_intensity * FOG_DENSITY_PER_INTENSITY


func clear() -> void:
	apply_weather(
		{
			"rain_intensity": 0.0,
			"snow_intensity": 0.0,
			"fog_intensity": 0.0,
			"wind_intensity": 0.0,
		}
	)
	_has_base_fog = false
