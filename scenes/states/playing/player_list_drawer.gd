extends DrawerContainer
class_name PlayerListDrawer

## Slide-out drawer showing connected players and their roles.
##
## Automatically updates when players join or leave. Only visible during
## networked games — starts completely hidden and slides the tab into view
## when a networked game begins.

# -- Internals --------------------------------------------------------------

var _header_label: Label
var _player_list_vbox: VBoxContainer


func _on_ready() -> void:
	drawer_width = 200.0

	_build_player_list_ui()
	_update_player_list()

	# Connect to network signals
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)


func _exit_tree() -> void:
	if NetworkManager.player_joined.is_connected(_on_player_joined):
		NetworkManager.player_joined.disconnect(_on_player_joined)
	if NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.disconnect(_on_player_left)
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)


# -- UI Construction ---------------------------------------------------------


func _build_player_list_ui() -> void:
	# Header
	_header_label = Label.new()
	_header_label.text = "Players"
	_header_label.theme_type_variation = &"PanelHeader"
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.add_child(_header_label)

	# Separator under header
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.add_child(sep)

	# Scrollable list area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.add_child(scroll)

	_player_list_vbox = VBoxContainer.new()
	_player_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_list_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_player_list_vbox)


# -- Player List Updates -----------------------------------------------------


func _update_player_list() -> void:
	# Clear existing rows
	for child in _player_list_vbox.get_children():
		child.queue_free()

	var players := NetworkManager.get_players()
	var local_id: int = 0
	if multiplayer.has_multiplayer_peer():
		local_id = multiplayer.get_unique_id()
	var count := players.size()

	# Update header with count
	_header_label.text = "Players (%d)" % count

	# Update tab text — player count only, fits in the narrow tab
	tab_text = str(count)

	if players.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No players connected"
		empty_label.theme_type_variation = &"Caption"
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_player_list_vbox.add_child(empty_label)
		return

	# Sort: host (peer 1) first, then alphabetically by name
	var sorted_ids: Array = players.keys()
	sorted_ids.sort_custom(
		func(a: int, b: int) -> bool:
			if a == 1:
				return true
			if b == 1:
				return false
			var name_a: String = players[a].get("name", "")
			var name_b: String = players[b].get("name", "")
			return name_a.naturalcasecmp_to(name_b) < 0
	)

	for peer_id in sorted_ids:
		var info: Dictionary = players[peer_id]
		var row := _create_player_row(peer_id, info, peer_id == local_id)
		_player_list_vbox.add_child(row)


func _create_player_row(peer_id: int, info: Dictionary, is_local: bool) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)

	# Role badge
	var role: NetworkManager.PlayerRole = info.get("role", NetworkManager.PlayerRole.PLAYER)
	var badge := Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size.x = 28

	if role == NetworkManager.PlayerRole.GM:
		badge.text = "GM"
		badge.theme_type_variation = &"SectionHeader"
	else:
		badge.text = ""

	row.add_child(badge)

	# Player name
	var player_name: String = info.get("name", "Player %d" % peer_id)
	var name_label := Label.new()
	name_label.text = player_name
	name_label.theme_type_variation = &"Body"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	# "(You)" indicator for the local player
	if is_local:
		var you_label := Label.new()
		you_label.text = "(You)"
		you_label.theme_type_variation = &"Caption"
		you_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(you_label)

	return row


# -- Signal Handlers ---------------------------------------------------------


func _on_player_joined(_peer_id: int, _player_info: Dictionary) -> void:
	_update_player_list()
	# Brief highlight flash on the tab to draw attention
	_flash_tab()


func _on_player_left(_peer_id: int) -> void:
	_update_player_list()
	_flash_tab()


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, _new_state: NetworkManager.ConnectionState
) -> void:
	_update_player_list()
	_update_visibility()


## Show/hide the drawer based on network state.
## Reveals the tab when networked, conceals when offline.
func _update_visibility() -> void:
	if NetworkManager.is_networked():
		visible = true
		reveal()
	else:
		conceal()


# -- Visual Feedback ---------------------------------------------------------


## Quick colour flash on the tab button to signal a roster change.
func _flash_tab() -> void:
	if not is_instance_valid(_tab_button):
		return

	var original_self_modulate := _tab_button.self_modulate
	var flash_color := Color(1.4, 1.4, 1.4, 1.0)  # Bright highlight

	var tween := create_tween()
	tween.tween_property(_tab_button, "self_modulate", flash_color, 0.1)
	tween.tween_property(_tab_button, "self_modulate", original_self_modulate, 0.3)
