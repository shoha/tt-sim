extends Node

## Starts the validation bridge (addons/validation_bridge/) for agent-driven runs.
##
## The bridge is a TCP command server for AI agents (screenshots, input injection,
## expression eval). It belongs to runs from source only, so every export preset
## excludes its folder and this loader is the one piece of it that ships. Registering
## the bridge script itself as the autoload would make an export fail to instantiate
## it at startup; the loader instead checks for the script and stays an inert node
## when it is absent.
##
## When the game is launched with `-- --validation-bridge` and the bridge script
## exists, the loader adds the bridge as its child, which then listens on
## 127.0.0.1:7777 exactly as before.

const BRIDGE_PATH: String = "res://addons/validation_bridge/validation_bridge.gd"
const BRIDGE_FLAG: String = "--validation-bridge"


func _ready() -> void:
	if not BRIDGE_FLAG in OS.get_cmdline_user_args():
		return
	if not ResourceLoader.exists(BRIDGE_PATH):
		push_warning("ValidationBridge: %s given, but this build has no bridge" % BRIDGE_FLAG)
		return
	var bridge: Node = load(BRIDGE_PATH).new()
	bridge.name = "Bridge"
	add_child(bridge)
