class_name PlayEvents
extends Node

## The GM's live brushes during play: the controller of the Events pane (EventsPane, in the
## Visuals drawer). GameplayMenuController makes one on every peer; only the GM's side with a
## table that takes live edits can arm it (refusal()).
##
## The brush is GameMap's own BrushTool (GameMap.setup_brush_tool: exclusive with the measure
## tool and the sun gizmo, no token drag and no right-button pan while it is out), its
## `editor` the table's play-side editor (LevelPlayController.live_edits), so every stroke
## records into the live history and goes to every peer as an op (LiveEdits). The modes are
## the authoring ones (BrushMode never reaches AuthoringController), set from the pane as
## AuthoringController sets them from its panes.
##
## Picking a brush's tile arms it on the board; its tile again, Esc or a right click puts it
## away (the pane keeps showing its controls). A brush with nothing to work with yet (Biome
## before a biome is picked) is picked but not armed. While it is out its keys lead the hint
## bar (InputHints tool layer), the last of them naming it (Esc, Put away Sculpt), Ctrl+Z and
## Ctrl+Y undo and redo the GM's live edits (GameMap leaves Ctrl+Z to it), and an edit that
## changes a lot at once (is_large) offers Undo in a toast (UI_TASTE I4).
##
## The board is the GM's while they work (UI_TASTE G11): the drawer stays open while a brush
## and its settings are picked, and the first press on the board sends it aside
## (stroke_started; GameplayMenuController closes it, keeping any look changes), so no ring
## works on ground under the glass. The brush stays out, named in the hint bar, and the
## Events rail item stays tinted (armed_changed); the item opens the pane again to change it.
## The canopy over the ring opens only while a press is held (BrushTool.fade_held_only), so
## the GM sees the result whole once they let go. A click that stays on its spot gets at least
## PLAY_CLICK_SECONDS of exposure (BrushTool.min_stroke_seconds), so it shows.
##
## Presets (EventPresets: Drop bridge, Topple trees) arm on the same brush as the brushes do.
## Their modes fire a TerrainEvent, which the table's TerrainEvents plays on every board and
## ends in an ordinary live edit; that entry, labelled for the event, always offers Undo in a
## toast ("The bridge fell for everyone at the table"), and its undo restores the map at once.
## A preset stays armed after it fires: the drawer steps aside for the spectacle and the hint
## bar keeps its keys, so a GM fells stand after stand without reopening the pane; Drop bridge
## puts itself away once no bridge is left to drop. A preset put away is forgotten as well
## (picked goes back to &""), so its gesture line and Advanced leave the pane with it.

## The brush was armed with tool `tool_id`, or put away (&"").
signal armed_changed(tool_id: StringName)
## A press on the board started a stroke of the armed brush.
signal stroke_started

## The F1 help row for the pane (HelpOverlay's Tools section).
const HELP_KEYS := "Events (GM)"
const HELP_TEXT := (
	"Visuals drawer: change the map for everyone with the map-building brushes; Ctrl+Z undoes"
)
## A brush stroke whose history entry holds at least this much (its compressed diff, which
## grows with the ground it changed) offers Undo in a toast; a river, pond or crossing edit
## always does (a whole feature at once). Measured: one mound of a 4 m Sculpt raise held
## 0.9 s holds 3.8 KB, so a single mound gets none and a wide sweep does.
const LARGE_EDIT_BYTES := 12 * 1024
## History methods of whole-feature edits (WaterEditor.apply_edit, CrossingEditor.apply_list).
const WHOLE_FEATURE_METHODS: Array[StringName] = [&"apply_edit", &"apply_list"]
const NOT_GM := "Only the GM can change the map during play."
const NOT_HOST := "Only the host can change the map during play."
const NOT_READY := "The map is still being set out; its brushes are ready in a moment."
## A large edit's toast: its label in the past tense (done_phrase), "Cleared for everyone at
## the table".
const UNDO_TOAST := "%s for everyone at the table"
const NEWER_EDITS := "Newer changes stand on that one: undo them first with Ctrl+Z."
## The size key every brush shows in the same slot, before Undo (BrushTool: [ and ] step the
## size; Shift+scroll does too, but Shift is Sculpt's Smooth).
const SIZE_KEY := "[ ]"
## Past tenses an edit label's first word does not take by adding "d" or "ed".
const IRREGULAR_PAST := {"Thin": "Thinned", "Cut": "Cut", "Lay": "Laid"}
## A preset's toast once its change is made (the history entry's "preset" kind).
const PRESET_DONE := {
	TerrainEvent.Kind.BRIDGE_COLLAPSE: "The bridge fell for everyone at the table",
	TerrainEvent.Kind.FOREST_FALL: "The trees fell for everyone at the table",
}
const NO_BRIDGE := EventPresets.NO_BRIDGE_TOOLTIP
## In play a click (a stroke that never left its spot) gets at least this much exposure
## (BrushTool.min_stroke_seconds), so a GM's quick click shows on the board: a Sculpt raise of
## about 0.2 m at the default 4 m size where authoring's CLICK_SECONDS left a few millimetres
## (measured with real input in the 2a review), a firm patch of thinning, a copse of a biome.
const PLAY_CLICK_SECONDS := 0.6

