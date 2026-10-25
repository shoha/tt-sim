extends GutTest

## ShadowGutter (scenes/ui/primitives/shadow_gutter.gd): the root cause of the clipped button
## shadows and the audit that finds every place it happens. The owner (2026-10-25) saw Verify in
## the collections card lose its shadow at the left edge of the panel and said it happens in
## other places too. A raised button's StyleBoxFlat shadow lies outside the button's rect; a
## ScrollContainer (or any clip_contents or clip_children control) cuts it off when the button
## sits flush with its edge.
##
## Two parts:
##  1. the constants (SIDE, TOP, BOTTOM) are the largest shadow and focus-ring extents of every
##     Button variation of both themes in every state, no more, so a theme change that grows a
##     shadow fails here with the new number;
##  2. every screen, sheet and dialog that hosts Buttons inside a clipping container is
##     instantiated and walked: no Button may have a clipping ancestor closer than its shadow.

const TITLE_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const NEW_MAP_SCENE := preload("res://scenes/states/authoring/new_map_dialog.tscn")
const PAUSE_SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")
const CONFIRM_SCENE := preload("res://scenes/ui/confirmation_dialog.tscn")
const PLAY_SCENE := preload("res://scenes/states/playing/gameplay_menu.tscn")
const HELP_SCENE := preload("res://scenes/ui/help_overlay.tscn")
const UPDATE_SCENE := preload("res://scenes/ui/update_dialog.tscn")
const ADD_PACK_SCENE := preload("res://scenes/ui/add_pack_dialog.tscn")
const LEVEL_PICKER_SCENE := preload("res://scenes/ui/level_picker_dialog.tscn")
const PLAYER_SELECTION_SCENE := preload("res://scenes/ui/player_selection_dialog.tscn")
const World := preload("res://tests/unit/library_world.gd")
const Zip := preload("res://tests/unit/zip_builder.gd")
const Fixture := preload("res://tests/unit/designer_fixture.gd")
const THEMES: Array[String] = [
	"res://themes/generated/paper_theme.tres", "res://themes/generated/glass_theme.tres"
]
const AVATAR_RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
const ROOT := "user://test_shadow_gutter"
const CANVAS := Vector2(1280.0, 720.0)
const SETTLE_S := 3.0

var _host: SubViewport
var _scene: Node
var _old_scene: Node
var _saved: Dictionary = {}


func before_all() -> void:
	_saved = {
		"settings": LibraryRegistry.settings_path,
		"official": LibraryRegistry.official_root,
		"user": LibraryRegistry.user_root,
		"levels": LevelManager.levels_dir,
	}


func after_all() -> void:
	LibraryRegistry.settings_path = _saved["settings"]
	LibraryRegistry.official_root = _saved["official"]
	LibraryRegistry.user_root = _saved["user"]
	LevelManager.levels_dir = _saved["levels"]
	LibraryImportFlow.serve_palette = true
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "ShadowGutterScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	_host = SubViewport.new()
	_host.size = Vector2i(CANVAS)
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_scene.add_child(_host)


func after_each() -> void:
	for node in _host.find_children("ColorRect", "ColorRect", true, false):
		UIManager.unregister_overlay(node as Control)
	for node in get_tree().root.get_children():
		if node is ConfirmationDialogUI or node is LibraryManager or node is LibraryInstallCard:
			node.free()
	get_tree().current_scene = _old_scene
	_scene.queue_free()


# ---- the constants against the themes ----


func _widest(into: Dictionary, extents: Dictionary) -> void:
	for side: String in into:
		into[side] = maxf(into[side], extents[side])


