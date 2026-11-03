class_name VillageBrush
extends BrushMode

## The Village tool's mode (VillageTool): lays, sizes, picks and removes the plaza discs of the
## map's dressed villages (Settlement.plazas; docs/systems/villages.md section 10). BrushTool routes
## the tool's press, frames, release and cancel to it. Where a plaza goes and how it is paved is
## SettlementEditor's rule (add_plaza, resize_plaza, remove_plaza: one history entry each, the
## paving and the kit's plaza furnishings follow, a live-edit peer receives the usual `surface`
## and `settlements` ops); this only wires the gestures to it. VillageRings draws the answer.
##
## Gestures.
## - A press on bare ground starts a new plaza at that point; the village it joins is the nearest
##   in reach (VillagePlazas.village_for), the picked one keeping a press that is only a few
##   metres nearer to another. A click lays a plaza of DEFAULT_RADIUS_M, a drag sizes it by how
##   far the pointer goes from the centre.
## - A press on a plaza's rim (the soft ring, or near one of its handle dots) grabs the edge: the
##   drag sizes that plaza, the rim following the pointer. A press inside a plaza picks it; dragged
##   past a click's distance (VillagePlazas.DRAG_MIN_M) it moves the plaza instead, the disc
##   following the pointer without jumping to it. A place the plaza may not stand (water, steep
##   ground, a building, out of reach of every village, a full village) shows the refusal pill, and
##   the release there changes nothing.
## - The release does the edit as one history entry; the ring drawn while dragging is the preview.
## - Delete or Backspace over a plaza, or the pane's Remove, removes it with its paving; the
##   brackets and Shift+wheel over a plaza step its radius by a metre; Escape lets go of the
##   picked plaza; RMB or Escape during a drag drops it.
##
## The picked village is what the pane shows. Until the author picks one (a press, a plaza, the
## pane's village row) it follows the pointer: the village a press there would join, so the pane,
## the ghost and its hint always name the same village. Once picked it stays until the author
## picks again.
##
## Fields (topic fields, villages.md section 11). With the pane's "Field" picked (`lay_field`), a
## press on bare ground lays a field of `field_kind` (or the village's default kind,
## VillageFields.kind_for) instead of a plaza, through SettlementEditor.add_field. A field is
## picked, sized and removed exactly as a plaza: the pick names its disc list (`selected_group`,
## VillageFields.GROUP_PLAZAS or GROUP_FIELDS) and its index in it (`selected_plaza`).

## The picked village or plaza changed.
signal selection_changed(village: int, plaza: int)
## Something the pane shows changed: the selection, the size a held drag is making, or the
## villages and plazas of the document (an edit, an undo, a redo).
signal view_changed

## The gesture a held press is making.
const GESTURE_NEW := &"new"
const GESTURE_RESIZE := &"resize"
const GESTURE_PICK := &"pick"
## A press inside a plaza dragged past the click threshold: the plaza follows the pointer.
const GESTURE_MOVE := &"move"

