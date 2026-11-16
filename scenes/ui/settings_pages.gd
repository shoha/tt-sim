class_name SettingsPages
extends RefCounted

## The two Settings pages that hold more than controls, split out of settings_menu.gd to keep it
## under the lint budget: the Controls shortcut list (profile-aware key names) and the Updates
## tab's "Check now" flow.

const UPDATE_DIALOG := preload("res://scenes/ui/update_dialog.tscn")


## Fills `list` with one row per shortcut, the key name (by the active input profile) then what it
## does.
static func populate_shortcuts(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
	var controls: Array[Array] = [
		["Left-drag", "Move a token"],
		["Right-click", "Open a token's menu"],
		[InputProfile.label(&"zoom"), "Zoom the camera"],
		[InputProfile.label(&"pan"), "Pan the camera"],
		[InputProfile.label(&"rotate"), "Rotate a token"],
		[InputProfile.label(&"scale"), "Scale a token"],
		[InputProfile.label(&"reset_transform"), "Reset a token's rotation and scale"],
		[InputProfile.label(&"reset_camera"), "Reset the camera"],
		[InputProfile.label(&"wasd"), "Move the camera"],
		[InputProfile.label(&"measure"), "Measure distances"],
		[InputProfile.label(&"grid"), "Show or hide the grid"],
		[InputProfile.label(&"pause"), "Pause, or close a menu"],
	]
	for control in controls:
		var hbox := HBoxContainer.new()
		var key_label := Label.new()
		key_label.text = control[0]
		key_label.theme_type_variation = "Body"
		hbox.add_child(key_label)
		var action_label := Label.new()
		action_label.text = control[1]
		action_label.theme_type_variation = "Caption"
		hbox.add_child(action_label)
		PropertyRow.fit_sheet_row(hbox)
		list.add_child(hbox)


## "Check now": asks UpdateManager, shows the answer on the status label and, for a new version,
## opens the update dialog.
static func check_for_updates(menu: SettingsMenu) -> void:
	menu.check_updates_button.disabled = true
	menu.update_status_label.text = "Checking for updates..."
	var on_complete := func(has_update: bool) -> void:
		menu.check_updates_button.disabled = false
		if has_update:
			var version = UpdateManager.latest_release.get("version", "?")
			menu.update_status_label.text = "Update available: v" + version
			var dialog = UPDATE_DIALOG.instantiate()
			menu.get_tree().root.add_child(dialog)
			dialog.setup(UpdateManager.latest_release)
		else:
			menu.update_status_label.text = "You're up to date!"
	var on_failed := func(error: String) -> void:
		menu.check_updates_button.disabled = false
		menu.update_status_label.text = "Check failed: " + error
	UpdateManager.update_check_complete.connect(on_complete, CONNECT_ONE_SHOT)
	UpdateManager.update_check_failed.connect(on_failed, CONNECT_ONE_SHOT)
	UpdateManager.check_for_updates()
