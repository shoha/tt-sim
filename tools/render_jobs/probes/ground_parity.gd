extends RefCounted

## Render-job probe (`call` op) for the ground ship's parity check (card 3c,
## jobs/ground_parity.json): view controls only. Nothing here sets a ground or grass uniform;
## the look comes from the palette through the game's own code. `action`:
## - `nocursor`: hides the authoring brush cursor and drops its pointer, so no capture shows it
##   (round 20's ground1.gd `nocursor` and ground2b.gd `nopointer` together).
## - `only` (`prefix`): shows only the scatter MultiMeshInstance3D nodes whose name, mesh path
##   or mesh name contains `prefix` ("Grass_" for the grass alone, "NOSCATTER_" for none);
##   `all` shows every one again. Round 20's `only` / `all`.
## - `freeze`: stops the shader clock and sets it to (near) 0: Engine.time_scale 0 and, for the
##   frames until `thaw`, a time rollover of 1e-6 s, so the next frame's TIME is under 1e-6 in
##   every run. Swaying blades then hold the same pose in two runs, and the lo-fi grain the same
##   pattern. The driver's `wait` runs on scaled time: `thaw` before any wait.
## - `thaw`: restores the rollover and time scale 1.
## - `save` (`folder`, must start with one of PREFIXES): writes the open map as that test level,
##   replacing an earlier one (the authoring save path, mass anchors included).
## - `cleanup`: deletes every level folder starting with one of PREFIXES (and the card 4 level
##   main's build saved under MAIN_SAVED, when `adopt` never ran), and nothing else.
## - `report`: the scatter's MultiMesh nodes, how many carry custom data (the massed grass, its
##   anchors), and whether the terrain material has a ground look.
## - `adopt` (`from`, `to`; card 4): renames a level main's build saved through its own
##   events_pane.gd probe (whose prefix is `_gm_events_`; `from` must be MAIN_SAVED) to `to`
##   (a `_gship4_` folder), so this probe's cleanup owns it.
## - `import_glb` (`path`, `name`, a `_gship4_` name; card 4): starts MapImport.import_glb, a
##   coroutine: follow it with a wait.
## - `rows` (card 4): the open document's scatter rows (all, and the assets named Grass_) with
##   an MD5 of the grass rows, beside the same read back from the level's saved map.ttmap, and
##   the live MultiMesh rows: an older level whose open regrew nothing shows them all equal.

const PREFIXES := ["_gship3c_", "_gship4_"]
const MAIN_SAVED := "_gm_events_gship4_old"
const ROLLOVER := "rendering/limits/time/time_rollover_secs"

static var _rollover: Variant = null


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"nocursor":
			return _no_cursor(base)
		"only":
			return _show(base, String(step.get("prefix", "")))
		"all":
			return _show(base, "")
		"freeze":
			if _rollover == null:
				_rollover = ProjectSettings.get_setting(ROLLOVER, 3600.0)
			Engine.time_scale = 0.0
			ProjectSettings.set_setting(ROLLOVER, 1e-6)
			return "shader clock frozen near 0"
		"thaw":
			if _rollover != null:
				ProjectSettings.set_setting(ROLLOVER, _rollover)
			Engine.time_scale = 1.0
			return "shader clock running (rollover %s)" % str(_rollover)
		"save":
			return _save(base, String(step.get("folder", "")))
		"cleanup":
			return _cleanup()
		"report":
			return _report(base)
		"adopt":
			return _adopt(String(step.get("from", "")), String(step.get("to", "")))
		"import_glb":
			return _import_glb(base, String(step.get("path", "")), String(step.get("name", "")))
		"rows":
			return _rows(base)
		"uniforms":
			return _uniforms(base, step)
	return "unknown action %s" % step.get("action", "")


