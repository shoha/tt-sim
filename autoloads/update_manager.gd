extends Node

## Manages checking for and downloading game updates from GitHub Releases.
## Queries the GitHub API at startup to detect new versions and provides
## download functionality with progress tracking.
##
## Update Strategy:
## - Downloads are saved to user://updates/ with a .pending marker file
## - On next startup, _apply_pending_update() checks for and applies any pending update
## - This avoids file locking issues since the update is applied before the game fully loads

const GITHUB_API_URL: String = "https://api.github.com/repos/shoha/tt-sim/releases"
const GITHUB_RELEASES_URL: String = "https://github.com/shoha/tt-sim/releases"
const UPDATE_CHECK_TIMEOUT: float = 15.0
const DOWNLOAD_TIMEOUT: float = 300.0  # 5 minutes for large downloads
const SETTINGS_FILE: String = "user://settings.cfg"
const UPDATES_DIR: String = "user://updates/"
const PENDING_UPDATE_FILE: String = "user://updates/pending_update.json"
const UPDATE_SUCCESS_FILE: String = "user://updates/update_success.txt"
const UPDATE_LOG_FILE: String = "user://updates/update_log.txt"

## Result of the last update attempt (for showing toast after UIManager is ready)
var _pending_toast_message: String = ""
var _pending_toast_is_error: bool = false

## Emitted when a new update is available
signal update_available(release_info: Dictionary)

## Emitted during update download (0.0 to 1.0, or -1 for indeterminate)
signal update_download_progress(percent: float)

## Emitted when update download completes successfully
signal update_download_complete(zip_path: String)

## Emitted when update download fails
signal update_download_failed(error: String)

## Emitted when update check fails (network error, etc.)
signal update_check_failed(error: String)

## Emitted when update check completes (whether update found or not)
signal update_check_complete(has_update: bool)

## Emitted when a pending update is being applied (before restart)
signal applying_pending_update(version: String)

## Emitted when update cannot be applied due to App Translocation (macOS)
signal update_blocked_by_translocation

## Latest available release info (populated after check)
var latest_release: Dictionary = {}

## Whether an update check is in progress
var is_checking: bool = false

## Whether an update download is in progress
var is_downloading: bool = false

## Current download progress (0.0 to 1.0)
var download_progress: float = 0.0

var _http_check: HTTPRequest
var _http_download: HTTPRequest
var _download_path: String = ""


func _ready() -> void:
	# Ensure updates directory exists
	if not DirAccess.dir_exists_absolute(UPDATES_DIR):
		DirAccess.make_dir_recursive_absolute(UPDATES_DIR)

	# Clean up old executables from previous updates (Windows)
	_cleanup_old_executables()

	# Check for update success from a previous restart (persisted to disk)
	_load_update_success_toast()

	# Check for and apply any pending update from a previous download
	_apply_pending_update()

	# Show any pending toast message after UIManager is ready
	if not _pending_toast_message.is_empty():
		call_deferred("_show_deferred_toast")


## Show a toast that was queued during startup (before UIManager was ready)
func _show_deferred_toast() -> void:
	# Wait a frame for UIManager's deferred _setup_ui_components to complete
	await get_tree().process_frame

	if _pending_toast_message.is_empty():
		return

	var ui_manager = get_node_or_null("/root/UIManager")
	if ui_manager:
		if _pending_toast_is_error:
			ui_manager.show_error(_pending_toast_message)
		else:
			ui_manager.show_success(_pending_toast_message)

	_pending_toast_message = ""


## Load a persisted update success toast from a previous restart
func _load_update_success_toast() -> void:
	if not FileAccess.file_exists(UPDATE_SUCCESS_FILE):
		return
	var file = FileAccess.open(UPDATE_SUCCESS_FILE, FileAccess.READ)
	if file:
		var version = file.get_as_text().strip_edges()
		file.close()
		if not version.is_empty():
			_pending_toast_message = "Updated to v%s" % version
			_pending_toast_is_error = false
	DirAccess.remove_absolute(UPDATE_SUCCESS_FILE)


## Persist the update success version to disk so the toast survives a restart
func _save_update_success_toast(version: String) -> void:
	var file = FileAccess.open(UPDATE_SUCCESS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(version)
		file.close()


## Show a dialog explaining App Translocation and how to fix it (macOS only)
func _show_translocation_dialog() -> void:
	# Wait for UI to be ready
	await get_tree().process_frame

	var ui_manager = get_node_or_null("/root/UIManager")
	if not ui_manager:
		return

	var title = "Update Requires App Relocation"
	var message = """An update is ready but cannot be installed because macOS is running the app from a temporary location.

To install the update:
1. Quit the app
2. Move TTSim.app to your Applications folder (or another permanent location)
3. Open the app from its new location

The update will install automatically when you next open the app from a permanent location."""

	ui_manager.show_confirmation(
		title,
		message,
		"Open Downloads",
		"OK",
		func(): OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR)),
		Callable(),
		"Warning"
	)


