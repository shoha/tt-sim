class_name RoomRows
extends RefCounted

## The rows RoomPanel lists, built fresh from RoomModel data on every refresh: a player (a
## portrait well with the name's initial, the name, a GM chip, the selected map's download
## state (download_state()), and Choose avatar on your own row) and a shelf map (a thumbnail
## well, the name and a caption, selectable as a Tile). Every picture sits in a CardThumb
## well, so a map with no thumbnail shows the well's wash and the name's Fraunces initial,
## never a flat grey box.

const PORTRAIT := Vector2(40, 40)
const SHELF_THUMB := Vector2(64, 36)
const SHELF_ROW_HEIGHT := 52.0
## The row's content inset inside its Tile.
const SHELF_INSET := 8.0
const BAR_HEIGHT := 6.0

static var _thumb_material: ShaderMaterial


## A CardThumb well of `well_size` (x 0: fills its width) holding a picture and, when there is
## none, the initial of `title` in `initial_variation`. The well clips the picture to its shape.
static func thumb_well(
	well_size: Vector2, texture: Texture2D, title: String, initial_variation: StringName
) -> Panel:
	var well := Panel.new()
	well.name = "Well"
	well.theme_type_variation = &"CardThumb"
	well.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.custom_minimum_size = well_size
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.material = thumb_material()
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(picture)
	var letter := Label.new()
	letter.name = "Letter"
	letter.theme_type_variation = initial_variation
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(letter)
	set_well(well, texture, title)
	return well


## Show `texture` in a well, or the initial of `title` when there is none.
static func set_well(well: Panel, texture: Texture2D, title: String) -> void:
	(well.get_node("Picture") as TextureRect).texture = texture
	var letter := well.get_node("Letter") as Label
	letter.text = LevelCard.initial_of(title)
	letter.visible = texture == null


## The level card's shader that keys an older thumbnail's black void out to the well's wash.
static func thumb_material() -> ShaderMaterial:
	if _thumb_material == null:
		_thumb_material = ShaderMaterial.new()
		_thumb_material.shader = LevelCard.THUMB_SHADER
	return _thumb_material


## One player: `player` is a RoomModel.players() entry, `selected` the selected map's key ("":
## no bar). Your own row carries Choose avatar, which calls `choose_avatar`.
static func player_row(player: Dictionary, selected: String, choose_avatar: Callable) -> Control:
	var row := HBoxContainer.new()
	row.name = "Player_%s" % str(player.id).validate_node_name()
	row.theme_type_variation = &"BoxContainerSpaced"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait := thumb_well(PORTRAIT, null, str(player.name), &"Heading")
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(line)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = str(player.name)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)
	if player.you:
		line.add_child(_caption("You", &"Caption", false))
	if player.gm:
		var chip := PanelContainer.new()
		chip.name = "GmBadge"
		chip.theme_type_variation = &"KeyChip"
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(_caption("GM", &"CaptionState", false))
		line.add_child(chip)
	if selected != "":
		info.add_child(download_state(selected in player.holds))

	if player.you:
		var choose := Button.new()
		choose.name = "ChooseAvatar"
		choose.text = "Choose avatar"
		choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		choose.pressed.connect(choose_avatar)
		row.add_child(choose)
	return row


## The selected map's download state for one player: a full bar when the player has it, else
## "Gets it at the table" (an empty bar's inset track does not read on glass). There is no
## partial fill yet: a player who lacks the map downloads it once it is set out.
static func download_state(held: bool) -> Control:
	if not held:
		var later := _caption("Gets it at the table", &"Caption")
		later.name = "Download"
		return later
	var bar := ProgressBar.new()
	bar.name = "Download"
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = 1.0
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar.theme_type_variation = &"ProgressSuccess"
	bar.tooltip_text = "Has this map"
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	return bar


## One shelf map: `entry` is a RoomModel.shelf() entry. A toggle Tile when `selectable`.
static func shelf_row(
	entry: Dictionary, texture: Texture2D, caption: String, selectable: bool
) -> Button:
	var row := Button.new()
	row.name = "Map_%s" % str(entry.key).validate_node_name()
	row.theme_type_variation = &"Tile"
	row.toggle_mode = true
	row.custom_minimum_size = Vector2(0, SHELF_ROW_HEIGHT)
	row.tooltip_text = str(entry.name)
	row.focus_mode = Control.FOCUS_ALL if selectable else Control.FOCUS_NONE
	row.mouse_filter = Control.MOUSE_FILTER_STOP if selectable else Control.MOUSE_FILTER_IGNORE
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.theme_type_variation = &"BoxContainerSpaced"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = SHELF_INSET
	inner.offset_right = -SHELF_INSET
	row.add_child(inner)
	var well := thumb_well(SHELF_THUMB, texture, str(entry.name), &"Heading")
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(well)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text)
	var name_label := _caption(str(entry.name), &"Body")
	name_label.name = "Name"
	text.add_child(name_label)
	var caption_label := _caption(caption, &"Caption")
	caption_label.name = "Caption"
	caption_label.visible = caption != ""
	text.add_child(caption_label)
	return row


## Show a shelf row selected (the Tile's selected fill, its text on that fill) or not.
static func show_shelf_selected(row: Button, on: bool) -> void:
	row.set_pressed_no_signal(on)
	var text := row.get_node("Inner/Text")
	(text.get_node("Name") as Label).theme_type_variation = &"BodyOnSelected" if on else &"Body"
	(text.get_node("Caption") as Label).theme_type_variation = (
		&"CaptionOnSelected" if on else &"Caption"
	)


## A label; `trim` ellipsizes it, for text that fills a column (a trimmed label asks for no
## width, so a short tag such as "GM" must not trim or it collapses to nothing).
static func _caption(text: String, variation: StringName, trim := true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if trim:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
