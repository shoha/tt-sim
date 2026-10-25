class_name DesignerLocks
extends RefCounted

## The designer's lock commands and the words about locks (step S9; the lock file itself is
## LibraryQuery's and LibraryWriter's): a LOCK freezes which assets a rule's query picks in each
## season, as the refs and the hash of the query that gave them; Save writes `biomes/<id>.lock.json`
## and the compiler uses a lock while its query's hash still matches. These are static functions
## over a BiomeDesignerModel (its `locks` is {"<season>/<rule key>": {query, assets}}), so the
## model stays inside its method budget: `lock_rule` (the model's own set_locked calls it),
## `set_all`, `refresh`, `state` and `summary`.

## The worst state wins when a rule is locked in several seasons.
const RANKS: Array[String] = ["locked", "stale_catalog", "stale_query"]


## Takes (`on`) or drops rule `key`'s lock in every season it grows in. No signal: the caller
## bumps the model's revision.
static func lock_rule(model: BiomeDesignerModel, key: String, on: bool) -> void:
	for season in model.season_ids():
		var lock_key := "%s/%s" % [season, key]
		if not on:
			model.locks.erase(lock_key)
		elif not BiomeSeasons.rule_in(model.def, key, season).is_empty():
			model.locks[lock_key] = fresh(model, key, season)


## The lock for rule `key` in `season` taken from its query as the season sees it: the query's
## hash and the refs its selection gives now.
static func fresh(model: BiomeDesignerModel, key: String, season: String) -> Dictionary:
	var query: Dictionary = BiomeSeasons.rule_in(model.def, key, season).get("query", {})
	var warnings: Array[String] = []
	var scope := {"biome": model.biome_id, "rule": key, "season": season, "label": "rule " + key}
	var picked := LibraryQuery.select(query, model.query_context(), scope, warnings)
	var refs: Array[String] = []
	for found: Dictionary in picked["found"]:
		refs.append(String(found["ref"]))
	return {"query": LibraryQuery.query_hash(query), "assets": refs}


## Locks (or unlocks) every rule of the biome in one step; false when nothing changes.
static func set_all(model: BiomeDesignerModel, on: bool) -> bool:
	var any := false
	for key in model.rule_keys():
		if on != model.is_locked(key):
			lock_rule(model, key, on)
			any = true
	if any:
		model.revision += 1
		model.changed.emit("Lock all" if on else "Unlock all")
	return any


## Takes rule `key`'s lock again from its query as it is now ("Lock again" on a stale lock).
static func refresh(model: BiomeDesignerModel, key: String) -> bool:
	if not model.is_locked(key):
		return false
	lock_rule(model, key, true)
	model.revision += 1
	model.changed.emit("Lock")
	return true


## How rule `key`'s lock stands: {state, seasons}. `state`: `unlocked`; `locked` (the plants the
## query gives now are the plants the lock holds); `stale_query` (the query changed since the lock
## was taken, so the compiler ignores the lock and warns); `stale_catalog` (the query is the same
## but the catalogs now give other plants than the lock holds). `seasons`: {season: {state, held:
## [refs], now: [refs]}} for the seasons the rule is locked in.
static func state(model: BiomeDesignerModel, key: String) -> Dictionary:
	var out := {"state": "unlocked", "seasons": {}}
	var worst := 0
	for season in model.season_ids():
		var lock: Variant = model.locks.get("%s/%s" % [season, key])
		if not lock is Dictionary:
			continue
		var taken := fresh(model, key, season)
		var kind := "locked"
		if String((lock as Dictionary).get("query", "")) != String(taken["query"]):
			kind = "stale_query"
		elif (lock as Dictionary).get("assets", []) != taken["assets"]:
			kind = "stale_catalog"
		out["seasons"][season] = {
			"state": kind, "held": (lock as Dictionary).get("assets", []), "now": taken["assets"]
		}
		worst = maxi(worst, RANKS.find(kind))
	if not (out["seasons"] as Dictionary).is_empty():
		out["state"] = RANKS[worst]
	return out


## {locked: rules with a lock, stale: of those how many are stale, saved: how many have a lock
## in the file as last saved, total: all rules} for the biome.
static func summary(model: BiomeDesignerModel) -> Dictionary:
	var locked := 0
	var stale := 0
	var saved := 0
	var written := model.saved_locks()
	for key in model.rule_keys():
		var kind := String(state(model, key)["state"])
		if kind != "unlocked":
			locked += 1
		if kind == "stale_query" or kind == "stale_catalog":
			stale += 1
		for season in model.season_ids():
			if written.has("%s/%s" % [season, key]):
				saved += 1
				break
	return {"locked": locked, "stale": stale, "saved": saved, "total": model.rule_keys().size()}


## Whether the draft's locks differ from the lock file as last saved.
static func changed(model: BiomeDesignerModel) -> bool:
	return model.locks.hash() != model.saved_locks().hash()
