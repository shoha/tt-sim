extends LineEdit

func _unhandled_key_input(event: InputEvent) -> void:
	if is_editing() and !event.is_pressed():
		accept_event()
