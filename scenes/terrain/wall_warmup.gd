class_name WallWarmup
extends RefCounted

## Pays a first wall's first-use costs when the Wall tool opens, not in the frame the wall lands
## (card painter-wall-path: a first stone wall's place frame was 103-106 ms on the 320 ft bench,
## 56 of it the baked masonry decoded and mipmapped on the main thread and about 28 the wall
## materials' shaders built as the mesh took them).
##
## Model. start() decodes the masonry images on a worker (MasonryTextures.decode, pure) unless the
## textures are made already; a process_frame poll takes the result once the task has completed
## (never waiting on one still running) and makes the textures (MasonryTextures.adopt). Then, one a
## frame, it asks each material a wall of the map's styles would wear for its RID
## (AuthoredWalls.warm_list: the same cached objects the wall's nodes then take), which builds its
## shader. Nothing it makes changes what a wall looks like: they are the materials and textures a
## first wall would make, made earlier. A wall placed before it finishes makes what is missing
## itself, as it always did. stop() (a closed map) makes no more materials; a worker still running
## is polled to its end and reaped, so a close never waits for it.

## Warm-ups still running (each holds itself here until its poll ends).
static var _live: Array[WallWarmup] = []

## Materials whose RIDs this warm-up asked for, and whether it has ended.
var warmed: int = 0
var done: bool = false
var _walls: WeakRef = null
var _styles := PackedStringArray()
var _task: int = -1
## Shared with the worker: {"images": the decoded masonry}.
var _job: Dictionary = {}
var _queue: Array[Material] = []
var _listed: bool = false
var _stopped: bool = false


## Starts a warm-up for `walls` (the map's AuthoredWalls) in the styles `styles` (the map's biome
## ids; none: the default style). Null without a scene tree to poll from.
static func start(walls: AuthoredWalls, styles: PackedStringArray) -> WallWarmup:
	var tree := Engine.get_main_loop() as SceneTree
	if walls == null or tree == null:
		return null
	var warm := WallWarmup.new()
	warm._walls = weakref(walls)
	warm._styles = styles.duplicate() if not styles.is_empty() else PackedStringArray([""])
	if (
		not MasonryTextures.made()
		and MasonryTextures.available()
		and GlbUtils.threaded_loads_safe()
	):
		var job := {"images": {}}
		warm._job = job
		warm._task = WorkerThreadPool.add_task(
			func() -> void: job["images"] = MasonryTextures.decode(), false, "Wall warm-up"
		)
	_live.append(warm)
	tree.process_frame.connect(warm.step)
	return warm


## Makes no more materials; a worker still decoding is reaped when it ends.
func stop() -> void:
	_stopped = true


## One frame's part: the worker's result once its task completed, else the list of materials,
## else one material's RID. Driven by process_frame; tests may call it.
func step() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		MasonryTextures.adopt(_job.get("images", {}))
		_job = {}
		return
	var walls := _walls.get_ref() as AuthoredWalls if _walls != null else null
	if _stopped or walls == null or not is_instance_valid(walls):
		_end()
		return
	if not _listed:
		_listed = true
		_queue = walls.warm_list(_styles)
		return
	if _queue.is_empty():
		_end()
		return
	# A BaseMaterial3D builds its shader when its RID is first asked for.
	_queue.pop_front().get_rid()
	warmed += 1


func _end() -> void:
	done = true
	_queue.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(step):
		tree.process_frame.disconnect(step)
	_live.erase(self)
