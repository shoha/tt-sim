class_name DesignerSeasonEdits
extends RefCounted

## The season edits of the biome designer (step S9, design doc 2.6.5 and 4.4): which seasons the
## biome has, and what each one changes (BiomeSeasons says how the compiler reads them). Commands
## on a BiomeDesignerModel, static over it like DesignerBiomeEdits, each one undoable step:
##
## - the list: `add_season`, `remove_season`, `set_seed`;
## - what a season changes of the biome: `set_ground`, `set_ground_look` and `set_density_scale`
##   (kept in the season's `overrides`), where a null value takes the override away again;
## - what a season changes of one rule: `set_rule_field` (kept in the rule's own `seasons`, so a
##   rule carries its seasons with it when it is duplicated or moved) and `set_present` (the
##   rule's `seasons.only` list);
## - `clear` takes every override of one season away, `summary` counts them for the panels.
##
## The panels edit the draft only through these; reading the season as the compiler sees it is
## BiomeSeasons.effective (`effective`).

const DEFAULT_NAMES: Array[String] = ["summer", "autumn", "winter", "spring", "wet", "dry"]


## The season ids the biome has not used yet, the usual four first.
static func unused_names(model: BiomeDesignerModel) -> Array[String]:
	var taken := model.season_ids()
	var out: Array[String] = []
	for name in DEFAULT_NAMES:
		if not name in taken:
			out.append(name)
	return out


## Adds season `id` (a new seed after the highest one when `seed_value` < 0). False when the id
## is not valid or taken, or the biome has the most seasons it may.
static func add_season(model: BiomeDesignerModel, id: String, seed_value: int = -1) -> bool:
	var seasons := model.season_list()
	if (
		seasons.size() >= LibraryContracts.MAX_SEASONS
		or not LibraryIds.season_problems(id).is_empty()
		or id in model.season_ids()
	):
		return false
	var top := 0
	for season: Dictionary in seasons:
		top = maxi(top, int(season.get("seed", 1)))
	seasons.append({"id": id, "seed": seed_value if seed_value >= 0 else top + 1})
	return model.apply_edit("Add season %s" % id, [DesignerPatch.set_op(["seasons"], seasons)])


## Removes season `id` and every override that named it. The last season cannot go.
static func remove_season(model: BiomeDesignerModel, id: String) -> bool:
	var at := model.season_ids().find(id)
	if at < 0 or model.season_ids().size() < 2:
		return false
	var ops: Array = [DesignerPatch.remove_op(["seasons"], at)]
	var rules: Array = model.def.get("rules", [])
	var remaining := model.season_ids()
	remaining.erase(id)
	for i in rules.size():
		var held: Variant = (rules[i] as Dictionary).get("seasons")
		if held is Dictionary:
			var cleaned := _without_season(held, id, remaining)
			ops.append(
				DesignerPatch.erase_op(["rules", i, "seasons"])
				if cleaned.is_empty()
				else DesignerPatch.set_op(["rules", i, "seasons"], cleaned)
			)
	return model.apply_edit("Remove season %s" % id, ops)


## Sets season `id`'s seed (it names the runtime biome, `<biome>_<season>_s<seed>`).
static func set_seed(model: BiomeDesignerModel, id: String, seed_value: int) -> bool:
	var at := model.season_ids().find(id)
	if at < 0 or seed_value < 0 or int(model.season_list()[at].get("seed", 1)) == seed_value:
		return false
	return model.apply_edit(
		"Set %s seed" % id, [DesignerPatch.set_op(["seasons", at, "seed"], seed_value)]
	)


## What season `id` sees of the biome-def, as the compiler reads it.
static func effective(model: BiomeDesignerModel, id: String) -> Dictionary:
	return BiomeSeasons.effective(model.def, id)


# ---- the biome in a season ----


## The override of ground field `field` in season `id`: Variant (null: none, so the base value
## shows through).
static func ground_override(model: BiomeDesignerModel, id: String, field: String) -> Variant:
	var held: Variant = _overrides(model, id).get("ground")
	return (held as Dictionary).get(field) if held is Dictionary else null


## Whether season `id` overrides ground field `field` (including erasing it).
static func has_ground_override(model: BiomeDesignerModel, id: String, field: String) -> bool:
	var held: Variant = _overrides(model, id).get("ground")
	return held is Dictionary and (held as Dictionary).has(field)


