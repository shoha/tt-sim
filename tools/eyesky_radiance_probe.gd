extends SceneTree

## Lighting-equivalence probe for the painted eye sky (card eyesky; ported from the streetsky probe).
## Run windowed:
##   godot --path D:/dev/tabletop/tt-sim --windowed --resolution 960x540 --script res://tools/eyesky_radiance_probe.gd
## Three spheres (diffuse white, rough metal, mirror) with ambient light and reflections coming
## only from the sky or background, no lights. For two bases (the shipped clear_day HDRI, and the
## default level's flat background colour) it renders the old environment, then the same
## environment after EyeSky.sync (the real product path: painted sky and edge fog), then a LOUD
## painted sky (red ridges, energy 4) to prove the probe can see a difference. The spheres'
## pixels must be identical in all of them: the painted sky is drawn in the visible pass only.

const SETTLE_FRAMES := 30
const SUN := Vector3(0.0, 0.64, 0.77)

var _cam: Camera3D
var _env: Environment
var _frame := 0
var _spheres: Array[MeshInstance3D] = []
var _shots: Dictionary = {}
var _order := [
	"hdri_old", "hdri_painted", "hdri_loud", "flat_old", "flat_painted", "flat_loud"
]
var _eye_sky := EyeSky.new()
var _panorama_sky: Sky


func _initialize() -> void:
	_panorama_sky = EnvironmentPresets.create_sky_from_preset("clear_day")
	_env = Environment.new()
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = _env
	root.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	root.add_child(_cam)
	_cam.make_current()
	for i in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.WHITE
		m.metallic = [0.0, 1.0, 1.0][i]
		m.roughness = [1.0, 0.5, 0.0][i]
		var sphere := MeshInstance3D.new()
		sphere.mesh = SphereMesh.new()
		sphere.material_override = m
		sphere.position = Vector3(-1.4 + 1.4 * i, 0.0, -4.0)
		root.add_child(sphere)
		_spheres.append(sphere)


func _base(hdri: bool) -> void:
	_eye_sky.leave()
	if hdri:
		_env.background_mode = Environment.BG_SKY
		_env.sky = _panorama_sky
		_env.sky_rotation = Vector3(0.0, deg_to_rad(40.0), 0.0)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color(0.45, 0.55, 0.65)
		_env.sky = null
		_env.sky_rotation = Vector3.ZERO
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
		_env.reflected_light_source = Environment.REFLECTION_SOURCE_BG


func _apply(which: String) -> void:
	_base(which.begins_with("hdri"))
	if which.ends_with("_old"):
		return
	_eye_sky.set_map("temperate_forest_summer_s1", 3)
	_eye_sky.sync(_env, SUN)
	if which.ends_with("_loud"):
		var mat := _eye_sky.material()
		mat.set_shader_parameter("band_energy", 4.0)
		mat.set_shader_parameter("near_color", Color(1.0, 0.0, 0.0))
		mat.set_shader_parameter("far_color", Color(1.0, 0.0, 0.0))
		mat.set_shader_parameter("height_deg", 25.0)
		mat.set_shader_parameter("base_deg", -10.0)


func _process(_delta: float) -> bool:
	_frame += 1
	var step := _frame / SETTLE_FRAMES
	var phase := _frame % SETTLE_FRAMES
	if phase == 1 and step < _order.size():
		_apply(_order[step])
	if phase == 0 and step >= 1 and step <= _order.size():
		_shots[_order[step - 1]] = root.get_texture().get_image()
	if step > _order.size():
		_report()
		return true
	return false


func _sphere_mask(img: Image) -> Array:
	var masks := []
	var k := Vector2(img.get_size()) / Vector2(root.get_visible_rect().size)
	for s in _spheres:
		var c := _cam.unproject_position(s.global_position) * k
		var edge := _cam.unproject_position(s.global_position + _cam.global_basis.x * 0.5) * k
		masks.append([c, (edge - c).length() * 0.8])
	return masks


func _region_diff(a: Image, b: Image, c: Vector2, r: float) -> Array:
	var sum := 0.0
	var mx := 0
	var n := 0
	for y in range(maxi(int(c.y - r), 0), mini(int(c.y + r) + 1, a.get_height())):
		for x in range(maxi(int(c.x - r), 0), mini(int(c.x + r) + 1, a.get_width())):
			if Vector2(x, y).distance_to(c) > r:
				continue
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			for k in 3:
				var d := absi(roundi(pa[k] * 255.0) - roundi(pb[k] * 255.0))
				sum += d
				mx = maxi(mx, d)
			n += 3
	return [sum / maxf(n, 1.0), mx]


func _report() -> void:
	var names := ["diffuse (ambient)", "rough metal 0.5", "mirror (reflection)"]
	for base in ["hdri", "flat"]:
		var old: Image = _shots[base + "_old"]
		var masks := _sphere_mask(old)
		for i in 3:
			var p := Vector2i(masks[i][0])
			print(
				"PROBE| %s sphere %d centre pixel old %s painted %s"
				% [base, i, str(old.get_pixelv(p)), str((_shots[base + "_painted"] as Image).get_pixelv(p))]
			)
		for which in ["painted", "loud"]:
			var img: Image = _shots[base + "_" + which]
			for i in 3:
				var d := _region_diff(old, img, masks[i][0], masks[i][1])
				print(
					"PROBE| %s old vs %s, %s: mean abs byte diff %.4f max %d"
					% [base, which, names[i], d[0], d[1]]
				)
			var mid := Vector2(old.get_width() / 2.0, old.get_height() / 2.0)
			var whole := _region_diff(old, img, mid, 1e5)
			print(
				"PROBE| %s old vs %s, whole frame (sky background included): mean %.4f max %d"
				% [base, which, whole[0], whole[1]]
			)
