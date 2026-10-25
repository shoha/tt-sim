class_name DesignerSeasonSection
extends Foldout

## The rule inspector's Seasons section (step S9, design doc 2.6.2 `seasons`): in which seasons the
## rule grows (a check per season), and what it changes in the season on the map: its density (a
## multiplier, 0 takes the rule out of the season), weight, spacing and steepest slope. The values
## are kept in the rule's own `seasons` (DesignerSeasonEdits.set_rule_field) and laid over the
## rule when that season is compiled (BiomeSeasons), so the other seasons are untouched. A value
## that differs from the rule's own is marked; right-click its label to take the change away.
## Every control edits the model; a model change syncs them back without sending anything.

const ROWS: Array[Dictionary] = [
	{
		"field": "density_factor",
		"label": "Density x",
		"low": 0.0,
		"high": 3.0,
		"step": 0.05,
		"unit": "x",
		"tip": "A multiplier of the rule's density in this season. 0 takes the rule out of it.",
	},
	{
		"field": "weight",
		"label": "Weight",
		"low": 0.0,
		"high": 10.0,
		"step": 0.05,
		"unit": "",
		"tip": "The rule's share of its class's budget in this season.",
	},
	{
		"field": "spacing_m",
		"label": "Spacing",
		"low": 0.0,
		"high": 12.0,
		"step": 0.05,
		"unit": "m",
		"tip": "The least distance between plants in this season.",
	},
	{
		"field": "slope_max_deg",
		"label": "Slope, steepest",
		"low": 0.0,
		"high": 90.0,
		"step": 1.0,
		"unit": "deg",
		"tip": "The steepest ground the plants grow on in this season.",
	},
]

var session: BiomeDesignerSession = null

var _key: String = ""
var _note: Label
var _checks: HFlowContainer
var _heading: Label
var _rows: Dictionary = {}
var _clear: Button
var _syncing: bool = false


func _init() -> void:
	name = "Seasons"
	title = "Seasons"


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	_note = DesignerRows.caption("SeasonNote", "")
	add_child(_note)
	_checks = HFlowContainer.new()
	_checks.name = "Grows"
	add_child(_checks)
	_heading = Label.new()
	_heading.name = "SeasonHeading"
	_heading.theme_type_variation = &"H3"
	add_child(_heading)
	for spec in ROWS:
		var row := DesignerRows.number(
			"Row_" + String(spec["field"]),
			String(spec["label"]),
			float(spec["low"]),
			float(spec["high"]),
			float(spec["step"]),
			String(spec["tip"]),
			String(spec["unit"])
		)
		row.value_changed.connect(_on_number.bind(String(spec["field"])))
		row.reset_requested.connect(_on_reset.bind(String(spec["field"])))
		add_child(row)
		_rows[spec["field"]] = row
	_clear = Button.new()
	_clear.name = "ClearSeason"
	_clear.text = "Clear this rule's changes"
	_clear.pressed.connect(_on_clear)
	add_child(_clear)
	session.model.changed.connect(func(_reason: String) -> void: _sync())
	session.season_changed.connect(func(_index: int) -> void: _sync())


func show_rule(key: String) -> void:
	_key = key
	_sync()


## The PropertyRow editing `field`, for tests and probes.
func row_of(field: String) -> PropertyRow:
	return _rows.get(field)


## The check of season `id`, null when there is none.
func check_of(id: String) -> CheckBox:
	return _checks.get_node_or_null("Grows_" + id) as CheckBox


func _sync() -> void:
	if _key == "" or session == null or not session.model.has_rule(_key):
		return
	_syncing = true
	var model := session.model
	var ids := model.season_ids()
	var here := session.season_id()
	var several := ids.size() > 1
	_note.text = (
		"Where the rule grows, and how it changes in the season on the map."
		if several
		else "Add a season from the header's Seasons menu to vary this rule through the year."
	)
	_rebuild_checks(ids)
	_heading.visible = several
	_clear.visible = several
	var present := DesignerSeasonEdits.is_present(model, _key, here)
	_heading.text = "In %s" % here.capitalize()
	var over := DesignerSeasonEdits.rule_override(model, _key, here)
	for spec in ROWS:
		var field := String(spec["field"])
		var row: PropertyRow = _rows[field]
		row.visible = several and present
		var shown := 1.0 if field == "density_factor" else model.effective_number(_key, field)
		if over.has(field):
			shown = float(over[field])
		row.set_value_no_signal(shown)
		row.overridden = over.has(field)
	_clear.disabled = over.is_empty() and present
	_syncing = false


func _rebuild_checks(ids: Array[String]) -> void:
	var signature := hash([ids, _key])
	if _checks.has_meta("signature") and _checks.get_meta("signature") == signature:
		for id in ids:
			var existing := check_of(id)
			if existing != null:
				existing.set_pressed_no_signal(
					DesignerSeasonEdits.is_present(session.model, _key, id)
				)
		return
	_checks.set_meta("signature", signature)
	for child in _checks.get_children():
		_checks.remove_child(child)
		child.queue_free()
	for id in ids:
		var check := CheckBox.new()
		check.name = "Grows_" + id
		check.text = id.capitalize()
		check.tooltip_text = "The rule grows in %s." % id.capitalize()
		check.button_pressed = DesignerSeasonEdits.is_present(session.model, _key, id)
		check.toggled.connect(_on_present.bind(id))
		_checks.add_child(check)


func _on_present(on: bool, id: String) -> void:
	if not _syncing and _key != "":
		DesignerSeasonEdits.set_present(session.model, _key, id, on)


func _on_number(value: float, field: String) -> void:
	if _syncing or _key == "":
		return
	var stored: Variant = value
	if field == "density_factor" and is_equal_approx(value, 1.0):
		stored = null
	DesignerSeasonEdits.set_rule_field(session.model, _key, session.season_id(), field, stored, true)


func _on_reset(field: String) -> void:
	if _key != "":
		DesignerSeasonEdits.set_rule_field(session.model, _key, session.season_id(), field, null)


func _on_clear() -> void:
	if _key == "":
		return
	var here := session.season_id()
	var model := session.model
	var over := DesignerSeasonEdits.rule_override(model, _key, here)
	for field: String in over:
		DesignerSeasonEdits.set_rule_field(model, _key, here, field, null)
	DesignerSeasonEdits.set_present(model, _key, here, true)
