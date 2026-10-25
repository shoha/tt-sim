class_name LibraryResolver
extends RefCounted

## Which of the libraries found on disk can be served, and in what order (design doc 2.3, 2.9,
## 2.10 and 3.2 module 5). Pure over dictionaries: LibraryRegistry scans folders and reads the
## files, this decides. A library that cannot be served is never a crash; it is an entry with
## status "error" and the reasons a manager shows.
##
## Input entries (one per library folder found, in any order):
##   {id, version, source ("official", "user" or "dev"), folder, enabled (bool), read_ok (bool),
##    reasons (Array[String], problems already found), dependencies: [{id, version (a range)}]}
## `builtin` is the core library the game ships inside its palette ({id, version}); it provides
## `core` when no folder does, so `core: ^1.0` is met on a game with no libraries/core folder yet.
##
## Rules:
## - Duplicate ids: an official library beats a user one; among user libraries the folder name
##   sorted first wins; the rest are errors that name the winner. A "dev" entry (the developer
##   override) is never a duplicate: it is served after the others and replaces biomes of the
##   same runtime id, as the override always did.
## - A disabled library is "disabled", not an error; a library that needs a disabled one is an
##   error that says so.
## - A dependency must be installed, enabled, available and satisfy its version range; chains
##   are at most LibraryContracts.MAX_DEPENDENCY_DEPTH deep and may not cycle.
## - At most LibraryContracts.MAX_ACTIVE_LIBRARIES are served; later ones in load order are
##   errors.
##
## resolve() returns {entries (annotated copies: status "ok", "error" or "disabled", reasons,
## provides: how each dependency was met), order (indexes of the "ok" entries in load order:
## dependencies first, core first, then by id, dev entries last)}.

const OK := "ok"
const ERROR := "error"
const DISABLED := "disabled"
const BUILTIN := -2


static func resolve(entries: Array[Dictionary], builtin: Dictionary = {}) -> Dictionary:
	var out: Array[Dictionary] = []
	for entry in entries:
		var copy := entry.duplicate(true)
		copy["status"] = OK if bool(copy.get("read_ok", true)) else ERROR
		copy["reasons"] = (copy.get("reasons", []) as Array).duplicate()
		copy["provides"] = {}
		out.append(copy)
	_mark_duplicates(out)
	for entry in out:
		if entry["status"] == OK and not bool(entry.get("enabled", true)):
			entry["status"] = DISABLED
	var providers := _providers(out, builtin)
	var state := {}
	for i in out.size():
		_settle(i, out, providers, builtin, state, [])
	var order := _load_order(out)
	var active := 0
	var kept: Array[int] = []
	for i in order:
		active += 1
		if active > LibraryContracts.MAX_ACTIVE_LIBRARIES:
			out[i]["status"] = ERROR
			(out[i]["reasons"] as Array).append(
				"more than %d libraries are active" % LibraryContracts.MAX_ACTIVE_LIBRARIES
			)
		else:
			kept.append(i)
	return {"entries": out, "order": kept}


## Errors every non-dev entry that shares an id with a better one (official, then folder name).
static func _mark_duplicates(entries: Array[Dictionary]) -> void:
	var groups := {}
	for i in entries.size():
		if entries[i].get("source") == "dev":
			continue
		var id := String(entries[i].get("id", ""))
		if id == "":
			continue
		var group: Array = groups.get(id, [])
		group.append(i)
		groups[id] = group
	for id: String in groups:
		var group: Array = groups[id]
		if group.size() < 2:
			continue
		group.sort_custom(
			func(a: int, b: int) -> bool:
				var left_official := bool(entries[a].get("official", false))
				var right_official := bool(entries[b].get("official", false))
				if left_official != right_official:
					return left_official
				# A library received from a host (a partial, transient) beats an installed one
				# only when it is a strictly newer version of it; the player's own copy wins ties.
				var left_received: bool = entries[a].get("source") == "received"
				var right_received: bool = entries[b].get("source") == "received"
				if left_received != right_received:
					var cmp := LibraryVersions.compare(
						String(entries[a].get("version", "")), String(entries[b].get("version", ""))
					)
					if cmp != 0:
						return cmp > 0
					return right_received
				return String(entries[a].get("folder", "")) < String(entries[b].get("folder", ""))
		)
		var winner: Dictionary = entries[group[0]]
		for k in range(1, group.size()):
			var loser: Dictionary = entries[group[k]]
			loser["status"] = ERROR
			var which := "the official library"
			if not winner.get("official", false):
				which = "'%s'" % winner.get("folder", "")
			(loser["reasons"] as Array).append(
				"duplicate library id '%s': %s is used instead" % [id, which]
			)


## id -> index of the entry that provides it (the duplicate winner, else a dev entry), or BUILTIN.
static func _providers(entries: Array[Dictionary], builtin: Dictionary) -> Dictionary:
	var providers := {}
	for i in entries.size():
		var id := String(entries[i].get("id", ""))
		if id == "" or entries[i].get("source") == "dev":
			continue
		if not providers.has(id) and not _is_loser(entries[i]):
			providers[id] = i
	for i in entries.size():
		var id := String(entries[i].get("id", ""))
		if id != "" and entries[i].get("source") == "dev" and not providers.has(id):
			providers[id] = i
	if not builtin.is_empty() and not providers.has(String(builtin.get("id", ""))):
		providers[String(builtin["id"])] = BUILTIN
	return providers


