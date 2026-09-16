class_name SettingsTooltips
extends RefCounted

## Tooltip text for every Settings control. Split out of settings_menu.gd to
## keep that file under the project's max-file-lines lint budget.


static func apply(menu: SettingsMenu) -> void:
	menu.master_slider.tooltip_text = "Overall volume for all audio"
	menu.music_slider.tooltip_text = "Background music volume"
	menu.sfx_slider.tooltip_text = "Sound effects for token interactions"
	menu.ui_slider.tooltip_text = "UI sounds (clicks, hover, panel open/close)"
	menu.fullscreen_check.tooltip_text = "Toggle fullscreen mode (F11)"
	menu.vsync_check.tooltip_text = "Sync frame rate to monitor refresh rate"
	menu.lofi_check.tooltip_text = "Apply a lo-fi pixel filter to the 3D view"
	menu.occlusion_fade_check.tooltip_text = "Fade map geometry that hides tokens from view"
	menu.antialiasing_option.tooltip_text = "Smooths jagged edges on foliage (uses more GPU memory)"
	menu.shadow_quality_option.tooltip_text = (
		"Shadow edge softness (Hard is fastest, " + "Ultra is priciest)"
	)
	menu.water_quality_option.tooltip_text = (
		"Water ripple detail and refraction quality (Low is fastest, " + "High is highest fidelity)"
	)
	menu.ssao_check.tooltip_text = (
		"Screen-space ambient occlusion -- softens contact shadows in corners and crevices "
		+ "(uses more GPU)"
	)
	menu.ssr_check.tooltip_text = (
		"Reflects nearby geometry in reflective surfaces like water " + "(uses more GPU)"
	)
	menu.sdfgi_check.tooltip_text = (
		"Signed distance field global illumination for more realistic indirect lighting "
		+ "(uses significantly more GPU)"
	)
	menu.renderer_method_option.tooltip_text = (
		"Which Godot rendering backend to use (Default follows the platform's "
		+ "normal choice). Changing this requires a restart."
	)
	menu.foliage_density_slider.tooltip_text = (
		"Maximum scattered foliage detail, in millions of triangles. Lower this if maps "
		+ "with heavy foliage run poorly; raise it if your machine has headroom. Applies "
		+ "without a map reload, and each player chooses their own."
	)
	menu.cell_tint_opacity_slider.tooltip_text = "Opacity of the cell fill shading on the grid"
	menu.line_thickness_slider.tooltip_text = "Thickness of the grid lines"
	menu.fade_distance_slider.tooltip_text = "How far the grid extends from the camera center"
	menu.input_device_option.tooltip_text = (
		"Choose which key labels to show in hints " + "(Auto detects device)"
	)
	menu.p2p_enabled_check.tooltip_text = "Allow peer-to-peer asset sharing with other players"
	menu.clear_cache_button.tooltip_text = "Delete downloaded asset files to free disk space"
	menu.prereleases_check.tooltip_text = "Include pre-release versions when checking for updates"
	menu.check_updates_button.tooltip_text = "Check for a newer version of TTSim"
	menu.reset_button.tooltip_text = "Reset all settings to defaults"
	menu.apply_button.tooltip_text = "Apply and save current settings"
	menu.close_button.tooltip_text = "Close settings (ESC)"
