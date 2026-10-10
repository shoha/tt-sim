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


func test_each_toast_kind_has_its_stripe_and_icon() -> void:
	var toasts: ToastContainer = TOAST_SCENE.instantiate()
	add_child_autofree(toasts)
	var glass := ThemeColors.glass_theme()
	for type: int in ToastContainer.KINDS:
		var kind: Array = ToastContainer.KINDS[type]
		var toast := toasts._create_toast("Level saved", type) as PanelContainer
		autofree(toast)
		assert_eq(toast.theme_type_variation, kind[0])
		var icon := toast.find_child("Icon", true, false) as TextureRect
		assert_not_null(icon.texture, "%s has a real icon, not a glyph" % kind[1])
		var stripe := glass.get_stylebox("panel", kind[0]) as StyleBoxFlat
		assert_eq(stripe.border_color, ThemeColors.GLASS_ROLES[kind[2]])
		assert_gt(stripe.border_width_left, 0)
	var info: Array = ToastContainer.KINDS[ToastContainer.ToastType.INFO]
	assert_eq(info[2], ThemeColors.STATE, "information is cool: warm means do")


## The toast stripes and icons sit on glass over any board: each holds 3:1 over white and
## over black.
func test_toast_kinds_hold_glyph_contrast_on_glass() -> void:
	for kind: Array in ToastContainer.KINDS.values():
		for ground: Color in [WHITE, BLACK]:
			var back := _over(ThemeColors.GLASS_ROLES[ThemeColors.SURFACE], ground)
			var ratio := _contrast(ThemeColors.GLASS_ROLES[kind[2]], back)
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
