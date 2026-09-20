extends Node3D
## Renders a map GLB through the real map pipeline (GlbUtils.load_map, which builds the
## scattered MultiMeshes and applies the wind shader) and saves two screenshots about a
## second apart, so wind motion shows up as a difference between them. A check tool
## for foliage exported from Blender (terrain-paint / treecube), not a game feature.
##
## Needs a window (the screenshots come from the viewport texture):
##
##   godot --path . tools/render_map.tscn -- <map.glb> <out_dir> [sun_az_deg] [cam_az_deg]
##
## Runs as a scene so the project's autoloads exist; a bare --script SceneTree cannot
## compile GlbUtils (it references AudioManager and friends at parse time).

const _FRAME_A := 8
const _FRAME_B := 70

var _out_dir := ""
var _frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: godot --path . tools/render_map.tscn -- map.glb out_dir [sun_az] [cam_az]")
		get_tree().quit(1)
		return
	var map_path: String = args[0]
	_out_dir = args[1]
	var sun_az := float(args[2]) if args.size() > 2 else 120.0
	var cam_az := float(args[3]) if args.size() > 3 else 300.0
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var map := GlbUtils.load_map(map_path, false, 1.0, {})
	if map == null:
		print("LOAD_FAILED ", map_path)
		get_tree().quit(1)
		return
	add_child(map)
	var multimeshes := 0
	var instances := 0
	for node in _collect(map):
		if node is MultiMeshInstance3D:
			multimeshes += 1
			instances += (node as MultiMeshInstance3D).multimesh.instance_count
	print("MAP_LOADED multimeshes=", multimeshes, " instances=", instances)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50.0, sun_az, 0.0)
	add_child(sun)

	var aabb := _map_aabb(map)
	var centre := aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 1.0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	var a := deg_to_rad(cam_az)
	var elev := deg_to_rad(28.0)
	var distance := radius / tan(deg_to_rad(25.0)) * 0.9
	add_child(cam)
	cam.position = centre + Vector3(cos(a) * cos(elev), sin(elev), sin(a) * cos(elev)) * distance
	cam.look_at(centre, Vector3.UP)
	cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == _FRAME_A:
		_shoot("frame_a.png")
	elif _frames == _FRAME_B:
		_shoot("frame_b.png")
		print("DONE")
		get_tree().quit()


func _shoot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(file_name)
	image.save_png(path)
	print("SHOT ", path)


func _collect(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_collect(child))
	return out


func _map_aabb(map: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in _collect(map):
		var box: AABB
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var mesh_node := node as MeshInstance3D
			box = mesh_node.global_transform * mesh_node.mesh.get_aabb()
		elif node is MultiMeshInstance3D:
			var multi := node as MultiMeshInstance3D
			box = multi.global_transform * multi.multimesh.get_aabb()
		else:
			continue
		result = box if first else result.merge(box)
		first = false
	return result
