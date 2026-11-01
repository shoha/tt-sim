extends SceneTree

## Renders a built-in token pack's 128 px icons: every GLB in <pack>/models/ on a transparent
## background, from the game camera's angle (45 degrees of azimuth, about 22 degrees down,
## orthographic), the figure turned toward the camera and fitted to the frame. Needs a window
## (a real renderer), so no --headless:
##   godot --path <tt-sim> --script res://tools/roster/render_icons.gd -- \
##     --pack <tt-sim>/builtin_packs/folk [--only villager_man]
## It writes <pack>/icons/<id>.png and quits on its own. The frame is lit by one soft key
## light and an ambient fill, not the board's environment: an icon is a portrait, not a capture.

const FolkGlb := preload("res://tools/roster/folk_glb.gd")
const SkinnedBounds := preload("res://tools/roster/skinned_bounds.gd")
const SIZE_PX := 128
const SUPERSAMPLE := 4
const AZIMUTH_RAD := PI / 4.0
const PITCH_DEG := 21.6
const MARGIN := 1.12
const WATCHDOG_S := 120.0

## Extra turn of the model away from facing the camera: people face it (0), a four-legged
## animal reads better in three-quarter view (--yaw -50, say).
var _yaw_deg := 0.0


func _initialize() -> void:
	var pack := ""
	var only := ""
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1):
		if args[i] == "--pack":
			pack = args[i + 1].trim_suffix("/")
		elif args[i] == "--only":
			only = args[i + 1]
		elif args[i] == "--yaw":
			_yaw_deg = float(args[i + 1])
	if pack == "":
		push_error("usage: -- --pack <pack folder> [--only <id>] [--yaw <degrees off the camera>]")
		quit(2)
		return
	create_timer(WATCHDOG_S).timeout.connect(func() -> void: quit(3))
	_run(pack, only)


func _run(pack: String, only: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE_PX, SIZE_PX) * SUPERSAMPLE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.82, 0.9)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-52.0), AZIMUTH_RAD + deg_to_rad(28.0), 0.0)
	light.light_energy = 1.0
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.basis = Basis.from_euler(Vector3(-deg_to_rad(PITCH_DEG), AZIMUTH_RAD, 0.0))
	viewport.add_child(camera)
	DirAccess.make_dir_recursive_absolute(pack + "/icons")
	var failed := 0
	for file_name in DirAccess.get_files_at(pack + "/models"):
		if file_name.get_extension() != "glb" or (only != "" and file_name.get_basename() != only):
			continue
		var model := _load(pack + "/models/" + file_name)
		if model == null:
			failed += 1
			continue
		model.rotation.y = AZIMUTH_RAD + deg_to_rad(_yaw_deg)
		viewport.add_child(model)
		_fit(camera, model)
		for i in 4:
			await process_frame
		var image := viewport.get_texture().get_image()
		image.resize(SIZE_PX, SIZE_PX, Image.INTERPOLATE_LANCZOS)
		var icon := pack + "/icons/" + file_name.get_basename() + ".png"
		var ok := image.save_png(icon) == OK and FolkGlb.write_keep_sidecar(icon)
		print("ICON %s ok=%s" % [file_name.get_basename(), ok])
		failed += 0 if ok else 1
		viewport.remove_child(model)
		model.free()
	quit(1 if failed > 0 else 0)


func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot load " + path)
		return null
	return doc.generate_scene(state) as Node3D


## Centres the camera on the model's turned bounds and sizes the orthographic view to hold it.
func _fit(camera: Camera3D, model: Node3D) -> void:
	var low := Vector3(INF, INF, INF)
	var high := -low
	# The model's rendered bounds (a skinned mesh is measured through its bones), turned and placed.
	var box := SkinnedBounds.of(model)
	for corner in 8:
		var point := box.position + box.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
		var world := model.transform * point
		low = low.min(world)
		high = high.max(world)
	var centre := (low + high) * 0.5
	# The view height that holds the model's projected extent, in the camera's own axes.
	var up := camera.basis.y
	var right := camera.basis.x
	var half_up := 0.0
	var half_right := 0.0
	for corner in 8:
		var offset := (low + (high - low) * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)) - centre
		half_up = maxf(half_up, absf(offset.dot(up)))
		half_right = maxf(half_right, absf(offset.dot(right)))
	camera.size = maxf(half_up, half_right) * 2.0 * MARGIN
	camera.position = centre + camera.basis.z * 10.0
