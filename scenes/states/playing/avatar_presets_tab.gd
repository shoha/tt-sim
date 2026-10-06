class_name AvatarPresetsTab
extends MarginContainer

## The "Player avatars" tab of the Add Token browser: the preset avatars (AvatarPresets)
## and a stance to stand them in. Activating a preset emits its recipe, with the chosen
## stance when one is picked, for the GM's add-token flow to spawn as an avatar token. A
## stopgap until the avatar builder replaces it.

signal avatar_selected(recipe: Dictionary, token_name: String)

const TAB_TITLE := "Player avatars"
## The stance option that keeps each preset's own stance.
const OWN_STANCE_LABEL := "Preset's own"

## Stance ids by option index (index 0, the preset's own, is "").
var _stances: Array[String] = [""]

@onready var stance_option: OptionButton = %StanceOption
@onready var preset_list: ItemList = %PresetList


func _ready() -> void:
	stance_option.clear()
	stance_option.add_item(OWN_STANCE_LABEL)
	var kit := AvatarTokenFactory.kit()
	if kit != null:
		for stance in kit.stance_names():
			_stances.append(String(stance))
			stance_option.add_item(AvatarPresets.stance_label(String(stance)))
	preset_list.clear()
	for preset in AvatarPresets.PRESETS:
		preset_list.add_item(String(preset.name))
	# One click adds, as the panel's hint says (not item_activated as well: a double click
	# would then add two).
	preset_list.item_clicked.connect(_on_item_clicked)


func _on_item_clicked(index: int, _at: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		activate(index)


## Emits preset `index`'s recipe in the chosen stance (the tab's activation, and the
## validation bridge's way in).
func activate(index: int) -> void:
	if index < 0 or index >= AvatarPresets.PRESETS.size():
		return
	var stance := _stances[maxi(0, stance_option.selected)]
	avatar_selected.emit(
		AvatarPresets.recipe(index, stance), String(AvatarPresets.PRESETS[index].name)
	)