## The pixels a rim grab reaches each side of the edge, and round a handle dot (the dots are the
## S6 target, 44 px across).
const RIM_PX := 12.0
const HANDLE_HIT_PX := 22.0
## The pixels a pointer reaches past a piece's drawn radius (a barrel is small on screen).
const PIECE_PAD_PX := 10.0
## The canopy fade's reach round a plaza (metres, before the brush's fade factor).
const FADE_M := 3.0
## Plain-words reasons a press makes nothing.
const NO_VILLAGE := "Dress a street with the Wall tool first: a plaza belongs to a village."
const FULL := "A village holds four plazas. Remove one to make room."
const REFUSED := "A plaza cannot go there."
const WATER := "A plaza cannot stand in water: put it on dry ground."
const STEEP := "A plaza needs level ground: that slope is too steep."
const REACH := "That is too far from any village: a plaza stays near its village."
## A plaza dropped over a house (ON_BUILDING says it for a field).
const PLAZA_ON_BUILDING := "A plaza cannot cover a building."
const PLAZA_ON_BUILDING_SHORT := "Over a building: put it on open ground"
## The same in the pill's few words, for a plaza held over a refused place.
const WATER_SHORT := "Too wet: needs dry ground"
const STEEP_SHORT := "Too steep: needs level ground"
const REACH_SHORT := "Too far from the village"
## The words beside the cursor.
const HOVER_RIM := "Drag the edge to size this plaza"
const HOVER_INSIDE := "Drag to move this plaza, click to pick it"
const HOVER_PICKED := "Drag to move it, drag the edge to size it"
const HOVER_PICKED_FIELD := "Drag the edge to size it, Delete removes it"
## The pill while a held plaza is over a place it may stand.
const MOVE_HINT := "Release to put it here"
const MOVE_HINT_IN := "Release to move it to %s"
const IDLE := "Click for a plaza, or drag to size it"
const IDLE_IN := "Click for a plaza in %s, or drag to size it"
const NO_VILLAGE_SHORT := "Dress a street first"
const FULL_SHORT := "Four plazas already"
const FIELDS_FULL := "A village holds four fields. Remove one to make room."
const FIELDS_FULL_SHORT := "Four fields already"
const NO_FIELDS := "This village keeps no fields: pick another character, or lay a plaza."
const NO_FIELDS_SHORT := "No fields here"
const ON_BUILDING := "A field cannot cover a building: lay it on open ground."
const ON_BUILDING_SHORT := "Over a building: lay it on open ground"
const FIELD_HOVER_RIM := "Drag the edge to size this field"
const FIELD_HOVER_INSIDE := "%s: click to pick, Delete removes it"
const FIELD_IDLE := "Click for %s, or drag to size it"
const FIELD_IDLE_IN := "Click for %s in %s, or drag to size it"
## What a press lays, in the hint's words.
const KIND_WORDS := {"crops": "a crop field", "orchard": "an orchard", "garden": "a garden"}

## The picked village (a Settlement id) and disc (an index in its `selected_group` list), or -1.
var selected_village: int = -1
var selected_plaza: int = -1
var selected_group: StringName = VillageFields.GROUP_PLAZAS
## The disc under the pointer: its village, list, index and part (VillagePlazas.PART_*), or -1.
var hover_village: int = -1
var hover_plaza: int = -1
var hover_group: StringName = VillageFields.GROUP_PLAZAS
var hover_part: StringName = &""
## The held press's gesture (GESTURE_*), or empty.
var gesture: StringName = &""
## A press on bare ground lays a field (true) or a plaza; the kind asked for ("" the default).
var lay_field: bool = false
var field_kind: String = ""
## The furnishing half: hover, pick, move, turn, swap and remove a standing piece (VillageProps).
var props := VillageProps.new()
## Swap, Back and Remove beside the picked piece's ring, on the cursor's overlay (made on the first
## frame that has one).
var piece_buttons: VillagePieceButtons = null

var _grab_village: int = -1
var _grab_plaza: int = -1
var _grab_group: StringName = VillageFields.GROUP_PLAZAS
var _grab_field_kind: String = ""
var _grab_kit: String = ""
var _centre: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
## A press inside a plaza: where it landed, the plaza's centre from there, and (once it moves) the
## place the plaza would stand, with the verdict on it (VillagePlazas.move_problem) and the map
## facts that verdict reads, built when the move starts.
var _press_at: Vector2 = Vector2.ZERO
var _offset: Vector2 = Vector2.ZERO
var _dest: Vector2 = Vector2.ZERO
var _verdict: Dictionary = {}
var _world: RefCounted = null
var _plans: Array[PackedVector2Array] = []
var _start_radius: float = 0.0
var _grabbed_at: float = 0.0
var _rim_m: float = VillagePlazas.RIM_BAND_M
var _handle_m: float = 0.0
var _explicit: bool = false
var _message: String = ""
var _signature: String = ""
## True after leave() paused the map's StructureWarmup; the next frame() resumes it.
var _warm_paused: bool = false


func _init() -> void:
	picks = true
	fades = true