## Diagnosis: the uniforms the game set, beside a round 20 job's `field` params (`ref`: a
## job JSON, `index`: the step holding them). Logs every bake and grass-tuft uniform whose
## name the job also set and whose value differs, the ground's slot-0 look vectors, and saves
## slot 0's bake texture to `png` when given.
static func _uniforms(base: Node, step: Dictionary) -> String:
	var c: AuthoringController = base.get("_authoring_controller")
	if c == null or c.editor == null or c.editor.terrain == null:
		return "no terrain"
	var job: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(step.get("ref"))))
	var field: Dictionary = job.steps[int(step.get("index", 0))].params
	var bake := c.editor.terrain.get_node_or_null("GroundLookBake")
	if bake == null:
		return "no GroundLookBake"
	var vp := bake.get_node("LookBake0") as SubViewport
	var bake_mat := (vp.get_node("Rect") as ColorRect).material as ShaderMaterial
	var lines := PackedStringArray()
	lines.append(
		(
			"bake px %s, bakes %s, sun %s, seed_m %s, rect %s, viewport children %d"
			% [
				str(vp.size),
				str(bake.get("bakes")),
				str(bake.get("_sun_dir")),
				str(bake.get("_seed_m")),
				str(bake.get("_rect")),
				vp.get_child_count(),
			]
		)
	)
	for child in vp.get_children():
		var count := child.get_child_count()
		if child is MultiMeshInstance2D and (child as MultiMeshInstance2D).multimesh:
			count = (child as MultiMeshInstance2D).multimesh.instance_count
		lines.append("  %s (%s): %d" % [child.name, child.get_class(), count])
	lines.append("bake: " + _mismatch(bake_mat, field))
	var grass: ShaderMaterial = null
	for m in bake.get("_grass_bound"):
		grass = m
		break
	lines.append("grass: " + (_mismatch(grass, field) if grass else "none bound"))
	if grass:
		lines.append(
			(
				"grass zone_tuft_ref %s, lit_dir %s, bound %d"
				% [
					str(grass.get_shader_parameter("zone_tuft_ref")),
					str(grass.get_shader_parameter("zone_mass_lit_dir")),
					(bake.get("_grass_bound") as Array).size(),
				]
			)
		)
	var mat := c.editor.terrain.get_material()
	for key in ["look_light", "look_ref", "look_brush", "look_shape", "look_rim", "look_rim_more"]:
		var arr: Variant = mat.get_shader_parameter(key)
		var first: Variant = arr[0] if arr != null and arr.size() > 0 else null
		lines.append("%s[0] %s (%s)" % [key, str(first), type_string(typeof(arr))])
	lines.append("look_rect %s" % str(mat.get_shader_parameter("look_rect")))
	var rows: Variant = mat.get_shader_parameter("look_row_slots")
	var layers: Variant = mat.get_shader_parameter("look_layer_slots")
	lines.append(
		(
			"look_row_slots %s, look_layer_slots %s, biome_ids %s, biome_present %s, rows %s"
			% [
				str(Array(rows).slice(0, 8)) if rows != null else "null",
				str(Array(layers).slice(0, 12)) if layers != null else "null",
				str(c.document.biome_ids),
				str(mat.get_shader_parameter("biome_present")),
				# Through the node's script, so this probe also compiles on a tree without it.
				str(
					bake.get_script().call(
						"rows_of",
						c.document,
						c.editor.terrain.layer_binding(),
						PaletteLibrary.DEFAULT_ROOT
					)
				),
			]
		)
	)
	if step.has("png"):
		vp.get_texture().get_image().save_png(String(step.png))
	return "\n".join(lines)


static func _mismatch(mat: ShaderMaterial, field: Dictionary) -> String:
	var names := {}
	for u in mat.shader.get_shader_uniform_list():
		names[u.name] = true
	var same := 0
	var out := PackedStringArray()
	for key: String in field:
		if not names.has(key):
			continue
		var want: Variant = field[key]
		var have: Variant = mat.get_shader_parameter(key)
		var a := PackedFloat64Array(want if want is Array else [want])
		var b := PackedFloat64Array()
		if have is Vector3:
			b = PackedFloat64Array([have.x, have.y, have.z])
		elif have is Vector2:
			b = PackedFloat64Array([have.x, have.y])
		elif have is float or have is int or have is bool:
			b = PackedFloat64Array([float(have)])
		var ok := a.size() == b.size()
		for i in mini(a.size(), b.size()):
			ok = ok and absf(a[i] - b[i]) < 1e-4
		if ok:
			same += 1
		else:
			out.append("%s want %s have %s" % [key, str(want), str(have)])
	return "%d equal; differ: %s" % [same, ", ".join(out)]


static func _no_cursor(base: Node) -> String:
	var c: AuthoringController = base.get("_authoring_controller")
	if c == null or c.brush == null:
		return "no brush"
	c.brush.cursor.set_visible(false)
	c.brush.has_pointer = false
	c.brush.redraw()
	return "brush cursor hidden, pointer off"


static func _scatter_nodes(base: Node) -> Array[MultiMeshInstance3D]:
	var gm: GameMap = base.get("_game_map")
	var out: Array[MultiMeshInstance3D] = []
	for node in gm.map_container.find_children("*", "MultiMeshInstance3D", true, false):
		if not String(node.name).contains("PipelineWarm"):
			out.append(node as MultiMeshInstance3D)
	return out


static func _label(mmi: MultiMeshInstance3D) -> String:
	var label := String(mmi.name)
	if mmi.multimesh != null and mmi.multimesh.mesh != null:
		label += " " + mmi.multimesh.mesh.resource_path + " " + mmi.multimesh.mesh.resource_name
	return label


