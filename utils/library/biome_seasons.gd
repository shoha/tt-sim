class_name BiomeSeasons
extends RefCounted

## Per-season overrides of a biome-def (design doc 2.6.5, step S9). A season is one palette
## biome (`<biome>_<season>_s<seed>`); this module turns the biome-def into the def of ONE season
## before the compiler reads it, so BiomeCompiler needs no season code of its own.
##
## Two places hold an override, applied in this order:
##
## - the season's `overrides` (in `seasons[i]`): `ground` (a field by field replacement of the
##   ground block, null erases a field), `ground_look` (deep merge over the base look, so a winter
##   can change two colours and keep the rest), `density_scale` (per size class, merged over the
##   biome's own) and `rules` ({rule key: override});
## - the rule's own `seasons`: `{"only": ["summer", "autumn"]}` (the rule is absent from every
##   other season) and `{"winter": override}`.
##
## A rule override may set any of LibraryContracts.SEASON_RULE_FIELDS: numbers and `response`,
## `habit`, `align`, `keep_colour` replace the rule's (null erases), `query` is merged key by key
## over the rule's query (its `match` list replaces the whole list), `enabled` false removes the
## rule from the season. `density_factor` is RELATIVE: it multiplies the density the rule compiles
## to (a rule with an explicit `density_per_m2` has that scaled; one without has its own factor
## scaled), and 0 removes the rule from the season. The biome's `density_scale` (base merged with
## the season's) multiplies every rule of the class the same way (a class budget multiplier).
##
## effective() returns the very `def` it was given when nothing applies to the season, so a biome
## without seasons' overrides, rule seasons or density scale compiles byte for byte as before.
## Pure: no files, no scene tree.


## The biome-def as season `season_id` sees it (`def` itself when nothing applies).
static func effective(def: Dictionary, season_id: String) -> Dictionary:
	var overrides := season_overrides(def, season_id)
	var scale := _density_scale(def, overrides)
	if overrides.is_empty() and scale.is_empty() and not _rules_have_seasons(def):
		return def
	var out := def.duplicate(true)
	if overrides.get("ground") is Dictionary:
		var ground: Dictionary = out.get("ground", {}) if out.get("ground") is Dictionary else {}
		out["ground"] = _replace_keys(ground, overrides["ground"])
	if overrides.get("ground_look") is Dictionary:
		var base: Variant = out.get("ground_look")
		out["ground_look"] = deep_merge(
			base if base is Dictionary else {}, overrides["ground_look"] as Dictionary
		)
	var by_key: Dictionary = (
		overrides["rules"] if overrides.get("rules") is Dictionary else {}
	)
	var rules: Array = []
	for raw: Variant in out.get("rules", []):
		var rule: Dictionary = raw
		var kept := _season_rule(rule, season_id, by_key.get(String(rule["key"])), scale)
		if not kept.is_empty():
			rules.append(kept)
	out["rules"] = rules
	return out


## A copy of rule `key` of `def` as season `season_id` sees it, {} when the biome has no such rule
## or the rule is not in that season.
static func rule_in(def: Dictionary, key: String, season_id: String) -> Dictionary:
	for item: Dictionary in effective(def, season_id).get("rules", []):
		if item["key"] == key:
			return item.duplicate(true)
	return {}


## The `overrides` object of season `season_id` ({} when it has none).
static func season_overrides(def: Dictionary, season_id: String) -> Dictionary:
	for season: Variant in def.get("seasons", []):
		if season is Dictionary and (season as Dictionary).get("id") == season_id:
			var held: Variant = (season as Dictionary).get("overrides")
			return held if held is Dictionary else {}
	return {}


## Whether season `season_id` changes anything of the biome.
static func has_overrides(def: Dictionary, season_id: String) -> bool:
	return (
		not season_overrides(def, season_id).is_empty()
		or _rule_seasons_touch(def, season_id)
	)


## Whether rule `rule` grows in `season_id` (its `seasons.only` lists it, or has no `only`).
static func present_in(rule: Dictionary, season_id: String) -> bool:
	var held: Variant = rule.get("seasons")
	if not held is Dictionary or not (held as Dictionary).get("only") is Array:
		return true
	return season_id in (held as Dictionary)["only"]


## Rule `key`'s override for `season_id` kept in the rule's own `seasons` ({} when none).
static func rule_override(rule: Dictionary, season_id: String) -> Dictionary:
	var held: Variant = rule.get("seasons")
	if held is Dictionary and (held as Dictionary).get(season_id) is Dictionary:
		return (held as Dictionary)[season_id]
	return {}