## The reason a plaza edit made nothing, in plain words. Pure.
static func refusal_text(reason: StringName) -> String:
	match reason:
		SettlementEditor.REFUSED_FULL:
			return FULL
		SettlementEditor.REFUSED_STREET:
			return NO_VILLAGE
		SettlementEditor.REFUSED_BUILDING:
			return ON_BUILDING
		SettlementEditor.REFUSED_WATER:
			return WATER
		SettlementEditor.REFUSED_STEEP:
			return STEEP
		SettlementEditor.REFUSED_REACH:
			return REACH
	return REFUSED


## The pill's few words for a refused place for a held plaza (VillagePlazas.move_problem's reason).
static func short_reason(reason: StringName) -> String:
	match reason:
		SettlementEditor.REFUSED_FULL:
			return FULL_SHORT
		SettlementEditor.REFUSED_BUILDING:
			return PLAZA_ON_BUILDING_SHORT
		SettlementEditor.REFUSED_WATER:
			return WATER_SHORT
		SettlementEditor.REFUSED_STEEP:
			return STEEP_SHORT
		SettlementEditor.REFUSED_REACH:
			return REACH_SHORT
	return REFUSED


## The words beside the ghost of a plaza (or, with `kind`, a field of that kind) that would join
## village `village` of `doc`: the village is named once the map has two or more.
static func ghost_hint(doc: MapDocument, village: int, kind: String = "") -> String:
	var named := VillagePlazas.village_name(village).to_lower()
	if kind != "":
		var words := str(KIND_WORDS.get(kind, "a field"))
		return FIELD_IDLE % words if doc.settlements.size() < 2 else FIELD_IDLE_IN % [words, named]
	if doc.settlements.size() < 2:
		return IDLE
	return IDLE_IN % named


## The kind of field a press lays in village `village` of `doc`, or "" when it lays a plaza (the
## pane's Plaza is picked) or the village keeps no fields.
func laying_kind(doc: MapDocument, village: int) -> String:
	var held := doc.settlement(village) if village > 0 else null
	if not lay_field or held == null:
		return ""
	return VillageFields.kind_for(held.kit, field_kind)


## The picked disc's record ({"at", "radius", ...}), or {}.
func picked_disc(doc: MapDocument) -> Dictionary:
	return _disc(doc, selected_village, selected_group, selected_plaza)


static func _disc(doc: MapDocument, village: int, group: StringName, index: int) -> Dictionary:
	var held := doc.settlement(village) if village > 0 else null
	if held == null or index < 0:
		return {}
	var discs: Array[Dictionary] = held.get(group)
	return discs[index] if index < discs.size() else {}


## `radius` held to the range of the disc it sizes: a plaza of `kit` or a field of `kind`.
static func clamp_for(radius: float, group: StringName, kit: String, kind: String) -> float:
	if group == VillageFields.GROUP_FIELDS:
		return VillageFields.clamp_radius(radius, kind)
	return VillagePlazas.clamp_radius(radius, kit)


## Why the last press or edit made nothing, or "".
func message() -> String:
	return _message


## The radius the held gesture is making now (metres in the map frame), or 0 with none.
func preview_radius() -> float:
	var field := _grab_group == VillageFields.GROUP_FIELDS
	match gesture:
		GESTURE_NEW:
			if field:
				return VillageFields.radius_for_drag(_centre, _to, _grab_field_kind)
			return VillagePlazas.radius_for_drag(_centre, _to, _grab_kit)
		GESTURE_RESIZE:
			# A disc already under its tool floor is never pushed up by a grab alone.
			var floor_m := minf(VillagePlazas.min_radius(_grab_kit), _start_radius)
			if field:
				floor_m = minf(VillageFields.clamp_radius(0.0, _grab_field_kind), _start_radius)
			var radius := VillagePlazas.radius_for_rim_drag(
				_start_radius, _grabbed_at, _centre.distance_to(_to), floor_m
			)
			if field:
				radius = minf(radius, VillageFields.clamp_radius(INF, _grab_field_kind))
			return radius
	return 0.0


## The held gesture's plaza centre (map XZ).
func centre() -> Vector2:
	return _centre


## Where the plaza a held move carries would stand (map XZ), or its own centre with none.
func move_destination() -> Vector2:
	return _dest if gesture == GESTURE_MOVE else _centre


