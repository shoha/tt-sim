extends GutTest

## Regression test for the late-joiner level-data snapshot patch.
##
## NetworkManager._current_level_dict is the level snapshot replayed via
## broadcast_level_data() to clients that connect after a level is already
## loaded. Live visual-settings edits (broadcast_visual_settings) also patch
## this snapshot via _patch_current_level_dict() -- otherwise a client joining
## after a live edit (but before the next full level load) sees stale values
## until the next full level broadcast. This mirrors the existing precedent in
## test_network_manager_security.gd
## (test_late_joiner_snapshot_reflects_live_visual_settings_edit) but targets
## sun_overrides specifically (missing until this fix), plus a generalized
## check across every key GameplayMenuController actually broadcasts.
##
## NetworkManager is a live autoload, not a doubled instance (see
## test_network_manager_security.gd's header comment for why -- GUT's
## stub()/double() only works on instances you construct yourself), so these
## tests drive it directly and restore its state in after_each().


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._current_level_dict.clear()


func test_late_joiner_snapshot_reflects_live_sun_override_edit() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._current_level_dict = {
		"level_folder": "sectest_level", "sun_overrides": {"mode": "auto", "time_of_day": 14.0}
	}

	NetworkManager._patch_current_level_dict({"sun_overrides": {"mode": "on", "time_of_day": 8.0}})

	assert_eq(
		NetworkManager._current_level_dict["sun_overrides"],
		{"mode": "on", "time_of_day": 8.0},
		"A live Sun edit must update the late-joiner snapshot, not just the live broadcast"
	)


## GameplayMenuController broadcasts these exact keys (see its
## _on_edit_*_changed handlers and _on_edit_save_requested) -- every one of
## them needs a corresponding branch in _patch_current_level_dict(), or a late
## joiner sees a stale value for whichever key was forgotten. This
## generalizes the regression beyond sun_overrides alone: an identical gap
## for any of these keys would have the same symptom.
func test_patch_current_level_dict_mirrors_every_broadcast_visual_settings_key() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._current_level_dict = {"level_folder": "sectest_level"}

	var net_settings := {
		"light_intensity": 0.4,
		"environment_preset": "night",
		"environment_overrides": {"fog_enabled": true},
		"lofi_overrides": {"pixelation": 2.0},
		"weather_overrides": {"rain_intensity": 0.5},
		"foliage_overrides": {"grass_sway_speed": 9.0},
		"sun_overrides": {"mode": "off"},
	}
	NetworkManager._patch_current_level_dict(net_settings)

	# "light_intensity" is special-cased to the LevelData field name it
	# actually corresponds to; every other key is a 1:1 mirror.
	assert_eq(NetworkManager._current_level_dict["light_intensity_scale"], 0.4)
	assert_eq(NetworkManager._current_level_dict["environment_preset"], "night")
	assert_eq(NetworkManager._current_level_dict["environment_overrides"], {"fog_enabled": true})
	assert_eq(NetworkManager._current_level_dict["lofi_overrides"], {"pixelation": 2.0})
	assert_eq(NetworkManager._current_level_dict["weather_overrides"], {"rain_intensity": 0.5})
	assert_eq(NetworkManager._current_level_dict["foliage_overrides"], {"grass_sway_speed": 9.0})
	assert_eq(NetworkManager._current_level_dict["sun_overrides"], {"mode": "off"})
