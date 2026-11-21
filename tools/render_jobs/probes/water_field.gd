extends RefCounted

## Render-job probe (`call` op) for the painted water field (card painter-water-field-painted,
## docs/systems/water_field.md "Checking it"): switches the open level between the old painted water
## (AuthoredWater's surface and the fall curtains) and the field surface, takes named views of the
## canonical falls map, and measures CONTINUITY through a fall from a wet capture and a dry one
## (painter-fall-spike's metric): the lip and foot windows' width step dW (under 0.06 is the bar),
## holes (0), the foot's lightness step dL (tracked) and bands. step.action:
##   setup {name}           a named view (CASES).
##   mode {mode}            "main" (the old meshes) or "field" (PainterWater.field_enabled).
##   water {visible}        every water mesh shown or hidden (the dry capture).
##   measure {dir, name, dry, label}  appends a line to metrics.jsonl in `dir`.
##   perf                   one line: field vertices, triangles and build milliseconds.
##   painted {on} / mood {preset, hour} / hud / tokens {items} / cleanup.
## The map is the render job `local/.../build.json` of the card (a 61 m map with six falls, ponds,
## a tributary and a stream into pools), saved as `_painter-water-field-painted_water`.

const WATER := preload("res://tools/render_jobs/probes/water.gd")
const PREFIX := "_painter-water-lip_"
## WaterFieldMesh.MESH_NAME, spelled out so the probe also runs on a tree without the field (the
## baseline the captures compare with).
const FIELD_MESH := "PaintedWaterField"
## The painted water and fall shaders as they were before the field (a card's local copies, kept
## out of the tree), for the A/B "main" mode.
const LEGACY_DIR := "res://tools/render_jobs/local/painter-water-lip/"
const LEGACY_WATER := LEGACY_DIR + "legacy_water.gdshader"
const LEGACY_FALL := LEGACY_DIR + "legacy_waterfall.gdshader"
const STEP_M := 0.05
const UP_M := 2.0
const DOWN_M := 2.0
const WINDOW_M := 0.8
const MASK_DIFF := 0.08
const LATERAL_STEP_M := 0.03
const GAP_SAMPLES := 3
const BAND_L := 0.06

## The named views (`setup {name}`): [pitch, zoom, "case" (a fall near the point, centred) or
## "at" (look at the point), the point, optional yaw].
const CASES := {
	"f1_o": [45, 5.0, "case", Vector2(-8, -8)],
	"f1_t": [80, 5.0, "case", Vector2(-8, -8)],
	"f2_o": [45, 5.0, "case", Vector2(9, -8)],
	"f3_o": [45, 5.0, "case", Vector2(-8, 12)],
	"f3_t": [80, 5.0, "case", Vector2(-8, 12)],
	"f4_o": [45, 5.0, "case", Vector2(9, 12)],
	"f5_o": [45, 5.0, "case", Vector2(-16, -3)],
	"f1_z": [45, 10.0, "case", Vector2(-8, -8)],
	"f1_o8": [45, 8.0, "case", Vector2(-8, -8)],
	"f1_z16": [45, 16.0, "at", Vector2(-8, -6)],
	# The stepped stream (cards painter-water-climb, -climb-2): three filled tiers that descend
	# along +z at x = 23, a fall at each lip into the pool of the tier below; `st_o` and `st_t` the
	# middle fall, `stpool_z3` its pool, `st_w` the stream. `walls_w` is the line drawn over three
	# walls north of it (what these names framed before): a gesture over rises, landed in parts.
	"st_o": [45, 5.0, "case", Vector2(23, 19)],
	"st_t": [88, 5.0, "case", Vector2(23, 19)],
	"st_w": [45, 12.0, "at", Vector2(23, 18)],
	"walls_w": [45, 12.0, "at", Vector2(23, -13)],
	"walls_o": [45, 6.5, "at", Vector2(23, -11)],
	"pond_z8": [45, 8.0, "at", Vector2(9, -2)],
	"f4up_z8": [45, 8.0, "at", Vector2(9, 7)],
	"exit_z8": [45, 8.0, "at", Vector2(-26, 25)],
	"trib_z8": [45, 8.0, "at", Vector2(-6, -5)],
	"wide": [45, 25.0, "at", Vector2(0, -2)],
	"top_wide": [88, 22.0, "at", Vector2(0, 0)],
	"bad_top": [88, 14.0, "at", Vector2(14, 23.5)],
	"bad_o": [45, 12.0, "at", Vector2(14, 23.5)],
	"outlet_z8": [45, 8.0, "at", Vector2(-21, 15)],
	"outlet_t": [80, 6.0, "at", Vector2(-21, 15)],
	"f2mouth_z5": [45, 5.0, "at", Vector2(9, -3)],
	"eye_pond": [28, 7.0, "at", Vector2(9, -2), 0.0],
	"eye_f2": [25, 7.0, "at", Vector2(9, -4)],
	"eye_f2w": [18, 6.0, "at", Vector2(9, -5), 60.0],
	"shore_z3": [45, 3.0, "at", Vector2(5.8, 1.5)],
	"bank_z3": [45, 3.0, "at", Vector2(-3.5, -12.0)],
	"stpool_z3": [45, 3.0, "at", Vector2(23, 21.5)],
}

