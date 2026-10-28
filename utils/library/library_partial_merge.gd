class_name LibraryPartialMerge
extends RefCounted

## Merging a DELTA partial into a partial library already kept from the same host (docs/systems/
## library.md "The cache of downloaded collections"). Pure over file dictionaries ({relative path:
## bytes}); the caller reads the existing folder, runs LibraryPartial.inspect on the result (every
## hash, the reader, the compile dry-run: the merged library is checked as hard as a fresh one)
## and writes it. A delta is itself a valid partial (the host cut it for the missing assets), so
## the merge is a union:
##   - library.json: the existing one, its `partial` block widened (assets, biomes, surfaces,
##     bytes);
##   - assets/catalog.json: the existing entries, then the delta's new ones (an id in both must
##     carry the same sha256);
##   - biomes/<id>.json: a biome in both has its rules united by key (the refs of a rule in both
##     united by ref, near and avoid relations united), a biome only in the delta is added;
##   - every other file (GLBs, surface maps): a path in both must hold the same bytes.
## Both sides must be the same library at the same version cut from the same source hash, else the
## answer is "changed" and the caller replaces the kept copy instead of merging.

const E_MERGE := "merge"
const E_CHANGED := "changed"


## {ok, code, error, files}: `current` united with `delta`.
static func merge(current: Dictionary, delta: Dictionary) -> Dictionary:
	var out := {"ok": false, "code": "", "error": "", "files": {}}
	var left := _json(current.get(LibraryPartial.LIBRARY_FILE, PackedByteArray()))
	var right := _json(delta.get(LibraryPartial.LIBRARY_FILE, PackedByteArray()))
	var problem := _same_source(left, right)
	if problem != "":
		return _fail(out, E_CHANGED, problem)
	var files := current.duplicate()
	for path: String in delta:
		if _is_special(path):
			continue
		if files.has(path):
			if files[path] != delta[path]:
				return _fail(out, E_MERGE, "%s differs between the kept copy and the delta" % path)
		else:
			files[path] = delta[path]
	var catalog := _merge_catalog(current, delta)
	if catalog.has("error"):
		return _fail(out, E_MERGE, String(catalog["error"]))
	files[LibraryPartial.CATALOG_FILE] = LibraryPartial.json_bytes(catalog)
	if current.has(LibraryStructures.INDEX_FILE) or delta.has(LibraryStructures.INDEX_FILE):
		var united := LibraryStructures.merge_index(
			current.get(LibraryStructures.INDEX_FILE), delta.get(LibraryStructures.INDEX_FILE)
		)
		if not united["ok"]:
			return _fail(out, E_MERGE, String(united["error"]))
		files[LibraryStructures.INDEX_FILE] = String(united["text"]).to_utf8_buffer()
	for path: String in delta:
		if not (path.begins_with("biomes/") and path.ends_with(".json")):
			continue
		if not current.has(path):
			files[path] = delta[path]
			continue
		var merged := merge_biome(_json(current[path]), _json(delta[path]))
		if merged.is_empty():
			return _fail(out, E_MERGE, "%s cannot be united with the kept one" % path)
		files[path] = LibraryPartial.json_bytes(merged)
	files[LibraryPartial.LIBRARY_FILE] = LibraryPartial.json_bytes(
		_merge_library(left, right, files)
	)
	out["files"] = files
	out["ok"] = true
	return out


## The two biome-defs united by rule key; {} when they are not the same biome. Pure.
static func merge_biome(left: Dictionary, right: Dictionary) -> Dictionary:
	if left.is_empty() or right.is_empty() or left.get("id") != right.get("id"):
		return {}
	var out := left.duplicate(true)
	var rules: Array = []
	var by_key := {}
	for raw: Variant in out.get("rules", []):
		if raw is Dictionary:
			rules.append(raw)
			by_key[String((raw as Dictionary).get("key", ""))] = raw
	for raw: Variant in right.get("rules", []):
		if not raw is Dictionary:
			continue
		var rule: Dictionary = raw
		var key := String(rule.get("key", ""))
		if by_key.has(key):
			_unite_rule(by_key[key], rule)
		else:
			rules.append(rule.duplicate(true))
			by_key[key] = rules.back()
	for rule: Dictionary in rules:
		_drop_dead_relations(rule, by_key)
	out["rules"] = rules
	return out


