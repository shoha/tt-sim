extends AnimatedCanvasLayerPanel
class_name AddPackDialog

## Dialog for downloading an asset pack from a manifest URL.
## Replaces the procedural dialog that was built in asset_browser_container.gd.

signal closed
signal pack_downloaded(pack_id: String)

@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var url_edit: LineEdit = %URLEdit
@onready var progress_label: Label = %ProgressLabel
@onready var download_button: Button = %DownloadButton
@onready var cancel_button: Button = %CancelButton

var _downloading_pack_id: String = ""


func _on_panel_ready() -> void:
	cancel_button.set_meta("ui_silent", true)
	download_button.set_meta("ui_silent", true)

	download_button.pressed.connect(_on_download_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)

	AssetManager.pack_download_progress.connect(_on_pack_download_progress)
	AssetManager.pack_download_completed.connect(_on_pack_download_completed)
	AssetManager.pack_download_failed.connect(_on_pack_download_failed)


func _on_after_animate_in() -> void:
	url_edit.grab_focus()


func _on_before_animate_out() -> void:
	if AssetManager.pack_download_progress.is_connected(_on_pack_download_progress):
		AssetManager.pack_download_progress.disconnect(_on_pack_download_progress)
	if AssetManager.pack_download_completed.is_connected(_on_pack_download_completed):
		AssetManager.pack_download_completed.disconnect(_on_pack_download_completed)
	if AssetManager.pack_download_failed.is_connected(_on_pack_download_failed):
		AssetManager.pack_download_failed.disconnect(_on_pack_download_failed)


func _on_after_animate_out() -> void:
	closed.emit()
	queue_free()


func _on_download_pressed() -> void:
	var url := url_edit.text.strip_edges()
	if url.is_empty():
		progress_label.text = "Please enter a manifest URL"
		progress_label.visible = true
		return
	AudioManager.play_confirm()
	progress_label.text = "Fetching manifest..."
	progress_label.visible = true
	download_button.disabled = true
	_downloading_pack_id = ""
	if not AssetManager.download_asset_pack_from_url(url):
		progress_label.text = "Failed to start download"
		download_button.disabled = false


func _on_cancel_pressed() -> void:
	AudioManager.play_cancel()
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


# ============================================================================
# Download Progress
# ============================================================================


func _on_pack_download_progress(pack_id: String, downloaded: int, total: int) -> void:
	_downloading_pack_id = pack_id
	progress_label.text = "Downloading %s: %d / %d" % [pack_id, downloaded, total]
	progress_label.visible = true


func _on_pack_download_completed(pack_id: String) -> void:
	if pack_id != _downloading_pack_id and _downloading_pack_id != "":
		return
	_downloading_pack_id = ""
	progress_label.text = "Download complete! Pack added."
	download_button.disabled = false
	download_button.text = "Done"
	# Replace the download handler with a close handler
	if download_button.pressed.is_connected(_on_download_pressed):
		download_button.pressed.disconnect(_on_download_pressed)
	download_button.pressed.connect(func() -> void: animate_out())
	pack_downloaded.emit(pack_id)


func _on_pack_download_failed(pack_id: String, error: String) -> void:
	if pack_id != _downloading_pack_id and _downloading_pack_id != "":
		return
	_downloading_pack_id = ""
	progress_label.text = "Download failed: %s" % error
	progress_label.visible = true
	download_button.disabled = false