## Why the place a held move is over is refused (SettlementEditor.REFUSED_*), or &"".
func move_reason() -> StringName:
	return _verdict.get("reason", &"") if gesture == GESTURE_MOVE else &""


## The village the held plaza would belong to at its place now, or -1.
func move_village() -> int:
	return int(_verdict.get("village", -1)) if gesture == GESTURE_MOVE else -1


## Whether a held drag is sizing a plaza (a new one or a grabbed rim).
func sizing() -> bool:
	return gesture == GESTURE_NEW or gesture == GESTURE_RESIZE


## The village a press at map point `p` would join (the ghost's), or -1.
func ghost_village(editor: AuthoringEditor, p: Vector2) -> int:
	return VillagePlazas.village_for(editor.document, p, selected_village)


## Picks village `village` and its plaza `plaza` (-1: the village alone). `explicit` false is the
## mode's own pick (the first village, or the one the pointer is over) that the next frame may
## move; an author's pick stays. `group` is the list `plaza` indexes (a plaza's or a field's).
func select(
	village: int, plaza: int, explicit: bool = true, group: StringName = VillageFields.GROUP_PLAZAS
) -> void:
	_explicit = explicit and village > 0
	if village == selected_village and plaza == selected_plaza and group == selected_group:
		return
	selected_village = village
	selected_plaza = plaza
	selected_group = group
	selection_changed.emit(village, plaza)
	view_changed.emit()


## Sets what a press on bare ground lays: a field (of `kind`, "" for the village's default) or a
## plaza.
func set_lay(field: bool, kind: String = "") -> void:
	if field == lay_field and kind == field_kind:
		return
	lay_field = field
	field_kind = kind
	view_changed.emit()


## Removes disc `index` of `group` (a plaza with its paving, or a field with its paint) of village
## `village`, keeping the pick pointing at the same disc. False when the editor refuses.
func remove(
	editor: AuthoringEditor,
	village: int,
	index: int,
	group: StringName = VillageFields.GROUP_PLAZAS
) -> bool:
	var fields := group == VillageFields.GROUP_FIELDS
	var done := (
		editor.settlements.remove_field(village, index)
		if fields
		else editor.settlements.remove_plaza(village, index)
	)
	if not done:
		return false
	hover_village = -1
	hover_plaza = -1
	if village == selected_village and selected_plaza >= 0 and group == selected_group:
		if selected_plaza == index:
			select(village, -1)
		elif selected_plaza > index:
			select(village, selected_plaza - 1, true, group)
	return true


## Removes the picked plaza or field (the pane's Remove).
func remove_selected(editor: AuthoringEditor) -> bool:
	if props.has_picked():
		return props.remove(editor, false) == ""
	if selected_plaza < 0:
		return false
	return remove(editor, selected_village, selected_plaza, selected_group)


## Sets the picked disc's radius to `radius` metres (the pane's slider). False when it changes
## nothing or the editor refuses.
func set_selected_radius(editor: AuthoringEditor, radius: float) -> bool:
	return _resize(editor, selected_village, selected_group, selected_plaza, radius)


func _resize(
	editor: AuthoringEditor, village: int, group: StringName, index: int, radius: float
) -> bool:
	var held := editor.document.settlement(village) if village > 0 else null
	var disc := _disc(editor.document, village, group, index)
	if disc.is_empty():
		return false
	var wanted := clamp_for(radius, group, held.kit, str(disc.get("kind", "")))
	if group == VillageFields.GROUP_FIELDS:
		return editor.settlements.resize_field(village, index, wanted)
	return editor.settlements.resize_plaza(village, index, wanted)


# ============================================================================
# BrushMode hooks
# ============================================================================


func has_target() -> bool:
	return hover_plaza >= 0 or props.has_hover()


