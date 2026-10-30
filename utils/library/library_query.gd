class_name LibraryQuery
extends RefCounted

## The asset query of a biome-def rule (design doc 2.6.3): which catalog entries a rule's
## `query` selects. Pure: it is handed the compile context (the library's catalog and its
## declared dependencies' catalogs) and returns plain dictionaries, never touching a file or the
## scene tree, so it is the same answer on a worker thread, in the compiler and in the designer's
## live "matched assets" list.
##
## Semantics, in order (deterministic; the same catalog and query give the same ids whatever
## order the catalog file lists its entries in, because every step orders by id):
## 1. Candidates are the catalog entries of this library plus those of every declared
##    dependency (a dependency's entry takes the local id `<library>__<id>`, LibraryIds), sorted
##    by that local id; a dependency's `retired` ids are left out.
## 2. A `ref` clause is explicit and not handled here (BiomeCompiler.resolve_ref), except that a
##    ref naming a GROUP instead of an entry expands to the group's variants (group_members).
## 3. Every other `match` clause is a filter: `category`, `subtype`, `group`, `ids`, `role`
##    (a contract role the catalog entry lists) and `library` (own id or a dependency's), AND-ed
##    inside the clause; the clauses are OR-ed. The query's shared `tags_all`, `tags_any`,
##    `tags_none` and `size_class` then apply to the clause matches, and `seasons` ("auto", the
##    default) drops entries whose `seasons` is not empty and lacks the season being compiled.
## 4. The survivors are grouped by the catalog `group` (an entry without one is a group of its
##    own; a dependency's group key is `<library>:<group>`) and the groups are ordered by
##    `order`: "hash" (default) by fnv1a32(salt + "|" + group) with salt "<biome id>/<rule key>",
##    ties by group id; "id" by group id; "explicit" by the position the clause `ids` list gives
##    them, the rest by group id.
## 5. `pin` names assets (an id, `<library>:<id>` or a group key) whose groups are taken FIRST,
##    in pin order, with ALL their variants, whatever the filters say; then the first `count`
##    other groups ("all" by default, a whole number from 1).
## 6. The result is every variant of every taken group, in group order and by local id inside a
##    group, capped at QUERY_MAX_ASSETS.
## A lock (biomes/<id>.lock.json: the resolved refs and the query's hash) replaces steps 3 to 6
## when the hash still matches and every ref still resolves.

const FNV_OFFSET := 0x811C9DC5
const FNV_PRIME := 0x01000193
const UINT32 := 0xFFFFFFFF
const CANDIDATE_CACHE := "query_candidates"


## 32-bit FNV-1a of the UTF-8 bytes of `text`.
static func fnv1a32(text: String) -> int:
	var hashed := FNV_OFFSET
	for byte in text.to_utf8_buffer():
		hashed = ((hashed ^ byte) * FNV_PRIME) & UINT32
	return hashed


## The ordering key of a group: fnv1a32(salt + "|" + group).
static func group_hash(salt: String, group: String) -> int:
	return fnv1a32(salt + "|" + group)


## A short hash of the query (whole floats written as ints so a JSON round trip does not change
## it): the identity a lock file records.
static func query_hash(query: Dictionary) -> String:
	return "%08x" % fnv1a32(JSON.stringify(_canonical(query), "", true))


## Whether the query selects by filter or pin at all (not only by explicit refs).
static func has_selection(query: Dictionary) -> bool:
	return not filter_clauses(query).is_empty() or not pins_of(query).is_empty()


