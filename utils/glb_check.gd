class_name GlbCheck
extends RefCounted

## The import check: what a map file holds, read before anything is written, so the library's
## Import and Replace map can show it and the author can decide (contract:
## docs/ASSET_PIPELINE.md section 11). Pure: it reads the file and nothing else.
##
## Only a single-file glTF Binary (.glb) is accepted. A .gltf keeps its buffers and textures
## in files beside it and a level bundles one file, so it is refused, as is a .tscn (a Godot
## scene, not an export) and a .glb that names files outside itself. A refusal is the report's
## "error", one sentence; everything else is a warning, and warnings never block.
##
## The check reads only the GLB's JSON chunk, never the binary one: the footprint comes from
## each mesh's POSITION accessor bounds (min and max, which glTF requires) carried through the
## node transforms, so a 50 MB map is checked in milliseconds without decoding a texture. The
## instance-source nodes the scatter extras name are left out of it: tt-sim frees them on load
## and Blender may have left them anywhere (section 4).
##
## The report: {"path", "error", "bytes", "mb", "has_bounds", "bounds" (AABB, metres, the
## scene's frame), "footprint_m" and "footprint_ft" (Vector2, X by Z), "floor_m" (the lowest
## point), "top_m", "meshes", "collision_nodes", "water_planes", "lights", "images",
## "extras": {"ambient_light", "background_color", "scatter_species", "scatter_instances",
## "other_keys"}, "warnings": [{"code", "text"}]}.

## The streaming budget: a bigger map.glb still plays, but each joining player downloads it
## once at about 1 MB/s (docs/NETWORKING.md), so the check says so.
const STREAMING_BUDGET_MB := 32.0
## A map whose longer side is under this (two 5 ft squares) or over the next is almost
## certainly in the wrong unit (centimetres or millimetres somewhere in the export).
const UNIT_MIN_M := 3.0
const UNIT_MAX_M := 1000.0
## The floor is off Y = 0 when the lowest point is this far above it, when the whole map is
## below it, or when the lowest point is deeper than any tabletop gorge.
const FLOOR_ABOVE_M := 0.5
const FLOOR_BELOW_M := 10.0
const METRES_PER_FOOT := 0.3048

## Warning codes.
const WARN_UNIT := "unit"
const WARN_FLOOR := "floor"
const WARN_BUDGET := "budget"
const WARN_EMPTY := "empty"

## The refusals, one sentence each.
const REFUSE_GLTF := (
	"A .gltf keeps its data in files beside it; export glTF Binary (.glb) from Blender instead."
)
const REFUSE_SCENE := (
	"A .tscn is a Godot scene, not a map export; export glTF Binary (.glb) from Blender instead."
)
const REFUSE_OTHER := "Only a glTF Binary (.glb) map can be imported."
const REFUSE_MISSING := "The file could not be opened."
const REFUSE_NOT_GLB := "This file is not a glTF Binary (.glb) export."
const REFUSE_EXTERNAL := (
	"This .glb names %d file(s) outside itself; export it with everything packed in."
)

const GLB_MAGIC := 0x46546C67
const GLB_VERSION := 2
const CHUNK_JSON := 0x4E4F534A
const HEADER_BYTES := 20
## The JSON chunk is read whole; a map's is a few MB at most (scatter extras included).
const MAX_JSON_BYTES := 256 * 1024 * 1024
## Normalized integer accessor component types and their largest value.
const NORMALIZED_MAX := {5120: 127.0, 5121: 255.0, 5122: 32767.0, 5123: 65535.0}


## The report for the file at `path` (see the header).
static func check(path: String) -> Dictionary:
	var report := _empty_report(path)
	var refusal := extension_refusal(path)
	if refusal != "":
		report.error = refusal
		return report
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		report.error = REFUSE_MISSING
		return report
	report.bytes = file.get_length()
	report.mb = report.bytes / 1048576.0
	var gltf := read_json_chunk(file)
	file.close()
	if gltf.is_empty():
		report.error = REFUSE_NOT_GLB
		return report
	var external := external_files(gltf)
	if external > 0:
		report.error = REFUSE_EXTERNAL % external
		return report
	_fill(report, gltf)
	report.warnings = warnings(report)
	return report


