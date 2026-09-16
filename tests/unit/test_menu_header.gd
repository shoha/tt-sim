extends GutTest

## MenuHeader: the title every menu screen opens with, a caption that hides when
## there is nothing to say, and a close button only where one is wanted.


func _header() -> MenuHeader:
	var header := MenuHeader.new()
	add_child_autofree(header)
	return header


func test_title_shows_and_caption_hides_by_default() -> void:
	var header := _header()
	header.setup("Paused")
	assert_eq(header.title_label.text, "Paused")
	assert_eq(header.title_label.theme_type_variation, &"H2")
	assert_false(header.caption_label.visible)
	assert_null(header.close_button, "no close button unless the caller asks for one")


func test_caption_shows_when_given() -> void:
	var header := _header()
	header.setup("Host a game", "Share the code, pick a level")
	assert_true(header.caption_label.visible)
	assert_eq(header.caption_label.text, "Share the code, pick a level")
	assert_eq(header.caption_label.theme_type_variation, &"Caption")


func test_close_button_only_when_closable_and_reports_presses() -> void:
	var header := _header()
	header.setup("Settings", "", true)
	assert_not_null(header.close_button)
	assert_eq(header.close_button.icon_name, "x")
	watch_signals(header)
	header.close_button.pressed.emit()
	assert_signal_emitted(header, "close_requested")


func test_setup_twice_does_not_add_a_second_close_button() -> void:
	var header := _header()
	header.setup("Settings", "", true)
	var first := header.close_button
	header.setup("Settings", "", true)
	assert_same(header.close_button, first)
