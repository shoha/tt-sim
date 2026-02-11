extends AnimatedVisibilityContainer

## Container for the asset browser overlay.
## Handles showing/hiding the browser and connecting to asset selection.

const AddPackDialogScene := preload("res://scenes/ui/add_pack_dialog.tscn")

@onready var asset_browser: AssetBrowser = $PanelContainer/VBox/AssetBrowser
@onready var toggle_button: Button = %ToggleAssetBrowserButton
@onready var add_pack_button: Button = %AddPackButton


func _ready() -> void:
	# Slide in from the right instead of a pure scale-up
	scale_in_from = Vector2(0.95, 0.95)
	scale_out_to = Vector2(0.97, 0.97)
	fade_in_duration = 0.25
	fade_out_duration = Constants.ANIM_FADE_OUT_DURATION
	trans_in_type = Tween.TRANS_BACK
	# Sounds are handled manually to avoid doubling with the toggle button's click.
	play_open_close_sounds = false

	asset_browser.asset_selected.connect(_on_asset_selected)
	if add_pack_button:
		add_pack_button.pressed.connect(_on_add_pack_pressed)


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
	# If the button is still pressed, the close came from ESC or asset selection
	# rather than the toggle button (which already plays its own click sound).
	if toggle_button.button_pressed:
		AudioManager.play_close()


# Also untoggle the button when closed via ESC (without re-triggering toggled signal)
func _on_after_animate_out() -> void:
	toggle_button.set_pressed_no_signal(false)


# =============================================================================
# ADD PACK DIALOG
# =============================================================================


func _on_add_pack_pressed() -> void:
	var dialog = AddPackDialogScene.instantiate()
	dialog.pack_downloaded.connect(func(_pack_id: String) -> void:
		# Refresh tabs to show the new pack
		asset_browser._create_tabs()
	)
	get_tree().root.add_child(dialog)
