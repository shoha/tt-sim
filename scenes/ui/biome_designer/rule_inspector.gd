class_name DesignerRuleInspector
extends VBoxContainer

## Panel 4 of the biome designer (design doc 4.3): the selected rule. A header (name, role, class,
## lock, duplicate, remove, and the validators' words about the rule), then sections: the assets
## the rule selects (DesignerQuerySection), placement (weight, density, spacing, slopes, spread,
## yaw) with the class mix, terrain response (the slope, height and wet curves,
## DesignerResponseSection) and habit, clump and relations (DesignerHabitSection). Every control
## edits the model through the session; a model change (an undo, a drag elsewhere) syncs the
## controls back without sending anything. Sliders edit with `merge`, so a drag is one undo step.

const NUMBER_ROWS: Array[Dictionary] = [
	{
		"field": "weight",
		"label": "Weight",
		"low": 0.0,
		"high": 10.0,
		"step": 0.05,
		"unit": "",
		"tip":
		"The rule's share of its size class's density budget (relative to the other rules of the class).",
	},
	{
		"field": "density_per_m2",
		"label": "Density",
		"low": 0.0005,
		"high": 8.0,
		"step": 0.0005,
		"unit": "/m2",
		"log": true,
		"tip":
		"Plants per square metre at full paint and full response (the response curves only lower it).",
	},
	{
		"field": "spacing_m",
		"label": "Spacing",
		"low": 0.0,
		"high": 12.0,
		"step": 0.05,
		"unit": "m",
		"tip": "The least distance between two plants of the rule's size class.",
	},
	{
		"field": "slope_max_deg",
		"label": "Slope, steepest",
		"low": 0.0,
		"high": 90.0,
		"step": 1.0,
		"unit": "deg",
		"tip": "Plants fade out over the 10 degrees above this slope.",
	},
	{
		"field": "slope_min_deg",
		"label": "Slope, gentlest",
		"low": 0.0,
		"high": 90.0,
		"step": 1.0,
		"unit": "deg",
		"tip":
		(
			"A band edge: no plants on ground flatter than this (they fade in over the 5 degrees "
			+ "below). 0 is off."
		),
	},
	{
		"field": "scale_spread",
		"label": "Size variation",
		"low": 0.0,
		"high": 0.9,
		"step": 0.01,
		"unit": "",
		"tip": "How much plants of the rule differ in size.",
	},
	{
		"field": "yaw_random_deg",
		"label": "Turn",
		"low": 0.0,
		"high": 360.0,
		"step": 5.0,
		"unit": "deg",
		"tip": "How far each plant is turned at random about its own axis.",
	},
]
## The rows whose value has a class default to be marked against (and reset to).
const CLASS_FIELDS: Array[String] = ["spacing_m", "slope_max_deg", "scale_spread", "yaw_random_deg"]
const CLASS_OPTIONS: Array = [
	["large", "Large"], ["medium", "Medium"], ["small", "Small"], ["ground", "Ground"]
]

var session: BiomeDesignerSession = null

var _key: String = ""
var _empty: Label
var _body: VBoxContainer
var _name_edit: LineEdit
var _role: OptionButton
var _class: OptionButton
var _lock: Button
var _focus: Button
var _lock_words: Label
var _lock_again: Button
var _issues: VBoxContainer
var _rows: Dictionary = {}
var _mix_box: VBoxContainer
var _mix_keys: Array[String] = []
var _query: DesignerQuerySection
var _response: DesignerResponseSection
var _habit: DesignerHabitSection
var _seasons: DesignerSeasonSection


