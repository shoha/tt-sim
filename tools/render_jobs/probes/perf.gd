extends RefCounted

## Render-job probe (`call` op) for performance passes. step.action picks what it does:
##   start {name}          begin sampling every frame: CPU frame time (wall clock between
##                         frames) and world-viewport GPU time (run vsync_off first)
##   stop                  end sampling; log n / median / p95 / worst / mean per series
##   info {name}           world-viewport render info (visible and shadow objects, primitives,
##                         draw calls), scatter MultiMesh counts, viewport and camera size
##   mem {ws}              engine memory monitors; ws = true adds the process working set,
##                         peak working set and private bytes (one powershell call, ~0.5 s)
##   gpu_state {name}      one nvidia-smi query: GPU utilisation, temperature, P-state, clock
##                         (the pinned procedure's idle check, logged in the run; P4b-3)
##   play {folder}         play a level and time its load (logged when it lands)
##   author {biome, size, seed, landform}  open a new map in authoring (landform: a
##                         StartingLandform.KINDS id, default flat) and time the loading
##                         screen, the whole palette resolve and the starting-cover regeneration
##   recipe {biome, size, seed, landform, runs}  time NewMap.create with the landform against
##                         Flat on the main thread, `runs` each (P5-5: the recipe's own cost)
##   dress {folder}        open an existing level in authoring, timed like author
##   scatter {visible}     show or hide every scatter MultiMesh under the map
##   ground_std {on}       draw every terrain chunk with a StandardMaterial3D made from the
##                         ground material's own textures (on), or the ground shader (off)
##   broad {on}            ground shader with (on) or without (off) the broad edge call
##   layers {mode}         biome ground state: "0" (layer count forced 0), "1" (whole map one
##                         forest layer), "4" (four surfaces in quadrants), "mix" (four
##                         surfaces in 1 m checker at half density)
##   skirt {visible}       terrain skirt visibility

const SAMPLER := "PerfSampler"
const WATCH := "PerfWatch"
const FOREST := "temperate_forest_summer_s1"
const LAYER_BIOMES := [
	"temperate_forest_summer_s1",
	"boreal_taiga_summer_s1",
	"rocky_badlands_summer_s1",
	"alpine_meadow_summer_s1",
]

static var _std_material: StandardMaterial3D = null
static var _ground_shader: Shader = null
static var _no_broad_shader: Shader = null


class Sampler:
	extends Node
	var cpu := PackedFloat64Array()
	var gpu := PackedFloat64Array()
	var rid: RID
	var last_us := 0
	var skip := 3

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -99
		last_us = Time.get_ticks_usec()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - last_us) / 1000.0
		last_us = now
		if skip > 0:
			skip -= 1
			return
		cpu.append(ms)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))


class Watch:
	extends Node
	var mode := ""
	var label := ""
	var base: Node = null
	var start_us := 0
	var last_us := 0
	var phase := 0
	var phase_start_us := 0
	var frames := PackedFloat64Array()
	var resolved_us := 0
	var regen_us := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -98
		last_us = Time.get_ticks_usec()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		frames.append((now - last_us) / 1000.0)
		last_us = now
		if mode == "play":
			var gm: Node = base.get("_game_map")
			var lpc: Node = base.get("_level_play_controller")
			if gm == null or not is_instance_valid(gm) or lpc == null:
				return
			if gm.call("_is_level_loading"):
				return
			var map: Variant = lpc.get("loaded_map_instance")
			if map == null or not is_instance_valid(map):
				return
			_log(
				(
					"load %s: %.0f ms, %s"
					% [label, (now - start_us) / 1000.0, Probe.stats_text(frames, "frames")]
				)
			)
			queue_free()
			return
		# Authoring: phase 0 until the loading screen drops, 1 until every prepared species
		# resolved and regeneration and growth are done.
		var c: Node = base.get("_authoring_controller")
		if c == null or not is_instance_valid(c):
			return
		if phase == 0:
			if not c.get("_is_open"):
				return
			_log(
				(
					"open %s: loading screen %.0f ms, %s, %s"
					% [
						label,
						(now - start_us) / 1000.0,
						Probe.stats_text(frames, "frames"),
						Probe.mem_text(false)
					]
				)
			)
			phase = 1
			phase_start_us = now
			frames = PackedFloat64Array()
			return
		var scatter: Node = c.get("scatter")
		if scatter == null or not is_instance_valid(scatter):
			return
		if resolved_us == 0 and not scatter.call("has_prepared_species"):
			resolved_us = now
		if regen_us == 0 and not scatter.call("is_regenerating") and not scatter.call("is_growing"):
			regen_us = now
		if resolved_us == 0 or regen_us == 0:
			return
		_log(
			(
				"after open %s: palette resolved +%.0f ms (%d species), regen+grow done +%.0f ms, %s, %s"
				% [
					label,
					(resolved_us - phase_start_us) / 1000.0,
					scatter.call("resolved_species_count"),
					(regen_us - phase_start_us) / 1000.0,
					Probe.stats_text(frames, "frames"),
					Probe.mem_text(false)
				]
			)
		)
		queue_free()

	func _log(s: String) -> void:
		for node in get_tree().root.get_children():
			if node.has_method("log_line"):
				node.call("log_line", s)
				return
		print("RJ| " + s)


