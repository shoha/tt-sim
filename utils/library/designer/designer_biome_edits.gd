class_name DesignerBiomeEdits
extends RefCounted

## The edits of the biome as a whole in the designer (design doc 4.3, the ground strip and the
## header): ground surfaces, accents and paths, the ground look overrides, the density scale per
## class, the seasons and the biome's name. Commands on a BiomeDesignerModel; static functions
## over it (see DesignerResponseEdits for why).

const GROUND_FIELDS: Array[String] = ["surface", "cliff", "scree", "water_bed", "shore"]


## Sets a ground surface field (`surface`, `cliff`, `scree`, `water_bed`, `shore`); "" erases.
static func set_ground(model: BiomeDesignerModel, field: String, surface: String) -> bool:
	if not field in GROUND_FIELDS:
		return false
	return _set_ground_value(model, field, surface if surface != "" else null)


## The accent list: [{surface, coverage, scale_m}], at most 8; [] erases it.
static func set_accents(model: BiomeDesignerModel, accents: Array) -> bool:
	return _set_ground_value(model, "accents", accents if not accents.is_empty() else null)


## The path surfaces, first the most used; [] erases them.
static func set_paths(model: BiomeDesignerModel, paths: Array) -> bool:
	return _set_ground_value(model, "paths", paths if not paths.is_empty() else null)


static func ground_value(model: BiomeDesignerModel, field: String) -> Variant:
	return DesignerPatch.get_at(model.def, ["ground", field])


## Replaces the ground look overrides (verbatim over GroundLook.BASE); null or {} erases them.
static func set_ground_look(model: BiomeDesignerModel, look: Variant) -> bool:
	if look == null or (look is Dictionary and (look as Dictionary).is_empty()):
		if not model.def.has("ground_look"):
			return false
		return model.apply_edit("Clear ground look", [DesignerPatch.erase_op(["ground_look"])])
	return model.apply_edit("Edit ground look", [DesignerPatch.set_op(["ground_look"], look)])


## The biome-wide multiplier of one size class's budget; null erases it.
static func set_density_scale(
	model: BiomeDesignerModel, size_class: String, scale: Variant
) -> bool:
	var scales: Dictionary = (model.def.get("density_scale", {}) as Dictionary).duplicate()
	if scale == null:
		scales.erase(size_class)
	else:
		scales[size_class] = scale
	var op := (
		DesignerPatch.erase_op(["density_scale"])
		if scales.is_empty()
		else DesignerPatch.set_op(["density_scale"], scales)
	)
	return model.apply_edit("Edit density scale", [op])


## The season list: [{id, seed}], 1 to LibraryContracts.MAX_SEASONS.
static func set_seasons(model: BiomeDesignerModel, seasons: Array) -> bool:
	if seasons.is_empty() or seasons.size() > LibraryContracts.MAX_SEASONS:
		return false
	return model.apply_edit("Edit seasons", [DesignerPatch.set_op(["seasons"], seasons)])


## Sets name, description, climate or tags of the biome.
static func set_info(model: BiomeDesignerModel, field: String, new_value: Variant) -> bool:
	if not field in ["name", "description", "climate", "tags"]:
		return false
	if model.def.get(field) == new_value:
		return false
	return model.apply_edit("Edit %s" % field, [DesignerPatch.set_op([field], new_value)])


static func _set_ground_value(model: BiomeDesignerModel, field: String, new_value: Variant) -> bool:
	var path: Array = ["ground", field]
	var current: Variant = DesignerPatch.get_at(model.def, path)
	if new_value == null:
		if current == null:
			return false
		return model.apply_edit("Clear %s" % field, [DesignerPatch.erase_op(path)])
	if current == new_value:
		return false
	var ops: Array = []
	if not model.def.has("ground"):
		ops.append(DesignerPatch.set_op(["ground"], {}))
	ops.append(DesignerPatch.set_op(path, new_value))
	return model.apply_edit("Set ground %s" % field, ops)