func _init() -> void:
	name = "RuleInspector"
	_empty = DesignerRows.caption(
		"Empty", "Select a rule from the slots, or drag an asset onto a slot to start one."
	)
	add_child(_empty)
	_body = VBoxContainer.new()
	_body.name = "Body"
	add_child(_body)


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	_build_header()
	_build_placement()
	_query = DesignerQuerySection.new()
	_query.setup(session)
	_body.add_child(_query)
	_response = DesignerResponseSection.new()
	_response.setup(session)
	_body.add_child(_response)
	_habit = DesignerHabitSection.new()
	_habit.setup(session)
	_body.add_child(_habit)
	_seasons = DesignerSeasonSection.new()
	_seasons.setup(session)
	_body.add_child(_seasons)
	session.selection_changed.connect(show_rule)
	session.model.changed.connect(func(_reason: String) -> void: _sync())
	session.compiled.connect(func(_result: Dictionary) -> void: _show_issues())
	show_rule(session.selected_rule)


## Shows rule `key` ("" for none).
func show_rule(key: String) -> void:
	_key = key if session.model.has_rule(key) else ""
	if session.focus_rule != "" and session.focus_rule != _key:
		session.set_focus(_key)  # "Show only this" follows the selection.
	_empty.visible = _key == ""
	_body.visible = _key != ""
	if _key != "":
		_query.show_rule(_key)
		_response.show_rule(_key)
		_habit.show_rule(_key)
		_seasons.show_rule(_key)
		_sync()


func current_key() -> String:
	return _key


## The PropertyRow editing `field`, for tests and probes.
func row_of(field: String) -> PropertyRow:
	return _rows.get(field)


func _build_header() -> void:
	var title := Label.new()
	title.text = "Rule"
	title.theme_type_variation = &"H3"
	_body.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.name = "RuleName"
	_name_edit.tooltip_text = "The rule's name. Other rules refer to it by this."
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(func() -> void: _on_name_submitted(_name_edit.text))
	_body.add_child(_name_edit)
	var roles: Array = []
	for role: String in LibraryContracts.ROLES:
		roles.append([role, DesignerSlots.role_label(role)])
	_role = DesignerRows.option(
		_body, "Role", "Role", roles, "What the rule's plants are to the ground rules."
	)
	_role.item_selected.connect(_on_role_selected)
	_class = DesignerRows.option(
		_body,
		"SizeClass",
		"Class",
		CLASS_OPTIONS,
		"Which budget and spacing family the rule belongs to."
	)
	_class.item_selected.connect(_on_class_selected)
	var buttons := HBoxContainer.new()
	buttons.name = "RuleButtons"
	_lock = Button.new()
	_lock.name = "Lock"
	_lock.text = "Lock selection"
	_lock.toggle_mode = true
	_lock.tooltip_text = (
		"Freeze which assets the query picks now; Save writes them to the lock file so a "
		+ "catalog update cannot change them."
	)
	_lock.toggled.connect(func(on: bool) -> void: session.model.set_locked(_key, on))
	buttons.add_child(_lock)
	_focus = Button.new()
	_focus.name = "Focus"
	_focus.text = "Show only this"
	_focus.toggle_mode = true
	_focus.tooltip_text = (
		"Hide every other rule's plants on the map, to judge this one alone. "
		+ "Nothing is removed from the biome."
	)
	_focus.toggled.connect(func(on: bool) -> void: session.set_focus(_key if on else ""))
	buttons.add_child(_focus)
	var copy := Button.new()
	copy.name = "Duplicate"
	copy.text = "Duplicate"
	copy.pressed.connect(
		func() -> void:
			var made := session.model.duplicate_rule(_key)
			if made != "":
				session.select_rule(made)
	)
	buttons.add_child(copy)
	var remove := Button.new()
	remove.name = "Remove"
	remove.text = "Remove"
	remove.pressed.connect(
		func() -> void:
			var gone := _key
			session.select_rule("")
			session.model.remove_rule(gone)
	)
	buttons.add_child(remove)
	_body.add_child(buttons)
	var lock_line := HBoxContainer.new()
	lock_line.name = "LockLine"
	_lock_words = DesignerRows.caption("LockWords", "")
	lock_line.add_child(_lock_words)
	_lock_again = DesignerRows.chip(
		"LockAgain", "Lock again", "Take the selection from the query as it is now."
	)
	_lock_again.pressed.connect(func() -> void: DesignerLocks.refresh(session.model, _key))
	lock_line.add_child(_lock_again)
	_body.add_child(lock_line)
	_issues = VBoxContainer.new()
	_issues.name = "Issues"
	_body.add_child(_issues)


