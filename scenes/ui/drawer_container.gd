class_name DrawerContainer
extends Control

## Reusable slide-in/slide-out drawer panel with a visible tab handle.
##
## The drawer slides from a screen edge and includes a small tab button that
## remains visible when the drawer is closed, allowing the user to re-open it.
## On first load the drawer is completely hidden; call [method reveal] (or set
## [member start_revealed] to [code]true[/code]) to slide the tab into view.
##
## Subclass this and override [method _on_ready], [method _on_opened], and
## [method _on_closed] to customise behaviour. Add content to
## [member content_container].
##
## The root Control should be anchored full-rect (preset 15) inside its parent.
## The panel and tab live inside a shared "sled" container that slides as a
## single unit, so the two always move in lock-step with no mid-animation gap.

# -- Configuration ----------------------------------------------------------

## Rail mode only: a rail item was chosen. Hosts show the matching pane.
signal pane_requested(id: StringName)

## Rail mode only: a footer item (below the pane items) was pressed. Footer
## items never select a pane or open the drawer; hosts use them for toggles.
signal rail_footer_pressed(id: StringName)

enum DrawerEdge { LEFT, RIGHT }

# -- Board span ----------------------------------------------------------------
# Every drawer is in GROUP. When one starts to open or close, or leaves the tree, it calls
# `on_drawers_moved` on every node in WATCHERS, which reads free_span() to keep clear of the
# open panels (InputHints centres its bar in the free span).
const GROUP := &"drawer_containers"
const WATCHERS := &"drawer_watchers"

# -- Surface -----------------------------------------------------------------
# The panel, its handle and its rail are drawn by theme variations (DrawerPanelLeft/Right,
# DrawerTabLeft/Right, DrawerRailLeft/Right, DrawerMargin; themes/painted_theme_base.gd
# `_define_drawer`), so they follow the leaf the drawer's host root carries: glass over a live
# table (UI_TASTE.md C8), paper where play is stopped (the map tools). Nothing is styled here.

# -- Icon tab padding -------------------------------------------------------
# Standard insets for icon-mode tabs so all icon tabs look consistent.
const _TAB_ICON_PAD_H := 6  # Horizontal (left + right) padding
const _TAB_ICON_PAD_V := 14  # Vertical (top + bottom) padding
## Rail mode: the rail panel's padding each side of its items (tab_width 44 fits 36 px items).
const _RAIL_PAD_H := 4.0
## Detached mode: the rail's distance from the screen's edge, the card's distance from the rail,
## and how far the card slides while it fades (it comes from beside the rail).
const FLOAT_MARGIN := 12.0
const FLOAT_GAP := 12.0
const _FLOAT_SLIDE := 20.0

# -- Tab badge ---------------------------------------------------------------
# Small accent dot drawn at the tab's top-right corner, e.g. for unsaved changes.
const _TAB_BADGE_SIZE := 8.0
const _TAB_BADGE_MARGIN := 4.0

@export var edge: DrawerEdge = DrawerEdge.LEFT
## Width of the sliding content panel.
@export var drawer_width: float = 220.0
## Width of the tab handle button.
@export var tab_width: float = 36.0
## Duration of the slide animation.
@export var slide_duration: float = UiMotion.PANEL_IN_S
## Whether the drawer starts open.
@export var start_open: bool = false
## Whether to play open/close sounds.
@export var play_sounds: bool = true
## Vertical offset from the top of the screen for the tab handle.
@export var tab_top_margin: float = 12.0
## Whether the drawer tab is visible on ready. When false (default) the
## drawer is completely off-screen until [method reveal] is called.
@export var start_revealed: bool = false
## Rail mode. When non-empty the single tab handle is replaced by an IconRail
## with one item per entry: {"id": StringName, "icon": String, "tooltip":
## String}. Set in _on_ready(). Clicking an item opens the drawer on that pane
## (pane_requested); clicking the active item closes the drawer, subject to
## _can_close_from_tab(). Rail width is tab_width (44 fits 36 px items).
@export var rail_items: Array[Dictionary] = []
## In fit mode, the most of the board's height the panel may take (1.0: all but the margins); a
## taller pane scrolls inside it.
@export_range(0.3, 1.0) var max_height_fraction: float = 1.0
## Rail mode: extra items drawn under the pane items after a gap, outside the
## single-select group. Same entry shape as rail_items.
@export var rail_footer_items: Array[Dictionary] = []
## Rail mode: each item's side (IconRail.item_size) and the step between two groups of items.
@export var rail_item_size: float = IconRail.ITEM_SIZE
@export var rail_group_gap: float = IconRail.GROUP_GAP
## Rail mode: a state-colour chip behind the active item (IconRail.chip).
@export var rail_chip: bool = false
## Detached mode (the map tools, card ui-authoring3), left edge only: the rail is a rounded capsule
## that stands still FLOAT_MARGIN in from the screen's edge, and the panel is a separate rounded
## card FLOAT_GAP to its right that fades and slides in from beside the rail when the drawer opens
## and out when it closes. No flat edge of one meets a curve of the other. Needs fit_height (the
## card is as tall as its content) and the DrawerCardFloat / DrawerRailFloat theme variations.
@export var rail_detached: bool = false
## The theme variation of the margin the content stands in: DrawerMargin (12 px) or
## DrawerMarginRoomy (16 px). Set in _on_ready().
@export var margin_variation: StringName = &"DrawerMargin"
## Fit mode: the panel is a card as tall as its content (the host reports it with
## fit_panel_height()), level with the rail's top, and the board shows below it. Off: the panel
## runs the whole edge. Set in _on_ready().
@export var fit_height: bool = false