## The gutter is the largest extent of the themes' buttons in every state: the raised buttons
## (shadow 10, dropped 4; the glass focus ring 8), the lifted Card (18, dropped 8) and the plain
## focus ring (4 on paper, 8 on glass) each have a kind, equal to what the themes draw.
func test_the_gutter_is_the_largest_shadow_extent_of_every_button_in_both_themes() -> void:
	var raised := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var card := raised.duplicate()
	var paper_ring := raised.duplicate()
	var glass_ring := raised.duplicate()
	var seen := 0
	for path in THEMES:
		var theme := load(path) as Theme
		assert_not_null(theme, path)
		var variations: Array[StringName] = [&"Button"]
		for type_name in theme.get_type_list():
			if theme.get_type_variation_base(type_name) == &"Button":
				variations.append(type_name)
		for variation in variations:
			var extents := ShadowGutter.extents_in_theme(theme, variation)
			seen += 1
			if variation == &"Card":
				_widest(card, extents)
			else:
				_widest(raised, extents)
			if variation == &"ListRow" or variation == &"Tile":
				_widest(glass_ring if path.contains("glass") else paper_ring, extents)
	assert_gt(seen, 20, "the variations of both themes were found")
	assert_eq(raised["left"], float(ShadowGutter.SIDE), "raised left %s" % [raised])
	assert_eq(raised["right"], float(ShadowGutter.SIDE), "raised right %s" % [raised])
	assert_eq(raised["top"], float(ShadowGutter.TOP), "raised top %s" % [raised])
	assert_eq(raised["bottom"], float(ShadowGutter.BOTTOM), "raised bottom %s" % [raised])
	assert_eq(card["left"], float(ShadowGutter.CARD_SIDE), "card left %s" % [card])
	assert_eq(card["right"], float(ShadowGutter.CARD_SIDE), "card right %s" % [card])
	assert_eq(card["top"], float(ShadowGutter.CARD_TOP), "card top %s" % [card])
	assert_eq(card["bottom"], float(ShadowGutter.CARD_BOTTOM), "card bottom %s" % [card])
	for side: String in paper_ring:
		assert_eq(paper_ring[side], float(ShadowGutter.RING_PX), "paper ring %s" % side)
		assert_eq(glass_ring[side], float(ShadowGutter.GLASS_RING_PX), "glass ring %s" % side)


func test_wrap_gives_a_scroll_the_room_of_its_kind() -> void:
	var cases := {
		ShadowGutter.Kind.BUTTON:
		[ShadowGutter.SIDE, ShadowGutter.TOP, ShadowGutter.SIDE, ShadowGutter.BOTTOM],
		ShadowGutter.Kind.CARD:
		[
			ShadowGutter.CARD_SIDE,
			ShadowGutter.CARD_TOP,
			ShadowGutter.CARD_SIDE,
			ShadowGutter.CARD_BOTTOM
		],
		ShadowGutter.Kind.RING: [4, 4, 4, 4],
		ShadowGutter.Kind.GLASS_RING: [8, 8, 8, 8],
	}
	for kind: int in cases:
		var scroll := ShadowGutter.wrap(ScrollContainer.new(), kind as ShadowGutter.Kind)
		var variation := ShadowGutter.variation_of(kind as ShadowGutter.Kind)
		assert_eq(scroll.theme_type_variation, variation)
		var want: Array = cases[kind]
		assert_eq(ShadowGutter.extra_height(kind as ShadowGutter.Kind), float(want[1] + want[3]))
		scroll.free()
		# Both themes define the variation, with the room the constants name.
		for path in THEMES:
			var theme := load(path) as Theme
			assert_true(theme.has_stylebox(&"panel", variation), "%s: %s" % [path, variation])
			var box := theme.get_stylebox(&"panel", variation)
			assert_eq(box.get_margin(SIDE_LEFT), float(want[0]), path)
			assert_eq(box.get_margin(SIDE_TOP), float(want[1]), path)
			assert_eq(box.get_margin(SIDE_RIGHT), float(want[2]), path)
			assert_eq(box.get_margin(SIDE_BOTTOM), float(want[3]), path)


func test_outset_keeps_the_content_where_it_was_and_reaches_the_clip_out() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(100, 60)
	scroll.add_child(rows)
	var holder := ShadowGutter.outset(scroll, ShadowGutter.Kind.RING)
	var column := VBoxContainer.new()
	column.size = Vector2(300, 200)
	_host.add_child(column)
	column.add_child(holder)
	await wait_process_frames(3)
	assert_eq(holder.size.x, 300.0, "the holder fills the column")
	var room := ShadowGutter.margins(ShadowGutter.Kind.RING)
	assert_almost_eq(scroll.size.x, 300.0 + room.x + room.z, 0.5, "the clip reaches out")
	assert_almost_eq(rows.global_position.x, holder.global_position.x, 0.5, "the content stays")
	assert_almost_eq(holder.get_combined_minimum_size().y, 60.0, 0.5, "and its need is the same")
	column.free()


func test_the_audit_finds_a_button_flush_with_a_clipping_scroll_and_passes_a_wrapped_one() -> void:
	for wrapped in [false, true]:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(300, 200)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		if wrapped:
			ShadowGutter.wrap(scroll)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
		var button := Button.new()
		button.text = "Verify"
		button.theme_type_variation = &"Secondary"
		content.add_child(button)
		var holder := Control.new()
		holder.add_child(scroll)
		_host.add_child(holder)
		await wait_process_frames(3)
		var found := ShadowGutter.violations(holder)
		if wrapped:
			assert_eq(found, [], "a wrapped scroll keeps every shadow")
		else:
			assert_gt(found.size(), 0, "a flush button is caught")
			assert_true("left" in "".join(found), str(found))
		holder.free()


