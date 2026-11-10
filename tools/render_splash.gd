extends SceneTree

## Renders the boot splash image (`application/boot_splash/image`) from the real d20 model
## (card splash, 2026-11-09). The engine draws that image once, before any script runs, scaled
## to fit the window (stretch mode Keep) on `boot_splash/bg_color`; so the image is square, as
## tall as a 4K window (2160 px, never upscaled at 4K, halved at 1080p), and fades to exactly
## the splash colour at its border so the bars beside it are seamless.
##
## The look is painted, not lit: the die is the d20 mesh with a custom unshaded shader (a warm
## key ramp from rose shadow to pale gold, a cool violet fill, a soft wash across each face and
## worn edges that catch the light, drawn from per-corner barycentrics), over a luminous amber
## glow inside a dusk-indigo haze, with three small gold glints. It renders at twice the output
## size with 4x MSAA and is downsampled with Lanczos.
##
## Run in a real window (it renders), the Godot lane held:
##   godot --path <project> --script res://tools/render_splash.gd -- [--out=<png>]
##     [--size=2160] [--variants=turn,front,low] [--sheet=<png>]
## Without --variants it renders the shipped pose ("turn") to res://assets/splash/boot_splash.png.

const MODEL := "res://assets/models/dice/d20.glb"
const OUT := "res://assets/splash/boot_splash.png"
## application/boot_splash/bg_color
const BG := Color(0.12156863, 0.12156863, 0.14901961)
## The die's height as a share of the image height.
const DIE_HEIGHT := 0.34
## The die sits this share of the image height above the centre (optical centre).
const LIFT := 0.02
const SUPERSAMPLE := 2

## Poses: tilt about X and Y in degrees, applied to the face-on pose (a face toward the viewer,
## its apex down, as in the app icon).
const POSES := {
	"turn": Vector2(-14.0, 24.0),
	"front": Vector2(0.0, 0.0),
	"low": Vector2(18.0, -22.0),
}

const DIE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec3 deep : source_color;
uniform vec3 shade : source_color;
uniform vec3 mid : source_color;
uniform vec3 lit : source_color;
uniform vec3 high : source_color;
uniform vec3 cool : source_color;
uniform vec3 rim_col : source_color;
uniform vec3 key_dir;
uniform vec3 fill_dir;
uniform float edge_w = 0.06;

varying vec3 wn;
varying vec3 wp;
varying vec3 bary;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bary = COLOR.rgb;
}

vec3 ramp(float t) {
	vec3 c = mix(deep, shade, smoothstep(0.0, 0.32, t));
	c = mix(c, mid, smoothstep(0.28, 0.56, t));
	c = mix(c, lit, smoothstep(0.56, 0.8, t));
	return mix(c, high, smoothstep(0.9, 1.08, t));
}

void fragment() {
	vec3 n = normalize(wn);
	vec3 kd = normalize(key_dir);
	float t = dot(n, kd) * 0.5 + 0.5;
	t = clamp(t + dot(wp, kd) * 0.07, 0.0, 1.0);
	vec3 c = ramp(t);
	float f = max(dot(n, normalize(fill_dir)), 0.0);
	c = mix(c, cool, f * 0.45 * (1.0 - t));
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.5);
	c = mix(c, rim_col, rim * 0.35);
	float e = min(min(bary.x, bary.y), bary.z);
	float edge = 1.0 - smoothstep(0.0, edge_w, e);
	c = mix(c, high, edge * (0.12 + 0.6 * t * t));
	ALBEDO = c;
}
"""

const BACK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

uniform vec3 bg : source_color;
uniform vec3 warm : source_color;
uniform vec3 haze : source_color;
uniform vec3 glint : source_color;
uniform vec2 centre;
uniform float extent = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float spark(vec2 p, vec2 at, float s) {
	vec2 d = (p - at) / s;
	float arms = exp(-d.x * d.x * 1.1 - d.y * d.y * 40.0) + exp(-d.y * d.y * 1.1 - d.x * d.x * 40.0);
	return arms * 0.4 + exp(-dot(d, d) * 2.0) * 0.8;
}

void fragment() {
	vec2 p = (wp.xy - centre) / extent;
	float r = length(p);
	float fade = 1.0 - smoothstep(0.34, 0.49, r);
	float h = exp(-pow(r / 0.3, 2.0)) * 0.5;
	float w = exp(-pow(r / 0.15, 2.0)) * 0.42;
	vec3 c = mix(bg, haze, h * fade);
	c = mix(c, warm, w * fade);
	float g = spark(p, vec2(-0.215, 0.11), 0.013);
	g += spark(p, vec2(0.205, 0.165), 0.009) * 0.8;
	g += spark(p, vec2(0.17, -0.19), 0.011) * 0.7;
	c = mix(c, glint, clamp(g, 0.0, 1.0) * fade);
	ALBEDO = c;
}
"""


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return fallback


