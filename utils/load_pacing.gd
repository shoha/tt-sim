class_name LoadPacing
extends RefCounted

## How fast a map load may run while nobody can see the table (perfaudit F-system-3).
##
## A load does its work in slices, one slice a frame, so a frame never stalls the window. With
## vsync on, every slice then waits for the next refresh: at 60 Hz an 8 ms slice spent half of
## each frame idle, and a load took about twice its work (0.81 s against 1.57 s at 320 ft). While
## a map load's sheet covers the screen (LoadingOverlay.show_loading: the painted backdrop hides
## the table being built), nothing the frames draw is seen, so pacing them to the display buys
## nothing. Covered:
##
## - the window's vsync is turned off, so a frame that has done its slice starts the next at once
##   (no tearing can show: the backdrop is the only thing on screen);
## - budget_usec() raises a loader's per-frame budget to COVERED_BUDGET_USEC, so the frames that
##   remain each carry more work (the bar and its caption still move a few times a second).
##
## Uncovered (the sheet gone, or the scrim of a wait over a live screen) the player's vsync mode
## is put back as it was and every caller's own budget stands. Covers are counted by owner
## (cover(owner) / uncover(owner)), so two overlays, or an overlay freed while showing, cannot
## leave vsync off: LoadingOverlay uncovers in hide_loading() and again on leaving the tree.

## The per-frame budget of a load slice while covered.
const COVERED_BUDGET_USEC := 12000
## The frame-rate cap while covered (Engine.max_fps, when the player's is off or higher). Without
## vsync a frame that only waits on a worker thread takes about 0.5 ms, so an authoring open spun
## about 3500 frames of the backdrop (measured 2026-11-08), a core and the GPU busy for nothing; at
## this cap a wait frame takes about 4 ms and a working frame is unaffected.
const COVERED_MAX_FPS := 240

## False turns the policy off (covers are ignored, budgets stand): the performance harness's
## in-run A/B switch (tools/render_jobs/probes/perfaudit_system.gd `pacing`).
static var enabled := true
## Instance ids of the owners covering the screen now.
static var _owners: Dictionary = {}
## The vsync mode in force before the first cover, put back by the last uncover; -1 when uncovered.
static var _saved_vsync := -1
## Engine.max_fps before the first cover, put back by the last uncover.
static var _saved_max_fps := 0


## Marks the screen covered by `owner` (a LoadingOverlay showing a map load).
static func cover(owner: Object) -> void:
	if owner == null or not enabled:
		return
	var was_covered := is_covered()
	_owners[owner.get_instance_id()] = true
	if not was_covered:
		_saved_vsync = DisplayServer.window_get_vsync_mode()
		if _saved_vsync != DisplayServer.VSYNC_DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_saved_max_fps = Engine.max_fps
		if _saved_max_fps == 0 or _saved_max_fps > COVERED_MAX_FPS:
			Engine.max_fps = COVERED_MAX_FPS


## Ends `owner`'s cover; the last one out puts the vsync mode back. Safe to call twice.
static func uncover(owner: Object) -> void:
	if owner == null or not _owners.erase(owner.get_instance_id()):
		return
	if is_covered():
		return
	if _saved_vsync >= 0 and _saved_vsync != DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(_saved_vsync as DisplayServer.VSyncMode)
	_saved_vsync = -1
	Engine.max_fps = _saved_max_fps


## Whether a map load's sheet covers the screen now.
static func is_covered() -> bool:
	return not _owners.is_empty()


## The per-frame budget a load slice may spend: `uncovered_usec` normally, at least
## COVERED_BUDGET_USEC while covered.
static func budget_usec(uncovered_usec: int) -> int:
	return maxi(uncovered_usec, COVERED_BUDGET_USEC) if is_covered() else uncovered_usec