# -- Public state ------------------------------------------------------------

## Whether the drawer is currently open (panel visible).
var is_open: bool = false

## Whether the tab handle is on-screen (revealed). The drawer starts fully
## hidden and must be revealed before the tab becomes visible.
var is_revealed: bool = false

## The container where subclasses should add their content.
var content_container: VBoxContainer

# -- Tab customisation -------------------------------------------------------

## Text shown on the tab handle. Set in [method _on_ready] or at any time.
var tab_text: String = "":
	set(value):
		tab_text = value
		if _tab_label:
			_tab_label.text = value
			_tab_label.visible = value != "" and tab_icon == null

## Icon shown on the tab handle instead of text. Set in [method _on_ready] or
## at any time. When set, the text label is hidden and the icon is displayed.
var tab_icon: Texture2D = null:
	set(value):
		tab_icon = value
		if _tab_icon_rect:
			_tab_icon_rect.texture = value
			_tab_icon_rect.visible = value != null
		if _tab_label:
			_tab_label.visible = value == null and tab_text != ""

# -- Internals --------------------------------------------------------------

var _sled: Control  ## Container that slides panel + tab as one unit
var _panel: PanelContainer  ## The sliding content panel
## Detached mode: the card's holder, which carries the slide and the fade so the card's own
## modulate stays free for the host (CardDimmer).
var _slot: Control
var _margin: MarginContainer  ## The content's margin inside the panel
var _fit_px: float = 0.0  ## Fit mode: the content's height the host last reported, 0 for none
var _tab_button: Button  ## The clickable tab handle
var _tab_label: Label
var _tab_icon_rect: TextureRect
var _tab_badge: Panel  ## Accent dot overlaid on the tab handle
var _rail: IconRail  ## Rail mode only
var _footer_rail: IconRail  ## Rail mode only, null without footer items
var _rail_panel: PanelContainer  ## Rail mode only: styled backdrop behind the rail
var _tab_control: Control  ## Whichever handle is in use: _tab_button or _rail_panel
var _last_rail_id: StringName = &""  ## Pane to reopen on when nothing is selected
var _pending_tab_tooltip: String = ""  ## Set via set_tab_tooltip() before the tab button exists
var _pending_tab_badge: bool = false  ## Set via set_tab_badge() before the tab badge exists
var _slide_tween: Tween
var _height_tween: Tween  ## Fit mode: the card's height easing to a new pane's
var _is_animating: bool = false
var _closing_from_open: bool = false  ## True when closing/concealing from an open state

# -- Lifecycle ---------------------------------------------------------------


func _ready() -> void:
	# Root Control is full-rect and click-through
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	tree_exiting.connect(_on_tree_exiting)

	_build_ui()

	# Let subclasses configure properties (drawer_width, tab_text, rail_items,
	# etc.) and populate the content_container.
	_on_ready()

	# The handle depends on rail_items, so it is built after _on_ready().
	_build_tab()
	_apply_panel_style()
	_attach_card_slot()

	# Re-apply panel size, tab style, sled layout, and positions AFTER
	# _on_ready(), because the subclass may have changed drawer_width,
	# edge, or other configuration.
	_panel.size.x = drawer_width
	_apply_tab_style()
	_layout_sled()
	_apply_initial_position()
	# The parent may have no size yet (its anchors resolve on the first layout): take its height
	# once it has one, so the panel and the handle's frame always run the whole edge.
	_on_parent_resized.call_deferred()


