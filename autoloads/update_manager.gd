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
const DOWNLOAD_TIMEOUT: float = 300.0 # 5 minutes for large downloads
const SETTINGS_FILE: String = "user://settings.cfg"
const UPDATES_DIR: String = "user://updates/"
const PENDING_UPDATE_FILE: String = "user://updates/pending_update.json"

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

	# Check for and apply any pending update from a previous download
	_apply_pending_update()


## Clean up .old executables left over from previous updates (Windows only)
func _cleanup_old_executables() -> void:
	if OS.get_name() != "Windows":
		return

	var exe_path = OS.get_executable_path()
	var exe_dir = exe_path.get_base_dir()
	var exe_name = exe_path.get_file()

	# Clean up main executable .old file
	var old_exe_path = exe_dir + "/" + exe_name + ".old"
	if FileAccess.file_exists(old_exe_path):
		var err = DirAccess.remove_absolute(old_exe_path)
		if err == OK:
			print("UpdateManager: Cleaned up old executable: %s" % old_exe_path)
		else:
			print("UpdateManager: Failed to clean up old executable (error %d)" % err)

	# Clean up console wrapper .old file (if export has console wrapper enabled)
	var console_exe_name = exe_name.get_basename() + ".console.exe"
	var old_console_path = exe_dir + "/" + console_exe_name + ".old"
	if FileAccess.file_exists(old_console_path):
		var err = DirAccess.remove_absolute(old_console_path)
		if err == OK:
			print("UpdateManager: Cleaned up old console wrapper: %s" % old_console_path)
		else:
			print("UpdateManager: Failed to clean up old console wrapper (error %d)" % err)


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
		print("UpdateManager: Skipping update check - pending update v%s ready" % pending.get("version", "?"))
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

	print("UpdateManager: Found pending update marker, checking...")

	# Read the pending update info
	var file = FileAccess.open(PENDING_UPDATE_FILE, FileAccess.READ)
	if not file:
		_cleanup_pending_update()
		return

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		print("UpdateManager: Failed to parse pending update marker")
		_cleanup_pending_update()
		return

	var pending_info = json.data
	if not pending_info is Dictionary:
		_cleanup_pending_update()
		return

	var zip_path = pending_info.get("zip_path", "")
	var version = pending_info.get("version", "unknown")
	var install_dir = pending_info.get("install_dir", "")

	# Verify the zip still exists
	if not FileAccess.file_exists(zip_path):
		print("UpdateManager: Pending update zip not found, cleaning up")
		_cleanup_pending_update()
		return

	# Verify we're running from the expected location
	var current_exe_dir = OS.get_executable_path().get_base_dir()
	if install_dir != current_exe_dir:
		print("UpdateManager: Running from different location than expected, skipping update")
		print("  Expected: %s" % install_dir)
		print("  Current: %s" % current_exe_dir)
		_cleanup_pending_update()
		return

	print("UpdateManager: Applying pending update v%s..." % version)
	applying_pending_update.emit(version)

	# Apply the update based on platform
	var success = false
	match OS.get_name():
		"Windows":
			success = _extract_update_windows(zip_path, install_dir)
		"macOS":
			success = _extract_update_macos(zip_path)
		_:
			print("UpdateManager: Unsupported platform for auto-update")

	if success:
		print("UpdateManager: Update applied successfully!")
		_cleanup_pending_update()
		# Delete the zip file after successful extraction
		DirAccess.remove_absolute(zip_path)

		# On Windows, we need to restart immediately to run the new executable
		# (we're currently running from the .old file)
		if OS.get_name() == "Windows":
			print("UpdateManager: Restarting to run updated executable...")
			var new_exe_path = pending_info.get("exe_path", "")
			if not new_exe_path.is_empty() and FileAccess.file_exists(new_exe_path):
				OS.create_process(new_exe_path, [])
				get_tree().quit()
	else:
		print("UpdateManager: Failed to apply update")
		# Leave the marker so we can retry next time, but log the error
		push_error("UpdateManager: Update extraction failed - will retry on next startup")


## Extract update on Windows
## Strategy: Rename the running exe to .old (Windows allows this), then extract new exe
func _extract_update_windows(zip_path: String, install_dir: String) -> bool:
	var global_zip = ProjectSettings.globalize_path(zip_path)
	var global_install = install_dir
	var exe_path = OS.get_executable_path()
	var old_exe_path = exe_path + ".old"

	print("UpdateManager: Extracting %s to %s" % [global_zip, global_install])

	# Check if we have write permission to the install directory
	var test_file = install_dir + "/.update_permission_test"
	var test = FileAccess.open(test_file, FileAccess.WRITE)
	if test:
		test.close()
		DirAccess.remove_absolute(test_file)
	else:
		print("UpdateManager: No write permission to %s" % install_dir)
		print("UpdateManager: Opening downloads folder for manual update")
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		_cleanup_pending_update()
		return false

	# Step 1: Rename the currently running executable to .old
	# Windows allows renaming a locked file - the lock follows the file handle, not the path
	# This frees up the original path for the new executable
	print("UpdateManager: Renaming current executable to .old")
	var rename_result = DirAccess.rename_absolute(exe_path, old_exe_path)
	if rename_result != OK:
		print("UpdateManager: Failed to rename executable (error %d)" % rename_result)
		print("UpdateManager: Opening downloads folder for manual update")
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		_cleanup_pending_update()
		return false

	# Also rename console wrapper if it exists (created when export_console_wrapper is enabled)
	var exe_basename = exe_path.get_basename()
	var console_exe_path = exe_basename + ".console.exe"
	var old_console_path = console_exe_path + ".old"
	var had_console_wrapper = false
	if FileAccess.file_exists(console_exe_path):
		had_console_wrapper = true
		var console_rename = DirAccess.rename_absolute(console_exe_path, old_console_path)
		if console_rename != OK:
			print("UpdateManager: Warning - failed to rename console wrapper (error %d)" % console_rename)
			# Non-fatal, continue with update

	# Step 2: Extract the new executable from the zip
	# Use -LiteralPath to handle paths with special characters (brackets, etc.)
	# Escape single quotes in paths by doubling them
	var escaped_zip = global_zip.replace("'", "''")
	var escaped_install = global_install.replace("'", "''")
	var output = []
	var exit_code = OS.execute("powershell", [
		"-NoProfile",
		"-Command",
		"Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force" % [escaped_zip, escaped_install]
	], output, true)

	if exit_code != 0:
		print("UpdateManager: PowerShell extraction failed with code %d" % exit_code)
		for line in output:
			print("  %s" % line)
		# Try to restore the original executables
		DirAccess.rename_absolute(old_exe_path, exe_path)
		if had_console_wrapper:
			DirAccess.rename_absolute(old_console_path, console_exe_path)
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		return false

	# Step 3: Verify the new executable exists
	if not FileAccess.file_exists(exe_path):
		print("UpdateManager: New executable not found after extraction")
		# Try to restore the original executables
		DirAccess.rename_absolute(old_exe_path, exe_path)
		if had_console_wrapper:
			DirAccess.rename_absolute(old_console_path, console_exe_path)
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		return false

	print("UpdateManager: Extraction successful, restart required to use new version")

	# The .old file will be cleaned up on next startup by _cleanup_old_executables()
	# We need to restart now to run the new executable
	return true


