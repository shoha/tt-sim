class_name StructureInstallQueue
extends RefCounted

## The landed builds of AuthoredStructures that wait for their node (perf3): making a node costs
## 2 to 5 ms on the main thread, so a burst of builds (20 adds, a staged load of 128) is installed a
## few a frame instead of all in one. One entry per structure id: {"id", "key", "parts", "seq"}
## where
## `seq` counts the builds started, so a later build has the higher number.
## Order of service (best_index): an entry prioritize() named, then one that replaces a node already
## standing (an edit or a drag preview, which the player is looking at), then the newest build.

const RANK_REPLACES := 1 << 40
const RANK_URGENT := 1 << 50

var entries: Array[Dictionary] = []
var _urgent: Dictionary = {}


func size() -> int:
	return entries.size()


func is_empty() -> bool:
	return entries.is_empty()


func clear() -> void:
	entries.clear()
	_urgent.clear()


## Queues `parts` for structure `id`, replacing the entry it already had.
func push(id: int, key: int, parts: Dictionary, seq: int) -> void:
	erase(id)
	entries.append({"id": id, "key": key, "parts": parts, "seq": seq})


## Forgets structure `id`'s entry and its priority.
func erase(id: int) -> void:
	for k in entries.size():
		if int(entries[k].id) == id:
			entries.remove_at(k)
			break
	_urgent.erase(id)


## Marks structure `id` to be served before every other entry.
func prioritize(id: int) -> void:
	_urgent[id] = true


## Drops the entries of ids `keys` (a Dictionary keyed by id) does not hold.
func retain(keys: Dictionary) -> void:
	for entry in entries.duplicate():
		if not keys.has(int(entry.id)):
			erase(int(entry.id))


## Removes and returns the entry to serve next (null when empty). `standing` is a Callable(id) ->
## bool: whether the structure has a node now.
func pop_best(standing: Callable) -> Variant:
	var best := -1
	var best_rank := -1
	for k in entries.size():
		var entry: Dictionary = entries[k]
		var rank := int(entry.seq)
		if _urgent.has(entry.id):
			rank += RANK_URGENT
		if bool(standing.call(int(entry.id))):
			rank += RANK_REPLACES
		if rank > best_rank:
			best_rank = rank
			best = k
	if best < 0:
		return null
	var chosen: Dictionary = entries[best]
	entries.remove_at(best)
	_urgent.erase(chosen.id)
	return chosen