## A press on a standing piece picks it (a drag moves it); on a plaza's rim grabs the edge, inside
## it picks the plaza, on bare ground starts a new plaza of the picked (or nearest) village. The
## edit is the release's. A piece beats the plaza it stands on, even on its rim (a market's stalls
## stand on the edge); the edge between them still grabs.
func press(brush: BrushTool) -> bool:
	_message = ""
	var editor := brush.editor
	var doc := editor.document
	var p := editor.to_map_xz(brush.hit)
	var found := VillageFields.pick_any(doc.settlements, p, _rim_m, _handle_m)
	var view := brush.cursor.camera if brush.cursor != null else null
	props.set_view(view, brush.pointer, brush.structure_blocks)
	if props.press(editor, p):
		select(props.village, -1, true)
		return false
	props.drop()
	if not found.is_empty():
		var village := int(found["settlement"])
		_grab_village = village
		_grab_kit = doc.settlement(village).kit
		_grab_group = found["group"]
		_grab_plaza = int(found["index"])
		var disc := _disc(doc, village, _grab_group, _grab_plaza)
		_grab_field_kind = str(disc.get("kind", ""))
		_centre = disc["at"]
		_start_radius = float(disc["radius"])
		_to = p
		_grabbed_at = _centre.distance_to(p)
		gesture = GESTURE_RESIZE if found["part"] == VillagePlazas.PART_RIM else GESTURE_PICK
		_press_at = p
		_offset = VillagePlazas.grab_offset(_centre, p)
		select(village, _grab_plaza, true, _grab_group)
		return false
	var target := ghost_village(editor, p)
	# A press may still drag a small field beside a house: only the smallest disc is refused here.
	_message = refusal_at(doc, target, p, true)
	if _message != "":
		brush.refused.emit(_message)
		return false
	_grab_village = target
	_grab_kit = doc.settlement(target).kit
	_grab_field_kind = laying_kind(doc, target)
	_grab_group = VillageFields.GROUP_FIELDS if lay_field else VillageFields.GROUP_PLAZAS
	_grab_plaza = -1
	_centre = p
	_to = p
	gesture = GESTURE_NEW
	select(target, -1)
	return false


## Why a press on bare ground joining village `target` (-1: none in reach) lays nothing, or "".
## With map point `at`, a field there that would cover a building is refused too: the kind's
## click size (the ghost), or with `smallest` its smallest size (a press, which may drag it).
func refusal_at(
	doc: MapDocument, target: int, at: Vector2 = Vector2.INF, smallest: bool = false
) -> String:
	if target < 0:
		return NO_VILLAGE
	var held := doc.settlement(target)
	if not lay_field:
		return FULL if held.plazas.size() >= Settlement.MAX_PLAZAS else ""
	var kind := laying_kind(doc, target)
	if kind == "":
		return NO_FIELDS
	if held.fields.size() >= Settlement.MAX_FIELDS:
		return FIELDS_FULL
	if at.is_finite():
		var table := VillageFields.MIN_RADIUS_M if smallest else VillageFields.DEFAULT_RADIUS_M
		var radius := float(table.get(kind, 4.0))
		if VillageFieldGround.covers_building(VillageFieldGround.footprints(doc), at, radius):
			return ON_BUILDING
	return ""


func took_press() -> bool:
	return gesture != &"" or props.gesture != &""


## Follows the pointer: the gesture's end, or the plaza under it; keeps the pick and the pane
## in step with the document (an undo can take a picked plaza away) and, until the author has
## picked a village, with the village under the pointer.
func frame(brush: BrushTool) -> void:
	var editor := brush.editor
	if editor == null:
		return
	if _warm_paused:
		_warm_paused = false
		StructureWarmup.resume_map(editor.map_root)
	_sync_selection(editor)
	if brush.hit == Vector3.INF:
		hover_village = -1
		hover_plaza = -1
		props.hover_village = -1
		props.hover_slot = ""
	else:
		var camera := brush.cursor.camera if brush.cursor != null else null
		var scale := editor.map_scale()
		_rim_m = maxf(
			VillagePlazas.RIM_BAND_M,
			StructureBrush.metres_for_pixels(camera, brush.hit, RIM_PX, scale)
		)
		_handle_m = maxf(
			_rim_m, StructureBrush.metres_for_pixels(camera, brush.hit, HANDLE_HIT_PX, scale)
		)
		var p := editor.to_map_xz(brush.hit)
		if props.gesture != &"":
			props.track(editor, p, brush.hit.y, brush.building_under_pointer())
		elif gesture != &"":
			_to = p
			_track_move(editor, p)
		else:
			var found := VillageFields.pick_any(editor.document.settlements, p, _rim_m, _handle_m)
			hover_village = int(found.get("settlement", -1))
			hover_plaza = int(found.get("index", -1))
			hover_group = found.get("group", VillageFields.GROUP_PLAZAS)
			hover_part = found.get("part", &"")
			var pad := StructureBrush.metres_for_pixels(camera, brush.hit, PIECE_PAD_PX, scale)
			props.set_view(camera, brush.pointer, brush.structure_blocks)
			props.hover(editor, p, pad)
			if props.has_hover():
				# A piece under the pointer is the target, not the plaza it stands in.
				hover_village = -1
				hover_plaza = -1
			if not _explicit:
				var target := hover_village if hover_plaza >= 0 else ghost_village(editor, p)
				if target > 0 and target != selected_village:
					select(target, -1, false)
	_announce(editor)
	_place_buttons(brush)


