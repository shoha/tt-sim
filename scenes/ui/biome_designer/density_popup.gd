class_name DesignerDensityPopup
extends PopupPanel

## The biome-wide density by size class (design doc 2.6.1 `density_scale`, step S9): one
## multiplier for each of large, medium, small and ground, applied to the density of every rule of
## the class (BiomeSeasons; 1 is no change, 0 empties the class). It edits where the ground strip's
## "Applies to" points: the biome (every season) or one season's own scale, which is laid over the
## biome's. A row that differs from the library's is marked; right-click its name to take the
## change away. The popup opens from the ground strip's Density... button.

const CLASSES: Array = [
	["large", "Large (trees)"],
	["medium", "Medium (shrubs)"],
	["small", "Small (ferns, rocks)"],
	["ground", "Ground (grass, flowers)"],
]
const WIDTH := 360.0

var session: BiomeDesignerSession = null

var _target: Label
var _rows: Dictionary = {}
var _syncing: bool = false


func _init() -> void:
	name = "DensityPopup"
	var box := VBoxContainer.new()
	box.name = "Body"
	box.custom_minimum_size = Vector2(WIDTH, 0.0)
	add_child(box)
	var title := Label.new()
	title.text = "Density by size class"
	title.theme_type_variation = &"H3"
	box.add_child(title)
	_target = DesignerRows.caption("Target", "")
	box.add_child(_target)
	for item: Array in CLASSES:
		var row := DesignerRows.number(
			"Scale_" + String(item[0]),
			String(item[1]),
			0.0,
			3.0,
			0.05,
			"A multiplier of every %s rule's density." % String(item[0]),
			"x"
		)
		row.allow_greater = true
		row.value_changed.connect(_on_value.bind(String(item[0])))
		row.reset_requested.connect(_on_reset.bind(String(item[0])))
		box.add_child(row)
		_rows[item[0]] = row


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	session.model.changed.connect(func(_reason: String) -> void: _sync())
	session.edit_target_changed.connect(func(_season: String) -> void: _sync())
	_sync()


## The PropertyRow of size class `size_class`, for tests and probes.
func row_of(size_class: String) -> PropertyRow:
	return _rows.get(size_class)


## The scale of `size_class` as the target sees it: the season's own, else the biome's, else 1.
func scale_of(size_class: String) -> float:
	var season := session.edit_season
	if season != "":
		var own: Variant = _own(season, size_class)
		if own != null:
			return float(own)
	var base: Variant = (session.model.def.get("density_scale", {}) as Dictionary).get(size_class)
	return float(base) if base != null else 1.0


func _own(season: String, size_class: String) -> Variant:
	var held: Variant = BiomeSeasons.season_overrides(session.model.def, season).get("density_scale")
	return (held as Dictionary).get(size_class) if held is Dictionary else null


func _sync() -> void:
	if session == null:
		return
	_syncing = true
	var season := session.edit_season
	_target.text = (
		"Every season's density, by size class."
		if season == ""
		else "%s only: laid over the biome's own scale." % season.capitalize()
	)
	for size_class: String in _rows:
		var row: PropertyRow = _rows[size_class]
		row.set_value_no_signal(scale_of(size_class))
		row.overridden = (
			_own(season, size_class) != null
			if season != ""
			else (session.model.def.get("density_scale", {}) as Dictionary).has(size_class)
		)
	_syncing = false


func _on_value(value: float, size_class: String) -> void:
	if _syncing:
		return
	var season := session.edit_season
	if season != "":
		DesignerSeasonEdits.set_density_scale(session.model, season, size_class, value)
	else:
		DesignerBiomeEdits.set_density_scale(
			session.model, size_class, null if is_equal_approx(value, 1.0) else value
		)


func _on_reset(size_class: String) -> void:
	var season := session.edit_season
	if season != "":
		DesignerSeasonEdits.set_density_scale(session.model, season, size_class, null)
	else:
		DesignerBiomeEdits.set_density_scale(session.model, size_class, null)
