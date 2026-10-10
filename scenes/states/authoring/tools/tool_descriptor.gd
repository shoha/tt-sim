class_name ToolDescriptor
extends RefCounted

## One map tool's declaration. ToolRegistry lists one per tool, and the hubs read it instead
## of keeping their own list of tools: AuthoringPanel builds the tool's rail item and pane,
## AuthoringController picks it, refreshes it and maps the brush's mode back to it, and the
## F1 help overlay lists its rows. A tool is one subclass under
## scenes/states/authoring/tools/ that sets the fields in _init() and overrides the hooks it
## needs.
##
## Declared: the id (the rail item and the pane share it), the label (rail tooltip and pane
## title), a one-line summary (pane caption and the tool's help row), the rail icon, an
## optional shortcut (a bare key; none of the seven tools of 2026-10 has one), the BrushMode
## class its gestures run in, its own help rows, and the contexts it exists in (authoring,
## play, or both).
##
## Gestures. `brush_mode` names a BrushMode subclass (WaterBrush, SculptBrush, ...): its
## press, frames, release, cancel, size step and cursor. BrushTool makes one per tool
## (BrushTool.mode_for) and dispatches to it, so a tool with gestures of its own adds its
## mode class and edits no brush code. A subclass's static of(brush) returns its mode, typed,
## for the controller and the panes that set what it paints.
##
## The hooks are the tool's half of the controller's tool wiring. They read the controller's
## public state and call its public methods only. can_select() refuses a pick the open map
## cannot take, armed() leaves the brush put down while it has nothing to work with, and
## prepare() warms what the first stroke would otherwise wait on. refresh() shows on the rail
## whether the open map can take the tool, after the map opens and after every edit, undo and
## redo. works_on() is the map half of can_select(), asked of an editor alone, so the GM's
## Events pane in play (PlayEvents, over the table's LiveEdits editor) asks it too.
##
## Panes. The seven tools that predate the registry have panes AuthoringPanel builds itself:
## five inline, plus WaterToolPane and BridgeToolPane, whose signals it relays to the
## controller. A tool added since returns its own pane class from build_pane() and wires its
## signals to the controller and the brush in connect_pane().

## Bits of `contexts`: where a tool exists.
const AUTHORING := 1
const PLAY := 2

## The rail item and pane id.
var id: StringName = &""
## The rail tooltip and the pane title.
var label: String = ""
## What the tool is for, in one line: the pane caption and the tool's F1 help row.
var summary: String = ""
## The rail icon (an icon name under assets/icons/ui/).
var icon: String = ""
## A bare key that picks the tool (no modifiers), or KEY_NONE.
var shortcut: Key = KEY_NONE
## Where the tool exists: AUTHORING, PLAY, or both.
var contexts: int = AUTHORING
## The BrushMode subclass its gestures run in, or null for a tool without brush gestures.
var brush_mode: GDScript = null
## Its own F1 help rows after its name row, each [keys, what they do]. The gestures every
## brush shares (size, cancel, undo) are the help overlay's own rows.
var help: Array = []
## The rail tooltip while the open map cannot take the tool ("" for a tool that always can).
var unavailable_tooltip: String = ""


## Whether the tool exists in `context` (AUTHORING or PLAY).
func exists_in(context: int) -> bool:
	return (contexts & context) != 0


## The shortcut as the help overlay shows it ("B"), or "" for none.
func shortcut_label() -> String:
	return OS.get_keycode_string(shortcut) if shortcut != KEY_NONE else ""


## The rail tooltip while the tool can be picked: its label, with the shortcut when it has
## one ("Biome (B)").
func rail_tooltip() -> String:
	var key := shortcut_label()
	return label if key == "" else "%s (%s)" % [label, key]


## The tool's entry in DrawerContainer.rail_items.
func rail_item() -> Dictionary:
	return {"id": id, "icon": icon, "tooltip": rail_tooltip()}


## The tool's F1 help rows: its name row (the rail tooltip and the summary), then `help`.
func help_rows() -> Array:
	var rows: Array = [[rail_tooltip(), summary.trim_suffix(".")]]
	rows.append_array(help)
	return rows


## True for a press of the shortcut key with no modifier held (not an echo).
func matches_shortcut(event: InputEvent) -> bool:
	if shortcut == KEY_NONE or not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.shift_pressed or key.alt_pressed or key.meta_pressed:
		return false
	return key.keycode == shortcut


## Whether a pick may switch the brush to this tool on the open map. Default: always.
func can_select(_controller: AuthoringController) -> bool:
	return true


## Whether the tool can work on the map `editor` edits (its ground the document's, water to
## work on): can_select()'s question asked of an editor alone, in authoring and in play.
## Default: always.
func works_on(_editor: AuthoringEditor) -> bool:
	return true


## Whether the brush has what it needs once switched to this tool; false switches it but
## leaves it put down. Default: always.
func armed(_controller: AuthoringController) -> bool:
	return true


## Runs as the tool is picked, after the brush switched to it and before it activates.
func prepare(_controller: AuthoringController) -> void:
	pass


## Shows on the rail whether the open map can take the tool. Default: enabled while
## can_select() holds, else disabled with unavailable_tooltip.
func refresh(controller: AuthoringController) -> void:
	controller.panel.set_tool_available(id, can_select(controller))


## The tool's pane, or null for a pane AuthoringPanel builds itself (the seven tools that
## predate the registry).
func build_pane(_panel: AuthoringPanel) -> Control:
	return null


## Wires a pane build_pane() made to the controller and its brush (the panel's own panes
## reach the controller through AuthoringPanel's signals instead).
func connect_pane(_controller: AuthoringController, _pane: Control) -> void:
	pass
