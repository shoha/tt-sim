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


## The theme leaf the map tools wear (SURFACE_PAPER).
static func surface_theme() -> Theme:
	return ThemeColors.paper_theme() if SURFACE_PAPER else ThemeColors.glass_theme()


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