## Override in subclasses for custom initialisation.
func _on_ready() -> void:
	pass


## Override in subclasses — called after the open animation finishes.
func _on_opened() -> void:
	pass


## Override in subclasses — called after the close animation finishes.
func _on_closed() -> void:
	pass


# -- Public API --------------------------------------------------------------


## Reveal the tab handle (slide it into view from off-screen).
## Does nothing if already revealed.
func reveal() -> void:
	if is_revealed:
		return
	is_revealed = true
	_closing_from_open = false
	_animate_to_state()


## Hide the tab handle completely off-screen.
func conceal() -> void:
	if not is_revealed and not is_open:
		return
	_closing_from_open = is_open
	is_open = false
	is_revealed = false
	_remember_rail_selection()
	_animate_to_state()


## Open the drawer with animation. In rail mode with nothing selected, the
## last pane (or the first item) is selected and pane_requested is emitted.
func open() -> void:
	if is_open or _is_animating:
		return
	is_open = true
	is_revealed = true
	_closing_from_open = false
	_animate_to_state()
	if _rail and _rail.selected.is_empty():
		var id := _default_rail_id()
		if not id.is_empty():
			_rail.select(id)
			pane_requested.emit(id)


## Close the drawer with animation (tab stays visible).
func close() -> void:
	if not is_open or _is_animating:
		return
	_closing_from_open = true
	is_open = false
	_remember_rail_selection()
	_animate_to_state()


func _remember_rail_selection() -> void:
	if _rail and not _rail.selected.is_empty():
		_last_rail_id = _rail.selected
		_rail.deselect()


func _default_rail_id() -> StringName:
	if _rail.has_item(_last_rail_id):
		return _last_rail_id
	if rail_items.is_empty():
		return &""
	return rail_items[0]["id"]


## The x span of `viewport`'s canvas that no open drawer in it covers, as (left, right).
static func free_span(viewport: Viewport) -> Vector2:
	var rect := viewport.get_visible_rect()
	var span := Vector2(rect.position.x, rect.end.x)
	for node in viewport.get_tree().get_nodes_in_group(GROUP):
		var drawer := node as DrawerContainer
		if drawer.get_viewport() != viewport or not drawer.is_open:
			continue
		if drawer.is_queued_for_deletion() or not drawer.is_visible_in_tree():
			continue
		var covered := drawer.covered_span()
		if drawer.edge == DrawerEdge.LEFT:
			span.x = maxf(span.x, covered.y)
		else:
			span.y = minf(span.y, covered.x)
	return span


## The x span of the canvas this drawer's panel and handle cover when it is open, as
## (left, right): where the slide is heading, not where it is mid-slide.
func covered_span() -> Vector2:
	var rect := get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	var width := drawer_width + tab_width
	if rail_detached:
		width = _detached_width() + FLOAT_GAP
	if edge == DrawerEdge.LEFT:
		return Vector2(rect.position.x, rect.position.x + width)
	return Vector2(rect.end.x - width, rect.end.x)


func _notify_watchers() -> void:
	if is_inside_tree():
		get_tree().call_group(WATCHERS, &"on_drawers_moved")


## A drawer freed while open (leaving play with it open) frees its span: the watchers look
## again once it is out of the tree and its group.
func _on_tree_exiting() -> void:
	if is_open:
		get_tree().call_group.call_deferred(WATCHERS, &"on_drawers_moved")


## Toggle the drawer open or closed.
func toggle() -> void:
	if is_open:
		close()
	else:
		open()


## Show or hide the small accent dot on the tab (e.g. unsaved changes).
## In rail mode `false` clears every item badge; `true` is ignored because
## badges are per item there (see set_rail_badge).
func set_tab_badge(badge_visible: bool) -> void:
	_pending_tab_badge = badge_visible
	if _tab_badge:
		_tab_badge.visible = badge_visible
	if _rail and not badge_visible:
		for item in rail_items:
			_rail.set_badge(item["id"], false)


