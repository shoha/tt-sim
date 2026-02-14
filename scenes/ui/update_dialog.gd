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
@onready var commit_link: LinkButton = %CommitLink
@onready var post_download_buttons: HBoxContainer = %PostDownloadButtons
@onready var restart_button: Button = %RestartButton
@onready var later_button: Button = %LaterButton
@onready var open_folder_button: Button = %OpenFolderButton

const GITHUB_COMMIT_URL := "https://github.com/shoha/tt-sim/commit/"

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


func _on_before_animate_out() -> void:
	if UpdateManager.update_download_progress.is_connected(_on_download_progress):
		UpdateManager.update_download_progress.disconnect(_on_download_progress)
	if UpdateManager.update_download_complete.is_connected(_on_download_complete):
		UpdateManager.update_download_complete.disconnect(_on_download_complete)
	if UpdateManager.update_download_failed.is_connected(_on_download_failed):
		UpdateManager.update_download_failed.disconnect(_on_download_failed)


func _on_after_animate_out() -> void:
	closed.emit()
	queue_free()


func _on_link_clicked(meta: Variant) -> void:
	# Open URL in browser
	if meta is String and (meta.begins_with("http://") or meta.begins_with("https://")):
		OS.shell_open(meta)


## Extract the short commit hash from a dev build version like "0.0.0-build.abc123"
static func _extract_commit_hash(version: String) -> String:
	var prefix := "-build."
	var idx := version.find(prefix)
	if idx >= 0:
		return version.substr(idx + prefix.length())
	return ""


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

	# Show a clickable commit link for dev builds (version contains "build.")
	var commit_hash := _extract_commit_hash(new_version)
	if not commit_hash.is_empty():
		commit_link.uri = GITHUB_COMMIT_URL + commit_hash
		commit_link.text = "commit %s" % commit_hash
		commit_link.tooltip_text = commit_link.uri
		commit_link.visible = true

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

	# Normalize line endings
	text = text.replace("\r", "")

	# Convert markdown links [text](url) to BBCode (first, before anything touches brackets)
	var link_regex = RegEx.new()
	link_regex.compile("\\[([^\\]]+)\\]\\(([^\\)]+)\\)")
	text = link_regex.sub(text, "[url=$2]$1[/url]", true)

	# Convert raw/bare URLs into clickable links (lookbehind skips urls already in [url=...])
	var raw_url_regex = RegEx.new()
	raw_url_regex.compile("(?<!=)(https?://[^\\s<>\\[\\]()]+)")
	text = raw_url_regex.sub(text, "[url=$1]$1[/url]", true)

	# Headers: anchored to line start, with proper closing tags.
	# Process h3 before h2 before h1 so ### isn't consumed by ##.
	var h3_regex = RegEx.new()
	h3_regex.compile("(?m)^### (.+)$")
	text = h3_regex.sub(text, "[b]$1[/b]", true)

	var h2_regex = RegEx.new()
	h2_regex.compile("(?m)^## (.+)$")
	text = h2_regex.sub(text, "[b][u]$1[/u][/b]", true)

	var h1_regex = RegEx.new()
	h1_regex.compile("(?m)^# (.+)$")
	text = h1_regex.sub(text, "[b][u]$1[/u][/b]", true)

	# Bullet points: anchored to line start, before bold/italic so leading * isn't
	# misinterpreted as emphasis
	var bullet_regex = RegEx.new()
	bullet_regex.compile("(?m)^[\\*\\-] ")
	text = bullet_regex.sub(text, "• ", true)

	# Bold (**text**) — must run before italic
	var bold_regex = RegEx.new()
	bold_regex.compile("\\*\\*(.+?)\\*\\*")
	text = bold_regex.sub(text, "[b]$1[/b]", true)

	# Italic (*text*)
	var italic_regex = RegEx.new()
	italic_regex.compile("\\*(.+?)\\*")
	text = italic_regex.sub(text, "[i]$1[/i]", true)

	# Inline code
	var code_regex = RegEx.new()
	code_regex.compile("`(.+?)`")
	text = code_regex.sub(text, "[code]$1[/code]", true)

	return text


func _on_download_pressed() -> void:
	# Start download
	download_button.disabled = true
	skip_button.disabled = true
	progress_container.visible = true
	progress_bar.value = 0
	progress_bar.visible = true
	progress_label.text = "Starting download..."

	# Fade in progress area
	progress_container.modulate.a = 0.0
	var tw = create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(progress_container, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)

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
		progress_bar.value = 50
	else:
		progress_bar.value = percent * 100
		progress_label.text = "Downloading... %d%%" % int(percent * 100)


func _on_download_complete(zip_path: String) -> void:
	_download_path = zip_path

	# Cross-fade into post-download state
	progress_container.visible = false
	button_container.visible = false
	post_download_buttons.visible = true

	title_label.text = "Ready to Update"
	release_notes.text = (
		"The update has been downloaded and will be installed when the game restarts."
		+ "\n\nClick 'Restart Now' to apply the update immediately, or 'Later' to continue playing."
		+ " The update will be applied the next time you start the game."
	)

	# Animate the post-download buttons in
	post_download_buttons.modulate.a = 0.0
	var tw = create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(post_download_buttons, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)

	AudioManager.play_success()
	restart_button.grab_focus()


func _on_download_failed(error: String) -> void:
	# Reset UI and show error
	download_button.disabled = false
	skip_button.disabled = false
	progress_container.visible = false

	progress_label.text = "Download failed: " + error
	progress_container.visible = true
	progress_bar.visible = false
	AudioManager.play_error()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not UpdateManager.is_downloading:
			_on_skip_pressed()
		get_viewport().set_input_as_handled()
