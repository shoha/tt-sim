extends GutTest

## The help overlay reads like the rest of the menus: the shared header, themed
## section headings and KeyChip key caps instead of a hand-built StyleBoxFlat.

const SCENE := preload("res://scenes/ui/help_overlay.tscn")
const CHIP_MIN_WIDTH := 140.0


func _overlay():
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	return overlay


func test_header_title_and_close_button() -> void:
	var overlay = _overlay()
	assert_eq(overlay.header.title_label.text, "Keyboard shortcuts")
	assert_not_null(overlay.header.close_button)


func test_one_section_header_variation_per_shortcut_section() -> void:
	var overlay = _overlay()
	assert_eq(_count_styled(overlay, "Label", &"SectionHeader"), 4)


func test_key_caps_use_the_key_chip_variation() -> void:
	var overlay = _overlay()
	assert_gt(_count_styled(overlay, "PanelContainer", &"KeyChip"), 10)
	var chip := _first_styled(overlay, "PanelContainer", &"KeyChip")
	assert_not_null(chip)
	assert_eq(chip.custom_minimum_size.x, CHIP_MIN_WIDTH)


func _count_styled(node: Node, type: String, variation: StringName) -> int:
	var total := 1 if _matches(node, type, variation) else 0
	for child in node.get_children():
		total += _count_styled(child, type, variation)
	return total


func _first_styled(node: Node, type: String, variation: StringName) -> Control:
	if _matches(node, type, variation):
		return node as Control
	for child in node.get_children():
		var found := _first_styled(child, type, variation)
		if found != null:
			return found
	return null


func _matches(node: Node, type: String, variation: StringName) -> bool:
	if not (node is Control) or not node.is_class(type):
		return false
	return (node as Control).theme_type_variation == variation
