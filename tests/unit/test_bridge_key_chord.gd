extends GutTest

## Tests for the validation bridge's key-chord grammar: the "key" action accepts
## "Z", "Ctrl+Z" or "Shift+Alt+F" and must turn the modifier prefixes into the
## matching InputEventKey flags rather than silently dropping them.

const ValidationBridgeScript := preload("res://addons/validation_bridge/validation_bridge.gd")


func test_bare_key_has_no_modifiers() -> void:
	var chord: Dictionary = ValidationBridgeScript._parse_key_chord("Z")
	assert_eq(chord["keycode"], KEY_Z)
	assert_false(chord["ctrl"])
	assert_false(chord["shift"])
	assert_false(chord["alt"])


func test_ctrl_chord_sets_ctrl_only() -> void:
	var chord: Dictionary = ValidationBridgeScript._parse_key_chord("Ctrl+Z")
	assert_eq(chord["keycode"], KEY_Z)
	assert_true(chord["ctrl"])
	assert_false(chord["shift"])
	assert_false(chord["alt"])


func test_two_modifiers_both_apply() -> void:
	var chord: Dictionary = ValidationBridgeScript._parse_key_chord("Shift+Alt+F")
	assert_eq(chord["keycode"], KEY_F)
	assert_true(chord["shift"])
	assert_true(chord["alt"])
	assert_false(chord["ctrl"])
