extends RefCounted

## Render-job probe (`call` op) for the phase 6 pinned performance pass (P6-2, rivers past the
## map edge). Works on the open authored map, in play or authoring. step.action:
##   shader {mode, zip}      the skirt material's shader (the patch shares it): "opaque" (the
##                           game's, res://), "transparent" (the skirt before phase 6: the
##                           wrapper and ground include from `zip`, made with `git archive
##                           --format=zip --output=<zip> 7bde99a shaders/authored_ground.gdshaderinc
##                           shaders/authored_ground_skirt.gdshader`, the include inlined),
##                           "band" (the probe's band variant: the channel patch opaque, the
##                           rest of the ring transparent through a surface override).
##   backdrop {on}           SkirtBackdrop's per-frame sync on or off (set_process).
##   backdrop_bench {runs}   times SkirtBackdrop.sync() `runs` times on the skirt's node: steady
##                           (nothing changed, the per-frame path) and forced (the last state
##                           cleared, so every uniform is set); microseconds per call.
##   exits_build {runs}      times RiverExitMesh.skirt_parts on the open map's document (the
##                           load and refresh workers' skirt job, run here on the main thread)
##                           `runs` times; logs the median, the range, the same with the
##                           skirt's current exits lent to the cache (P6-3: a refresh whose edit
##                           touched no exit) and how many pieces that built, the exits and the
##                           vertex counts of the skirt, the patch and the ribbon.
##   apply_bench {runs}      times AuthoredTerrain.apply_river_exits (the main thread's part of a
##                           water refresh for the skirt) with the map's own parts, `runs` times.
##   water_timing            the last water refresh: build (worker), bake, swap (main thread,
##                           apply_river_exits included), the editor's main-thread parts and
##                           the terrain's last in-place skirt refresh.
##   cache_check             how many exit pieces a build on the main thread, lent the skirt's
##                           current exits (built on the refresh worker), builds again: 0 when
##                           the cache keys agree across threads.
##   mirror_bench {runs}     times the skirt's vertex mirror made from the document
##                           (TerrainMeshBuilder.skirt_vertex_mirror, the main thread's first
##                           in-place edge update after a rebuild before P6-3) against read off
##                           the built arrays (skirt_mirror_of, on the worker since P6-3).

const BACKDROP := "SkirtBackdrop"
const WRAPPER := "shaders/authored_ground_skirt.gdshader"
const INCLUDE := "shaders/authored_ground.gdshaderinc"
const INCLUDE_LINE := '#include "res://shaders/authored_ground.gdshaderinc"'

static var _game_shader: Shader = null
static var _old_shader: Shader = null


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"shader":
			return _shader(base, String(step.get("mode", "opaque")), String(step.get("zip", "")))
		"backdrop":
			return _backdrop(base, bool(step.get("on", true)))
		"backdrop_bench":
			return _backdrop_bench(base, int(step.get("runs", 2000)))
		"exits_build":
			return _exits_build(base, int(step.get("runs", 5)))
		"apply_bench":
			return _apply_bench(base, int(step.get("runs", 5)))
		"water_timing":
			return _water_timing(base)
		"mirror_bench":
			return _mirror_bench(base, int(step.get("runs", 5)))
		"cache_check":
			var terrain := _terrain(base)
			var old := terrain.river_exits()
			var now := RiverExitMesh.build(
				terrain.document,
				AuthoredTerrain.skirt_width_m(),
				AuthoredTerrain.SKIRT_FADE_M,
				AuthoredTerrain.SKIRT_WOBBLE,
				old
			)
			return (
				"cache check: %d of %d pieces built again from the skirt's exits"
				% [int(now.get("built", -1)), (now.get("pieces", {}) as Dictionary).size()]
			)
	return "unknown action %s" % step.get("action", "")


static func _terrain(base: Node) -> AuthoredTerrain:
	var found := base.get_tree().root.find_children(
		"AuthoredTerrain", "AuthoredTerrain", true, false
	)
	return found[0] as AuthoredTerrain if not found.is_empty() else null


static func _skirt_material(base: Node) -> ShaderMaterial:
	var terrain := _terrain(base)
	var skirt := terrain.get_skirt() if terrain != null else null
	return skirt.mesh.surface_get_material(0) as ShaderMaterial if skirt != null else null


static func _shader(base: Node, mode: String, zip_path: String) -> String:
	var material := _skirt_material(base)
	if material == null:
		return "no skirt"
	var skirt := _terrain(base).get_skirt()
	skirt.set_surface_override_material(0, null)
	if _game_shader == null:
		_game_shader = load("res://" + WRAPPER) as Shader
	material.shader = _game_shader
	if mode == "opaque":
		return "skirt shader: opaque (the game's)"
	if mode != "transparent" and mode != "band":
		return "unknown skirt shader mode %s" % mode
	if _old_shader == null:
		var zip := ZIPReader.new()
		if zip.open(zip_path) != OK:
			return "cannot open %s" % zip_path
		var wrapper := zip.read_file(WRAPPER).get_string_from_utf8()
		var include := zip.read_file(INCLUDE).get_string_from_utf8()
		zip.close()
		if not wrapper.contains(INCLUDE_LINE):
			return "include line not found in the old wrapper"
		_old_shader = Shader.new()
		_old_shader.code = wrapper.replace(INCLUDE_LINE, include)
	if mode == "band":
		# The patch keeps the opaque material; the rest of the ring draws transparent.
		var ring := material.duplicate() as ShaderMaterial
		ring.shader = _old_shader
		skirt.set_surface_override_material(0, ring)
		return "skirt shader: band (patch opaque, ring transparent)"
	material.shader = _old_shader
	return "skirt shader: transparent (%d chars)" % _old_shader.code.length()


