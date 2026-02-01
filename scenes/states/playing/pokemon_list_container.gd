extends AnimatedVisibilityContainer

@onready var pokemon_filter: LineEdit = $PanelContainer/VBox/Header/PokemonFilter
@onready var pokemon_list: ItemList = $PanelContainer/VBox/PokemonList
@onready var toggle_pokemon_list_button: Button = %TogglePokemonListButton


func _ready() -> void:
	pokemon_list.asset_selected.connect(_on_asset_selected)


func _on_asset_selected(_pack_id: String, _asset_id: String, _variant_id: String) -> void:
	# Close the overlay after an asset is selected
	animate_out()


func _on_button_toggled(toggled_on: bool) -> void:
	toggle_animated(toggled_on)
	if toggled_on:
		pokemon_filter.grab_focus()


# Register with UIManager when opening
func _on_before_animate_in() -> void:
	UIManager.register_overlay(self)


# Unregister and clear filter when closing
func _on_before_animate_out() -> void:
	UIManager.unregister_overlay(self)
	pokemon_filter.clear()


# Also untoggle the button when closed via ESC
func _on_after_animate_out() -> void:
	toggle_pokemon_list_button.button_pressed = false
