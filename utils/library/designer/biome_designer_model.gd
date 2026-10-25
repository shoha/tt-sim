class_name BiomeDesignerModel
extends RefCounted

## The editable draft of one biome-def (design doc 4, step S8a): the in-memory biome the
## designer's panels edit, with every operation a command that can be undone and redone, the
## validators' verdict on every edit, the compile to the palette form the scatter solver reads,
## dirty tracking and the save to the library folder. Pure model: no nodes, no scene tree; the
## files it reads come through LibraryRegistry.designer_context and the files it writes through
## LibraryWriter, so a test drives it with a context built from strings.
##
## Edits are DesignerPatch ops on the draft biome-def (`def`, the JSON of biomes/<id>.json), so
## the undo stack holds the bytes an edit changed. An edit made with `merge` set (a slider being
## dragged) folds into the previous one when it is the same field within COALESCE_MSEC, so a
## drag is one undo step. The draft is NEVER the served palette: compile() makes the palette
## form of the draft (one palette biome per season, BiomeCompiler) and the designer session lays
## it over the palette (LibraryRegistry.serve_draft) and regenerates the scatter. Response
## curves and the biome-wide edits are static commands over the model (DesignerResponseEdits,
## DesignerBiomeEdits).
##
## Writable. A user library and the developer-override folder can be saved; an official library
## (from res://) cannot, and the editor offers "Duplicate as new collection" instead
## (LibraryWriter.create_collection, then open the copy). `locks` is the designer's Lock: the
## resolved selection of a query frozen into biomes/<id>.lock.json at Save (LibraryQuery).
## Map and model: docs/systems/biome_designer.md.

signal changed(reason: String)
signal saved

const MAX_UNDO := 200
const COALESCE_MSEC := 800
const SEASON_DEFAULT: Array = [{"id": "summer", "seed": 1}]

var library_id: String = ""
var biome_id: String = ""
var library_name: String = ""
var library_version: String = ""
var source: String = ""
var folder: String = ""
var writable: bool = false
## Why the model could not be built; "" when it is usable.
var error: String = ""
## The draft biome-def (biomes/<id>.json as the designer edits it).
var def: Dictionary = {}
## Locked selections: {"<season id>/<rule key>": {query: hash, assets: [refs]}}.
var locks: Dictionary = {}
## Bumped by every edit, undo, redo and revert: a cheap key for caches and debounces.
var revision: int = 0
## The last compile() result: {ok, validation, compiled, msec, revision}.
var last_compile: Dictionary = {}
## The designer context the model was built over (LibraryRegistry.designer_context's form).
var context: Dictionary = {}

var _saved_hash: int = 0
var _saved_lock_hash: int = 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _query_context: Dictionary = {}
var _resolved: Dictionary = {}
var _revision_of_cache: int = -1


## The model of biome `biome` of library `library` as the registry serves it (a model with
## `error` set when the library is not served from a folder or has no such biome).
static func open(library: String, biome: String) -> BiomeDesignerModel:
	return from_context(LibraryRegistry.designer_context(library), biome)


## The model over a designer context.
static func from_context(designer_context: Dictionary, biome: String) -> BiomeDesignerModel:
	var model := BiomeDesignerModel.new()
	if not designer_context.get("ok", false):
		model.error = String(designer_context.get("error", "the library is not available"))
		return model
	var read: Dictionary = designer_context["read"]
	var found := {}
	for item: Dictionary in read["biomes"]:
		if (item["def"] as Dictionary)["id"] == biome:
			found = item["def"]
	if found.is_empty():
		model.error = "library '%s' has no biome '%s'" % [designer_context["id"], biome]
		return model
	model.context = designer_context
	model.library_id = String(designer_context["id"])
	model.library_name = String(designer_context["name"])
	model.library_version = String(designer_context["version"])
	model.source = String(designer_context["source"])
	model.folder = String(designer_context["folder"])
	model.writable = bool(designer_context["writable"])
	model.biome_id = biome
	model.def = found.duplicate(true)
	model.locks = model._saved_locks().duplicate(true)
	model._mark_saved()
	return model


# ---- reading the draft ----


func rule_keys() -> Array[String]:
	var out: Array[String] = []
	for rule_data: Dictionary in def.get("rules", []):
		out.append(String(rule_data["key"]))
	return out


