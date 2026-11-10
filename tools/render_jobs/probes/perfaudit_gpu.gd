extends RefCounted

## Render-job probe for the GPU audit (topic perfaudit, stream gpu, 2026-11-09): where the world
## viewport's GPU time goes, pass by pass, and what each knob of the pipeline buys. One `call` step
## per action; every action writes into `dir` (default user://render_jobs/perfaudit_gpu).
##
##   {action: "explore", name}
##       The renderer, the project's render settings, the environment, the sun's shadow setup, the
##       VRAM counters, every visible GeometryInstance3D grouped by class (see _class_of: the
##       material's shader file name, plus the foliage wind category) with nodes, instances,
##       triangles and shadow casters, the MultiMeshes grouped by mesh (species), and every texture
##       the classes' materials bind (size, layers, mips, format, bytes). Writes <name>_explore.txt.
##   {action: "perf", name, rounds: 6, warm: 1, frames: 60, settle: 20, base: {..}, variants: [..]}
##       In-run A/B under the pinned procedure (vsync off, max_fps 0, the same camera): each round
##       measures the base, every variant (order rotated each round, reversed on odd rounds), then
##       the base again for the drift check; the first `warm` rounds are discarded. A variant is a
##       dictionary of knobs merged over `base` (knob list: _apply). Per frame: the world and root
##       viewports' measured GPU time, the world's CPU render time, wall time, and every engine
##       pass timestamp (only with --gpu-profile on the command line) inside the world viewport.
##       Writes <name>_table.txt: per configuration the median of the round medians and their
##       range, the passes, and the render info (objects, primitives, draw calls; visible and
##       shadow).
##   {action: "overdraw", name, sets: [{name, hide?: [..], calib?: true}]}
##       The overdraw debug view (every draw additive, no depth rejection) under a linear tonemap.
##       The `calib` set (the ground alone) gives one layer's value; each set then reports the
##       layers per pixel (mean, p50, p90, p99, share over 4, 8 and 16) and saves <name>_<set>.png.
##   {action: "pose", mode: "eye"|"orbit", at: [x, z], yaw, pitch}
##       The eye view standing at `at` (with the shipped eye MSAA), or back to the orbit view.
##   {action: "await"}  holds the job while a rig runs.
##
## Knobs (absent = left as the game set it): hide [class globs], q (0-5 shadow filter tier),
## shadows (bool), cascades (1, 2, 4), shadow_dist (m), atlas (directional atlas px), ssao, glow,
## fog, lofi (bool), prepass (bool, rendering/driver/depth_prepass/enable), scale (0-1),
## upscale ("bilinear", "fsr", "fsr2"), msaa (0, 2, 4, 8, through VisualEffectsController so the
## foliage swaps its cutout variant), taa, fxaa (bool), aniso (0-4), size ([w, h] world viewport),
## fshader ("trivial", "unshaded", "cheap": every wind material's shader), ground_flat (bool: a
## plain lit StandardMaterial3D over the ground classes; or "skirt" / "map" for one of them),
## debug (Viewport.DEBUG_DRAW_* int), and
## blend, splits, noaa, a2c (perfaudit_gpu_knobs.gd).

const GROUP := "perfaudit_gpu_rig"
const HIDE_LAYER := 1 << 19
const DEFAULT_DIR := "user://render_jobs/perfaudit_gpu"
const Util := preload("res://tools/render_jobs/probes/perfaudit_gpu_util.gd")
const Knobs := preload("res://tools/render_jobs/probes/perfaudit_gpu_knobs.gd")


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the perfaudit gpu rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var gm: GameMap = base.get("_game_map")
	if gm == null:
		return "%s: no map open" % action
	if action == "pose":
		return _pose(gm, step)
	var rig := Rig.new()
	rig.gm = gm
	rig.step = step
	rig.mode = action
	base.get_tree().root.add_child(rig)
	return "%s %s started" % [action, String(step.get("name", ""))]


static func _pose(gm: GameMap, step: Dictionary) -> String:
	var cc := gm.get_camera_controller()
	if String(step.get("mode", "orbit")) == "eye":
		var at := Vector2(float(step.at[0]), float(step.at[1]))
		cc.set_view_mode(cc.eye)
		cc.eye.frame_ground(at, 0.0)
		cc.set_yaw_now(float(step.get("yaw", 45.0)))
		cc.set_pitch_now(float(step.get("pitch", 0.0)))
		cc.finish_zoom()
		gm.eye_view_antialiasing = true
	else:
		cc.set_view_mode(cc.orbit_view())
		gm.eye_view_antialiasing = false
		if step.has("pitch"):
			cc.set_pitch_now(float(step.pitch))
	return "pose %s" % String(cc.view_mode().mode_name())


