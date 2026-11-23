class_name GroundPresses
extends RefCounted

## The presses of the tools that read the ground as it has landed, while the terraforming core's
## work is still in flight (card terraform-p2-noblock2; docs/systems/terraform.md "Never blocking").
## Part of AuthoringEditor (`AuthoringEditor.presses`), split out to keep it a readable size.
##
## With the core on, a river release, a held raise or an undo leaves work in flight for some frames:
## the session's derive on its thread, TerraEditor's landings, the bridge's water conversion and the
## height queue's spread ground. A crossing planned on the banks, a village laid on its street,
## an undo or a redo behind one of them used to finish all of it on the main thread first
## (AuthoringEditor.finish_height_work: 550 to 1030 ms on the 320 ft hilltop). Now such a press
## goes through run(): with nothing in flight it runs at once, else it waits here, in order, and the
## frame loop (AuthoringEditor.step_height_work, drain()) runs it on the first frame after the work
## has landed. That is exactly finish_height_work() followed by the press, so the press reads and
## leaves the same map either way (test_terra_noblock_presses), and no main-thread call waits.
##
## A press made inside a running one (a village's Dress laying its bridges through
## CrossingEditor.swap) runs at once, inside it. With the core off everything runs at once and the
## press's own body finishes the height work first, as before. A held stroke (Fire, Sculpt, Paint)
## cannot wait: it starts at once and may overtake a waiting press; its own edits need nothing
## landed (the fire mask, the burnt biome) or queue behind the derive as gestures (TerraEditor).

## settle_async() lets the work land over at most this many frames before finishing it.
const SETTLE_MAX_FRAMES := 1200

## How many presses have waited so far (tests, the bench).
var queued_count := 0

var _owner: WeakRef = null
## The waiting presses, oldest first.
var _waiting: Array[Callable] = []
## How deep run() is inside a press now.
var _depth := 0


static func create(editor: AuthoringEditor) -> GroundPresses:
	var presses := GroundPresses.new()
	presses._owner = weakref(editor)
	return presses


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor if _owner != null else null


## Runs `press` and returns its result, or, while the core's work is in flight (or a press already
## waits), queues it and returns `queued` (see the header).
func run(press: Callable, queued: Variant = null) -> Variant:
	var e := _editor()
	if _depth > 0 or e == null or not e.terra.active():
		return _call(press)
	if not _waiting.is_empty() or _ground_work(e):
		_waiting.append(press)
		queued_count += 1
		return queued
	return _call(press)


## Queues `press` (an undo or a redo) behind the presses waiting now, so it acts on them: true
## when it was queued, false when none waits or a press runs (the caller runs it at once).
func defer(press: Callable) -> bool:
	if _waiting.is_empty() or _depth > 0:
		return false
	_waiting.append(press)
	queued_count += 1
	return true


## A save's settle and the table move's: with the core on, the height work and the presses waiting
## for it land over frames (stepped here as the frame loop does; at most SETTLE_MAX_FRAMES, then the
## rest at once) instead of a main-thread wait, leaving the map finish_height_work() would; with it
## off, finish_height_work() as before.
func settle_async(tree: SceneTree) -> void:
	var e := _editor()
	if e == null:
		return
	if e.terra.active():
		var frames := 0
		while e.has_height_work() and frames < SETTLE_MAX_FRAMES:
			e.step_height_work()
			frames += 1
			await tree.process_frame
			if _editor() == null:
				return
	e.finish_height_work()


## True while a press runs (a press made now runs inside it, at once).
func is_running() -> bool:
	return _depth > 0


## True while a press waits for the ground.
func is_waiting() -> bool:
	return not _waiting.is_empty()


## One frame (AuthoringEditor.step_height_work, after the work's own share): runs the waiting
## presses, oldest first, while nothing is in flight; `had_work` (work was in flight when the frame
## began) keeps them for the next frame, so a press never shares a frame with the ground's last
## share.
func drain(had_work: bool) -> void:
	var e := _editor()
	if had_work or e == null:
		return
	while not _waiting.is_empty() and _depth == 0 and not _ground_work(e):
		_call(_waiting.pop_front())


## Runs every waiting press now, finishing the work before each (AuthoringEditor.finish_height_work:
## a save in a test, op_of, a peer's catch-up). Nothing while a press runs.
func finish() -> void:
	var e := _editor()
	while e != null and not _waiting.is_empty() and _depth == 0:
		_call(_waiting.pop_front())
		e.terra.finish_work()
		e.heights.finish_work()


## Forgets the waiting presses (the map goes away).
func clear() -> void:
	_waiting.clear()


static func _ground_work(e: AuthoringEditor) -> bool:
	return e.terra.has_work() or e.heights.has_work()


func _call(press: Callable) -> Variant:
	_depth += 1
	var out: Variant = press.call()
	_depth -= 1
	return out
