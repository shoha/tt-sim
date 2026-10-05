extends RefCounted

## Render-job probe (`call` op) for water drawn over the ground skirt (phase 6, P6-0): can a
## river that reaches the map edge continue into the skirt (TerrainSkirt) as scenery? Works
## on the open authored map (authoring, or play). Positions are map XZ metres; a line's
## `from` is moved along the line onto the map edge, so it may be any point inside the map on
## the river's course. step.action:
##   dip {from, to, width, depth, bank, rings}
##                         rebuilds the skirt mesh with `rings` rings (default RINGS, against
##                         the game's 8, so a channel a few metres wide has vertices to bend)
##                         and lowers it along the line `from` (on the map edge where the river
##                         leaves) to `to` (out into the skirt). By default the channel is the
##                         river's own cross-section 0.25 m inside the edge (the document's
##                         ground over the wet span plus `bank` metres either side) carried
##                         straight out; with `depth`, a synthetic one instead: `width` wide
##                         (default the wet span), its bed `depth` under the water level, easing
##                         up to the skirt over `bank` metres either side.
##                         The skirt keeps its material; ring 0 stays the map's boundary. Logs
##                         the level, the edge bed, the wet span and the vertex count.
##   undip                 puts the game's skirt mesh back.
##   ribbon {from, to, width, level, mode, name, priority}
##                         a water strip at `level` (default: the level dip found) along the
##                         line, `width` (the waterline; default the wet span) plus
##                         RIBBON_MARGIN_M either side wide, under the map root as
##                         "P6Ribbon_<name>" (replacing one of that name). mode "real": the
##                         shared water material duplicated onto a copy of shaders/water.gdshader
##                         whose ALPHA is also multiplied by the skirt's fade (the skirt's own
##                         skirt_alpha(), same noise and seed), UVs on the in-map water's flow
##                         map grid (clamped past the edge, so the edge's flow carries on).
##                         mode "simple": a water material that reads no depth or screen
##                         texture: the water's own colours, shallows and a foam lip by distance
##                         from the ribbon's centre line, a few soft ripples, the same fade.
##                         `priority`: the material's render_priority, default the skirt's + 1
##                         (at equal priority the skirt draws over the ribbon).
##   ribbon_visible {visible, name}  shows or hides the ribbon (GPU A/B).
##   skirt_depth {mode}    the skirt's shader: "never" (the game's: blend_mix,
##                         depth_draw_never), "always" (depth_draw_always), "prepass"
##                         (depth_prepass_alpha), "dither" (opaque, depth_draw_opaque, the fade
##                         as a per-pixel dithered discard ahead of the texture work),
##                         "dissolve" (the same with world-space noise patches as the
##                         threshold), "tint" (opaque, no discard past the early one: the fade
##                         as ALBEDO * a plus EMISSION = the environment's background colour *
##                         (1 - a)). Variants are built from the
##                         repo files, written to user://render_jobs/p6_probe/skirt_<mode>
##                         .gdshader for reference and hot-swapped onto the skirt's material;
##                         the repo shader is untouched.
##   fog {on, density, color}  the environment's depth fog on every WorldEnvironment (off
##                         restores what was there).
##   info                  the skirt and ribbon materials' modes and render priorities, and
##                         the environment's fog.
##   state {name, from, to}  one of STATES (a capture name's state): the dip, the ribbon
##                         ("ribbon", replaced or hidden) and the skirt shader set together.

