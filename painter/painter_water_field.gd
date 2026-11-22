class_name PainterWaterField
extends RefCounted

## The painted look's water SURFACE: one WaterField of the map's document drawn as one mesh
## (WaterFieldMesh, painter_water.gdshader's field branch) in place of AuthoredWater's surface mesh
## and the curtains of its falls. Owned by PainterWater, which makes one per painted map
## (docs/systems/water_field.md "Drawing it", docs/systems/painter.md "Water").
##
## Draw only. Gameplay (WaterSurface, zones, walkability, the ripple registry) keeps reading
## AuthoredWater's own data until the gameplay stage, so the old meshes are still built; here the
## surface mesh is hidden while the field draws (the falls mesh stays: its mist is the one part of
## a fall the field does not draw) and shown again on release(). The field mesh is a child of the
## map root, not of AuthoredWater, because AuthoredWater.apply() frees its children on every edit.
##
## Edits. Three things change what the field draws, and each redoes only a dirty rect
## (WaterField.update, equal to a full build bit for bit):
## - a water edit: AuthoredWater.refreshed fires; each body's signature (and the pond mask's
##   samples) is compared with the last one, and the rects of the changed bodies, as they were
##   (kept per body) and as they are (WaterField.rect_of_bodies), are redone;
## - a ground edit: AuthoredTerrain.ground_edited(rect) near water, redone for that rect; away
##   from water only the field's copy of the heights is taken (_take_ground), so a later
##   update that reads them sees what a full build would (the dressing refresh no longer marks the
##   whole grid after every water or height edit, card painter-edit-hitch).
## Ground edits arrive in bursts, so rects are merged and redone once the burst pauses (a frame with
## no edit, at most FLUSH_WAIT frames on: a water landing's three edits flush once). The mesh is
## rebuilt whole from the field after an update (about 50 ms on a 245 x 245 grid: GDScript over the
## field's arrays); an update that changed nothing builds nothing.
##
## A held sculpt stroke (AuthoredTerrain.stroke_held). Its flushes run on a WorkerThreadPool task
## over a clone of the field and a copy-on-write snapshot of the document, with the mesh arrays and
## texture images; the result lands on the first frame after the task completes (to_mesh and the
## texture upload stay here), and the next flush, held or not, waits for it. The main thread never
## waits on an unfinished task: an update that cannot wait (a small water edit, a probe) drops the
## job and redoes its rect with its own. The stroke's end edits its whole rect once more, so what
## lands after a stroke is the synchronous result (card painter-held-stroke: 14 to 20 ms every
## fourth held frame before).
##
## A water landing (card painter-river-landing). Its document takes the new bodies and the carve
## in one frame, so the ground flush that follows also redoes the changed bodies' rect and notes
## their signatures; the swap's refreshed signal then finds nothing changed (the field was updated
## twice per landing before, about 95 ms each on a second river, over the same inputs). A flush or
## water edit over ASYNC_SAMPLES or more runs on the worker path above, held or not, and lands a
## few frames later with the bytes a synchronous update gives.

## The mesh's custom bounds margin: a surface is never above its tallest sample.
const MARGIN_M := 0.5
## A ground edit within this many samples of water redoes the field there (the bank hold and the
## buried rings read the ground up to a few samples out).
const GROUND_REACH := 8
## The lowest depth the textures hold: a buried or dry sample must not drag a bicubic fetch of the
## waterline down by metres.
const DEPTH_FLOOR := -0.3
## The most frames a ground edit near water waits for its flush while edits keep coming (a stroke
## beside water redoes the field every FLUSH_WAIT frames, not every frame).
const FLUSH_WAIT := 4
## A flush or water edit whose rect holds at least this many samples runs on a worker, as a held
## stroke's does (about 3 ms of update per thousand samples: a river's landing redoes about 32
## thousand); a smaller one runs at once.
const ASYNC_SAMPLES := 4096
## WaterField's packed arrays, copied by clone_field().
const _CLONED: Array[StringName] = [
	&"ground", &"w", &"ew", &"depth", &"energy", &"steep", &"shore", &"lateral", &"spill", &"calm",
	&"owner", &"flow_u", &"foot", &"_raw", &"_stroke_energy", &"_foot_raw", &"_base",
]

