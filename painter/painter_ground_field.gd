class_name PainterGroundField
extends RefCounted

## PainterSurfaces' keeper of what the painted ground's FORM is lit from, for one authored
## terrain (card painter-ground-robust; docs/systems/painter.md "Ground shading"):
##   the shading field (GroundShadeField): the normal, slope, convexity and nearest steep face
##   painter_ground.gdshader reads in place of the mesh's, baked from the document's heights and
##   kept current per edit: AuthoredTerrain.ground_edited marks a rectangle, and the next sync()
##   (PainterSurfaces' zone rebuild, once that frame) redoes only the heights that changed in it;
##   the terrain's shadow caster: back faces only while painted (TerrainBackCaster), put back on
##   release().
## Events, never a poll: it follows the terrain's own signals from the first sync() to release().
##
## The worker update (card painter-land-frame). An edit's rect of ASYNC_SAMPLES samples or more (a
## river landing's, about 30000 samples: 44 ms of the landing frame) runs GroundShadeField.update()
## on a WorkerThreadPool task over a clone() of the field and a copy of the heights; the field and
## its texture stay as they were until the frame that finds the task completed adopts the clone
## (polled once a frame while it runs). Edits meanwhile wait in the dirty rect and follow at the
## landing, so the settled field equals the synchronous updates bit for bit (each stage is a pure
## function of the heights: GroundShadeField's header). As PainterZoneMaps' worker build, the main
## thread never waits for a task that has not completed: finish() redoes the job's update here, and
## release() or the predelete abandons it, reaped once it has completed (card painter-edit-hitch4b).

## The samples of a dirty rect from which the update runs on a worker (about 6 ms of GDScript here;
## a held stroke's every-third-frame rect, about 2100 samples, stays synchronous).
const ASYNC_SAMPLES := 4096

## The tasks let go of before they completed, waited for once each has (_reap()); process wide.
static var _abandoned := PackedInt64Array()

var _field := GroundShadeField.new()
var _terrain: AuthoredTerrain = null
var _dirty := Rect2i()
## The heights may have changed anywhere (a new terrain, a rebuild): the next sync() compares all.
var _whole := true
## The worker update in flight: its task id (-1 for none) and its job ({"field" clone, "doc"
## snapshot, "rect"}; only the worker touches the clone until the task completes).
var _task := -1
var _job: Dictionary = {}
## The materials the field was last bound to (the landing's catch-up rebinds them).
var _materials: Array = []


## Brings the field up to `terrain`'s document and binds it to `materials` (the ground's). While a
## worker update runs, the edits wait for its landing (_on_frame).
func sync(terrain: AuthoredTerrain, materials: Array) -> void:
	if terrain != _terrain:
		release()
		_terrain = terrain
		terrain.ground_edited.connect(_on_ground_edited)
		terrain.child_entered_tree.connect(_on_terrain_child)
		terrain.set_back_caster(true)
	_materials = materials
	var doc := terrain.document
	if _task >= 0 and not _field.matches(doc):
		_cancel()
	if _task < 0:
		_bring_up(doc)
	_bind()


## Stops following the terrain and gives it its own shadow casting back (a worker update in flight
## is abandoned, never waited for).
func release() -> void:
	_cancel()
	if is_instance_valid(_terrain):
		_terrain.ground_edited.disconnect(_on_ground_edited)
		_terrain.child_entered_tree.disconnect(_on_terrain_child)
		_terrain.set_back_caster(false)
	_terrain = null
	_dirty = Rect2i()
	_whole = true
	_materials = []


## The field itself (tests and probes).
func field() -> GroundShadeField:
	return _field


## Whether a worker update is in flight (tests, probes).
func updating() -> bool:
	return _task >= 0


## Lands the worker update in flight now and follows the edits that waited for it (tests, and a
## caller that needs the field now): the task's clone when it has completed, else the same update
## on this thread (the task is abandoned); false when none was in flight.
func finish() -> bool:
	if _task < 0:
		return false
	if WorkerThreadPool.is_task_completed(_task):
		_land()
	else:
		var job := _job
		_cancel()
		_field.update(job["doc"], job["rect"])
	if is_instance_valid(_terrain) and _terrain.document != null:
		_bring_up(_terrain.document, false)
	return true


