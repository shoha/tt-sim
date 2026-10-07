class_name AvatarBuilder
extends AnimatedCanvasLayerPanel

## The avatar builder: a player makes or edits their avatar token (docs/ASSET_PIPELINE.md
## section 10 "Recipe") by clicking, with the figure updating at once. A turntable preview
## of the figure stands on the left (AvatarBuilderPreview); a rail picks one calm pane at a
## time: Pose (the player's own figure as a silhouette in each stance, AvatarStanceTiles),
## Face (the sheet's actual eye, brow, mouth and mark cells), Colours (swatches from the
## kit's curated sets, one row per palette slot the chosen parts use), Shape (three
## sliders) and, once a slot has more than one part, Parts (thumbnails). "Surprise me" draws
## a whole harmonious recipe (AvatarSurprise) and each pane rerolls its own section.
##
## Two ways in: open_for_new (the Add Token browser's Avatar tab) starts from one of the
## preset recipes and emits create_confirmed; open_for_token (a placed avatar's context
## menu) previews every pick on the token itself (AvatarTokenFactory.set_recipe, local
## only), puts the original back on cancel and emits edit_confirmed for the owner to commit
## and record as one undo entry. Proportion drags are quantised to AvatarSurprise.STEP and
## applied at most once a frame (a never-seen shape costs about 1.6 ms); the stance
## silhouettes follow a shape change after a short pause.
##
## The panel takes a large share of the window (panel_size) and gives most of its height to
## the preview, which is about PREVIEW_ASPECT as wide as it is tall; the pose tiles grow to
## the pane's height. The Face pane zooms the preview to the head, and its tiles are painted
## on the avatar's skin (AvatarFaceIcons).

signal create_confirmed(recipe: Dictionary, token_name: String)
signal edit_confirmed(
	token: BoardToken,
	original: Dictionary,
	recipe: Dictionary,
	original_name: String,
	token_name: String
)
signal cancelled

const SCENE_PATH := "res://scenes/states/playing/avatar_builder.tscn"
## Rail items: id, icon, label. "parts" shows only when a slot has a choice.
const PANES := [
	[&"pose", "walk", "Pose"],
	[&"face", "mood-smile", "Face"],
	[&"colours", "palette", "Colours"],
	[&"shape", "adjustments", "Shape"],
	[&"parts", "shirt", "Parts"],
]
const COLOUR_LABELS := {
	"skin": "Skin",
	"hair": "Hair",
	"eyes": "Eyes",
	"primary": "Outfit",
	"secondary": "Trim",
	"accent": "Accent",
	"leather": "Leather",
	"metal": "Metal",
}
const FACE_LABELS := {"eyes": "Eyes", "brows": "Brows", "mouths": "Mouth", "marks": "Marks"}
## Shape rows in display order: control, label, low hint, high hint.
const SHAPE_ROWS := [
	["height", "Height", "Short", "Tall"],
	["build", "Build", "Slight", "Sturdy"],
	["head", "Head", "Small", "Big"],
]
const FACE_TILE := Vector2(88, 88)
const PART_TILE := Vector2(84, 96)
const PART_ICON_PX := 56
## The panel's share of the window, its size limits, and the window margin it keeps.
const PANEL_SHARE := Vector2(0.86, 0.86)
const PANEL_MIN := Vector2(860, 600)
const PANEL_MAX := Vector2(1640, 1400)
const WINDOW_MARGIN := 24.0
## The preview's width as a share of the panel's height, and its least size.
const PREVIEW_ASPECT := 0.5
const PREVIEW_MIN := Vector2(280, 380)
## The Pose pane's title row and the gap below it, which the stance tiles leave free.
const POSE_TITLE_ROOM := 64.0
const SILHOUETTE_REFRESH_S := 0.25
const THUMBNAIL_DIR := "res://assets/avatar_kit/thumbnails/"

## The working recipe (normalized).
var recipe: Dictionary = {}
## The placed token being edited, or null when making a new avatar.
var token: BoardToken = null
var token_name := ""

