extends GutTest

## Every handler connected to AssetStreamer's asset_received / asset_failed /
## transfer_progress signals must accept all five arguments. Godot 4.7 refuses to call a
## handler with fewer parameters ("Method expected 4 argument(s), but called with 5")
## and the handler silently never runs; four-parameter handlers in
## MapDownloadCoordinator left every client map download stalled.

const STREAMER_SIGNAL_ARGS := 5

const LISTENERS := {
	"res://scenes/states/playing/map_download_coordinator.gd":
	["_on_map_received", "_on_map_failed", "_on_map_transfer_progress"],
	"res://scenes/ui/download_queue.gd":
	["_on_p2p_completed", "_on_p2p_failed", "_on_p2p_progress"],
	"res://autoloads/asset_resolver.gd":
	["_on_p2p_asset_received", "_on_p2p_asset_failed", "_on_p2p_transfer_progress"],
}


func _max_args(script: Script, method_name: String) -> int:
	for method in script.get_script_method_list():
		if method["name"] == method_name:
			return method["args"].size()
	return -1


func test_streamer_signals_carry_five_arguments() -> void:
	var streamer: Script = load("res://autoloads/asset_streamer.gd")
	for signal_info in streamer.get_script_signal_list():
		if signal_info["name"] in ["asset_received", "asset_failed", "transfer_progress"]:
			assert_eq(signal_info["args"].size(), STREAMER_SIGNAL_ARGS, signal_info["name"])


func test_every_listener_accepts_all_signal_arguments() -> void:
	for path in LISTENERS:
		var script: Script = load(path)
		for method_name in LISTENERS[path]:
			assert_gte(
				_max_args(script, method_name),
				STREAMER_SIGNAL_ARGS,
				(
					"%s.%s must accept %d arguments"
					% [path.get_file(), method_name, STREAMER_SIGNAL_ARGS]
				)
			)