## The `match` clauses that are filters (anything that is not a `ref` clause).
static func filter_clauses(query: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var clauses: Variant = query.get("match")
	if clauses is Array:
		for raw: Variant in clauses as Array:
			if raw is Dictionary and not (raw as Dictionary).has("ref"):
				out.append(raw)
	return out


## The query's pin list, strings only.
static func pins_of(query: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if query.get("pin") is Array:
		for raw: Variant in query["pin"] as Array:
			if raw is String and not String(raw) in out:
				out.append(raw)
	return out


## Every catalog entry a query can select, sorted by local id: [{library (that holds the GLB),
## id (its id there), local (the id it takes in the biome), ref (as a query names it), entry,
## folder, group}]. Cached in `context` for the compile.
static func candidates(context: Dictionary) -> Array[Dictionary]:
	if context.has(CANDIDATE_CACHE):
		var cached: Array[Dictionary] = []
		cached.assign(context[CANDIDATE_CACHE])
		return cached
	var out: Array[Dictionary] = []
	var own := String(context["library"])
	var catalog: Dictionary = context["catalog"]
	for id: String in catalog:
		if not LibraryContracts.scatters(catalog[id]):
			continue
		out.append(_candidate(own, id, id, catalog[id], String(context.get("folder", "")), own))
	var deps: Dictionary = context.get("deps", {})
	for library: String in deps:
		var dep: Dictionary = deps[library]
		var read: Dictionary = dep.get("read", {})
		var retired := _retired(read.get("library", {}))
		var dep_catalog: Dictionary = read.get("catalog", {})
		for id: String in dep_catalog:
			if id in retired or not LibraryContracts.scatters(dep_catalog[id]):
				continue
			out.append(
				_candidate(
					library,
					id,
					LibraryIds.dependency_local(library, id),
					dep_catalog[id],
					String(dep.get("folder", "")),
					own
				)
			)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["local"]) < String(b["local"])
	)
	context[CANDIDATE_CACHE] = out
	return out


## The variants of the group a `ref` names, when `ref` is a group and not an entry; [] when it is
## an entry or names nothing (the caller then resolves it as an entry and warns as before).
static func group_members(ref: String, context: Dictionary) -> Array[Dictionary]:
	var parts := LibraryIds.split_ref(ref)
	var none: Array[Dictionary] = []
	if parts.is_empty():
		return none
	var own := String(context["library"])
	var library := String(parts["library"])
	var want := String(parts["local"])
	var key := want if library == "" or library == own else library + ":" + want
	var found: Array[Dictionary] = []
	for candidate in candidates(context):
		if candidate["ref"] == ref or (library == "" and candidate["local"] == want):
			return none
		if candidate["group"] == key:
			found.append(candidate)
	return found


## The selection of a rule's filter clauses and pins: {found (candidates in order, capped),
## groups (the group keys taken, in order), matched (candidates the filters passed), locked
## (a lock supplied the answer), hash (the query hash)}. `scope`: {"biome": local biome id,
## "rule": key, "season": season id, "label": text for warnings, "lock": {query, assets} or
## absent}. A pin that names nothing and a stale lock append to `warnings`.
static func select(
	query: Dictionary, context: Dictionary, scope: Dictionary, warnings: Array[String]
) -> Dictionary:
	var result := {
		"found": [] as Array[Dictionary],
		"groups": [] as Array[String],
		"matched": 0,
		"locked": false,
		"hash": query_hash(query),
	}
	if not has_selection(query):
		return result
	var all := candidates(context)
	var by_ref := _by_ref(all)
	var label := String(scope.get("label", "query"))
	var lock: Variant = scope.get("lock")
	if lock is Dictionary and not (lock as Dictionary).is_empty():
		var locked := _locked(lock, query, by_ref, label, warnings)
		if not locked.is_empty():
			result["found"] = locked
			result["locked"] = true
			result["matched"] = locked.size()
			return result
	var matched := filtered(query, all, String(scope.get("season", "")))
	result["matched"] = matched.size()
	var by_group := _by_group(matched)
	var taken: Array[String] = []
	var pinned: Array[Dictionary] = []
	for pin in pins_of(query):
		var group := _pinned_group(pin, by_ref, all)
		if group == "":
			warnings.append("%s: pin '%s' names no asset or group (ignored)" % [label, pin])
		elif not group in taken:
			taken.append(group)
	var rest := _order_groups(by_group.keys(), query, by_group, scope)
	var limit := _count_of(query, rest.size())
	var added := 0
	for group in rest:
		if added >= limit:
			break
		if not group in taken:
			taken.append(group)
			added += 1
	var found: Array[Dictionary] = []
	for group in taken:
		var members: Array[Dictionary] = []
		if group in by_group and not _is_pinned(group, query, by_ref, all):
			members.assign(by_group[group])
		else:
			for candidate in all:
				if candidate["group"] == group:
					members.append(candidate)
		found.append_array(members)
	if found.size() > LibraryContracts.QUERY_MAX_ASSETS:
		warnings.append(
			(
				"%s: the query selects %d assets; the first %d are kept"
				% [label, found.size(), LibraryContracts.QUERY_MAX_ASSETS]
			)
		)
		found.resize(LibraryContracts.QUERY_MAX_ASSETS)
	result["found"] = found
	result["groups"] = taken
	return result