## The one-sentence refusal of a file by its extension, or "" for a .glb.
static func extension_refusal(path: String) -> String:
	match path.get_extension().to_lower():
		"glb":
			return ""
		"gltf":
			return REFUSE_GLTF
		"tscn", "scn":
			return REFUSE_SCENE
	return REFUSE_OTHER


## The parsed JSON chunk of the GLB open in `file` (at its start), or {} when the file is
## not a version 2 GLB or its JSON does not parse.
static func read_json_chunk(file: FileAccess) -> Dictionary:
	if file.get_length() < HEADER_BYTES:
		return {}
	var magic := file.get_32()
	var version := file.get_32()
	file.get_32()  # Total length; the chunk length below is what is read.
	var chunk_length := file.get_32()
	var chunk_type := file.get_32()
	if magic != GLB_MAGIC or version != GLB_VERSION or chunk_type != CHUNK_JSON:
		return {}
	if chunk_length > mini(file.get_length() - HEADER_BYTES, MAX_JSON_BYTES):
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_buffer(chunk_length).get_string_from_utf8()) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


## How many buffers and images name a file by URI (a data: URI is inside the file).
static func external_files(gltf: Dictionary) -> int:
	var count := 0
	for key in ["buffers", "images"]:
		for entry: Variant in _array(gltf.get(key)):
			if entry is Dictionary:
				var uri: Variant = entry.get("uri")
				if uri is String and not (uri as String).begins_with("data:"):
					count += 1
	return count


