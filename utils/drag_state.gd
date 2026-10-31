class_name DragState
extends RefCounted

## The state machine of one pointer drag, with no scene and no input events: DragController feeds
## it what happened and acts on what it answers.
##
## IDLE -> press() -> PENDING -> motion() past the threshold -> ACTIVE -> finish() -> IDLE
##
## A press only arms the drag (PENDING). Nothing moves until the pointer has travelled the
## threshold from where the button went down, so a plain click never nudges a token. The anchor
## is the press position itself, not the cursor's last cached position, which only follows real
## OS motion and so is stale for injected events. A pending press is dropped by a release
## (a click) or by abort_pending() (right click); an active drag ends by finish(), and the
## caller decides whether that was a drop or a cancel.

enum Phase { IDLE, PENDING, ACTIVE }

## Pixels of travel from the press before a drag begins.
var threshold: float = 5.0

var phase: Phase = Phase.IDLE
## The draggable the press landed on while PENDING, and the one being dragged while ACTIVE.
var subject: Object = null

var _anchor: Vector2 = Vector2.ZERO


## Arm a drag on `p_subject` from a press at `position`. Ignored (false) unless IDLE: a second
## press cannot steal an armed or running drag.
func press(p_subject: Object, position: Vector2) -> bool:
	if phase != Phase.IDLE or p_subject == null:
		return false
	phase = Phase.PENDING
	subject = p_subject
	_anchor = position
	return true


## Feed a pointer position. Returns true exactly once, when a PENDING press crosses the threshold
## and the drag becomes ACTIVE. A single past-threshold jump is enough (a stylus or remote
## cursor delivers press, one large move, release).
func motion(position: Vector2) -> bool:
	if phase != Phase.PENDING:
		return false
	if not DragMath.threshold_reached(_anchor, position, threshold):
		return false
	phase = Phase.ACTIVE
	return true


## Begin a drag at once on `p_subject`, with no press and no threshold (a render probe, or a
## token picked up by code). Returns false unless IDLE.
func begin(p_subject: Object) -> bool:
	if phase != Phase.IDLE or p_subject == null:
		return false
	phase = Phase.ACTIVE
	subject = p_subject
	return true


## Drop a PENDING press without it becoming a drag (button released before the threshold, or a
## right click). Returns whether there was one.
func abort_pending() -> bool:
	if phase != Phase.PENDING:
		return false
	_reset()
	return true


## End an ACTIVE drag and return its subject (null when none was active).
func finish() -> Object:
	if phase != Phase.ACTIVE:
		return null
	var finished := subject
	_reset()
	return finished


func is_pending() -> bool:
	return phase == Phase.PENDING


func is_active() -> bool:
	return phase == Phase.ACTIVE


func _reset() -> void:
	phase = Phase.IDLE
	subject = null