var _kit: AvatarKit = null
var _original: Dictionary = {}
var _original_name := ""
var _rng := RandomNumberGenerator.new()
var _preview: AvatarBuilderPreview
var _stance_tiles: AvatarStanceTiles
var _face_icons: AvatarFaceIcons
var _rail: IconRail
var _stack: PaneStack
var _face_rows: Dictionary = {}  # kind -> TileRow
var _swatch_rows: Dictionary = {}  # slot -> AvatarSwatchRow
var _swatch_fields: Dictionary = {}  # slot -> Control (hidden when no part uses the slot)
var _shape_rows: Dictionary = {}  # control -> PropertyRow
var _part_rows: Dictionary = {}  # slot -> TileRow
## Proportion values waiting for the next frame (control -> value).
var _pending: Dictionary = {}
var _silhouettes_in_s := -1.0
var _name_edited := false
var _closing := false

@onready var panel: PanelContainer = %PanelContainer
@onready var content: VBoxContainer = %Content
@onready var header_slot: VBoxContainer = %HeaderSlot
@onready var name_input: LineEdit = %NameInput
@onready var surprise_button: Button = %SurpriseButton
@onready var preview_slot: VBoxContainer = %PreviewSlot
@onready var rail_slot: VBoxContainer = %RailSlot
@onready var pane_slot: Control = %PaneSlot
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton


## Opens the builder for a new avatar under `parent`, starting from `start` (a preset
## recipe when empty) named `start_name` (the preset's name when empty).
static func open_for_new(
	parent: Node, start: Dictionary = {}, start_name: String = ""
) -> AvatarBuilder:
	var builder := _instantiate()
	builder.recipe = start.duplicate(true)
	builder.token_name = start_name
	parent.add_child(builder)
	return builder


## Opens the builder on a placed avatar `target`, previewing edits on it.
static func open_for_token(parent: Node, target: BoardToken) -> AvatarBuilder:
	var builder := _instantiate()
	builder.token = target
	builder.recipe = target.avatar_recipe.duplicate(true)
	builder.token_name = target.token_name
	parent.add_child(builder)
	return builder


static func _instantiate() -> AvatarBuilder:
	var scene := load(SCENE_PATH) as PackedScene
	return scene.instantiate() as AvatarBuilder


## The panel's size in a `window` of that size: PANEL_SHARE of it within PANEL_MIN and
## PANEL_MAX, and never closer than WINDOW_MARGIN to its edges.
static func panel_size(window: Vector2) -> Vector2:
	var wanted := (window * PANEL_SHARE).clamp(PANEL_MIN, PANEL_MAX)
	return wanted.min(window - Vector2.ONE * WINDOW_MARGIN * 2.0).max(Vector2.ZERO)


## The preview's least size in a panel of `panel_px`: PREVIEW_ASPECT of the panel's height
## wide, at most two fifths of its width.
static func preview_size(panel_px: Vector2) -> Vector2:
	var width := minf(panel_px.y * PREVIEW_ASPECT, panel_px.x * 0.4)
	return Vector2(maxf(width, PREVIEW_MIN.x), PREVIEW_MIN.y)


## The property changes a committed edit records as one undo entry
## (GameplayActionHistory.record_compound_property_change): the recipe when it changed and
## the name when it changed; empty when nothing did.
static func undo_changes(
	network_id: String,
	original: Dictionary,
	recipe: Dictionary,
	original_name: String,
	token_name: String,
) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if recipe != original:
		(
			changes
			. append(
				{
					"network_id": network_id,
					"property": "avatar_recipe",
					"old_value": original.duplicate(true),
					"new_value": recipe.duplicate(true),
					"description": "edited avatar",
				}
			)
		)
	if not token_name.is_empty() and token_name != original_name:
		(
			changes
			. append(
				{
					"network_id": network_id,
					"property": "token_name",
					"old_value": original_name,
					"new_value": token_name,
					"description": "edited avatar",
				}
			)
		)
	return changes