## The candidates the query's filter clauses and shared filters let through (no pins, no count),
## in local id order, for `season` ("" ignores the season).
static func filtered(
	query: Dictionary, all: Array[Dictionary], season: String
) -> Array[Dictionary]:
	var clauses := filter_clauses(query)
	var out: Array[Dictionary] = []
	if clauses.is_empty():
		return out
	for candidate in all:
		if not season_ok(query, candidate, season) or not shared_ok(query, candidate):
			continue
		for clause in clauses:
			if clause_matches(clause, candidate):
				out.append(candidate)
				break
	return out


## One filter clause against one candidate (category, subtype, group, ids, role, library).
static func clause_matches(clause: Dictionary, candidate: Dictionary) -> bool:
	return clause_failures(clause, candidate, true).is_empty()


## Why a candidate fails a filter clause: one short phrase per failed condition ([] when it
## matches). `first_only` stops at the first.
static func clause_failures(
	clause: Dictionary, candidate: Dictionary, first_only: bool = false
) -> Array[String]:
	var out: Array[String] = []
	var entry: Dictionary = candidate["entry"]
	for field: String in ["category", "subtype"]:
		if clause.has(field) and String(clause[field]) != String(entry.get(field, "")):
			out.append("%s is %s, not %s" % [field, String(entry.get(field, "")), clause[field]])
	if clause.has("group") and not _group_named(String(clause["group"]), candidate):
		out.append("group is %s" % _plain_group(candidate))
	if clause.has("role") and not String(clause["role"]) in _strings(entry.get("roles")):
		out.append("not used as role %s" % clause["role"])
	if clause.has("library") and not _library_named(String(clause["library"]), candidate):
		out.append("library is %s" % candidate["library"])
	if clause.has("ids") and not _id_listed(clause["ids"], candidate):
		out.append("id is not listed")
	if first_only and not out.is_empty():
		return [out[0]]
	return out


## The query's shared filters (tags and size class) against one candidate.
static func shared_ok(query: Dictionary, candidate: Dictionary) -> bool:
	return shared_failures(query, candidate).is_empty()


