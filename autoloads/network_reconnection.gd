class_name NetworkReconnection

## Encapsulates the exponential-backoff reconnection state machine
## extracted from NetworkManager.
##
## The owner (NetworkManager) calls `start()` when the server disconnects
## and `stop()` after a successful reconnection or when giving up.
## On each retry, the handler calls `reconnect_callback` which should
## attempt to rejoin the game.

const MAX_ATTEMPTS := 5
const BASE_DELAY := 1.0
const MAX_DELAY := 16.0

## Emitted so the UI can show "Reconnecting 2/5…" etc.
signal reconnecting(attempt: int, max_attempts: int)

## Emitted when all attempts are exhausted.
signal reconnection_failed(reason: String)

var _attempts: int = 0
var _stored_room_code: String = ""
var _timer: Timer
var _reconnect_callback: Callable  # func(room_code: String) -> void
var _set_state_callback: Callable  # func(state: int) -> void
var _state_reconnecting: int       # ConnectionState.RECONNECTING value


func _init(
	owner: Node,
	reconnect_callback: Callable,
	set_state_callback: Callable,
	state_reconnecting: int,
) -> void:
	_reconnect_callback = reconnect_callback
	_set_state_callback = set_state_callback
	_state_reconnecting = state_reconnecting

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	owner.add_child(_timer)


## Whether we're in the middle of a reconnection cycle.
## Can't rely on connection_state alone because join_game() temporarily
## changes it to CONNECTING during each attempt.
func is_reconnecting() -> bool:
	return _attempts > 0


## Begin (or continue) the reconnection cycle.
## [param room_code] is stored on the first call and reused for subsequent
## attempts.
func start(room_code: String = "") -> void:
	# Store room code on first call
	if _stored_room_code.is_empty() and not room_code.is_empty():
		_stored_room_code = room_code

	if _stored_room_code.is_empty():
		reconnection_failed.emit("Cannot reconnect: no room code available")
		return

	_attempts += 1

	if _attempts > MAX_ATTEMPTS:
		var reason = "Reconnection failed after %d attempts" % MAX_ATTEMPTS
		stop()
		reconnection_failed.emit(reason)
		return

	_set_state_callback.call(_state_reconnecting)
	reconnecting.emit(_attempts, MAX_ATTEMPTS)

	var delay = min(BASE_DELAY * pow(2, _attempts - 1), MAX_DELAY)
	_timer.wait_time = delay
	_timer.start()


## Called when a reconnection attempt fails at the network layer.
## Decides whether to retry or give up.
func on_attempt_failed() -> void:
	if _attempts >= MAX_ATTEMPTS:
		var reason = "Reconnection failed after %d attempts" % MAX_ATTEMPTS
		stop()
		reconnection_failed.emit(reason)
	else:
		start()


## Stop the reconnection process and reset state.
func stop() -> void:
	_timer.stop()
	_attempts = 0
	_stored_room_code = ""


func _on_timeout() -> void:
	if not is_reconnecting():
		return

	_reconnect_callback.call(_stored_room_code)