## Log a message to both console and persistent log file
func _log(message: String) -> void:
	print("UpdateManager: " + message)

	# Also write to log file for debugging (especially useful on macOS)
	var file = FileAccess.open(UPDATE_LOG_FILE, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(UPDATE_LOG_FILE, FileAccess.WRITE)
	if file:
		file.seek_end()
		var timestamp = Time.get_datetime_string_from_system()
		file.store_line("[%s] %s" % [timestamp, message])
		file.close()


## Clean up .old executables left over from previous updates (Windows only)
func _cleanup_old_executables() -> void:
	UpdateInstaller.cleanup_old_executables()


## Get the current application version from project settings
func get_current_version() -> String:
	return UpdateVersion.get_current()


## Check if prerelease updates are enabled in settings
func is_prerelease_enabled() -> bool:
	var config = ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		return config.get_value("updates", "check_prereleases", false)
	return false


## Set the prerelease preference
func set_prerelease_enabled(enabled: bool) -> void:
	var config = ConfigFile.new()
	config.load(SETTINGS_FILE)  # OK if doesn't exist
	config.set_value("updates", "check_prereleases", enabled)
	config.save(SETTINGS_FILE)


## Check if there's a pending update waiting to be applied
func has_pending_update() -> bool:
	return FileAccess.file_exists(PENDING_UPDATE_FILE)


## Get info about the pending update, or empty dict if none
func get_pending_update_info() -> Dictionary:
	if not FileAccess.file_exists(PENDING_UPDATE_FILE):
		return {}

	var file = FileAccess.open(PENDING_UPDATE_FILE, FileAccess.READ)
	if not file:
		return {}

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK or not json.data is Dictionary:
		return {}

	return json.data


## Check for updates by querying GitHub Releases API
func check_for_updates() -> void:
	if is_checking:
		return

	# Skip check if we already have a pending update
	if has_pending_update():
		var pending = get_pending_update_info()
		print(
			(
				"UpdateManager: Skipping update check - pending update v%s ready"
				% pending.get("version", "?")
			)
		)
		update_check_complete.emit(false)
		return

	is_checking = true
	latest_release = {}

	# Create HTTP request for API call
	_http_check = HTTPRequest.new()
	_http_check.timeout = UPDATE_CHECK_TIMEOUT
	add_child(_http_check)
	_http_check.request_completed.connect(_on_check_completed)

	# GitHub API requires User-Agent header
	var headers = ["User-Agent: TTSim-Game-Client", "Accept: application/vnd.github.v3+json"]

	var error = _http_check.request(GITHUB_API_URL, headers)
	if error != OK:
		_cleanup_check()
		update_check_failed.emit("Failed to start update check: " + str(error))
		update_check_complete.emit(false)
		return

	print("UpdateManager: Checking for updates...")


## Handle update check response
func _on_check_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_cleanup_check()

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = _get_http_error(result)
		print("UpdateManager: Check failed - " + error_msg)
		update_check_failed.emit(error_msg)
		update_check_complete.emit(false)
		return

	if response_code != 200:
		print("UpdateManager: Check failed - HTTP " + str(response_code))
		update_check_failed.emit("GitHub API returned " + str(response_code))
		update_check_complete.emit(false)
		return

	# Parse JSON response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		print("UpdateManager: Failed to parse releases JSON")
		update_check_failed.emit("Failed to parse release data")
		update_check_complete.emit(false)
		return

	var releases = json.data
	if not releases is Array or releases.is_empty():
		print("UpdateManager: No releases found")
		update_check_complete.emit(false)
		return

	# Sort releases by published_at descending (API order is unreliable)
	releases.sort_custom(
		func(a, b):
			var date_a = a.get("published_at", "") if a is Dictionary else ""
			var date_b = b.get("published_at", "") if b is Dictionary else ""
			return date_a > date_b  # Descending order (newest first)
	)

	# Find the best release (respecting prerelease setting)
	var check_prereleases = is_prerelease_enabled()
	var best_release: Dictionary = {}

	for release in releases:
		if not release is Dictionary:
			continue

		var is_prerelease = release.get("prerelease", false)
		var is_draft = release.get("draft", false)

		# Skip drafts always
		if is_draft:
			continue

		# Skip prereleases if not enabled
		if is_prerelease and not check_prereleases:
			continue

		# First valid release is the latest (sorted by published_at)
		best_release = release
		break

	if best_release.is_empty():
		print("UpdateManager: No suitable release found")
		update_check_complete.emit(false)
		return

	# Parse release info first to get normalized version
	latest_release = _parse_release_info(best_release)
	var current_version = get_current_version()
	var release_version = latest_release.version

	print("UpdateManager: Current version: %s, Latest: %s" % [current_version, release_version])

	# Check if update is available
	var is_newer = false

	# For dev builds (both have "build." in suffix), compare by checking if different
	if UpdateVersion.is_dev_build(current_version) and UpdateVersion.is_dev_build(release_version):
		is_newer = (current_version != release_version)
		if is_newer:
			print("UpdateManager: Different dev build detected")
	else:
		is_newer = UpdateVersion.is_newer(release_version, current_version)

	if is_newer:
		print("UpdateManager: Update available - %s" % release_version)
		update_available.emit(latest_release)
		update_check_complete.emit(true)
	else:
		print("UpdateManager: Already up to date")
		latest_release = {}
		update_check_complete.emit(false)


## Parse release info into a standardized dictionary
func _parse_release_info(release: Dictionary) -> Dictionary:
	var tag = release.get("tag_name", "")
	var assets = release.get("assets", [])

	var version = UpdateVersion.normalize_tag(tag)

	# Find platform-specific download URL
	var platform = UpdateVersion.get_platform_name()
	var download_url = ""
	var download_size: int = 0

	for asset in assets:
		var asset_name = asset.get("name", "")
		if platform in asset_name.to_lower():
			download_url = asset.get("browser_download_url", "")
			download_size = asset.get("size", 0)
			break

	return {
		"version": version,
		"tag": tag,
		"name": release.get("name", tag),
		"body": release.get("body", ""),
		"prerelease": release.get("prerelease", false),
		"published_at": release.get("published_at", ""),
		"html_url": release.get("html_url", ""),
		"download_url": download_url,
		"download_size": download_size,
	}


## Download the update for the current platform
func download_update() -> void:
	if is_downloading:
		return

	if latest_release.is_empty() or latest_release.download_url.is_empty():
		update_download_failed.emit("No download URL available")
		return

	is_downloading = true
	download_progress = 0.0

	# Prepare download path
	var filename = "TTSim-%s-%s.zip" % [UpdateVersion.get_platform_name(), latest_release.version]
	_download_path = UPDATES_DIR + filename

	# Clean up any existing partial download
	if FileAccess.file_exists(_download_path):
		DirAccess.remove_absolute(_download_path)

	# Create HTTP request for download
	_http_download = HTTPRequest.new()
	_http_download.timeout = DOWNLOAD_TIMEOUT
	_http_download.download_file = _download_path
	_http_download.use_threads = true
	add_child(_http_download)
	_http_download.request_completed.connect(_on_download_completed)

	var headers = ["User-Agent: TTSim-Game-Client"]
	var error = _http_download.request(latest_release.download_url, headers)

	if error != OK:
		_cleanup_download()
		update_download_failed.emit("Failed to start download: " + str(error))
		return

	print("UpdateManager: Starting download of %s" % latest_release.version)


func _process(_delta: float) -> void:
	# Update download progress
	if is_downloading and _http_download:
		var downloaded = _http_download.get_downloaded_bytes()
		var total = _http_download.get_body_size()

		if total > 0:
			var new_progress = float(downloaded) / float(total)
			if abs(new_progress - download_progress) > 0.01:
				download_progress = new_progress
				update_download_progress.emit(download_progress)
		elif downloaded > 0:
			update_download_progress.emit(-1.0)  # Indeterminate


## Handle download completion
func _on_download_completed(
	result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray
) -> void:
	_cleanup_download()

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = _get_http_error(result)
		print("UpdateManager: Download failed - " + error_msg)
		_cleanup_download_file()
		update_download_failed.emit(error_msg)
		return

	if response_code < 200 or response_code >= 300:
		print("UpdateManager: Download failed - HTTP " + str(response_code))
		_cleanup_download_file()
		update_download_failed.emit("Download failed: HTTP " + str(response_code))
		return

	if not FileAccess.file_exists(_download_path):
		print("UpdateManager: Download completed but file not found")
		update_download_failed.emit("Download completed but file not found")
		return

	# Create pending update marker so we apply it on next startup
	_create_pending_update_marker(_download_path, latest_release.version)

	print("UpdateManager: Download complete - %s" % _download_path)
	update_download_complete.emit(_download_path)


## Create a marker file indicating an update is ready to be applied
func _create_pending_update_marker(zip_path: String, version: String) -> void:
	var pending_info = {
		"zip_path": zip_path,
		"version": version,
		"exe_path": OS.get_executable_path(),
		"install_dir": OS.get_executable_path().get_base_dir(),
		"created_at": Time.get_datetime_string_from_system()
	}

	var file = FileAccess.open(PENDING_UPDATE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(pending_info, "\t"))
		file.close()
		print("UpdateManager: Pending update marker created for v%s" % version)
	else:
		push_error("UpdateManager: Failed to create pending update marker")


## Check for and apply any pending update on startup
func _apply_pending_update() -> void:
	if not FileAccess.file_exists(PENDING_UPDATE_FILE):
		return

	_log("Found pending update marker, checking...")
	_log("Platform: %s" % OS.get_name())
	_log("Executable path: %s" % OS.get_executable_path())

	# Read the pending update info
	var file = FileAccess.open(PENDING_UPDATE_FILE, FileAccess.READ)
	if not file:
		_log("ERROR: Could not open pending update file")
		_cleanup_pending_update()
		return

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		_log("ERROR: Failed to parse pending update marker")
		_cleanup_pending_update()
		return

	var pending_info = json.data
	if not pending_info is Dictionary:
		_log("ERROR: Pending update data is not a dictionary")
		_cleanup_pending_update()
		return

	var zip_path = pending_info.get("zip_path", "")
	var version = pending_info.get("version", "unknown")
	var stored_install_dir = pending_info.get("install_dir", "")

	_log("Pending update version: %s" % version)
	_log("Zip path: %s" % zip_path)
	_log("Stored install_dir: %s" % stored_install_dir)

	# Verify the zip still exists
	var global_zip = ProjectSettings.globalize_path(zip_path)
	_log("Globalized zip path: %s" % global_zip)

	if not FileAccess.file_exists(zip_path):
		_log("ERROR: Pending update zip not found at: %s" % zip_path)
		_log("Checking globalized path exists: %s" % FileAccess.file_exists(global_zip))
		_cleanup_pending_update()
		_pending_toast_message = "Update file not found"
		_pending_toast_is_error = true
		return

	# Verify we're running from the expected location
	var current_exe_path = OS.get_executable_path()
	var current_exe_dir = current_exe_path.get_base_dir()

	_log("Current exe dir: %s" % current_exe_dir)

	# On macOS, the stored path might differ from current due to symlinks or translocation
	var location_ok = false
	if OS.get_name() == "macOS":
		var stored_app = UpdateInstaller.extract_app_name_from_path(stored_install_dir)
		var current_app = UpdateInstaller.extract_app_name_from_path(current_exe_dir)
		_log("Stored app name: '%s', Current app name: '%s'" % [stored_app, current_app])
		location_ok = (stored_app == current_app and not stored_app.is_empty())

		if not location_ok:
			location_ok = (stored_install_dir == current_exe_dir)
	else:
		location_ok = (stored_install_dir == current_exe_dir)

	if not location_ok:
		_log("WARNING: Running from different location than expected, skipping update")
		_log("  Expected: %s" % stored_install_dir)
		_log("  Current: %s" % current_exe_dir)
		_cleanup_pending_update()
		_pending_toast_message = "Update skipped - app location changed"
		_pending_toast_is_error = true
		return

	_log("Applying pending update v%s..." % version)
	applying_pending_update.emit(version)

	# Apply the update based on platform (delegating to UpdateInstaller)
	var log_fn := Callable(self, "_log")
	var success = false
	match OS.get_name():
		"Windows":
			success = UpdateInstaller.extract_windows(zip_path, stored_install_dir, log_fn)
		"macOS":
			success = UpdateInstaller.extract_macos(zip_path, log_fn)
		_:
			_log("ERROR: Unsupported platform for auto-update: %s" % OS.get_name())

	if success:
		_log("Update applied successfully!")
		_cleanup_pending_update()
		# Delete the zip file after successful extraction
		DirAccess.remove_absolute(zip_path)

		# Persist success toast so it survives the restart
		_save_update_success_toast(version)

		# Restart to run the new executable — the current process is still the old binary
		match OS.get_name():
			"Windows":
				_log("Restarting to run updated executable...")
				var new_exe_path = pending_info.get("exe_path", "")
				if not new_exe_path.is_empty() and FileAccess.file_exists(new_exe_path):
					OS.create_process(new_exe_path, [])
					get_tree().quit()
			"macOS":
				_log("Restarting to run updated executable...")
				UpdateInstaller.restart_macos(OS.get_executable_path(), get_tree())

		# Fallback: if restart didn't happen, show toast in current session
		_pending_toast_message = "Updated to v%s" % version
		_pending_toast_is_error = false
	else:
		_log("ERROR: Failed to apply update - see above for details")
		_pending_toast_message = "Update failed - check update_log.txt"
		_pending_toast_is_error = true
		# Leave the marker so we can retry next time
		push_error("UpdateManager: Update extraction failed - will retry on next startup")


## macOS extraction wrapper — delegates to UpdateInstaller but handles
## App Translocation detection (which requires emitting signals on this node).
func _extract_update_macos(zip_path: String) -> bool:
	var exe_path = OS.get_executable_path()
	var app_path = exe_path
	while not app_path.ends_with(".app") and app_path != "/":
		app_path = app_path.get_base_dir()

	# Detect App Translocation before delegating
	if app_path.ends_with(".app"):
		if "/private/var/folders/" in app_path or "/AppTranslocation/" in app_path:
			_log("ERROR: App Translocation detected")
			update_blocked_by_translocation.emit()
			call_deferred("_show_translocation_dialog")
			return false

	var log_fn := Callable(self, "_log")
	return UpdateInstaller.extract_macos(zip_path, log_fn)


## Clean up pending update marker and related files
func _cleanup_pending_update() -> void:
	if FileAccess.file_exists(PENDING_UPDATE_FILE):
		DirAccess.remove_absolute(PENDING_UPDATE_FILE)
		print("UpdateManager: Cleaned up pending update marker")


## Cancel a pending update (removes the marker and downloaded zip)
func cancel_pending_update() -> void:
	if not FileAccess.file_exists(PENDING_UPDATE_FILE):
		return

	var pending = get_pending_update_info()
	var zip_path = pending.get("zip_path", "")

	# Remove the zip file if it exists
	if not zip_path.is_empty() and FileAccess.file_exists(zip_path):
		DirAccess.remove_absolute(zip_path)
		print("UpdateManager: Removed pending update zip")

	_cleanup_pending_update()


## Apply the downloaded update by restarting the game
## On Windows, the actual extraction happens on next startup via _apply_pending_update()
## On macOS, we extract in-place before restarting (no file locking issues)
func apply_update(zip_path: String) -> void:
	print("UpdateManager: Restarting to apply update...")

	match OS.get_name():
		"Windows":
			UpdateInstaller.restart_windows(OS.get_executable_path(), get_tree())
		"macOS":
			_apply_and_restart_macos(zip_path)
		_:
			print("UpdateManager: Please restart the game to apply the update")
			get_tree().quit()


## Apply update and restart on macOS in a single step to avoid double-restart.
func _apply_and_restart_macos(zip_path: String) -> void:
	var pending = get_pending_update_info()
	var version = pending.get("version", "unknown")

	_log("Extracting update v%s before restart (avoiding double-restart)..." % version)

	var success = _extract_update_macos(zip_path)
	if success:
		_log("Update extracted successfully, restarting into new version...")
		_cleanup_pending_update()
		DirAccess.remove_absolute(zip_path)
		_save_update_success_toast(version)

	UpdateInstaller.restart_macos(OS.get_executable_path(), get_tree())


## Open the releases page in the default browser
func open_releases_page() -> void:
	if latest_release.has("html_url") and not latest_release.html_url.is_empty():
		OS.shell_open(latest_release.html_url)
	else:
		OS.shell_open(GITHUB_RELEASES_URL)


## Open the downloads folder in the file manager
func open_downloads_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))


## Cancel an in-progress download
func cancel_download() -> void:
	if is_downloading and _http_download:
		_http_download.cancel_request()
		_cleanup_download()
		_cleanup_download_file()


## Clean up after check completes
func _cleanup_check() -> void:
	is_checking = false
	if _http_check:
		_http_check.queue_free()
		_http_check = null


## Clean up after download completes
func _cleanup_download() -> void:
	is_downloading = false
	download_progress = 0.0
	if _http_download:
		_http_download.queue_free()
		_http_download = null


## Clean up partial download file
func _cleanup_download_file() -> void:
	if not _download_path.is_empty() and FileAccess.file_exists(_download_path):
		DirAccess.remove_absolute(_download_path)
	_download_path = ""


## Get human-readable error message for HTTP result
func _get_http_error(result: int) -> String:
	return UpdateInstaller.get_http_error(result)