# ---- the screens ----


func _audit(what: String, node: Node, settle: bool = true) -> void:
	if settle:
		await wait_process_frames(2)
		for tween in get_tree().get_processed_tweens():
			tween.custom_step(SETTLE_S)
		await wait_process_frames(3)
	var found := ShadowGutter.violations(node)
	assert_eq(found.size(), 0, "%s: %s" % [what, "\n".join(found)])


func test_the_collections_manager_and_its_cards_keep_every_shadow() -> void:
	World.remove_tree(ROOT)
	var paths := World.build(ROOT)
	World.write_alien(ROOT + "/source/alienworld", "0.3.1", [], false)
	World.write_alien(paths["user"] + "/alienworld_copy", "0.3.1", [], false)
	var needy: String = paths["user"] + "/needsfuture"
	World.write_alien(needy, "0.1.0", [{"id": "core", "version": "^9.0"}], false)
	World.edit_json(needy + "/library.json", func(d: Dictionary) -> void: d["id"] = "needsfuture")
	LibraryImportFlow.serve_palette = false
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = ROOT + "/settings.cfg"
	LibraryRegistry.official_root = paths["official"]
	LibraryRegistry.user_root = paths["user"]
	LevelManager.levels_dir = ROOT + "/levels/"
	var manager := LibraryManager.new()
	manager.palette_root = paths["base"]
	_host.add_child(manager)
	await _audit("manager on core", manager)
	for key in manager.keys():
		manager.select(key)
		await _audit("manager on %s" % key, manager)
	manager.select("needsfuture")
	manager.detail.details_box.visible = true
	await _audit("manager with details open", manager)
	manager.verify_all.box.visible = true
	await _audit("manager with the verify all list", manager)
	# The install card in each state (a collection that fails is gone first: the palette logs
	# every library that fails when the card compiles its dry run).
	DirAccess.make_dir_recursive_absolute(ROOT + "/inbox")
	Zip.write(ROOT + "/inbox/pack.ttlib", Zip.entries_of(ROOT + "/source/alienworld"))
	World.remove_tree(paths["user"] + "/alienworld_copy")
	World.remove_tree(needy)
	manager.rescan(true)
	manager.flow.begin(ROOT + "/inbox/pack.ttlib")
	var card_ready := func() -> bool:
		var open := is_instance_valid(manager.flow.panel)
		return open and manager.flow.panel.confirm_button != null
	await wait_until(card_ready, 10.0, "card")
	var card := manager.flow.panel
	await _audit("install card", card)
	card.show_failure("The collection could not be moved into place.", true)
	await _audit("install card after a failure", card)
	card.show_refused("bad.zip", ["'x' is not a readable zip file."])
	await _audit("refusal card", card)
	card.cancel_button.pressed.emit()
	await wait_process_frames(3)
	manager.free()
	LibraryRegistry.clear()


func test_the_mismatch_dialog_and_the_designers_picker_keep_every_shadow() -> void:
	var claimed: Array[Dictionary] = [
		{"id": "frostworld", "version": "1.2.0", "hash": "", "url": "https://example.org/frost"}
	]
	var asker := LibraryMismatchDialog.show(MapLibraries.check(claimed), _host)
	await _audit("mismatch dialog", asker.dialog())
	asker.dialog().free()
	var picker := BiomeDesignerPicker.show_over(_host)
	await _audit("designer picker", picker)
	picker.free()


func test_the_title_the_dialogs_and_the_sheets_keep_every_shadow() -> void:
	var title := TITLE_SCENE.instantiate() as TitleScreen
	title.level_provider = func() -> Array[Dictionary]: return []
	title.session_provider = func() -> Array[Dictionary]: return []
	_host.add_child(title)
	await _audit("title screen", title)
	title.free()
	var menu := SETTINGS_SCENE.instantiate() as SettingsMenu
	_host.add_child(menu)
	for spec in SettingsMenu.SECTIONS:
		menu.section_rail.select(StringName(spec[0]))
		await _audit("settings %s" % spec[0], menu)
	menu.free()
	var dialog := NEW_MAP_SCENE.instantiate()
	_host.add_child(dialog)
	await _audit("new map dialog", dialog)
	dialog.free()
	var pause := PAUSE_SCENE.instantiate()
	_host.add_child(pause)
	await _audit("pause menu", pause)
	pause.free()
	var confirm := CONFIRM_SCENE.instantiate()
	_host.add_child(confirm)
	var none := Callable()
	confirm.setup("Remove it?", "This cannot be undone.", "Remove", "Cancel", none, none, "Danger")
	confirm.add_alternate_action("Keep a copy", Callable())
	await _audit("confirmation dialog", confirm)
	confirm.free()
	var help := HELP_SCENE.instantiate()
	_host.add_child(help)
	await _audit("help overlay", help)
	help.free()
	for scene: PackedScene in [
		UPDATE_SCENE, ADD_PACK_SCENE, LEVEL_PICKER_SCENE, PLAYER_SELECTION_SCENE
	]:
		var sheet := scene.instantiate()
		_host.add_child(sheet)
		await _audit(scene.resource_path.get_file(), sheet)
		sheet.free()