## Tasks of dropped jobs, waited for (at once) once they have completed (PainterZoneMaps' rule:
## the main thread never waits on an unfinished task).
static var _abandoned: PackedInt64Array = PackedInt64Array()

## The field, null until a map is attached.
var field: WaterField = null
## The mesh node, null when the map has no water (or nothing is attached).
var node: MeshInstance3D = null
## Milliseconds of the last build: {"field": ms, "mesh": ms}.
var timings: Dictionary = {}
## The last build's counts: {"vertices", "triangles"}.
var counts: Dictionary = {}

var _map: Node3D = null
var _terrain: AuthoredTerrain = null
var _water: AuthoredWater = null
var _material: Material = null
var _enabled: bool = true
var _signatures: Dictionary = {}
var _rects: Dictionary = {}
var _pond_mask: PackedByteArray = PackedByteArray()
var _dirty: Rect2i = Rect2i()
var _flush_queued: bool = false
## The frames of the first and the latest ground edit merged into _dirty.
var _dirty_since: int = 0
var _dirty_last: int = 0
var _tex_a: ImageTexture = null
var _tex_b: ImageTexture = null
## A held stroke's worker update ({"doc" snapshot, "rect", "field" clone, then what _run_job adds};
## only the task touches it until it lands) and its WorkerThreadPool task, -1 when none.
var _job: Dictionary = {}
var _task: int = -1
## The rects _take_ground took on the field while the job ran: taken again on its clone at landing.
var _job_takes: Rect2i = Rect2i()


## Draws the water of `map` (a map root with an AuthoredTerrain and an AuthoredWater) with
## `material` (the shared painted water material). False, drawing nothing, when the map has no
## authored terrain (a Blender map: its water planes keep the shader's depth-buffer path).
func attach(map: Node3D, material: Material) -> bool:
	detach()
	_map = map
	_material = material
	_terrain = map.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
	if _terrain == null or _terrain.document == null:
		return false
	if not _terrain.ground_edited.is_connected(_on_ground_edited):
		_terrain.ground_edited.connect(_on_ground_edited)
	_bind_water(map.get_node_or_null(NodePath(AuthoredWater.NODE_NAME)) as AuthoredWater)
	if _water == null:
		# The map's first water is made later (an authoring edit on a dry map): wait for its node.
		map.child_entered_tree.connect(_on_map_child)
	_rebuild_all()
	_apply_visibility()
	return true


func _bind_water(water: AuthoredWater) -> void:
	_water = water
	if water != null and not water.refreshed.is_connected(_on_water_refreshed):
		water.refreshed.connect(_on_water_refreshed)


func _on_map_child(child: Node) -> void:
	if child is AuthoredWater and _water == null:
		_bind_water(child as AuthoredWater)
		_map.child_entered_tree.disconnect(_on_map_child)


## Stops drawing: frees the mesh, shows AuthoredWater's own surface and lets go of the map. A worker
## update in flight is dropped, never waited for.
func detach() -> void:
	_cancel_job()
	if _map != null and is_instance_valid(_map):
		if _map.child_entered_tree.is_connected(_on_map_child):
			_map.child_entered_tree.disconnect(_on_map_child)
	if _water != null and is_instance_valid(_water):
		if _water.refreshed.is_connected(_on_water_refreshed):
			_water.refreshed.disconnect(_on_water_refreshed)
		var old := _water.get_mesh_instance()
		if old != null:
			old.visible = true
	if _terrain != null and is_instance_valid(_terrain):
		if _terrain.ground_edited.is_connected(_on_ground_edited):
			_terrain.ground_edited.disconnect(_on_ground_edited)
	_free_node()
	field = null
	_signatures.clear()
	_rects.clear()
	_pond_mask = PackedByteArray()
	_dirty = Rect2i()
	_map = null
	_terrain = null
	_water = null
	_material = null


func _notification(what: int) -> void:
	# Static only: the instance's own methods are gone by now.
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		_abandon(_task)
		_task = -1


## Whether the field is attached to a map.
func is_attached() -> bool:
	return field != null


## Whether the field draws now (false: AuthoredWater's own surface does).
func is_enabled() -> bool:
	return _enabled


## Draws the field (true) or AuthoredWater's own surface and curtains (false), for an A/B of the
## two in one run.
func set_enabled(on: bool) -> void:
	_enabled = on
	_apply_visibility()


