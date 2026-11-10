class_name BootPrecompile
extends Node

## Compiles the play and authoring code in the background of the title (perf audit boot2,
## 2026-11-09).
##
## The start-up leaves the map, the table, the authoring editors and the procgen structure doors
## out of its script graph (tools/boot_graph.gd, test_boot_graph.gd), which takes about 2 s off the
## time to the title but moves that compile to the first map. This loads those scripts on a worker
## thread while the title idles. Slicing the compile on the main thread does not work: the play
## and authoring scripts form one strongly connected web, and loading any one of them compiles the
## whole web in one frame (measured: one 2.26 s frame, boot2 handoff).
##
## ROOTS are the doors into that code, in the order the first map needs them; each load compiles
## what it names, so the list stays short. They are loaded in this natural order on purpose: a
## leaf-first list of all 418 scripts compiled just as fast but left about 1600 objects and 985
## resources unfreed at exit (measured, on the worker and on the main thread alike), while loading
## the doors does not. A script already loaded is skipped. Root calls finish() before the first
## thing that needs the code (a session or a map): the worker stops after its current script and
## the main thread carries on, loading what is left itself. A window close while the worker runs
## waits for it (_notification), because quitting under a compile crashes.
##
## `first` goes ahead of ROOTS: on a first launch Root puts the graphics warm-up's screen there,
## whose scripts reach the same web (its load was a 2.1 s frame before the first one; perf audit
## S6), and starts the warm-up behind the title on `first_loaded`.

## Emitted once on the main thread: the `first` scripts are loaded, or the precompile stopped
## before them (the caller then loads what is left itself).
signal first_loaded

## The scripts that open the play and authoring code: the map scene (play and authoring with it),
## the table, the authoring controller, the avatar builder, the token look and the procgen
## structure doors (StructureProcgen).
const ROOTS: PackedStringArray = [
	"res://scenes/states/playing/game_map.tscn",
	"res://scenes/states/playing/level_play_controller.gd",
	"res://scenes/states/authoring/authoring_controller.gd",
	"res://scenes/states/playing/avatar_builder.gd",
	"res://scenes/board_token/token_toon.gd",
	"res://procgen/graph/structure_registry.gd",
	"res://procgen/gen/row_gen.gd",
	"res://procgen/nodes/row_node.gd",
	"res://procgen/graph/graph_evaluator.gd",
	"res://procgen/gen/settlement.gd",
	"res://procgen/gen/props.gd",
	"res://procgen/gen/ornaments.gd",
	"res://procgen/graph/recipes_ornaments.gd",
]
## Frames to wait after the title is up before the worker starts, so its first frames are clean.
const START_DELAY_FRAMES := 3
## The longest _exit_tree waits for the worker (it usually cannot finish: the main loop is stopped).
const EXIT_WAIT_MS := 2000

## The running precompile, null when there is none (finished, stopped or never made).
static var current: BootPrecompile = null

## Threads still running when the game left, kept so none is destroyed while running.
static var _stranded: Array[Thread] = []

## Loaded before ROOTS, in order (see the class doc). Set before the node enters the tree.
var first: PackedStringArray = []
## Scripts the worker compiled, and the time it took (ms), for the boot trace.
var compiled := 0
var spent_ms := 0.0
## How many paths the worker is past (written by the worker only).
var _passed := 0
var _first_sent := false

var _thread: Thread = null
var _delay := START_DELAY_FRAMES
var _stop := false
var _closing := false


## Stops the running precompile, if any: called at the doors into play and authoring code.
static func finish_current() -> void:
	if is_instance_valid(current):
		current.finish()


func _enter_tree() -> void:
	current = self


## The window's close request while the worker runs: the engine must not tear the scripts down
## under a compile (measured: an access violation on 5 of 6 quits 0.5 s and 2 s after the title).
## The worker cannot finish while the main thread is blocked (it needs the main loop: waiting
## 15 s in _exit_tree did not get it done), so the quit is held back, the frames keep running,
## and _process quits once the worker has stopped (after its current script, a few seconds at
## most in the first big load).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST or _closing or _thread == null:
		return
	if not _thread.is_alive():
		return
	_closing = true
	_stop = true
	get_tree().auto_accept_quit = false


## The game is leaving by another way (SceneTree.quit from code): waits a little for the worker,
## and when it is still running keeps its Thread object alive so it is not destroyed running.
func _exit_tree() -> void:
	_stop = true
	if current == self:
		current = null
	if _thread == null or not _thread.is_started():
		return
	var waited_from := Time.get_ticks_msec()
	while _thread.is_alive() and Time.get_ticks_msec() - waited_from < EXIT_WAIT_MS:
		RenderingServer.force_sync()
		OS.delay_msec(5)
	if _thread.is_alive():
		# Too slow to wait for: keep the Thread object alive so it is not destroyed running.
		_stranded.append(_thread)
	else:
		_thread.wait_to_finish()


func _process(_delta: float) -> void:
	if _thread != null:
		if _passed >= first.size():
			_send_first()
		if not _thread.is_alive():
			_thread.wait_to_finish()
			BootTrace.mark("precompiled the play and authoring scripts (%d)" % compiled)
			set_process(false)
			if current == self:
				current = null
			_send_first()
			if _closing:
				get_tree().quit()
			queue_free()
		return
	if _stop:
		_send_first()
		queue_free()
		return
	if _delay > 0:
		_delay -= 1
		return
	_thread = Thread.new()
	_thread.start(_run.bind(first + ROOTS))


func _send_first() -> void:
	if not _first_sent:
		_first_sent = true
		first_loaded.emit()


## Asks the worker to stop after the script it is on, and does not wait: the main thread that
## goes on to load play or authoring code finds the cache and any load in flight through
## ResourceLoader, which waits for a load another thread has started on the same path. (Joining
## the thread here would deadlock: the worker needs the main thread to finish a compile.) This
## node joins the thread in _process once it is done, then frees itself.
func finish() -> void:
	_stop = true
	if current == self:
		current = null


func _run(paths: PackedStringArray) -> void:
	var start_us := Time.get_ticks_usec()
	for path in paths:
		if _stop:
			break
		if not ResourceLoader.has_cached(path):
			ResourceLoader.load(path)
			compiled += 1
		_passed += 1
	spent_ms = (Time.get_ticks_usec() - start_us) / 1000.0