## Extract update on macOS (called during startup when nothing is locked)
func _extract_update_macos(zip_path: String) -> bool:
	var global_zip = ProjectSettings.globalize_path(zip_path)
	var exe_path = OS.get_executable_path()

	# Find the .app bundle path
	var app_path = exe_path
	while not app_path.ends_with(".app") and app_path != "/":
		app_path = app_path.get_base_dir()

	if not app_path.ends_with(".app"):
		print("UpdateManager: Could not find .app bundle")
		return false

	# Detect App Translocation - macOS moves quarantined apps to a random read-only location
	# If the app path contains "/private/var/folders/" or "/AppTranslocation/", we can't update in place
	if "/private/var/folders/" in app_path or "/AppTranslocation/" in app_path:
		print("UpdateManager: App Translocation detected - app is running from a temporary location")
		print("UpdateManager: Please move the app to /Applications or another permanent location first")
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		_cleanup_pending_update()
		return false

	var install_dir = app_path.get_base_dir()
	print("UpdateManager: Extracting %s to %s" % [global_zip, install_dir])

	# Check if we have write permission to the install directory
	var test_file = install_dir + "/.update_permission_test"
	var test = FileAccess.open(test_file, FileAccess.WRITE)
	if test:
		test.close()
		DirAccess.remove_absolute(test_file)
	else:
		print("UpdateManager: No write permission to %s" % install_dir)
		print("UpdateManager: Opening downloads folder for manual update")
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		_cleanup_pending_update()
		return false

	var output = []
	var exit_code = OS.execute("unzip", ["-o", global_zip, "-d", install_dir], output, true)

	if exit_code != 0:
		print("UpdateManager: unzip failed with code %d" % exit_code)
		for line in output:
			print("  %s" % line)
		OS.shell_open(ProjectSettings.globalize_path(UPDATES_DIR))
		return false

	# Remove quarantine attribute from the extracted app so Gatekeeper doesn't complain
	var app_name = app_path.get_file()
	var new_app_path = install_dir + "/" + app_name
	OS.execute("xattr", ["-rd", "com.apple.quarantine", new_app_path], [], false)
	print("UpdateManager: Removed quarantine attribute from %s" % new_app_path)

	return true


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
## The actual extraction happens on next startup via _apply_pending_update()
func apply_update(_zip_path: String) -> void:
	var exe_path = OS.get_executable_path()

	print("UpdateManager: Restarting to apply update...")

	match OS.get_name():
		"Windows":
			_restart_windows(exe_path)
		"macOS":
			_restart_macos(exe_path)
		_:
			# Fallback: just quit and let user restart manually
			print("UpdateManager: Please restart the game to apply the update")
			get_tree().quit()


## Restart the game on Windows
func _restart_windows(exe_path: String) -> void:
	# Create a simple batch script that waits for us to exit, then relaunches
	var script_path = UPDATES_DIR + "restart.bat"
	var global_script = ProjectSettings.globalize_path(script_path)

	var script = """@echo off
timeout /t 1 /nobreak >nul
start "" "%s"
del "%%~f0"
""" % [exe_path]

	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script)
		file.close()

		# Launch the script and quit the game
		OS.create_process("cmd.exe", ["/c", global_script])
		get_tree().quit()
	else:
		push_error("UpdateManager: Failed to create restart script")
		get_tree().quit()


## Restart the game on macOS
func _restart_macos(exe_path: String) -> void:
	# Find the .app bundle path
	var app_path = exe_path
	while not app_path.ends_with(".app") and app_path != "/":
		app_path = app_path.get_base_dir()

	if not app_path.ends_with(".app"):
		# Can't find app bundle, just quit
		get_tree().quit()
		return

	var script_path = UPDATES_DIR + "restart.sh"
	var global_script = ProjectSettings.globalize_path(script_path)

	var script = """#!/bin/bash
sleep 1
open "%s"
rm "$0"
""" % [app_path]

	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script)
		file.close()

		# Make executable and run
		OS.execute("chmod", ["+x", global_script])
		OS.create_process("/bin/bash", [global_script])
		get_tree().quit()
	else:
		push_error("UpdateManager: Failed to create restart script")
		get_tree().quit()


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