func rule_index(key: String) -> int:
	var rules: Array = def.get("rules", [])
	for i in rules.size():
		if (rules[i] as Dictionary)["key"] == key:
			return i
	return -1


func has_rule(key: String) -> bool:
	return rule_index(key) >= 0


## Whether the model was built (no `error`).
func valid() -> bool:
	return error == ""


## A copy of rule `key`'s biome-def, {} when there is none.
func rule(key: String) -> Dictionary:
	var at := rule_index(key)
	return (def["rules"][at] as Dictionary).duplicate(true) if at >= 0 else {}


## Rule `key`'s value for `field`, `fallback` when it has none.
func value(key: String, field: String, fallback: Variant = null) -> Variant:
	var at := rule_index(key)
	if at < 0:
		return fallback
	var found: Variant = (def["rules"][at] as Dictionary).get(field)
	return fallback if found == null else found


## The rule's number for `field` as the compiler will use it: its own, else the class default
## (spacing, slope, spread, yaw; density times the factor).
func effective_number(key: String, field: String) -> float:
	var own: Variant = value(key, field)
	if own != null:
		return float(own)
	var role := String(value(key, "role", ""))
	var size_class := String(value(key, "size_class", LibraryContracts.size_class_of(role)))
	var defaults := LibraryContracts.class_defaults(size_class)
	match field:
		"density_per_m2":
			var base := float(defaults.get("density_per_m2", 0.0))
			return base * float(value(key, "density_factor", 1.0))
		"spacing_m", "slope_max_deg", "scale_spread", "yaw_random_deg":
			return float(defaults.get(field, 0.0))
		"weight", "density_factor":
			return 1.0
	return 0.0


func season_list() -> Array:
	return (def.get("seasons", SEASON_DEFAULT) as Array).duplicate(true)


func season_ids() -> Array[String]:
	var out: Array[String] = []
	for season: Dictionary in season_list():
		out.append(String(season["id"]))
	return out


## The palette biome ids of the draft, one per season, in season order.
func runtime_ids() -> Array[String]:
	var out: Array[String] = []
	for season: Dictionary in season_list():
		var season_id := String(season["id"])
		var seed_value := int(season.get("seed", 1))
		out.append(LibraryIds.runtime_biome(library_id, biome_id, season_id, seed_value))
	return out


## Rule keys grouped by role, in draft order: {role: [keys]}.
func rules_by_role() -> Dictionary:
	var out := {}
	for rule_data: Dictionary in def.get("rules", []):
		var held: Array = out.get(String(rule_data["role"]), [])
		held.append(String(rule_data["key"]))
		out[String(rule_data["role"])] = held
	return out


func is_dirty() -> bool:
	return def.hash() != _saved_hash or locks.hash() != _saved_lock_hash


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## The label of the edit undo (`redo` false) or redo would take back or reapply, "" when none.
func history_label(redo: bool = false) -> String:
	var stack := _redo if redo else _undo
	return String(stack[stack.size() - 1]["label"]) if not stack.is_empty() else ""


# ---- rules ----


## A new rule of `role`, after the last rule of that role (or at the end). `query` empty: every
## catalog asset used as that role, three groups. Returns its key ("" when the draft is full).
func add_rule(role: String, query: Dictionary = {}, wanted_key: String = "") -> String:
	var full: bool = def.get("rules", []).size() >= int(LibraryContracts.CAPS["rules_per_biome"])
	if full or not LibraryContracts.has_role(role):
		return ""
	var key := unique_key(wanted_key if wanted_key != "" else role)
	var rules: Array = def["rules"]
	var at := rules.size()
	for i in rules.size():
		if (rules[i] as Dictionary)["role"] == role:
			at = i + 1
	apply_edit(
		"Add rule %s" % key, [DesignerPatch.insert_op(["rules"], at, _new_rule(role, key, query))]
	)
	return key


## `base` made unique among the rule keys (`oak`, `oak_2`, `oak_3`...).
func unique_key(base: String) -> String:
	var stem := base.to_lower().strip_edges().replace(" ", "_")
	if stem == "":
		stem = "rule"
	if not has_rule(stem):
		return stem
	var n := 2
	while has_rule("%s_%d" % [stem, n]):
		n += 1
	return "%s_%d" % [stem, n]


## Removes rule `key` and every near/avoid entry that named it.
func remove_rule(key: String) -> bool:
	var at := rule_index(key)
	if at < 0:
		return false
	var ops: Array = [DesignerPatch.remove_op(["rules"], at)]
	ops.append_array(_relation_cleanup(key, at))
	return apply_edit("Remove rule %s" % key, ops)