func test_the_avatar_screens_keep_every_shadow() -> void:
	var roster := AvatarRoster.open(_host)
	await _audit("avatar roster", roster)
	roster.free()
	var builder := AvatarBuilder.open_for_new(_host, AVATAR_RECIPE, "Plum")
	for spec in AvatarBuilder.PANES:
		builder._rail.select(spec[0])
		await _audit("avatar builder on %s" % spec[2], builder)
	builder.free()


func test_the_title_with_a_selected_map_and_the_drawers_keep_every_shadow() -> void:
	var level := {
		"path": "user://x/_shadow_mossy/",
		"folder": "_shadow_mossy",
		"is_folder_based": true,
		"name": "Mossy Hollow",
		"token_count": 3,
		"modified_at": 1,
		"environment_preset": "",
		"thumbnail": "",
	}
	var title := TITLE_SCENE.instantiate() as TitleScreen
	title.level_provider = func() -> Array[Dictionary]: return [level.duplicate()]
	title.session_provider = func() -> Array[Dictionary]: return []
	_host.add_child(title)
	await _audit("title with a map selected", title)
	title.free()
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var panel := AuthoringPanel.new()
	panel.theme = ThemeColors.glass_theme()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	for pane in [
		AuthoringPanel.TOOL_BIOME,
		AuthoringPanel.TOOL_PLACE,
		AuthoringPanel.TOOL_SCULPT,
		AuthoringPanel.TOOL_PAINT,
		AuthoringPanel.TOOL_WATER,
	]:
		if pane != panel._rail.selected or not panel.is_open:
			panel._on_rail_item_pressed(pane)
		await _audit("authoring drawer on %s" % pane, panel)
	layer.free()


func test_the_play_hud_drawers_and_the_room_keep_every_shadow() -> void:
	var play := PLAY_SCENE.instantiate()
	_host.add_child(play)
	var menu: Node = play.get_node("GameplayMenu")
	var drawer := menu.get("level_edit_panel") as LevelEditPanel
	drawer.initialize(LevelData.new())
	drawer._mark_dirty()
	for pane in LevelEditPanel.PANE_IDS:
		if pane != drawer._rail.selected or not drawer.is_open:
			drawer._on_rail_item_pressed(pane)
		await _audit("visuals drawer on %s" % pane, drawer)
	drawer.mark_clean()
	drawer.close()
	(menu.get("toggle_asset_browser_button") as Button).button_pressed = true
	await _audit("play HUD with the asset browser", menu.get_node("AssetBrowserContainer"))
	play.free()
	var room := RoomScreen.new()
	room.connect_network = false
	_host.add_child(room)
	room.panel.set_code(LobbyCode.encode(109775244321098765))
	var shelf := [
		{"folder": "hollow", "map_path": "", "hashes": {}, "name": "Mossy Hollow"},
		{"folder": "mill", "map_path": "", "hashes": {}, "name": "Old Mill"},
	]
	var summary := {
		"open": true,
		"table": "",
		"shelf": shelf,
		"players": {"enet-1": {"name": "Marigold", "peer_id": 1}},
		"holdings": {"enet-1": ["hollow", "mill"]},
	}
	room.panel.show_session(summary, "enet-1", true)
	room.panel.select("hollow")
	await _audit("room", room)
	room.free()


func test_the_biome_designers_panels_keep_every_shadow() -> void:
	var made := Fixture.context("user://test_shadow_gutter/mini", true)
	var model := BiomeDesignerModel.from_context(made, "meadow")
	var session := BiomeDesignerSession.new()
	session.debounce = 100000.0
	add_child_autofree(session)
	session.setup(model, null)
	var ui := DesignerUI.new()
	ui.setup(session)
	add_child_autofree(ui)
	await wait_process_frames(1)
	ui.size = Vector2(1600.0, 900.0)
	await _audit("biome designer", ui)