## Redoes the field over `rect` (sample coordinates) now and rebuilds the mesh when it changed
## (tests, probes; the signals queue this once per frame). A held stroke's worker update in flight
## is dropped, and its rect redone here with this one.
func update_rect(rect: Rect2i) -> void:
	if field == null or _terrain == null:
		return
	if _task >= 0:
		rect = _merge(rect, _job["rect"])
		_cancel_job()
	var t0 := Time.get_ticks_usec()
	var changed := field.update(_terrain.document, rect)
	timings["field"] = (Time.get_ticks_usec() - t0) / 1000.0
	if changed.has_area():
		_build_mesh()


## Redoes the whole field and mesh (a probe's switch changes what a build makes).
func rebuild() -> void:
	if _terrain != null:
		_rebuild_all()


## Whether a held stroke's worker update is in flight (tests).
func updating() -> bool:
	return _task >= 0


## Lands the worker update in flight now (tests, probes): its result when the task has completed,
## else the same update of the same snapshot on this thread (the task is abandoned, never waited
## for); false when none was in flight.
func finish_update() -> bool:
	if _task < 0:
		return false
	if WorkerThreadPool.is_task_completed(_task):
		_land_job()
		return true
	# A dictionary of its own: the abandoned task still writes into its job's.
	var redo := {"doc": _job["doc"], "rect": _job["rect"], "field": clone_field(field)}
	_cancel_job()
	PainterWaterField._run_job(redo)
	_install_job(redo)
	return true


func _rebuild_all() -> void:
	_cancel_job()
	var doc := _terrain.document
	var t0 := Time.get_ticks_usec()
	field = WaterField.build(doc)
	timings["field"] = (Time.get_ticks_usec() - t0) / 1000.0
	_remember(doc)
	_build_mesh()


## The mesh of the field's current state, replacing the node's.
func _build_mesh() -> void:
	var t0 := Time.get_ticks_usec()
	var built := WaterFieldMesh.build(field)
	if not _install_mesh(built, t0):
		return
	var t1 := Time.get_ticks_usec()
	var packed := WaterFieldNative.pack_textures(field, DEPTH_FLOOR)
	_upload_textures(_images(field, packed))
	timings["textures"] = (Time.get_ticks_usec() - t1) / 1000.0


## Puts `built` (WaterFieldMesh.build of the field) on the node; `t0` is when its build started.
## False, freeing the node, when the field holds no water.
func _install_mesh(built: Dictionary, t0: int) -> bool:
	counts = {"vertices": built.vertices, "triangles": built.triangles}
	var mesh := WaterFieldMesh.to_mesh(built, _material)
	if mesh == null:
		_free_node()
		return false
	var aabb: AABB = built.aabb
	mesh.custom_aabb = aabb.grow(MARGIN_M)
	if node == null:
		node = MeshInstance3D.new()
		node.name = WaterFieldMesh.MESH_NAME
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta(Constants.BOUNDS_EXEMPT_META, true)
		_map.add_child(node)
		node.set_instance_shader_parameter(
			&"water_flow_present", not _terrain.document.water_flow.is_empty()
		)
	node.mesh = mesh
	node.visible = _enabled
	timings["mesh"] = (Time.get_ticks_usec() - t0) / 1000.0
	return true


## The two texture images of `f` from WaterFieldNative.pack_textures' `packed` (any thread).
static func _images(f: WaterField, packed: Dictionary) -> Array[Image]:
	var nx := f.size.x
	var nz := f.size.y
	var a: PackedFloat32Array = packed.a
	var b: PackedFloat32Array = packed.b
	return [
		Image.create_from_data(nx, nz, false, Image.FORMAT_RGBAF, a.to_byte_array()),
		Image.create_from_data(nx, nz, false, Image.FORMAT_RGBAF, b.to_byte_array()),
	]


