extends AnimatedVisibilityContainer

## Container for the asset browser overlay.
## Handles showing/hiding the browser, connecting to asset selection,
## and the "Add Pack" modal for downloading packs from a manifest URL.

@onready var asset_browser: AssetBrowser = $PanelContainer/VBox/AssetBrowser
@onready var toggle_button: Button = %ToggleAssetBrowserButton
@onready var add_pack_button: Button = %AddPackButton

var _downloading_pack_id: String = ""


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
	AssetPackManager.pack_download_progress.connect(_on_pack_download_progress)
	AssetPackManager.pack_download_completed.connect(_on_pack_download_completed)
	AssetPackManager.pack_download_failed.connect(_on_pack_download_failed)


func _exit_tree() -> void:
	if AssetPackManager.pack_download_progress.is_connected(_on_pack_download_progress):
		AssetPackManager.pack_download_progress.disconnect(_on_pack_download_progress)
	if AssetPackManager.pack_download_completed.is_connected(_on_pack_download_completed):
		AssetPackManager.pack_download_completed.disconnect(_on_pack_download_completed)
	if AssetPackManager.pack_download_failed.is_connected(_on_pack_download_failed):
		AssetPackManager.pack_download_failed.disconnect(_on_pack_download_failed)


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
# ADD PACK MODAL
# =============================================================================


func _on_add_pack_pressed() -> void:
	_show_add_pack_dialog()


