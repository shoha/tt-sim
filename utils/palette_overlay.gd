class_name PaletteOverlay
extends RefCounted

## A built treecube palette package laid over a loaded palette for one run, so a species
## capture round needs no merge into assets/palette and no editor import, and lanes with
## different packages can share one checkout (PaletteLibrary.overlay_package applies it to
## its caches; the render-job op `palette_overlay` calls that). The package is a
## build_palette.py output folder anywhere on disk: palette.json plus assets/<biome>/*.glb.
##
## Each package biome (or each one `only` names) replaces the palette's biome of that id, or
## is appended, together with all of its assets: the palette's assets under "<biome>/" go and
## the package's come in. An asset whose GLB is byte-identical to the one under the palette
## root keeps the root's own load path (for res://, the editor-imported mesh), so an unchanged
## species renders exactly as the installed palette draws it. Only the GLBs whose bytes
## differ are parsed here, through GLTFDocument with mesh compression off, and then each
## surface is compressed where the installed version of the same asset has that surface
## compressed (compressed_like). The editor import compresses vertex attributes on some
## surfaces only (a 12-vertex carpet flower yes, a 120-vertex bellflower no) and the runtime
## parse compresses all or none, so following the installed asset is how a changed asset
## draws as its import would; a new asset stays uncompressed, as the bellflowers' imports
## were (lookbench capture probe and backend card, 2026-10-20). Vertex order still differs
## from the import's, which drew no different pixel there.
##
## Surfaces, thumbnails and the palette version stay the installed palette's: a species
## round changes plants, not ground. read() reads files but touches no cache.

## GLTFDocument.append_from_buffer's flag for EditorSceneFormatImporter's
## IMPORT_FORCE_DISABLE_MESH_COMPRESSION (an editor-only enum, so the value is written out).
const FORCE_DISABLE_COMPRESSION := 64


## The palette `base` (validated, as PaletteLibrary.get_palette(root) holds it) with the
## package at `package` laid over it. Returns {"ok", "error", "palette" (a new Dictionary;
## `base` is left as it was), "meshes" (asset id -> parsed Mesh, or null when the parse
## failed), "dropped" (every asset id whose cached mesh is now stale: the overlaid biomes'
## old and new ids), "biomes", "parsed", "kept", "failed" (asset ids), "warnings" (the
## package's validation warnings), "msec"}. A package with no readable palette.json, or none
## of the biomes asked for, is not ok and returns `base` unchanged.
static func read(package: String, base: Dictionary, root: String, only: Array = []) -> Dictionary:
	var started := Time.get_ticks_usec()
	var report := _new_report(base)
	var path := package.path_join(PaletteLibrary.PALETTE_FILE)
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if text == "":
		report["error"] = "no readable %s" % path
		return report
	var result := PaletteLibrary.validate_palette(JSON.parse_string(text))
	report["warnings"] = result["warnings"]
	return _merge(result["palette"], package, base, root, only, report, path, started)


## read() for a package palette that is already in memory: `raw` is a palette.json-shaped
## Dictionary (LibraryRegistry's compiled library), validated here, and `package` is the folder
## its asset `file` values are relative to. The same report, the same merge rule.
static func read_palette(
	raw: Dictionary, package: String, base: Dictionary, root: String, only: Array = []
) -> Dictionary:
	var started := Time.get_ticks_usec()
	var report := _new_report(base)
	var result := PaletteLibrary.validate_palette(raw)
	report["warnings"] = result["warnings"]
	var merged := _merge(result["palette"], package, base, root, only, report, package, started)
	if merged["ok"]:
		# A library brings its own surfaces (SurfaceStore resolves their paths); the table it
		# compiled holds the base's too, unchanged, so the merge adds only what is new.
		var palette: Dictionary = merged["palette"]
		var surfaces: Dictionary = (base["surfaces"] as Dictionary).duplicate()
		surfaces.merge(result["palette"]["surfaces"], true)
		palette["surfaces"] = surfaces
	return merged


static func _new_report(base: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error": "",
		"palette": base,
		"meshes": {},
		"dropped": [],
		"biomes": [],
		"parsed": [],
		"kept": [],
		"failed": [],
		"warnings": [],
		"msec": 0.0,
	}