## Shade spike (S1): the field's channels as two RGBAF textures over the sample grid, sampled per
## fragment (bicubic) so the shore, the depth tint and the white read smooth fields instead of
## per-vertex attributes on the 0.25 m grid. `fld_a` = (depth, energy, shore, steep) with the
## buried and dry samples' depth held at DEPTH_FLOOR; `fld_b` = (flow coordinate premultiplied by
## its weight, weight, 0, 0), filtered bilinear and divided back in the shader. The whole texture
## is rebuilt after an update (ImageTexture has no partial update in Godot 4.7). `images` is
## _images() of the field.
func _upload_textures(images: Array[Image]) -> void:
	if _material == null or not (_material is ShaderMaterial):
		return
	var sm := _material as ShaderMaterial
	_tex_a = _fill_texture(_tex_a, images[0])
	_tex_b = _fill_texture(_tex_b, images[1])
	sm.set_shader_parameter(&"fld_a", _tex_a)
	sm.set_shader_parameter(&"fld_b", _tex_b)
	sm.set_shader_parameter(&"fld_origin", field.origin)
	sm.set_shader_parameter(&"fld_inv_step", Vector2.ONE / field.step)
	sm.set_shader_parameter(&"fld_dim", Vector2(field.size.x, field.size.y))


func _fill_texture(tex: ImageTexture, img: Image) -> ImageTexture:
	var nx := img.get_width()
	var nz := img.get_height()
	if tex != null and tex.get_width() == nx and tex.get_height() == nz:
		tex.update(img)
		return tex
	return ImageTexture.create_from_image(img)


func _free_node() -> void:
	if node != null and is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()
	node = null


## The old surface shows only while the field does not draw it.
func _apply_visibility() -> void:
	if _water != null and is_instance_valid(_water):
		var old := _water.get_mesh_instance()
		if old != null:
			old.visible = not (_enabled and node != null)
	if node != null:
		node.visible = _enabled


func _on_water_refreshed() -> void:
	if field == null:
		return
	var doc := _terrain.document
	var rect := _changed_rect(doc)
	_remember(doc)
	if rect.has_area():
		if _dirty.has_area():
			# A ground flush still waiting is redone with this rect (its callback finds nothing).
			rect = _merge(rect, _dirty)
			_dirty = Rect2i()
		_redo(rect)
	_apply_visibility()


## The sample rect a water edit changed: the changed bodies' areas as they were (kept in _rects)
## and as they are, and the pond mask's changed samples' bodies. Empty when nothing changed.
func _changed_rect(doc: MapDocument) -> Rect2i:
	var ids := {}
	var now := {}
	for body in doc.water_bodies:
		now[body.id] = body
		if not _signatures.has(body.id) or _signatures[body.id] != _signature(body):
			ids[body.id] = true
	for id: int in _signatures:
		if not now.has(id):
			ids[id] = true
	var mask := doc.pond_mask
	if mask != _pond_mask:
		var same := mask.size() == _pond_mask.size()
		for i in mask.size():
			var was := _pond_mask[i] if same else 0
			if mask[i] != was:
				ids[int(mask[i])] = true
				ids[int(was)] = true
	var rect := Rect2i()
	var bodies: Array[WaterBody] = []
	for id: int in ids:
		if _rects.has(id):
			rect = _merge(rect, _rects[id])
		if now.has(id):
			bodies.append(now[id])
	if not bodies.is_empty():
		rect = _merge(rect, WaterField.rect_of_bodies(doc, bodies))
	return rect


## Notes each body's signature, the area it covers and the pond mask, for the next edit.
func _remember(doc: MapDocument) -> void:
	_signatures.clear()
	_rects.clear()
	for body in doc.water_bodies:
		_signatures[body.id] = _signature(body)
		var one: Array[WaterBody] = [body]
		_rects[body.id] = WaterField.rect_of_bodies(doc, one)
	_pond_mask = doc.pond_mask.duplicate()


static func _signature(body: WaterBody) -> int:
	return [
		body.kind, body.depth, body.level_m, body.speed, body.points, body.half_widths
	].hash()


static func _merge(a: Rect2i, b: Rect2i) -> Rect2i:
	if not a.has_area():
		return b
	if not b.has_area():
		return a
	return a.merge(b)


func _on_ground_edited(sample_rect: Rect2i) -> void:
	if field == null or not sample_rect.has_area():
		return
	var near := sample_rect.grow(GROUND_REACH).intersection(Rect2i(Vector2i.ZERO, field.size))
	if not _has_water(near):
		# Nothing to redo, but the field's ground copy follows: a later update near here reads it.
		_take_ground(field, _terrain.document, near)
		if _task >= 0:
			_job_takes = _merge(_job_takes, near)
		return
	_dirty = _merge(_dirty, sample_rect.grow(WaterField.RING_MARGIN))
	var frame := Engine.get_process_frames()
	_dirty_last = frame
	if not _flush_queued:
		_flush_queued = true
		_dirty_since = frame
		_queue_flush()