## Rail mode: badge one item (a pane with unsaved edits).
func set_rail_badge(id: StringName, on: bool) -> void:
	if _rail:
		_rail.set_badge(id, on)


## Rail mode: tint a pane item as on or off (a tool that stays active while its pane is
## closed).
func set_rail_item_active(id: StringName, on: bool) -> void:
	if _rail:
		_rail.set_item_active(id, on)


## Rail mode: tint a footer item as on or off.
func set_footer_item_active(id: StringName, on: bool) -> void:
	if _footer_rail:
		_footer_rail.set_item_active(id, on)


## Rail mode: update a footer item's tooltip (e.g. a toggle whose meaning
## flips with its state).
func set_footer_item_tooltip(id: StringName, text: String) -> void:
	if _footer_rail:
		_footer_rail.set_item_tooltip(id, text)


## Rail mode: enable or disable a footer item (e.g. Undo with nothing to undo).
func set_footer_item_enabled(id: StringName, on: bool) -> void:
	if _footer_rail:
		_footer_rail.set_enabled(id, on)


## Rail mode: badge a footer item (e.g. Save while there are unsaved changes), and with `word` say
## it in a word under the icon while it is on, so the cue is not colour or a dot alone.
func set_footer_badge(id: StringName, on: bool, word: String = "") -> void:
	if _footer_rail:
		_footer_rail.set_badge(id, on)
		_footer_rail.set_item_caption(id, word if on else "")


## Rail mode: enable or disable a pane item (a tool that is not available yet).
func set_rail_item_enabled(id: StringName, on: bool) -> void:
	if _rail:
		_rail.set_enabled(id, on)


## Rail mode: update a pane item's tooltip (e.g. saying why it is disabled).
func set_rail_item_tooltip(id: StringName, text: String) -> void:
	if _rail:
		_rail.set_item_tooltip(id, text)


## Tooltip shown when hovering the tab handle (single-tab mode only; rail
## items carry their own tooltips).
func set_tab_tooltip(text: String) -> void:
	_pending_tab_tooltip = text
	if _tab_button:
		_tab_button.tooltip_text = text


## Subclasses may veto a close initiated from the tab button (e.g. to prompt
## about unsaved changes). Programmatic close() is never vetoed.
func _can_close_from_tab() -> bool:
	return true


# -- UI Construction ---------------------------------------------------------


func _build_ui() -> void:
	# Re-sync when the parent resizes
	resized.connect(_on_parent_resized)

	# -- Sled container (moves panel + tab as one unit) ----------------------
	_sled = Control.new()
	_sled.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sled)

	# -- Content panel -------------------------------------------------------
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size = Vector2(drawer_width, size.y)
	_sled.add_child(_panel)

	_margin = MarginContainer.new()
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_margin.theme_type_variation = margin_variation
	_panel.add_child(_margin)

	content_container = VBoxContainer.new()
	content_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.theme_type_variation = &"BoxContainerSpaced"
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.add_child(content_container)


func _build_tab() -> void:
	if rail_items.is_empty():
		_build_tab_button()
		_tab_control = _tab_button
	else:
		_build_rail()
		_tab_control = _rail_panel


func _build_tab_button() -> void:
	# -- Tab button ----------------------------------------------------------
	_tab_button = Button.new()
	_tab_button.custom_minimum_size = Vector2(tab_width, 64)
	_tab_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_tab_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tab_button.focus_mode = Control.FOCUS_NONE
	# Silence the default auto-connected click sound; we play open/close instead
	_tab_button.set_meta("ui_silent", true)
	_tab_button.pressed.connect(_on_tab_pressed)

	# Style the tab for visibility against the dark viewport
	_apply_tab_style()

	_sled.add_child(_tab_button)

	_tab_label = Label.new()
	_tab_label.text = tab_text
	_tab_label.theme_type_variation = &"Body"
	_tab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_tab_button.add_child(_tab_label)

	_tab_icon_rect = TextureRect.new()
	_tab_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tab_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tab_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor full-rect with padding so the icon doesn't fill the entire tab.
	_tab_icon_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_tab_icon_rect.offset_left = _TAB_ICON_PAD_H
	_tab_icon_rect.offset_right = -_TAB_ICON_PAD_H
	_tab_icon_rect.offset_top = _TAB_ICON_PAD_V
	_tab_icon_rect.offset_bottom = -_TAB_ICON_PAD_V
	# Tint the icon with the theme's accent colour (ember under the glass theme).
	_tab_icon_rect.self_modulate = ThemeColors.of(self, ThemeColors.ACCENT)
	_tab_icon_rect.visible = tab_icon != null
	_tab_icon_rect.texture = tab_icon
	_tab_button.add_child(_tab_icon_rect)

	# Unsaved-changes dot. Hidden until a subclass calls set_tab_badge(true).
	_tab_badge = Panel.new()
	_tab_badge.name = "TabBadge"
	_tab_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_badge.custom_minimum_size = Vector2(_TAB_BADGE_SIZE, _TAB_BADGE_SIZE)
	_tab_badge.size = Vector2(_TAB_BADGE_SIZE, _TAB_BADGE_SIZE)
	_tab_badge.theme_type_variation = &"Badge"
	_tab_badge.visible = false
	_tab_button.add_child(_tab_badge)

	# Apply any tooltip/badge set by a subclass from _on_ready(), before these
	# nodes existed (set_tab_tooltip()/set_tab_badge() recorded them as pending).
	_tab_button.tooltip_text = _pending_tab_tooltip
	_tab_badge.visible = _pending_tab_badge


