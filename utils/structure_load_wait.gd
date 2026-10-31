class_name StructureLoadWait
extends RefCounted

## The staged install of a map's structures (perf4): a play load makes the structures' nodes
## INSTALL_BUDGET_MS a frame (AuthoredStructures.create(..., staged = true)) instead of all in one
## frame, so the loading screen stays smooth. The load then waits here until none is left, so play
## never starts with a structure missing and a token never lands on a roof that has no collision
## yet.
## Pure helpers over the map root; the queue itself lives in AuthoredStructures
## (pending_count, install_pending, flush) and StructureInstallQueue.

## A wait that has run this many frames installs what is left at once instead of waiting on. Each
## frame installs at least one structure, so 128 structures need 128 frames at the very worst; the
## cap is above that and only guards against a node that stopped processing.
const MAX_FRAMES: int = 600
## "No limit" for AuthoredStructures.install_pending.
const NO_BUDGET_MS: float = 1.0e9


## The structure node of map root `root`, or null.
static func structures_of(root: Node) -> AuthoredStructures:
	if root == null:
		return null
	return root.get_node_or_null(NodePath(AuthoredStructures.NODE_NAME)) as AuthoredStructures


## How many structures of map root `root` are not standing yet (builds in flight or waiting for
## their node).
static func pending_of(root: Node) -> int:
	var structures := structures_of(root)
	return structures.pending_count() if structures != null else 0


## Makes every queued node of map root `root` at once. An edit calls it first, so a refresh never
## rebuilds a structure whose finished build is still waiting in the queue. Returns how many nodes
## it made.
static func settle(root: Node) -> int:
	var structures := structures_of(root)
	if structures == null or structures.pending_count() == 0:
		return 0
	return structures.install_pending(NO_BUDGET_MS)


## Forgets the queued installs of map root `root` (a load that was superseded or cancelled), so
## nothing keeps making nodes for a map that is going away.
static func cancel(root: Node) -> void:
	var structures := structures_of(root)
	if structures != null:
		structures._installs.clear()


## Waits (one frame at a time) until map root `root` has no structure left to install. `progress`
## is Callable(done: int, total: int) -> void, called each frame (may be invalid).
## `is_superseded` is Callable() -> bool; when it says so the queue is cancelled and false returns.
## True when everything stands. After MAX_FRAMES the rest is installed at once.
static func wait_async(
	tree: SceneTree, root: Node, is_superseded: Callable, progress: Callable = Callable()
) -> bool:
	if not is_instance_valid(root):
		return false
	var total := pending_of(root)
	var frames := 0
	while pending_of(root) > 0:
		if is_superseded.call():
			cancel(root)
			return false
		if progress.is_valid():
			progress.call(total - pending_of(root), total)
		var structures := structures_of(root)
		if frames >= MAX_FRAMES or not structures.is_inside_tree():
			# A node outside the tree is never processed: make its structures now.
			if frames >= MAX_FRAMES:
				push_warning(
					"StructureLoadWait: %d structures still pending after %d frames; making them now"
					% [pending_of(root), frames]
				)
			structures.flush()
			break
		frames += 1
		await tree.process_frame
		if not is_instance_valid(root):
			return false
	if progress.is_valid() and total > 0:
		progress.call(total, total)
	return true
