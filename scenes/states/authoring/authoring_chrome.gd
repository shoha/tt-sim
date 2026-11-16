class_name AuthoringChrome
extends RefCounted

## What the map tools' frame is made of, apart from the panes: the material of the drawer and
## rail (paper or glass), the actions under the rail and their words, and the keys the frame
## answers. AuthoringPanel builds the frame from these and AuthoringController answers its keys;
## they are here so the two hubs stay short and the words are in one place (docs/UI_SYSTEMS.md
## "Map building chrome").

## The material of the map tools' drawer and rail. Paper: building a map stops play, and "if it
## stops play it is paper" (UI_TASTE.md C8, the 2026-11-15 ui-authoring entry). Glass was the
## material until then and is kept as the one-line alternative: set this false and the whole
## drawer, its rail and every pane follow (the styles are theme variations, not code).
const SURFACE_PAPER := true

## The drawer's panel is a card as tall as its pane (DrawerContainer.fit_height), so a short pane
## (Sculpt, Water) leaves the board visible below it instead of a pale slab down the whole edge.
## Set false for the full-height panel.
const FIT_HEIGHT := true

## The rail's items are 46 px squares (43 real px in a 1280x720 window, the target size the critic
## asked for), the tools in one column and the actions in a second beside it, so the rail's 11
## tools and its runs still fit 720p. RAIL_GROUP_GAP is the extra step between runs: with the
## rail's own 4 px either side it reads as 20 px.
const RAIL_ITEM_SIZE := 46.0
const RAIL_GROUP_GAP := 12.0

## The card's opacity while a brush is down on the board (it steps back, the stroke shows).
const STROKE_DIM := 0.3

## The word under Save while there is anything to save (with the dot): the cue says it in text.
const UNSAVED_WORD := "Unsaved"

const ACTION_UNDO := &"undo"
const ACTION_REDO := &"redo"
const ACTION_SAVE := &"save_map"
const ACTION_LEAVE := &"leave_authoring"

## The actions under the rail, apart from the tools: each one's words say its key.
const FOOTER_ITEMS: Array[Dictionary] = [
	{"id": ACTION_UNDO, "icon": "arrow-back-up", "tooltip": "Undo (Ctrl+Z)"},
	{"id": ACTION_REDO, "icon": "arrow-forward-up", "tooltip": "Redo (Ctrl+Y)"},
	{"id": ACTION_SAVE, "icon": "device-floppy", "tooltip": "Save map (Ctrl+S)"},
	{"id": ACTION_LEAVE, "icon": "door-exit", "tooltip": "Leave map building (Esc)"},
]


## Place tiles' icons by words in the species key (the first match wins), so an oak, a birch and a
## pine are three pictures; a kind's icon (AuthoringPanel.PLACE_ICONS) is the fallback.
const PLACE_KEY_ICONS: Array[Dictionary] = [
	{"words": ["pine", "spruce", "fir", "larch", "cedar", "hemlock"], "icon": "christmas-tree"},
	{"words": ["bush", "shrub", "sapling", "thicket", "fern", "bramble"], "icon": "plant"},
	{"words": ["boulder", "rock", "stone", "outcrop", "slab", "scree"], "icon": "stone"},
	{"words": ["birch", "aspen", "willow", "poplar", "maple", "alder"], "icon": "leaf"},
	{"words": ["cactus", "agave"], "icon": "cactus"},
]


## The icon of a Place tile for species `key` (e.g. "dwarf_pine"); `fallback` when no word fits.
static func place_icon(key: String, fallback: String) -> String:
	var lowered := key.to_lower()
	for entry in PLACE_KEY_ICONS:
		for word: String in entry["words"]:
			if lowered.contains(word):
				return String(entry["icon"])
	return fallback


## A wrapped caption line saying a pane's gestures (the pane's lead: two lines at most).
static func help_label(label_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## The rest of a pane's help behind a "More" foldout, closed: the lead above it says enough to
## start.
static func more_foldout(foldout_name: String, text: String) -> Foldout:
	var foldout := Foldout.new()
	foldout.name = foldout_name
	foldout.title = "More"
	foldout.add_child(help_label(foldout_name + "Text", text))
	return foldout


## The theme leaf the map tools wear (SURFACE_PAPER).
static func surface_theme() -> Theme:
	return ThemeColors.paper_theme() if SURFACE_PAPER else ThemeColors.glass_theme()


## The height the drawer's panel wants for the pane on show: what its margin needs (the name
## field, the pane's head, the stack) with the stack's share swapped for the pane's own height,
## because the pane scrolls inside the stack and the stack asks for none. 0 with no pane.
static func panel_height(margin: Control, stack: Control, pane: Control) -> float:
	if pane == null:
		return 0.0
	var rest := margin.get_combined_minimum_size().y - stack.get_combined_minimum_size().y
	return rest + pane.get_combined_minimum_size().y


## The tooltip of an Undo or Redo item: its verb, the edit it acts on and its key when it can act
## ("Undo Raise (Ctrl+Z)"), else that there is nothing to do ("Nothing to undo").
static func history_tip(verb: String, key: String, can_act: bool, label: String) -> String:
	if not can_act:
		return "Nothing to %s" % verb.to_lower()
	var what := "" if label == "" else " %s" % label
	return "%s%s (%s)" % [verb, what, key]


## The Save item's tooltip: whether there is anything to save, and its key.
static func save_tip(dirty: bool) -> String:
	if dirty:
		return "Save map: unsaved changes (Ctrl+S)"
	return "Save map: all changes saved (Ctrl+S)"


## True for a press of Ctrl+S (the Save item's key, as the biome designer's).
static func is_save_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_S
