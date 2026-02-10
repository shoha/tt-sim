class_name UpdateInstaller

## Platform-specific update extraction and restart logic.
## Extracted from UpdateManager to isolate OS-level operations.


## Extract a downloaded update on Windows.
## Strategy: Rename the running exe to .old (Windows allows this), then extract new exe.
## Returns true on success.
static func extract_windows(
	zip_path: String, install_dir: String, log_fn: Callable = Callable()
) -> bool:
	var global_zip = ProjectSettings.globalize_path(zip_path)
	var global_install = install_dir
	var exe_path = OS.get_executable_path()
	var old_exe_path = exe_path + ".old"

	_log(log_fn, "Extracting %s to %s" % [global_zip, global_install])

	# Check write permission
	var test_file = install_dir + "/.update_permission_test"
	var test = FileAccess.open(test_file, FileAccess.WRITE)
	if test:
		test.close()
		DirAccess.remove_absolute(test_file)
	else:
		_log(log_fn, "No write permission to %s" % install_dir)
		OS.shell_open(ProjectSettings.globalize_path("user://updates/"))
		return false

	# Step 1: Rename current exe to .old
	_log(log_fn, "Renaming current executable to .old")
	var rename_result = DirAccess.rename_absolute(exe_path, old_exe_path)
	if rename_result != OK:
		_log(log_fn, "Failed to rename executable (error %d)" % rename_result)
		OS.shell_open(ProjectSettings.globalize_path("user://updates/"))
		return false

	# Also rename console wrapper if it exists
	var exe_basename = exe_path.get_basename()
	var console_exe_path = exe_basename + ".console.exe"
	var old_console_path = console_exe_path + ".old"
	var had_console_wrapper = false
	if FileAccess.file_exists(console_exe_path):
		had_console_wrapper = true
		var console_rename = DirAccess.rename_absolute(console_exe_path, old_console_path)
		if console_rename != OK:
			_log(
				log_fn,
				"Warning — failed to rename console wrapper (error %d)" % console_rename
			)

	# Step 2: Extract the zip
	var escaped_zip = global_zip.replace("'", "''")
	var escaped_install = global_install.replace("'", "''")
	var output = []
	var exit_code = OS.execute(
		"powershell",
		[
			"-NoProfile",
			"-Command",
			(
				"Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force"
				% [escaped_zip, escaped_install]
			)
		],
		output,
		true
	)

	if exit_code != 0:
		_log(log_fn, "PowerShell extraction failed with code %d" % exit_code)
		for line in output:
			_log(log_fn, "  %s" % line)
		DirAccess.rename_absolute(old_exe_path, exe_path)
		if had_console_wrapper:
			DirAccess.rename_absolute(old_console_path, console_exe_path)
		OS.shell_open(ProjectSettings.globalize_path("user://updates/"))
		return false

	# Step 3: Verify new exe exists
	if not FileAccess.file_exists(exe_path):
		_log(log_fn, "New executable not found after extraction")
		DirAccess.rename_absolute(old_exe_path, exe_path)
		if had_console_wrapper:
			DirAccess.rename_absolute(old_console_path, console_exe_path)
		OS.shell_open(ProjectSettings.globalize_path("user://updates/"))
		return false

	_log(log_fn, "Extraction successful")
	return true


