extends RefCounted

## A minimal GLB writer for the Folk build (tools/roster/build_folk.gd): one node, one mesh,
## one primitive per merged group, embedded lossy-WebP base colour textures (EXT_texture_webp).
##
## Godot's own exporter writes a tangent accessor for every vertex even when the mesh has no
## normal map (a third of the file), so a figure is encoded here instead: positions, normals
## and UVs as float32, 16-bit indices, nothing else. The output is deterministic, which the
## pack's build test relies on. tt-sim and Godot's importer read the file as any GLB.

const _FLOAT := 5126
const _USHORT := 5123
const _ARRAY_BUFFER := 34962
const _ELEMENT_ARRAY_BUFFER := 34963


## Encodes `groups` (each an object with `verts`, `normals`, `uvs`, `indices` and a
## StandardMaterial3D `material` with an albedo texture and tint) as a GLB.
static func encode(
	node_name: String, groups: Array, webp_quality: float, copyright: String
) -> PackedByteArray:
	var bin := PackedByteArray()
	var views: Array = []
	var accessors: Array = []
	var materials: Array = []
	var textures: Array = []
	var images: Array = []
	var primitives: Array = []
	var texture_of := {}
	for group in groups:
		var attributes := {}
		attributes["POSITION"] = _accessor(bin, views, accessors, _vec3(group.verts), "VEC3", true)
		attributes["NORMAL"] = _accessor(bin, views, accessors, _vec3(group.normals), "VEC3", false)
		attributes["TEXCOORD_0"] = _accessor(bin, views, accessors, _vec2(group.uvs), "VEC2", false)
		var index_view := _push(bin, views, _ushorts(group.indices), _ELEMENT_ARRAY_BUFFER)
		accessors.append(
			{
				"bufferView": index_view,
				"componentType": _USHORT,
				"count": group.indices.size(),
				"type": "SCALAR"
			}
		)
		var texture: Texture2D = group.material.albedo_texture
		if not texture_of.has(texture):
			var webp := texture.get_image().save_webp_to_buffer(true, webp_quality)
			images.append({"bufferView": _push(bin, views, webp, 0), "mimeType": "image/webp"})
			textures.append({"extensions": {"EXT_texture_webp": {"source": images.size() - 1}}})
			texture_of[texture] = textures.size() - 1
		# glTF's baseColorFactor is linear; the material's albedo colour is sRGB.
		var tint: Color = group.material.albedo_color.srgb_to_linear()
		materials.append(
			{
				"name": group.material.resource_name,
				"pbrMetallicRoughness":
				{
					"baseColorFactor": [tint.r, tint.g, tint.b, 1.0],
					"baseColorTexture": {"index": texture_of[texture]},
					"metallicFactor": 0.0,
					"roughnessFactor": 1.0,
				},
			}
		)
		primitives.append(
			{
				"attributes": attributes,
				"indices": accessors.size() - 1,
				"material": materials.size() - 1,
				"mode": 4,
			}
		)
	var document := {
		"asset": {"version": "2.0", "generator": "tt-sim tools/roster/build_folk.gd", "copyright": copyright},
		"extensionsUsed": ["EXT_texture_webp"],
		"extensionsRequired": ["EXT_texture_webp"],
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"name": node_name, "mesh": 0}],
		"meshes": [{"name": node_name, "primitives": primitives}],
		"materials": materials,
		"textures": textures,
		"images": images,
		"accessors": accessors,
		"bufferViews": views,
		"buffers": [{"byteLength": bin.size()}],
	}
	return _container(JSON.stringify(document, "", true).to_utf8_buffer(), bin)


## Writes the constant `<path>.import` sidecar a built-in pack file needs (`importer="keep"`, the
## library Route K: an export then ships the raw bytes the loader reads). Returns success.
static func write_keep_sidecar(path: String) -> bool:
	var file := FileAccess.open(path + ".import", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string('[remap]\n\nimporter="keep"\n')
	file.close()
	return true


static func _container(json: PackedByteArray, bin: PackedByteArray) -> PackedByteArray:
	while json.size() % 4 != 0:
		json.append(0x20)
	while bin.size() % 4 != 0:
		bin.append(0)
	var out := PackedByteArray()
	out.resize(12 + 8 + json.size() + 8 + bin.size())
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, out.size())
	out.encode_u32(12, json.size())
	out.encode_u32(16, 0x4E4F534A)
	for i in json.size():
		out[20 + i] = json[i]
	var at := 20 + json.size()
	out.encode_u32(at, bin.size())
	out.encode_u32(at + 4, 0x004E4942)
	for i in bin.size():
		out[at + 8 + i] = bin[i]
	return out


## Appends `data` to the binary buffer (4-byte aligned) as a buffer view; returns its index.
static func _push(bin: PackedByteArray, views: Array, data: PackedByteArray, target: int) -> int:
	while bin.size() % 4 != 0:
		bin.append(0)
	var view := {"buffer": 0, "byteOffset": bin.size(), "byteLength": data.size()}
	if target != 0:
		view["target"] = target
	bin.append_array(data)
	views.append(view)
	return views.size() - 1


## A float accessor over `floats` (3 or 2 per element); returns its accessor index.
static func _accessor(
	bin: PackedByteArray, views: Array, accessors: Array, floats: PackedFloat32Array, type: String, bounds: bool
) -> int:
	var width := 3 if type == "VEC3" else 2
	var accessor := {
		"bufferView": _push(bin, views, floats.to_byte_array(), _ARRAY_BUFFER),
		"componentType": _FLOAT,
		"count": floats.size() / width,
		"type": type,
	}
	if bounds:
		var low := [INF, INF, INF]
		var high := [-INF, -INF, -INF]
		for i in floats.size():
			low[i % 3] = minf(low[i % 3], floats[i])
			high[i % 3] = maxf(high[i % 3], floats[i])
		accessor["min"] = low
		accessor["max"] = high
	accessors.append(accessor)
	return accessors.size() - 1


static func _vec3(values: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size() * 3)
	for i in values.size():
		out[i * 3] = values[i].x
		out[i * 3 + 1] = values[i].y
		out[i * 3 + 2] = values[i].z
	return out


static func _vec2(values: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size() * 2)
	for i in values.size():
		out[i * 2] = values[i].x
		out[i * 2 + 1] = values[i].y
	return out


## Triangle indices as 16-bit values, each triangle's winding reversed: Godot's front faces are
## clockwise, glTF's are counter-clockwise, and the importer reverses them back.
static func _ushorts(values: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(values.size() * 2)
	for i in values.size():
		var swapped := i - (i % 3) + (3 - i % 3) % 3 if i % 3 != 0 else i
		out.encode_u16(i * 2, values[swapped])
	return out