## The warnings of a filled report (see the header): never a refusal.
static func warnings(report: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not report.has_bounds:
		out.append(_warning(WARN_EMPTY, "The file holds no ground: no mesh with bounds."))
	else:
		var side: float = maxf(report.footprint_m.x, report.footprint_m.y)
		var units := "; check the units it was exported in."
		if side < UNIT_MIN_M:
			out.append(_warning(WARN_UNIT, "The map is only %.2f m across" % side + units))
		elif side > UNIT_MAX_M:
			out.append(_warning(WARN_UNIT, "The map is %d m across" % roundi(side) + units))
		var floor_m: float = report.floor_m
		if floor_m > FLOOR_ABOVE_M:
			var above := "The lowest ground is %.1f m above Y = 0, " % floor_m
			var down := "so the table grid sits under the map. "
			var fix := "In Blender, move the map down to Y = 0 and export it again."
			out.append(_warning(WARN_FLOOR, above + down + fix))
		elif report.top_m < 0.0 or floor_m < -FLOOR_BELOW_M:
			var below := "The map reaches %.1f m below Y = 0, where the table grid is. " % -floor_m
			var fix := "In Blender, move the map up until its ground sits at Y = 0, and export it again."
			out.append(_warning(WARN_FLOOR, below + fix))
	if report.mb > STREAMING_BUDGET_MB:
		var over := (
			"At %.1f MB it is over the %d MB streaming budget: "
			% [report.mb, roundi(STREAMING_BUDGET_MB)]
		)
		out.append(_warning(WARN_BUDGET, over + "each player downloads it once when they join."))
	return out


## The bounds (AABB in the scene's frame) of every mesh under the default scene's root nodes,
## skipping the subtrees of nodes named in `skip_names`. {"bounds": AABB, "found": bool}.
static func scene_bounds(gltf: Dictionary, skip_names: Dictionary = {}) -> Dictionary:
	var nodes := _array(gltf.get("nodes"))
	var meshes := _array(gltf.get("meshes"))
	var accessors := _array(gltf.get("accessors"))
	var bounds := AABB()
	var found := false
	# glTF nodes form a forest (one parent at most), so a node seen twice is a malformed cycle.
	var seen := {}
	var stack: Array = []
	for root: Variant in _array(_default_scene(gltf).get("nodes")):
		stack.append([root, Transform3D.IDENTITY])
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var index: Variant = item[0]
		if not (index is int or index is float) or int(index) < 0 or int(index) >= nodes.size():
			continue
		var node: Variant = nodes[int(index)]
		if not node is Dictionary or seen.has(int(index)):
			continue
		seen[int(index)] = true
		if skip_names.has(String(node.get("name", ""))):
			continue
		var world: Transform3D = item[1] * node_transform(node)
		var mesh_index: Variant = node.get("mesh")
		if (mesh_index is int or mesh_index is float) and int(mesh_index) < meshes.size():
			var local := mesh_bounds(meshes[int(mesh_index)], accessors)
			if local.found:
				var box: AABB = world * (local.bounds as AABB)
				bounds = box if not found else bounds.merge(box)
				found = true
		for child: Variant in _array(node.get("children")):
			stack.append([child, world])
	return {"bounds": bounds, "found": found}


## A glTF node's local transform: its "matrix" (column-major) or its translation, rotation
## and scale.
static func node_transform(node: Dictionary) -> Transform3D:
	var m := _numbers(node.get("matrix"), 16)
	if not m.is_empty():
		return Transform3D(
			Vector3(m[0], m[1], m[2]),
			Vector3(m[4], m[5], m[6]),
			Vector3(m[8], m[9], m[10]),
			Vector3(m[12], m[13], m[14])
		)
	var t := _numbers(node.get("translation"), 3)
	var r := _numbers(node.get("rotation"), 4)
	var s := _numbers(node.get("scale"), 3)
	var rotation := Quaternion.IDENTITY
	if not r.is_empty():
		var q := Quaternion(r[0], r[1], r[2], r[3])
		if q.length_squared() > 0.0:
			rotation = q.normalized()
	var scale := Vector3(s[0], s[1], s[2]) if not s.is_empty() else Vector3.ONE
	var origin := Vector3(t[0], t[1], t[2]) if not t.is_empty() else Vector3.ZERO
	return Transform3D(Basis(rotation) * Basis.from_scale(scale), origin)


## The local bounds of a glTF mesh from its primitives' POSITION accessor min and max.
## {"bounds": AABB, "found": bool}.
static func mesh_bounds(mesh: Variant, accessors: Array) -> Dictionary:
	var bounds := AABB()
	var found := false
	if not mesh is Dictionary:
		return {"bounds": bounds, "found": false}
	for primitive: Variant in _array(mesh.get("primitives")):
		if not primitive is Dictionary or not primitive.get("attributes") is Dictionary:
			continue
		var position: Variant = primitive.attributes.get("POSITION")
		if not (position is int or position is float) or int(position) >= accessors.size():
			continue
		var accessor: Variant = accessors[int(position)]
		if not accessor is Dictionary:
			continue
		var low := _numbers(accessor.get("min"), 3)
		var high := _numbers(accessor.get("max"), 3)
		if low.is_empty() or high.is_empty():
			continue
		var divisor := 1.0
		if accessor.get("normalized", false) == true:
			divisor = NORMALIZED_MAX.get(int(accessor.get("componentType", 0)), 1.0)
		var a := Vector3(low[0], low[1], low[2]) / divisor
		var b := Vector3(high[0], high[1], high[2]) / divisor
		var box := AABB(a, Vector3.ZERO).expand(b)
		bounds = box if not found else bounds.merge(box)
		found = true
	return {"bounds": bounds, "found": found}


## The default scene's extras (the dict terrain-paint patches), or {}.
static func scene_extras(gltf: Dictionary) -> Dictionary:
	var extras: Variant = _default_scene(gltf).get("extras", {})
	return extras if extras is Dictionary else {}


## What the scene extras hold: {"ambient_light", "background_color" (bools),
## "scatter_species", "scatter_instances" (ints), "other_keys" (the keys tt-sim does not
## read)}.
static func extras_summary(extras: Dictionary) -> Dictionary:
	var known := [
		"tt_ambient_light_color",
		"tt_ambient_light_energy",
		"tt_background_color",
		"tt_scatter_instances",
	]
	var scatter: Variant = extras.get("tt_scatter_instances", {})
	var species := 0
	var instances := 0
	if scatter is Dictionary:
		for key: Variant in scatter:
			if scatter[key] is Array:
				species += 1
				instances += (scatter[key] as Array).size()
	var other := PackedStringArray()
	for key: Variant in extras:
		if not known.has(String(key)):
			other.append(String(key))
	return {
		"ambient_light":
		extras.has("tt_ambient_light_color") or extras.has("tt_ambient_light_energy"),
		"background_color": extras.has("tt_background_color"),
		"scatter_species": species,
		"scatter_instances": instances,
		"other_keys": other,
	}


static func _fill(report: Dictionary, gltf: Dictionary) -> void:
	var extras := scene_extras(gltf)
	report.extras = extras_summary(extras)
	var skip := {}
	var scatter: Variant = extras.get("tt_scatter_instances", {})
	if scatter is Dictionary:
		for key: Variant in scatter:
			skip[String(key)] = true
	var measured := scene_bounds(gltf, skip)
	report.has_bounds = measured.found
	if measured.found:
		var bounds: AABB = measured.bounds
		report.bounds = bounds
		report.footprint_m = Vector2(bounds.size.x, bounds.size.z)
		report.footprint_ft = report.footprint_m / METRES_PER_FOOT
		report.floor_m = bounds.position.y
		report.top_m = bounds.end.y
	for node: Variant in _array(gltf.get("nodes")):
		if not node is Dictionary:
			continue
		var node_name := String(node.get("name", "")).to_lower()
		if node.has("mesh"):
			report.meshes += 1
		if node_name.ends_with("-water"):
			report.water_planes += 1
		for suffix: String in GlbUtils.COLLISION_SUFFIXES:
			if node_name.ends_with(suffix):
				report.collision_nodes += 1
				break
	report.images = _array(gltf.get("images")).size()
	var extensions: Variant = gltf.get("extensions", {})
	if extensions is Dictionary and extensions.get("KHR_lights_punctual") is Dictionary:
		report.lights = _array(extensions.KHR_lights_punctual.get("lights")).size()


static func _empty_report(path: String) -> Dictionary:
	return {
		"path": path,
		"error": "",
		"bytes": 0,
		"mb": 0.0,
		"has_bounds": false,
		"bounds": AABB(),
		"footprint_m": Vector2.ZERO,
		"footprint_ft": Vector2.ZERO,
		"floor_m": 0.0,
		"top_m": 0.0,
		"meshes": 0,
		"collision_nodes": 0,
		"water_planes": 0,
		"lights": 0,
		"images": 0,
		"extras": extras_summary({}),
		"warnings": [] as Array[Dictionary],
	}


static func _warning(code: String, text: String) -> Dictionary:
	return {"code": code, "text": text}


## The default scene ("scene", else the first), or {}.
static func _default_scene(gltf: Dictionary) -> Dictionary:
	var scenes := _array(gltf.get("scenes"))
	var index: Variant = gltf.get("scene", 0)
	if not (index is int or index is float) or int(index) < 0 or int(index) >= scenes.size():
		return {}
	var scene: Variant = scenes[int(index)]
	return scene if scene is Dictionary else {}


static func _array(value: Variant) -> Array:
	return value if value is Array else []


## `value` as `count` floats, or empty when it is not an array of that many numbers.
static func _numbers(value: Variant, count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if not value is Array or (value as Array).size() != count:
		return out
	for v: Variant in value:
		if not (v is int or v is float):
			return PackedFloat64Array()
		out.append(float(v))
	return out
