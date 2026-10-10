extends RefCounted

## Render-job probe for the map-size measurement (see README.md). step.action picks:
##   dump {name}     writes the open authoring document (scatter and props synced from the
##                   scene, as a save does) to user://_msize_/<name>.ttmap through
##                   MapDocumentIO.write, the same path a level save takes
##   fill            paints the first biome at density 255 over every sample and regenerates
##                   the whole scatter (a dense forest everywhere the ground allows)
##   paint           paints every sample with two of eight ground-role surfaces whose weights
##                   sum to 255, in soft noise patches (full ground paint: no automatic
##                   ground left), and refreshes the ground as an edit does
##   mark {name}     remembers the time now under `name`
##   since {name}    logs the milliseconds since that mark (pair with wait_ready to time a
##                   regeneration)
##   save {folder}   saves the open map as a level, only into a user://levels/_psize_* folder
##                   (replacing it); cleanup.gd deletes those
## Never writes under user://levels/ except a _psize_ folder.

const OUT_DIR := "user://_msize_"
const LEVEL_PREFIX := "_psize_"
## Ground-role palette surfaces (none suppresses plants as a built path would).
const PAINT_SURFACES: Array[String] = [
	"forest_floor", "moss", "pine_duff", "dirt", "dirt_peat", "grass", "grass_alpine", "mud"
]
## Feature size of the paint patches, metres: about a brush stroke's width.
const PAINT_FEATURE_M := 6.0


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var action := String(step.get("action", "dump"))
	match action:
		"mark":
			Engine.set_meta(_meta_key(step), Time.get_ticks_usec())
			return "mark %s" % step.get("name", "")
		"since":
			var start := int(Engine.get_meta(_meta_key(step), 0))
			return "since %s: %.0f ms" % [step.get("name", ""), (Time.get_ticks_usec() - start) / 1000.0]
		"fit_zoom":
			return _fit_zoom(base)
	if ctrl == null:
		return "no authoring controller"
	match action:
		"fill":
			return _fill(ctrl)
		"paint":
			return _paint(ctrl)
		"save":
			return _save(ctrl, String(step.get("folder", "")))
	return _dump(ctrl, String(step.get("name", "map")))


## Raises the camera's zoom-out limit to the loaded map's whole-map fit (the camera's own
## fit size with authoring's margin), so a following `zoom` op with no size shows the whole
## map in play as authoring does.
static func _fit_zoom(base: Node) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc: Node = gm.get("_camera_controller") if gm else null
	if cc == null:
		return "fit_zoom: no camera controller"
	var fit := float(cc.get("_fit_size"))
	if is_inf(fit) or fit <= 0.0:
		return "fit_zoom: no fit size"
	var high := maxf(AuthoringController.PLAY_MAX_ZOOM, fit * AuthoringController.ZOOM_FIT_MARGIN)
	gm.set_zoom_limits(AuthoringController.MIN_ZOOM, high)
	return "fit_zoom: max zoom %.2f (fit %.2f)" % [high, fit]


static func _meta_key(step: Dictionary) -> String:
	return "msize_mark_" + String(step.get("name", "")).validate_node_name()


static func _dump(ctrl: AuthoringController, name: String) -> String:
	ctrl.call("_sync_document")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/%s.ttmap" % [OUT_DIR, name]
	var err := MapDocumentIO.write(ctrl.document, path)
	var doc: MapDocument = ctrl.document
	return (
		"dumped %s err %d bytes %d scatter rows %d (%d assets) props %d water %d crossings %d"
		% [
			path,
			err,
			FileAccess.get_file_as_bytes(path).size(),
			MapDocument.row_count(doc.scatter),
			doc.scatter.size(),
			MapDocument.row_count(doc.props),
			doc.water_bodies.size(),
			doc.crossings.size(),
		]
	)


## Paints the open map's first biome at full density over every sample (as the perf pass's
## "painted at full density over a whole 200 ft map") and regenerates the whole scatter.
static func _fill(ctrl: AuthoringController) -> String:
	var doc: MapDocument = ctrl.document
	var count := doc.sample_count()
	for i in count:
		doc.biome_slots[i] = 1
		doc.biome_density[i] = 255
	var scatter: AuthoredScatter = ctrl.scatter
	var half := doc.extent_m() * 0.5
	scatter.request_region(Rect2(-half, doc.extent_m()))
	return "filled %d samples with %s at 255" % [count, doc.biome_ids[0]]


## Full ground paint (see the header): at each sample a noise value picks a pair of adjacent
## slots and splits 255 between them, so every slot is in use and the weight images carry
## soft patches rather than incompressible noise.
static func _paint(ctrl: AuthoringController) -> String:
	var doc: MapDocument = ctrl.document
	var slots := PackedInt32Array()
	for surface in PAINT_SURFACES:
		var slot := doc.ensure_surface(surface)
		if slot < 0:
			return "paint: no slot for %s" % surface
		slots.append(slot)
	var count := doc.sample_count()
	var weights := PackedByteArray()
	weights.resize(count * MapDocument.SURFACE_CHANNELS * 2)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = doc.map_seed & 0x7fffffff
	noise.frequency = 1.0 / PAINT_FEATURE_M
	var n := slots.size()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var world := doc.sample_to_world(Vector2(x, z))
			var t := clampf((noise.get_noise_2d(world.x, world.y) * 0.5 + 0.5) * n, 0.0, n - 0.001)
			var a := floori(t)
			var share := roundi((t - a) * 255.0)
			var i := doc.sample_index(x, z)
			weights[MapDocument.surface_offset(i, slots[a], count)] = 255 - share
			weights[MapDocument.surface_offset(i, slots[(a + 1) % n], count)] = share
	doc.surface_weights = weights
	ctrl.editor.call("_refresh", Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	return "painted %d samples with %d surfaces" % [count, n]


static func _save(ctrl: AuthoringController, folder: String) -> String:
	if not folder.begins_with(LEVEL_PREFIX):
		return "save: %s is not a %s folder" % [folder, LEVEL_PREFIX]
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	var bytes := FileAccess.get_file_as_bytes(LevelManager.map_document_path(folder))
	return (
		"saved %s: %s, map.ttmap %d bytes, zstd %d bytes"
		% [folder, str(ok), bytes.size(), bytes.compress(FileAccess.COMPRESSION_ZSTD).size()]
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
