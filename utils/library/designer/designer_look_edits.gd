class_name DesignerLookEdits
extends RefCounted

## The model side of the ground look editor (step S9): reading and editing the biome's
## `ground_look` block field by field (GroundLook is the contract: BASE holds every key, RANGES
## the limits, validate() the consumer's lenient rules). A TARGET says where an edit lands:
## `season` "" is the biome's own look (every season), a season id is that season's override
## (`seasons[i].overrides.ground_look`, deep-merged over the biome's at compile, BiomeSeasons), so
## a winter can change two colours and keep the rest. A field is addressed by (`group`, `key`)
## like `zones`, `strength`. Commands on a BiomeDesignerModel are static functions, each one
## undoable step; a drag folds into one through `merge`.
##
## The LIBRARY value of a field is its value in the biome as last saved (what the library ships):
## `reset_value` puts it back, `is_changed` says whether the draft differs from it.
## Colours are stored in LINEAR light as the contract says; the panel shows them in sRGB.

## The look a biome without one starts as when the editor adds a look: four earthy zones and the
## BASE for everything else (GroundLook.validate needs three or four zone colours).
const DEFAULT_COLORS: Array = [
	[0.16, 0.30, 0.08], [0.05, 0.19, 0.09], [0.45, 0.30, 0.10], [0.28, 0.18, 0.36]
]


## The raw look the compiler reads for `season` (the biome's, with that season's override laid
## over it); {} when the biome has none. A copy. Season "" is the biome's own.
static func raw(model: BiomeDesignerModel, season: String) -> Dictionary:
	return _look_of(BiomeSeasons.effective(model.def, season) if season != "" else model.def)


## The look as the game keeps it for display: GroundLook.BASE with `raw` merged over it.
static func merged(model: BiomeDesignerModel, season: String) -> Dictionary:
	return BiomeSeasons.deep_merge(GroundLook.BASE, raw(model, season))


## The value of (`group`, `key`) as `season` sees it (a copy for lists).
static func value(model: BiomeDesignerModel, season: String, group: String, key: String) -> Variant:
	return _field(merged(model, season), group, key)


## The value of (`group`, `key`) in the biome as last saved, for the same season.
static func library_value(
	model: BiomeDesignerModel, season: String, group: String, key: String
) -> Variant:
	var saved := model.saved_def()
	var look := _look_of(BiomeSeasons.effective(saved, season) if season != "" else saved)
	return _field(BiomeSeasons.deep_merge(GroundLook.BASE, look), group, key)


## Whether the draft's value differs from the library's.
static func is_changed(
	model: BiomeDesignerModel, season: String, group: String, key: String
) -> bool:
	return not _same(
		value(model, season, group, key), library_value(model, season, group, key)
	)


## Whether the biome (or `season`) has any look at all.
static func has_look(model: BiomeDesignerModel, season: String) -> bool:
	return not raw(model, season).is_empty()


## Whether the target holds an explicit value for (`group`, `key`).
static func is_set(model: BiomeDesignerModel, season: String, group: String, key: String) -> bool:
	var target := _target(model, season)
	return target.get(group) is Dictionary and (target[group] as Dictionary).has(key)


## Gives the biome a look when it has none (DEFAULT_COLORS and the BASE for the rest). False when
## it has one.
static func add_look(model: BiomeDesignerModel) -> bool:
	if has_look(model, ""):
		return false
	var look := {"zones": {"colors_linear": DEFAULT_COLORS.duplicate(true)}}
	var ground: Variant = model.def.get("ground")
	var surface: Variant = (ground as Dictionary).get("surface") if ground is Dictionary else null
	if surface is String and surface != "":
		look["ref_surface"] = SurfaceStore.runtime_name(surface)
	return DesignerBiomeEdits.set_ground_look(model, look)