func _build_rail() -> void:
	# The rail is its items and the panel's side padding, never narrower: the sled places the
	# panel by tab_width, so a rail wider than it would hang past its own frame.
	tab_width = maxf(tab_width, rail_item_size + _RAIL_PAD_H * 2.0)
	_rail_panel = PanelContainer.new()
	_rail_panel.name = "RailPanel"
	_rail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_rail_panel.custom_minimum_size = Vector2(tab_width, 0)
	_sled.add_child(_rail_panel)

	_rail = IconRail.new()
	_rail.name = "Rail"
	_rail.vertical = true
	_rail.auto_select = false
	# The indicator sits on the edge facing the panel, joining the item to the pane it opened,
	# as the avatar builder's rail does. On the outer edge it ran to the rail's rim and read as
	# cut there (2026-10-10 once-over).
	_rail.indicator_at_end = edge == DrawerEdge.RIGHT or rail_detached
	_rail.item_size = rail_item_size
	_rail.chip = rail_chip
	# An item's optional "group" breaks the rail into runs of related tools: a gap where it changes.
	var group: StringName = &""
	for item in rail_items:
		var item_group := StringName(item.get("group", &""))
		if _rail.get_child_count() > 0 and item_group != group:
			_rail.add_gap(rail_group_gap)
		group = item_group
		_rail.add_item(item["id"], item["icon"], item.get("tooltip", ""))
		if item.has("key"):
			_rail.set_item_key(item["id"], String(item["key"]), String(item.get("digit", "")))
	_rail.item_pressed.connect(_on_rail_item_pressed)
	var column := VBoxContainer.new()
	column.name = "RailColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_panel.add_child(column)
	column.add_child(_rail)
	if rail_footer_items.is_empty():
		return
	_footer_rail = IconRail.new()
	_footer_rail.name = "FooterRail"
	_footer_rail.vertical = true
	_footer_rail.auto_select = false
	_footer_rail.item_size = rail_item_size
	for item in rail_footer_items:
		_footer_rail.add_item(item["id"], item["icon"], item.get("tooltip", ""))
	_footer_rail.item_pressed.connect(_on_rail_footer_pressed)
	var gap := Control.new()
	gap.name = "FooterGap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(0, IconRail.GROUP_GAP + IconRail.ITEM_GAP)
	column.add_child(gap)
	column.add_child(_footer_rail)


func _apply_panel_style() -> void:
	# The panel and the content's margin take their theme variations by the edge, which a subclass
	# may set in _on_ready(), so this runs after it.
	if rail_detached:
		_panel.theme_type_variation = &"DrawerCardFloat"
	else:
		_panel.theme_type_variation = _edge_variation("DrawerCard" if fit_height else "DrawerPanel")
	_margin.theme_type_variation = margin_variation


func _apply_tab_style() -> void:
	# Badge position depends on tab_width, which a subclass may change in
	# _on_ready(). This runs again afterwards, so it lands on the final width.
	# Null on the first call, made from _build_tab_button() before the badge
	# is created.
	if _tab_badge:
		_tab_badge.position = Vector2(
			tab_width - _TAB_BADGE_SIZE - _TAB_BADGE_MARGIN, _TAB_BADGE_MARGIN
		)
	if _tab_button:
		_tab_button.theme_type_variation = _edge_variation("DrawerTab")
	if _rail_panel:
		_rail_panel.theme_type_variation = (
			&"DrawerRailFloat" if rail_detached else _edge_variation("DrawerRail")
		)


