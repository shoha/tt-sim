extends GutTest

## Foldout moves authored children into its body, starts at the requested
## state without animating, and animates on toggle.


func _foldout(expanded_at_start: bool = false) -> Foldout:
	var foldout := Foldout.new()
	foldout.title = "Advanced"
	foldout.expanded = expanded_at_start
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, 40)
	foldout.add_child(row)
	add_child_autofree(foldout)
	return foldout


func test_authored_children_move_into_body() -> void:
	var foldout := _foldout()
	assert_eq(foldout.body.get_child_count(), 1)
	assert_eq(foldout.get_child_count(), 2, "header + clip only")


func test_starts_collapsed_with_zero_height_body() -> void:
	var foldout := _foldout()
	assert_false(foldout.expanded)
	assert_eq(foldout._clip.custom_minimum_size.y, 0.0)
	assert_false(foldout.body.visible)


func test_starts_expanded_at_natural_height() -> void:
	var foldout := _foldout(true)
	assert_eq(foldout._clip.custom_minimum_size.y, 40.0)
	assert_true(foldout.body.visible)
	assert_almost_eq(foldout._chevron.rotation, PI / 2.0, 0.001)


func test_toggle_emits_and_starts_tween() -> void:
	var foldout := _foldout()
	watch_signals(foldout)
	foldout.toggle()
	assert_true(foldout.expanded)
	assert_signal_emitted_with_parameters(foldout, "expanded_changed", [true])
	assert_true(foldout._tween != null and foldout._tween.is_valid())
	assert_true(foldout.body.visible, "body shows before the expand tween runs")


func test_setting_same_value_is_a_no_op() -> void:
	var foldout := _foldout()
	watch_signals(foldout)
	foldout.expanded = false
	assert_signal_not_emitted(foldout, "expanded_changed")


func test_title_reaches_label() -> void:
	var foldout := _foldout()
	foldout.title = "More"
	assert_eq(foldout._title_label.text, "More")


## Rows authored under a Foldout in a .tscn belong to the scene root; moving
## them into the body must not break the root's %unique_name lookups.
func test_authored_children_keep_their_owner() -> void:
	var host := Control.new()
	var foldout := Foldout.new()
	host.add_child(foldout)
	var row := Control.new()
	row.name = "Row"
	foldout.add_child(row)
	row.owner = host
	row.unique_name_in_owner = true
	add_child_autofree(host)
	assert_eq(row.get_parent(), foldout.body)
	assert_eq(row.owner, host)
	assert_eq(host.get_node("%Row"), row)