func _on_panel_ready() -> void:
	_rng.randomize()
	_kit = AvatarTokenFactory.kit()
	if recipe.is_empty():
		var index := _rng.randi_range(0, AvatarPresets.PRESETS.size() - 1)
		recipe = AvatarPresets.recipe(index)
		if token_name.is_empty():
			token_name = String(AvatarPresets.PRESETS[index].name)
	recipe = AvatarRecipe.normalized(recipe)
	# A recipe from another client may lack a section; the picks write into them.
	for key in ["parts", "colours", "face", "proportions"]:
		if not recipe.get(key) is Dictionary:
			recipe[key] = {}
	_original = recipe.duplicate(true)
	_original_name = token_name
	_name_edited = token != null

	var header := MenuHeader.new()
	header.name = "Header"
	header_slot.add_child(header)
	header.setup(
		"Edit avatar" if token != null else "Make an avatar",
		"Click a pose, a face and colours; the figure follows every pick",
		true
	)
	header.close_requested.connect(cancel)
	name_input.text = token_name
	name_input.text_changed.connect(_on_name_changed)
	name_input.text_submitted.connect(func(_text: String) -> void: confirm())
	surprise_button.icon = IconButton.load_icon("wand")
	surprise_button.pressed.connect(surprise)
	cancel_button.pressed.connect(cancel)
	confirm_button.text = "Save" if token != null else "Add to board"
	confirm_button.pressed.connect(confirm)
	confirm_button.disabled = _kit == null

	_preview = AvatarBuilderPreview.new()
	_preview.name = "Preview"
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_slot.add_child(_preview)
	var turn_hint := Label.new()
	turn_hint.name = "TurnHint"
	turn_hint.text = "Drag to turn"
	turn_hint.theme_type_variation = &"Caption"
	turn_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_slot.add_child(turn_hint)

	_rail = IconRail.new()
	_rail.name = "Rail"
	_rail.vertical = true
	_rail.show_labels = true
	_rail.indicator_at_end = true
	rail_slot.add_child(_rail)
	_stack = PaneStack.new()
	_stack.name = "Panes"
	_stack.slide_from_right = false
	_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pane_slot.add_child(_stack)
	if _kit != null:
		_build_panes()
	_rail.selection_changed.connect(_on_rail_selected)
	_rail.select(&"pose")
	UIManager.register_overlay($ColorRect as Control)
	if _kit != null:
		_preview.set_recipe(recipe)
		_sync_controls()
	get_viewport().size_changed.connect(_fit_to_window)
	pane_slot.resized.connect(_fit_pose_tiles)
	_fit_to_window()


## Sizes the panel and the preview to the window.
func _fit_to_window() -> void:
	var window := get_viewport().get_visible_rect().size
	var panel_px := panel_size(window)
	panel.custom_minimum_size = panel_px
	_preview.custom_minimum_size = preview_size(panel_px)


## Grows the stance tiles so their two rows fill the Pose pane's height.
func _fit_pose_tiles() -> void:
	if _stance_tiles == null:
		return
	var count := _kit.stance_names().size()
	var rows := ceili(float(count) / float(maxi(_stance_tiles.columns, 1)))
	var gap := float(_stance_tiles.get_theme_constant("v_separation"))
	var room := pane_slot.size.y - POSE_TITLE_ROOM - gap * float(maxi(rows - 1, 0))
	_stance_tiles.fit(room / float(maxi(rows, 1)))


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children(content)


## ESC through UIManager's overlay stack.
func request_close() -> void:
	cancel()


func _process(delta: float) -> void:
	if token != null and not is_instance_valid(token) and not _closing:
		# The token left the board under us (removed by the GM): nothing to edit.
		token = null
		cancel()
		return
	if not _pending.is_empty():
		var next := recipe.duplicate(true)
		var values: Dictionary = next.get("proportions", {})
		for control in _pending:
			values[control] = AvatarSurprise.quantize(float(_pending[control]))
		next["proportions"] = values
		_pending.clear()
		if next.proportions != recipe.proportions:
			_apply(next)
	if _silhouettes_in_s >= 0.0:
		_silhouettes_in_s -= delta
		if _silhouettes_in_s < 0.0 and _stance_tiles != null:
			_stance_tiles.refresh(recipe)


