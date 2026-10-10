class_name RoomRows
extends RefCounted

## The rows RoomPanel lists, built fresh from RoomModel data on every refresh.
##
## A player row is a portrait well with the name's initial in Inter semibold, the name on a
## line of its own (the full width the row has), and a caption line under it in one fixed
## order in every view: the GM chip, "You", then the selected map's download state as an icon
## and a word (download_state()). Your own row ends in Choose avatar, a compact framed button
## with the shirt icon and its name in the tooltip.
##
## A shelf map is a plain list row like a player (the ListRow button: clear at rest, the
## hover wash, the selected fill when picked): its picture, name and a caption. Every map
## picture sits in a CardThumb well, and a map with no thumbnail shows its painted placeholder
## (MapPlaceholder), never a flat box.

const PORTRAIT := Vector2(40, 40)
const SHELF_THUMB := Vector2(64, 36)
const SHELF_ROW_HEIGHT := 52.0
## The row's content inset inside its button.
const SHELF_INSET := 8.0
## The download state's icon, beside its caption word.
const STATE_ICON := Vector2(16, 16)
const HAS_IT := "Has it"
const GETS_IT := "Gets it at the table"

static var _thumb_material: ShaderMaterial


## A CardThumb well of `well_size` (x 0: fills its width) holding a map's thumbnail, or its
## painted placeholder when `texture` is null. `key` and `mood` paint the placeholder
## (MapPlaceholder.paint()). The well clips the picture to its shape.
static func map_well(well_size: Vector2, texture: Texture2D, key: String, mood: String) -> Panel:
	var well := _well(well_size)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.material = thumb_material()
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(picture)
	var placeholder := MapPlaceholder.new()
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(placeholder)
	set_map_well(well, texture, key, mood)
	return well


## Show `texture` in a map well, or the placeholder painted for `key` in `mood`.
static func set_map_well(well: Panel, texture: Texture2D, key: String, mood: String) -> void:
	(well.get_node("Picture") as TextureRect).texture = texture
	var placeholder := well.get_node("Placeholder") as MapPlaceholder
	placeholder.visible = texture == null
	if texture == null:
		placeholder.paint(key, mood)


## A player's portrait: a CardThumb well with the initial of `player_name` in Inter semibold
## (T3: Fraunces never in rows).
static func portrait(player_name: String) -> Panel:
	var well := _well(PORTRAIT)
	var letter := Label.new()
	letter.name = "Letter"
	letter.theme_type_variation = &"H3"
	letter.text = LevelCard.initial_of(player_name)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(letter)
	return well


## The level card's shader that keys an older thumbnail's black void out to the well's wash.
static func thumb_material() -> ShaderMaterial:
	if _thumb_material == null:
		_thumb_material = ShaderMaterial.new()
		_thumb_material.shader = LevelCard.THUMB_SHADER
	return _thumb_material


## One player: `player` is a RoomModel.players() entry, `selected` the selected map's key (""
## for none: no download state). Your own row carries Choose avatar, which calls
## `choose_avatar`.
static func player_row(player: Dictionary, selected: String, choose_avatar: Callable) -> Control:
	var row := HBoxContainer.new()
	row.name = "Player_%s" % str(player.id).validate_node_name()
	row.theme_type_variation = &"BoxContainerSpaced"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = PORTRAIT.y
	var face := portrait(str(player.name))
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(face)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_label := _caption(str(player.name), &"Body")
	name_label.name = "Name"
	name_label.tooltip_text = str(player.name)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(name_label)
	var line := HBoxContainer.new()
	line.name = "CaptionLine"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(line)
	if player.gm:
		var chip := PanelContainer.new()
		chip.name = "GmBadge"
		chip.theme_type_variation = &"KeyChip"
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(_caption("GM", &"CaptionState", false))
		line.add_child(chip)
	if player.you:
		var you := _caption("You", &"Caption", false)
		you.name = "You"
		line.add_child(you)
	if selected != "":
		line.add_child(download_state(selected in player.holds))
	line.visible = line.get_child_count() > 0

	if player.you:
		row.add_child(_choose_avatar_button(choose_avatar))
	return row


## The selected map's download state for one player, an icon and a word (C7: never colour
## alone): the lake check and "Has it", or the download arrow and "Gets it at the table".
## There is no partial progress yet: a player who lacks the map downloads it once it is set
## out.
static func download_state(held: bool) -> Control:
	var box := HBoxContainer.new()
	box.name = "Download"
	box.theme_type_variation = &"BoxContainerTight"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = IconButton.load_icon("circle-check" if held else "download")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = STATE_ICON
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A white icon tinted by hand: lake (state) for has it, the soft text role for not yet,
	# read once the icon is under its paper or glass parent.
	var role := ThemeColors.STATE if held else ThemeColors.TEXT_SOFT
	icon.theme_changed.connect(func() -> void: icon.self_modulate = ThemeColors.of(icon, role))
	box.add_child(icon)
	var word := _caption(HAS_IT if held else GETS_IT, &"Caption")
	word.name = "Word"
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(word)
	return box


## One shelf map: `entry` is a RoomModel.shelf() entry, `mood` its environment preset (for the
## placeholder). A toggle row; `selectable` false makes it read-only.
static func shelf_row(
	entry: Dictionary, texture: Texture2D, mood: String, caption: String, selectable: bool
) -> Button:
	var row := Button.new()
	row.name = "Map_%s" % str(entry.key).validate_node_name()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.custom_minimum_size = Vector2(0, SHELF_ROW_HEIGHT)
	row.tooltip_text = str(entry.name)
	row.focus_mode = Control.FOCUS_ALL if selectable else Control.FOCUS_NONE
	row.mouse_filter = Control.MOUSE_FILTER_STOP if selectable else Control.MOUSE_FILTER_IGNORE
	if selectable:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.theme_type_variation = &"BoxContainerSpaced"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = SHELF_INSET
	inner.offset_right = -SHELF_INSET
	row.add_child(inner)
	var key := str(entry.folder) if str(entry.folder) != "" else str(entry.name)
	var well := map_well(SHELF_THUMB, texture, key, mood)
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


## Show a shelf row selected (the row's selected fill, its text on that fill) or not.
static func show_shelf_selected(row: Button, on: bool) -> void:
	row.set_pressed_no_signal(on)
	var text := row.get_node("Inner/Text")
	(text.get_node("Name") as Label).theme_type_variation = &"BodyOnSelected" if on else &"Body"
	(text.get_node("Caption") as Label).theme_type_variation = (
		&"CaptionOnSelected" if on else &"Caption"
	)


static func _well(well_size: Vector2) -> Panel:
	var well := Panel.new()
	well.name = "Well"
	well.theme_type_variation = &"CardThumb"
	well.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.custom_minimum_size = well_size
	return well


## Your own row's Choose avatar: compact, framed at rest so it reads as a button, named in its
## tooltip and for screen readers (W7).
static func _choose_avatar_button(choose_avatar: Callable) -> Button:
	var choose := Button.new()
	choose.name = "ChooseAvatar"
	choose.icon = IconButton.load_icon("shirt")
	choose.tooltip_text = "Choose avatar"
	choose.accessibility_name = "Choose avatar"
	choose.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choose.custom_minimum_size = PORTRAIT
	choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	choose.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	choose.pressed.connect(choose_avatar)
	return choose


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