## The shared merge of read() and read_palette(): each biome of `pkg` (validated) replaces the
## base's biome of that id with all its "<id>/" assets. `source` names the origin in errors.
static func _merge(
	pkg: Dictionary,
	package: String,
	base: Dictionary,
	root: String,
	only: Array,
	report: Dictionary,
	source: String,
	started: int
) -> Dictionary:
	var path := source
	var biomes: Array = (base["biomes"] as Array).duplicate()
	var assets: Dictionary = (base["assets"] as Dictionary).duplicate()
	for biome: Dictionary in pkg["biomes"]:
		var id := String(biome["id"])
		if not only.is_empty() and not only.has(id):
			continue
		var at := biomes.find_custom(func(b: Dictionary) -> bool: return b["id"] == id)
		if at < 0:
			biomes.append(biome)
		else:
			biomes[at] = biome
		report["biomes"].append(id)
		for key: String in assets.keys():
			if key.begins_with(id + "/"):
				assets.erase(key)
				report["dropped"].append(key)
		for key: String in pkg["assets"]:
			if key.begins_with(id + "/"):
				_overlay_asset(key, pkg["assets"][key], package, root, assets, report)
	if (report["biomes"] as Array).is_empty():
		report["error"] = "%s has none of the biomes %s" % [path, str(only)]
		return report
	var palette := base.duplicate()
	palette["biomes"] = biomes
	palette["assets"] = assets
	report["palette"] = palette
	report["ok"] = true
	report["msec"] = (Time.get_ticks_usec() - started) / 1000.0
	return report


## Adds one package asset to `assets`, and to the report as kept (byte-identical under
## `root`) or parsed (its mesh in report.meshes) or failed.
static func _overlay_asset(
	key: String,
	entry: Dictionary,
	package: String,
	root: String,
	assets: Dictionary,
	report: Dictionary,
) -> void:
	assets[key] = entry
	if not (report["dropped"] as Array).has(key):
		report["dropped"].append(key)
	var file := String(entry["file"])
	if same_bytes(root.path_join(file), package.path_join(file)):
		report["kept"].append(key)
		return
	var node_name := String(entry["node"])
	var mesh := parse_mesh(package.path_join(file), node_name)
	if mesh is ArrayMesh:
		var installed := PaletteAssetFiles.load_mesh(root.path_join(file), node_name)
		mesh = compressed_like(mesh as ArrayMesh, installed as ArrayMesh)
	report["meshes"][key] = mesh
	report["failed" if mesh == null else "parsed"].append(key)


## Whether files `a` and `b` both exist with the same bytes. An exported game ships no raw
## res:// GLB, so there every package asset counts as changed and is parsed.
static func same_bytes(a: String, b: String) -> bool:
	if not FileAccess.file_exists(a) or not FileAccess.file_exists(b):
		return false
	return FileAccess.get_sha256(a) == FileAccess.get_sha256(b)


## `mesh` (uncompressed) with each surface compressed whose counterpart in `like` is: a new
## ArrayMesh with the same arrays, materials and names, or `mesh` itself when `like` is null
## or compresses nothing. Blend shapes and LODs are not carried (palette assets have none).
static func compressed_like(mesh: ArrayMesh, like: ArrayMesh) -> ArrayMesh:
	if like == null:
		return mesh
	var compress: Array[bool] = []
	for s in mesh.get_surface_count():
		compress.append(
			(
				s < like.get_surface_count()
				and (like.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0
			)
		)
	if not compress.has(true):
		return mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var flags := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES if compress[s] else 0
		out.add_surface_from_arrays(
			mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {}, flags
		)
		out.surface_set_material(s, mesh.surface_get_material(s))
		out.surface_set_name(s, mesh.surface_get_name(s))
	return out


## The Mesh of node `node_name` in the GLB at `path`, parsed with mesh compression off, or
## null for a missing, oversized or unparseable file or a missing node.
static func parse_mesh(path: String, node_name: String) -> Mesh:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > PaletteLibrary.MAX_ASSET_FILE_BYTES:
		return null
	var buffer := file.get_buffer(file.get_length())
	file.close()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var flags := FORCE_DISABLE_COMPRESSION
	if document.append_from_buffer(buffer, path.get_base_dir(), state, flags) != OK:
		return null
	var scene := document.generate_scene(state)
	if scene == null:
		return null
	var node := GlbUtils.find_node_by_name(scene, node_name)
	if node == null:
		node = GlbUtils.find_node_by_name(scene, node_name.validate_node_name())
	var mesh: Mesh = (node as MeshInstance3D).mesh if node is MeshInstance3D else null
	scene.free()
	return mesh
