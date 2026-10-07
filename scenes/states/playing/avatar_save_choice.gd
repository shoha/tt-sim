class_name AvatarSaveChoice
extends HBoxContainer

## The avatar builder's offer to keep an avatar made or edited in a game in the player's
## library (AvatarLibrary): a "Save to my avatars" check, on by default. When the avatar
## came from the library (`setup` with its entry), a choice beside it picks between
## updating that entry (the default) and saving a new one.

const UPDATE := 0
const SAVE_NEW := 1

var _check: CheckBox
var _target: OptionButton
var _existing: Dictionary = {}


func _init() -> void:
	name = "SaveChoice"
	add_theme_constant_override("separation", 8)
	_check = CheckBox.new()
	_check.name = "SaveCheck"
	_check.text = "Save to my avatars"
	_check.button_pressed = true
	_check.tooltip_text = "Keep this avatar on this computer, for any game"
	_check.toggled.connect(func(_on: bool) -> void: _refresh())
	add_child(_check)
	_target = OptionButton.new()
	_target.name = "SaveTarget"
	_target.visible = false
	add_child(_target)


## Offers to update `existing` (a library entry) as well as saving a new avatar; an empty
## entry offers a new avatar only.
func setup(existing: Dictionary) -> void:
	_existing = existing
	_target.clear()
	if not existing.is_empty():
		_target.add_item("Update %s" % String(existing.get("name", "")), UPDATE)
		_target.add_item("As a new avatar", SAVE_NEW)
		_target.select(0)
	_refresh()


## Whether the player wants the avatar saved.
func wants_save() -> bool:
	return _check.button_pressed


## Sets the check (the bridge and tests).
func set_save(on: bool) -> void:
	_check.button_pressed = on


## The library id to update, or "" for a new avatar.
func update_id() -> String:
	if _existing.is_empty() or _target.get_selected_id() != UPDATE:
		return ""
	return String(_existing.get("id", ""))


## Picks a new avatar over updating the existing one (the bridge and tests).
func choose_new(on: bool) -> void:
	if _target.item_count > 1:
		_target.select(1 if on else 0)


func _refresh() -> void:
	_target.visible = wants_save() and not _existing.is_empty()
