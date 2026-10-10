class_name AvatarCard
extends Button

## A saved avatar as a card (the title screen's roster, the Add Token browser's Avatar
## tab): its rendered figure (AvatarThumbnails) on the builder's warm backdrop, with its
## name underneath. A press is the host's main action (edit on the roster, place in game),
## and with `draggable` a held card dragged away starts the game's drag-place (drag_started);
## with `with_menu` the overflow button in the picture's corner offers Edit, Duplicate and
## Delete. setup_make() turns the card into the "Make an avatar" card: a plus and a line
## inviting a new figure, on the same backdrop.

signal action_requested(entry: Dictionary, action: StringName)
## With `draggable`, the card was held and moved DRAG_THRESHOLD_PX: the host starts a
## drag-place, which takes the release, so the press never lands as a click.
signal drag_started

enum { ACTION_EDIT, ACTION_DUPLICATE, ACTION_DELETE }

## How far a held card moves before it counts as a drag (the pack tabs' threshold).
const DRAG_THRESHOLD_PX := 8.0

## The picture's height as a share of the card's width (the thumbnail is 3:4).
const PICTURE_ASPECT := 4.0 / 3.0
const INSET := 4.0
const HOVER_SCALE := Vector2(1.04, 1.04)

## The library entry shown (AvatarLibrary), empty for the "Make an avatar" card.
var entry: Dictionary = {}
var with_menu := false
## A held card dragged past DRAG_THRESHOLD_PX emits drag_started.
var draggable := false

var _press_pos := Vector2.INF
var _column: VBoxContainer
var _slot: Control
var _thumb: TextureRect
var _mark: TextureRect
var _name: Label
var _caption: Label
var _menu_button: IconButton
var _menu: PopupMenu
var _tween: Tween


func _init() -> void:
	theme_type_variation = &"Card"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column.offset_left = INSET
	_column.offset_top = INSET
	_column.offset_right = -INSET
	_column.offset_bottom = -INSET
	_column.add_theme_constant_override("separation", 4)
	_column.minimum_size_changed.connect(_fit_height)
	add_child(_column)

	_slot = Control.new()
	_slot.name = "Picture"
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot.clip_contents = true
	_slot.resized.connect(_on_slot_resized)
	_column.add_child(_slot)
	_slot.add_child(AvatarBuilderPreview.backdrop())
	_thumb = TextureRect.new()
	_thumb.name = "Thumb"
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot.add_child(_thumb)
	_mark = TextureRect.new()
	_mark.name = "Mark"
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.custom_minimum_size = Vector2(48, 48)
	_mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mark.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_mark.visible = false
	_slot.add_child(_mark)

	_name = Label.new()
	_name.name = "Name"
	_name.theme_type_variation = &"Body"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_name)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.theme_type_variation = &"Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	_column.add_child(_caption)

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_gui_input)


## Shows saved avatar `info` (an AvatarLibrary entry); `menu` adds the overflow actions.
func setup(info: Dictionary, menu: bool = false) -> void:
	entry = info
	with_menu = menu
	_name.text = String(info.get("name", AvatarLibrary.DEFAULT_NAME))
	tooltip_text = _name.text
	var recipe: Dictionary = info.get("recipe", {})
	_thumb.texture = AvatarThumbnails.request(recipe, _on_thumbnail)
	if menu and _menu_button == null:
		_add_menu()


## Makes this the "Make an avatar" card, with `caption` under its title.
func setup_make(caption: String = "") -> void:
	entry = {}
	_name.text = "Make an avatar"
	tooltip_text = "Pick a pose, a face and colours; the figure follows every pick"
	_mark.texture = IconButton.load_icon("plus")
	_mark.visible = true
	_thumb.texture = null
	_caption.text = caption
	_caption.visible = not caption.is_empty()


## The card's picture (null until it is drawn).
func thumbnail() -> Texture2D:
	return _thumb.texture


func _on_thumbnail(texture: Texture2D) -> void:
	if is_instance_valid(self) and texture != null:
		_thumb.texture = texture


func _add_menu() -> void:
	_menu_button = IconButton.new()
	_menu_button.name = "Menu"
	_menu_button.icon_name = "dots-vertical"
	_menu_button.tooltip_text = "More"
	_menu_button.custom_minimum_size = Vector2(28, 28)
	_menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu_button.position = Vector2(-32, 4)
	_menu_button.pressed.connect(_on_menu_pressed)
	_slot.add_child(_menu_button)
	_menu = PopupMenu.new()
	_menu.name = "Actions"
	_menu.add_item("Edit", ACTION_EDIT)
	_menu.add_item("Duplicate", ACTION_DUPLICATE)
	_menu.add_item("Delete", ACTION_DELETE)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)


func _on_menu_pressed() -> void:
	_menu.position = Vector2i(_menu_button.get_screen_position()) + Vector2i(0, 28)
	_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	match id:
		ACTION_EDIT:
			action_requested.emit(entry, &"edit")
		ACTION_DUPLICATE:
			action_requested.emit(entry, &"duplicate")
		ACTION_DELETE:
			action_requested.emit(entry, &"delete")


## The picture keeps its 3:4 shape at whatever width the host gives the card.
func _on_slot_resized() -> void:
	var height := roundf(_slot.size.x * PICTURE_ASPECT)
	if not is_equal_approx(_slot.custom_minimum_size.y, height):
		_slot.custom_minimum_size = Vector2(0, height)
		_fit_height()
	_thumb.pivot_offset = _thumb.size * 0.5


## Button's own minimum size ignores its children, so the card's height follows its column
## through custom_minimum_size.y (as LevelCard does); .x is the host's column width.
func _fit_height() -> void:
	if _column == null:
		return
	custom_minimum_size.y = _column.get_combined_minimum_size().y + INSET * 2.0


## Tracks a left press so a held card dragged far enough becomes drag_started.
func _on_gui_input(event: InputEvent) -> void:
	if not draggable:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_press_pos = button.position if button.pressed else Vector2.INF
		return
	var motion := event as InputEventMouseMotion
	if motion and _press_pos != Vector2.INF:
		if motion.position.distance_to(_press_pos) >= DRAG_THRESHOLD_PX:
			_press_pos = Vector2.INF
			drag_started.emit()


func _on_hover(entered: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var duration := Constants.ANIM_HOVER_SOFT_IN if entered else Constants.ANIM_HOVER_SOFT_OUT
	_tween.tween_property(_thumb, "scale", HOVER_SCALE if entered else Vector2.ONE, duration)