func _build_placement() -> void:
	var section := DesignerRows.section("Placement", "Placement", true)
	for spec in NUMBER_ROWS:
		var row := DesignerRows.number(
			"Row_" + String(spec["field"]),
			String(spec["label"]),
			float(spec["low"]),
			float(spec["high"]),
			float(spec["step"]),
			String(spec["tip"]),
			String(spec["unit"]),
			bool(spec.get("log", false))
		)
		row.value_changed.connect(_on_number.bind(String(spec["field"])))
		row.reset_requested.connect(_on_reset.bind(String(spec["field"])))
		section.add_child(row)
		_rows[spec["field"]] = row
	_body.add_child(section)
	var mix := DesignerRows.section("Mix", "Mix of the class")
	_mix_box = VBoxContainer.new()
	_mix_box.name = "MixRows"
	mix.add_child(_mix_box)
	_body.add_child(mix)


func _sync() -> void:
	if _key == "" or session == null or not session.model.has_rule(_key):
		return
	var model := session.model
	if not _name_edit.has_focus():
		_name_edit.text = _key
	DesignerRows.select(_role, model.value(_key, "role"))
	DesignerRows.select(
		_class,
		model.value(
			_key, "size_class", LibraryContracts.size_class_of(String(model.value(_key, "role")))
		)
	)
	_lock.set_pressed_no_signal(model.is_locked(_key))
	_show_lock(DesignerLocks.state(model, _key))
	_focus.set_pressed_no_signal(session.focus_rule == _key)
	for field: String in _rows:
		var row: PropertyRow = _rows[field]
		var shown := model.effective_number(_key, field)
		row.set_value_no_signal(shown)
		row.overridden = (
			field in CLASS_FIELDS
			and model.value(_key, field) != null
			and not is_equal_approx(float(model.value(_key, field)), _class_default(field))
		)
	_rebuild_mix()
	_show_issues()


## The words about the rule's lock (DesignerLocks.state): unlocked, locked, or stale
## because the query or the catalogs moved since it was taken.
func _show_lock(lock: Dictionary) -> void:
	var state := String(lock["state"])
	var words := ""
	match state:
		"unlocked":
			words = (
				"Not locked: the query decides which assets grow, so a catalog update can "
				+ "change them."
			)
		"locked":
			var held := 0
			for season: String in lock["seasons"]:
				held = maxi(held, (lock["seasons"][season]["held"] as Array).size())
			var plural := "" if held == 1 else "s"
			words = "Locked to %d picked asset%s. Save writes the lock file." % [held, plural]
			if not _lock_saved():
				words = "Locked to %d picked asset%s (not saved yet)." % [held, plural]
			if held == 0:
				words = "Locked, but its query names every asset, so nothing picked can change."
		"stale_query":
			words = "The query changed after the lock was taken, so the lock is ignored."
		"stale_catalog":
			var added := 0
			var gone := 0
			for season: String in lock["seasons"]:
				var held: Array = lock["seasons"][season]["held"]
				var now: Array = lock["seasons"][season]["now"]
				for ref in now:
					added += 0 if ref in held else 1
				for ref in held:
					gone += 0 if ref in now else 1
			words = (
				"The catalogs changed after the lock: the query would now give %d new and miss %d "
				% [added, gone]
				+ "locked asset%s." % ("" if gone == 1 else "s")
			)
	_lock_words.text = words
	_lock_again.visible = state == "stale_query" or state == "stale_catalog"