## A copy of rule `key` right after it, under a new key; returns the key.
func duplicate_rule(key: String) -> String:
	var at := rule_index(key)
	var full: bool = def.get("rules", []).size() >= int(LibraryContracts.CAPS["rules_per_biome"])
	if at < 0 or full:
		return ""
	var copy := rule(key)
	copy["key"] = unique_key(key)
	apply_edit("Duplicate rule %s" % key, [DesignerPatch.insert_op(["rules"], at + 1, copy)])
	return String(copy["key"])


## Moves rule `key` to position `index` (the order is the palette order within a class).
func move_rule(key: String, index: int) -> bool:
	var at := rule_index(key)
	var last: int = def.get("rules", []).size() - 1
	if at < 0 or index == at:
		return false
	var op := DesignerPatch.move_op(["rules"], at, clampi(index, 0, last))
	return apply_edit("Move rule %s" % key, [op])


## Renames rule `key` (kept unique); near/avoid entries that named it follow. Returns the key.
func rename_rule(key: String, wanted: String) -> String:
	var at := rule_index(key)
	var fresh := unique_key(wanted)
	if at < 0 or fresh == key:
		return key
	var ops: Array = [DesignerPatch.set_op(["rules", at, "key"], fresh)]
	for i in def["rules"].size():
		for field in ["near", "avoid"]:
			var items: Array = (def["rules"][i] as Dictionary).get(field, [])
			for j in items.size():
				if (items[j] as Dictionary).get("rule") == key:
					ops.append(DesignerPatch.set_op(["rules", i, field, j, "rule"], fresh))
	apply_edit("Rename rule %s" % key, ops)
	return fresh


## Sets a field of rule `key` (a number, `habit`, `clump`, `near`...); null erases it.
## `merge`: a slider drag, folded into the previous edit of the same field.
func set_field(key: String, field: String, new_value: Variant, merge: bool = false) -> bool:
	var at := rule_index(key)
	if at < 0:
		return false
	var path: Array = ["rules", at, field]
	var current: Variant = DesignerPatch.get_at(def, path)
	var tag := "field:%s:%s" % [key, field] if merge else ""
	if new_value == null:
		if current == null:
			return false
		return apply_edit("Clear %s" % field, [DesignerPatch.erase_op(path)], tag)
	if current != null and _same(current, new_value):
		return false
	return apply_edit("Set %s" % field, [DesignerPatch.set_op(path, new_value)], tag)


## Changes the role of rule `key`; a size class that was the old role's default follows.
func set_role(key: String, role: String) -> bool:
	var at := rule_index(key)
	if at < 0 or not LibraryContracts.has_role(role) or value(key, "role") == role:
		return false
	var old_role := String(value(key, "role"))
	var ops: Array = [DesignerPatch.set_op(["rules", at, "role"], role)]
	var current_class: Variant = value(key, "size_class")
	if current_class != null and current_class == LibraryContracts.size_class_of(old_role):
		ops.append(DesignerPatch.erase_op(["rules", at, "size_class"]))
	return apply_edit("Set role %s" % role, ops)


## Sets rule `key`'s size class; the role's own default erases the field.
func set_size_class(key: String, size_class: String) -> bool:
	var role := String(value(key, "role", ""))
	var stored: Variant = null if size_class == LibraryContracts.size_class_of(role) else size_class
	return set_field(key, "size_class", stored)


# ---- queries ----


## Replaces rule `key`'s query.
func set_query(key: String, query: Dictionary) -> bool:
	var at := rule_index(key)
	if at < 0 or DesignerPatch.get_at(def, ["rules", at, "query"]) == query:
		return false
	return apply_edit("Edit query", [DesignerPatch.set_op(["rules", at, "query"], query)])


## Sets one query field (`tags_any`, `count`, `order`, `seasons`, `size_class`...); null or an
## empty list erases it.
func set_query_field(key: String, field: String, new_value: Variant) -> bool:
	var at := rule_index(key)
	if at < 0:
		return false
	var path: Array = ["rules", at, "query", field]
	var current: Variant = DesignerPatch.get_at(def, path)
	var empty: bool = new_value == null or (new_value is Array and (new_value as Array).is_empty())
	if empty:
		if current == null:
			return false
		return apply_edit("Edit query", [DesignerPatch.erase_op(path)])
	if current != null and _same(current, new_value):
		return false
	return apply_edit("Edit query", [DesignerPatch.set_op(path, new_value)])


