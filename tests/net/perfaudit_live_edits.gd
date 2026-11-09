extends "res://tests/net/enet_live_edits.gd"

## enet_live_edits with every peer's ENet peer counted (tests/net/counting_peer.gd): the
## perfaudit net harness's view of what each live map edit costs on the wire. The scenario runs
## as enet_live_edits does; the counting peer wraps the ENet peer on the first frame it
## appears, before any client has connected, and a counting window closes at every phase
## change, labelled with the phase it covered and the op index (NETW and NETM lines in each
## role's log), so an op's bytes sit in the host's brushing / op windows of its index.
##
## Run (headless, own worktree user folder, its own port):
##   godot --headless --path <worktree> res://tests/net/net_launcher.tscn --
##     --data-root=net_launcher --scenario=perfaudit_live_edits --peers=3 --timeout-s=300
##     --port=28591

const CountingPeer := preload("res://tests/net/counting_peer.gd")

var _meter: CountingPeer = null
var _window := "start"


func _process(delta: float) -> void:
	var peer := multiplayer.multiplayer_peer
	if _meter == null and peer is ENetMultiplayerPeer:
		_meter = CountingPeer.new(peer, get_tree().root)
		multiplayer.multiplayer_peer = _meter
		_log("counting peer installed")
	super._process(delta)


func _set_phase(phase: String) -> void:
	if _meter != null:
		for line in CountingPeer.window_lines(_role, _meter.cut(_window)):
			_log(line)
	_window = "%s#%d" % [phase, _op]
	super._set_phase(phase)