static func shared_failures(query: Dictionary, candidate: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var entry: Dictionary = candidate["entry"]
	var tags := _strings(entry.get("tags"))
	for tag in _strings(query.get("tags_all")):
		if not tag in tags:
			out.append("lacks tag %s" % tag)
	var any := _strings(query.get("tags_any"))
	if not any.is_empty():
		var hit := false
		for tag in any:
			hit = hit or tag in tags
		if not hit:
			out.append("has none of the tags %s" % ", ".join(any))
	for tag in _strings(query.get("tags_none")):
		if tag in tags:
			out.append("has excluded tag %s" % tag)
	var classes := _strings(query.get("size_class"))
	if not classes.is_empty() and not String(entry.get("size_class", "")) in classes:
		out.append("size class is %s" % String(entry.get("size_class", "")))
	return out


## Whether the candidate's `seasons` allows `season` under the query's seasons mode.
static func season_ok(query: Dictionary, candidate: Dictionary, season: String) -> bool:
	if String(query.get("seasons", "auto")) != "auto" or season == "":
		return true
	var seasons := _strings((candidate["entry"] as Dictionary).get("seasons"))
	return seasons.is_empty() or season in seasons


## Why a candidate is not in the selection: the failed conditions of the clause it came
## closest to ([] when the filters accept it), with the season's.
static func why_not(query: Dictionary, candidate: Dictionary, season: String = "") -> Array[String]:
	var clauses := filter_clauses(query)
	var best: Array[String] = []
	var first := true
	for clause in clauses:
		var failures := clause_failures(clause, candidate)
		if first or failures.size() < best.size():
			best = failures
			first = false
	if clauses.is_empty():
		best.append("the query has no filter clause")
	best.append_array(shared_failures(query, candidate))
	if not season_ok(query, candidate, season):
		best.append("not in season %s" % season)
	return best


# ---- helpers ----


static func _candidate(
	library: String, id: String, local: String, entry: Dictionary, folder: String, own: String
) -> Dictionary:
	var group := String(entry.get("group", ""))
	if group == "":
		group = id
	return {
		"library": library,
		"id": id,
		"local": local,
		"ref": id if library == own else library + ":" + id,
		"entry": entry,
		"folder": folder,
		"group": group if library == own else library + ":" + group,
	}


static func _by_ref(all: Array[Dictionary]) -> Dictionary:
	var out := {}
	for candidate in all:
		out[candidate["ref"]] = candidate
		out[candidate["local"]] = candidate
	return out


static func _by_group(matched: Array[Dictionary]) -> Dictionary:
	var out := {}
	for candidate in matched:
		var members: Array = out.get(candidate["group"], [])
		members.append(candidate)
		out[candidate["group"]] = members
	return out


static func _pinned_group(pin: String, by_ref: Dictionary, all: Array[Dictionary]) -> String:
	if by_ref.has(pin):
		return String(by_ref[pin]["group"])
	for candidate in all:
		if candidate["group"] == pin:
			return pin
	return ""


static func _is_pinned(
	group: String, query: Dictionary, by_ref: Dictionary, all: Array[Dictionary]
) -> bool:
	for pin in pins_of(query):
		if _pinned_group(pin, by_ref, all) == group:
			return true
	return false


static func _order_groups(
	groups: Array, query: Dictionary, by_group: Dictionary, scope: Dictionary
) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(groups)
	var order := String(query.get("order", "hash"))
	var salt := "%s/%s" % [String(scope.get("biome", "")), String(scope.get("rule", ""))]
	var rank := {}
	if order == "explicit":
		rank = _explicit_rank(query, by_group)
	ids.sort_custom(
		func(a: String, b: String) -> bool:
			match order:
				"id":
					return a < b
				"explicit":
					var ra: int = rank.get(a, 1 << 30)
					var rb: int = rank.get(b, 1 << 30)
					return ra < rb or (ra == rb and a < b)
			var ha := group_hash(salt, a)
			var hb := group_hash(salt, b)
			return ha < hb or (ha == hb and a < b)
	)
	return ids


## Group key -> position of its first member in the clauses' `ids` lists.
static func _explicit_rank(query: Dictionary, by_group: Dictionary) -> Dictionary:
	var listed: Array[String] = []
	for clause in filter_clauses(query):
		listed.append_array(_strings(clause.get("ids")))
	var rank := {}
	for group: String in by_group:
		for candidate: Dictionary in by_group[group]:
			for position in listed.size():
				if listed[position] in [candidate["ref"], candidate["local"]]:
					rank[group] = mini(rank.get(group, 1 << 30), position)
	return rank


static func _count_of(query: Dictionary, available: int) -> int:
	var count: Variant = query.get("count", "all")
	if count is String or count == null:
		return available
	if (count is int or count is float) and float(count) >= 1.0:
		return mini(int(count), available)
	return available


static func _locked(
	lock: Dictionary, query: Dictionary, by_ref: Dictionary, label: String, warnings: Array[String]
) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if String(lock.get("query", "")) != query_hash(query):
		warnings.append("%s: the lock file is stale (the query changed); resolved again" % label)
		return none
	var out: Array[Dictionary] = []
	for ref in _strings(lock.get("assets")):
		if not by_ref.has(ref):
			warnings.append(
				(
					"%s: the lock file names '%s', which the catalogs lack; resolved again"
					% [label, ref]
				)
			)
			return none
		out.append(by_ref[ref])
	return out


static func _group_named(wanted: String, candidate: Dictionary) -> bool:
	return wanted == candidate["group"] or wanted == _plain_group(candidate)


## The group as its own catalog names it (a dependency's without the `<library>:` prefix).
static func _plain_group(candidate: Dictionary) -> String:
	var group := String(candidate["group"])
	var prefix := String(candidate["library"]) + ":"
	if group.begins_with(prefix) and candidate["ref"] != candidate["id"]:
		return group.substr(prefix.length())
	return group


static func _library_named(wanted: String, candidate: Dictionary) -> bool:
	return wanted == candidate["library"] or (wanted == "" and candidate["ref"] == candidate["id"])


static func _id_listed(ids: Variant, candidate: Dictionary) -> bool:
	for id in _strings(ids):
		if id == candidate["ref"] or id == candidate["local"]:
			return true
	return false


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value as Array:
			if item is String:
				out.append(item)
	return out


static func _retired(library: Dictionary) -> Array[String]:
	return _strings(library.get("retired"))


## `value` with whole floats turned into ints (recursively), the form query_hash hashes.
static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value as Dictionary:
			out[key] = _canonical((value as Dictionary)[key])
		return out
	if value is Array:
		var items := []
		for item: Variant in value as Array:
			items.append(_canonical(item))
		return items
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 1e15:
		return int(value)
	return value