## Sets ground field `field` in season `id` to `value`; null takes the override away, and
## `erase_base` true makes the season have no such field at all (a winter with no accents).
static func set_ground(
	model: BiomeDesignerModel, id: String, field: String, value: Variant, erase_base: bool = false
) -> bool:
	if not field in LibraryContracts.GROUND_KEYS:
		return false
	var ground: Dictionary = (_overrides(model, id).get("ground", {}) as Dictionary).duplicate(true)
	if value == null and not erase_base:
		ground.erase(field)
	else:
		ground[field] = value
	return _set_override(model, id, "ground", ground, "Set %s ground %s" % [id, field])


## The ground look override of season `id` ({} when none).
static func look_override(model: BiomeDesignerModel, id: String) -> Dictionary:
	var held: Variant = _overrides(model, id).get("ground_look")
	return (held as Dictionary).duplicate(true) if held is Dictionary else {}


## Replaces season `id`'s ground look override (deep-merged over the base look at compile);
## null or {} takes it away.
static func set_ground_look(
	model: BiomeDesignerModel, id: String, look: Variant, merge_tag: String = ""
) -> bool:
	return _set_override(model, id, "ground_look", look, "Set %s ground look" % id, merge_tag)


## Sets the density scale of size class `size_class` in season `id` (multiplies the class's
## rules); null takes the override away.
static func set_density_scale(
	model: BiomeDesignerModel, id: String, size_class: String, scale: Variant
) -> bool:
	var scales: Dictionary = (
		(_overrides(model, id).get("density_scale", {}) as Dictionary).duplicate(true)
	)
	if scale == null:
		scales.erase(size_class)
	else:
		scales[size_class] = scale
	return _set_override(model, id, "density_scale", scales, "Set %s density scale" % id)


# ---- a rule in a season ----


## Rule `key`'s override for season `id` (its own `seasons[id]`, a copy; {} when none).
static func rule_override(model: BiomeDesignerModel, key: String, id: String) -> Dictionary:
	return BiomeSeasons.rule_override(model.rule(key), id).duplicate(true)


## Whether rule `key` grows in season `id`.
static func is_present(model: BiomeDesignerModel, key: String, id: String) -> bool:
	return BiomeSeasons.present_in(model.rule(key), id)


## Sets field `field` of rule `key`'s override for season `id` (see
## LibraryContracts.SEASON_RULE_FIELDS; `density_factor` there is relative). null takes the
## field away; an override left empty goes.
static func set_rule_field(
	model: BiomeDesignerModel,
	key: String,
	id: String,
	field: String,
	value: Variant,
	merge: bool = false
) -> bool:
	var at := model.rule_index(key)
	if at < 0 or not field in LibraryContracts.SEASON_RULE_FIELDS or field == "enabled":
		return false
	var over := rule_override(model, key, id)
	if value == null:
		over.erase(field)
	else:
		over[field] = value
	var tag := "season:%s:%s:%s" % [key, id, field] if merge else ""
	return _set_rule_season(model, at, id, over, "Set %s %s in %s" % [key, field, id], tag)


## Lets rule `key` grow in season `id` (`on`) or takes it out of that season. The rule's
## `seasons.only` list is made on the first season turned off and goes when every season is on.
static func set_present(model: BiomeDesignerModel, key: String, id: String, on: bool) -> bool:
	var at := model.rule_index(key)
	if at < 0 or not id in model.season_ids() or is_present(model, key, id) == on:
		return false
	var held: Dictionary = (model.rule(key).get("seasons", {}) as Dictionary).duplicate(true)
	var only: Array = held.get("only", model.season_ids())
	if on:
		only.append(id)
	else:
		only.erase(id)
	var ordered: Array = []
	for season in model.season_ids():
		if season in only:
			ordered.append(season)
	if ordered.size() == model.season_ids().size():
		held.erase("only")
	else:
		held["only"] = ordered
	var label := "%s %s in %s" % ["Show" if on else "Hide", key, id]
	return _apply_rule_seasons(model, at, held, label)


