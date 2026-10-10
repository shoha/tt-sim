extends GutTest

## The theme-bypass ratchet (docs/UI_TASTE.md C1, C4, S1, T1, T2, G7): colour literals,
## theme overrides and literal font sizes per file under scenes/ and autoloads/
## (tools/ui_audit/bypass_audit.gd says exactly what counts) against the committed
## tests/ui_bypass_baseline.json. A count may fall, never rise. On a failure, read the role,
## variation or constant from the theme instead; a real exception (a 3D colour in a UI
## script) raises that file's entry by hand, with the reason in the commit message. After a
## migration lowers counts, lower the baseline with
## `godot --headless --path D:/dev/tt-sim --script res://tools/ui_audit/bypass_baseline.gd`.
## The run prints each rule's total against the baseline and every entry that can be lowered.
##
## Some rules and review methods here are adapted from Impeccable by Paul Bakaus
## (https://github.com/pbakaus/impeccable), Apache License 2.0.

const Audit := preload("res://tools/ui_audit/bypass_audit.gd")


func test_no_file_adds_a_theme_bypass() -> void:
	var current := Audit.scan()
	var baseline := Audit.load_baseline()
	assert_false(baseline.is_empty(), "the baseline loads")
	print(Audit.summary(current, baseline))
	for line in Audit.falls(current, baseline):
		print("  can lower: " + line)
	var rises := Audit.rises(current, baseline)
	assert_eq(rises.size(), 0, "theme bypasses above the baseline:\n" + "\n".join(rises))


func test_a_colour_literal_counts_and_a_role_does_not() -> void:
	var text := "\n".join(
		[
			'var a := Color("#2c1f2b")',
			"var b := Color(0, 0, 0, 0.6)",
			"var c := ThemeColors.ACCENT",
			"var d := Color.from_ok_hsl(0.1, 0.5, 0.5)",
			"var e := Color.WHITE",
			"var f := SkyColor(1)",
		]
	)
	assert_eq(Audit.count_text(text, false), {"colour": 2})


func test_comment_lines_do_not_count_in_scripts() -> void:
	var text := "## Was Color(0, 0, 0, 0.6)\n\t# add_theme_color_override(&\"x\", Color.RED)\n"
	assert_eq(Audit.count_text(text, false), {})


func test_overrides_count_in_scripts_and_scenes() -> void:
	var script := (
		'label.add_theme_color_override("font_color", ThemeColors.ACCENT)\n'
		+ 'box.add_theme_constant_override("separation", 8)\n'
		+ 'label.get_theme_color("font_color")\n'
	)
	assert_eq(Audit.count_text(script, false), {"override": 2})
	var scene := (
		"[node name=\"Code\" type=\"Label\" parent=\".\"]\n"
		+ "theme_override_colors/font_color = Color(1, 0.8, 0.4, 1)\n"
		+ "theme_override_constants/separation = 12\n"
		+ 'theme_type_variation = &"Caption"\n'
	)
	assert_eq(Audit.count_text(scene, true), {"colour": 1, "override": 2})


func test_a_literal_font_size_counts_and_a_constant_does_not() -> void:
	var script := (
		'title.add_theme_font_size_override("font_size", 36)\n'
		+ 'caption.add_theme_font_size_override("font_size", Constants.FONT_CAPTION)\n'
		+ "settings.font_size = 14\n"
		+ "if font_size == 14:\n"
	)
	assert_eq(Audit.count_text(script, false), {"override": 2, "font_size": 2})
	var scene := "theme_override_font_sizes/font_size = 18\n[sub_resource]\nfont_size = 12\n"
	assert_eq(Audit.count_text(scene, true), {"override": 1, "font_size": 2})


func test_the_ratchet_only_lowers() -> void:
	var baseline := {"a.gd": {"colour": 3, "override": 2}, "gone.gd": {"colour": 1}}
	var current := {"a.gd": {"colour": 1, "override": 4}, "new.gd": {"font_size": 1}}
	assert_eq(
		Audit.rises(current, baseline),
		PackedStringArray(["a.gd: override 4, baseline 2", "new.gd: font_size 1, baseline 0"])
	)
	assert_eq(
		Audit.falls(current, baseline),
		PackedStringArray(["a.gd: colour 1, baseline 3", "gone.gd: colour 0, baseline 1"])
	)
	assert_eq(
		Audit.lowered(current, baseline),
		{"a.gd": {"colour": 1, "override": 2}},
		"a rise keeps its baseline, a fall lowers it, a file at zero drops out"
	)