static func _is_loser(entry: Dictionary) -> bool:
	for reason: String in entry["reasons"]:
		if reason.begins_with("duplicate library id"):
			return true
	return false


## Decides entry `i` (depth first, so its dependencies are decided before it). `stack` is the
## chain of entry indexes being decided, for cycle and depth detection. Returns the chain depth.
static func _settle(
	i: int,
	entries: Array[Dictionary],
	providers: Dictionary,
	builtin: Dictionary,
	state: Dictionary,
	stack: Array
) -> int:
	if state.has(i):
		return int(state[i])
	var entry: Dictionary = entries[i]
	if entry["status"] != OK:
		state[i] = 0
		return 0
	if i in stack:
		entry["status"] = ERROR
		(entry["reasons"] as Array).append("dependency cycle: " + _chain(stack, i, entries))
		state[i] = 0
		return 0
	stack.append(i)
	var depth := 0
	for dep: Dictionary in entry.get("dependencies", []):
		var need := String(dep.get("id", ""))
		var wanted := String(dep.get("version", "*"))
		var provider := _provider_of(need, entries, providers, builtin, state, stack)
		var reason := _dependency_problem(need, wanted, provider, entries, builtin)
		if reason != "":
			entry["status"] = ERROR
			(entry["reasons"] as Array).append(reason)
			continue
		if provider == BUILTIN:
			entry["provides"][need] = "built in"
			depth = maxi(depth, 1)
		else:
			entry["provides"][need] = String(entries[provider]["version"])
			depth = maxi(depth, int(state.get(provider, 0)) + 1)
	stack.pop_back()
	if entry["status"] == OK and depth > LibraryContracts.MAX_DEPENDENCY_DEPTH:
		entry["status"] = ERROR
		(entry["reasons"] as Array).append(
			"dependencies are nested deeper than %d" % LibraryContracts.MAX_DEPENDENCY_DEPTH
		)
	state[i] = depth
	return depth


## The entry index that meets dependency `need` once it is decided, BUILTIN when the game's own
## core does (no folder provides it, or the folder that does is unavailable), or -1.
static func _provider_of(
	need: String,
	entries: Array[Dictionary],
	providers: Dictionary,
	builtin: Dictionary,
	state: Dictionary,
	stack: Array
) -> int:
	if not providers.has(need):
		return -1
	var provider: int = providers[need]
	if provider == BUILTIN:
		return BUILTIN
	_settle(provider, entries, providers, builtin, state, stack)
	if entries[provider]["status"] != OK and need == String(builtin.get("id", "")):
		return BUILTIN
	return provider


## "" when dependency `need` (range `wanted`) is met by `provider`, else the reason it is not.
static func _dependency_problem(
	need: String, wanted: String, provider: int, entries: Array[Dictionary], builtin: Dictionary
) -> String:
	if provider == -1:
		return (
			"needs library '%s' %s, which is not installed"
			% [need, LibraryVersions.describe(wanted)]
		)
	var have := String(builtin.get("version", ""))
	if provider != BUILTIN:
		var other: Dictionary = entries[provider]
		have = String(other.get("version", ""))
		if other["status"] == DISABLED:
			return "needs library '%s', which is disabled" % need
		if other["status"] != OK:
			return "needs library '%s', which is unavailable" % need
	if not LibraryVersions.satisfies(have, wanted):
		return (
			"needs library '%s' %s, but %s is installed"
			% [need, LibraryVersions.describe(wanted), have if have != "" else "no version"]
		)
	return ""


static func _chain(stack: Array, back_to: int, entries: Array[Dictionary]) -> String:
	var names: Array[String] = []
	var started := false
	for index: int in stack:
		if index == back_to:
			started = true
		if started:
			names.append(String(entries[index].get("id", "?")))
	names.append(String(entries[back_to].get("id", "?")))
	return " -> ".join(names)


## The indexes of the "ok" entries in load order: dependencies before the libraries that need
## them, core first, then ascending id, dev entries after every other.
static func _load_order(entries: Array[Dictionary]) -> Array[int]:
	var candidates: Array[int] = []
	for i in entries.size():
		if entries[i]["status"] == OK:
			candidates.append(i)
	candidates.sort_custom(
		func(a: int, b: int) -> bool: return _sort_key(entries[a]) < _sort_key(entries[b])
	)
	var order: Array[int] = []
	var placed := {}
	for i in candidates:
		_place(i, candidates, entries, placed, order)
	return order


static func _sort_key(entry: Dictionary) -> String:
	var id := String(entry.get("id", ""))
	var group := "1"
	if entry.get("source") == "dev":
		group = "2"
	elif id == LibraryContracts.CORE_ID:
		group = "0"
	return group + id + "|" + String(entry.get("folder", ""))


static func _place(
	i: int, candidates: Array[int], entries: Array[Dictionary], placed: Dictionary, order: Array[int]
) -> void:
	if placed.has(i):
		return
	placed[i] = true
	for dep: Dictionary in entries[i].get("dependencies", []):
		for j in candidates:
			# A dev entry is placed with the dev group even when it provides a dependency.
			if entries[j]["id"] == dep.get("id") and j != i:
				_place(j, candidates, entries, placed, order)
				break
	order.append(i)