## Takes every override of season `id` away: its `overrides`, every rule's override for it, and
## the seasons it was left out of. False when it had none.
static func clear(model: BiomeDesignerModel, id: String) -> bool:
	var at := model.season_ids().find(id)
	if at < 0 or not BiomeSeasons.has_overrides(model.def, id):
		return false
	var ops: Array = []
	if model.season_list()[at].has("overrides"):
		ops.append(DesignerPatch.erase_op(["seasons", at, "overrides"]))
	var rules: Array = model.def.get("rules", [])
	for i in rules.size():
		var held: Variant = (rules[i] as Dictionary).get("seasons")
		if not held is Dictionary:
			continue
		var cleaned := (held as Dictionary).duplicate(true)
		cleaned.erase(id)
		if cleaned.get("only") is Array:
			# Every other season keeps its place; this one is on again.
			var only: Array = cleaned["only"]
			if not id in only:
				only.append(id)
			if only.size() >= model.season_ids().size():
				cleaned.erase("only")
		if cleaned != held:
			ops.append(
				DesignerPatch.erase_op(["rules", i, "seasons"])
				if cleaned.is_empty()
				else DesignerPatch.set_op(["rules", i, "seasons"], cleaned)
			)
	return model.apply_edit("Clear %s overrides" % id, ops)


## {ground: fields overridden, look: bool, density: classes, rules: rules with an override,
## hidden: rules left out, total: all of them} for season `id`, for the panels' words.
static func summary(model: BiomeDesignerModel, id: String) -> Dictionary:
	var over := _overrides(model, id)
	var ground: Variant = over.get("ground")
	var scale: Variant = over.get("density_scale")
	var by_key: Variant = over.get("rules")
	var touched := {}
	var hidden := 0
	for rule: Dictionary in model.def.get("rules", []):
		var key := String(rule["key"])
		if not BiomeSeasons.present_in(rule, id):
			hidden += 1
		if not BiomeSeasons.rule_override(rule, id).is_empty():
			touched[key] = true
		if by_key is Dictionary and (by_key as Dictionary).has(key):
			touched[key] = true
	var out := {
		"ground": (ground as Dictionary).size() if ground is Dictionary else 0,
		"look": not look_override(model, id).is_empty(),
		"density": (scale as Dictionary).size() if scale is Dictionary else 0,
		"rules": touched.size(),
		"hidden": hidden,
	}
	out["total"] = (
		int(out["ground"]) + int(out["look"]) + int(out["density"]) + int(out["rules"]) + hidden
	)
	return out


# ---- internals ----


static func _overrides(model: BiomeDesignerModel, id: String) -> Dictionary:
	return BiomeSeasons.season_overrides(model.def, id)


## Sets (or, when `value` is null or empty, erases) key `key` of season `id`'s overrides, and the
## overrides themselves when they end up empty.
static func _set_override(
	model: BiomeDesignerModel,
	id: String,
	key: String,
	value: Variant,
	label: String,
	merge_tag: String = ""
) -> bool:
	var at := model.season_ids().find(id)
	if at < 0:
		return false
	var over := _overrides(model, id).duplicate(true)
	var empty: bool = value == null or (value is Dictionary and (value as Dictionary).is_empty())
	if empty:
		if not over.has(key):
			return false
		over.erase(key)
	else:
		if over.get(key) == value:
			return false
		over[key] = value
	var path: Array = ["seasons", at, "overrides"]
	return model.apply_edit(
		label,
		[DesignerPatch.erase_op(path) if over.is_empty() else DesignerPatch.set_op(path, over)],
		merge_tag
	)


static func _set_rule_season(
	model: BiomeDesignerModel,
	at: int,
	id: String,
	over: Dictionary,
	label: String,
	merge_tag: String = ""
) -> bool:
	var held: Dictionary = (
		((model.def["rules"][at] as Dictionary).get("seasons", {}) as Dictionary).duplicate(true)
	)
	if over.is_empty():
		held.erase(id)
	else:
		held[id] = over
	return _apply_rule_seasons(model, at, held, label, merge_tag)


static func _apply_rule_seasons(
	model: BiomeDesignerModel, at: int, held: Dictionary, label: String, merge_tag: String = ""
) -> bool:
	var path: Array = ["rules", at, "seasons"]
	var current: Variant = DesignerPatch.get_at(model.def, path)
	if held.is_empty():
		if current == null:
			return false
		return model.apply_edit(label, [DesignerPatch.erase_op(path)])
	if current == held:
		return false
	return model.apply_edit(label, [DesignerPatch.set_op(path, held)], merge_tag)


## `held` (a rule's `seasons`) without season `id`; `remaining` are the seasons that stay (an
## `only` list that names all of them says nothing, so it goes).
static func _without_season(held: Dictionary, id: String, remaining: Array[String]) -> Dictionary:
	var out := held.duplicate(true)
	out.erase(id)
	if out.get("only") is Array:
		(out["only"] as Array).erase(id)
		var all := true
		for season in remaining:
			all = all and season in (out["only"] as Array)
		if all:
			out.erase("only")
	return out