## Appends a clause (`{ref}` or a filter) to rule `key`'s query.match unless it is there;
## returns its index (-1 when the list is full or there is no such rule).
func add_clause(key: String, clause: Dictionary) -> int:
	var at := rule_index(key)
	if at < 0:
		return -1
	var path: Array = ["rules", at, "query", "match"]
	var matches: Array = DesignerPatch.get_at(def, path, [])
	if matches.has(clause):
		return matches.find(clause)
	if matches.size() >= LibraryContracts.QUERY_MAX_ASSETS:
		return -1
	var index := matches.size()
	apply_edit("Add to query", [DesignerPatch.insert_op(path, index, clause)])
	return index


## Adds `{ref: ref}` to rule `key`'s query unless it is there; true when it is in the query now.
func add_ref(key: String, ref: String) -> bool:
	return add_clause(key, {"ref": ref}) >= 0


func remove_clause(key: String, index: int) -> bool:
	var at := rule_index(key)
	var path: Array = ["rules", at, "query", "match"]
	var matches: Array = DesignerPatch.get_at(def, path, [])
	if at < 0 or matches.size() <= 1 or index < 0 or index >= matches.size():
		return false
	return apply_edit("Remove from query", [DesignerPatch.remove_op(path, index)])


## Pins (or unpins) catalog asset `ref` in rule `key`'s query.
func set_pin(key: String, ref: String, on: bool) -> bool:
	var at := rule_index(key)
	if at < 0:
		return false
	var pins: Array = DesignerPatch.get_at(def, ["rules", at, "query", "pin"], []).duplicate()
	if on == (ref in pins):
		return false
	if on:
		pins.append(ref)
	else:
		pins.erase(ref)
	return set_query_field(key, "pin", pins)


# ---- what the query selects ----


## The query context LibraryQuery reads (catalog and dependencies' catalogs), cached.
func query_context() -> Dictionary:
	if _query_context.is_empty():
		_query_context = {
			"library": library_id,
			"catalog": (context["read"] as Dictionary)["catalog"],
			"folder": folder,
			"deps": context["dependencies"],
		}
	return _query_context


## Every asset the draft's library and its dependencies offer, sorted by local id.
func catalog() -> Array[Dictionary]:
	return LibraryQuery.candidates(query_context())


## The assets rule `key` selects in `season` (the first season when ""), in the compiler's
## order: refs and group refs, then the filters' and pins' selection. Candidate dictionaries
## ({library, id, local, ref, entry, folder, group}); cached until the next edit.
func resolved_assets(key: String, season: String = "") -> Array[Dictionary]:
	if _revision_of_cache != revision:
		_resolved.clear()
		_revision_of_cache = revision
	var which := season if season != "" else season_ids()[0]
	var cache_key := "%s|%s" % [key, which]
	if _resolved.has(cache_key):
		var cached: Array[Dictionary] = []
		cached.assign(_resolved[cache_key])
		return cached
	var out: Array[Dictionary] = []
	var query: Dictionary = rule(key).get("query", {})
	var seen := {}
	var ctx := query_context()
	var all := LibraryQuery.candidates(ctx)
	for clause: Variant in query.get("match", []):
		if not clause is Dictionary or not (clause as Dictionary).get("ref") is String:
			continue
		var ref := String(clause["ref"])
		var members := LibraryQuery.group_members(ref, ctx)
		if members.is_empty():
			for candidate in all:
				if candidate["ref"] == ref:
					members = [candidate]
		for member in members:
			if not seen.has(member["local"]):
				seen[member["local"]] = true
				out.append(member)
	var warnings: Array[String] = []
	var picked := LibraryQuery.select(query, ctx, _scope(key, which), warnings)
	for member: Dictionary in picked["found"]:
		if not seen.has(member["local"]):
			seen[member["local"]] = true
			out.append(member)
	_resolved[cache_key] = out
	return out


## The rule keys that use catalog asset `ref` in `season`.
func rules_using(ref: String, season: String = "") -> Array[String]:
	var out: Array[String] = []
	for key in rule_keys():
		for member in resolved_assets(key, season):
			if member["ref"] == ref:
				out.append(key)
				break
	return out


