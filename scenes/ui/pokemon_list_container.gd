extends AnimatedVisibilityContainer

@onready var pokemon_filter: LineEdit = $PokemonFilter

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		$"../TogglePokemonList".button_pressed = false

# Override to clear filter before hiding
func _on_before_animate_out() -> void:
	pokemon_filter.clear()

func _on_button_toggled(toggled_on: bool) -> void:
	toggle_animated(toggled_on)
	pokemon_filter.grab_focus()