## Takes `doc`'s heights into `f`'s copy of the ground over `rect` (inside the grid) without
## redoing anything: an edit away from water, whose samples a later update reads as unchanged
## inputs, so the field stays what a full build gives. A rect over an eighth of the grid takes the
## whole copy (one array copy beats the per-sample loop).
static func _take_ground(f: WaterField, doc: MapDocument, rect: Rect2i) -> void:
	var heights := doc.heights
	if heights.size() != f.ground.size():
		return
	if rect.get_area() * 8 > heights.size():
		f.ground = heights.duplicate()
		return
	var ground := f.ground
	for z in range(rect.position.y, rect.end.y):
		var row := z * f.size.x
		for i in range(row + rect.position.x, row + rect.end.x):
			ground[i] = heights[i]
	f.ground = ground


func _queue_flush() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.process_frame.connect(_flush_dirty, CONNECT_ONE_SHOT)


## Redoes the merged rect once the edits pause: a frame with no ground edit since the last one, or
## FLUSH_WAIT frames after the first. A water landing edits the ground three frames running (the
## carve, the settle, the dressing refresh), each frame already holding the zone maps' update;
## one flush after them replaces three in those frames (card painter-edit-hitch2).
##
## While a sculpt stroke is held (AuthoredTerrain.stroke_held) the update runs on a worker over a
## snapshot and lands a few frames later (_start_job); the next one waits for it. The stroke's end
## edits its whole rect once more (settle_heights), and that flush, not held, runs here once the job
## in flight has landed, so what lands after the stroke is the synchronous result.
func _flush_dirty() -> void:
	var frame := Engine.get_process_frames()
	var held := _held()
	# A job in flight lands first (a frame or two), held or not: the stroke's end then redoes only
	# what changed since, instead of dropping the job and redoing its rect too.
	if (frame - _dirty_last < 2 and frame - _dirty_since < FLUSH_WAIT) or _task >= 0:
		_queue_flush()
		return
	_flush_queued = false
	var rect := _dirty
	_dirty = Rect2i()
	if field == null or not rect.has_area():
		return
	# A water landing's ground edits arrive with its bodies already in the document: redo their rect
	# here too, so the refreshed signal of the swap that follows finds nothing left to redo.
	var doc := _terrain.document
	var bodies := _changed_rect(doc)
	if bodies.has_area():
		rect = _merge(rect, bodies)
		_remember(doc)
	if held:
		_start_job(rect)
	else:
		_redo(rect)


## Redoes `rect` now when it holds fewer than ASYNC_SAMPLES samples, else on a worker like a held
## stroke's flush (a job in flight is dropped and its rect redone with this one).
func _redo(rect: Rect2i) -> void:
	if rect.get_area() < ASYNC_SAMPLES:
		update_rect(rect)
		return
	if _task >= 0:
		rect = _merge(rect, _job["rect"])
		_cancel_job()
	_start_job(rect)


func _held() -> bool:
	return _terrain != null and is_instance_valid(_terrain) and _terrain.stroke_held


## Starts the update of `rect` on a worker: a clone of the field (clone_field) over a snapshot
## of the document (_snapshot; the water bodies are shared, and a held sculpt stroke never edits
## them), polled once a frame until it lands.
func _start_job(rect: Rect2i) -> void:
	var doc := _terrain.document
	_job = {"doc": _snapshot(doc), "rect": rect, "field": clone_field(field)}
	_job_takes = Rect2i()
	# The script's static function: the task never calls into this object, which may be freed first.
	_task = WorkerThreadPool.add_task(
		PainterWaterField._run_job.bind(_job), true, "PainterWaterField.update"
	)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_poll_job):
		tree.process_frame.connect(_poll_job)


## What WaterField.update() reads of `doc` (the grid, the heights, the pond mask, the water bodies
## and the seed), copied: packed arrays copy-on-write, so a later edit never reaches the copy.
## Nothing else is shared, so a stroke's edits of the scatter rows meanwhile copy nothing.
static func _snapshot(doc: MapDocument) -> MapDocument:
	var s := MapDocument.new()
	s.map_seed = doc.map_seed
	s.size_cells = doc.size_cells
	s.cell_size_m = doc.cell_size_m
	s.sample_spacing_m = doc.sample_spacing_m
	s.tier_height_m = doc.tier_height_m
	s.heights = doc.heights.duplicate()
	s.pond_mask = doc.pond_mask.duplicate()
	# Copies (a few bodies, cheap): a water edit or its undo lands while a release's job runs.
	var bodies: Array[WaterBody] = []
	for body in doc.water_bodies:
		bodies.append(body.copy())
	s.water_bodies = bodies
	return s


