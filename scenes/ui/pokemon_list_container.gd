extends Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hide()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		$"../TogglePokemonList".button_pressed = false
	
func _on_button_toggled(toggled_on: bool) -> void:
	if(toggled_on):
		show()
	else:
		$PokemonFilter.clear()
		hide()
