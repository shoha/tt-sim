extends RefCounted

## Render-job probe (`call` op) for the reopened-level darkening (card reopen-dark,
## jobs/reopen_dark.json): dumps the render state that decides how the ground and grass draw,
## so a fresh build and the same map reopened from disk can be compared key by key instead
## of guessed at. `action`:
## - `dump` (`path`): writes a flat JSON object {key: text} of the open level's LevelData, every
##   WorldEnvironment, Light3D, Camera3D and SubViewport in the tree, the global shader
##   parameters, the terrain's chunks, skirt and look bake (node, mesh arrays, materials) and
##   the scatter, folded per mesh path (every distinct value of a key across that path's
##   nodes, the row count and a digest of the rows). Resources are described through their
##   stored properties, a ShaderMaterial's parameters included, a texture by class, size,
##   format, mipmaps and an MD5 of its image data, a mesh by the MD5 (and for normals and
##   colours the mean) of each surface array.
## - `diff` (`a`, `b`, `path`): writes every key whose text differs between two dumps (or that
##   only one holds) to `path`, and returns the count per key prefix.
## - `save` (`folder`, must start with PREFIX): writes the open map as that test level,
##   replacing an earlier one (the authoring save path, as ground_parity.gd's `save`).
## - `cleanup`: deletes every level folder starting with PREFIX, and nothing else.

const PREFIX := "_reopen_"
const MAX_DEPTH := 4
## Scatter node keys that differ per node by design (placement), left out of the fold.
const PER_NODE := ["transform", "multimesh/buffer", "multimesh/instance_count", "name"]

static var _auto_name := RegEx.create_from_string("@[A-Za-z0-9_]+@\\d+")


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"dump":
			return _dump(base, String(step.get("path", "")))
		"diff":
			return _diff(String(step.get("a", "")), String(step.get("b", "")), String(step.get("path", "")))
		"save":
			return _save(base, String(step.get("folder", "")))
		"cleanup":
			return _cleanup()
		"reprobe":
			return _reprobe(base, String(step.get("mode", "always")) == "always")
	return "unknown action %s" % step.get("action", "")


## Bisection: every ReflectionProbe in the tree to UPDATE_ALWAYS (`mode` "always", so it
## captures the scene as it stands now) or back to UPDATE_ONCE (`mode` "once").
static func _reprobe(base: Node, always: bool) -> String:
	var lines := PackedStringArray()
	for node in base.get_tree().root.find_children("*", "ReflectionProbe", true, false):
		var probe := node as ReflectionProbe
		probe.update_mode = (
			ReflectionProbe.UPDATE_ALWAYS if always else ReflectionProbe.UPDATE_ONCE
		)
		lines.append("%s at %s size %s" % [probe.name, str(probe.global_position), str(probe.size)])
	return "%s: %s" % ["always" if always else "once", ", ".join(lines)]


static func _dump(base: Node, path: String) -> String:
	var out := {}
	var seen := {}
	var root := base.get_tree().root
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl != null and ctrl.level != null:
		_describe(ctrl.level, "level", out, seen, 0)
	for cls in [
		"WorldEnvironment",
		"Light3D",
		"Camera3D",
		"SubViewport",
		"ReflectionProbe",
		"VoxelGI",
		"LightmapGI",
		"Decal",
		"FogVolume",
	]:
		for node in root.find_children("*", cls, true, false):
			var key := "%s:%s" % [cls, _rel(root, node)]
			_describe(node, key, out, seen, 0)
			if node is Node3D:
				out[key + "/global_transform"] = str((node as Node3D).global_transform)
			if node is Camera3D:
				out[key + "/current"] = str((node as Camera3D).current)
	for name: StringName in RenderingServer.global_shader_parameter_get_list():
		out["global:%s" % name] = _text(RenderingServer.global_shader_parameter_get(name))
	var terrain: Node = null
	if ctrl != null and ctrl.editor != null:
		terrain = ctrl.editor.terrain
	if terrain != null:
		_save_bake(terrain, path)
		for cls in ["MeshInstance3D", "SubViewport", "ColorRect"]:
			for node in terrain.find_children("*", cls, true, false):
				_describe(node, "terrain:%s" % _rel(terrain, node), out, seen, 0)
	_fold_scatter(base, out, seen)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s" % path
	file.store_string(JSON.stringify(out, "\t", true))
	file.close()
	return "dumped %d keys to %s" % [out.size(), path]


