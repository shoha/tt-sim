extends LineEdit


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _unhandled_key_input(event: InputEvent) -> void:
	if is_editing() and !event.is_pressed():
		accept_event()
