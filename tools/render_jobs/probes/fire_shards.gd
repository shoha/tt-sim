extends RefCounted

## Render-job probe (`call` op) for the grey shards and straight-edged wedges on burnt ground
## (card F4b-2; job fire_shards). Actions:
##   only {keep}       hides every GeometryInstance3D under the map but those `keep` names:
##                     "ground" (the AuthoredTerrain's chunks), "skirt" (its skirt), "rest"
##                     (everything else: scatter, props, the fire); `keep` is a list
##   show              shows everything the last `only` hid
##   chunks            the AuthoredTerrain's chunk meshes: count, surfaces, vertices, formats and
##                     the largest gap between a vertex's UV and its XZ
##   effects {on}      the scene's screen-space effects (SSAO, SSIL, SSR, SDFGI) off or back
##   debug {view}      the ground shader's code swapped in place for a debug view of its last
##                     outputs (DEBUG_VIEWS: lit grey, unlit, the shading normal, the geometric
##                     normal, the char's weight, the sim fire bake's albedo tile as RGB: the
##                     char's weight, the dried band's mix, the scorch (card fire-prod-c4; F4b-5
##                     read the static bake's first tile), the albedo before the fire, the
##                     fire's emission), built in memory from
##                     authored_ground.gdshaderinc; 0 puts the shader's own code back

const EFFECTS: PackedStringArray = ["ssao_enabled", "ssil_enabled", "ssr_enabled", "sdfgi_enabled"]
const GROUND_INC := "res://shaders/authored_ground.gdshaderinc"
const ANCHOR := "\tNORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * n_map));"
const DEBUG_VIEWS := {
	1: "ALBEDO = vec3(0.5); EMISSION = vec3(0.0); ROUGHNESS = 1.0; SPECULAR = 0.0;",
	2: "EMISSION = ALBEDO + EMISSION; ALBEDO = vec3(0.0); SPECULAR = 0.0; ROUGHNESS = 1.0;",
	3: "EMISSION = n_map * 0.5 + 0.5; ALBEDO = vec3(0.0); SPECULAR = 0.0;",
	4: "EMISSION = n_geom * 0.5 + 0.5; ALBEDO = vec3(0.0); SPECULAR = 0.0;",
	5: "EMISSION = vec3(charred); ALBEDO = vec3(0.0); SPECULAR = 0.0;",
	6:
	(
		"{ vec2 s6 = (world_xz - fire_sim_rect.xy) / fire_sim_rect.zw;"
		+ " s6.x = clamp(s6.x * 0.5, 0.0, 0.5);"
		+ " EMISSION = texture(fire_sim_map, s6).rgb;"
		+ " ALBEDO = vec3(0.0); SPECULAR = 0.0; }"
	),
	7: "EMISSION = lit_albedo; ALBEDO = vec3(0.0); SPECULAR = 0.0;",
	8: "ALBEDO = vec3(0.0); SPECULAR = 0.0;",
}

static var _hidden: Array[GeometryInstance3D] = []
static var _effects := {}
static var _code := ""


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var terrain: AuthoredTerrain = ctrl.editor.terrain
	match String(step.get("action", "")):
		"only":
			return _only(ctrl.editor.map_root, terrain, step.get("keep", []))
		"show":
			for node in _hidden:
				if is_instance_valid(node):
					node.visible = true
			var n := _hidden.size()
			_hidden.clear()
			return "shown %d" % n
		"chunks":
			return _chunks(terrain)
		"effects":
			return _screen_effects(base, bool(step.get("on", true)))
		"debug":
			return _debug(terrain.get_material().shader, int(step.get("view", 0)))
	return "unknown action"


static func _debug(shader: Shader, view: int) -> String:
	if _code == "":
		_code = shader.code
	if view == 0:
		shader.code = _code
		return "ground shader restored"
	var include := '#include "%s"' % GROUND_INC
	var source := FileAccess.get_file_as_string(GROUND_INC)
	if not _code.contains(include) or not source.contains(ANCHOR):
		return "no anchor for the debug view"
	source = source.replace(ANCHOR, ANCHOR + "\n\t" + String(DEBUG_VIEWS[view]))
	shader.code = _code.replace(include, source)
	return "ground debug view %d" % view


static func _screen_effects(base: Node, on: bool) -> String:
	var out := PackedStringArray()
	for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env == null:
			continue
		if not on and not _effects.has(env):
			var saved := {}
			for key in EFFECTS:
				saved[key] = env.get(key)
				env.set(key, false)
			_effects[env] = saved
			out.append(str(saved))
		elif on and _effects.has(env):
			for key in EFFECTS:
				env.set(key, _effects[env][key])
			_effects.erase(env)
	return "screen effects %s %s" % ["restored" if on else "off, were", ", ".join(out)]


static func _only(root: Node, terrain: AuthoredTerrain, keep: Array) -> String:
	var counts := {"ground": 0, "skirt": 0, "rest": 0}
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var kind := "rest"
		if geometry.get_parent() == terrain:
			kind = "skirt" if geometry == terrain.get_skirt() else "ground"
		if kind in keep or not geometry.visible:
			continue
		geometry.visible = false
		_hidden.append(geometry)
		counts[kind] += 1
	return "hidden %s" % str(counts)


static func _chunks(terrain: AuthoredTerrain) -> String:
	var chunks := 0
	var vertices := 0
	var worst := 0.0
	var surfaces := 0
	var flags := {}
	for child in terrain.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node == terrain.get_skirt() or mesh_node.mesh == null:
			continue
		chunks += 1
		var mesh := mesh_node.mesh as ArrayMesh
		surfaces += mesh.get_surface_count()
		for s in mesh.get_surface_count():
			flags[mesh.surface_get_format(s)] = true
			var arrays := mesh.surface_get_arrays(s)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			vertices += points.size()
			for i in mini(points.size(), uvs.size()):
				worst = maxf(worst, uvs[i].distance_to(Vector2(points[i].x, points[i].z)))
	return "chunks %d, surfaces %d, vertices %d, formats %s, largest UV - XZ gap %.4f m" % [
		chunks, surfaces, vertices, str(flags.keys()), worst
	]