static var _case: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"painted":
			return _painted(base, bool(step.get("on", true)))
		"mood":
			return _mood(base, step)
		"hud":
			return _hud(base)
		"opt":
			return _opt(base, int(step.get("bits", 0)))
		"clock_set":
			# Pins the water's one clock (with the time scale at 0) so two runs draw the same phase.
			var pw := painter_water(base)
			if pw == null:
				return "not painted"
			pw.set("clock_t", float(step.get("t", 10.0)))
			return "clock_t %.2f" % float(step.get("t", 10.0))
		"defs":
			return _defs(base, String(step.get("defs", "")), String(step.get("file", "")))
		"exact":
			# F1 on or off: the field is rebuilt under the switch.
			var pwe := painter_water(base)
			var host: Variant = pwe.call("field") if pwe != null else null
			if host == null:
				return "not painted"
			WaterField.exact_shore = bool(step.get("on", true))
			host.rebuild()
			return "exact_shore %s" % WaterField.exact_shore
		"gd":
			# The field's GDScript path on or off (ScatterNative.force_gdscript_wfield), the field
			# rebuilt under it: how a twin-only prototype of a field pass is drawn beside the
			# native path in one run (card painter-water-fielddata).
			var pwf := painter_water(base)
			var hostf: Variant = pwf.call("field") if pwf != null else null
			if hostf == null:
				return "not painted"
			ScatterNative.force_gdscript_wfield = bool(step.get("on", false))
			hostf.rebuild()
			return "gdscript field %s" % ScatterNative.force_gdscript_wfield
		"seams":
			# The foot coordinate's seams cleared (shipped) or kept, the field rebuilt under it: the
			# hairline across a pool between two falls, in one run (card painter-water-climb-2).
			var pws := painter_water(base)
			var hosts: Variant = pws.call("field") if pws != null else null
			if hosts == null:
				return "not painted"
			WaterFieldStroke.foot_seams_cleared = bool(step.get("on", true))
			hosts.rebuild()
			return "foot seams cleared %s" % WaterFieldStroke.foot_seams_cleared
		"tokens":
			return _tokens(base, step.get("items", []))
		"state":
			return _state(base, step)
		"cleanup":
			return WATER.run(base, {"action": "cleanup", "prefix": PREFIX})
	var doc := _document(base)
	var root := _map_root(base)
	if doc == null or root == null:
		return "no map document"
	match String(step.get("action", "")):
		"setup":
			return _setup(base, doc, String(step.get("name", "")))
		"mode":
			return set_mode(base, String(step.get("mode", "main")))
		"water":
			return _water(base, root, bool(step.get("visible", true)))
		"measure":
			return _measure(base, step)
		"perf":
			return _perf(base)
		"dump":
			return _dump(base, step)
	return "unknown action %s" % step.get("action", "")


## The PainterWater of the open level (null while the look is not Painted).
static func painter_water(base: Node) -> RefCounted:
	var lpc: Variant = base.get("_level_play_controller")
	if lpc == null or (lpc as Object) == null:
		return null
	var env: Variant = lpc.get_environment_manager()
	var surfaces: Variant = env.get("_surfaces") if env != null else null
	if surfaces == null:
		return null
	return surfaces.call("water") as RefCounted


