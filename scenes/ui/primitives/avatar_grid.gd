class_name AvatarGrid
extends ScrollContainer

## The player's saved avatars (AvatarLibrary) as a grid of AvatarCards, newest first, with
## an optional "Make an avatar" card leading it. The title screen's roster uses it with the
## overflow menu on every card; the Add Token browser's Avatar tab without, where a press
## places the avatar and, with `draggable`, a drag carries it onto the map. Cards are an
## equal share of the width (`columns` per line). The grid refreshes itself when the library
## changes (AvatarLibrary.events().changed).

signal avatar_pressed(entry: Dictionary)
## A card held and dragged (only with `draggable`); `icon` is its picture.
signal avatar_drag_started(entry: Dictionary, icon: Texture2D)
signal make_pressed
signal action_requested(entry: Dictionary, action: StringName)
## The cards' layout changed size (content_height() may have changed).
signal content_resized

const GAP := 10
const SCROLL_RESERVE := 14.0

@export var columns := 4
## Cards carry Edit, Duplicate and Delete.
@export var with_menu := false
## A "Make an avatar" card leads the grid.
@export var make_card := true
## Avatar cards can be dragged out (AvatarCard.drag_started), to drag-place in game.
@export var draggable := false
## The line under the make card's title.
var make_caption := ""

var _flow: HFlowContainer
var _cards: Array[AvatarCard] = []


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_flow = HFlowContainer.new()
	_flow.name = "Flow"
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", GAP)
	_flow.add_theme_constant_override("v_separation", GAP)
	add_child(_flow)
	_flow.minimum_size_changed.connect(content_resized.emit)
	resized.connect(_fit_columns)


func _ready() -> void:
	AvatarLibrary.events().changed.connect(refresh)


func _exit_tree() -> void:
	if AvatarLibrary.events().changed.is_connected(refresh):
		AvatarLibrary.events().changed.disconnect(refresh)


## Rebuilds the cards from the library.
func refresh() -> void:
	for child in _flow.get_children():
		_flow.remove_child(child)
		child.queue_free()
	_cards.clear()
	if make_card:
		var make := AvatarCard.new()
		make.name = "Make"
		make.setup_make(make_caption)
		make.pressed.connect(make_pressed.emit)
		_flow.add_child(make)
		_cards.append(make)
	for info in AvatarLibrary.list():
		var card := AvatarCard.new()
		card.name = "Avatar_" + String(info.id)
		card.setup(info, with_menu)
		card.pressed.connect(avatar_pressed.emit.bind(info))
		if draggable:
			card.draggable = true
			card.drag_started.connect(
				func() -> void: avatar_drag_started.emit(info, card.thumbnail())
			)
		card.action_requested.connect(action_requested.emit)
		_flow.add_child(card)
		_cards.append(card)
	_fit_columns()


## Saved avatars shown (the make card not counted).
func avatar_count() -> int:
	return _cards.size() - (1 if make_card else 0)


## The card for avatar `id`, or null.
func card_for(id: String) -> AvatarCard:
	for card in _cards:
		if String(card.entry.get("id", "")) == id:
			return card
	return null


## The height the grid needs to show every card without scrolling, at its current width.
func content_height() -> float:
	var lines := ceili(float(_cards.size()) / float(maxi(columns, 1)))
	var card_height := 0.0
	for card in _cards:
		card_height = maxf(card_height, card.get_combined_minimum_size().y)
	return lines * card_height + GAP * float(maxi(lines - 1, 0))


## Cards an equal share of the width. The scroll bar's width is always kept free, so a
## scroll bar appearing never re-wraps the cards (which would loop).
func _fit_columns() -> void:
	var width := size.x - SCROLL_RESERVE
	if width <= 0.0:
		return
	var each := floorf((width - GAP * float(columns - 1)) / float(maxi(columns, 1)))
	for card in _cards:
		card.custom_minimum_size.x = each
