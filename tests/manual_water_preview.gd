extends Node3D

## Throwaway manual visual-check scene for the water shader (shaders/water.gdshader).
## Not a GUT test -- no real map in the repo currently has a "-water" suffixed mesh, so
## this builds a minimal shore-to-deep water plane entirely in code and applies the
## shared production material via GlbUtils.process_water_meshes(), exactly like a real
## GLB map would. Delete once the shader work it was used to verify is done.


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)

	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(6, 8, 10)
	camera.look_at(Vector3(0, -0.5, 0), Vector3.UP)

	# Shallow floor near "shore" (negative x), close under the water surface -- this is
	# where depth_diff should read near 0 and shore_color / refraction should dominate.
	var shallow := MeshInstance3D.new()
	var shallow_box := BoxMesh.new()
	shallow_box.size = Vector3(6, 0.3, 8)
	shallow.mesh = shallow_box
	shallow.position = Vector3(-3, -0.15, 0)
	var shallow_mat := StandardMaterial3D.new()
	shallow_mat.albedo_color = Color(0.76, 0.7, 0.5)
	shallow.material_override = shallow_mat
	add_child(shallow)

	# Deep floor further from shore (positive x), well below the water surface -- this is
	# where depth_diff should read near 1 and water_color should dominate.
	var deep := MeshInstance3D.new()
	var deep_box := BoxMesh.new()
	deep_box.size = Vector3(6, 0.3, 8)
	deep.mesh = deep_box
	deep.position = Vector3(3, -2.0, 0)
	var deep_mat := StandardMaterial3D.new()
	deep_mat.albedo_color = Color(0.15, 0.12, 0.1)
	deep.material_override = deep_mat
	add_child(deep)

	# A distinct upright object on the deep floor so screen-space refraction distortion
	# is visible against a recognizable shape rather than a flat color.
	var marker := MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.4
	marker_mesh.bottom_radius = 0.4
	marker_mesh.height = 1.2
	marker.mesh = marker_mesh
	marker.position = Vector3(3, -1.3, 0)
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.9, 0.2, 0.2)
	marker.material_override = marker_mat
	add_child(marker)

	# The water plane itself -- named with the "-water" suffix so GlbUtils applies the
	# same shared ShaderMaterial instance a real GLB map would get.
	var water := MeshInstance3D.new()
	water.name = "Pond-water"
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(12, 8)
	water.mesh = water_mesh
	add_child(water)

	GlbUtils.process_water_meshes(self)