## The pane this controls (set by setup()).
var pane: EventsPane = null
## The tool whose controls the pane shows (&"" for none), and the one armed on the board.
var picked: StringName = &""
var armed: StringName = &""

var _lpc: LevelPlayController = null
var _brush: BrushTool = null
## The live edits the brush is wired to (their history's recorded signal is connected).
var _edits: LiveEdits = null
var _biome_id: String = ""


## The reason this peer cannot change the map now, or "" when it can: GM access, a map with a
## document (LiveEdits.refusal), its live edits started, and the GM's side of them. Pure.
static func refusal_for(gm_access: bool, doc: MapDocument, edits: LiveEdits) -> String:
	if not gm_access:
		return NOT_GM
	var why := LiveEdits.refusal(doc)
	if why != "":
		return why
	if edits == null:
		return NOT_READY
	return "" if edits.sends else NOT_HOST


## Whether history `entry` changed a lot at once (see LARGE_EDIT_BYTES). Pure.
static func is_large(entry: Dictionary) -> bool:
	var redo: Callable = entry.get("redo", Callable())
	if redo.is_valid() and redo.get_method() in WHOLE_FEATURE_METHODS:
		return true
	return int(entry.get("bytes", 0)) >= LARGE_EDIT_BYTES


## The hint bar's keys while `tool_id` (a brush or a preset) is out: its gestures, then in the
## same three slots for every brush its size key (SIZE_KEY; Drop bridge has no size), Undo,
## and Esc naming what it puts away (at most five, so with Help beside them the row keeps one
## line at 720p with the drawer open). A preset's first key already names it ("Click Topple
## trees"), so its Esc says only "Put away" and its keys stay short;
## `sculpt_tile` names the Sculpt drag, `water_shape` the Water drag.
static func hints_for(
	tool_id: StringName, sculpt_tile: int = HeightBrush.RAISE, water_shape: int = 0
) -> Array[Dictionary]:
	var rows: Array = []
	var size := "Size"
	match tool_id:
		BiomeTool.ID:
			rows = [["Left-drag", "Paint biome"]]
		ThinTool.ID:
			rows = [["Left-drag", "Thin"], ["Ctrl+left-drag", "Clear"]]
		SculptTool.ID:
			var tile_label := "Shape"
			for tile in AuthoringPanel.SCULPT_TILES:
				if int(tile.op) == sculpt_tile:
					tile_label = String(tile.label)
			# Shift smooths too, but a sixth key wraps the row beside the drawer at 720p: the
			# pane's gesture line and its Smooth tile carry it.
			rows = [["Left-drag", tile_label], ["Ctrl+left-drag", "Lower"]]
		PaintTool.ID:
			rows = [["Left-drag", "Lay surface"], ["Ctrl+left-drag", "Erase paint"]]
		WaterTool.ID:
			var drag := "Paint pond" if water_shape == WaterBrush.Shape.POND else "Draw river"
			rows = [["Left-drag", drag], ["Ctrl+left-drag", "Erase water"]]
			size = "Width"
		BridgeTool.ID:
			rows = [["Left-drag", "Lay a crossing"], ["Ctrl+click", "Remove one"]]
			size = "Width"
		EventPresets.COLLAPSE:
			rows = [["Click", EventPresets.DROP_LABEL]]
			size = ""
		EventPresets.TOPPLE:
			rows = [["Click", EventPresets.TOPPLE_LABEL], ["Drag", "Wider stand"]]
	var tool := ToolRegistry.find(tool_id)
	var put_away := "Put away " + tool.label if tool != null else "Put away"
	if size != "":
		rows.append([SIZE_KEY, size])
	rows.append_array([["Ctrl+Z", "Undo"], ["Esc", put_away]])
	var hints: Array[Dictionary] = []
	for row: Array in rows:
		hints.append({"key": row[0], "action": row[1]})
	return hints


