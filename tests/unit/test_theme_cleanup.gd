extends GutTest

## The Painted Table cleanup (docs/UI_TASTE.md C4, C5, C7): one shared scrim instead of black
## dims, the title's Host stepping down from its fill while a sheet is up, toasts that carry
## their kind in a cool-or-outcome stripe and a real icon, and glass chips over the board.

const TITLE_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
const TOAST_SCENE := preload("res://scenes/ui/toast_container.tscn")
const GLYPH := 3.0
const WHITE := Color(1, 1, 1)
const BLACK := Color(0, 0, 0)
## Every full-screen sheet that stops play.
const SCRIMMED_SCENES: Array[String] = [
	"res://scenes/ui/settings_menu.tscn",
	"res://scenes/ui/confirmation_dialog.tscn",
	"res://scenes/ui/update_dialog.tscn",
	"res://scenes/ui/add_pack_dialog.tscn",
	"res://scenes/ui/player_selection_dialog.tscn",
	"res://scenes/ui/level_picker_dialog.tscn",
	"res://scenes/ui/help_overlay.tscn",
	"res://scenes/ui/avatar_roster.tscn",
	"res://scenes/states/paused/pause_overlay.tscn",
	"res://scenes/states/playing/avatar_builder.tscn",
	"res://scenes/states/authoring/new_map_dialog.tscn",
]


func test_every_sheet_backdrop_is_the_shared_scrim() -> void:
	for path in SCRIMMED_SCENES:
		var state := (load(path) as PackedScene).get_state()
		var found := false
		for i in range(state.get_node_count()):
			if state.get_node_name(i) != &"ColorRect":
				continue
			for p in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, p) == &"script":
					var script := state.get_node_property_value(i, p) as Script
					found = script != null and script.resource_path.ends_with("scrim.gd")
		assert_true(found, "%s dims with Scrim, not a black ColorRect" % path)


func test_the_scrim_is_the_plum_tint_over_a_blur() -> void:
	var scrim := Scrim.new()
	autofree(scrim)
	var material := scrim.material as ShaderMaterial
	assert_same(material, Scrim.shared_material(), "every scrim shares one material")
	assert_eq(material.get_shader_parameter(&"tint"), ThemeColors.SCRIM)
	assert_true(scrim.is_in_group(Scrim.GROUP))
	assert_eq(scrim.color, Color.WHITE, "no colour of its own: the shader draws it")


func test_host_steps_down_from_its_fill_while_a_sheet_is_up() -> void:
	var title: TitleScreen = TITLE_SCENE.instantiate()
	title.level_provider = func() -> Array[Dictionary]: return []
	add_child_autofree(title)
	assert_eq(title.host_button.theme_type_variation, &"Primary")
	var scrim := Scrim.new()
	add_child(scrim)
	await wait_frames(2)
	assert_eq(title.host_button.theme_type_variation, &"Secondary", "one fill per screen")
	scrim.free()
	await wait_frames(2)
	assert_eq(title.host_button.theme_type_variation, &"Primary", "the fill comes back")


## Every toast is the same stripe-less surface (a stripe at rest is decoration); its kind
## shows in a real icon tinted with the kind's role, and in its words.
func test_each_toast_kind_has_its_icon_and_no_stripe() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	var glass := ThemeColors.glass_theme()
	var surface := glass.get_stylebox("panel", "Toast") as StyleBoxFlat
	assert_eq(surface.border_width_left, surface.border_width_right, "no side stripe")
	for type: int in ToastContainer.KINDS:
		var kind: Array = ToastContainer.KINDS[type]
		var toast := toasts._create_toast("Map saved", type) as PanelContainer
		autofree(toast)
		assert_eq(toast.theme_type_variation, &"Toast")
		var icon := toast.find_child("Icon", true, false) as TextureRect
		assert_not_null(icon.texture, "%s has a real icon, not a glyph" % kind[0])
		assert_eq(icon.self_modulate, ThemeColors.GLASS_ROLES[kind[1]])
	for variation in ["ToastInfo", "ToastSuccess", "ToastWarning", "ToastError"]:
		assert_false(glass.has_stylebox("panel", variation), "%s is gone" % variation)
	var info: Array = ToastContainer.KINDS[ToastContainer.ToastType.INFO]
	assert_eq(info[1], ThemeColors.STATE, "information is cool: warm means do")


## A toast's action (the removal's Undo) runs once and dismisses the toast.
func test_a_toast_action_runs_once_and_dismisses() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	var calls := [0]
	toasts.show_toast('Removed "Marigold"', 0, 30.0, "Undo", func(): calls[0] += 1, "arrow-back-up")
	var button := toasts.toast_vbox.find_child("Action", true, false) as Button
	assert_eq(button.text, "Undo")
	assert_not_null(button.icon, "a real icon")
	button.pressed.emit()
	button.pressed.emit()
	assert_eq(calls[0], 1)
	assert_eq(toasts._active_toasts.size(), 0, "dismissed")


## The toast icons sit on glass over any board: each holds 3:1 over white and over black.
func test_toast_kinds_hold_glyph_contrast_on_glass() -> void:
	for kind: Array in ToastContainer.KINDS.values():
		for ground: Color in [WHITE, BLACK]:
			var back := _over(ThemeColors.GLASS_ROLES[ThemeColors.SURFACE], ground)
			var ratio := _contrast(ThemeColors.GLASS_ROLES[kind[1]], back)
			assert_gt(ratio, GLYPH, "%s on glass: %.2f" % [kind[0], ratio])


