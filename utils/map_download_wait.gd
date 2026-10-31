class_name MapDownloadWait
extends RefCounted

## The client's side of a staged load (staged_load2): a map that has to be downloaded is loaded and
## finalised by MapDownloadCoordinator after its files arrive, so the level load that asked for it
## waits here until the coordinator is done (its files in, the map built and installed, and every
## structure of it standing: LevelPlayLoader._finalize_map_loading waits for those with
## StructureLoadWait) before it sets any token down. Without the wait a client's tokens landed
## while the roofs under them had no collision yet, or before the map existed at all.


## Waits (a frame at a time) while `is_busy` (Callable() -> bool, MapDownloadCoordinator.is_busy)
## says a map is downloading or being finalised. `is_superseded` is Callable() -> bool: when it
## says so the wait ends and false returns (the caller drops its load). `on_wait` is called once,
## when the first frame is waited (the loading bar's text; may be invalid). True when the map is
## in. The wait itself has no limit of its own: the download ends in the streamer's success or
## failure signals, a reset ends it too, and the structure wait inside the finalise is bounded
## (StructureLoadWait.MAX_FRAMES, which logs and continues).
static func wait_async(
	tree: SceneTree, is_busy: Callable, is_superseded: Callable, on_wait: Callable = Callable()
) -> bool:
	var announced := false
	while is_busy.call():
		if is_superseded.call():
			return false
		if not announced and on_wait.is_valid():
			on_wait.call()
			announced = true
		await tree.process_frame
	return not is_superseded.call()