# --- picks -------------------------------------------------------------------------------------


func pick_stance(stance: String) -> void:
	var next := recipe.duplicate(true)
	next["stance"] = stance
	_apply(next)


func pick_face(kind: String, index: int) -> void:
	var next := recipe.duplicate(true)
	next["face"][kind] = index
	_apply(next)


func pick_colour(slot: String, index: int) -> void:
	var next := recipe.duplicate(true)
	next["colours"][slot] = index
	_apply(next)


func pick_part(slot: String, part_id: String) -> void:
	var next := recipe.duplicate(true)
	next["parts"][slot] = part_id
	_apply(next)


## Queues a proportion value; the figure takes it on the next frame (quantised).
func set_proportion(control: String, value: float) -> void:
	_pending[control] = value


## A whole new harmonious recipe, and a new name unless the player typed one.
func surprise() -> void:
	if _kit == null:
		return
	var next := AvatarSurprise.recipe(_kit, _rng)
	if not _name_edited:
		token_name = AvatarSurprise.pick_name(_rng)
		name_input.text = token_name
	_apply(next)


## Draws `section` (AvatarSurprise.SECTIONS) again, keeping the rest.
func reroll(section: StringName) -> void:
	if _kit == null:
		return
	_apply(AvatarSurprise.reroll(_kit, recipe, section, _rng))


func confirm() -> void:
	if _closing or _kit == null:
		return
	_closing = true
	var final_name := name_input.text.strip_edges()
	if final_name.is_empty():
		final_name = (
			_original_name if not _original_name.is_empty() else AvatarTokenFactory.DEFAULT_NAME
		)
	if token != null and is_instance_valid(token):
		edit_confirmed.emit(token, _original, recipe.duplicate(true), _original_name, final_name)
	elif token == null:
		create_confirmed.emit(recipe.duplicate(true), final_name)
	animate_out()


func cancel() -> void:
	if _closing:
		return
	_closing = true
	if token != null and is_instance_valid(token) and recipe != _original:
		AvatarTokenFactory.set_recipe(token, _original)
	cancelled.emit()
	animate_out()


func _on_before_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)


# --- applying ----------------------------------------------------------------------------------


## Makes `next` the working recipe, shows it on the preview and the edited token, and puts
## the controls in step (a pick from the bridge or a reroll has no tile of its own).
func _apply(next: Dictionary) -> void:
	var normalized := AvatarRecipe.normalized(next)
	var reshaped: bool = (
		normalized.get("parts") != recipe.get("parts")
		or normalized.get("proportions") != recipe.get("proportions")
	)
	recipe = normalized
	_preview.set_recipe(recipe)
	if token != null and is_instance_valid(token):
		AvatarTokenFactory.set_recipe(token, recipe)
	if reshaped:
		_silhouettes_in_s = SILHOUETTE_REFRESH_S
	_sync_controls()


## Puts every control in step with the recipe, silently.
func _sync_controls() -> void:
	if _stance_tiles != null:
		_stance_tiles.select(StringName(String(recipe.get("stance", ""))))
	var face: Dictionary = recipe.get("face", {})
	_paint_face_icons()
	for kind in _face_rows:
		(_face_rows[kind] as TileRow).select(StringName(str(int(face.get(kind, 0)))))
	var colours: Dictionary = recipe.get("colours", {})
	for slot in _swatch_rows:
		(_swatch_rows[slot] as AvatarSwatchRow).select(int(colours.get(slot, 0)))
	var values: Dictionary = recipe.get("proportions", {})
	for control in _shape_rows:
		(_shape_rows[control] as PropertyRow).set_value_no_signal(float(values.get(control, 0.5)))
	var parts: Dictionary = recipe.get("parts", {})
	for slot in _part_rows:
		(_part_rows[slot] as TileRow).select(StringName(String(parts.get(slot, ""))))
	_refresh_colour_fields()


