extends SceneTree

## Builds the Beasts and Farm Animals pack models (builtin_packs/beasts/models/) from Quaternius's
## CC0 animal downloads. Godot's own readers (FBXDocument for the Farm pack, GLTFDocument for the
## Animals pack) load each source, the build sets the animal's real-world size and feet on y = 0
## on the root node, renames the clips the token animation tree plays, and Godot's glTF exporter
## writes the GLB. No Blender is involved.
##   godot --headless --path <tt-sim> --script res://tools/roster/build_beasts.gd -- \
##     --farm "<dir with the FBX files>" --animals "<dir with the .gltf files>" \
##     --out <tt-sim>/builtin_packs/beasts/models [--only cow]
## The sources are untrusted downloads: extract them outside the project and pass the folders.
## Each model's `importer="keep"` sidecar is written beside it. Sizes are in BeastRecipes.

const BeastRecipes := preload("res://tools/roster/beast_recipes.gd")
const FolkGlb := preload("res://tools/roster/folk_glb.gd")
const SkinnedBounds := preload("res://tools/roster/skinned_bounds.gd")


func _initialize() -> void:
	var folders := {}
	var out := ""
	var only := ""
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1):
		match args[i]:
			"--farm":
				folders["farm"] = args[i + 1].trim_suffix("/")
			"--animals":
				folders["animals"] = args[i + 1].trim_suffix("/")
			"--out":
				out = args[i + 1].trim_suffix("/")
			"--only":
				only = args[i + 1]
	if folders.is_empty() or out == "":
		push_error("usage: -- [--farm <fbx folder>] [--animals <gltf folder>] --out <models> [--only id]")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var failed := 0
	for id in BeastRecipes.ANIMALS:
		var recipe: Dictionary = BeastRecipes.ANIMALS[id]
		if (only != "" and id != only) or not folders.has(recipe["source"]):
			continue
		var ok := _build(id, recipe, folders[recipe["source"]], out)
		failed += 0 if ok else 1
	quit(1 if failed > 0 else 0)


func _build(id: String, recipe: Dictionary, src: String, out: String) -> bool:
	var source: String = src + "/" + String(recipe["file"])
	var root := _read(source)
	if root == null:
		push_error("cannot read " + source)
		return false
	var box := _bounds(root)
	var scale_factor: float = float(recipe["height_m"]) / box.size.y
	root.name = id
	root.scale = Vector3.ONE * scale_factor
	root.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * scale_factor
	var clips := _rename_clips(root)
	var export_doc := GLTFDocument.new()
	var export_state := GLTFState.new()
	export_doc.append_from_scene(root, export_state)
	var path := out + "/" + id + ".glb"
	var written := export_doc.write_to_filesystem(export_state, path) == OK
	var ok := written and FolkGlb.write_keep_sidecar(path)
	var size := FileAccess.get_file_as_bytes(path).size()
	print(
		(
			"BEAST %s ok=%s scale=%.3f source_size=%s bytes=%d clips=%s"
			% [id, ok, scale_factor, box.size, size, clips]
		)
	)
	root.free()
	return ok


## The source scene: an FBX through FBXDocument, a glTF through GLTFDocument.
func _read(path: String) -> Node3D:
	if path.get_extension() == "fbx":
		var fbx := FBXDocument.new()
		var fbx_state := FBXState.new()
		if fbx.append_from_file(path, fbx_state) != OK:
			return null
		return fbx.generate_scene(fbx_state) as Node3D
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## The model's bounds in the root's own space (meshes at rest; the skeleton is not posed).
func _bounds(root: Node3D) -> AABB:
	return SkinnedBounds.of(root)


## Renames the source clips to the names the token animation tree travels to (BeastRecipes.CLIPS)
## and returns the clip names left in the model.
func _rename_clips(root: Node) -> PackedStringArray:
	var names := PackedStringArray()
	for player: AnimationPlayer in root.find_children("*", "AnimationPlayer", true, false):
		var library := player.get_animation_library(&"")
		if library == null:
			continue
		for source_name in library.get_animation_list():
			var target := BeastRecipes.clip_name(String(source_name))
			var animation := library.get_animation(source_name)
			if target == "":
				library.remove_animation(source_name)
				continue
			if target != source_name:
				library.rename_animation(source_name, target)
			# glTF carries no loop flag: the token animation tree loops the idle at run time.
			animation.loop_mode = Animation.LOOP_NONE
		# The tree plays down01_start, then holds down01: the death clip serves as both.
		if library.has_animation(&"down01_start") and not library.has_animation(&"down01"):
			library.add_animation(&"down01", library.get_animation(&"down01_start").duplicate())
		names.append_array(PackedStringArray(Array(library.get_animation_list())))
	return names
