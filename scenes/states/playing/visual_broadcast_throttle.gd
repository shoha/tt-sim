class_name VisualBroadcastThrottle
extends Node

## Coalesces live visual-settings broadcasts from the Visuals drawer.
##
## Every slider tick used to send one reliable RPC (and make every client re-apply
## the whole environment). Callers queue() partial settings dictionaries; the
## throttle merges them and sends once per interval through `send`. Save and Cancel
## drop() whatever is pending before sending their own full snapshot, so a stale
## partial can never land after the authoritative one.

const DEFAULT_INTERVAL: float = 0.1  # Seconds between sends while edits keep coming

var interval: float = DEFAULT_INTERVAL
## Called with the merged settings Dictionary. Typically NetworkManager.broadcast_visual_settings.
var send: Callable

var _pending: Dictionary = {}
var _time_until_send: float = 0.0


func _ready() -> void:
	set_process(false)


## Merge settings into the pending batch and start the countdown if idle.
func queue(settings: Dictionary) -> void:
	if _pending.is_empty():
		_time_until_send = interval
		set_process(true)
	_pending.merge(settings, true)


## Send whatever is pending right now.
func flush() -> void:
	if _pending.is_empty():
		return
	var batch := _pending
	_pending = {}
	set_process(false)
	if send.is_valid():
		send.call(batch)


## Discard the pending batch without sending.
func drop() -> void:
	_pending = {}
	set_process(false)


func has_pending() -> bool:
	return not _pending.is_empty()


func _process(delta: float) -> void:
	_time_until_send -= delta
	if _time_until_send <= 0.0:
		flush()