class Rig:
	extends Node

	var gm: GameMap = null
	var step: Dictionary = {}
	var mode := "perf"
	var _dir := ""
	var _lines: Array[String] = []
	var _orig := {}
	var _hidden := {}
	var _flat_ground: StandardMaterial3D = null
	var _ground_overrides := {}
	var _foliage_shaders := {}
	var _msaa_changed := false
	var _atlas := -1
	var _q := -1
	var _class_cache := {}
	var _ground_shaders := {}
	var _built_shaders := {}
	var _ground_prios := {}
	var _knobs: RefCounted = null

	## class_of as first seen, before the rig swapped any material (a flat ground override
	## would otherwise read as "std" and fall out of the ground globs).
	func _cls(gi: GeometryInstance3D) -> String:
		if not _class_cache.has(gi):
			_class_cache[gi] = class_of(gi)
		return _class_cache[gi]

	## The class of a geometry instance: a kind prefix, the shader file name of its material (or
	## "std" for a StandardMaterial3D) and, for foliage, the material's wind category.
	static func class_of(gi: GeometryInstance3D) -> String:
		var mat: Material = gi.material_override
		var mesh: Mesh = null
		var prefix := ""
		if gi is MultiMeshInstance3D:
			prefix = "mm:"
			var mm := (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh if mm != null else null
		elif gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
			if mat == null and mesh != null and mesh.get_surface_count() > 0:
				mat = (gi as MeshInstance3D).get_active_material(0)
		elif gi is GPUParticles3D or gi is CPUParticles3D:
			prefix = "particles:"
		else:
			prefix = gi.get_class().to_lower() + ":"
		if mat == null and mesh != null and mesh.get_surface_count() > 0:
			mat = mesh.surface_get_material(0)
		var shader_name := "none"
		if mat is ShaderMaterial:
			var sh := (mat as ShaderMaterial).shader
			shader_name = sh.resource_path.get_file().get_basename() if sh != null else "noshader"
			if shader_name.is_empty():
				shader_name = "inline"
		elif mat is BaseMaterial3D:
			shader_name = "std"
		var cat := ""
		if mat != null and mat.has_meta("wind_category"):
			cat = ":" + str(mat.get_meta("wind_category"))
		return prefix + shader_name + cat

	static func triangles(mesh: Mesh) -> int:
		var am := mesh as ArrayMesh
		if am == null:
			return 0
		var n := 0
		for s in am.get_surface_count():
			var idx := am.surface_get_array_index_len(s)
			n += (idx if idx > 0 else am.surface_get_array_len(s)) / 3
		return n

	func _ready() -> void:
		add_to_group(GROUP)
		_dir = ProjectSettings.globalize_path(String(step.get("dir", DEFAULT_DIR)))
		DirAccess.make_dir_recursive_absolute(_dir)
		_main()

	func _main() -> void:
		_capture_originals()
		match mode:
			"explore":
				_explore()
			"perf":
				await _perf()
			"overdraw":
				await _overdraw()
			"shots":
				await _shots()
			_:
				_log("unknown action %s" % mode)
		_apply({})
		var tag := "%s_%s" % [String(step.get("name", mode)), mode]
		var f := FileAccess.open(_dir.path_join("%s.txt" % tag), FileAccess.WRITE)
		if f != null:
			for l in _lines:
				f.store_line(l)
		print("RJ| perfaudit_gpu %s done, %d lines, %s" % [tag, _lines.size(), _dir])
		queue_free()

	func _log(text: String) -> void:
		_lines.append(text)
		print("RJ| " + text)

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	static func _median(a: Array) -> float:
		if a.is_empty():
			return 0.0
		var b := a.duplicate()
		b.sort()
		return float(b[b.size() / 2])

	static func _min(a: Array) -> float:
		return float(a.min()) if not a.is_empty() else 0.0

	static func _max(a: Array) -> float:
		return float(a.max()) if not a.is_empty() else 0.0

	# ---- knobs ----

	func _env() -> Environment:
		for node in gm.world_viewport.find_children("*", "WorldEnvironment", true, false):
			var we := node as WorldEnvironment
			if we.environment != null:
				return we.environment
		return gm.world_viewport.world_3d.environment if gm.world_viewport.world_3d else null

	func _suns() -> Array[DirectionalLight3D]:
		var out: Array[DirectionalLight3D] = []
		for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			var light := node as DirectionalLight3D
			if light.shadow_enabled or light.has_meta("perfaudit_sun"):
				light.set_meta("perfaudit_sun", true)
				out.append(light)
		return out

	func _vfx() -> VisualEffectsController:
		return gm.get("_visual_effects") as VisualEffectsController

	func _capture_originals() -> void:
		var vp := gm.world_viewport
		var env := _env()
		_orig = {
			"prepass": ProjectSettings.get_setting("rendering/driver/depth_prepass/enable", true),
			"scale": vp.scaling_3d_scale,
			"upscale": vp.scaling_3d_mode,
			"msaa": vp.msaa_3d,
			"msaa_setting": int(_vfx().get("_foliage_antialiasing_level")),
			"taa": vp.use_taa,
			"fxaa": vp.screen_space_aa,
			"aniso": vp.anisotropic_filtering_level,
			"debug": vp.debug_draw,
			"lofi_mat": gm.viewport_container.material,
			"stretch": gm.viewport_container.stretch,
			"vp_size": vp.size,
			"q": 4,
			"atlas": int(
				ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
			),
		}
		if env != null:
			_orig["ssao"] = env.ssao_enabled
			_orig["glow"] = env.glow_enabled
			_orig["fog"] = env.fog_enabled
		var suns := {}
		for s in _suns():
			suns[s] = {
				"on": s.shadow_enabled,
				"mode": s.directional_shadow_mode,
				"dist": s.directional_shadow_max_distance
			}
		_orig["suns"] = suns

	## Every knob to `cfg`'s value, or back to what the game had when the rig started.
	func _apply(cfg: Dictionary) -> void:
		if _knobs != null:
			_knobs.restore_foliage()
			_knobs.restore_casts()
		var vp := gm.world_viewport
		var env := _env()
		ProjectSettings.set_setting(
			"rendering/driver/depth_prepass/enable", bool(cfg.get("prepass", _orig.prepass))
		)
		var q := int(cfg.get("q", _orig.q))
		if q != _q:
			_q = q
			RenderingServer.directional_soft_shadow_filter_set_quality(q)
		var atlas := int(cfg.get("atlas", _orig.atlas))
		if atlas != _atlas:
			_atlas = atlas
			RenderingServer.directional_shadow_atlas_set_size(atlas, true)
		var suns: Dictionary = _orig.suns
		for s: DirectionalLight3D in suns:
			var o: Dictionary = suns[s]
			s.shadow_enabled = bool(cfg.get("shadows", o.on))
			var casc := int(cfg.get("cascades", 0))
			s.directional_shadow_mode = (
				o.mode
				if casc == 0
				else (
					DirectionalLight3D.SHADOW_ORTHOGONAL
					if casc == 1
					else (
						DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
						if casc == 2
						else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
					)
				)
			)
			s.directional_shadow_max_distance = float(cfg.get("shadow_dist", o.dist))
		if env != null:
			env.ssao_enabled = bool(cfg.get("ssao", _orig.ssao))
			env.glow_enabled = bool(cfg.get("glow", _orig.glow))
			env.fog_enabled = bool(cfg.get("fog", _orig.fog))
		gm.viewport_container.material = (
			_orig.lofi_mat if bool(cfg.get("lofi", true)) else null
		)
		vp.scaling_3d_scale = float(cfg.get("scale", _orig.scale))
		var modes := {
			"bilinear": Viewport.SCALING_3D_MODE_BILINEAR,
			"fsr": Viewport.SCALING_3D_MODE_FSR,
			"fsr2": Viewport.SCALING_3D_MODE_FSR2
		}
		vp.scaling_3d_mode = (
			modes.get(String(cfg.upscale), _orig.upscale) if cfg.has("upscale") else _orig.upscale
		)
		if cfg.has("msaa"):
			_vfx().set_foliage_antialiasing_level(int(cfg.msaa))
			_msaa_changed = true
		elif _msaa_changed:
			_vfx().set_foliage_antialiasing_level(int(_orig.msaa_setting))
			_msaa_changed = false
		vp.use_taa = bool(cfg.get("taa", _orig.taa))
		vp.screen_space_aa = (
			Viewport.SCREEN_SPACE_AA_FXAA if bool(cfg.get("fxaa", false)) else _orig.fxaa
		)
		vp.anisotropic_filtering_level = int(cfg.get("aniso", _orig.aniso))
		vp.debug_draw = int(cfg.get("debug", _orig.debug))
		if cfg.has("size"):
			gm.viewport_container.stretch = false
			vp.size = Vector2i(int(cfg.size[0]), int(cfg.size[1]))
		else:
			# The output-sized viewport (WorldView, rendersize) is never stretched, so the size
			# itself goes back, not only the stretch flag (card minspec2).
			if gm.viewport_container.stretch != _orig.stretch:
				gm.viewport_container.stretch = _orig.stretch
			if vp.size != _orig.vp_size:
				vp.size = _orig.vp_size
		_set_hidden(cfg.get("hide", []))
		_set_foliage_shader(String(cfg.get("fshader", "")))
		var flat: Variant = cfg.get("ground_flat", false)
		_set_ground_flat(flat if flat is String else ("all" if bool(flat) else ""))
		_set_ground_shader(String(cfg.get("gshader", "")))
		_set_ground_priority(int(cfg.get("gprio", 0)))
		if _knobs == null:
			_knobs = Knobs.new()
			_knobs.rig = self
		_knobs.apply(gm, cfg)

	## Every ground material's (chunks and skirt) render_priority, or back to what it was. The
	## opaque passes sort by priority before shader and material, so it decides whether the ground
	## draws before or after the foliage in the depth pre-pass.
	func _set_ground_priority(prio: int) -> void:
		for m: Material in _ground_prios:
			m.render_priority = _ground_prios[m]
		_ground_prios.clear()
		if prio == 0:
			return
		for node in gm.world_viewport.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			if not _cls(gi).contains("authored_ground") or not gi is MeshInstance3D:
				continue
			var m := gi.material_override
			if m == null:
				m = (gi as MeshInstance3D).get_active_material(0)
			if m != null and not _ground_prios.has(m):
				_ground_prios[m] = m.render_priority
				m.render_priority = prio

	## Every ground chunk's ShaderMaterial on the shader at `path`, or back (see _define_shader).
	func _set_ground_shader(path: String) -> void:
		for m: ShaderMaterial in _ground_shaders:
			m.shader = _ground_shaders[m]
		_ground_shaders.clear()
		if path.is_empty():
			return
		var target := _define_shader(path) if path.contains("#") else load(path) as Shader
		# A define spec also swaps the skirt, with GROUND_SKIRT added.
		var skirt_target := _define_shader(path + ",GROUND_SKIRT") if path.contains("#") else null
		for node in gm.world_viewport.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			var on_skirt := skirt_target != null and _cls(gi).begins_with("authored_ground_skirt")
			var on_map := (
				_cls(gi).begins_with("authored_ground_looked")
				or _cls(gi).begins_with("authored_ground_clip")
			)
			if not on_map and not on_skirt:
				continue
			var mesh := (gi as MeshInstance3D).mesh if gi is MeshInstance3D else null
			var m := gi.material_override as ShaderMaterial
			if m == null and mesh != null and mesh.get_surface_count() > 0:
				m = (gi as MeshInstance3D).get_active_material(0) as ShaderMaterial
			if m != null and not _ground_shaders.has(m):
				_ground_shaders[m] = m.shader
				m.shader = skirt_target if on_skirt else target

	## The opaque ground shader from an include and defines, "res://x.gdshaderinc#A,B" (Util).
	func _define_shader(spec: String) -> Shader:
		return Util.define_shader(spec, Util.GROUND_MODE, _built_shaders)

	## Whether `key` matches one of the globs and none of the "!glob" exclusions.
	func _matches(key: String, patterns: Array) -> bool:
		var hit := false
		for p in patterns:
			var glob := String(p)
			if glob.begins_with("!"):
				if key.match(glob.substr(1)):
					return false
			elif key.match(glob):
				hit = true
		return hit

	## Moves every instance whose class matches a glob onto HIDE_LAYER (which the camera does not
	## draw) with its shadow off; everything else back as it was.
	func _set_hidden(patterns: Array) -> void:
		var cam := gm.camera_node
		if patterns.is_empty():
			for gi: GeometryInstance3D in _hidden:
				if is_instance_valid(gi):
					gi.layers = _hidden[gi].layers
					gi.cast_shadow = _hidden[gi].cast
			_hidden.clear()
			cam.cull_mask |= HIDE_LAYER
			return
		cam.cull_mask &= ~HIDE_LAYER
		var keep := {}
		for node in gm.world_viewport.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			if gi.layers == HIDE_LAYER and not _hidden.has(gi):
				continue
			if _matches(_cls(gi), patterns):
				keep[gi] = true
				if not _hidden.has(gi):
					_hidden[gi] = {"layers": gi.layers, "cast": gi.cast_shadow}
					gi.layers = HIDE_LAYER
					gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for gi: GeometryInstance3D in _hidden.keys():
			if not keep.has(gi):
				if is_instance_valid(gi):
					gi.layers = _hidden[gi].layers
					gi.cast_shadow = _hidden[gi].cast
				_hidden.erase(gi)

	func _set_foliage_shader(kind: String) -> void:
		var target: Shader = null
		match kind:
			"trivial":
				target = WindFoliage.get_shader_debug_trivial()
			"unshaded":
				target = WindFoliage.get_shader_debug_unshaded()
			"cheap":
				target = WindFoliage.get_shader_debug_cheap_lighting()
		var only_no_aa := false
		if kind.contains("#"):
			# "res://x.gdshaderinc#A,B": the no-AA foliage materials only, on that include with
			# the defines under the no-AA variant's render mode.
			only_no_aa = true
			target = Util.define_shader(kind, Util.FOLIAGE_NO_AA_MODE, _built_shaders)
		if target == null:
			for m: ShaderMaterial in _foliage_shaders:
				m.shader = _foliage_shaders[m]
			_foliage_shaders.clear()
			return
		for m in WindFoliage.collect_foliage_shader_materials(gm.map_container):
			var orig: Shader = _foliage_shaders.get(m, m.shader)
			var file := orig.resource_path.get_file() if orig != null else ""
			if only_no_aa and file != "wind_foliage_no_aa.gdshader":
				continue
			if not _foliage_shaders.has(m):
				_foliage_shaders[m] = m.shader
			m.shader = target

	## `which`: "" puts the ground's own materials back; "all" a flat lit material over every
	## ground class, "skirt" over the skirt's alone, "map" over the map's chunks alone (clipmap4).
	func _set_ground_flat(which: String) -> void:
		for key: Variant in _ground_overrides:
			if is_instance_valid(key):
				(key as GeometryInstance3D).material_override = _ground_overrides[key]
		_ground_overrides.clear()
		if which == "":
			return
		if _flat_ground == null:
			_flat_ground = StandardMaterial3D.new()
			_flat_ground.albedo_color = Color(0.36, 0.45, 0.22)
			_flat_ground.roughness = 1.0
		for node in gm.world_viewport.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			var cls := _cls(gi)
			var skirt := cls.begins_with("authored_ground_skirt")
			var wanted := which == "all" or (skirt if which == "skirt" else not skirt)
			# The ground clipmap's strip copies (bake shader, own world) are not the drawn ground.
			wanted = wanted and not cls.contains("authored_ground_bake")
			if cls.contains("authored_ground") and wanted and not _ground_overrides.has(gi):
				_ground_overrides[gi] = gi.material_override
				gi.material_override = _flat_ground

	# ---- explore ----

	func _explore() -> void:
		var vp := gm.world_viewport
		_log(
			(
				"renderer: %s, %s %s, api %s; method %s, driver %s; window %s, world viewport %s"
				% [
					RenderingServer.get_video_adapter_name(),
					RenderingServer.get_video_adapter_vendor(),
					RenderingServer.get_video_adapter_type(),
					RenderingServer.get_video_adapter_api_version(),
					RenderingServer.get_current_rendering_method(),
					RenderingServer.get_current_rendering_driver_name(),
					str(DisplayServer.window_get_size()), str(vp.size)
				]
			)
		)
		var settings: Array[String] = []
		for key in [
			"rendering/driver/depth_prepass/enable",
			"rendering/anti_aliasing/quality/msaa_3d",
			"rendering/anti_aliasing/quality/screen_space_aa",
			"rendering/anti_aliasing/quality/use_taa",
			"rendering/scaling_3d/mode",
			"rendering/scaling_3d/scale",
			"rendering/textures/default_filters/anisotropic_filtering_level",
			"rendering/textures/vram_compression/import_s3tc_bptc",
			"rendering/lights_and_shadows/directional_shadow/size",
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
			"rendering/lights_and_shadows/directional_shadow/16_bits",
			"rendering/environment/ssao/quality",
			"rendering/environment/ssao/half_size",
			"rendering/environment/glow/upscale_mode",
			"rendering/occlusion_culling/use_occlusion_culling",
			"rendering/mesh_lod/lod_change/threshold_pixels",
			"rendering/limits/cluster_builder/max_clustered_elements",
		]:
			settings.append("%s=%s" % [key.get_file(), str(ProjectSettings.get_setting(key))])
		_log("settings: " + ", ".join(settings))
		_log(
			(
				"viewport: msaa %d fxaa %d taa %s scale %.2f mode %d aniso %d debanding %s lod %.1f"
				% [
					vp.msaa_3d, vp.screen_space_aa, vp.use_taa, vp.scaling_3d_scale,
					vp.scaling_3d_mode, vp.anisotropic_filtering_level, vp.use_debanding,
					vp.mesh_lod_threshold
				]
			)
		)
		var env := _env()
		if env != null:
			_log(
				(
					(
						"environment: bg %d sky %s tonemap %d ssao %s (r %.2f int %.2f) ssil %s ssr %s"
						+ " sdfgi %s glow %s (blend %d) fog %s vol_fog %s adjust %s"
					)
					% [
						env.background_mode, env.sky != null, env.tonemap_mode, env.ssao_enabled,
						env.ssao_radius, env.ssao_intensity, env.ssil_enabled, env.ssr_enabled,
						env.sdfgi_enabled, env.glow_enabled, env.glow_blend_mode, env.fog_enabled,
						env.volumetric_fog_enabled, env.adjustment_enabled
					]
				)
			)
		for s in _suns():
			_log(
				(
					"sun %s: shadow %s mode %d splits %.2f %.2f %.2f maxd %.1f blur %.2f bias %.3f"
					% [
						s.name, s.shadow_enabled, s.directional_shadow_mode,
						s.directional_shadow_split_1, s.directional_shadow_split_2,
						s.directional_shadow_split_3, s.directional_shadow_max_distance,
						s.shadow_blur, s.shadow_bias
					]
				)
			)
		var lights := get_tree().root.find_children("*", "Light3D", true, false)
		_log("lights: %d Light3D in the tree" % lights.size())
		_log(
			(
				"vram MB: textures %.1f buffers %.1f video %.1f"
				% [
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
					/ 1048576.0,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)
					/ 1048576.0,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
					/ 1048576.0
				]
			)
		)
		_explore_classes()

	func _explore_classes() -> void:
		var classes := {}
		var species := {}
		var textures := {}
		for node in gm.world_viewport.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var key := class_of(gi)
			if not classes.has(key):
				classes[key] = {"nodes": 0, "inst": 0, "tris": 0, "cast": 0, "names": []}
			var c: Dictionary = classes[key]
			c.nodes += 1
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				c.cast += 1
			if c.names.size() < 3:
				c.names.append(String(gi.name))
			var mesh: Mesh = null
			var inst := 1
			if gi is MultiMeshInstance3D:
				var mm := (gi as MultiMeshInstance3D).multimesh
				if mm != null:
					mesh = mm.mesh
					inst = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			elif gi is MeshInstance3D:
				mesh = (gi as MeshInstance3D).mesh
			var tris := triangles(mesh) if mesh != null else 0
			c.inst += inst
			c.tris += tris * inst
			if gi is MultiMeshInstance3D and mesh != null:
				var sp := mesh.resource_name if not mesh.resource_name.is_empty() else String(gi.name)
				if not species.has(sp):
					species[sp] = {"nodes": 0, "inst": 0, "tris": 0, "mesh_tris": tris, "class": key}
				species[sp].nodes += 1
				species[sp].inst += inst
				species[sp].tris += tris * inst
			_collect_textures(gi, mesh, key, textures)
		var keys := classes.keys()
		keys.sort_custom(func(a, b): return classes[a].tris > classes[b].tris)
		_log("classes (%d), by triangles:" % keys.size())
		for k in keys:
			var c: Dictionary = classes[k]
			_log(
				(
					"  %-48s nodes %5d inst %8d tris %9d casters %5d e.g. %s"
					% [k, c.nodes, c.inst, c.tris, c.cast, ", ".join(c.names)]
				)
			)
		var sp_keys := species.keys()
		sp_keys.sort_custom(func(a, b): return species[a].tris > species[b].tris)
		_log("multimesh species (%d), top 30 by triangles:" % sp_keys.size())
		for i in mini(30, sp_keys.size()):
			var s: Dictionary = species[sp_keys[i]]
			_log(
				(
					"  %-40s nodes %4d inst %7d mesh tris %6d tris %9d (%s)"
					% [sp_keys[i], s.nodes, s.inst, s.mesh_tris, s.tris, s.class]
				)
			)
		var total := 0
		var tex_lines: Array = []
		for rid in textures:
			var t: Dictionary = textures[rid]
			total += int(t.bytes)
			tex_lines.append(t)
		tex_lines.sort_custom(func(a, b): return a.bytes > b.bytes)
		_log("textures bound by the classes: %d, %.1f MB" % [tex_lines.size(), total / 1048576.0])
		for t: Dictionary in tex_lines:
			_log(
				(
					"  %7.2f MB %5dx%-5d x%-3d mips %-5s fmt %-3d %-24s %s (%s)"
					% [
						t.bytes / 1048576.0, t.w, t.h, t.layers, t.mips, t.fmt, t.param, t.path,
						t.class
					]
				)
			)

	func _collect_textures(gi: GeometryInstance3D, mesh: Mesh, key: String, out: Dictionary) -> void:
		var mats: Array[Material] = []
		if gi.material_override != null:
			mats.append(gi.material_override)
		if mesh != null:
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m != null and not mats.has(m):
					mats.append(m)
		for m in mats:
			var params: Array = []
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
					params.append([String(u.name), (m as ShaderMaterial).get_shader_parameter(u.name)])
			elif m is BaseMaterial3D:
				for p in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture"]:
					params.append([p, m.get(p)])
			for pv in params:
				if not (pv[1] is Texture):
					continue
				var tex := pv[1] as Texture
				if out.has(tex.get_rid()):
					continue
				out[tex.get_rid()] = _texture_info(tex, String(pv[0]), key)

	func _texture_info(tex: Texture, param: String, key: String) -> Dictionary:
		var info := {
			"w": 0, "h": 0, "layers": 1, "mips": false, "fmt": -1, "bytes": 0, "param": param,
			"path": tex.resource_path.get_file(), "class": key
		}
		var img: Image = null
		if tex is TextureLayered:
			var tl := tex as TextureLayered
			info.layers = tl.get_layers()
			info.w = tl.get_width()
			info.h = tl.get_height()
			info.mips = tl.has_mipmaps()
			info.fmt = tl.get_format()
			img = tl.get_layer_data(0)
		elif tex is Texture2D:
			var t2 := tex as Texture2D
			info.w = t2.get_width()
			info.h = t2.get_height()
			img = t2.get_image()
		if img != null:
			info.mips = img.has_mipmaps()
			info.fmt = img.get_format()
			info.bytes = img.get_data().size() * int(info.layers)
		return info

	# ---- perf ----

	func _perf() -> void:
		var vp := gm.world_viewport
		var rid := vp.get_viewport_rid()
		var root_rid := get_tree().root.get_viewport_rid()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var max_fps := Engine.max_fps
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(rid, true)
		RenderingServer.viewport_set_measure_render_time(root_rid, true)
		var base: Dictionary = step.get("base", {})
		var variants: Array = step.get("variants", [])
		_log(
			(
				"perf %s: world viewport %s, window %s, view %s zoom %.2f, base %s, %d variants"
				% [
					step.get("name", ""), str(vp.size), str(DisplayServer.window_get_size()),
					String(gm.get_camera_controller().view_mode().mode_name()),
					gm.camera_node.size, JSON.stringify(base), variants.size()
				]
			)
		)
		var keys: Array[String] = ["base_start"]
		for v: Dictionary in variants:
			keys.append(String(v.name))
		keys.append("base_end")
		var data := {}
		for key in keys:
			data[key] = {"gpu": [], "root": [], "cpu": [], "wall": [], "pass": {}, "info": ""}
		var rounds := int(step.get("rounds", 6))
		var warm := int(step.get("warm", 1))
		var drift: Array[String] = []
		var scale_samples: Array = []
		for r in rounds:
			await _measure(base, "base_start", r >= warm, data, scale_samples)
			var order := variants.duplicate()
			for i in r % maxi(order.size(), 1):
				order.push_back(order.pop_front())
			if r % 2 == 1:
				order.reverse()
			for v: Dictionary in order:
				var cfg := base.duplicate()
				cfg.merge(v, true)
				await _measure(cfg, String(v.name), r >= warm, data, scale_samples)
			await _measure(base, "base_end", r >= warm, data, scale_samples)
			if r >= warm:
				drift.append("%.3f" % (data.base_end.gpu[-1] / maxf(data.base_start.gpu[-1], 0.001)))
		_apply({})
		Engine.max_fps = max_fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		var raw_to_ms := _median(scale_samples)
		_report(keys, data, raw_to_ms, drift)

	func _report(
		keys: Array[String], data: Dictionary, raw_to_ms: float, drift: Array[String]
	) -> void:
		var table: Array[String] = []
		var base_gpu := _median(data.base_start.gpu + data.base_end.gpu)
		var head := "perf %s, %s; timestamps raw to ms x1e6 %.4f"
		table.append(head % [step.get("name", ""), _gpu_state(), raw_to_ms * 1e6])
		for key in keys:
			var d: Dictionary = data[key]
			var g := _median(d.gpu)
			table.append(
				(
					"%-16s gpu %6.3f [%.3f-%.3f] %+7.3f | root %.3f cpu %.3f wall %.3f (%d) | %s"
					% [
						key, g, _min(d.gpu), _max(d.gpu), g - base_gpu, _median(d.root),
						_median(d.cpu), _median(d.wall), d.gpu.size(), d.info
					]
				)
			)
			var passes: Array[String] = []
			var names: Array = d.pass.keys()
			names.sort_custom(func(x, y): return _median(d.pass[x]) > _median(d.pass[y]))
			for n in names:
				var ms: float = _median(d.pass[n]) * raw_to_ms
				if ms >= 0.02:
					passes.append(
						(
							"%s %.3f [%.3f-%.3f]"
							% [n, ms, _min(d.pass[n]) * raw_to_ms, _max(d.pass[n]) * raw_to_ms]
						)
					)
			if not passes.is_empty():
				table.append("    passes: " + "; ".join(passes))
		table.append("drift base_end/base_start per round %s" % " ".join(drift))
		for l in table:
			_log(l)
		var f := FileAccess.open(
			_dir.path_join("%s_table.txt" % String(step.get("name", "perf"))), FileAccess.WRITE
		)
		if f != null:
			for l in table:
				f.store_line(l)

	func _gpu_state() -> String:
		return "%s, %s, world %s" % [
			RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method(),
			str(gm.world_viewport.size)
		]

	## Settle, then `frames` frames: the world and root viewports' GPU time, the world's CPU render
	## time, wall time, and the engine pass timestamps between the world viewport's begin and end.
	func _measure(
		cfg: Dictionary, key: String, keep: bool, data: Dictionary, scale_samples: Array
	) -> void:
		_apply(cfg)
		await _frames(int(step.get("settle", 20)))
		var rid := gm.world_viewport.get_viewport_rid()
		var root_rid := get_tree().root.get_viewport_rid()
		var rd := RenderingServer.get_rendering_device()
		var begin_name := "vp_begin_%d" % rid.get_id()
		var end_name := "vp_end_%d" % rid.get_id()
		var gpu: Array = []
		var root: Array = []
		var cpu: Array = []
		var wall: Array = []
		var passes := {}
		var last := Time.get_ticks_usec()
		for n in int(step.get("frames", 60)):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			wall.append(float(now - last) / 1000.0)
			last = now
			var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
			gpu.append(g)
			root.append(RenderingServer.viewport_get_measured_render_time_gpu(root_rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			if rd == null:
				continue
			var count := rd.get_captured_timestamps_count()
			var sums := {}
			var t_begin := -1
			var t_end := -1
			var inside := false
			for i in count:
				var nm := rd.get_captured_timestamp_name(i)
				var t := rd.get_captured_timestamp_gpu_time(i)
				if nm == begin_name:
					t_begin = t
					inside = true
				elif nm == end_name:
					t_end = t
					inside = false
				elif i + 1 < count:
					var label := nm if inside else "~" + nm
					sums[label] = (
						float(sums.get(label, 0.0))
						+ float(rd.get_captured_timestamp_gpu_time(i + 1) - t)
					)
			for nm in sums:
				if not passes.has(nm):
					passes[nm] = []
				passes[nm].append(sums[nm])
			if t_begin >= 0 and t_end > t_begin and g > 0.0:
				scale_samples.append(g / float(t_end - t_begin))
		var d: Dictionary = data[key]
		d.info = _info(rid)
		if not keep:
			return
		d.gpu.append(_median(gpu))
		d.root.append(_median(root))
		d.cpu.append(_median(cpu))
		d.wall.append(_median(wall))
		for nm in passes:
			if not d.pass.has(nm):
				d.pass[nm] = []
			d.pass[nm].append(_median(passes[nm]))

	func _info(rid: RID) -> String:
		var parts: Array[String] = []
		for t in [
			[RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, "vis"],
			[RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, "shadow"]
		]:
			parts.append(
				(
					"%s %d/%d/%d"
					% [
						t[1],
						RenderingServer.viewport_get_render_info(
							rid, t[0], RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
						),
						RenderingServer.viewport_get_render_info(
							rid, t[0], RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
						),
						RenderingServer.viewport_get_render_info(
							rid, t[0], RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
						)
					]
				)
			)
		return " ".join(parts)

	# ---- shots ----

	## {action: "shots", name, sets: [{name, ..knobs}]}: the world viewport at its native size
	## under each set's knobs, saved as <name>_<set>.png, so a timing can be checked against what
	## was drawn (and a look change judged).
	## A set with `diff: "<earlier set>"` is also compared with that set's image: per-channel
	## 8-bit levels, the max, the mean, the share of channels off by more than 1, 2, 4 and 8
	## levels, and <name>_<set>_diff.png (the difference times 16) when anything differs.
	func _shots() -> void:
		var taken := {}
		for s: Dictionary in step.get("sets", []):
			_apply(s)
			await _frames(int(s.get("settle", 20)))
			await RenderingServer.frame_post_draw
			var img := gm.world_viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var path := _dir.path_join("%s_%s.png" % [step.get("name", "shot"), s.name])
			if bool(s.get("half", false)):
				# A half-size copy for a before/after pair; the diff stays at full size.
				var small := img.duplicate() as Image
				small.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
				small.save_png(path)
			else:
				img.save_png(path)
			taken[String(s.name)] = img
			_log("shot %s: %s %s" % [s.name, str(img.get_size()), path])
			if s.has("diff") and taken.has(String(s.diff)):
				var diff_path := _dir.path_join("%s_%s_diff.png" % [step.get("name", "shot"), s.name])
				var label := "%s vs %s" % [s.name, s.diff]
				_log(Util.diff_line(label, taken[String(s.diff)], img, diff_path))

	# ---- overdraw ----

	func _overdraw() -> void:
		var env := _env()
		var saved := {}
		if env != null:
			saved = {
				"tm": env.tonemap_mode, "exp": env.tonemap_exposure, "adj": env.adjustment_enabled
			}
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.tonemap_exposure = 1.0
			env.adjustment_enabled = false
		var unit := 0.0
		for s: Dictionary in step.get("sets", []):
			_apply({"debug": Viewport.DEBUG_DRAW_OVERDRAW, "glow": false, "hide": s.get("hide", [])})
			await _frames(12)
			await RenderingServer.frame_post_draw
			var img := gm.world_viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.save_png(_dir.path_join("%s_%s.png" % [step.get("name", "overdraw"), s.name]))
			var vals := _linear_red(img)
			if bool(s.get("calib", false)):
				var lit := vals.filter(func(x): return x > 0.002)
				unit = _median(lit)
				_log("overdraw %s: one layer = linear red %.4f (%d samples)" % [s.name, unit, lit.size()])
			if unit <= 0.0:
				continue
			_log(_overdraw_line(String(s.name), vals, unit))
		if env != null:
			env.tonemap_mode = saved.tm
			env.tonemap_exposure = saved.exp
			env.adjustment_enabled = saved.adj

	func _linear_red(img: Image) -> Array:
		var vals: Array = []
		var stride := 3
		for y in range(0, img.get_height(), stride):
			for x in range(0, img.get_width(), stride):
				vals.append(img.get_pixel(x, y).srgb_to_linear().r)
		return vals

	func _overdraw_line(set_name: String, vals: Array, unit: float) -> String:
		var layers := vals.map(func(x): return x / unit)
		layers.sort()
		var n := layers.size()
		var total := 0.0
		var over := [0, 0, 0]
		var sat := 0
		for l: float in layers:
			total += l
			over[0] += 1 if l > 4.0 else 0
			over[1] += 1 if l > 8.0 else 0
			over[2] += 1 if l > 16.0 else 0
		for v: float in vals:
			sat += 1 if v >= 0.995 else 0
		return (
			(
				"overdraw %s: layers per pixel mean %.2f p50 %.2f p90 %.2f p99 %.2f;"
				+ " over 4 %.1f %%, 8 %.1f %%, 16 %.1f %%; saturated %.1f %%"
			)
			% [
				set_name, total / maxf(n, 1), layers[n / 2], layers[int(n * 0.9)],
				layers[int(n * 0.99)], 100.0 * over[0] / n, 100.0 * over[1] / n,
				100.0 * over[2] / n, 100.0 * sat / n
			]
		)