## The brush or preset with id `id` (ToolRegistry, EventPresets), or null.
static func find_tool(id: StringName) -> ToolDescriptor:
	var tool := ToolRegistry.find(id)
	return tool if tool != null else EventPresets.find(id)


## History label `label` in the past tense, for the large-edit toast: its first word's past
## ("Clear" -> "Cleared", "Carve river" -> "Carved river", "Thin" -> "Thinned"). Pure.
static func done_phrase(label: String) -> String:
	if label == "":
		return "Changed"
	var words := label.split(" ", false, 1)
	var verb := words[0]
	var past: String = IRREGULAR_PAST.get(verb, "")
	if past == "":
		past = verb + ("d" if verb.ends_with("e") else "ed")
	return past if words.size() == 1 else past + " " + words[1]


## Wires the controller to the table's LevelPlayController and to `events_pane`.
func setup(lpc: LevelPlayController, events_pane: EventsPane) -> void:
	_lpc = lpc
	pane = events_pane
	pane.tool_toggled.connect(_on_tool_toggled)
	pane.sculpt_selected.connect(_on_sculpt_selected)
	pane.biome_selected.connect(_on_biome_selected)
	pane.paint_selected.connect(_on_paint_selected)
	pane.water_shape_selected.connect(
		func(shape: int) -> void: _set_mode(WaterTool.ID, "shape", shape)
	)
	pane.water_depth_selected.connect(
		func(depth: int) -> void: _set_mode(WaterTool.ID, "depth", depth)
	)
	pane.water_speed_changed.connect(
		func(speed: float) -> void: _set_mode(WaterTool.ID, "speed", speed, false)
	)
	pane.bridge_kind_selected.connect(
		func(kind: int) -> void: _set_mode(BridgeTool.ID, "kind", kind)
	)
	pane.brush_size_changed.connect(func(radius: float) -> void: _wired_brush().set_radius(radius))
	pane.brush_strength_changed.connect(func(flow: float) -> void: _wired_brush().set_flow(flow))
	pane.visibility_changed.connect(refresh)
	lpc.level_cleared.connect(_on_level_cleared)
	lpc.level_loaded.connect(func(_level: LevelData) -> void: refresh())
	refresh()


## Why this peer cannot change the map now, or "".
func refusal() -> String:
	if _lpc == null or not _lpc.has_active_level():
		return NOT_READY
	return refusal_for(NetworkManager.has_gm_access(), _lpc.loaded_map_document, _lpc.live_edits)


## The play brushes and presets the table's map can take now (tool id -> true): none while
## refusal() says why, else each tool's works_on() on the live editor, and Collapse while a
## bridge stands.
func available() -> Dictionary:
	var out := {}
	var ok := refusal() == ""
	for tool in ToolRegistry.tools(ToolDescriptor.PLAY):
		out[tool.id] = ok and tool.works_on(_lpc.live_edits.editor)
	out[EventPresets.TOPPLE] = ok
	out[EventPresets.COLLAPSE] = ok and has_bridge(_lpc.live_edits.editor.document)
	return out


## Whether `doc` has a bridge (a deck crossing) to collapse. Pure.
static func has_bridge(doc: MapDocument) -> bool:
	for crossing in doc.crossings:
		if crossing.is_deck():
			return true
	return false


## Shows on the pane why the map takes no live edits, which brushes it can take, and the
## picked and armed brush.
func refresh() -> void:
	if pane == null:
		return
	var why := refusal()
	var open := available()
	# An armed preset the map no longer takes (the last bridge fell) puts itself away.
	if EventPresets.find(armed) != null and not bool(open.get(armed, false)):
		put_away()
		return
	# A table still being set out is no reason to explain; a map that never takes edits is.
	pane.set_notice("" if why == NOT_READY else why)
	pane.set_available(open)
	# A picked brush waiting on a pick in its controls (a biome) keeps its tile pressed.
	var waiting := picked != &"" and _brush != null and not _has_work(picked)
	pane.show_tool(picked, picked != &"" and (armed == picked or waiting))