const RIBBON_PREFIX := "P6Ribbon_"
## Named probe states: [dip, ribbon mode ("" for none), skirt shader mode, and optionally the
## ribbon's render priority (default the skirt's + 1)].
const STATES := {
	"now": [false, "", "never"],
	"dip": [true, "", "never"],
	"real_p0": [true, "real", "never", 0],
	"real": [true, "real", "never"],
	"real_depth": [true, "real", "always"],
	"real_prepass": [true, "real", "prepass"],
	"real_dither": [true, "real", "dither"],
	"real_dissolve": [true, "real", "dissolve"],
	"real_tint": [true, "real", "tint"],
	"dip_tint": [true, "", "tint"],
	"dip_dither": [true, "", "dither"],
	"simple": [true, "simple", "never"],
	"simple_dither": [true, "simple", "dither"],
}
const RINGS := 32
## Ribbon sampling: a row every ROW_M along the line, ACROSS vertices across it.
const ROW_M := 0.5
const ACROSS := 9
## The ribbon reaches this far past the waterline on either side.
const RIBBON_MARGIN_M := 0.6
const VARIANT_DIR := "user://render_jobs/p6_probe"
const SKIRT_FILE := "res://shaders/authored_ground_skirt.gdshader"
const INCLUDE_FILE := "res://shaders/authored_ground.gdshaderinc"
const INCLUDE_LINE := '#include "res://shaders/authored_ground.gdshaderinc"'
const WATER_FILE := "res://shaders/water.gdshader"
const WATER_ALPHA_LINE := "ALPHA = clamp(alpha + foam * 0.3, 0.0, 1.0) * shoreline;"
## The skirt's fade (authored_ground.gdshaderinc skirt_alpha and its value noise), renamed so
## it can sit in the water shader beside that shader's own noise.
const FADE_CODE := """
uniform vec2 p6_half_extent = vec2(30.0);
uniform float p6_fade_m = 24.0;
uniform float p6_wobble = 0.45;
uniform int p6_seed = 0;

uvec2 p6_pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}

float p6_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 u = fract(p);
	u = u * u * (3.0 - 2.0 * u);
	uvec2 c = uvec2(ivec2(i) + ivec2(p6_seed, p6_seed * 7919));
	float a = float(p6_pcg2d(c).x);
	float b = float(p6_pcg2d(c + uvec2(1u, 0u)).x);
	float d = float(p6_pcg2d(c + uvec2(0u, 1u)).x);
	float e = float(p6_pcg2d(c + uvec2(1u, 1u)).x);
	return mix(mix(a, b, u.x), mix(d, e, u.x), u.y) * (1.0 / 4294967295.0);
}

float p6_skirt_alpha(vec2 world_xz) {
	float d = length(max(abs(world_xz) - p6_half_extent, vec2(0.0)));
	vec2 p = world_xz / 11.0;
	float n = p6_value_noise(p + vec2(3.7, -8.2)) * 0.7
		+ p6_value_noise(p * 2.3 + vec2(-5.1, 2.9)) * 0.3;
	d *= 1.0 + (n - 0.5) * 2.0 * p6_wobble;
	float t = clamp(d / p6_fade_m, 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}
"""
## The candidate simple ribbon: no depth or screen reads. UV2 is (metres along, metres
## across from the centre line).
const SIMPLE_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.05, 0.30, 0.38, 0.8);
uniform vec4 shore_color : source_color = vec4(0.35, 0.75, 0.70, 0.6);
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.96, 0.9);
uniform float ribbon_half_width = 1.5;
uniform float wave_speed = 0.6;
varying vec3 world_pos;
%s
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fade = p6_skirt_alpha(world_pos.xz);
	if (fade <= 0.0) {
		discard;
	}
	float t = TIME * wave_speed;
	vec2 p = world_pos.xz;
	// 0 on the bank line, 1 on the centre line.
	float inner = clamp(1.0 - abs(UV2.y) / ribbon_half_width, 0.0, 1.0);
	float deep = smoothstep(0.05, 0.75, inner);
	vec3 col = mix(shore_color.rgb, water_color.rgb, deep);
	vec2 g = vec2(
		sin(p.x * 1.7 + t) + 0.5 * sin(p.y * 2.9 - t * 1.3),
		cos(p.y * 1.9 + t * 0.8) + 0.5 * cos(p.x * 2.3 - t)
	) * 0.05;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-g.x, 1.0, -g.y)), 0.0)).xyz);
	float lap = 0.75 + 0.25 * sin(inner * 40.0 - t * 2.0);
	float foam = (1.0 - smoothstep(0.04, 0.2, inner)) * lap;
	col = mix(col, foam_color.rgb, foam * foam_color.a * 0.8);
	ALBEDO = col;
	ROUGHNESS = mix(0.1, 0.9, foam);
	SPECULAR = 0.6;
	ALPHA = mix(shore_color.a, 0.95, deep) * smoothstep(0.0, 0.06, inner) * fade;
}
"""
## Screen-space dither for the opaque skirt: interleaved gradient noise.
## "dither": interleaved gradient noise per pixel. "dissolve": world-space value noise, so the
## fade breaks into soft patches about a metre across instead of a stipple.
const DITHER_CODE := """
float p6_dither(vec2 frag, vec2 world_xz) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