## Whether the lock file as last saved holds rule `_key`.
func _lock_saved() -> bool:
	for season in session.model.season_ids():
		if session.model.saved_locks().has("%s/%s" % [season, _key]):
			return true
	return false


## The class default of `field` for the selected rule (what a cleared field falls back to).
func _class_default(field: String) -> float:
	var role := String(session.model.value(_key, "role", ""))
	var size_class := String(
		session.model.value(_key, "size_class", LibraryContracts.size_class_of(role))
	)
	return float(LibraryContracts.class_defaults(size_class).get(field, 0.0))


func _rebuild_mix() -> void:
	var model := session.model
	var role := String(model.value(_key, "role", ""))
	var size_class := String(model.value(_key, "size_class", LibraryContracts.size_class_of(role)))
	var peers: Array[String] = []
	var total := 0.0
	for key in model.rule_keys():
		var peer_role := String(model.value(key, "role", ""))
		if (
			String(model.value(key, "size_class", LibraryContracts.size_class_of(peer_role)))
			== size_class
		):
			peers.append(key)
			total += model.effective_number(key, "weight")
	if _mix_box.get_child_count() != peers.size() or _mix_keys != peers:
		_mix_keys = peers
		for child in _mix_box.get_children():
			_mix_box.remove_child(child)
			child.queue_free()
		for key in peers:
			var row := DesignerRows.number(
				"Mix_" + key.validate_node_name(),
				key,
				0.0,
				10.0,
				0.05,
				"Weight of %s in the %s class." % [key, size_class]
			)
			row.value_changed.connect(
				func(value: float) -> void: session.model.set_field(key, "weight", value, true)
			)
			_mix_box.add_child(row)
	for i in peers.size():
		var row := _mix_box.get_child(i) as PropertyRow
		row.set_value_no_signal(model.effective_number(peers[i], "weight"))
		var share := model.effective_number(peers[i], "weight") / maxf(total, 0.0001)
		row.tooltip_text = (
			"%s: %d%% of the %s class" % [peers[i], roundi(share * 100.0), size_class]
		)


func _show_issues() -> void:
	for child in _issues.get_children():
		_issues.remove_child(child)
		child.queue_free()
	if _key == "":
		return
	var verdict := session.model.validation()
	for item: Dictionary in DesignerValidation.for_rule(verdict, _key):
		var line := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = IconButton.load_icon(
			"alert-circle" if item["level"] == "error" else "alert-triangle"
		)
		icon.modulate = ThemeColors.of(
			self, ThemeColors.DANGER if item["level"] == "error" else ThemeColors.WARNING
		)
		icon.custom_minimum_size = Vector2(18.0, 18.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(icon)
		line.add_child(DesignerRows.caption("Issue", _plain(String(item["message"]))))
		_issues.add_child(line)


## A validator line without its location prefix.
static func _plain(message: String) -> String:
	var at := message.find("': ")
	if at >= 0:
		return message.substr(at + 3)
	return message.get_slice(": ", message.count(": "))


func _on_number(value: float, field: String) -> void:
	if _key == "":
		return
	if field == "slope_min_deg":
		DesignerResponseEdits.set_slope_min(session.model, _key, value, true)
	else:
		session.model.set_field(_key, field, value, true)


func _on_reset(field: String) -> void:
	if _key != "":
		session.model.set_field(_key, field, null)


func _on_name_submitted(text: String) -> void:
	if _key == "" or text.strip_edges() == "" or text == _key:
		return
	var fresh := session.model.rename_rule(_key, text)
	if fresh != _key:
		_key = fresh
		session.selected_rule = fresh
		session.selection_changed.emit(fresh)


func _on_role_selected(index: int) -> void:
	session.model.set_role(_key, String(_role.get_item_metadata(index)))


func _on_class_selected(index: int) -> void:
	session.model.set_size_class(_key, String(_class.get_item_metadata(index)))