static func _show(base: Node, prefix: String) -> String:
	var shown := 0
	var hidden := 0
	for mmi in _scatter_nodes(base):
		mmi.visible = prefix == "" or _label(mmi).contains(prefix)
		shown += 1 if mmi.visible else 0
		hidden += 0 if mmi.visible else 1
	return "scatter shown %d hidden %d (prefix '%s')" % [shown, hidden, prefix]


static func _report(base: Node) -> String:
	var nodes := 0
	var custom := 0
	var rows := 0
	var custom_rows := 0
	for mmi in _scatter_nodes(base):
		if mmi.multimesh == null:
			continue
		nodes += 1
		rows += mmi.multimesh.instance_count
		if mmi.multimesh.use_custom_data:
			custom += 1
			custom_rows += mmi.multimesh.instance_count
	var look := "no terrain"
	var c: AuthoringController = base.get("_authoring_controller")
	if c != null and c.editor != null and c.editor.terrain != null:
		var mat: ShaderMaterial = c.editor.terrain.get_material()
		look = "look_present %s" % str(mat.get_shader_parameter("look_present")) if mat else "no material"
	return (
		"scatter nodes %d (%d rows), custom data on %d (%d rows); %s"
		% [nodes, rows, custom, custom_rows, look]
	)


static func _save(base: Node, folder: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not _is_test(folder):
		return "no authoring controller, or not a %s folder" % str(PREFIXES)
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	var anchors: Variant = ctrl.document.get("mass_anchors")
	var count := (anchors as Dictionary).size() if anchors is Dictionary else -1
	return "saved %s: %s (mass_anchors entries %d)" % [folder, str(ok), count]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if _is_test(folder) or folder == MAIN_SAVED:
			# delete_level_folder also forgets an imported level's source.
			if not LevelManager.delete_level_folder(LevelManager.folder_path(folder)):
				_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	var index := ConfigFile.new()
	if index.load(ImportSources.path) == OK and index.get_sections().is_empty():
		DirAccess.remove_absolute(ImportSources.path)
	return "removed %s" % str(removed)


static func _is_test(folder: String) -> bool:
	for prefix: String in PREFIXES:
		if folder.begins_with(prefix):
			return true
	return false


static func _adopt(from: String, to: String) -> String:
	if from != MAIN_SAVED or not to.begins_with("_gship4_"):
		return "refused: from must be %s and to a _gship4_ folder" % MAIN_SAVED
	var source := LevelManager.folder_path(from)
	if not DirAccess.dir_exists_absolute(source):
		return "no %s" % from
	_remove_tree(LevelManager.folder_path(to))
	var err := DirAccess.rename_absolute(source, LevelManager.folder_path(to))
	return "adopted %s as %s: %s" % [from, to, error_string(err)]


static func _import_glb(base: Node, path: String, level_name: String) -> String:
	if not Paths.sanitize_level_name(level_name).begins_with("_gship4_"):
		return "refused: the name must start with _gship4_"
	_run_import(path, level_name, base.get_tree())
	return "import of %s as %s started" % [path, level_name]


static func _run_import(path: String, level_name: String, tree: SceneTree) -> void:
	var result: Dictionary = await MapImport.import_glb(path, level_name, tree)
	print("RJ| import_glb result ok %s folder %s error '%s'" % [
		str(result.get("ok")), result.get("folder", ""), result.get("error", "")
	])


static func _rows(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.document == null or ctrl.level == null:
		return "no open document"
	var saved_path := LevelManager.folder_path(ctrl.level.level_folder).path_join("map.ttmap")
	var saved: MapDocument = MapDocumentIO.read(saved_path).get("document")
	var live := 0
	for mmi in _scatter_nodes(base):
		live += mmi.multimesh.instance_count if mmi.multimesh != null else 0
	return (
		"open %s; saved %s; live MultiMesh rows %d; anchors %d"
		% [
			_rows_digest(ctrl.document.scatter),
			_rows_digest(saved.scatter) if saved != null else "unreadable",
			live,
			ctrl.document.mass_anchors.size(),
		]
	)


static func _rows_digest(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	var grass := 0
	var ids := rows_by_asset.keys()
	ids.sort()
	for asset_id: String in ids:
		if asset_id.contains("/Grass_"):
			grass += rows_by_asset[asset_id].size() / MapDocument.ROW_STRIDE
			hashing.update(rows_by_asset[asset_id].to_byte_array())
	return (
		"rows %d, grass %d md5 %s"
		% [MapDocument.row_count(rows_by_asset), grass, hashing.finish().hex_encode().left(12)]
	)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
