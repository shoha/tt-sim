class_name PaletteAssetFiles
extends RefCounted

## Loads the Mesh of an asset GLB for PaletteLibrary (split out of it in step S2 of the
## content library): the imported PackedScene for the built-in res:// palette, a runtime
## GLTFDocument parse for a user:// palette or a test fixture. Stateless; the caching is
## PaletteLibrary's.

const MAX_ASSET_FILE_BYTES := 64 * 1024 * 1024


## Loads the Mesh of node `node_name` from an asset GLB. The built-in res:// palette goes
## through Godot's editor import (ResourceLoader on the imported PackedScene): an
## exported game ships only the imported .scn, never the raw .glb, so FileAccess finds
## nothing there. Its import settings (committed .glb.import sidecars: textures embedded
## uncompressed, no LODs, no shadow meshes) and the evidence for them are in
## docs/ASSET_PIPELINE.md section 9 "Import path". A GLB with no import (a user:// palette,
## the unit-test fixture) is parsed at runtime through GLTFDocument instead, the path
## GlbUtils uses for user:// maps. Both give the same materials, vertex colours and
## unmipmapped textures, but not the same vertex buffers: the import compresses the vertex
## attributes of some surfaces and reorders every surface's vertices, while this parse
## compresses every surface (lookbench capture probe, 2026-10-20). So the two paths draw
## alike to the eye but not bit for bit (PaletteOverlay parses with compression off, which
## comes closest).
##
## Returns null (the caller warns) for a missing, oversized or unparseable file or a
## missing node. Treecube exports the asset node at the identity transform; one that is
## not would be placed without that offset, since only its Mesh is used, so it warns.
static func load_mesh(path: String, node_name: String) -> Mesh:
	var scene := load_scene(path)
	if scene == null:
		return null
	var node := GlbUtils.find_node_by_name(scene, node_name)
	if node == null:
		node = GlbUtils.find_node_by_name(scene, node_name.validate_node_name())
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
		if (node as Node3D).transform != Transform3D.IDENTITY:
			push_warning("PaletteLibrary: node '%s' in %s is not at the origin" % [node_name, path])
	scene.free()
	return mesh


## The instantiated scene of an asset GLB (the caller frees it), or null. Imported
## resources win over the raw file so the editor exercises the same path as an export.
static func load_scene(path: String) -> Node:
	if ResourceLoader.exists(path, "PackedScene"):
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		return packed.instantiate() if packed != null else null
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_ASSET_FILE_BYTES:
		return null
	var buffer := file.get_buffer(file.get_length())
	file.close()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(buffer, "", state) != OK:
		return null
	return document.generate_scene(state)