func _run() -> void:
	var size := int(_arg("size", "2160"))
	var names := _arg("variants", "turn").split(",")
	var out := _arg("out", OUT)
	var sheet_path := _arg("sheet", "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var mesh := _barycentric_mesh()
	var shots: Array[Image] = []
	for n in names:
		var img := await _render(mesh, POSES[n], size)
		shots.append(img)
		var path := out if names.size() == 1 else out.get_basename() + "_%s.png" % n
		var err := img.save_png(ProjectSettings.globalize_path(path))
		print("render_splash: %s %dx%d -> %s (%s)" % [n, size, size, path, error_string(err)])
	if not sheet_path.is_empty():
		var sheet := Image.create(size * shots.size(), size, false, Image.FORMAT_RGB8)
		for i in shots.size():
			sheet.blit_rect(shots[i], Rect2i(0, 0, size, size), Vector2i(size * i, 0))
		sheet.save_png(ProjectSettings.globalize_path(sheet_path))
		print("render_splash: sheet -> %s" % sheet_path)
	quit()


## The d20 mesh with each triangle's corners coloured (1,0,0), (0,1,0), (0,0,1), so the shader
## knows how far a fragment is from the face's edges.
func _barycentric_mesh() -> ArrayMesh:
	var scene: Node = (load(MODEL) as PackedScene).instantiate()
	var src: Mesh = (scene.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).mesh
	scene.free()
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var index := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		index = arrays[Mesh.ARRAY_INDEX]
	if index.is_empty():
		for i in verts.size():
			index.append(i)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var corners := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]
	for i in index.size():
		out_v.append(verts[index[i]])
		out_n.append(normals[index[i]])
		out_c.append(corners[i % 3])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = out_v
	a[Mesh.ARRAY_NORMAL] = out_n
	a[Mesh.ARRAY_COLOR] = out_c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh


## The face-on basis: the face most toward +Z turned to face the camera exactly, its apex down.
func _face_on(mesh: ArrayMesh) -> Basis:
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var best := 0
	var best_dot := -2.0
	for f in range(0, v.size(), 3):
		var n := (v[f + 1] - v[f]).cross(v[f + 2] - v[f]).normalized()
		var centre := (v[f] + v[f + 1] + v[f + 2]) / 3.0
		if n.dot(centre) < 0.0:
			n = -n
		if n.z > best_dot:
			best_dot = n.z
			best = f
	var c := (v[best] + v[best + 1] + v[best + 2]) / 3.0
	var align := Basis(Quaternion(c.normalized(), Vector3.BACK))
	var apex := align * (v[best] - c)
	var roll := Basis(Vector3.BACK, Vector2(apex.x, apex.y).angle_to(Vector2(0, -1)))
	return roll * align


func _render(mesh: ArrayMesh, tilt: Vector2, size: int) -> Image:
	var px := size * SUPERSAMPLE
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_debanding = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var basis := Basis.from_euler(Vector3(deg_to_rad(tilt.x), deg_to_rad(tilt.y), 0.0))
	basis = basis * _face_on(mesh)
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in v:
		var q := basis * p
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var extent := (hi.y - lo.y) / DIE_HEIGHT
	var mid := (lo + hi) * 0.5

	var die := MeshInstance3D.new()
	die.mesh = mesh
	die.transform = Transform3D(basis, Vector3(-mid.x, -mid.y + extent * LIFT, 0.0))
	var dm := ShaderMaterial.new()
	dm.shader = Shader.new()
	dm.shader.code = DIE_SHADER
	dm.set_shader_parameter("deep", Color("7c2c45"))
	dm.set_shader_parameter("shade", Color("c9493a"))
	dm.set_shader_parameter("mid", Color("f2842f"))
	dm.set_shader_parameter("lit", Color("ffb347"))
	dm.set_shader_parameter("high", Color("fff1c4"))
	dm.set_shader_parameter("cool", Color("6f5fc4"))
	dm.set_shader_parameter("rim_col", Color("ffd27a"))
	dm.set_shader_parameter("key_dir", Vector3(-0.55, 0.7, 0.55))
	dm.set_shader_parameter("fill_dir", Vector3(0.75, -0.45, 0.35))
	die.material_override = dm
	vp.add_child(die)

	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(extent, extent)
	back.mesh = quad
	back.position = Vector3(0, 0, -4)
	var bm := ShaderMaterial.new()
	bm.shader = Shader.new()
	bm.shader.code = BACK_SHADER
	bm.set_shader_parameter("bg", BG)
	bm.set_shader_parameter("warm", Color("ff9a48"))
	bm.set_shader_parameter("haze", Color("3d4380"))
	bm.set_shader_parameter("glint", Color("ffe6a8"))
	bm.set_shader_parameter("centre", Vector2(0.0, extent * LIFT))
	bm.set_shader_parameter("extent", extent)
	back.material_override = bm
	vp.add_child(back)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent
	cam.position = Vector3(0, 0, 10)
	cam.near = 0.1
	cam.far = 50.0
	vp.add_child(cam)
	cam.make_current()

	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.convert(Image.FORMAT_RGB8)
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img