## How many abandoned tasks wait to be reaped (tests).
static func abandoned_count() -> int:
	return _abandoned.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		# Only static functions here: the object's own methods fail in a RefCounted's predelete.
		_abandon(_task)


## Follows what is dirty (the whole grid, or the dirty rect: on a worker when it is large and
## `worker` allows).
func _bring_up(doc: MapDocument, worker: bool = true) -> void:
	if not _field.matches(doc):
		_field.bake(doc)
	elif _whole:
		_field.update(doc, Rect2i(0, 0, _field.width, _field.depth))
	elif worker and _dirty.get_area() >= ASYNC_SAMPLES:
		_start(doc, _dirty)
	elif _dirty.has_area():
		_field.update(doc, _dirty)
	_whole = false
	_dirty = Rect2i()


func _bind() -> void:
	for material: ShaderMaterial in _materials:
		# Not `field_map`: that name is the village fields' (painter_field.gdshaderinc).
		material.set_shader_parameter(&"shade_map", _field.texture())
		material.set_shader_parameter(&"shade_present", true)


## Starts the worker update of `rect` over a clone of the field and a copy of `doc`'s heights.
func _start(doc: MapDocument, rect: Rect2i) -> void:
	_field.texture()  # Made now: the clone has none, and the landing uploads into this one.
	var snapshot := MapDocument.new()
	snapshot.size_cells = doc.size_cells
	snapshot.cell_size_m = doc.cell_size_m
	snapshot.sample_spacing_m = doc.sample_spacing_m
	snapshot.heights = doc.heights.duplicate()
	_job = {"field": _field.clone(), "doc": snapshot, "rect": rect}
	# The script's static function: the task never calls into this object, which may be freed first.
	_task = WorkerThreadPool.add_task(
		PainterGroundField._run.bind(_job), true, "PainterGroundField.update"
	)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_on_frame):
		tree.process_frame.connect(_on_frame)


## The worker's half: the update on the job's clone (any thread; it reads only the job).
static func _run(job: Dictionary) -> void:
	var f: GroundShadeField = job["field"]
	job["changed"] = f.update(job["doc"], job["rect"])


## A frame while the worker update runs: once it has completed, the field takes it and the edits
## that waited follow (which may start the next one).
func _on_frame() -> void:
	if _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
		return
	_unwatch()
	if _task < 0:
		return
	_land()
	if is_instance_valid(_terrain) and _terrain.document != null:
		_bring_up(_terrain.document)
		_bind()


## Takes the completed task's clone (the wait returns at once: the callers check first).
func _land() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	var job := _job
	_task = -1
	_job = {}
	_unwatch()
	var changed: Rect2i = job.get("changed", Rect2i())
	if changed.has_area():
		_field.adopt(job["field"])


## Drops the worker update in flight, if any, without waiting for it; its task is reaped once it
## completes. The rect it was following is dirty again.
func _cancel() -> void:
	if _task < 0:
		return
	var rect: Rect2i = _job["rect"]
	_dirty = _dirty.merge(rect) if _dirty.has_area() else rect
	_abandon(_task)
	_task = -1
	_job = {}
	_unwatch()


func _unwatch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_on_frame):
		tree.process_frame.disconnect(_on_frame)


static func _abandon(task: int) -> void:
	_abandoned.append(task)
	_reap()
	var tree := Engine.get_main_loop() as SceneTree
	if not _abandoned.is_empty() and tree != null:
		if not tree.process_frame.is_connected(PainterGroundField._reap):
			tree.process_frame.connect(PainterGroundField._reap)


## Waits for each abandoned task that has completed (at once: it has), keeps the rest, and stops
## polling when none is left.
static func _reap() -> void:
	var left := PackedInt64Array()
	for task in _abandoned:
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			left.append(task)
	_abandoned = left
	var tree := Engine.get_main_loop() as SceneTree
	if left.is_empty() and tree != null and tree.process_frame.is_connected(PainterGroundField._reap):
		tree.process_frame.disconnect(PainterGroundField._reap)


func _on_ground_edited(rect: Rect2i) -> void:
	_dirty = _dirty.merge(rect) if _dirty.has_area() else rect


func _on_terrain_child(node: Node) -> void:
	# The skirt is built last by every AuthoredTerrain.build(): the heights may be new.
	if str(node.name) == AuthoredTerrain.SKIRT_NAME:
		_whole = true