## Sets the Swap, Back and Remove buttons beside the picked piece, or hides them while none is
## picked or a press is held (a carried piece shows its own pill instead).
func _place_buttons(brush: BrushTool) -> void:
	var cursor := brush.cursor
	if cursor == null or not is_instance_valid(cursor.canvas) or cursor.camera == null:
		return
	if piece_buttons == null or not is_instance_valid(piece_buttons):
		piece_buttons = VillagePieceButtons.new()
		piece_buttons.acted.connect(_act.bind(brush))
		cursor.canvas.add_child(piece_buttons)
	var row := props.picked_row(brush.editor)
	if row.is_empty() or gesture != &"" or props.gesture != &"":
		piece_buttons.hide_all()
		return
	var ring_m := maxf(
		VillageFurnishings.drawn_radius(row["item"]) + VillagePropRings.RING_GROW_M,
		VillagePropRings.RING_FLOOR_M
	)
	var actions := VillagePieceButtons.actions_for(
		props.pane_state(brush.editor.document, props.village)
	)
	piece_buttons.place(cursor.camera, brush.editor, row, ring_m, actions)


## A button beside the picked piece was pressed: the pane's Swap, Back to its spot or Remove.
func _act(action: StringName, brush: BrushTool) -> void:
	var editor := brush.editor
	if editor == null or not props.has_picked() or gesture != &"" or props.gesture != &"":
		return
	match action:
		VillagePieceButtons.SWAP:
			_tell(brush, props.swap(editor))
		VillagePieceButtons.BACK:
			props.unpin(editor)
		VillagePieceButtons.REMOVE:
			_tell(brush, props.remove(editor, false))
	brush.redraw()


## A press inside a plaza turns into a move once the pointer is a click's distance from where it
## landed; while it is a move, the place the plaza would stand and the verdict on it follow the
## pointer (the verdict is asked again only when the place changes).
func _track_move(editor: AuthoringEditor, p: Vector2) -> void:
	var plazas := _grab_group == VillageFields.GROUP_PLAZAS
	if gesture == GESTURE_PICK and plazas and VillagePlazas.is_move(_press_at, p):
		gesture = GESTURE_MOVE
		_world = SettlementGround.world_of(editor.document)
		_plans = VillageFieldGround.footprints(editor.document)
		_dest = _centre
		_verdict = {"village": _grab_village, "reason": &""}
	if gesture != GESTURE_MOVE:
		return
	var at := VillagePlazas.moved_to(p, _offset)
	if at.is_equal_approx(_dest):
		return
	_dest = at
	if at.is_equal_approx(_centre):
		# Back where it started: nothing to refuse, even if the plaza already covers a house.
		_verdict = {"village": _grab_village, "reason": &""}
		return
	_verdict = VillagePlazas.move_problem(
		editor.document, _grab_village, _grab_plaza, at, _world, _plans
	)