## Sets (`group`, `key`) to `new_value` on the target of `season` (see the header); `merge`
## folds a drag into one undo step. A season target cannot be made before the biome has a look.
static func set_value(
	model: BiomeDesignerModel,
	season: String,
	group: String,
	key: String,
	new_value: Variant,
	merge: bool = false
) -> bool:
	if not GroundLook.BASE.has(group) or not (GroundLook.BASE[group] as Dictionary).has(key):
		return false
	var target := _target(model, season)
	var section: Dictionary = (target.get(group, {}) as Dictionary).duplicate(true)
	if _same(section.get(key), new_value):
		return false
	section[key] = new_value
	target[group] = section
	return _write(model, season, target, "Set %s.%s" % [group, key], merge)


## Puts (`group`, `key`) back to the library's: the saved explicit value, or none (the BASE shows
## through) when the saved target had none.
static func reset_value(
	model: BiomeDesignerModel, season: String, group: String, key: String
) -> bool:
	var saved := _target_of(model.saved_def(), season)
	var target := _target(model, season)
	var section: Dictionary = (target.get(group, {}) as Dictionary).duplicate(true)
	var held: Variant = (saved.get(group, {}) as Dictionary).get(key)
	if held == null:
		if not section.has(key):
			return false
		section.erase(key)
	elif _same(section.get(key), held):
		return false
	else:
		section[key] = held.duplicate(true) if held is Array else held
	if section.is_empty():
		target.erase(group)
	else:
		target[group] = section
	return _write(model, season, target, "Reset %s.%s" % [group, key], false)


## Puts the whole target back to the library's look.
static func reset_all(model: BiomeDesignerModel, season: String) -> bool:
	var saved := _target_of(model.saved_def(), season)
	if _same(saved, _target(model, season)):
		return false
	return _write(model, season, saved, "Reset ground look", false)


## Sets zone colour `index` (0..3) to `srgb` (a colour as the picker shows it); the look keeps
## it in linear light. `index` == the current count appends one (at most GroundLook.MAX_COLORS).
static func set_zone_color(
	model: BiomeDesignerModel, season: String, index: int, srgb: Color, merge: bool = false
) -> bool:
	var colors: Array = (value(model, season, "zones", "colors_linear") as Array).duplicate(true)
	if index < 0 or index > colors.size() or index >= GroundLook.MAX_COLORS:
		return false
	var linear := srgb.srgb_to_linear()
	var triple := [snappedf(linear.r, 0.0001), snappedf(linear.g, 0.0001), snappedf(linear.b, 0.0001)]
	if index == colors.size():
		colors.append(triple)
	else:
		colors[index] = triple
	return set_value(model, season, "zones", "colors_linear", colors, merge)


## Removes zone colour `index` (the look keeps at least GroundLook.MIN_COLORS).
static func remove_zone_color(model: BiomeDesignerModel, season: String, index: int) -> bool:
	var colors: Array = (value(model, season, "zones", "colors_linear") as Array).duplicate(true)
	if colors.size() <= GroundLook.MIN_COLORS or index < 0 or index >= colors.size():
		return false
	colors.remove_at(index)
	return set_value(model, season, "zones", "colors_linear", colors)


## `linear` (a stored colour triple) as the sRGB colour the picker shows.
static func display_color(linear: Variant) -> Color:
	if not linear is Array or (linear as Array).size() < 3:
		return Color.BLACK
	var triple: Array = linear
	return Color(float(triple[0]), float(triple[1]), float(triple[2])).linear_to_srgb()