func is_locked(key: String) -> bool:
	for season in season_ids():
		if locks.has("%s/%s" % [season, key]):
			return true
	return false


## Freezes (or releases) rule `key`'s selection in every season: Save writes the lock file.
func set_locked(key: String, on: bool) -> bool:
	if not has_rule(key) or on == is_locked(key):
		return false
	for season in season_ids():
		var lock_key := "%s/%s" % [season, key]
		if on:
			locks[lock_key] = _fresh_lock(key, season)
		else:
			locks.erase(lock_key)
	revision += 1
	changed.emit("Lock" if on else "Unlock")
	return true


# ---- validation and compile ----


## The validators' verdict on the draft (DesignerValidation's report), including the last
## compile's warnings when it was of this revision.
func validation() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	LibraryReader.check_biome(def.duplicate(true), biome_id + ".json", errors, warnings)
	var lines: Array[String] = []
	if last_compile.has("compiled") and last_compile.get("revision", -1) == revision:
		lines = _compile_lines(last_compile["compiled"])
	return DesignerValidation.report(errors, warnings, lines)


## Compiles the draft: the validators first (a draft with errors is not compiled), then
## BiomeCompiler over the library's catalog, surfaces and dependencies. Returns {ok, validation,
## compiled (BiomeCompiler's result), msec, revision} and keeps it as last_compile.
func compile() -> Dictionary:
	var started := Time.get_ticks_usec()
	var verdict := validation()
	var result := {
		"ok": false, "validation": verdict, "compiled": {}, "msec": 0.0, "revision": revision
	}
	if (verdict["errors"] as Array).is_empty():
		var read: Dictionary = (context["read"] as Dictionary).duplicate()
		read["biomes"] = [{"file": biome_id + ".json", "def": def.duplicate(true)}]
		read["locks"] = {biome_id: {"rules": locks.duplicate(true)}}
		var options := {
			"folder": folder,
			"surfaces": context["surfaces"],
			"hash": String(context["hash"]),
			"files": context["files"],
			"dependencies": context["dependencies"],
		}
		var compiled := BiomeCompiler.compile(read, options)
		var warnings: Array[String] = []
		warnings.assign(verdict["warnings"])
		result["compiled"] = compiled
		result["ok"] = not (compiled["biome_ids"] as Array).is_empty()
		result["validation"] = DesignerValidation.report([], warnings, _compile_lines(compiled))
	result["msec"] = (Time.get_ticks_usec() - started) / 1000.0
	last_compile = result
	return result


# ---- history, save ----


## Applies `ops` (DesignerPatch) as one undoable edit named `label`. `merge_tag` folds a run of
## edits with the same tag within COALESCE_MSEC into one undo step. Returns false when nothing
## changed. The one door every edit goes through.
func apply_edit(label: String, ops: Array, merge_tag: String = "") -> bool:
	var inverse := DesignerPatch.apply(def, ops)
	var applied := false
	for op: Dictionary in inverse:
		applied = applied or op["op"] != "noop"
	if not applied:
		return false
	var now := Time.get_ticks_msec()
	var last: Dictionary = _undo[_undo.size() - 1] if not _undo.is_empty() else {}
	var folds: bool = merge_tag != "" and not last.is_empty() and last["tag"] == merge_tag
	if folds and now - int(last["msec"]) < COALESCE_MSEC:
		last["redo"] = ops
		last["msec"] = now
	else:
		_undo.append({"label": label, "undo": inverse, "redo": ops, "tag": merge_tag, "msec": now})
		if _undo.size() > MAX_UNDO:
			_undo.pop_front()
	_redo.clear()
	revision += 1
	changed.emit(label)
	return true


func undo() -> bool:
	if _undo.is_empty():
		return false
	var entry: Dictionary = _undo.pop_back()
	entry["redo"] = DesignerPatch.apply(def, entry["undo"])
	_redo.append(entry)
	revision += 1
	changed.emit("Undo " + String(entry["label"]))
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var entry: Dictionary = _redo.pop_back()
	entry["undo"] = DesignerPatch.apply(def, entry["redo"])
	_undo.append(entry)
	revision += 1
	changed.emit("Redo " + String(entry["label"]))
	return true


