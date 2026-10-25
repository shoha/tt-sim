class_name DesignerSlotList
extends VBoxContainer

## Panel 2 of the biome designer (design doc 4.3): the rules grouped by what they are to the
## ground, in the slots an author thinks in (canopy, understory, shrubs, grass...). Every slot is
## shown even when empty, so a gap is visible. A rule is a chip; clicking it selects the rule,
## right-clicking opens its menu (duplicate, remove, lock), "+" starts a rule of the slot's role,
## dropping an asset on a chip adds it to the rule (Shift pins it), on a slot's header or its "+"
## starts a rule from the asset, and dragging a chip onto another slot changes its role.

signal rule_selected(key: String)
signal add_rule_requested(role: String)

const SLOTS_MIN_HEIGHT := 150.0
const MENU_DUPLICATE := 1
const MENU_REMOVE := 2
const MENU_LOCK := 3

var session: BiomeDesignerSession = null

var _scroll: ScrollContainer
var _box: VBoxContainer
var _chips: Dictionary = {}
var _signature: int = 0
var _menu: PopupMenu
var _menu_key: String = ""
var _role_menu: PopupMenu
var _role_group: String = ""


func _init() -> void:
	name = "SlotList"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "Slots"
	title.theme_type_variation = &"H3"
	add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.name = "SlotScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0.0, SLOTS_MIN_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.name = "Slots"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	_menu = PopupMenu.new()
	_menu.name = "ChipMenu"
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	_role_menu = PopupMenu.new()
	_role_menu.name = "RoleMenu"
	_role_menu.id_pressed.connect(_on_role_menu)
	add_child(_role_menu)


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	session.model.changed.connect(func(_reason: String) -> void: refresh())
	session.selection_changed.connect(func(_key: String) -> void: _mark_selection())
	session.compiled.connect(func(_result: Dictionary) -> void: _update_chips())
	refresh()


## The chip of rule `key`, null when there is none.
func chip_of(key: String) -> DesignerSlotChip:
	return _chips.get(key)


func refresh() -> void:
	var model := session.model
	var signature := hash([model.rule_keys(), _roles(), model.locks.keys()])
	if signature != _signature:
		_signature = signature
		_rebuild()
	_update_chips()


func _roles() -> Array:
	var out := []
	for key in session.model.rule_keys():
		out.append(session.model.value(key, "role"))
	return out


func _rebuild() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_chips.clear()
	var by_role := session.model.rules_by_role()
	for group in DesignerSlots.GROUPS:
		var row := _slot_row(group, by_role)
		_box.add_child(row)
	_mark_selection()


func _slot_row(group: Dictionary, by_role: Dictionary) -> Control:
	var row := DesignerSlotRow.new()
	row.name = "Slot_" + String(group["id"])
	row.group_id = String(group["id"])
	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = String(group["label"])
	label.tooltip_text = String(group["hint"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var plus := Button.new()
	plus.name = "Add_" + String(group["id"])
	plus.text = "+"
	plus.theme_type_variation = &"Chip"
	plus.tooltip_text = "Start a %s rule" % String(group["label"]).to_lower()
	plus.pressed.connect(_on_plus.bind(String(group["id"]), plus))
	head.add_child(plus)
	row.add_child(head)
	var flow := HFlowContainer.new()
	flow.name = "Chips"
	row.add_child(flow)
	var any := false
	for role: String in group["roles"]:
		for key: String in by_role.get(role, []):
			any = true
			var chip := DesignerSlotChip.new()
			chip.setup(key)
			chip.pressed.connect(func() -> void: rule_selected.emit(key))
			chip.asset_dropped.connect(_on_asset_dropped)
			chip.menu_requested.connect(_on_menu_requested)
			flow.add_child(chip)
			_chips[key] = chip
	if not any:
		var none := Label.new()
		none.text = "no rules"
		none.theme_type_variation = &"Caption"
		flow.add_child(none)
	row.asset_dropped.connect(_on_slot_asset)
	row.rule_dropped.connect(_on_slot_rule)
	return row


func _update_chips() -> void:
	var verdict := session.model.validation()
	for key: String in _chips:
		var chip: DesignerSlotChip = _chips[key]
		var problem := ""
		for item: Dictionary in DesignerValidation.for_rule(verdict, key):
			if item["level"] == "error" or problem == "":
				problem = String(item["message"])
		var season := session.model.season_ids()[session.season_index]
		var assets := session.model.resolved_assets(key, season).size()
		chip.show_state(assets, problem, session.model.is_locked(key))
	_mark_selection()


func _mark_selection() -> void:
	for key: String in _chips:
		(_chips[key] as DesignerSlotChip).set_pressed_no_signal(key == session.selected_rule)


func _on_plus(group_id: String, button: Button) -> void:
	var roles: Array = DesignerSlots.group(group_id)["roles"]
	if roles.size() == 1:
		add_rule_requested.emit(String(roles[0]))
		return
	_role_group = group_id
	_role_menu.clear()
	for i in roles.size():
		_role_menu.add_item(DesignerSlots.role_label(String(roles[i])), i)
	_role_menu.position = Vector2i(button.get_screen_position() + Vector2(0.0, button.size.y))
	_role_menu.popup()


func _on_role_menu(id: int) -> void:
	var roles: Array = DesignerSlots.group(_role_group)["roles"]
	if id >= 0 and id < roles.size():
		add_rule_requested.emit(String(roles[id]))


func _on_menu_requested(key: String, at: Vector2) -> void:
	_menu_key = key
	_menu.clear()
	_menu.add_item("Duplicate", MENU_DUPLICATE)
	_menu.add_item("Remove", MENU_REMOVE)
	var locked := session.model.is_locked(key)
	_menu.add_item("Unlock selection" if locked else "Lock selection", MENU_LOCK)
	_menu.position = Vector2i(at)
	_menu.popup()


func _on_menu(id: int) -> void:
	var model := session.model
	match id:
		MENU_DUPLICATE:
			var copy := model.duplicate_rule(_menu_key)
			if copy != "":
				session.select_rule(copy)
		MENU_REMOVE:
			if model.remove_rule(_menu_key) and session.selected_rule == _menu_key:
				session.select_rule("")
		MENU_LOCK:
			model.set_locked(_menu_key, not model.is_locked(_menu_key))


func _on_asset_dropped(key: String, ref: String, pin: bool) -> void:
	if pin:
		session.model.set_pin(key, ref, true)
	else:
		session.model.add_ref(key, ref)
	session.select_rule(key)


## An asset dropped on a slot's header: a new rule of the slot's role that selects it.
func _on_slot_asset(group_id: String, ref: String) -> void:
	var role := String(DesignerSlots.group(group_id)["roles"][0])
	var key := session.model.add_rule(role, {"match": [{"ref": ref}]}, ref)
	if key != "":
		session.select_rule(key)


## A chip dropped on a slot: the rule takes the slot's first role.
func _on_slot_rule(group_id: String, key: String) -> void:
	var role := String(DesignerSlots.group(group_id)["roles"][0])
	var current := String(session.model.value(key, "role", ""))
	if DesignerSlots.group_of(current) != group_id:
		session.model.set_role(key, role)