## Saves the ground look's slot 0 bake beside the dump: `<path>.bake_rgb.png` and its alpha as
## grey in `<path>.bake_a.png`, so two dumps' bakes can be compared with parity_diff.gd.
static func _save_bake(terrain: Node, path: String) -> void:
	var vp := terrain.get_node_or_null("GroundLookBake/LookBake0") as SubViewport
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var alpha := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			alpha.set_pixel(x, y, Color(a, a, a))
	var rgb := img.duplicate() as Image
	rgb.convert(Image.FORMAT_RGB8)
	rgb.save_png(path + ".bake_rgb.png")
	alpha.save_png(path + ".bake_a.png")


## Every scatter MultiMeshInstance3D under the map, folded per mesh path: each key holds the
## distinct values its nodes carry (joined by " | "), plus the node and row counts and an MD5
## over the sorted per-node row digests.
static func _fold_scatter(base: Node, out: Dictionary, seen: Dictionary) -> void:
	var gm: GameMap = base.get("_game_map")
	if gm == null or gm.map_container == null:
		return
	var folds := {}
	for node in gm.map_container.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh == null or String(mmi.name).contains("PipelineWarm"):
			continue
		var group := "scatter:%s" % String(mmi.name).get_slice("_MultiMesh", 0)
		var own := {}
		_describe(mmi, "", own, seen, 0)
		out["scatter_rows:%s" % mmi.name] = (
			"%d %s" % [mmi.multimesh.instance_count, own.get("/multimesh/buffer", "")]
		)
		var fold: Dictionary = folds.get(group, {"nodes": 0, "rows": 0, "digests": [], "keys": {}})
		fold.nodes += 1
		fold.rows += mmi.multimesh.instance_count
		fold.digests.append(own.get("/multimesh/buffer", ""))
		for key: String in own:
			if key.trim_prefix("/") in PER_NODE:
				continue
			var values: Dictionary = fold["keys"].get(key, {})
			values[own[key]] = true
			fold["keys"][key] = values
		folds[group] = fold
	for group: String in folds:
		var fold: Dictionary = folds[group]
		var digests: Array = fold.digests
		digests.sort()
		out[group + "/nodes"] = str(fold.nodes)
		out[group + "/rows"] = str(fold.rows)
		out[group + "/rows_md5"] = str(digests).md5_text()
		for key: String in fold["keys"]:
			var values: Array = (fold["keys"][key] as Dictionary).keys()
			values.sort()
			out[group + key] = " | ".join(PackedStringArray(values))


static func _rel(from: Node, node: Node) -> String:
	return _auto_name.sub(str(from.get_path_to(node)), "@", true)


## The stored properties of `obj` under `prefix`, resources described in place.
static func _describe(
	obj: Object, prefix: String, out: Dictionary, seen: Dictionary, depth: int
) -> void:
	for p: Dictionary in obj.get_property_list():
		if not int(p.usage) & PROPERTY_USAGE_STORAGE:
			continue
		var name := String(p.name)
		if name == "script" and obj is Node:
			continue
		_value(obj.get(name), "%s/%s" % [prefix, name], out, seen, depth)


static func _value(v: Variant, key: String, out: Dictionary, seen: Dictionary, depth: int) -> void:
	if v is Node:
		out[key] = "node %s" % (v as Node).name
	elif v is Texture2D or v is TextureLayered:
		out[key] = _texture(v as Texture, seen)
	elif v is Shader:
		var shader := v as Shader
		out[key] = "Shader %s code md5 %s" % [shader.resource_path, shader.code.md5_text()]
	elif v is Mesh:
		_mesh(v as Mesh, key, out, seen, depth)
	elif v is Resource:
		var res := v as Resource
		out[key] = "%s %s" % [res.get_class(), res.resource_path]
		var id := "obj%d" % res.get_instance_id()
		if depth < MAX_DEPTH and not seen.has(id):
			seen[id] = true
			_describe(res, key, out, seen, depth + 1)
			seen.erase(id)
	else:
		out[key] = _text(v)


static func _text(v: Variant) -> String:
	match typeof(v):
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
		TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, \
		TYPE_PACKED_STRING_ARRAY:
			if v.size() <= 16:
				return "%s %s" % [type_string(typeof(v)), str(v)]
			return "%s n %d md5 %s" % [type_string(typeof(v)), v.size(), _md5(var_to_bytes(v))]
		TYPE_ARRAY, TYPE_DICTIONARY:
			var text := str(v)
			if text.length() <= 400:
				return text
			return "%s n %d md5 %s" % [type_string(typeof(v)), v.size(), text.md5_text()]
		TYPE_FLOAT:
			return var_to_str(v)
	return "%s %s" % [type_string(typeof(v)), str(v)]