## The theme variation `base` has for this drawer's edge ("DrawerPanelLeft", "DrawerTabRight").
func _edge_variation(base: String) -> StringName:
	return StringName(base + ("Left" if edge == DrawerEdge.LEFT else "Right"))


## Fit mode: tells the drawer how tall its content wants the panel (the margin, the head of the
## pane and the pane itself). The panel takes that, or the room the window leaves, whichever is
## less.
func fit_panel_height(content_px: float) -> void:
	_fit_px = content_px
	_apply_panel_height(true)


## The panel's height and top: the whole edge, or in fit mode its content's, below the rail's top.
## With `animate` and the drawer open, a change of height eases over UiMotion.STATE_S; under
## Reduce motion (and at once for a resize or the first fit) it is a cut.
func _apply_panel_height(animate: bool = false) -> void:
	if _panel == null:
		return
	if _height_tween and _height_tween.is_valid():
		_height_tween.kill()
	if not fit_height:
		_panel.size.y = size.y
		_panel.position.y = 0.0
		return
	var room := minf(maxf(size.y - tab_top_margin * 2.0, 0.0), size.y * max_height_fraction)
	var target := minf(_fit_px, room) if _fit_px > 0.0 else room
	_panel.position.y = tab_top_margin
	if animate and is_open and not UiMotion.reduced() and not is_equal_approx(_panel.size.y, target):
		_height_tween = create_tween().set_trans(UiMotion.ARRIVE_TRANS).set_ease(Tween.EASE_OUT)
		_height_tween.tween_property(_panel, "size:y", target, UiMotion.STATE_S)
		return
	_panel.size.y = target


func _on_parent_resized() -> void:
	if _sled:
		_sled.size.y = size.y
		_apply_panel_height()
		# Right-edge drawers depend on size.x for their sled position.
		if not _is_animating:
			_sled.position.x = _get_sled_x()


# -- Sled Layout -------------------------------------------------------------


## Detached mode: the width from the screen's edge to the card's far side.
func _detached_width() -> float:
	return FLOAT_MARGIN + tab_width + FLOAT_GAP + drawer_width


## Detached mode: where the card stands when open, in the sled.
func _card_x() -> float:
	return FLOAT_MARGIN + tab_width + FLOAT_GAP


## Detached mode: the card goes into its own slot, a sibling of the rail in the sled, so the slot
## can slide and fade while the card's own modulate stays the host's.
func _attach_card_slot() -> void:
	if not rail_detached:
		return
	_slot = Control.new()
	_slot.name = "CardSlot"
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sled.add_child(_slot)
	_sled.remove_child(_panel)
	_slot.add_child(_panel)
	# The rail is drawn over the slot, so a card that slides out passes from behind it.
	_sled.move_child(_slot, 0)


## Arrange the panel and tab at fixed positions inside the sled.
## Called once after _on_ready() so subclass config is already applied.
func _layout_sled() -> void:
	_sled.size = Vector2(drawer_width + tab_width, size.y)
	_sled.position.y = 0

	if rail_detached:
		_sled.size = Vector2(_detached_width(), size.y)
		_tab_control.position = Vector2(FLOAT_MARGIN, tab_top_margin)
		_slot.size = Vector2(drawer_width, size.y)
		_panel.position = Vector2.ZERO
		_panel.size = Vector2(drawer_width, size.y)
		_set_card_state(is_open)
		_apply_panel_height()
		return

	if edge == DrawerEdge.LEFT:
		_panel.position = Vector2(0, 0)
		_tab_control.position = Vector2(drawer_width, tab_top_margin)
	else:
		_tab_control.position = Vector2(0, tab_top_margin)
		_panel.position = Vector2(tab_width, 0)

	_panel.size = Vector2(drawer_width, size.y)
	_apply_panel_height()


# -- Position Helpers --------------------------------------------------------


func _apply_initial_position() -> void:
	if start_open:
		is_open = true
		is_revealed = true
	elif start_revealed:
		is_revealed = true

	_sled.position.x = _get_sled_x()
	_set_card_state(is_open)
	if is_open:
		_notify_watchers()