## Throws away every unsaved edit.
func revert() -> void:
	for item: Dictionary in (context.get("read", {}) as Dictionary).get("biomes", []):
		if (item["def"] as Dictionary)["id"] == biome_id:
			def = (item["def"] as Dictionary).duplicate(true)
	locks = _saved_locks().duplicate(true)
	_undo.clear()
	_redo.clear()
	_mark_saved()
	revision += 1
	changed.emit("Revert")


## Writes the draft (and its locks) to the library folder; {ok, error}. Refused for an official
## library and for a draft the validators reject.
func save() -> Dictionary:
	if not writable:
		var why := "%s is read-only; duplicate it as a new collection" % library_name
		return {"ok": false, "error": why}
	var verdict := validation()
	if not (verdict["errors"] as Array).is_empty():
		return {"ok": false, "error": String((verdict["errors"] as Array)[0])}
	var written := LibraryWriter.write_biome(folder, biome_id, def, _lock_entries())
	if written["ok"]:
		_mark_saved()
		saved.emit()
	return written


# ---- internals ----


## A rule dictionary with the class defaults for `role`, explicit as the exporter writes them.
func _new_rule(role: String, key: String, query: Dictionary) -> Dictionary:
	var size_class := LibraryContracts.size_class_of(role)
	if size_class == "":
		size_class = "medium"
	var defaults := LibraryContracts.class_defaults(size_class)
	var wanted := query
	if wanted.is_empty():
		wanted = {"match": [{"role": role}], "count": 3, "order": "hash"}
	return {
		"key": key,
		"role": role,
		"weight": 1,
		"density_per_m2": defaults["density_per_m2"],
		"spacing_m": defaults["spacing_m"],
		"slope_max_deg": defaults["slope_max_deg"],
		"scale_spread": defaults["scale_spread"],
		"yaw_random_deg": defaults["yaw_random_deg"],
		"near": [],
		"avoid": [],
		"query": wanted.duplicate(true),
	}


## The lock for rule `key` in `season`: the query's hash and the refs its selection gives now.
func _fresh_lock(key: String, season: String) -> Dictionary:
	var query: Dictionary = rule(key).get("query", {})
	var warnings: Array[String] = []
	var picked := LibraryQuery.select(query, query_context(), _scope(key, season), warnings)
	var refs: Array[String] = []
	for found: Dictionary in picked["found"]:
		refs.append(String(found["ref"]))
	return {"query": LibraryQuery.query_hash(query), "assets": refs}


## The lock file's rules: the locked rules that still exist, a lock whose query changed taken
## again from the query as it is now.
func _lock_entries() -> Dictionary:
	var out := {}
	for lock_key: String in locks:
		var rule_key := lock_key.get_slice("/", 1)
		if not has_rule(rule_key):
			continue
		var query: Dictionary = rule(rule_key).get("query", {})
		out[lock_key] = locks[lock_key]
		if String(locks[lock_key]["query"]) != LibraryQuery.query_hash(query):
			out[lock_key] = _fresh_lock(rule_key, lock_key.get_slice("/", 0))
	return out


func _saved_locks() -> Dictionary:
	var read: Dictionary = context.get("read", {})
	var held: Dictionary = (read.get("locks", {}) as Dictionary).get(biome_id, {})
	return held.get("rules", {})


func _mark_saved() -> void:
	_saved_hash = def.hash()
	_saved_lock_hash = locks.hash()


func _scope(key: String, season: String) -> Dictionary:
	return {"biome": biome_id, "rule": key, "season": season, "label": "rule " + key}


## Whether two values are the same for an edit: numbers by value, the rest by ==.
func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


## Ops that drop the near/avoid entries naming rule `key` from the other rules (`removed_at`
## is where `key` stood, so indices after it shift down by one).
func _relation_cleanup(key: String, removed_at: int) -> Array:
	var ops: Array = []
	var rules: Array = def["rules"]
	for i in rules.size():
		if i == removed_at:
			continue
		var shifted := i - 1 if i > removed_at else i
		for field in ["near", "avoid"]:
			var items: Array = (rules[i] as Dictionary).get(field, [])
			var kept: Array = []
			for item: Variant in items:
				if not (item is Dictionary and (item as Dictionary).get("rule") == key):
					kept.append(item)
			if kept.size() != items.size():
				ops.append(DesignerPatch.set_op(["rules", shifted, field], kept))
	return ops


func _compile_lines(compiled: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.assign(compiled.get("warnings", []))
	for line: String in compiled.get("palette_warnings", []):
		out.append("palette: " + line)
	return out