## Picks `tool_id` and arms it on the board when it has what it needs; a refused pick says
## why in a toast.
func pick(tool_id: StringName) -> void:
	var tool := find_tool(tool_id)
	if tool == null or not tool.exists_in(ToolDescriptor.PLAY):
		return
	var why := refusal()
	if why == "" and not tool.works_on(_lpc.live_edits.editor):
		why = tool.unavailable_tooltip
	if why == "" and tool_id == EventPresets.COLLAPSE:
		why = "" if has_bridge(_lpc.live_edits.editor.document) else NO_BRIDGE
	if why != "":
		UIManager.show_toast(why, UIManager.TOAST_WARNING, 5.0)
		refresh()
		return
	var brush := _wired_brush()
	brush.use_tool(tool)
	picked = tool_id
	if tool_id == PaintTool.ID and PaintTool.of(brush).surface == "":
		# The pane's Paint tiles open on a picked surface (as authoring's do): that one.
		pane.ensure_paint_tiles()
		PaintTool.of(brush).surface = pane.paint_surface()
	if not _has_work(tool_id):
		brush.deactivate()
		_set_armed(&"")
		refresh()
		return
	_prepare(tool_id)
	var mode := brush.mode_for(tool)
	if mode.has_signal(&"fired") and not mode.is_connected(&"fired", _on_fired):
		mode.connect(&"fired", _on_fired)
	brush.fade_held_only = true
	brush.min_stroke_seconds = PLAY_CLICK_SECONDS
	brush.activate()
	_set_armed(tool_id)
	refresh()


## Puts the brush away. The pane keeps a picked brush's controls (its picks arm it again); a
## preset has none, so it is forgotten and the pane is as fresh.
func put_away() -> void:
	if _brush != null:
		if _brush.is_active():
			_brush.deactivate()
		# GameMap's brush is authoring's too: its canopy follows the cursor there, and a click
		# keeps authoring's own exposure.
		_brush.fade_held_only = false
		_brush.min_stroke_seconds = 0.0
	if EventPresets.find(picked) != null:
		picked = &""
	_set_armed(&"")
	refresh()


## Undoes the GM's newest live edit (a gesture in progress is finished first, a water edit
## still computing lands first), with a toast naming it ("Raise undone"). Returns its label,
## or "".
func undo() -> String:
	if not _finish_for_history():
		return ""
	var label := _edits.history.undo()
	if label != "":
		UIManager.show_info("%s undone" % label)
	return label


## Redoes the GM's newest undone live edit, with a toast naming it ("Raise redone"). Returns
## its label, or "".
func redo() -> String:
	if not _finish_for_history():
		return ""
	var label := _edits.history.redo()
	if label != "":
		UIManager.show_info("%s redone" % label)
	return label


func _finish_for_history() -> bool:
	if _edits == null or not is_instance_valid(_edits):
		return false
	if _brush != null:
		_brush.finish_gesture()
	_edits.editor.water.finish_work()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if armed == &"" or _brush == null:
		return
	if event.is_action_pressed("ui_cancel") and not _brush.is_dragging():
		put_away()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_undo"):
		undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_redo"):
		redo()
		get_viewport().set_input_as_handled()


## GameMap's brush, made on first use, its editor the table's live editor and its units the
## level's.
func _wired_brush() -> BrushTool:
	if _brush == null:
		_brush = _lpc.get_game_map().setup_brush_tool()
		_brush.toggled.connect(_on_brush_toggled)
		_brush.refused.connect(
			func(reason: String) -> void: UIManager.show_toast(reason, UIManager.TOAST_WARNING, 5.0)
		)
		_brush.radius_changed.connect(
			func(radius: float) -> void: pane.set_brush_values(radius, _brush.get_flow())
		)
		_brush.gesture_started.connect(
			func() -> void:
				if armed != &"":
					stroke_started.emit()
		)
	var edits := _lpc.live_edits
	if edits != _edits:
		if is_instance_valid(_edits) and _edits.history.recorded.is_connected(_on_recorded):
			_edits.history.recorded.disconnect(_on_recorded)
			_edits.history.changed.disconnect(refresh)
		_edits = edits
		if edits != null:
			edits.history.recorded.connect(_on_recorded)
			edits.history.changed.connect(refresh)
	_brush.editor = edits.editor if edits != null else null
	var level := _lpc.active_level_data
	if level != null:
		_brush.unit_cell_m = level.grid_cell_size
		_brush.unit_per_cell = level.display_unit_per_cell
		_brush.unit_label = level.display_unit
	return _brush


## Whether `tool_id` has what its first stroke needs: a biome for Biome, a surface for Paint.
func _has_work(tool_id: StringName) -> bool:
	match tool_id:
		BiomeTool.ID:
			return _biome_id != ""
		PaintTool.ID:
			return PaintTool.of(_brush).surface != ""
	return true


## What the first stroke would otherwise wait on, and the mode's paint from the pane.
func _prepare(tool_id: StringName) -> void:
	match tool_id:
		PaintTool.ID:
			var surface := PaintTool.of(_brush).surface
			PaintTool.of(_brush).tint = AuthoringController.surface_tint(surface)
			var terrain := _brush.editor.terrain
			if is_instance_valid(terrain):
				terrain.warm_surface(surface)
		WaterTool.ID:
			AuthoredWater.warm_fall_material()
			AuthoredWater.warm_flow_carrier()


