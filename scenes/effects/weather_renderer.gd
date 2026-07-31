class_name WeatherRenderer
extends Node3D

## Manages weather particle effects and fog overlay.
## Lives inside the SubViewport as a sibling of MapContainer.
## Call apply_weather() to set intensities; transitions are automatic.

const TRANSITION_DURATION := 1.0
const EMISSION_MARGIN := 1.25  # 25% beyond visible area to prevent pop-in at edges
const WIND_DIRECTION := Vector3(0.707107, 0.0, -0.707107)  # Vector3(1, 0, -1).normalized()
const RAIN_BASE_GRAVITY := Vector3(0, -9.8, 0)
const SNOW_BASE_GRAVITY := Vector3(0, -1.5, 0)
const RAIN_WIND_STRENGTH := 6.0  # horizontal m/s^2 at wind intensity 1.0
const SNOW_WIND_STRENGTH := 2.0

# Baseline (local-space) visibility_aabb half-extents, matching the AABB each
# emitter is created with. _grow_visibility_aabb() never shrinks below these.
const BASE_VISIBILITY_HALF_EXTENT := 30.0
const BASE_VISIBILITY_HALF_HEIGHT := 15.0

# Intensity targets (0.0-1.0)
var _rain_intensity := 0.0
var _snow_intensity := 0.0
var _fog_intensity := 0.0
var _wind_intensity := 0.0

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


func setup(camera: Camera3D, environment_manager: LevelEnvironmentManager) -> void:
	_camera = camera
	_environment_manager = environment_manager
	_create_emitters()


func _process(_delta: float) -> void:
	if not _camera or not is_instance_valid(_camera):
		return
	var any_active := (
		(_rain_emitter and _rain_emitter.emitting)
		or (_snow_emitter and _snow_emitter.emitting)
		or (_wind_emitter and _wind_emitter.emitting)
	)
	if any_active:
		_update_emitter_positions()


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
	mat.initial_velocity_min = 12.0
	mat.initial_velocity_max = 16.0
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
	mat.gravity = Vector3(0, -1.5, 0)
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
	mat.direction = Vector3(1, 0, -1).normalized()
	mat.spread = 15.0
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0, -0.3, 0)
	mat.damping_min = 0.0
	mat.damping_max = 0.5
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	mat.color = Color(0.85, 0.85, 0.8, 0.4)
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
	_transition_emitter("wind", _wind_emitter, _wind_intensity, wind)
	_transition_fog(fog)

	_rain_intensity = rain
	_snow_intensity = snow
	_fog_intensity = fog
	_wind_intensity = wind

	_apply_wind_to_precipitation()


func _apply_wind_to_precipitation() -> void:
	var wind_offset := WIND_DIRECTION * _wind_intensity
	if _rain_emitter and _rain_emitter.process_material:
		var mat := _rain_emitter.process_material as ParticleProcessMaterial
		mat.gravity = RAIN_BASE_GRAVITY + wind_offset * RAIN_WIND_STRENGTH
	if _snow_emitter and _snow_emitter.process_material:
		var mat := _snow_emitter.process_material as ParticleProcessMaterial
		mat.gravity = SNOW_BASE_GRAVITY + wind_offset * SNOW_WIND_STRENGTH


func _transition_emitter(
	emitter_name: String, emitter: GPUParticles3D, from: float, to: float
) -> void:
	if not emitter or is_equal_approx(from, to):
		return

	if from <= 0.0 and to > 0.0:
		emitter.amount_ratio = 0.0
		emitter.emitting = true

	var existing_tween: Tween = _emitter_tweens.get(emitter_name)
	if existing_tween and existing_tween.is_valid():
		existing_tween.kill()

	var tween := create_tween()
	tween.tween_property(emitter, "amount_ratio", to, TRANSITION_DURATION)
	tween.tween_callback(
		func() -> void:
			if to <= 0.0:
				emitter.emitting = false
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

	# Intensity 1.0 adds 0.05 to base density (substantial visible fog)
	var target_density := _base_fog_density + target_intensity * 0.05

	if target_intensity > 0.0:
		env.environment.fog_enabled = true

	_fog_tween = create_tween()
	_fog_tween.tween_property(env.environment, "fog_density", target_density, TRANSITION_DURATION)
	_fog_tween.tween_callback(
		func() -> void:
			if target_intensity <= 0.0:
				env.environment.fog_enabled = _base_fog_enabled
	)


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