## The release of a move: the plaza goes where it was carried, unless that place is refused (then
## it stays and the pill's reason is a toast).
func _end_move(brush: BrushTool) -> void:
	var editor := brush.editor
	var reason: StringName = _verdict.get("reason", &"")
	if reason == &"" and not _dest.is_equal_approx(_centre):
		if editor.settlements.move_plaza(_grab_village, _grab_plaza, _dest):
			var target := int(_verdict["village"])
			if target != _grab_village:
				select(target, editor.document.settlement(target).plazas.size() - 1)
			return
		reason = editor.settlements.last_refusal
	if reason != &"":
		_message = refusal_text(reason)
		if reason == SettlementEditor.REFUSED_BUILDING:
			_message = PLAZA_ON_BUILDING
		brush.refused.emit(_message)


## The release: lays the new plaza, or sizes or moves the grabbed one, as one history entry.
func end(brush: BrushTool) -> void:
	var editor := brush.editor
	if props.gesture != &"" and editor != null:
		var refused := props.end(editor)
		if refused != "":
			_message = refused
			brush.refused.emit(refused)
		reset()
		return
	if gesture == &"" or editor == null:
		reset()
		return
	if gesture == GESTURE_MOVE:
		_end_move(brush)
		reset()
		return
	var radius := preview_radius()
	var done := true
	var fields := _grab_group == VillageFields.GROUP_FIELDS
	if gesture == GESTURE_NEW and fields:
		done = editor.settlements.add_field(_grab_village, _centre, radius, _grab_field_kind)
		if done:
			var count := editor.document.settlement(_grab_village).fields.size()
			select(_grab_village, count - 1, true, _grab_group)
	elif gesture == GESTURE_NEW:
		done = editor.settlements.add_plaza(_grab_village, _centre, radius)
		if done:
			select(_grab_village, editor.document.settlement(_grab_village).plazas.size() - 1)
	elif gesture == GESTURE_RESIZE and absf(radius - _start_radius) >= 0.1:
		done = (
			editor.settlements.resize_field(_grab_village, _grab_plaza, radius)
			if fields
			else editor.settlements.resize_plaza(_grab_village, _grab_plaza, radius)
		)
	if not done:
		_message = refusal_text(editor.settlements.last_refusal)
		brush.refused.emit(_message)
	reset()


## Escape or RMB: drops a held gesture, else lets go of the picked plaza.
func cancel(_brush: BrushTool) -> void:
	if gesture != &"" or props.gesture != &"":
		reset()
	elif props.has_picked():
		props.drop()
		view_changed.emit()
	elif selected_plaza >= 0:
		select(selected_village, -1)


## Escape with no press held is the brush's while a plaza or a piece is picked.
func has_selection() -> bool:
	return selected_plaza >= 0 or props.has_picked()


## The tool is put down or another is picked.
func leave(brush: BrushTool) -> void:
	StructureWarmup.pause_map(brush.editor.map_root if brush.editor != null else null)
	_warm_paused = true
	reset()
	hover_village = -1
	hover_plaza = -1
	props.clear()
	if piece_buttons != null and is_instance_valid(piece_buttons):
		piece_buttons.hide_all()
	select(-1, -1, false)
	_signature = ""


## Drops a held gesture.
func reset() -> void:
	gesture = &""
	props.reset()
	_grab_village = -1
	_grab_plaza = -1
	_verdict = {}
	_world = null
	_plans = []


## Delete or Backspace over a piece or a plaza.
func remove_target(brush: BrushTool) -> void:
	if brush.editor == null:
		return
	if props.has_hover():
		_tell(brush, props.remove(brush.editor))
	elif hover_plaza >= 0:
		if not remove(brush.editor, hover_village, hover_plaza, hover_group):
			brush.refused.emit(REFUSED)


## Q and E turn the piece under the pointer (else the picked one) a notch, Shift a quarter.
func rotates() -> bool:
	return props.has_hover() or props.has_picked()


func rotate(brush: BrushTool, steps: int) -> void:
	if brush.editor != null and gesture == &"" and props.gesture == &"":
		_tell(brush, props.turn(brush.editor, steps))


## R shows another draw of the piece under the pointer (else the picked one).
func rerolls() -> bool:
	return props.has_hover() or props.has_picked()