func _show_add_pack_dialog() -> void:
	# Build dialog as a CanvasLayer (same pattern as ConfirmationDialogUI)
	var dialog = CanvasLayer.new()
	dialog.layer = Constants.LAYER_DIALOG

	# Dimmed background
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	dialog.add_child(bg)

	# Centered container
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)

	# Panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(panel)

	# VBox content
	var vbox = VBoxContainer.new()
	vbox.theme_type_variation = &"BoxContainerSpaced"
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Add Asset Pack"
	title.theme_type_variation = &"H1"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Description
	var desc = Label.new()
	desc.text = "Enter the URL to a pack's manifest.json to download all its assets."
	desc.theme_type_variation = &"Body"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	# URL input
	var url_edit = LineEdit.new()
	url_edit.placeholder_text = "https://example.com/packs/my_pack/manifest.json"
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(url_edit)

	# Progress label (hidden initially)
	var progress_label = Label.new()
	progress_label.theme_type_variation = &"Caption"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.visible = false
	vbox.add_child(progress_label)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Buttons
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var download_btn = Button.new()
	download_btn.text = "Download"
	download_btn.custom_minimum_size = Vector2(120, 0)
	download_btn.theme_type_variation = &"Success"
	btn_row.add_child(download_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 0)
	cancel_btn.theme_type_variation = &"Secondary"
	btn_row.add_child(cancel_btn)

	# Add to scene
	get_tree().root.add_child(dialog)

	# Store references for signal handlers
	dialog.set_meta("url_edit", url_edit)
	dialog.set_meta("progress_label", progress_label)
	dialog.set_meta("download_btn", download_btn)

	# Animate in
	bg.modulate.a = 0.0
	center.modulate.a = 0.0
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.9, 0.9)
	var intro_tween = dialog.create_tween()
	intro_tween.set_parallel(true)
	intro_tween.set_ease(Tween.EASE_OUT)
	intro_tween.set_trans(Tween.TRANS_BACK)
	intro_tween.tween_property(bg, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	intro_tween.tween_property(center, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	intro_tween.tween_property(panel, "scale", Vector2.ONE, Constants.ANIM_FADE_IN_DURATION)
	await intro_tween.finished
	url_edit.grab_focus()

	# Connect buttons
	var close_dialog = func() -> void: _close_add_pack_dialog(dialog)

	cancel_btn.pressed.connect(close_dialog)

	download_btn.pressed.connect(
		func() -> void:
			var url = url_edit.text.strip_edges()
			if url.is_empty():
				progress_label.text = "Please enter a manifest URL"
				progress_label.visible = true
				return
			progress_label.text = "Fetching manifest..."
			progress_label.visible = true
			download_btn.disabled = true
			_downloading_pack_id = ""
			if not AssetPackManager.download_asset_pack_from_url(url):
				progress_label.text = "Failed to start download"
				download_btn.disabled = false
	)

	# ESC to close
	dialog.set_meta(
		"_esc_handler",
		func(event: InputEvent) -> void:
			if event.is_action_pressed("ui_cancel"):
				close_dialog.call()
				dialog.get_viewport().set_input_as_handled()
	)
	# We use set_process_unhandled_input but CanvasLayer doesn't support it,
	# so we add a Control that catches ESC
	var esc_catcher = Control.new()
	esc_catcher.anchors_preset = Control.PRESET_FULL_RECT
	esc_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(esc_catcher)
	esc_catcher.set_script(GDScript.new())
	# Can't easily attach inline script; handle ESC via bg click instead
	bg.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				close_dialog.call()
	)

	# Store current dialog reference
	set_meta("_add_pack_dialog", dialog)


func _close_add_pack_dialog(dialog: Node) -> void:
	if not is_instance_valid(dialog):
		return
	var bg = dialog.get_child(0) as ColorRect
	var center = dialog.get_child(1) as CenterContainer
	var panel = center.get_child(0) as PanelContainer
	panel.pivot_offset = panel.size / 2
	var outro_tween = dialog.create_tween()
	outro_tween.set_parallel(true)
	outro_tween.set_ease(Tween.EASE_IN)
	outro_tween.set_trans(Tween.TRANS_CUBIC)
	outro_tween.tween_property(bg, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	outro_tween.tween_property(center, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	outro_tween.tween_property(
		panel, "scale", Vector2(0.95, 0.95), Constants.ANIM_FADE_OUT_DURATION
	)
	await outro_tween.finished
	dialog.queue_free()
	if has_meta("_add_pack_dialog"):
		remove_meta("_add_pack_dialog")


func _get_active_dialog() -> Node:
	if has_meta("_add_pack_dialog"):
		var dialog = get_meta("_add_pack_dialog")
		if is_instance_valid(dialog):
			return dialog
	return null


# =============================================================================
# DOWNLOAD PROGRESS (updates the dialog if open)
# =============================================================================


func _on_pack_download_progress(pack_id: String, downloaded: int, total: int) -> void:
	_downloading_pack_id = pack_id
	var dialog = _get_active_dialog()
	if dialog:
		var label = dialog.get_meta("progress_label") as Label
		if label:
			label.text = "Downloading %s: %d / %d" % [pack_id, downloaded, total]
			label.visible = true


func _on_pack_download_completed(pack_id: String) -> void:
	if pack_id != _downloading_pack_id and _downloading_pack_id != "":
		return
	_downloading_pack_id = ""
	# Refresh tabs to show the new pack
	asset_browser._create_tabs()
	var dialog = _get_active_dialog()
	if dialog:
		var label = dialog.get_meta("progress_label") as Label
		var btn = dialog.get_meta("download_btn") as Button
		if label:
			label.text = "Download complete! Pack added."
		if btn:
			btn.disabled = false
			btn.text = "Done"
			btn.pressed.connect(func() -> void: _close_add_pack_dialog(dialog))


func _on_pack_download_failed(pack_id: String, error: String) -> void:
	if pack_id != _downloading_pack_id and _downloading_pack_id != "":
		return
	_downloading_pack_id = ""
	var dialog = _get_active_dialog()
	if dialog:
		var label = dialog.get_meta("progress_label") as Label
		var btn = dialog.get_meta("download_btn") as Button
		if label:
			label.text = "Download failed: %s" % error
			label.visible = true
		if btn:
			btn.disabled = false