## Alias so the inner classes can reach the static helpers.
class Probe:
	static func stats(values: PackedFloat64Array) -> Dictionary:
		var s := values.duplicate()
		s.sort()
		var n := s.size()
		if n == 0:
			return {"n": 0, "median": 0.0, "p95": 0.0, "worst": 0.0, "mean": 0.0}
		var total := 0.0
		for v in s:
			total += v
		return {
			"n": n,
			"median": s[n / 2],
			"p95": s[clampi(ceili(0.95 * n) - 1, 0, n - 1)],
			"worst": s[n - 1],
			"mean": total / n,
		}

	static func stats_text(values: PackedFloat64Array, name: String) -> String:
		var d := stats(values)
		return (
			"%s n %d median %.3f p95 %.3f worst %.3f mean %.3f"
			% [name, d.n, d.median, d.p95, d.worst, d.mean]
		)

	static func mem_text(ws: bool) -> String:
		var out := (
			"static %.1f MB (peak %.1f), video %.1f MB (tex %.1f, buf %.1f), objects %d, nodes %d"
			% [
				OS.get_static_memory_usage() / 1048576.0,
				OS.get_static_memory_peak_usage() / 1048576.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			]
		)
		if ws:
			var pid := OS.get_process_id()
			var cmd := (
				(
					"$p = Get-Process -Id %d; '{0} {1} {2}' -f $p.WorkingSet64, "
					+ "$p.PeakWorkingSet64, $p.PrivateMemorySize64"
				)
				% pid
			)
			var res: Array = []
			OS.execute("powershell", ["-NoProfile", "-Command", cmd], res, true)
			var parts := String(res[0] if not res.is_empty() else "").strip_edges().split(" ")
			if parts.size() == 3:
				out += (
					", working set %.0f MB (peak %.0f), private %.0f MB"
					% [
						float(parts[0]) / 1048576.0,
						float(parts[1]) / 1048576.0,
						float(parts[2]) / 1048576.0
					]
				)
			else:
				out += ", working set unavailable (%s)" % str(res)
		return out


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	match String(step.get("action", "")):
		"start":
			_remove(base, SAMPLER)
			var sampler := Sampler.new()
			sampler.name = SAMPLER
			sampler.rid = gm.world_viewport.get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(sampler.rid, true)
			sampler.set_meta("label", String(step.get("name", "")))
			base.get_tree().root.add_child(sampler)
			return "sampling %s" % step.get("name", "")
		"stop":
			var sampler := base.get_tree().root.get_node_or_null(SAMPLER) as Sampler
			if sampler == null:
				return "no sampler"
			var label := String(sampler.get_meta("label", ""))
			var text := (
				"perf %s | %s | %s"
				% [
					label,
					Probe.stats_text(sampler.cpu, "cpu"),
					Probe.stats_text(sampler.gpu, "gpu")
				]
			)
			sampler.queue_free()
			return text
		"info":
			return "info %s | %s | %s" % [step.get("name", ""), _render_info(gm), _scatter_info(gm)]
		"mem":
			return (
				"mem %s | %s" % [step.get("name", ""), Probe.mem_text(bool(step.get("ws", false)))]
			)
		"gpu_state":
			# The pinned procedure's idle check (PERFORMANCE.md), from inside the run: one
			# nvidia-smi query (utilisation, temperature, P-state, graphics clock).
			var res: Array = []
			var query := "--query-gpu=utilization.gpu,temperature.gpu,pstate,clocks.gr"
			var code := OS.execute("nvidia-smi", [query, "--format=csv,noheader"], res, true)
			return (
				"gpu_state %s | %s (exit %d)"
				% [
					step.get("name", ""),
					String(res[0] if not res.is_empty() else "").strip_edges(),
					code
				]
			)
		"play":
			var level := LevelManager.load_level_folder(String(step.folder), false)
			_watch(base, "play", String(step.folder))
			base.call("_on_play_level_requested", level)
			return "playing %s" % step.folder
		"author":
			var landform := String(step.get("landform", StartingLandform.FLAT))
			var label := (
				"new %s %s %d ft" % [step.get("biome", ""), landform, int(step.get("size", 200))]
			)
			_watch(base, "author", label)
			(
				base
				. call(
					"_begin_authoring",
					{
						"level": null,
						"new_map":
						{
							"size_ft": int(step.get("size", 200)),
							"biome_id": String(step.get("biome", "")),
							"seed": int(step.get("seed", 1234)),
							"landform": landform,
						},
						"return_to": &"title"
					}
				)
			)
			return "authoring %s" % label
		"recipe":
			return _recipe(step)
		"dress":
			var dressed := LevelManager.load_level_folder(String(step.folder), false)
			_watch(base, "author", String(step.folder))
			base.call("_begin_authoring", {"level": dressed, "return_to": &"title"})
			return "authoring %s" % step.folder
		"scatter":
			var n := 0
			for node in _multimeshes(gm):
				node.visible = bool(step.get("visible", true))
				n += 1
			return "scatter visible %s on %d nodes" % [str(step.get("visible", true)), n]
		"ground_std":
			return _ground_std(gm, bool(step.get("on", true)))
		"broad":
			return _broad(gm, bool(step.get("on", true)))
		"layers":
			return _layers(base, String(step.get("mode", "0")))
		"skirt":
			var n := 0
			for terrain in _terrains(gm):
				var skirt: MeshInstance3D = terrain.get_skirt()
				if skirt:
					skirt.visible = bool(step.get("visible", true))
					n += 1
			return "skirt visible %s on %d" % [str(step.get("visible", true)), n]
	return "unknown action %s" % step.get("action", "")