func _set_armed(tool_id: StringName) -> void:
	if armed == tool_id:
		_show_hints()
		return
	armed = tool_id
	_show_hints()
	armed_changed.emit(armed)


## The armed brush's keys lead the hint bar; put away, the play row returns, unless the
## measure tool or the sun gizmo took over (their own keys are on the bar then).
func _show_hints() -> void:
	if armed != &"":
		var sculpt := SculptTool.of(_brush).tile
		var shape := WaterTool.of(_brush).shape
		UIManager.set_tool_hints(hints_for(armed, sculpt, shape))
		return
	var map := _lpc.get_game_map() if _lpc != null else null
	var measuring := map != null and map.get_measure_tool() != null
	if measuring and map.get_measure_tool().is_active():
		return
	UIManager.clear_tool_hints()


func _on_tool_toggled(tool_id: StringName, on: bool) -> void:
	if on:
		pick(tool_id)
	elif tool_id == armed:
		put_away()
	else:
		refresh()


func _on_sculpt_selected(op: int) -> void:
	SculptTool.of(_wired_brush()).tile = op
	_pick_again(SculptTool.ID)


func _on_biome_selected(biome_id: String) -> void:
	_biome_id = biome_id
	var brush := _wired_brush()
	BiomeTool.of(brush).biome_id = biome_id
	BiomeTool.of(brush).tint = AuthoringController.biome_tint(biome_id)
	if brush.editor != null:
		brush.editor.prepare_biome(biome_id)
	_pick_again(BiomeTool.ID)


func _on_paint_selected(surface: String) -> void:
	var brush := _wired_brush()
	PaintTool.of(brush).surface = surface
	if brush.editor != null:
		var reason := brush.editor.surface_refusal(surface)
		if reason != "":
			UIManager.show_toast(reason, UIManager.TOAST_WARNING, 5.0)
	_pick_again(PaintTool.ID)


## A mode setting `field` = `value` picked in the pane; `arm` arms its tool as a tile does.
func _set_mode(tool_id: StringName, field: String, value: Variant, arm: bool = true) -> void:
	var brush := _wired_brush()
	brush.mode_for(ToolRegistry.find(tool_id)).set(field, value)
	if arm:
		_pick_again(tool_id)
	elif armed == tool_id:
		_show_hints()


## A tile of the tool's own picked: arms it (again), as a pick in authoring re-activates a
## brush put down with a right click.
func _pick_again(tool_id: StringName) -> void:
	pick(tool_id)


func _on_brush_toggled(active: bool) -> void:
	if not active and armed != &"":
		_brush.fade_held_only = false
		_brush.min_stroke_seconds = 0.0
		if EventPresets.find(picked) != null:
			picked = &""
		_set_armed(&"")
		refresh()


## A preset fired an event: the table's TerrainEvents starts it on every board (a refusal is
## toasted), and the drawer steps aside, since the spectacle is the board's (UI_TASTE M7). The
## preset stays armed, its keys on the hint bar, for the next one.
func _on_fired(event: TerrainEvent) -> void:
	var edits := _lpc.live_edits if _lpc != null else null
	if edits == null or edits.events == null:
		return
	var why := edits.events.start(event)
	if why != "":
		UIManager.show_toast(why, UIManager.TOAST_WARNING, 5.0)
		return
	stroke_started.emit()


## A live edit recorded: a preset's change, or a large edit, offers Undo in a toast while it is
## still the newest.
func _on_recorded(entry: Dictionary) -> void:
	if entry.has("preset"):
		var done: String = PRESET_DONE.get(int(entry.preset), "Changed for everyone at the table")
		UIManager.show_undo_toast(done, _undo_entry.bind(entry))
		return
	if not is_large(entry):
		return
	UIManager.show_undo_toast(
		UNDO_TOAST % done_phrase(String(entry.get("label", ""))), _undo_entry.bind(entry)
	)


func _undo_entry(entry: Dictionary) -> void:
	if _edits == null or not is_instance_valid(_edits):
		return
	if not _edits.history.is_newest(entry):
		UIManager.show_info(NEWER_EDITS)
		return
	undo()


## The brush the Events pane arms (GameMap's), or null before the first pick.
func brush() -> BrushTool:
	return _brush


func _on_level_cleared() -> void:
	put_away()
	picked = &""
	_edits = null
	if _brush != null:
		_brush.editor = null
	refresh()
