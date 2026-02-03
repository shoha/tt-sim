extends Node

## Manages checking for and downloading game updates from GitHub Releases.
## Queries the GitHub API at startup to detect new versions and provides
## download functionality with progress tracking.

const GITHUB_API_URL: String = "https://api.github.com/repos/shoha/tt-sim/releases"
const GITHUB_RELEASES_URL: String = "https://github.com/shoha/tt-sim/releases"
const UPDATE_CHECK_TIMEOUT: float = 15.0
const DOWNLOAD_TIMEOUT: float = 300.0 # 5 minutes for large downloads
const SETTINGS_FILE: String = "user://settings.cfg"
const UPDATES_DIR: String = "user://updates/"

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


## Get the current application version from project settings
func get_current_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "0.0.0-dev")


## Check if prerelease updates are enabled in settings
func is_prerelease_enabled() -> bool:
	var config = ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		return config.get_value("updates", "check_prereleases", false)
	return false


## Set the prerelease preference
func set_prerelease_enabled(enabled: bool) -> void:
	var config = ConfigFile.new()
	config.load(SETTINGS_FILE) # OK if doesn't exist
	config.set_value("updates", "check_prereleases", enabled)
	config.save(SETTINGS_FILE)


## Check for updates by querying GitHub Releases API
func check_for_updates() -> void:
	if is_checking:
		return
	
	is_checking = true
	latest_release = {}
	
	# Create HTTP request for API call
	_http_check = HTTPRequest.new()
	_http_check.timeout = UPDATE_CHECK_TIMEOUT
	add_child(_http_check)
	_http_check.request_completed.connect(_on_check_completed)
	
	# GitHub API requires User-Agent header
	var headers = [
		"User-Agent: TTSim-Game-Client",
		"Accept: application/vnd.github.v3+json"
	]
	
	var error = _http_check.request(GITHUB_API_URL, headers)
	if error != OK:
		_cleanup_check()
		update_check_failed.emit("Failed to start update check: " + str(error))
		update_check_complete.emit(false)
		return
	
	print("UpdateManager: Checking for updates...")


## Handle update check response
func _on_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
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
	releases.sort_custom(func(a, b):
		var date_a = a.get("published_at", "") if a is Dictionary else ""
		var date_b = b.get("published_at", "") if b is Dictionary else ""
		return date_a > date_b # Descending order (newest first)
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
	# Since commit hashes aren't orderable, any different dev build is potentially newer
	if _is_dev_build(current_version) and _is_dev_build(release_version):
		# Different commit hash = different build, offer update
		is_newer = (current_version != release_version)
		if is_newer:
			print("UpdateManager: Different dev build detected")
	else:
		# Standard semver comparison
		is_newer = _is_newer_version(release_version, current_version)
	
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
	
	# Normalize version from tag
	# - "v1.0.0" -> "1.0.0"
	# - "build-abc123" -> "0.0.0-build.abc123" (to match project.godot format)
	var version = tag
	if tag.begins_with("v"):
		version = tag.substr(1)
	elif tag.begins_with("build-"):
		version = "0.0.0-build." + tag.substr(6)
	
	# Find platform-specific download URL
	var platform = _get_platform_name()
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


## Get the platform name for asset matching
func _get_platform_name() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		"Linux":
			return "linux"
		_:
			return OS.get_name().to_lower()


## Check if a version is a dev build (contains "build." in suffix)
func _is_dev_build(version: String) -> bool:
	return "-build." in version or version.begins_with("build.")


## Compare two semantic versions, returns true if version_a > version_b
func _is_newer_version(version_a: String, version_b: String) -> bool:
	var parts_a = _parse_version(version_a)
	var parts_b = _parse_version(version_b)
	
	# Compare major.minor.patch
	for i in range(3):
		if parts_a[i] > parts_b[i]:
			return true
		elif parts_a[i] < parts_b[i]:
			return false
	
	# Same base version - check prerelease suffix
	# A release version (no suffix) is newer than a prerelease
	var suffix_a = parts_a[3]
	var suffix_b = parts_b[3]
	
	if suffix_a.is_empty() and not suffix_b.is_empty():
		return true # a is release, b is prerelease
	if not suffix_a.is_empty() and suffix_b.is_empty():
		return false # a is prerelease, b is release
	
	# Both have suffixes or both don't - compare lexically
	return suffix_a > suffix_b


## Parse a version string into [major, minor, patch, suffix]
func _parse_version(version: String) -> Array:
	# Handle versions like "1.2.3-beta", "1.2.3", "0.0.0-build.abc123"
	var suffix = ""
	var base = version
	
	var dash_pos = version.find("-")
	if dash_pos >= 0:
		base = version.substr(0, dash_pos)
		suffix = version.substr(dash_pos + 1)
	
	var parts = base.split(".")
	var major = int(parts[0]) if parts.size() > 0 else 0
	var minor = int(parts[1]) if parts.size() > 1 else 0
	var patch = int(parts[2]) if parts.size() > 2 else 0
	
	return [major, minor, patch, suffix]


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
	var filename = "TTSim-%s-%s.zip" % [_get_platform_name(), latest_release.version]
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
			update_download_progress.emit(-1.0) # Indeterminate


## Handle download completion
func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
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
	
	print("UpdateManager: Download complete - %s" % _download_path)
	update_download_complete.emit(_download_path)


## Apply the downloaded update (platform-specific)
func apply_update(zip_path: String) -> void:
	var exe_path = OS.get_executable_path()
	var install_dir = exe_path.get_base_dir()
	
	match OS.get_name():
		"Windows":
			_apply_update_windows(zip_path, install_dir, exe_path)
		"macOS":
			_apply_update_macos(zip_path, install_dir)
		_:
			# Fallback: just open the downloads folder
			OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))


