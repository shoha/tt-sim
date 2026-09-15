extends GutTest


func _make_button(node_name: String, text: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = rect.position
	button.size = rect.size
	return button


func test_collects_a_visible_control() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.add_child(_make_button("Play", "Start Game", Rect2(10, 20, 100, 40)))

	var found := BridgeInspector.collect_controls(root, true)

	assert_eq(found.size(), 2)
	var names: Array = found.map(func(entry: Dictionary) -> String: return entry["name"])
	assert_has(names, "Play")


func test_describes_centre_in_viewport_coordinates() -> void:
	var root := Control.new()
	add_child_autofree(root)
	var button := _make_button("Play", "Start Game", Rect2(10, 20, 100, 40))
	root.add_child(button)

	var entry := BridgeInspector.describe_control(button)

	# Button's minimum width for "Start Game" at the project's default theme font size (16) is
	# 101px, which exceeds the requested 100px width, so Godot clamps size.x up to 101. Height
	# (40) stays as requested since it is above the 28px minimum.
	assert_eq(entry["center"], [60.5, 40.0])
	assert_eq(entry["rect"], [10.0, 20.0, 101.0, 40.0])


func test_describes_button_text_and_state() -> void:
	var root := Control.new()
	add_child_autofree(root)
	var button := _make_button("Play", "Start Game", Rect2(0, 0, 10, 10))
	button.disabled = true
	root.add_child(button)

	var entry := BridgeInspector.describe_control(button)

	assert_eq(entry["text"], "Start Game")
	assert_true(entry["disabled"])


func test_hidden_controls_are_excluded_unless_asked_for() -> void:
	var root := Control.new()
	add_child_autofree(root)
	var button := _make_button("Play", "Start Game", Rect2(0, 0, 10, 10))
	button.visible = false
	root.add_child(button)

	assert_eq(BridgeInspector.collect_controls(root, true).size(), 1)
	assert_eq(BridgeInspector.collect_controls(root, false).size(), 2)


func test_finds_by_node_name() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.add_child(_make_button("Play", "Start Game", Rect2(0, 0, 10, 10)))

	var matches := BridgeInspector.find_matches(root, "Play", true)

	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["name"], "Play")


func test_finds_by_button_text_when_no_name_matches() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.add_child(_make_button("Play", "Start Game", Rect2(0, 0, 10, 10)))

	var matches := BridgeInspector.find_matches(root, "Start Game", true)

	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["name"], "Play")


func test_name_match_wins_over_text_match() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.add_child(_make_button("Confirm", "Cancel", Rect2(0, 0, 10, 10)))
	root.add_child(_make_button("Cancel", "Dismiss", Rect2(0, 20, 10, 10)))

	var matches := BridgeInspector.find_matches(root, "Cancel", true)

	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["text"], "Dismiss")


func test_reports_every_match_when_ambiguous() -> void:
	var root := Control.new()
	add_child_autofree(root)
	var left := Control.new()
	left.name = "Panel"
	var right := Control.new()
	right.name = "Other"
	root.add_child(left)
	root.add_child(right)
	left.add_child(_make_button("Close", "X", Rect2(0, 0, 10, 10)))
	right.add_child(_make_button("Close", "X", Rect2(0, 0, 10, 10)))

	var matches := BridgeInspector.find_matches(root, "Close", true)

	assert_eq(matches.size(), 2)


func test_returns_no_matches_for_an_unknown_query() -> void:
	var root := Control.new()
	add_child_autofree(root)

	assert_eq(BridgeInspector.find_matches(root, "Nonexistent", true).size(), 0)


func test_collection_is_capped() -> void:
	var root := Control.new()
	add_child_autofree(root)
	for i in range(BridgeInspector.MAX_CONTROLS + 20):
		root.add_child(_make_button("Button%d" % i, "", Rect2(0, 0, 1, 1)))

	assert_eq(BridgeInspector.collect_controls(root, true).size(), BridgeInspector.MAX_CONTROLS)