## The new map's document built on the main thread as AuthoringController's open builds it
## (NewMap.create with the landform), against the same with Flat, `runs` times each
## interleaved; logs the median and range of each and the median difference (the recipe's
## own cost). Run from the title, between opens, so it never lands in a timed frame.
static func _recipe(step: Dictionary) -> String:
	var size := int(step.get("size", 150))
	var biome := String(step.get("biome", FOREST))
	var seed_value := int(step.get("seed", 1234))
	var landform := String(step.get("landform", StartingLandform.VALLEY))
	var shaped := PackedFloat64Array()
	var flat := PackedFloat64Array()
	for i in int(step.get("runs", 3)):
		var t0 := Time.get_ticks_usec()
		NewMap.create(size, biome, seed_value, PaletteLibrary.DEFAULT_ROOT, landform)
		var t1 := Time.get_ticks_usec()
		NewMap.create(size, biome, seed_value, PaletteLibrary.DEFAULT_ROOT, StartingLandform.FLAT)
		var t2 := Time.get_ticks_usec()
		shaped.append((t1 - t0) / 1000.0)
		flat.append((t2 - t1) / 1000.0)
	var s := Probe.stats(shaped)
	var f := Probe.stats(flat)
	return (
		"recipe %s %d ft seed %d: create %.1f ms (%.1f-%.1f), flat %.1f ms (%.1f-%.1f), recipe %.1f ms"
		% [
			landform,
			size,
			seed_value,
			s.median,
			_min(shaped),
			s.worst,
			f.median,
			_min(flat),
			f.worst,
			s.median - f.median
		]
	)


static func _min(values: PackedFloat64Array) -> float:
	var out := INF
	for v in values:
		out = minf(out, v)
	return out


static func _remove(base: Node, name: String) -> void:
	var old := base.get_tree().root.get_node_or_null(name)
	if old:
		old.name = name + "_old"
		old.queue_free()


static func _watch(base: Node, mode: String, label: String) -> void:
	_remove(base, WATCH)
	var watch := Watch.new()
	watch.name = WATCH
	watch.mode = mode
	watch.label = label
	watch.base = base
	watch.start_us = Time.get_ticks_usec()
	base.get_tree().root.add_child(watch)


static func _render_info(gm: GameMap) -> String:
	var rid := gm.world_viewport.get_viewport_rid()
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var sha := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	return (
		"viewport %s zoom %.2f | visible obj %d prims %d draws %d | shadow prims %d draws %d"
		% [
			str(gm.world_viewport.size),
			gm.camera_node.size,
			RenderingServer.viewport_get_render_info(
				rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
			),
			RenderingServer.viewport_get_render_info(
				rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
			),
			RenderingServer.viewport_get_render_info(
				rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
			),
			RenderingServer.viewport_get_render_info(
				rid, sha, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
			),
			RenderingServer.viewport_get_render_info(
				rid, sha, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
			),
		]
	)


static func _multimeshes(gm: GameMap) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for node in gm.map_container.find_children("*", "MultiMeshInstance3D", true, false):
		if String(node.name).contains("PipelineWarm"):
			continue
		out.append(node as MultiMeshInstance3D)
	return out