## `base` with `over` laid over it key by key; objects merge, anything else (a list, a number)
## replaces. Neither argument changes.
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: Variant in over:
		var value: Variant = over[key]
		if value is Dictionary and out.get(key) is Dictionary:
			out[key] = deep_merge(out[key], value)
		else:
			out[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return out


## The validators' lines for the seasons of `def` (called by LibraryReader.check_biome once the
## rule keys are known): unknown keys warn, a malformed value is an error with the rule's words,
## an override naming a rule or season the biome lacks warns.
static func check(
	def: Dictionary,
	where: String,
	rule_keys: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var ids := {}
	for season: Variant in def.get("seasons", [{"id": "summer"}]):
		if season is Dictionary and (season as Dictionary).get("id") is String:
			ids[(season as Dictionary)["id"]] = true
	for season: Variant in def.get("seasons", []):
		if not season is Dictionary or not (season as Dictionary).get("overrides") is Dictionary:
			continue
		var id := String((season as Dictionary).get("id", ""))
		_check_overrides(
			(season as Dictionary)["overrides"], "%s season '%s'" % [where, id], rule_keys, errors,
			warnings
		)
	for raw: Variant in def.get("rules", []):
		if raw is Dictionary and (raw as Dictionary).has("seasons"):
			_check_rule_seasons(raw, where, ids, errors, warnings)


## The size class of a rule-def: its own, else its role's.
static func size_class_of(rule: Dictionary) -> String:
	var own: Variant = rule.get("size_class")
	if own is String and own != "":
		return own
	return LibraryContracts.size_class_of(String(rule.get("role", "")))


# ---- applying ----


static func _density_scale(def: Dictionary, overrides: Dictionary) -> Dictionary:
	var scale := {}
	for source: Variant in [def.get("density_scale"), overrides.get("density_scale")]:
		if source is Dictionary:
			for size_class: Variant in source as Dictionary:
				var value: Variant = (source as Dictionary)[size_class]
				if (value is float or value is int) and float(value) != 1.0:
					scale[String(size_class)] = float(value)
				elif value is float or value is int:
					scale.erase(String(size_class))
	return scale


static func _rules_have_seasons(def: Dictionary) -> bool:
	for rule: Variant in def.get("rules", []):
		if rule is Dictionary and (rule as Dictionary).has("seasons"):
			return true
	return false


static func _rule_seasons_touch(def: Dictionary, season_id: String) -> bool:
	for rule: Variant in def.get("rules", []):
		if not rule is Dictionary:
			continue
		if not present_in(rule, season_id) or not rule_override(rule, season_id).is_empty():
			return true
	return false


## `base` with each key of `over` set; a null value erases the key.
static func _replace_keys(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: Variant in over:
		if over[key] == null:
			out.erase(key)
		else:
			var value: Variant = over[key]
			out[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return out


## The rule as the season sees it, or {} when it is absent from the season.
static func _season_rule(
	rule: Dictionary, season_id: String, by_key: Variant, scale: Dictionary
) -> Dictionary:
	if not present_in(rule, season_id):
		return {}
	var out := rule.duplicate(true)
	out.erase("seasons")
	var multiplier := 1.0
	for over: Variant in [by_key, rule_override(rule, season_id)]:
		if not over is Dictionary:
			continue
		if (over as Dictionary).get("enabled") == false:
			return {}
		multiplier *= _apply_override(out, over as Dictionary)
	multiplier *= float(scale.get(size_class_of(out), 1.0))
	if multiplier <= 0.0:
		return {}
	if multiplier != 1.0:
		if out.get("density_per_m2") != null:
			out["density_per_m2"] = float(out["density_per_m2"]) * multiplier
		else:
			out["density_factor"] = float(out.get("density_factor", 1.0)) * multiplier
	return out


## Lays one override over `rule`; returns the relative density factor it asks for.
static func _apply_override(rule: Dictionary, over: Dictionary) -> float:
	var factor := 1.0
	for field: Variant in over:
		var name := String(field)
		var value: Variant = over[field]
		if name == "enabled" or not LibraryContracts.SEASON_RULE_FIELDS.has(name):
			continue
		if name == "density_factor":
			if value is float or value is int:
				factor *= float(value)
		elif name == "query":
			if value is Dictionary:
				rule["query"] = _merge_query(rule.get("query", {}), value)
		elif value == null:
			rule.erase(name)
		else:
			rule[name] = value.duplicate(true) if value is Dictionary or value is Array else value
	return factor


## `base` with the keys of `over` set; a null erases a key, `match` replaces the whole list.
static func _merge_query(base: Variant, over: Dictionary) -> Dictionary:
	var out: Dictionary = (base as Dictionary).duplicate(true) if base is Dictionary else {}
	for key: Variant in over:
		if over[key] == null:
			out.erase(key)
		else:
			var value: Variant = over[key]
			out[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return out


# ---- checking ----


static func _check_overrides(
	over: Dictionary,
	label: String,
	rule_keys: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	for key: Variant in over:
		if not String(key) in LibraryContracts.SEASON_OVERRIDE_KEYS:
			warnings.append("%s: override '%s' is unknown (ignored)" % [label, _short(String(key))])
	var ground: Variant = over.get("ground")
	if over.has("ground") and not ground is Dictionary:
		errors.append("%s: overrides.ground must be an object" % label)
	elif ground is Dictionary:
		for key: Variant in ground as Dictionary:
			if not String(key) in LibraryContracts.GROUND_KEYS:
				warnings.append(
					"%s: ground override '%s' is unknown (ignored)" % [label, _short(String(key))]
				)
	if over.has("ground_look") and not over["ground_look"] is Dictionary:
		errors.append("%s: overrides.ground_look must be an object" % label)
	var scale: Variant = over.get("density_scale")
	if over.has("density_scale") and not scale is Dictionary:
		errors.append("%s: overrides.density_scale must be an object" % label)
	elif scale is Dictionary:
		for size_class: Variant in scale as Dictionary:
			var value: Variant = (scale as Dictionary)[size_class]
			if not LibraryContracts.SIZE_CLASSES.has(String(size_class)):
				warnings.append(
					"%s: density_scale class '%s' is unknown (ignored)" % [label, _short(String(size_class))]
				)
			if not (value is float or value is int) or float(value) < 0.0 or float(value) > 100.0:
				errors.append("%s: density_scale.%s must be a number from 0 to 100" % [label, size_class])
	var rules: Variant = over.get("rules")
	if over.has("rules") and not rules is Dictionary:
		errors.append("%s: overrides.rules must be an object of rule key -> override" % label)
	elif rules is Dictionary:
		for key: Variant in rules as Dictionary:
			if not rule_keys.has(String(key)):
				warnings.append(
					"%s: overrides.rules names '%s', which is not a rule (ignored)" % [label, _short(String(key))]
				)
			if (rules as Dictionary)[key] is Dictionary:
				_check_rule_override(
					(rules as Dictionary)[key], "%s rule '%s'" % [label, _short(String(key))],
					errors, warnings
				)
			else:
				errors.append("%s: the override of rule '%s' must be an object" % [label, _short(String(key))])


static func _check_rule_seasons(
	rule: Dictionary,
	where: String,
	ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var label := "%s rule '%s' seasons" % [where, _short(String(rule.get("key", "")))]
	var held: Variant = rule["seasons"]
	if not held is Dictionary:
		errors.append("%s: must be an object" % label)
		return
	for key: Variant in held as Dictionary:
		var value: Variant = (held as Dictionary)[key]
		if String(key) == "only":
			if not value is Array:
				errors.append("%s: only must be a list of season ids" % label)
				continue
			for item: Variant in value as Array:
				if not item is String or not ids.has(item):
					warnings.append("%s: only names '%s', which is not a season" % [label, str(item)])
			continue
		if not ids.has(String(key)):
			warnings.append(
				"%s: '%s' is not a season of this biome (ignored)" % [label, _short(String(key))]
			)
		if value is Dictionary:
			_check_rule_override(value, "%s.%s" % [label, _short(String(key))], errors, warnings)
		else:
			errors.append("%s: the override of season '%s' must be an object" % [label, _short(String(key))])


static func _check_rule_override(
	over: Dictionary, label: String, errors: Array[String], warnings: Array[String]
) -> void:
	for key: Variant in over:
		if not String(key) in LibraryContracts.SEASON_RULE_FIELDS:
			warnings.append(
				"%s: field '%s' cannot change by season (ignored)" % [label, _short(String(key))]
			)
	if over.has("enabled") and not over["enabled"] is bool:
		errors.append("%s: enabled must be true or false" % label)
	# density_factor is relative, so it may be 0 (the rule leaves the season).
	LibraryReader.check_rule_values(over, label, errors, warnings)
	if over.get("query") is Dictionary:
		LibraryReader.check_query_override(over["query"], label, errors, warnings)
	elif over.has("query"):
		errors.append("%s: query must be an object" % label)


static func _short(text: String) -> String:
	return text if text.length() <= 48 else text.substr(0, 45) + "..."