## Extract a downloaded update on macOS.
## Returns true on success.
static func extract_macos(
	zip_path: String, log_fn: Callable = Callable()
) -> bool:
	var global_zip = ProjectSettings.globalize_path(zip_path)
	var exe_path = OS.get_executable_path()

	_log(log_fn, "macOS extraction starting...")
	_log(log_fn, "Zip path: %s" % global_zip)
	_log(log_fn, "Exe path: %s" % exe_path)

	# Find the .app bundle path
	var app_path = exe_path
	while not app_path.ends_with(".app") and app_path != "/":
		app_path = app_path.get_base_dir()

	_log(log_fn, "Found app path: %s" % app_path)

	if not app_path.ends_with(".app"):
		_log(log_fn, "ERROR: Could not find .app bundle in path")
		return false

	# Detect App Translocation
	if "/private/var/folders/" in app_path or "/AppTranslocation/" in app_path:
		_log(log_fn, "ERROR: App Translocation detected")
		return false

	var install_dir = app_path.get_base_dir()
	_log(log_fn, "Install directory: %s" % install_dir)

	# Check write permission
	_log(log_fn, "Testing write permission to: %s" % install_dir)
	var test_file = install_dir + "/.update_permission_test"
	var test = FileAccess.open(test_file, FileAccess.WRITE)
	if test:
		test.close()
		DirAccess.remove_absolute(test_file)
		_log(log_fn, "Write permission OK")
	else:
		_log(log_fn, "ERROR: No write permission to %s" % install_dir)
		OS.shell_open(ProjectSettings.globalize_path("user://updates/"))
		return false

	# Run unzip
	_log(log_fn, "Running: unzip -o '%s' -d '%s'" % [global_zip, install_dir])
	var output = []
	var exit_code = OS.execute("unzip", ["-o", global_zip, "-d", install_dir], output, true)

	_log(log_fn, "unzip exit code: %d" % exit_code)
	for line in output:
		_log(log_fn, "unzip output: %s" % str(line))

	if exit_code != 0:
		_log(log_fn, "ERROR: unzip failed with code %d" % exit_code)
		OS.shell_open(ProjectSettings.globalize_path("user://updates/"))
		return false

	# Verify the app was extracted
	var app_name = app_path.get_file()
	var new_app_path = install_dir + "/" + app_name
	_log(log_fn, "Checking for extracted app at: %s" % new_app_path)

	if not DirAccess.dir_exists_absolute(new_app_path):
		_log(log_fn, "ERROR: Extracted app not found at expected location")
		OS.shell_open(ProjectSettings.globalize_path("user://updates/"))
		return false

	# Remove quarantine attribute
	_log(log_fn, "Removing quarantine attribute from: %s" % new_app_path)
	var xattr_output = []
	OS.execute("xattr", ["-rd", "com.apple.quarantine", new_app_path], xattr_output, true)
	_log(log_fn, "Quarantine removal complete")

	_log(log_fn, "macOS extraction completed successfully")
	return true


## Restart the game on Windows using a batch script.
static func restart_windows(exe_path: String, tree: SceneTree) -> void:
	var script_path = "user://updates/restart.bat"
	var global_script = ProjectSettings.globalize_path(script_path)

	var script = (
		"""@echo off
timeout /t 1 /nobreak >nul
start "" "%s"
del "%%~f0"
"""
		% [exe_path]
	)

	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script)
		file.close()
		OS.create_process("cmd.exe", ["/c", global_script])
		tree.quit()
	else:
		push_error("UpdateInstaller: Failed to create restart script")
		tree.quit()


## Restart the game on macOS using a shell script.
static func restart_macos(exe_path: String, tree: SceneTree) -> void:
	# Find the .app bundle path
	var app_path = exe_path
	while not app_path.ends_with(".app") and app_path != "/":
		app_path = app_path.get_base_dir()

	if not app_path.ends_with(".app"):
		tree.quit()
		return

	var script_path = "user://updates/restart.sh"
	var global_script = ProjectSettings.globalize_path(script_path)

	var script = (
		"""#!/bin/bash
sleep 1
open "%s"
rm "$0"
"""
		% [app_path]
	)

	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script)
		file.close()
		OS.execute("chmod", ["+x", global_script])
		OS.create_process("/bin/bash", [global_script])
		tree.quit()
	else:
		push_error("UpdateInstaller: Failed to create restart script")
		tree.quit()


## Extract app name from a macOS path.
## e.g. "/Applications/TTSim.app/Contents/MacOS" -> "TTSim"
static func extract_app_name_from_path(path: String) -> String:
	var parts = path.split("/")
	for part in parts:
		if part.ends_with(".app"):
			return part.get_basename()
	return ""


## Clean up .old executables left over from previous updates (Windows only).
static func cleanup_old_executables() -> void:
	if OS.get_name() != "Windows":
		return

	var exe_path = OS.get_executable_path()
	var exe_dir = exe_path.get_base_dir()
	var exe_name = exe_path.get_file()

	var old_exe_path = exe_dir + "/" + exe_name + ".old"
	if FileAccess.file_exists(old_exe_path):
		var err = DirAccess.remove_absolute(old_exe_path)
		if err == OK:
			print("UpdateInstaller: Cleaned up old executable: %s" % old_exe_path)
		else:
			print("UpdateInstaller: Failed to clean up old executable (error %d)" % err)

	var console_exe_name = exe_name.get_basename() + ".console.exe"
	var old_console_path = exe_dir + "/" + console_exe_name + ".old"
	if FileAccess.file_exists(old_console_path):
		var err = DirAccess.remove_absolute(old_console_path)
		if err == OK:
			print("UpdateInstaller: Cleaned up old console wrapper: %s" % old_console_path)
		else:
			print("UpdateInstaller: Failed to clean up old console wrapper (error %d)" % err)


## Get human-readable error message for HTTP result
static func get_http_error(result: int) -> String:
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


static func _log(log_fn: Callable, message: String) -> void:
	if log_fn.is_valid():
		log_fn.call(message)
	else:
		print("UpdateInstaller: " + message)