## Apply update on Windows using a batch script
func _apply_update_windows(zip_path: String, install_dir: String, exe_path: String) -> void:
	var global_zip = ProjectSettings.globalize_path(zip_path)
	var global_install = install_dir
	var global_exe = exe_path
	
	# Create update batch script
	var script_path = UPDATES_DIR + "update.bat"
	var global_script = ProjectSettings.globalize_path(script_path)
	
	var script = """@echo off
echo Waiting for game to close...
timeout /t 2 /nobreak >nul

echo Extracting update...
powershell -command "Expand-Archive -Path '%s' -DestinationPath '%s' -Force"

echo Launching updated game...
start "" "%s"

echo Cleaning up...
del "%s"
del "%%~f0"
""" % [global_zip, global_install, global_exe, global_zip]
	
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script)
		file.close()
		
		# Launch the script and quit the game
		OS.create_process("cmd.exe", ["/c", global_script])
		get_tree().quit()
	else:
		push_error("UpdateManager: Failed to create update script")
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))


## Apply update on macOS using a shell script
func _apply_update_macos(zip_path: String, install_dir: String) -> void:
	var global_zip = ProjectSettings.globalize_path(zip_path)
	var global_install = install_dir
	
	# For macOS, the app bundle needs to be replaced
	# Find the .app bundle path
	var app_path = global_install
	while not app_path.ends_with(".app") and app_path != "/":
		app_path = app_path.get_base_dir()
	
	if not app_path.ends_with(".app"):
		# Fallback: just open the downloads folder
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		return
	
	var script_path = UPDATES_DIR + "update.sh"
	var global_script = ProjectSettings.globalize_path(script_path)
	
	var script = """#!/bin/bash
sleep 2
unzip -o "%s" -d "%s"
rm "%s"
open "%s"
rm "$0"
""" % [global_zip, app_path.get_base_dir(), global_zip, app_path]
	
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script)
		file.close()
		
		# Make executable and run
		OS.execute("chmod", ["+x", global_script])
		OS.create_process("/bin/bash", [global_script])
		get_tree().quit()
	else:
		push_error("UpdateManager: Failed to create update script")
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))


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
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Cannot connect to server"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Cannot resolve hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "No response from server"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Response too large"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Cannot open download file"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Error writing download file"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "Too many redirects"
		HTTPRequest.RESULT_TIMEOUT:
			return "Request timed out"
		_:
			return "Unknown error: " + str(result)
