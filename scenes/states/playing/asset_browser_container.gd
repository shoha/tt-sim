extends AnimatedVisibilityContainer

## Container for the asset browser overlay.
## Handles showing/hiding the browser and connecting to asset selection.

@onready var asset_browser: AssetBrowser = $PanelContainer/VBox/AssetBrowser
@onready var toggle_button: Button = %ToggleAssetBrowserButton


func _ready() -> void:
	asset_browser.asset_selected.connect(_on_asset_selected)


func _on_asset_selected(_pack_id: String, _asset_id: String, _variant_id: String) -> void:
	# Close the overlay after an asset is selected
	animate_out()


func _on_button_toggled(toggled_on: bool) -> void:
	toggle_animated(toggled_on)
	if toggled_on:
		asset_browser.focus_current_search()


# Register with UIManager when opening
func _on_before_animate_in() -> void:
	UIManager.register_overlay(self)


# Unregister and clear filters when closing
func _on_before_animate_out() -> void:
	UIManager.unregister_overlay(self)
	asset_browser.clear_filters()


# Also untoggle the button when closed via ESC
func _on_after_animate_out() -> void:
	toggle_button.button_pressed = false