func test_board_labels_are_glass_chips() -> void:
	var label := MapOverlayUtils.create_label_panel(12)
	var checks := MapOverlayUtils.create_checkbox_panel(PackedStringArray(["a"]))
	autofree(label.panel)
	autofree(checks.panel)
	for panel: PanelContainer in [label.panel, checks.panel]:
		assert_eq(panel.theme_type_variation, &"Chip")
	var font_size := (label.label as Label).get_theme_font_size("font_size")
	assert_eq(font_size, MapOverlayUtils.CAPTION_SIZE, "never under the caption floor")
	var chip := ThemeColors.glass_theme().get_stylebox("panel", "Chip") as StyleBoxFlat
	assert_eq(chip.bg_color, ThemeColors.GLASS, "the glass surface, not black")
	assert_gt(chip.border_width_top, 0, "the glass top rim")


## Focus and selection never share a mark: a selected card keeps its edge (no ring; the ring
## is focus) and says so in its caption strip, the selected fill under ON_SELECTED text.
func test_a_selected_card_fills_its_strip_and_leaves_the_ring_to_focus() -> void:
	var leaves := [
		[ThemeColors.paper_theme(), ThemeColors.PAPER_ROLES],
		[ThemeColors.glass_theme(), ThemeColors.GLASS_ROLES],
	]
	for leaf: Array in leaves:
		var theme: Theme = leaf[0]
		var roles: Dictionary = leaf[1]
		var normal := theme.get_stylebox("normal", "Card") as StyleBoxFlat
		var pressed := theme.get_stylebox("pressed", "Card") as StyleBoxFlat
		assert_eq(pressed.border_color, normal.border_color, "no state ring on a selected card")
		assert_eq(pressed.border_width_top, normal.border_width_top)
		var strip := theme.get_stylebox("panel", "CardStripSelected") as StyleBoxFlat
		assert_eq(strip.bg_color, roles[ThemeColors.SELECTED])
		assert_eq(theme.get_stylebox("panel", "CardStrip").bg_color.a, 0.0, "clear at rest")
		for label in ["BodyOnSelected", "CaptionOnSelected"]:
			assert_eq(theme.get_color("font_color", label), roles[ThemeColors.ON_SELECTED], label)
	var card := LevelCard.new()
	add_child_autofree(card)
	card.setup({"name": "Mossy Hollow", "path": "user://x/"})
	card.set_selected(true)
	assert_true(card.button_pressed)
	assert_eq(card._strip.theme_type_variation, &"CardStripSelected")
	assert_eq(card._name.theme_type_variation, &"BodyOnSelected")
	assert_eq(card._caption.theme_type_variation, &"CaptionOnSelected")
	card.set_selected(false)
	assert_eq(card._strip.theme_type_variation, &"CardStrip")
	assert_eq(card._name.theme_type_variation, &"Body")


## The slider's unfilled track is a 3 px rail under the 6 px fill: Godot draws both at the
## track's minimum height, and the fill's expand margins widen it.
func test_the_slider_track_is_thinner_than_its_fill() -> void:
	var theme := ThemeColors.paper_theme()
	for type in ["HSlider", "VSlider"]:
		var track := theme.get_stylebox("slider", type) as StyleBoxFlat
		var fill := theme.get_stylebox("grabber_area", type) as StyleBoxFlat
		var across := track.get_minimum_size().y if type == "HSlider" else track.get_minimum_size().x
		var widen := (
			fill.expand_margin_top + fill.expand_margin_bottom
			if type == "HSlider"
			else fill.expand_margin_left + fill.expand_margin_right
		)
		assert_eq(across, 3.0, "%s rail" % type)
		assert_eq(across + widen, 6.0, "%s fill" % type)


## A divider is at least one physical pixel at 1280x720 (the canvas draws at 0.667 there).
func test_dividers_survive_the_smallest_window() -> void:
	for theme: Theme in [ThemeColors.paper_theme(), ThemeColors.glass_theme()]:
		for item: Array in [
			["separator", "HSeparator"], ["separator", "VSeparator"], ["separator", "PopupMenu"]
		]:
			var line := theme.get_stylebox(item[0], item[1]) as StyleBoxLine
			assert_gte(line.thickness * 1280.0 / 1920.0, 1.0, "%s at 720p" % item[1])


## Settings rows share one label column and the PropertyRow gap.
func test_sheet_rows_share_one_label_column() -> void:
	var gap := ThemeColors.paper_theme().get_constant("separation", "PropertyRow")
	assert_eq(gap, 16)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(Button.new())
	autofree(row)
	PropertyRow.fit_sheet_row(row)
	assert_eq(row.theme_type_variation, &"PropertyRow")
	assert_eq(label.custom_minimum_size.x, PropertyRow.SHEET_LABEL_WIDTH)
	assert_eq(label.size_flags_horizontal, Control.SIZE_FILL, "the control sits on the edge")
	var bare := HBoxContainer.new()
	bare.add_child(Control.new())
	autofree(bare)
	PropertyRow.fit_sheet_row(bare)
	assert_eq(bare.theme_type_variation, &"", "a row that does not start with a label is left")


func test_copy_counts_and_tells_gestures_apart() -> void:
	var two: Array[Dictionary] = [{"holds": ["camp"]}, {"holds": []}]
	assert_eq(RoomModel.readiness_text(two, "camp"), "1 of 2 have it")
	for i in range(2):
		var pan: String = InputProfile.LABELS[&"pan"][i]
		var rotate: String = InputProfile.LABELS[&"rotate"][i]
		assert_ne(pan, rotate, "pan and rotate read differently")


func _over(color: Color, ground: Color) -> Color:
	return Color(
		lerpf(ground.r, color.r, color.a),
		lerpf(ground.g, color.g, color.a),
		lerpf(ground.b, color.b, color.a),
	)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	var lin := color.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