## "main" draws the old painted water (AuthoredWater's surface and the fall curtains, under the
## shaders of before the field when the card's local `legacy_*` copies exist), "field" the field
## surface under the shipped shaders.
static func set_mode(base: Node, mode: String) -> String:
	var water := painter_water(base)
	if water == null:
		return "not painted"
	var old := mode == "main"
	if water.has_method("field"):
		water.set("field_enabled", not old)
	var legacy := ResourceLoader.exists(LEGACY_WATER) and ResourceLoader.exists(LEGACY_FALL)
	var wm := water.call("water_material") as ShaderMaterial
	var fm := water.call("fall_material") as ShaderMaterial
	if wm != null and fm != null:
		wm.shader = load(LEGACY_WATER if old and legacy else PainterWater.SHADER) as Shader
		fm.shader = load(LEGACY_FALL if old and legacy else PainterWater.FALL_SHADER) as Shader
	return "mode %s%s" % [mode, " (legacy shaders)" if old and legacy else ""]


## Shade spike: sets the field shader's option bits (1 textures, 2 one clock, 4 tint floor and soft
## foot, 8 the hybrid: main's curtain under the legacy fall shader over the steep faces). Call after
## `mode field` (which puts the shipped fall shader back).
static func _opt(base: Node, bits: int) -> String:
	var water := painter_water(base)
	if water == null:
		return "not painted"
	water.set("shade_opt", bits)
	var fm := water.call("fall_material") as ShaderMaterial
	if fm != null:
		var legacy := ResourceLoader.exists(LEGACY_FALL)
		var path: String = LEGACY_FALL if (bits & 8) != 0 and legacy else PainterWater.FALL_SHADER
		fm.shader = load(path) as Shader
	return "shade_opt %d" % bits


## Foot spike: the field shader's own text with `#define`s (space separated, e.g. "FOOT_R1") put at
## its //ABL_DEFS marker, on the shared water material ("" puts the shipped shader back).
static func _defs(base: Node, defs: String, file: String = "") -> String:
	var water := painter_water(base)
	if water == null:
		return "not painted"
	var wm := water.call("water_material") as ShaderMaterial
	if defs.strip_edges() == "" and file == "":
		wm.shader = load(PainterWater.SHADER) as Shader
		return "shader shipped"
	# `file`: another copy of the water shader (a previous card's, in a local folder) to compare.
	var sh := Shader.new()
	var text := FileAccess.get_file_as_string(file if file != "" else PainterWater.SHADER)
	var lines := PackedStringArray()
	for d in defs.split(" ", false):
		# "-NAME" switches a shipped define off.
		lines.append("#undef " + d.substr(1) if d.begins_with("-") else "#define " + d)
	sh.code = text.replace("//ABL_DEFS", "\n".join(lines))
	wm.shader = sh
	return "shader defs %s" % defs