func reroll(brush: BrushTool) -> void:
	if brush.editor != null and gesture == &"" and props.gesture == &"":
		_tell(brush, props.reroll(brush.editor))


## Toasts `words` when an edit was refused.
func _tell(brush: BrushTool, words: String) -> void:
	if words != "":
		_message = words
		brush.refused.emit(words)


## Shift+wheel over a plaza or a bracket key: the plaza under the pointer (else the picked one)
## grows or shrinks a metre a notch.
func step(brush: BrushTool, steps: int) -> void:
	var editor := brush.editor
	if editor == null or gesture != &"":
		return
	var village := hover_village if hover_plaza >= 0 else selected_village
	var index := hover_plaza if hover_plaza >= 0 else selected_plaza
	var group := hover_group if hover_plaza >= 0 else selected_group
	var disc := _disc(editor.document, village, group, index)
	if disc.is_empty():
		return
	var wanted := float(disc["radius"]) + steps * VillagePlazas.RADIUS_STEP_M
	if not _resize(editor, village, group, index, wanted):
		if editor.settlements.last_refusal != &"":
			brush.refused.emit(REFUSED)
		return
	select(village, index, true, group)
	brush.redraw()


## The picked piece clears the bush it stands in, stems and all (VillageFurnishings.cut_radius),
## at its standing place or, while carried, at the place it would go. None while no piece is
## picked. The cut, not the brush window, keeps the piece clear while the pointer is on its
## buttons: a window held open there stripped the leaves round the piece and left bare stems.
func fade_cut(brush: BrushTool) -> Vector4:
	if brush.editor == null or not props.has_picked():
		return Vector4.ZERO
	var row := props.picked_row(brush.editor)
	if row.is_empty():
		return Vector4.ZERO
	var spot: Vector2 = row["item"]["position"]
	var y := float(row["y"])
	if props.moving():
		spot = props.destination()
		y = WaterGeometry.ground_at(brush.editor.document, spot)
	var at := brush.editor.to_world(Vector3(spot.x, y, spot.y))
	var radius := VillageFurnishings.cut_radius(row["item"]) * brush.editor.map_scale()
	return Vector4(at.x, at.y, at.z, radius)


func fade_focus(brush: BrushTool) -> Vector4:
	var reach := FADE_M
	var at := brush.hit
	if gesture != &"" and brush.editor != null:
		var middle := move_destination()
		var radius := _start_radius if gesture == GESTURE_MOVE else preview_radius()
		reach += radius * brush.editor.map_scale()
		var y := WaterGeometry.ground_at(brush.editor.document, middle)
		at = brush.editor.to_world(Vector3(middle.x, y, middle.y))
	return Vector4(at.x, at.y, at.z, reach)


# ============================================================================
# State kept in step with the document
# ============================================================================


## Lets go of a pick an undo took away, and picks the first village when none is picked, so the
## pane's character tiles are live from the first frame.
func _sync_selection(editor: AuthoringEditor) -> void:
	props.sync(editor)
	var doc := editor.document
	var held := doc.settlement(selected_village) if selected_village > 0 else null
	if held == null:
		var first: int = doc.settlements[0].id if not doc.settlements.is_empty() else -1
		select(first, -1, false)
	elif selected_plaza >= 0 and picked_disc(doc).is_empty():
		select(selected_village, -1, _explicit)
	if gesture != &"" and doc.settlement(_grab_village) == null:
		reset()


## Emits view_changed when what the pane shows differs from the last frame (a held drag's size
## included, so the pane's size reads it live).
func _announce(editor: AuthoringEditor) -> void:
	var parts: Array = [
		selected_village,
		selected_plaza,
		selected_group,
		lay_field,
		field_kind,
		preview_radius() if sizing() else 0.0,
		props.signature(),
	]
	for settlement in editor.document.settlements:
		parts.append(
			[
				settlement.id,
				settlement.kit,
				settlement.plazas,
				settlement.fields,
				settlement.removed.size(),
			]
		)
	var now := var_to_str(parts)
	if now != _signature:
		_signature = now
		view_changed.emit()


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if brush.editor != null:
		VillageRings.draw(brush, cursor, self)