## Detached mode: puts the card slot at its open (or closed) rest, with no motion.
func _set_card_state(open_now: bool) -> void:
	if _slot == null:
		return
	_slot.visible = open_now
	_slot.modulate.a = 1.0 if open_now else 0.0
	_slot.position.x = _card_x() if open_now else _card_x() - _FLOAT_SLIDE


func _get_sled_x() -> float:
	## Sled X for the current state.
	## The sled holds both the panel and the tab, so moving it slides
	## both in perfect lock-step.
	if rail_detached:
		# The rail stands still once revealed; only an unrevealed drawer waits off-screen.
		return 0.0 if is_revealed else -(_detached_width() + 20.0)
	if edge == DrawerEdge.LEFT:
		if is_open:
			return 0.0
		if is_revealed:
			return -drawer_width
		return -(drawer_width + tab_width + 20)
	if is_open:
		return size.x - drawer_width - tab_width
	if is_revealed:
		return size.x - tab_width
	return size.x + 20


# -- Animation ---------------------------------------------------------------


func _animate_to_state() -> void:
	if _slide_tween:
		_slide_tween.kill()

	_is_animating = true

	var target := _get_sled_x()

	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(UiMotion.ARRIVE_TRANS)
	if rail_detached:
		_animate_detached(target)
	elif UiMotion.reduced():
		# Reduce motion: no travel. Opening fades the sled in where it stands; closing cuts.
		_sled.position.x = target
		_sled.modulate.a = 0.0 if is_open else 1.0
		_slide_tween.tween_property(_sled, "modulate:a", 1.0, UiMotion.FADE_ONLY_S)
	else:
		_slide_tween.tween_property(_sled, "position:x", target, slide_duration)
	_slide_tween.finished.connect(_on_slide_finished, CONNECT_ONE_SHOT)
	_notify_watchers()

	if play_sounds:
		if is_open:
			AudioManager.play(&"open")
		elif is_revealed:
			AudioManager.play(&"close")


## Detached mode's motion, added to the running tween: the whole sled slides in from off-screen on
## reveal (the rail then stands still), and the card fades and slides from beside the rail on open,
## the reverse on close. Under Reduce motion nothing travels: the sled cuts, the card fades in and
## cuts out (the panel's own rule above).
func _animate_detached(sled_x: float) -> void:
	var reduced := UiMotion.reduced()
	if reduced:
		_sled.position.x = sled_x
	elif not is_equal_approx(_sled.position.x, sled_x):
		_slide_tween.tween_property(_sled, "position:x", sled_x, slide_duration)
	if _slot == null:
		return
	var rest := _card_x()
	if is_open:
		if not _slot.visible:
			_slot.visible = true
			_slot.modulate.a = 0.0
			_slot.position.x = rest if reduced else rest - _FLOAT_SLIDE
		_slide_tween.parallel().tween_property(_slot, "modulate:a", 1.0, slide_duration)
		if not reduced:
			_slide_tween.parallel().tween_property(_slot, "position:x", rest, slide_duration)
	elif reduced:
		_set_card_state(false)
		# A tween with nothing to do never finishes, which would leave the drawer "animating".
		_slide_tween.tween_interval(0.01)
	else:
		var out := UiMotion.PANEL_OUT_S
		_slide_tween.parallel().tween_property(_slot, "modulate:a", 0.0, out)
		_slide_tween.parallel().tween_property(_slot, "position:x", rest - _FLOAT_SLIDE, out)
		_slide_tween.tween_callback(_set_card_state.bind(false))


func _on_slide_finished() -> void:
	_is_animating = false
	if is_open:
		_on_opened()
	elif _closing_from_open:
		_closing_from_open = false
		_on_closed()


# -- Input -------------------------------------------------------------------


func _on_tab_pressed() -> void:
	if is_open and not _can_close_from_tab():
		return
	toggle()


func _on_rail_item_pressed(id: StringName) -> void:
	if not is_open:
		if _is_animating:
			return
		_rail.select(id)
		pane_requested.emit(id)
		open()
		return
	if id == _rail.selected:
		if _can_close_from_tab():
			close()
		return
	_rail.select(id)
	AudioManager.play(&"tick")
	pane_requested.emit(id)


func _on_rail_footer_pressed(id: StringName) -> void:
	rail_footer_pressed.emit(id)