"""
const DISSOLVE_CODE := """
float p6_dither(vec2 frag, vec2 world_xz) {
	float ign = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	float n = value_noise(world_xz / 1.6 + vec2(17.3, -4.1)) * 0.65
		+ value_noise(world_xz / 0.55 + vec2(-9.7, 31.2)) * 0.35;
	return clamp(mix(n, ign, 0.15), 0.0, 1.0);
}

"""
## "tint": the backdrop colour (the environment's flat background) and the fade in colour.
const TINT_UNIFORM := "uniform vec3 p6_backdrop : source_color = vec3(0.7, 0.75, 0.8);\n\n"
const TINT_CODE := (
	"\tALBEDO *= skirt_a;\n\tSPECULAR = 0.5 * skirt_a;\n"
	+ "\tEMISSION = p6_backdrop * (1.0 - skirt_a);"
)
## The skirt include's early discard, and what the opaque variants put in its place: the fade
## as a discard ahead of every texture fetch.
const EARLY_DISCARD := "\tif (skirt_a <= 0.0) {"
const DITHER_DISCARD := "\tif (skirt_a <= 0.0 || skirt_a < p6_dither(FRAGCOORD.xy, world_xz)) {"

## The game's skirt mesh and shader, kept so undip and skirt_depth never can put them back.
static var _game_mesh: Mesh = null
static var _game_shader: Shader = null
## What dip found: the water level and the wet span just inside the edge.
static var _level: float = 0.0
static var _span: float = 3.0
## The environment's fog before `fog` turned it on: [enabled, density, colour].
static var _fog_saved: Array = []


static func run(base: Node, step: Dictionary) -> String:
	var out := ""
	match String(step.get("action", "")):
		"dip":
			out = _dip(base, step)
		"undip":
			out = _undip(base)
		"ribbon":
			out = _ribbon(base, step)
		"ribbon_visible":
			out = _ribbon_visible(base, step)
		"skirt_depth":
			out = _skirt_depth(base, String(step.get("mode", "never")))
		"fog":
			out = _fog(base, step)
		"info":
			out = _info(base)
		"state":
			out = _state(base, step)
		_:
			out = "unknown action %s" % step.get("action", "")
	return out


static func _xz(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _state(base: Node, step: Dictionary) -> String:
	var name := String(step.get("name", "now"))
	if not STATES.has(name):
		return "unknown state %s" % name
	var spec: Array = STATES[name]
	var parts := PackedStringArray([name])
	parts.append(_dip(base, step) if spec[0] else _undip(base))
	var mode := String(spec[1])
	if mode.is_empty():
		parts.append(_ribbon_visible(base, {"visible": false}))
	else:
		var ribbon := step.duplicate()
		ribbon["mode"] = mode
		ribbon["name"] = "ribbon"
		if spec.size() > 3:
			ribbon["priority"] = spec[3]
		parts.append(_ribbon(base, ribbon))
	parts.append(_skirt_depth(base, String(spec[2])))
	return " | ".join(parts)


## `from` moved along the line toward `to` until it meets the map edge (the first side of
## the map rectangle the line crosses).
static func _on_edge(doc: MapDocument, from: Vector2, to: Vector2) -> Vector2:
	var half := doc.extent_m() * 0.5
	var dir := (to - from).normalized()
	var t := INF
	for axis in 2:
		if absf(dir[axis]) > 1e-6:
			t = minf(t, (signf(dir[axis]) * half[axis] - from[axis]) / dir[axis])
	return from + dir * t if t != INF else from


## The open document: the authoring controller's, or in play the loaded level's.
static func _document(base: Node) -> MapDocument:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl != null and ctrl.document != null:
		return ctrl.document
	var lpc: LevelPlayController = base.get("_level_play_controller")
	return lpc.loaded_map_document if lpc != null else null


static func _map_root(base: Node) -> Node3D:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.map_container == null:
		return null
	return gm.map_container.get_node_or_null(^"LevelMap") as Node3D


static func _skirt(base: Node) -> MeshInstance3D:
	var found := base.get_tree().root.find_children(
		AuthoredTerrain.SKIRT_NAME, "MeshInstance3D", true, false
	)
	return found[0] as MeshInstance3D if not found.is_empty() else null


static func _skirt_material(skirt: MeshInstance3D) -> ShaderMaterial:
	if skirt == null or skirt.mesh == null:
		return null
	return skirt.mesh.surface_get_material(0) as ShaderMaterial


# --- dip ---------------------------------------------------------------------------------------


static func _dip(base: Node, step: Dictionary) -> String:
	var doc := _document(base)
	var skirt := _skirt(base)
	var material := _skirt_material(skirt)
	if doc == null or material == null:
		return "no document or skirt"
	if _game_mesh == null:
		_game_mesh = skirt.mesh
	var to := _xz(step.get("to"), Vector2(0, 60))
	var from := _on_edge(doc, _xz(step.get("from"), Vector2.ZERO), to)
	var dir := (to - from).normalized()
	var across := Vector2(-dir.y, dir.x)
	# Just inside the edge: the river's level, its bed on the line and its wet span.
	var inside := from - dir * 0.25
	_level = WaterGeometry.level_at(doc, inside)
	var edge_bed := WaterGeometry.ground_at(doc, inside)
	var wet := _wet_span(doc, inside, across)
	if _level == WaterGeometry.DRY:
		_level = edge_bed
	_span = maxf(wet.y - wet.x, 0.5)
	var width := float(step.get("width", _span))
	var depth := float(step.get("depth", _level - edge_bed))
	var bank := float(step.get("bank", 1.5))
	var bed := _level - depth
	# Without an explicit depth the channel is the river's own cross-section at the edge,
	# carried straight out (its waterline then meets the in-map one at the mouth).
	var extrude := not step.has("depth")
	var half := width * 0.5 + bank
	var profile := _edge_profile(doc, inside, across, half)
	var rings := int(step.get("rings", RINGS))
	var arrays := _skirt_arrays(doc, rings)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var count: int = vertices.size() / (rings + 1)
	var moved := 0
	for k in range(count, vertices.size()):
		var q := Vector2(vertices[k].x, vertices[k].z)
		var s := (q - from).dot(dir)
		if s < 0.0:
			continue
		var u := (q - from).dot(across)
		var y := vertices[k].y
		if extrude:
			if absf(u) < half:
				y = minf(y, profile[clampi(roundi((u + half) / 0.1), 0, profile.size() - 1)])
		else:
			var inner := 1.0 - smoothstep(width * 0.3, width * 0.5 + bank, absf(u))
			y = minf(y, lerpf(y, bed, inner))
		if y < vertices[k].y:
			moved += 1
		vertices[k].y = y
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals(vertices, arrays[Mesh.ARRAY_INDEX])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	mesh.custom_aabb = (_game_mesh as ArrayMesh).custom_aabb
	skirt.mesh = mesh
	return (
		(
			"dip: level %.3f, edge bed %.3f, wet span %.2f..%.2f (%.2f m), channel width %.2f"
			+ " bed %.3f bank %.1f, %d rings x %d, %d vertices lowered | centre line %s"
		)
		% [
			_level,
			edge_bed,
			wet.x,
			wet.y,
			_span,
			width,
			bed,
			bank,
			rings,
			count,
			moved,
			_centre_line(vertices, count, rings, from, dir),
		]
	)


## The vertex nearest the line on every fourth ring: "(distance out, y)".
static func _centre_line(
	vertices: PackedVector3Array, count: int, rings: int, from: Vector2, dir: Vector2
) -> String:
	var parts := PackedStringArray()
	var across := Vector2(-dir.y, dir.x)
	for r in range(0, rings + 1, 4):
		var best := -1
		var best_u := INF
		for i in count:
			var v := vertices[r * count + i]
			var q := Vector2(v.x, v.z) - from
			var u := absf(q.dot(across))
			if q.dot(dir) >= -0.01 and u < best_u:
				best_u = u
				best = r * count + i
		if best >= 0:
			var v := vertices[best]
			parts.append("(%.1f, %.2f)" % [(Vector2(v.x, v.z) - from).dot(dir), v.y])
	return " ".join(parts)


## The document's ground across the line at `at`, every 0.1 m from -half to +half.
static func _edge_profile(
	doc: MapDocument, at: Vector2, across: Vector2, half: float
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in int(round(2.0 * half / 0.1)) + 1:
		out.append(WaterGeometry.ground_at(doc, at + across * (i * 0.1 - half)))
	return out


## Lowest and highest offset along `across` from `at` (within 6 m) where the ground is under
## the water level.
static func _wet_span(doc: MapDocument, at: Vector2, across: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in range(-60, 61):
		var u := i * 0.1
		var q := at + across * u
		var level := WaterGeometry.level_at(doc, q)
		if level != WaterGeometry.DRY and WaterGeometry.ground_at(doc, q) < level:
			lo = minf(lo, u)
			hi = maxf(hi, u)
	return Vector2(lo, hi) if lo <= hi else Vector2.ZERO


## TerrainMeshBuilder.build_skirt_arrays with `rings` rings instead of SKIRT_RINGS (same
## spacing power, width and fall-off), so a narrow channel has vertices to follow it.
static func _skirt_arrays(doc: MapDocument, rings: int) -> Array:
	var loop := TerrainMeshBuilder.boundary_samples(doc)
	var count := loop.size()
	var width := AuthoredTerrain.skirt_width_m()
	var fall := AuthoredTerrain.SKIRT_FADE_M
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(count * (rings + 1))
	uvs.resize(count * (rings + 1))
	for i in count:
		var sample := loop[i]
		var inner := TerrainMeshBuilder.sample_position(doc, sample.x, sample.y)
		var out := Vector3(
			-1.0 if sample.x == 0 else (1.0 if sample.x == last.x else 0.0),
			0.0,
			-1.0 if sample.y == 0 else (1.0 if sample.y == last.y else 0.0)
		)
		for r in rings + 1:
			var distance := (
				width * pow(float(r) / rings, TerrainMeshBuilder.SKIRT_RING_SPACING_POWER)
			)
			var point := inner + out * distance
			point.y = TerrainMeshBuilder.skirt_height(inner.y, distance, fall)
			vertices[r * count + i] = point
			uvs[r * count + i] = Vector2(point.x, point.z)
	var indices := PackedInt32Array()
	for r in rings:
		for i in count:
			var j := (i + 1) % count
			var a := r * count + i
			var b := r * count + j
			var c := (r + 1) * count + j
			var d := (r + 1) * count + i
			indices.append_array(_up([a, b, c], vertices))
			indices.append_array(_up([a, c, d], vertices))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## The triangle wound so its front faces +Y (Godot's front faces are clockwise from the
## front: cross(C - A, B - A) points at the viewer).
static func _up(tri: Array, vertices: PackedVector3Array) -> Array:
	var a := vertices[tri[0]]
	var n := (vertices[tri[2]] - a).cross(vertices[tri[1]] - a)
	return tri if n.y >= 0.0 else [tri[0], tri[2], tri[1]]


static func _normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.ZERO)
	for f in indices.size() / 3:
		var a := indices[f * 3]
		var b := indices[f * 3 + 1]
		var c := indices[f * 3 + 2]
		var n := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	for k in normals.size():
		normals[k] = normals[k].normalized() if normals[k].length_squared() > 0.0 else Vector3.UP
	return normals


static func _undip(base: Node) -> String:
	var skirt := _skirt(base)
	if skirt == null or _game_mesh == null:
		return "nothing to undo"
	skirt.mesh = _game_mesh
	return "skirt mesh restored"


# --- ribbon ------------------------------------------------------------------------------------


static func _ribbon(base: Node, step: Dictionary) -> String:
	var doc := _document(base)
	var root := _map_root(base)
	var skirt_material := _skirt_material(_skirt(base))
	if doc == null or root == null or skirt_material == null:
		return "no document, map root or skirt"
	var to := _xz(step.get("to"), Vector2(0, 60))
	var from := _on_edge(doc, _xz(step.get("from"), Vector2.ZERO), to)
	# The waterline (the wet span), and the strip a margin wider so the banks cross the level
	# inside it: where the depth texture holds the channel, the water shader's own shoreline
	# fade and foam draw the edge, as in the map.
	var waterline := float(step.get("width", _span))
	var width := waterline + 2.0 * RIBBON_MARGIN_M
	var level := float(step.get("level", _level))
	var mode := String(step.get("mode", "real"))
	var label := String(step.get("name", "ribbon"))
	_remove_ribbon(root, label)
	var material := _ribbon_material(mode, waterline, skirt_material)
	if material == null:
		return "no water material"
	# At equal priority the skirt (one transparent mesh, origin at the map centre like the
	# ribbon's) drew over the ribbon in the first captures; above it, the ribbon draws last.
	material.render_priority = int(step.get("priority", skirt_material.render_priority + 1))
	var instance := MeshInstance3D.new()
	instance.name = RIBBON_PREFIX + label
	instance.mesh = _strip(doc, from, to, width, level)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(Constants.BOUNDS_EXEMPT_META, true)
	if mode == "real":
		instance.set_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM, true)
	root.add_child(instance)
	return (
		"ribbon %s (%s): %s -> %s width %.2f level %.3f, priority %d (skirt %d)"
		% [
			label,
			mode,
			str(from),
			str(to),
			width,
			level,
			material.render_priority,
			skirt_material.render_priority,
		]
	)


## The strip: rows every ROW_M from `from` to `to`, ACROSS vertices over `width`, flat at
## `level`. UV is the in-map water's flow-map grid (WaterMeshBuilder: the map extent mapped
## to 0..1), UV2 (metres along, metres across).
static func _strip(
	doc: MapDocument, from: Vector2, to: Vector2, width: float, level: float
) -> ArrayMesh:
	var length := from.distance_to(to)
	var dir := (to - from) / maxf(length, 1e-4)
	var across := Vector2(-dir.y, dir.x)
	var rows := int(ceil(length / ROW_M)) + 1
	var extent := doc.extent_m()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	for i in rows:
		var s := minf(i * ROW_M, length)
		for j in ACROSS:
			var u := (float(j) / float(ACROSS - 1) - 0.5) * width
			var q := from + dir * s + across * u
			vertices.append(Vector3(q.x, level, q.y))
			uvs.append(q / extent + Vector2(0.5, 0.5))
			uv2s.append(Vector2(s, u))
	var indices := PackedInt32Array()
	for i in rows - 1:
		for j in ACROSS - 1:
			var a := i * ACROSS + j
			var b := a + 1
			var c := a + ACROSS
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _ribbon_material(
	mode: String, width: float, skirt_material: ShaderMaterial
) -> ShaderMaterial:
	var water := WaterGlbUtils._get_water_material()
	if water == null:
		return null
	var material: ShaderMaterial
	var shader := Shader.new()
	if mode == "simple":
		shader.code = SIMPLE_CODE % FADE_CODE
		material = ShaderMaterial.new()
		material.shader = shader
		for key in ["water_color", "shore_color", "foam_color", "wave_speed"]:
			material.set_shader_parameter(key, water.get_shader_parameter(key))
		material.set_shader_parameter("ribbon_half_width", width * 0.5)
		material.render_priority = water.render_priority
	else:
		var code := FileAccess.get_file_as_string(WATER_FILE)
		code = code.replace("void vertex() {", FADE_CODE + "\nvoid vertex() {")
		code = code.replace(
			WATER_ALPHA_LINE, WATER_ALPHA_LINE.replace(";", " * p6_skirt_alpha(world_pos.xz);")
		)
		shader.code = code
		material = water.duplicate() as ShaderMaterial
		material.shader = shader
	material.set_shader_parameter(
		"p6_half_extent", skirt_material.get_shader_parameter("skirt_half_extent")
	)
	material.set_shader_parameter("p6_fade_m", skirt_material.get_shader_parameter("skirt_fade_m"))
	material.set_shader_parameter("p6_wobble", skirt_material.get_shader_parameter("skirt_wobble"))
	material.set_shader_parameter("p6_seed", skirt_material.get_shader_parameter("breakup_seed"))
	return material


static func _remove_ribbon(root: Node3D, label: String) -> void:
	var node := root.get_node_or_null(RIBBON_PREFIX + label)
	if node != null:
		root.remove_child(node)
		node.free()


static func _ribbon_visible(base: Node, step: Dictionary) -> String:
	var root := _map_root(base)
	if root == null:
		return "no map root"
	var label := String(step.get("name", "ribbon"))
	var node := root.get_node_or_null(RIBBON_PREFIX + label) as MeshInstance3D
	if node == null:
		return "no ribbon %s" % label
	node.visible = bool(step.get("visible", true))
	return "ribbon %s visible %s" % [label, str(node.visible)]


# --- skirt shader variants ---------------------------------------------------------------------


static func _skirt_depth(base: Node, mode: String) -> String:
	var material := _skirt_material(_skirt(base))
	if material == null:
		return "no skirt"
	if _game_shader == null:
		_game_shader = material.shader
	if mode == "never":
		material.shader = _game_shader
		return "skirt shader: the game's"
	var wrapper := FileAccess.get_file_as_string(SKIRT_FILE)
	var include := FileAccess.get_file_as_string(INCLUDE_FILE)
	var modes := "blend_mix, depth_draw_never"
	match mode:
		"always":
			wrapper = wrapper.replace(modes, "blend_mix, depth_draw_always")
		"prepass":
			wrapper = wrapper.replace(modes, "blend_mix, depth_prepass_alpha")
		"dither", "dissolve":
			# Opaque: in the depth prepass and the screen texture like the map's own ground.
			wrapper = wrapper.replace(modes, "depth_draw_opaque")
			var noise := DITHER_CODE if mode == "dither" else DISSOLVE_CODE
			include = include.replace("void vertex() {", noise + "void vertex() {")
			include = include.replace(EARLY_DISCARD, DITHER_DISCARD)
			include = include.replace("\tALPHA = skirt_a;", "\t// ALPHA: dithered discard above")
		"tint":
			# Opaque, the fade done in colour: lit ground * a + backdrop * (1 - a), which is
			# what the alpha blend gives for diffuse light, over a flat-colour backdrop.
			wrapper = wrapper.replace(modes, "depth_draw_opaque")
			include = include.replace("void vertex() {", TINT_UNIFORM + "void vertex() {")
			include = include.replace("\tALPHA = skirt_a;", TINT_CODE)
			var envs := _environments(base)
			if not envs.is_empty():
				material.set_shader_parameter("p6_backdrop", envs[0].background_color)
		_:
			return "unknown skirt mode %s" % mode
	var code := wrapper.replace(INCLUDE_LINE, include)
	DirAccess.make_dir_recursive_absolute(VARIANT_DIR)
	var file := FileAccess.open("%s/skirt_%s.gdshader" % [VARIANT_DIR, mode], FileAccess.WRITE)
	if file != null:
		file.store_string(code)
		file.close()
	var shader := Shader.new()
	shader.code = code
	material.shader = shader
	return "skirt shader: %s (%d chars)" % [mode, code.length()]


# --- fog and info ------------------------------------------------------------------------------


static func _environments(base: Node) -> Array[Environment]:
	var out: Array[Environment] = []
	for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env != null:
			out.append(env)
	return out


static func _fog(base: Node, step: Dictionary) -> String:
	var on := bool(step.get("on", true))
	var c: Array = step.get("color", [0.78, 0.84, 0.88])
	var parts := PackedStringArray()
	for env in _environments(base):
		if on:
			if _fog_saved.is_empty():
				_fog_saved = [env.fog_enabled, env.fog_density, env.fog_light_color]
			env.fog_enabled = true
			env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
			env.fog_density = float(step.get("density", 0.01))
			env.fog_light_color = Color(float(c[0]), float(c[1]), float(c[2]))
		elif not _fog_saved.is_empty():
			env.fog_enabled = _fog_saved[0]
			env.fog_density = _fog_saved[1]
			env.fog_light_color = _fog_saved[2]
		parts.append("fog %s density %.4f" % [str(env.fog_enabled), env.fog_density])
	if not on:
		_fog_saved = []
	return " | ".join(parts)


static func _info(base: Node) -> String:
	var parts := PackedStringArray()
	var material := _skirt_material(_skirt(base))
	if material != null:
		parts.append(
			(
				"skirt priority %d shader %s"
				% [material.render_priority, material.shader.resource_path]
			)
		)
	var root := _map_root(base)
	if root != null:
		for node in root.find_children(RIBBON_PREFIX + "*", "MeshInstance3D", false, false):
			var ribbon := node as MeshInstance3D
			parts.append(
				(
					"%s visible %s priority %d"
					% [ribbon.name, str(ribbon.visible), ribbon.material_override.render_priority]
				)
			)
	var gm := base.get("_game_map") as GameMap
	if gm != null and gm.camera_node != null:
		parts.append(
			"camera size %.2f at %s" % [gm.camera_node.size, str(gm.camera_node.global_position)]
		)
	for env in _environments(base):
		parts.append(
			(
				"env fog %s density %.4f bg %d"
				% [str(env.fog_enabled), env.fog_density, env.background_mode]
			)
		)
	return " | ".join(parts)