## The words about (`group`, `key`) as the consumer reads the draft: an explicit value outside its
## range (clamped by the game) or of the wrong shape; "" when it is fine.
static func field_problem(
	model: BiomeDesignerModel, season: String, group: String, key: String
) -> String:
	var held: Variant = _field(raw(model, season), group, key)
	if held == null:
		return ""
	var name := "%s.%s" % [group, key]
	var base: Variant = _field(GroundLook.BASE, group, key)
	var limits: Array = GroundLook.RANGES.get(name, [-INF, INF])
	if name == "zones.colors_linear":
		var count: int = (held as Array).size() if held is Array else 0
		if count < GroundLook.MIN_COLORS or count > GroundLook.MAX_COLORS:
			return "needs %d or %d colours" % [GroundLook.MIN_COLORS, GroundLook.MAX_COLORS]
		for triple: Variant in held as Array:
			if not triple is Array or (triple as Array).size() != 3:
				return "needs colours of three numbers"
			for item: Variant in triple as Array:
				var problem := _number_problem(item, limits)
				if problem != "":
					return problem
		return ""
	if base is Array:
		if not held is Array or (held as Array).size() != (base as Array).size():
			return "needs a list of %d numbers" % (base as Array).size()
		for item: Variant in held as Array:
			var problem := _number_problem(item, limits)
			if problem != "":
				return problem
		return ""
	return _number_problem(held, limits)


## The consumer's lines about the draft's look for `season` (GroundLook.validate's warnings), and
## whether the biome would fall back to today's ground (a look without usable zone colours).
static func warnings(model: BiomeDesignerModel, season: String) -> Array[String]:
	var out: Array[String] = []
	var look := raw(model, season)
	if look.is_empty():
		return out
	var ground: Variant = BiomeSeasons.effective(model.def, season).get("ground")
	var surface := String((ground as Dictionary).get("surface", "")) if ground is Dictionary else ""
	GroundLook.validate(
		look, model.biome_id, surface, model.context.get("surfaces", {}), out
	)
	return out


## How many biomes of the proving ground carry a look (the draft, and the reference in the A/B
## view): GroundLookBake draws at most GroundLookUniforms.SLOTS per map.
static func looked_biomes(biome_ids: PackedStringArray) -> int:
	var count := 0
	for id in biome_ids:
		if not PaletteLibrary.ground_look(id).is_empty():
			count += 1
	return count


# ---- internals ----


static func _look_of(def: Dictionary) -> Dictionary:
	var held: Variant = def.get("ground_look")
	return (held as Dictionary).duplicate(true) if held is Dictionary else {}


static func _field(look: Dictionary, group: String, key: String) -> Variant:
	var section: Variant = look.get(group)
	if not section is Dictionary or not (section as Dictionary).has(key):
		return null
	var held: Variant = (section as Dictionary)[key]
	return held.duplicate(true) if held is Array else held


## What an edit on `season`'s target writes to: the biome's look or the season's override.
static func _target(model: BiomeDesignerModel, season: String) -> Dictionary:
	return _target_of(model.def, season)


static func _target_of(def: Dictionary, season: String) -> Dictionary:
	if season == "":
		return _look_of(def)
	var held: Variant = BiomeSeasons.season_overrides(def, season).get("ground_look")
	return (held as Dictionary).duplicate(true) if held is Dictionary else {}


static func _write(
	model: BiomeDesignerModel, season: String, target: Dictionary, label: String, merge: bool
) -> bool:
	var tag := "look:%s:%s" % [season, label] if merge else ""
	if season == "":
		return DesignerBiomeEdits.set_ground_look(model, target, tag)
	return DesignerSeasonEdits.set_ground_look(model, season, target, tag)


static func _number_problem(item: Variant, limits: Array) -> String:
	if item is bool or not (item is float or item is int):
		return "needs a number"
	var number := float(item)
	if is_nan(number) or is_inf(number):
		return "needs a finite number"
	if number < float(limits[0]):
		return "is under %s, the game raises it" % _short(float(limits[0]))
	if number > float(limits[1]):
		return "is over %s, the game lowers it" % _short(float(limits[1]))
	return ""


static func _short(number: float) -> String:
	return str(snappedf(number, 0.0001))


static func _same(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		return (a as Dictionary).hash() == (b as Dictionary).hash()
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b
