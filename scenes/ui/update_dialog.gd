extends AnimatedCanvasLayerPanel
class_name UpdateDialogUI

## Dialog shown when a game update is available.
## Displays version info, release notes, and provides download functionality.

signal closed

@onready var title_label: Label = %TitleLabel
@onready var version_label: Label = %VersionLabel
@onready var release_notes_container: ScrollContainer = %ReleaseNotesContainer
@onready var release_notes: RichTextLabel = %ReleaseNotes
@onready var progress_container: VBoxContainer = %ProgressContainer
@onready var progress_label: Label = %ProgressLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var button_container: HBoxContainer = %ButtonContainer
@onready var download_button: Button = %DownloadButton
@onready var view_button: Button = %ViewButton
@onready var skip_button: Button = %SkipButton
@onready var post_download_buttons: HBoxContainer = %PostDownloadButtons
@onready var restart_button: Button = %RestartButton
@onready var later_button: Button = %LaterButton
@onready var open_folder_button: Button = %OpenFolderButton

var _release_info: Dictionary = {}
var _download_path: String = ""


func _on_panel_ready() -> void:
	# Connect buttons
	download_button.pressed.connect(_on_download_pressed)
	view_button.pressed.connect(_on_view_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	later_button.pressed.connect(_on_later_pressed)
	open_folder_button.pressed.connect(_on_open_folder_pressed)
	
	# Connect to UpdateManager signals
	UpdateManager.update_download_progress.connect(_on_download_progress)
	UpdateManager.update_download_complete.connect(_on_download_complete)
	UpdateManager.update_download_failed.connect(_on_download_failed)
	
	# Connect RichTextLabel link clicks
	release_notes.meta_clicked.connect(_on_link_clicked)


func _on_after_animate_in() -> void:
	download_button.grab_focus()


func _on_after_animate_out() -> void:
	closed.emit()
	queue_free()


func _on_link_clicked(meta: Variant) -> void:
	# Open URL in browser
	if meta is String and (meta.begins_with("http://") or meta.begins_with("https://")):
		OS.shell_open(meta)


func setup(release_info: Dictionary) -> void:
	_release_info = release_info
	
	var current_version = UpdateManager.get_current_version()
	var new_version = release_info.get("version", "?")
	
	# Update labels
	if release_info.get("prerelease", false):
		title_label.text = "Prerelease Update Available"
	else:
		title_label.text = "Update Available"
	
	version_label.text = "v%s → v%s" % [current_version, new_version]
	
	# Parse and display release notes
	var body = release_info.get("body", "")
	if body.is_empty():
		release_notes.text = "No release notes available."
	else:
		# Convert GitHub markdown to BBCode (basic conversion)
		release_notes.text = _markdown_to_bbcode(body)
	
	# Show/hide download button based on platform availability
	if release_info.get("download_url", "").is_empty():
		download_button.visible = false
		download_button.tooltip_text = "No download available for your platform"


func _markdown_to_bbcode(markdown: String) -> String:
	var text = markdown
	
	# Convert headers
	text = text.replace("### ", "[b]")
	text = text.replace("## ", "[b][u]")
	text = text.replace("# ", "[b][u]")
	
	# Basic bold/italic (simplified)
	var bold_regex = RegEx.new()
	bold_regex.compile("\\*\\*(.+?)\\*\\*")
	text = bold_regex.sub(text, "[b]$1[/b]", true)
	
	var italic_regex = RegEx.new()
	italic_regex.compile("\\*(.+?)\\*")
	text = italic_regex.sub(text, "[i]$1[/i]", true)
	
	# Convert bullet points
	text = text.replace("\n- ", "\n• ")
	text = text.replace("\n* ", "\n• ")
	
	# Convert inline code
	var code_regex = RegEx.new()
	code_regex.compile("`(.+?)`")
	text = code_regex.sub(text, "[code]$1[/code]", true)
	
	# Convert markdown links [text](url) to BBCode [url=...]text[/url]
	var link_regex = RegEx.new()
	link_regex.compile("\\[([^\\]]+)\\]\\(([^\\)]+)\\)")
	text = link_regex.sub(text, "[url=$2]$1[/url]", true)
	
	return text


func _on_download_pressed() -> void:
	# Start download
	download_button.disabled = true
	skip_button.disabled = true
	progress_container.visible = true
	progress_bar.value = 0
	progress_label.text = "Starting download..."
	
	UpdateManager.download_update()


func _on_view_pressed() -> void:
	UpdateManager.open_releases_page()


func _on_skip_pressed() -> void:
	animate_out()


func _on_restart_pressed() -> void:
	if not _download_path.is_empty():
		UpdateManager.apply_update(_download_path)
	else:
		animate_out()


func _on_later_pressed() -> void:
	animate_out()


func _on_open_folder_pressed() -> void:
	UpdateManager.open_downloads_folder()


func _on_download_progress(percent: float) -> void:
	if percent < 0:
		# Indeterminate progress
		progress_label.text = "Downloading..."
		progress_bar.value = 50 # Could use animated indeterminate style
	else:
		progress_bar.value = percent * 100
		progress_label.text = "Downloading... %d%%" % int(percent * 100)


func _on_download_complete(zip_path: String) -> void:
	_download_path = zip_path
	
	# Update UI for post-download state
	progress_container.visible = false
	button_container.visible = false
	post_download_buttons.visible = true
	
	title_label.text = "Ready to Update"
	release_notes.text = "The update has been downloaded and will be installed when the game restarts.\n\nClick 'Restart Now' to apply the update immediately, or 'Later' to continue playing. The update will be applied the next time you start the game."
	
	restart_button.grab_focus()


func _on_download_failed(error: String) -> void:
	# Reset UI and show error
	download_button.disabled = false
	skip_button.disabled = false
	progress_container.visible = false
	
	progress_label.text = "Download failed: " + error
	progress_container.visible = true
	progress_bar.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not UpdateManager.is_downloading:
			_on_skip_pressed()
		get_viewport().set_input_as_handled()