## Palette slots the chosen parts paint, plus skin and eyes (the face), which always show.
func _used_slots() -> Dictionary:
	var used := {"skin": true, "eyes": true}
	var parts: Dictionary = recipe.get("parts", {})
	for slot in parts:
		var entry: Dictionary = _kit.parts_by_id.get(String(parts[slot]), {})
		for painted in entry.get("slots_used", []):
			used[String(painted)] = true
	return used


func _refresh_colour_fields() -> void:
	var used := _used_slots()
	for slot in _swatch_fields:
		(_swatch_fields[slot] as Control).visible = used.has(slot)


func _on_name_changed(_text: String) -> void:
	_name_edited = true


func _on_rail_selected(id: StringName) -> void:
	_paint_face_icons()
	_stack.show_pane(id)
	_preview.focus_face(id == &"face")


## Repaints the face tiles for the recipe's skin and face while the Face pane shows (a
## repaint of every tile costs a few milliseconds, so a skin pick on the Colours pane leaves
## it for the moment the Face pane opens).
func _paint_face_icons() -> void:
	if _face_icons != null and _rail != null and _rail.selected == &"face":
		_face_icons.update(AvatarFaceIcons.skin_colour(_kit, recipe), recipe.get("face", {}))


# --- panes -------------------------------------------------------------------------------------


func _build_panes() -> void:
	var has_parts := false
	for slot in _kit.parts_by_slot:
		if (_kit.parts_by_slot[slot] as Array).size() > 1:
			has_parts = true
	for entry in PANES:
		var id: StringName = entry[0]
		if id == &"parts" and not has_parts:
			continue
		_rail.add_item(id, entry[1], entry[2])
	_stack.add_pane(&"pose", _pose_pane())
	_stack.add_pane(&"face", _face_pane())
	_stack.add_pane(&"colours", _colours_pane())
	_stack.add_pane(&"shape", _shape_pane())
	if has_parts:
		_stack.add_pane(&"parts", _parts_pane())


## A pane's frame: a title row with the section's reroll button; the caller stacks the
## pane's rows below it.
func _pane(title: String, section: StringName, reroll_tip: String) -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.name = title + "Pane"
	pane.theme_type_variation = &"BoxContainerSpaced"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.name = "TitleRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = "Title"
	label.text = title
	label.theme_type_variation = &"H3"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var reroll_button := IconButton.new()
	reroll_button.name = "Reroll"
	reroll_button.icon_name = "sparkles"
	reroll_button.tooltip_text = reroll_tip
	reroll_button.pressed.connect(reroll.bind(section))
	row.add_child(reroll_button)
	pane.add_child(row)
	return pane


func _caption(text: String) -> Label:
	var label := Label.new()
	label.name = text.replace(" ", "") + "Caption"
	label.text = text
	label.theme_type_variation = &"Caption"
	return label


func _pose_pane() -> Control:
	var pane := _pane("Pose", &"stance", "Another pose")
	_stance_tiles = AvatarStanceTiles.new()
	_stance_tiles.name = "Stances"
	_stance_tiles.columns = 3
	_stance_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stance_tiles.build(_kit, recipe)
	_stance_tiles.selection_changed.connect(func(id: StringName) -> void: pick_stance(String(id)))
	pane.add_child(_stance_tiles)
	return pane