## The worker's half: the update, then the mesh arrays and the texture images of the result, into
## `job` (any thread; it reads only the job).
static func _run_job(job: Dictionary) -> void:
	var f: WaterField = job["field"]
	var t0 := Time.get_ticks_usec()
	var changed := f.update(job["doc"], job["rect"])
	job["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	job["changed"] = changed
	if changed.has_area():
		job["built"] = WaterFieldMesh.build(f)
		job["images"] = _images(f, WaterFieldNative.pack_textures(f, DEPTH_FLOOR))


func _poll_job() -> void:
	if _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
		return
	_unwatch_job()
	if _task >= 0:
		_land_job()


func _unwatch_job() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_poll_job):
		tree.process_frame.disconnect(_poll_job)


## Lands the completed job (the wait returns at once: callers check first).
func _land_job() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	var job := _job
	_task = -1
	_job = {}
	_unwatch_job()
	_install_job(job)


## Takes `job`'s field as the field (the edits away from water made meanwhile taken again on it)
## and its mesh and textures when the update changed anything.
func _install_job(job: Dictionary) -> void:
	field = job["field"]
	if _job_takes.has_area():
		_take_ground(field, _terrain.document, _job_takes)
	_job_takes = Rect2i()
	timings["field"] = job["ms"]
	var changed: Rect2i = job["changed"]
	if not changed.has_area():
		return
	var t0 := Time.get_ticks_usec()
	if _install_mesh(job["built"], t0):
		var t1 := Time.get_ticks_usec()
		_upload_textures(job["images"])
		timings["textures"] = (Time.get_ticks_usec() - t1) / 1000.0
	_apply_visibility()


## Drops the job in flight, if any, without waiting for it; its task is reaped once it completes.
func _cancel_job() -> void:
	_unwatch_job()
	if _task >= 0:
		_abandon(_task)
	_task = -1
	_job = {}
	_job_takes = Rect2i()


static func _abandon(task: int) -> void:
	_abandoned.append(task)
	_reap()
	var tree := Engine.get_main_loop() as SceneTree
	if not _abandoned.is_empty() and tree != null:
		if not tree.process_frame.is_connected(PainterWaterField._reap):
			tree.process_frame.connect(PainterWaterField._reap)


## A copy of `f` that shares nothing writable with it, so WaterField.update() can run on it on a
## worker while `f` is read or edited here. The packed arrays are duplicated (copy-on-write: O(1)
## now, the first write on either side copies; a plain assignment would share them), the tables and
## events deep. Every field of WaterField's state is listed here.
static func clone_field(f: WaterField) -> WaterField:
	var c := WaterField.new()
	c.size = f.size
	c.step = f.step
	c.origin = f.origin
	for key: StringName in _CLONED:
		c.set(key, f.get(key).duplicate())
	c.marks.film = f.marks.film.duplicate()
	c.marks.bank = f.marks.bank.duplicate()
	c.events = f.events.duplicate(true)
	c.timings = f.timings.duplicate()
	c._foot_rects = f._foot_rects.duplicate()
	c._tables = f._tables.duplicate(true)
	return c


## How many dropped tasks wait to be reaped (tests).
static func abandoned_count() -> int:
	return _abandoned.size()


static func _reap() -> void:
	var left := PackedInt64Array()
	for task in _abandoned:
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			left.append(task)
	_abandoned = left
	var tree := Engine.get_main_loop() as SceneTree
	if left.is_empty() and tree != null and tree.process_frame.is_connected(PainterWaterField._reap):
		tree.process_frame.disconnect(PainterWaterField._reap)


## Whether any sample of `rect` holds water (the surface's height is set).
func _has_water(rect: Rect2i) -> bool:
	for z in range(rect.position.y, rect.end.y):
		var row := z * field.size.x
		for x in range(rect.position.x, rect.end.x):
			if field.w[row + x] != WaterGeometry.DRY:
				return true
	return false