## Foot spike: the field's samples along the open case's centreline (every `every`-th station):
## arc, depth, energy, steep, shore, w, for a metrics-style look at what the shader is fed.
static func _dump(base: Node, step: Dictionary) -> String:
	var pw := painter_water(base)
	if pw == null or _case.is_empty():
		return "no case"
	var host: Variant = pw.call("field")
	if host == null or host.field == null:
		return "no field"
	var f: WaterField = host.field
	var every := int(step.get("every", 4))
	var across: Vector2 = (_case.dir as Vector2).orthogonal()
	var off := float(step.get("across", 0.0))
	var out := PackedStringArray()
	var stations: Array = _case.path
	for k in range(0, stations.size(), every):
		var st: Dictionary = stations[k]
		var p3: Vector3 = st.p
		var p := Vector2(p3.x, p3.z) + across * off
		var i := f.index_of(p)
		if i < 0:
			continue
		out.append(
			(
				"arc %.2f y %.2f depth %.2f en %.2f steep %.2f shore %.2f w %.2f"
				% [st.arc, p3.y, f.depth[i], f.energy[i], f.steep[i], f.shore[i], f.w[i]]
			)
		)
	var path := String(step.get("dir", "user://")).path_join(
		"dump_%s_%s.txt" % [_case.label, String(step.get("tag", "mid"))]
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_line("pool_arc %.2f" % _case.pool_arc)
		for l in out:
			file.store_line(l)
	return "dump %d rows to %s" % [out.size(), path]


## What the water's materials and meshes hold, written in tree order to `dir`/state_`tag`.txt so two
## runs can be diffed (card painter-water-lap): the clock, the time scale, every uniform of each
## water and fall material (a texture as the SHA-1 of its pixels), and per mesh drawn with such a
## material its transform, instance uniforms and the SHA-1 of each vertex array, plus the camera.
## Two runs of a pinned job must write the same file. It is NOT everything the pixels read: the
## engine's TIME and the global shader parameters are not in it (the engine reads the globals back
## only in the editor), so two equal dumps with different pixels point at one of those, as they
## did for the mist on that card.
static func _state(base: Node, step: Dictionary) -> String:
	var lines := PackedStringArray()
	var pw := painter_water(base)
	lines.append("time_scale %s" % var_to_str(Engine.time_scale))
	if pw != null:
		lines.append("clock_t %s" % var_to_str(pw.get("clock_t")))
		lines.append("shade_opt %s" % var_to_str(pw.get("shade_opt")))
	var seen := {}
	var meshes: Array[Node] = base.get_tree().root.find_children("*", "MeshInstance3D", true, false)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as ShaderMaterial
			if mat == null or mat.shader == null or not mat.shader.resource_path.contains("water"):
				continue
			var tag := "mesh %s/%d" % [mi.name, s]
			lines.append("%s shader %s" % [tag, mat.shader.resource_path.get_file()])
			lines.append("%s visible %s" % [tag, mi.is_visible_in_tree()])
			lines.append("%s xform %s" % [tag, var_to_str(mi.global_transform)])
			var arrays := mi.mesh.surface_get_arrays(s)
			for a in arrays.size():
				if arrays[a] != null:
					lines.append("%s array %d %s" % [tag, a, _state_value(arrays[a])])
			for u in mat.shader.get_shader_uniform_list():
				var uname := StringName(u.name)
				var iv: Variant = mi.get_instance_shader_parameter(uname)
				if iv != null:
					lines.append("%s instance %s %s" % [tag, uname, _state_value(iv)])
				if not seen.has(mat):
					var uv: Variant = mat.get_shader_parameter(uname)
					lines.append("%s uniform %s %s" % [tag, uname, _state_value(uv)])
			seen[mat] = true
	var cam := base.get_viewport().get_camera_3d()
	if cam != null:
		lines.append("camera %s fov %s size %s" % [var_to_str(cam.global_transform), cam.fov, cam.size])
	var dir := String(step.get("dir", "user://"))
	var path := dir.path_join("state_%s.txt" % String(step.get("tag", "a")))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "state: cannot write %s" % path
	for l in lines:
		file.store_line(l)
	return "state %d lines to %s" % [lines.size(), path]


## A value of the state dump: a texture or an array as the SHA-1 of its bytes, anything else in
## full.
static func _state_value(v: Variant) -> String:
	if v is Texture2D:
		var tex: Texture2D = v
		var img := tex.get_image()
		var bytes := img.get_data() if img != null else PackedByteArray()
		return "tex %s %s" % [tex.get_size(), bytes.hex_encode().sha1_text()]
	if v is Array or typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
		return "sha1 %s" % var_to_bytes(v).hex_encode().sha1_text()
	return var_to_str(v)


static func _setup(base: Node, doc: MapDocument, name: String) -> String:
	if not CASES.has(name):
		return "no case %s" % name
	var spec: Array = CASES[name]
	var gm := base.get("_game_map") as GameMap
	var cc := gm.get_camera_controller()
	cc.set_yaw_now(float(spec[4]) if spec.size() > 4 else 0.0)
	cc.set_pitch_now(float(spec[0]))
	(cc.view_mode() as OrbitView).target_zoom = float(spec[1])
	var p: Vector2 = spec[3]
	if spec[2] == "case":
		return _pick(base, doc, {"near": [p.x, p.y], "label": name})
	_case = {}
	return WATER.run(base, {"action": "look", "at": [p.x, p.y]})


static func _document(base: Node) -> MapDocument:
	var lpc: Variant = base.get("_level_play_controller")
	if lpc != null and (lpc as Node) != null and lpc.loaded_map_document != null:
		return lpc.loaded_map_document
	var ctrl: Variant = base.get("_authoring_controller")
	if ctrl != null and (ctrl as Node) != null and ctrl.editor != null:
		return ctrl.document
	return null


static func _map_root(base: Node) -> Node3D:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.map_container == null:
		return null
	return gm.map_container.get_node_or_null(^"LevelMap") as Node3D


static func _pick(base: Node, doc: MapDocument, step: Dictionary) -> String:
	var near_v: Array = step.get("near", [0, 0])
	var near := Vector2(float(near_v[0]), float(near_v[1]))
	var best: Dictionary = {}
	for frame in WaterFallFrames.frames(doc, WaterFalls.falls(doc)):
		var lip: Vector2 = frame.lip
		if best.is_empty() or lip.distance_to(near) < (best.lip as Vector2).distance_to(near):
			best = frame
	if best.is_empty():
		return "no falls"
	_case = best.duplicate()
	_case["hw"] = float(best.fall.half_width)
	_case["label"] = String(step.get("label", "case"))
	_case["path"] = _centreline(doc, best)
	var lip: Vector2 = best.lip
	var dir: Vector2 = best.dir
	var middle := lip + dir * (float(best.x_pool) * 0.5)
	var gm := base.get("_game_map") as GameMap
	var forward := -gm.camera_node.global_transform.basis.z
	var flat := Vector2(forward.x, forward.z)
	var tan_pitch := maxf(-forward.y, 0.05) / maxf(flat.length(), 0.05)
	flat = flat.normalized() if flat.length() > 1e-4 else Vector2.ZERO
	var y_mid := (float(best.top) + float(best.bottom)) * 0.5
	var target := middle
	for _pass in 3:
		var g := WaterGeometry.ground_at(doc, target)
		target = middle + flat * ((y_mid - g) / tan_pitch)
	WATER.run(base, {"action": "look", "at": [target.x, target.y]})
	return (
		"case %s: lip %s dir %s drop %.2f hw %.2f x_pool %.2f"
		% [
			_case.label,
			str(lip.snapped(Vector2.ONE * 0.01)),
			str(dir.snapped(Vector2.ONE * 0.01)),
			best.drop,
			_case.hw,
			best.x_pool,
		]
	)


## The fall's centreline from 2 m above the lip to 2 m past the foot, every STEP_M, each with its
## arc length (0 at the lip).
static func _centreline(doc: MapDocument, frame: Dictionary) -> Array[Dictionary]:
	var lip: Vector2 = frame.lip
	var dir: Vector2 = frame.dir
	var top: float = frame.top
	var bottom: float = frame.bottom
	var rows: PackedFloat32Array = frame.rows
	var x_max := WaterCarve.fall_foot(top - bottom, frame.depth) + WaterFallMesh.END_PAST_FOOT_M
	var mid := WaterFallMesh.trajectory(
		doc, lip, dir, top, bottom, frame.depth, frame.v0, rows, x_max
	)
	var poly := PackedVector3Array()
	poly.append(Vector3(lip.x - dir.x * UP_M, top, lip.y - dir.y * UP_M))
	for k in rows.size() - 1:
		poly.append(mid[k])
	var at_pool := mid[rows.size() - 2]
	poly.append(at_pool + Vector3(dir.x, 0.0, dir.y) * DOWN_M)
	var out: Array[Dictionary] = []
	var arc := -UP_M
	var pool_arc := 0.0
	for i in poly.size() - 1:
		var a := poly[i]
		var b := poly[i + 1]
		var length := a.distance_to(b)
		if i == rows.size() - 1:
			pool_arc = arc
		if length < 1e-6:
			continue
		var t := 0.0
		while t < length - 1e-6:
			out.append({"p": a.lerp(b, t / length), "arc": arc + t})
			t += STEP_M
		arc += length
	_case["pool_arc"] = pool_arc
	return out


## The dry capture's state: every water mesh hidden (the field's and the old ones), or put back
## as the current mode shows them.
static func _water(base: Node, root: Node3D, visible: bool) -> String:
	var count := 0
	var field_on := true
	var pw := painter_water(base)
	if pw != null:
		field_on = bool(pw.get("field_enabled"))
	for name: String in ["AuthoredWater-water", FIELD_MESH, "AuthoredWater-falls"]:
		for node in root.find_children(name, "MeshInstance3D", true, false):
			var inst := node as MeshInstance3D
			if not visible:
				inst.visible = false
			elif name == FIELD_MESH:
				inst.visible = field_on
			elif name == "AuthoredWater-water":
				inst.visible = not field_on or root.find_child(FIELD_MESH, true, false) == null
			else:
				inst.visible = true
			count += 1
	return "water meshes visible %s: %d" % [visible, count]


static func _perf(base: Node) -> String:
	var pw := painter_water(base)
	if pw == null:
		return "not painted"
	if not pw.has_method("field"):
		return "no field on this tree"
	var host: Variant = pw.call("field")
	if host == null or host.field == null:
		return "no field"
	return "field %s counts %s timings %s" % [host.field.size, str(host.counts), str(host.timings)]


static func _measure(base: Node, step: Dictionary) -> String:
	if _case.is_empty():
		return "no case"
	var gm := base.get("_game_map") as GameMap
	var cam := gm.camera_node
	var view_size := Vector2(gm.world_viewport.size)
	var dir := String(step.get("dir", ""))
	var wet_img := Image.load_from_file(dir.path_join(String(step.name) + "_sub.png"))
	var dry_img := Image.load_from_file(dir.path_join(String(step.dry) + "_sub.png"))
	if wet_img == null or dry_img == null:
		return "missing captures"
	var scale := float(wet_img.get_width()) / view_size.x
	var lip_dir: Vector2 = _case.dir
	var across := Vector3(lip_dir.orthogonal().x, 0.0, lip_dir.orthogonal().y)
	var hw: float = _case.hw
	var reach := hw * 1.6 + 1.0
	var stations: Array = _case.path
	var labs: Array[Vector3] = []
	var widths := PackedFloat32Array()
	var holes := PackedInt32Array()
	var px_per_m := 0.0
	var off_screen := 0
	for st: Dictionary in stations:
		st.erase("off")
		var p: Vector3 = st.p
		var px := cam.unproject_position(p) * scale
		if (
			px.x < 2.0
			or px.y < 2.0
			or px.x > wet_img.get_width() - 3.0
			or px.y > wet_img.get_height() - 3.0
		):
			off_screen += 1
			st["off"] = true
		labs.append(_oklab(_mean(wet_img, px)))
		var w := 0.0
		var gaps := 0
		var centre_dry := 0 if _masked(wet_img, dry_img, px) else 1
		for side in [-1.0, 1.0]:
			var t := LATERAL_STEP_M
			var run_dry := 0
			var extent := 0.0
			while t <= reach:
				var q := cam.unproject_position(p + across * (t * side)) * scale
				if _masked(wet_img, dry_img, q):
					if run_dry > 0 and extent > 0.0:
						gaps += 1
					run_dry = 0
					extent = t
				else:
					run_dry += 1
					if run_dry >= GAP_SAMPLES:
						break
				t += LATERAL_STEP_M
			w += extent
		if px_per_m == 0.0:
			var q1 := cam.unproject_position(p + across) * scale
			px_per_m = q1.distance_to(px)
		widths.append(w)
		holes.append(centre_dry + gaps)
	var pool_arc: float = _case.pool_arc
	var lip_m := _window(stations, labs, widths, holes, 0.0, hw)
	var foot_m := _window(stations, labs, widths, holes, pool_arc, hw)
	if bool(step.get("trace", false)):
		# The foot window's lightness along the path (arc:L, every station), to see where a step stands.
		var trace := PackedStringArray()
		for st_i in stations.size():
			var tarc: float = stations[st_i].arc
			if absf(tarc - pool_arc) <= WINDOW_M:
				trace.append("%.2f:%.0f" % [tarc, labs[st_i].x * 100.0])
		print("RJ| trace %s pool_arc %.2f  %s" % [step.get("label", ""), pool_arc, " ".join(trace)])
	var all_holes := 0
	for st_i in stations.size():
		var arc: float = stations[st_i].arc
		var shown := not bool(stations[st_i].get("off", false))
		if shown and arc > -1.0 and arc < pool_arc + 1.0:
			all_holes += holes[st_i]
	# Foot spike: what the field holds under each hole station (the one-pixel probe).
	var hole_info: Array = []
	var pw := painter_water(base)
	var host: Variant = pw.call("field") if pw != null and pw.has_method("field") else null
	if host != null and host.field != null and all_holes > 0:
		var f: WaterField = host.field
		for st_i in stations.size():
			var st: Dictionary = stations[st_i]
			var arc: float = st.arc
			if holes[st_i] == 0 or bool(st.get("off", false)) or arc < -1.0 or arc > pool_arc + 1.0:
				continue
			var p3: Vector3 = st.p
			var i := f.index_of(Vector2(p3.x, p3.z))
			if i < 0:
				continue
			var min_d := INF
			for o in [-1, 0, 1, -f.size.x, f.size.x, -f.size.x - 1, f.size.x + 1]:
				if i + o >= 0 and i + o < f.depth.size():
					min_d = minf(min_d, f.depth[i + o])
			hole_info.append(
				{
					"arc": snappedf(arc, 0.01),
					"holes": holes[st_i],
					"y": snappedf(p3.y, 0.01),
					"depth": snappedf(f.depth[i], 0.001),
					"min_nb_depth": snappedf(min_d, 0.001),
					"w": snappedf(f.w[i], 0.01),
					"en": snappedf(f.energy[i], 0.01),
					"steep": snappedf(f.steep[i], 0.01),
					"shore": snappedf(f.shore[i], 0.01),
					"spill": f.spill[i],
					"calm": f.calm[i],
					"owner": f.owner[i],
				}
			)
	var record := {
		"hole_info": hole_info,
		"case": _case.label,
		"label": String(step.get("label", "")),
		"capture": String(step.name),
		"lip": lip_m,
		"foot": foot_m,
		"holes_path": all_holes,
		"off_screen": off_screen,
		"px_per_m": snappedf(px_per_m, 0.1),
		"pool_arc": snappedf(pool_arc, 0.01),
	}
	var file_path := dir.path_join("metrics.jsonl")
	var f := FileAccess.open(file_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(file_path, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify(record))
		f.close()
	return (
		(
			"measure %s %s: lip dL %.1f dab %.1f bands %d dW %.2f holes %d"
			+ " | foot dL %.1f dab %.1f bands %d dW %.2f holes %d | path holes %d px/m %.0f off %d"
		)
		% [
			_case.label,
			String(step.get("label", step.name)),
			lip_m.dL,
			lip_m.dab,
			lip_m.bands,
			lip_m.dW,
			lip_m.holes,
			foot_m.dL,
			foot_m.dab,
			foot_m.bands,
			foot_m.dW,
			foot_m.holes,
			all_holes,
			px_per_m,
			off_screen,
		]
	)


static func _window(
	stations: Array,
	labs: Array[Vector3],
	widths: PackedFloat32Array,
	holes: PackedInt32Array,
	centre: float,
	hw: float
) -> Dictionary:
	var d_l := 0.0
	var d_ab := 0.0
	var d_w := 0.0
	var hole_count := 0
	var bands := 0
	var last_extreme := -1.0
	var trend := 0
	var prev := -1
	for i in stations.size():
		var arc: float = stations[i].arc
		if absf(arc - centre) > WINDOW_M or bool(stations[i].get("off", false)):
			continue
		hole_count += holes[i]
		if prev >= 0:
			var a := labs[prev]
			var b := labs[i]
			d_l = maxf(d_l, absf(b.x - a.x))
			d_ab = maxf(d_ab, Vector2(b.y - a.y, b.z - a.z).length())
			d_w = maxf(d_w, absf(widths[i] - widths[prev]) / maxf(2.0 * hw, 0.1))
			if last_extreme < 0.0:
				last_extreme = a.x
			var diff := b.x - last_extreme
			if trend >= 0 and diff < -BAND_L:
				if trend > 0:
					bands += 1
				trend = -1
				last_extreme = b.x
			elif trend <= 0 and diff > BAND_L:
				if trend < 0:
					bands += 1
				trend = 1
				last_extreme = b.x
			elif (trend > 0 and b.x > last_extreme) or (trend < 0 and b.x < last_extreme):
				last_extreme = b.x
		prev = i
	return {
		"dL": snappedf(d_l * 100.0, 0.1),
		"dab": snappedf(d_ab * 100.0, 0.1),
		"dW": snappedf(d_w, 0.01),
		"holes": hole_count,
		"bands": bands,
	}


static func _masked(wet: Image, dry: Image, px: Vector2) -> bool:
	var x := clampi(int(px.x), 0, wet.get_width() - 1)
	var y := clampi(int(px.y), 0, wet.get_height() - 1)
	var a := wet.get_pixel(x, y)
	var b := dry.get_pixel(x, y)
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) > MASK_DIFF


static func _mean(img: Image, px: Vector2) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := clampi(int(px.x) + dx, 0, img.get_width() - 1)
			var y := clampi(int(px.y) + dy, 0, img.get_height() - 1)
			sum += img.get_pixel(x, y)
			n += 1
	return sum / float(n)


static func _oklab(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	var l := 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b
	var m := 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b
	var s := 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b
	l = pow(l, 1.0 / 3.0)
	m = pow(m, 1.0 / 3.0)
	s = pow(s, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	)


static func _painted(base: Node, on: bool) -> String:
	var lpc: LevelPlayController = base.get("_level_play_controller")
	if lpc == null:
		return "not playing"
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED if on else RenderStyle.CHOICE_CLASSIC
	lpc.get_environment_manager().apply_render_style()
	return "painted %s" % on


## `preset` "level" restores the level's own mood; any other names an environment preset ("dusk",
## "arctic", ...); `hour` (0-24) sets the sun to that time of day through DefaultSun.
static func _mood(base: Node, step: Dictionary) -> String:
	var lpc: LevelPlayController = base.get("_level_play_controller")
	if lpc == null or lpc.active_level_data == null:
		return "not playing"
	var level := lpc.active_level_data
	var preset := String(step.get("preset", "level"))
	var sun := level.visual_settings.sun.copy_settings()
	if preset == "level" and not step.has("hour"):
		lpc.apply_environment_settings(level.environment_preset, level.environment_overrides)
		lpc.apply_sun_settings(sun)
		return "mood level ('%s')" % level.environment_preset
	if step.has("hour"):
		var timed := DefaultSun.settings_for_time(float(step["hour"]))
		sun.azimuth_degrees = timed.azimuth_degrees
		sun.elevation_degrees = timed.elevation_degrees
		sun.color = timed.color
		sun.energy = timed.energy
		sun.time_of_day = timed.time_of_day
	var name := level.environment_preset if preset == "level" else preset
	lpc.apply_environment_settings(name, {})
	lpc.apply_sun_settings(sun)
	return "mood %s sun az %.0f el %.0f" % [name, sun.azimuth_degrees, sun.elevation_degrees]


static func _hud(base: Node) -> String:
	var names := PackedStringArray()
	for node in base.get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.name == "WorldViewportLayer" or not layer.visible:
			continue
		layer.visible = false
		names.append(String(layer.name))
	return "hud hidden: %s" % ", ".join(names)


static func _tokens(base: Node, items: Array) -> String:
	var row: GDScript = load("res://tools/render_jobs/probes/token_toon_row.gd")
	var out := PackedStringArray()
	for item: Array in items:
		var spec := {
			"action": "spawn_row",
			"from": [item[0], item[1]],
			"to": [item[0], item[1]],
			"items": [item[2]],
			"yaw": float(item[3]) if item.size() > 3 else 200.0,
		}
		out.append(str(row.call("run", base, spec)))
	return "; ".join(out)