static func _scatter_info(gm: GameMap) -> String:
	var nodes := 0
	var total := 0
	var shown := 0
	var prims := 0
	var meshes := {}
	for node in _multimeshes(gm):
		var mm := node.multimesh
		if mm == null or mm.mesh == null:
			continue
		nodes += 1
		var visible := (
			mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		)
		total += mm.instance_count
		shown += visible
		meshes[mm.mesh] = true
		prims += visible * _triangles(mm.mesh)
	return (
		"scatter nodes %d meshes %d instances %d visible %d visible-instance prims %d"
		% [nodes, meshes.size(), total, shown, prims]
	)


static func _triangles(mesh: Mesh) -> int:
	var tris := 0
	var array_mesh := mesh as ArrayMesh
	for s in mesh.get_surface_count():
		if array_mesh:
			var idx := array_mesh.surface_get_array_index_len(s)
			tris += (idx if idx > 0 else array_mesh.surface_get_array_len(s)) / 3
		else:
			var arrays := mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += indices.size() / 3
	return tris


static func _terrains(gm: GameMap) -> Array:
	var out: Array = []
	for node in gm.map_container.find_children("*", "Node3D", true, false):
		if node is AuthoredTerrain:
			out.append(node)
	return out


static func _ground_std(gm: GameMap, on: bool) -> String:
	var n := 0
	for terrain: AuthoredTerrain in _terrains(gm):
		var mat := terrain.get_material()
		if on and _std_material == null:
			_std_material = StandardMaterial3D.new()
			_std_material.albedo_texture = mat.get_shader_parameter("albedo_tex")
			_std_material.normal_enabled = true
			_std_material.normal_texture = mat.get_shader_parameter("normal_tex")
			var orm: Texture2D = mat.get_shader_parameter("orm_tex")
			_std_material.ao_enabled = true
			_std_material.ao_texture = orm
			_std_material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			_std_material.roughness_texture = orm
			_std_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			_std_material.metallic = 1.0
			_std_material.metallic_texture = orm
			_std_material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			var tile := float(mat.get_shader_parameter("tile_m"))
			_std_material.uv1_scale = Vector3.ONE / maxf(tile, 0.01)
			_std_material.texture_filter = (
				BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			)
		for cell in terrain.chunk_cells():
			terrain.get_chunk(cell).material_override = _std_material if on else null
			n += 1
	return "ground_std %s on %d chunks" % [str(on), n]


static func _broad(gm: GameMap, on: bool) -> String:
	var n := 0
	for terrain: AuthoredTerrain in _terrains(gm):
		var mat := terrain.get_material()
		if _ground_shader == null:
			_ground_shader = mat.shader
			var wrapper := FileAccess.get_file_as_string("res://shaders/authored_ground.gdshader")
			var inc := FileAccess.get_file_as_string("res://shaders/authored_ground.gdshaderinc")
			var call := "ground.albedo = apply_broad_edge(ground.albedo, world_xz, ground_a, ground_b);"
			if not inc.contains(call):
				return "broad: call not found in the include"
			inc = inc.replace(call, "")
			_no_broad_shader = Shader.new()
			_no_broad_shader.code = wrapper.replace(
				'#include "res://shaders/authored_ground.gdshaderinc"', inc
			)
		mat.shader = _ground_shader if on else _no_broad_shader
		n += 1
	return "broad %s on %d" % [str(on), n]


static func _layers(base: Node, mode: String) -> String:
	var c: AuthoringController = base.get("_authoring_controller")
	var doc := c.document
	var terrain: AuthoredTerrain = c.editor.terrain
	var mat := terrain.get_material()
	var count := doc.sample_count()
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(count)
	density.resize(count)
	# The biome list only grows, so layer assignment stays forest, boreal, badlands, alpine.
	var ids := doc.biome_ids
	for id in LAYER_BIOMES:
		if not ids.has(id) and (mode != "1" or id == FOREST):
			ids.append(id)
	doc.biome_ids = ids
	var forced := -1
	if mode == "0":
		forced = 0
	elif mode == "1":
		slots.fill(ids.find(FOREST) + 1)
		density.fill(255)
		forced = 1
	else:
		forced = 4
		for z in doc.samples_z():
			for x in doc.samples_x():
				var w := doc.sample_to_world(Vector2(x, z))
				var k := 0
				if mode == "4":
					k = (1 if w.x >= 0.0 else 0) + (2 if w.y >= 0.0 else 0)
				else:
					k = (floori(w.x) & 1) + 2 * (floori(w.y) & 1)
				var i := doc.sample_index(x, z)
				slots[i] = ids.find(LAYER_BIOMES[k]) + 1
				density[i] = 255 if mode == "4" else 128
	doc.biome_slots = slots
	doc.biome_density = density
	terrain.update_ground_region(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	if forced == 0:
		mat.set_shader_parameter("layer_ground_mask", 0)
	return (
		"layers %s: ground layers %s, layer_count %s"
		% [mode, str(terrain.ground_layers()), str(mat.get_shader_parameter("layer_count"))]
	)