static func _backdrops(base: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node in base.get_tree().root.find_children(BACKDROP, "", true, false):
		if node is SkirtBackdrop:
			out.append(node)
	return out


static func _backdrop(base: Node, on: bool) -> String:
	var nodes := _backdrops(base)
	for node in nodes:
		node.set_process(on)
	return "skirt backdrop sync %s on %d nodes" % [str(on), nodes.size()]


static func _backdrop_bench(base: Node, runs: int) -> String:
	var nodes := _backdrops(base)
	if nodes.is_empty():
		return "no skirt backdrop"
	var node := nodes[0] as SkirtBackdrop
	var t0 := Time.get_ticks_usec()
	for i in runs:
		node.sync()
	var steady := float(Time.get_ticks_usec() - t0) / runs
	t0 = Time.get_ticks_usec()
	for i in runs:
		node.set("_last", {})
		node.sync()
	var forced := float(Time.get_ticks_usec() - t0) / runs
	return (
		"backdrop sync over %d calls, %d materials: steady %.2f us, forced %.2f us"
		% [runs, node.materials.size(), steady, forced]
	)


static func _exits_build(base: Node, runs: int) -> String:
	var terrain := _terrain(base)
	if terrain == null:
		return "no authored terrain"
	var doc := terrain.document
	var times := PackedFloat64Array()
	var parts := {}
	for i in runs:
		var t0 := Time.get_ticks_usec()
		parts = RiverExitMesh.skirt_parts(
			doc,
			AuthoredTerrain.skirt_width_m(),
			AuthoredTerrain.SKIRT_FADE_M,
			AuthoredTerrain.SKIRT_WOBBLE
		)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	# With the skirt's own exits lent (RiverExitMesh.build's cache): a refresh after an edit
	# that touched no exit.
	var cached := PackedFloat64Array()
	var reused := 0
	for i in runs:
		var t0 := Time.get_ticks_usec()
		var again := RiverExitMesh.skirt_parts(
			doc,
			AuthoredTerrain.skirt_width_m(),
			AuthoredTerrain.SKIRT_FADE_M,
			AuthoredTerrain.SKIRT_WOBBLE,
			terrain.river_exits()
		)
		cached.append((Time.get_ticks_usec() - t0) / 1000.0)
		reused = int((again.get("exits", {}) as Dictionary).get("built", -1))
	var exits: Dictionary = parts.get("exits", {})
	var skirt: Array = parts.get("skirt", [])
	return (
		"skirt_parts %s, cached %s (%d pieces built) | exits %d | skirt %d vertices, patch %d, ribbon %d"
		% [
			_stats(times),
			_stats(cached),
			reused,
			RiverExits.exits(doc).size(),
			_vertices(skirt),
			_vertices(exits.get("channel", [])),
			_vertices(exits.get("ribbon", [])),
		]
	)


static func _apply_bench(base: Node, runs: int) -> String:
	var terrain := _terrain(base)
	if terrain == null:
		return "no authored terrain"
	var parts := RiverExitMesh.skirt_parts(
		terrain.document,
		AuthoredTerrain.skirt_width_m(),
		AuthoredTerrain.SKIRT_FADE_M,
		AuthoredTerrain.SKIRT_WOBBLE
	)
	if (parts.get("exits", {}) as Dictionary).is_empty():
		return "no river exits: apply_river_exits does nothing"
	var times := PackedFloat64Array()
	for i in runs:
		var t0 := Time.get_ticks_usec()
		terrain.apply_river_exits(parts)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	return "apply_river_exits %s" % _stats(times)


static func _water_timing(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null or ctrl.editor.map_root == null:
		return "no authoring map"
	var water := ctrl.editor.map_root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	var parts := PackedStringArray()
	var timings: Dictionary = ctrl.editor.water.timings
	for key: String in timings:
		parts.append("%s %.1f" % [key, float(timings[key]) / 1000.0])
	var terrain := _terrain(base)
	if terrain != null:
		parts.append("last skirt refresh %.1f" % (terrain.last_skirt_usec / 1000.0))
	if water == null:
		return "no water | parts ms: " + ", ".join(parts)
	return (
		"water refresh build %.1f ms (worker), bake %.1f ms, swap %.1f ms | parts ms: %s"
		% [
			water.last_build_usec / 1000.0,
			water.last_bake_usec / 1000.0,
			water.last_swap_usec / 1000.0,
			", ".join(parts),
		]
	)


static func _mirror_bench(base: Node, runs: int) -> String:
	var terrain := _terrain(base)
	if terrain == null:
		return "no authored terrain"
	var doc := terrain.document
	var width := AuthoredTerrain.skirt_width_m()
	var full := PackedFloat64Array()
	var read := PackedFloat64Array()
	var arrays := TerrainMeshBuilder.build_skirt_arrays(doc, width, AuthoredTerrain.SKIRT_FADE_M)
	var count := TerrainMeshBuilder.boundary_samples(doc).size()
	for i in runs:
		var t0 := Time.get_ticks_usec()
		TerrainMeshBuilder.skirt_vertex_mirror(doc, width, AuthoredTerrain.SKIRT_FADE_M)
		full.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		TerrainMeshBuilder.skirt_mirror_of(arrays, count)
		read.append((Time.get_ticks_usec() - t0) / 1000.0)
	return "skirt_vertex_mirror %s | skirt_mirror_of %s" % [_stats(full), _stats(read)]


static func _vertices(arrays: Array) -> int:
	if arrays.is_empty():
		return 0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size()


static func _stats(times: PackedFloat64Array) -> String:
	var sorted := times.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return "n 0"
	return (
		"median %.1f ms (%.1f-%.1f, n %d)"
		% [sorted[sorted.size() / 2], sorted[0], sorted[-1], sorted.size()]
	)