static func _unite_rule(into: Dictionary, other: Dictionary) -> void:
	var query: Variant = into.get("query")
	var more: Variant = (other.get("query", {}) as Dictionary).get("match")
	if query is Dictionary and more is Array:
		var refs: Array = (query as Dictionary).get("match", [])
		var seen := {}
		for clause: Variant in refs:
			if clause is Dictionary:
				seen[String((clause as Dictionary).get("ref", ""))] = true
		for clause: Variant in more as Array:
			if clause is Dictionary and not seen.has(String((clause as Dictionary).get("ref", ""))):
				refs.append((clause as Dictionary).duplicate(true))
		(query as Dictionary)["match"] = refs
	for field in ["near", "avoid"]:
		if not other.get(field) is Array:
			continue
		var held: Array = into.get(field, [])
		var texts := {}
		for item: Variant in held:
			texts[JSON.stringify(item, "", true)] = true
		for item: Variant in other[field] as Array:
			if not texts.has(JSON.stringify(item, "", true)):
				held.append(item)
		into[field] = held


static func _drop_dead_relations(rule: Dictionary, keys: Dictionary) -> void:
	for field in ["near", "avoid"]:
		if not rule.get(field) is Array:
			continue
		var live: Array = []
		for item: Variant in rule[field] as Array:
			if item is Dictionary and (item as Dictionary).get("rule") is String:
				if not keys.has(String((item as Dictionary)["rule"])):
					continue
			live.append(item)
		rule[field] = live


## "" when the two library.json files are the same library, version and source, else why not.
static func _same_source(left: Dictionary, right: Dictionary) -> String:
	var a: Variant = left.get(LibraryPartial.PARTIAL_KEY)
	var b: Variant = right.get(LibraryPartial.PARTIAL_KEY)
	if not a is Dictionary or not b is Dictionary:
		return "one of the two is not a partial copy"
	if left.get("id") != right.get("id"):
		return "another library"
	if left.get("version") != right.get("version"):
		return "another version (%s, then %s)" % [left.get("version"), right.get("version")]
	for field in ["source_hash", "source_version", "assets_only"]:
		if (a as Dictionary).get(field) != (b as Dictionary).get(field):
			return "the host's copy changed (%s)" % field
	return ""


static func _merge_catalog(current: Dictionary, delta: Dictionary) -> Dictionary:
	var left := _json(current.get(LibraryPartial.CATALOG_FILE, PackedByteArray()))
	var right := _json(delta.get(LibraryPartial.CATALOG_FILE, PackedByteArray()))
	var entries: Array = []
	var by_id := {}
	for source: Dictionary in [left, right]:
		for raw: Variant in source.get("assets", []):
			if not raw is Dictionary or not (raw as Dictionary).get("id") is String:
				continue
			var entry: Dictionary = raw
			var id := String(entry["id"])
			if by_id.has(id):
				if (by_id[id] as Dictionary).get("sha256") != entry.get("sha256"):
					return {"error": "asset %s differs between the kept copy and the delta" % id}
				continue
			by_id[id] = entry
			entries.append(entry.duplicate(true))
	var out := left.duplicate(true)
	out["assets"] = entries
	return out


static func _merge_library(left: Dictionary, right: Dictionary, files: Dictionary) -> Dictionary:
	var out := left.duplicate(true)
	var info: Dictionary = out[LibraryPartial.PARTIAL_KEY]
	var other: Dictionary = right[LibraryPartial.PARTIAL_KEY]
	for field in ["assets", "biomes", "surfaces", "structures"]:
		var united := {}
		for source: Dictionary in [info, other]:
			for item: Variant in source.get(field, []) as Array:
				united[String(item)] = true
		var names: Array[String] = []
		names.assign(united.keys())
		names.sort()
		info[field] = names
	var payload := 0
	for path: String in files:
		if _is_special(path) or path.begins_with("biomes/"):
			continue
		payload += (files[path] as PackedByteArray).size()
	info["bytes"] = payload
	return out


static func _is_special(path: String) -> bool:
	return (
		path == LibraryPartial.LIBRARY_FILE
		or path == LibraryPartial.CATALOG_FILE
		or path == LibraryStructures.INDEX_FILE
		or (path.begins_with("biomes/") and path.ends_with(".json"))
	)


static func _json(bytes: Variant) -> Dictionary:
	if not bytes is PackedByteArray:
		return {}
	var json := JSON.new()
	if json.parse((bytes as PackedByteArray).get_string_from_utf8()) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


static func _fail(out: Dictionary, code: String, text: String) -> Dictionary:
	out["code"] = code
	out["error"] = text
	return out
