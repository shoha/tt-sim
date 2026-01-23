extends AnimatedVisibilityContainer

## Example of a settings menu that uses AnimatedVisibilityContainer
## This demonstrates how simple it is to add animations to any UI element

# Customize the animation feel
func _ready():
	# Make settings menu slide in from the side with an elastic bounce
	fade_in_duration = 0.4
	fade_out_duration = 0.25
	scale_in_from = Vector2(0.0, 1.0)  # Slide from left
	trans_in_type = Tween.TRANS_ELASTIC
	super._ready()

func _on_before_animate_in():
	# Could load settings here
	print("Settings menu opening...")

func _on_after_animate_in():
	# Focus first control after animation
	if has_node("FirstSetting"):
		$FirstSetting.grab_focus()

func _on_before_animate_out():
	# Save settings before closing
	print("Settings menu closing...")

func _on_settings_button_pressed():
	animate_in()

func _on_close_button_pressed():
	animate_out()
