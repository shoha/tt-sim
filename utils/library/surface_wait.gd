class_name SurfaceWait
extends RefCounted

## Work a panel does with library surface maps once the prebake lane has them, so building a
## panel never bakes in its own frame (card authbake: the authoring open's first frame baked the
## nine biome tiles' ground albedos, 2.7 to 2.8 s on a cold cache, perfaudit sysbake).
##
## A caller names the maps its work reads (palette-relative paths) and hands over the work. The
## maps are queued on the lane (SurfaceStore.prebake_paths); while any of them is queued or
## baking (SurfaceStore.is_pending) the work waits, else it runs, at once when nothing had to be
## queued. Each frame runs waiting work in the order it came, within the load's frame budget
## (MapSourceLoader.frame_budget_usec) and at least one piece. A picture made this way is shown
## at once as a placeholder texture the work repaints in place (ImageTexture.set_image keeps the
## texture, so every control showing it updates): BiomeThumbnail.of's `deferred`.
##
## Start-up code reaches it by path (SURFACE_WAIT, load() on first use), not by class name, so the
## start-up script graph does not grow (test_boot_graph.gd).

## False runs every piece of work at once, its bakes in the caller's frame as before card
## authbake: the performance harness's in-run A/B switch (perfaudit_system.gd `prebake`
## "nopanel"). A disabled lane (SurfaceStore.prebake_enabled) does the same.
static var enabled: bool = true
## [{root, relatives, work}] waiting, oldest first.
static var _waiting: Array[Dictionary] = []


## Runs `work` (func() -> void) once no map of `relatives` (palette-relative paths under `root`)
## is queued or baking on the lane, after queueing the ones not in memory at `priority`
## (SurfaceStore.PRIORITY_*). Returns true when it ran at once, false when it waits for a later
## frame.
static func call_when_ready(
	root: String, relatives: PackedStringArray, priority: int, work: Callable
) -> bool:
	if enabled and SurfaceStore.prebake_enabled:
		SurfaceStore.prebake_paths(root, relatives, priority)
		if _pending(root, relatives):
			_waiting.append({"root": root, "relatives": relatives, "work": work})
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null and not tree.process_frame.is_connected(_poll):
				tree.process_frame.connect(_poll)
			return false
	work.call()
	return true


## Runs `work` (func() -> void) in a later frame, within that frame's budget, behind the work
## already waiting: a picture painted from the maps' files (SurfaceStore.picture_image, which
## never bakes) still costs a few ms, so a panel of them spreads over frames (card coldopen).
## Runs it at once when not enabled.
static func later(work: Callable) -> void:
	if not enabled:
		work.call()
		return
	_waiting.append({"root": "", "relatives": PackedStringArray(), "work": work})
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_poll):
		tree.process_frame.connect(_poll)


## How many pieces of work wait.
static func waiting() -> int:
	return _waiting.size()


## Runs the waiting work whose maps are done, oldest first, within the frame budget.
static func _poll() -> void:
	var started := Time.get_ticks_usec()
	var budget := MapSourceLoader.frame_budget_usec()
	var ran := false
	var i := 0
	while i < _waiting.size():
		if ran and Time.get_ticks_usec() - started >= budget:
			break
		var entry: Dictionary = _waiting[i]
		if _pending(String(entry["root"]), entry["relatives"]):
			i += 1
			continue
		_waiting.remove_at(i)
		(entry["work"] as Callable).call()
		ran = true
	if _waiting.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.process_frame.is_connected(_poll):
			tree.process_frame.disconnect(_poll)


static func _pending(root: String, relatives: PackedStringArray) -> bool:
	for relative in relatives:
		if SurfaceStore.is_pending(root, relative):
			return true
	return false