static func _md5(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


## Class, path, size, format, mipmaps and an MD5 of the image data (each layer's for a
## layered texture), read back once per texture.
static func _texture(tex: Texture, seen: Dictionary) -> String:
	var id := "tex%d" % tex.get_rid().get_id()
	if seen.has(id):
		return seen[id]
	var text := "%s %s" % [tex.get_class(), tex.resource_path]
	if tex is Texture2D:
		var img := (tex as Texture2D).get_image()
		text += " size %s" % str((tex as Texture2D).get_size())
		if img != null:
			text += (
				" fmt %d mips %s md5 %s"
				% [img.get_format(), str(img.has_mipmaps()), _md5(img.get_data())]
			)
	elif tex is TextureLayered:
		var layered := tex as TextureLayered
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_MD5)
		for i in layered.get_layers():
			var img := layered.get_layer_data(i)
			if img != null:
				hashing.update(img.get_data())
		text += (
			" layers %d %dx%d fmt %d mips %s md5 %s"
			% [
				layered.get_layers(),
				layered.get_width(),
				layered.get_height(),
				layered.get_format(),
				str(layered.has_mipmaps()),
				hashing.finish().hex_encode(),
			]
		)
	seen[id] = text
	return text


## A mesh by class, path and AABB, then per surface the MD5 of each array (with the mean of
## the normals and colours, so a change in shading shows its direction) and its material.
static func _mesh(mesh: Mesh, key: String, out: Dictionary, seen: Dictionary, depth: int) -> void:
	var id := "mesh%d" % mesh.get_instance_id()
	if not seen.has(id):
		var own := {}
		_mesh_arrays(mesh, "", own, seen, depth)
		seen[id] = own
	var cached: Dictionary = seen[id]
	for suffix: String in cached:
		out[key + suffix] = cached[suffix]


static func _mesh_arrays(
	mesh: Mesh, key: String, out: Dictionary, seen: Dictionary, depth: int
) -> void:
	out[key] = "%s %s aabb %s" % [mesh.get_class(), mesh.resource_path, str(mesh.get_aabb())]
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		for a in arrays.size():
			if arrays[a] == null:
				continue
			var text := _text(arrays[a])
			if a == Mesh.ARRAY_NORMAL and arrays[a] is PackedVector3Array:
				var sum := Vector3.ZERO
				for n: Vector3 in arrays[a]:
					sum += n
				text += " mean %s" % str(sum / maxi(1, arrays[a].size()))
			elif a == Mesh.ARRAY_COLOR and arrays[a] is PackedColorArray:
				var csum := Vector4.ZERO
				for c: Color in arrays[a]:
					csum += Vector4(c.r, c.g, c.b, c.a)
				text += " mean %s" % str(csum / maxi(1, arrays[a].size()))
			out["%s/surface%d/array%d" % [key, s, a]] = text
		if mesh is ArrayMesh:
			out["%s/surface%d/format" % [key, s]] = str((mesh as ArrayMesh).surface_get_format(s))
		_value(mesh.surface_get_material(s), "%s/surface%d/material" % [key, s], out, seen, depth)


static func _diff(a_path: String, b_path: String, path: String) -> String:
	var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(a_path))
	var b: Variant = JSON.parse_string(FileAccess.get_file_as_string(b_path))
	if not a is Dictionary or not b is Dictionary:
		return "cannot read %s or %s" % [a_path, b_path]
	var keys := {}
	for k: String in a:
		keys[k] = true
	for k: String in b:
		keys[k] = true
	var sorted := keys.keys()
	sorted.sort()
	var lines := PackedStringArray()
	var counts := {}
	for k: String in sorted:
		var va := String(a.get(k, "<absent>"))
		var vb := String(b.get(k, "<absent>"))
		if va == vb:
			continue
		lines.append("%s\n  A %s\n  B %s" % [k, va, vb])
		var group := k.get_slice("/", 0)
		counts[group] = int(counts.get(group, 0)) + 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines))
		file.close()
	return "%d keys differ of %d (%s) -> %s" % [lines.size(), sorted.size(), str(counts), path]


static func _save(base: Node, folder: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [folder, str(ok)]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			if not LevelManager.delete_level_folder(LevelManager.folder_path(folder)):
				_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
