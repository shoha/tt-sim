extends GutTest

## DragState: the idle / pending / active machine of one pointer drag.

var _state: DragState
var _subject: Node


func before_each() -> void:
	_state = DragState.new()
	_subject = autofree(Node.new())


func test_starts_idle() -> void:
	assert_eq(_state.phase, DragState.Phase.IDLE)
	assert_false(_state.is_pending())
	assert_false(_state.is_active())
	assert_null(_state.subject)


func test_press_arms_a_pending_drag() -> void:
	assert_true(_state.press(_subject, Vector2(10, 10)))
	assert_true(_state.is_pending())
	assert_false(_state.is_active(), "armed, not yet dragging")
	assert_eq(_state.subject, _subject)


func test_press_with_no_subject_is_refused() -> void:
	assert_false(_state.press(null, Vector2.ZERO))
	assert_eq(_state.phase, DragState.Phase.IDLE)


func test_a_second_press_cannot_steal_a_pending_drag() -> void:
	var other: Node = autofree(Node.new())
	_state.press(_subject, Vector2.ZERO)
	assert_false(_state.press(other, Vector2(50, 50)))
	assert_eq(_state.subject, _subject)


func test_a_press_cannot_steal_an_active_drag() -> void:
	var other: Node = autofree(Node.new())
	_state.press(_subject, Vector2.ZERO)
	_state.motion(Vector2(20, 0))
	assert_false(_state.press(other, Vector2(50, 50)))
	assert_eq(_state.subject, _subject)


func test_motion_below_the_threshold_stays_pending() -> void:
	_state.press(_subject, Vector2(100, 100))
	assert_false(_state.motion(Vector2(104, 100)))
	assert_true(_state.is_pending())


func test_motion_at_the_threshold_activates_once() -> void:
	_state.press(_subject, Vector2(100, 100))
	assert_true(_state.motion(Vector2(105, 100)), "exactly the threshold begins")
	assert_true(_state.is_active())
	assert_false(_state.motion(Vector2(300, 100)), "later motion does not re-activate")


func test_a_single_large_jump_activates() -> void:
	# A stylus or remote cursor: press, one big move, release.
	_state.press(_subject, Vector2(0, 0))
	assert_true(_state.motion(Vector2(900, 400)))


func test_threshold_is_configurable() -> void:
	_state.threshold = 20.0
	_state.press(_subject, Vector2.ZERO)
	assert_false(_state.motion(Vector2(19, 0)))
	assert_true(_state.motion(Vector2(20, 0)))


func test_motion_when_idle_does_nothing() -> void:
	assert_false(_state.motion(Vector2(500, 500)))
	assert_eq(_state.phase, DragState.Phase.IDLE)


func test_abort_pending_returns_to_idle() -> void:
	_state.press(_subject, Vector2.ZERO)
	assert_true(_state.abort_pending())
	assert_eq(_state.phase, DragState.Phase.IDLE)
	assert_null(_state.subject)
	assert_false(_state.motion(Vector2(500, 0)), "an aborted press cannot become a drag")


func test_abort_pending_does_not_end_an_active_drag() -> void:
	_state.press(_subject, Vector2.ZERO)
	_state.motion(Vector2(20, 0))
	assert_false(_state.abort_pending())
	assert_true(_state.is_active())


func test_finish_returns_the_subject_and_goes_idle() -> void:
	_state.press(_subject, Vector2.ZERO)
	_state.motion(Vector2(20, 0))
	assert_eq(_state.finish(), _subject)
	assert_eq(_state.phase, DragState.Phase.IDLE)
	assert_null(_state.subject)


func test_finish_when_not_active_returns_null_and_keeps_a_pending_press() -> void:
	_state.press(_subject, Vector2.ZERO)
	assert_null(_state.finish())
	assert_true(_state.is_pending())


func test_the_anchor_does_not_leak_into_the_next_drag() -> void:
	_state.press(_subject, Vector2(0, 0))
	_state.motion(Vector2(10, 0))
	_state.finish()
	# Pressed again where the cursor now sits, 2 px of motion is far from the old anchor (12 px)
	# but near the new one.
	_state.press(_subject, Vector2(10, 0))
	assert_false(_state.motion(Vector2(12, 0)))
	assert_true(_state.is_pending())


func test_begin_goes_straight_to_active() -> void:
	assert_true(_state.begin(_subject))
	assert_true(_state.is_active())
	assert_eq(_state.subject, _subject)


func test_begin_is_refused_unless_idle() -> void:
	_state.press(_subject, Vector2.ZERO)
	assert_false(_state.begin(_subject))
	assert_true(_state.is_pending())