func _face_pane() -> Control:
	var pane := _pane("Face", &"face", "Another face")
	var sheet: Dictionary = _kit.manifest.get("face_sheet", {})
	var names: Dictionary = sheet.get("names", {})
	_face_icons = AvatarFaceIcons.create(
		_kit, AvatarFaceIcons.skin_colour(_kit, recipe), recipe.get("face", {})
	)
	var icons := _face_icons.textures
	var counts := _kit.face_counts()
	for kind in AvatarRecipe.FACE_KINDS:
		var count := int(counts.get(kind, 0))
		if count == 0:
			continue
		pane.add_child(_caption(FACE_LABELS.get(kind, kind.capitalize())))
		var tiles := TileRow.new()
		tiles.name = kind.capitalize() + "Tiles"
		tiles.tile_min_size = FACE_TILE
		tiles.photo_icons = true
		var kind_names: Array = names.get(kind, [])
		var kind_icons: Array = icons.get(kind, [])
		for i in count:
			var cell_name := String(kind_names[i]) if i < kind_names.size() else str(i)
			var icon: Texture2D = kind_icons[i] if i < kind_icons.size() else null
			tiles.add_tile(StringName(str(i)), "", "", cell_name.capitalize(), icon)
		tiles.selection_changed.connect(
			func(id: StringName) -> void: pick_face(kind, int(String(id)))
		)
		_face_rows[kind] = tiles
		pane.add_child(tiles)
	return pane


func _colours_pane() -> Control:
	var pane := _pane("Colours", &"colours", "Another set of colours")
	var sets: Dictionary = _kit.manifest.get("colour_sets", {})
	for slot in AvatarPalette.SLOTS:
		var triples: Array = sets.get(AvatarPalette.SET_FOR_SLOT[slot], [])
		if triples.is_empty():
			continue
		var field := VBoxContainer.new()
		field.name = slot.capitalize() + "Field"
		field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		field.add_child(_caption(COLOUR_LABELS.get(slot, slot.capitalize())))
		var swatches := AvatarSwatchRow.new()
		swatches.name = "Swatches"
		swatches.build(triples)
		swatches.picked.connect(func(index: int) -> void: pick_colour(slot, index))
		field.add_child(swatches)
		pane.add_child(field)
		_swatch_rows[slot] = swatches
		_swatch_fields[slot] = field
	return pane


func _shape_pane() -> Control:
	var pane := _pane("Shape", &"shape", "Another shape")
	var controls: Dictionary = _kit.manifest.get("proportions", {})
	var ordered: Array = []
	for entry in SHAPE_ROWS:
		if controls.has(entry[0]):
			ordered.append(entry)
	var rest: Array = controls.keys()
	rest.sort()
	for control in rest:
		var known := false
		for entry in SHAPE_ROWS:
			known = known or entry[0] == control
		if not known:
			ordered.append([control, String(control).capitalize(), "", ""])
	for entry in ordered:
		var row := PropertyRow.new()
		row.name = String(entry[1]) + "Row"
		row.label = entry[1]
		row.min_value = 0.0
		row.max_value = 1.0
		row.step = AvatarSurprise.STEP
		row.hint_low = entry[2]
		row.hint_high = entry[3]
		row.label_min_width = 72.0
		row.value_changed.connect(func(value: float) -> void: set_proportion(entry[0], value))
		pane.add_child(row)
		_shape_rows[entry[0]] = row
	return pane


func _parts_pane() -> Control:
	var pane := _pane("Parts", &"parts", "Other parts")
	var slots: Array = _kit.parts_by_slot.keys()
	slots.sort()
	for slot in slots:
		var ids: Array = _kit.parts_by_slot[slot]
		if ids.size() <= 1:
			continue
		pane.add_child(_caption(String(slot).capitalize()))
		var tiles := TileRow.new()
		tiles.name = String(slot).capitalize() + "Tiles"
		tiles.tile_min_size = PART_TILE
		tiles.photo_icons = true
		for part_id in ids:
			var path := THUMBNAIL_DIR + String(part_id) + ".png"
			var icon: Texture2D = load(path) if ResourceLoader.exists(path) else null
			var label := String(part_id).trim_prefix(String(slot) + "_").capitalize()
			var tile := tiles.add_tile(
				StringName(String(part_id)), label, "", String(part_id), icon
			)
			tile.add_theme_constant_override("icon_max_width", PART_ICON_PX)
		tiles.selection_changed.connect(
			func(id: StringName) -> void: pick_part(String(slot), String(id))
		)
		_part_rows[slot] = tiles
		pane.add_child(tiles)
	return pane
