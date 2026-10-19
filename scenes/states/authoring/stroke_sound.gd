class_name StrokeSound
extends RefCounted

## The brush's sounds: a soft answer to every edit, by the tool's family. BrushTool owns
## one and tells it when a stroke begins, how far each frame of it moved and when it ends;
## this decides what is heard. Every sound is a recorded shot in tools/sfx_spec.py (SHOTS)
## on the SFX bus, its takes, level and jitter set there; this class only says when.
##
## Families. A tool's id names its family (FAMILIES): plant for Biome and Thin / Clear (a
## leafy rustle), prop for Place and Bridge (a soft wood knock), water, paint (a brush swish
## on the ground) and sculpt (a low earthy shift). Fire has none of its own, its roar
## (FireSound) answers it; a tool without a family is silent.
##
## Moments. The press plays `<family>_start`. While the stroke is dragged a quiet
## `<family>_tick` plays per spacing_m() of ground travelled (a share of the brush radius,
## never under MIN_SPACING_M): ticks_for() turns the distance carried into ticks, at most
## one plays a frame and the rest of a fast frame's distance is dropped (carry()), and the
## tick's own cooldown caps the rate, so a quick drag never runs them into a machine-gun.
## Holding still is silent. The release plays `<family>_settle`, unless the stroke was a
## tap (settles(): shorter than SETTLE_MIN_S and never a spacing from its start), which is
## heard once, as its start. A cancelled stroke ends without a sound. Undo and redo play
## `undo` and `redo` (play_history, from AuthoringController).

## Tool id -> sound family (the prefix of its shots' names).
const FAMILIES := {
	&"biome": &"plant",
	&"thin_clear": &"plant",
	&"place": &"prop",
	&"bridge": &"prop",
	&"water": &"water",
	&"paint": &"paint",
	&"sculpt": &"sculpt",
}
## A tick per this share of the brush radius travelled...
const SPACING_PER_RADIUS := 0.75
## ...but never closer than this (metres), so a small brush does not chatter.
const MIN_SPACING_M := 2.0
## A stroke held at least this long (seconds) settles even if it never moved.
const SETTLE_MIN_S := 0.3

## Plays a sound by name: AudioManager.play, or a test's recorder.
var player: Callable = _play_on_manager

var _family: StringName = &""
var _spacing: float = MIN_SPACING_M
var _carried: float = 0.0
var _travelled: float = 0.0
var _held_s: float = 0.0


## The family of the tool with id `tool_id`, or &"" for a silent tool.
static func family_of(tool_id: StringName) -> StringName:
	return FAMILIES.get(tool_id, &"")


## Metres of ground between two ticks for a brush of world radius `radius`.
static func spacing_m(radius: float) -> float:
	return maxf(MIN_SPACING_M, radius * SPACING_PER_RADIUS)


## How many whole tick spacings `travelled_m` covers (0 under one spacing). Pure: the
## throttle's distance-to-ticks rule; moved() plays at most one of them a frame.
static func ticks_for(travelled_m: float, spacing: float) -> int:
	if spacing <= 0.0 or travelled_m <= 0.0:
		return 0
	return int(floor(travelled_m / spacing))


## The distance carried toward the next tick after `travelled_m`: what is left past the
## last whole spacing.
static func carry(travelled_m: float, spacing: float) -> float:
	if spacing <= 0.0:
		return 0.0
	return travelled_m - ticks_for(travelled_m, spacing) * spacing


## Whether a stroke held `held_s` seconds that travelled `travelled_m` ends in a settle: a
## tap (quick and in place) does not, so a click is heard once.
static func settles(held_s: float, travelled_m: float, spacing: float) -> bool:
	return held_s >= SETTLE_MIN_S or travelled_m >= spacing


## Plays undo's tick (`redo` false) or redo's.
static func play_history(redo: bool) -> void:
	AudioManager.play(&"redo" if redo else &"undo")


## True while a stroke of a family with sounds is in progress.
func is_active() -> bool:
	return _family != &""


## A stroke of the tool `tool_id` began at a brush of world radius `radius`: its start.
func begin(tool_id: StringName, radius: float) -> void:
	_family = family_of(tool_id)
	_spacing = spacing_m(radius)
	_carried = 0.0
	_travelled = 0.0
	_held_s = 0.0
	_emit(&"start")


## A frame of the stroke: the brush moved `step_m` metres over `seconds`. Plays a tick when
## the distance carried reaches a spacing.
func moved(step_m: float, seconds: float) -> void:
	if not is_active():
		return
	_held_s += seconds
	_travelled += step_m
	_carried += step_m
	if ticks_for(_carried, _spacing) > 0:
		_emit(&"tick")
		_carried = carry(_carried, _spacing)


## The stroke was released: its settle, unless it was a tap.
func end() -> void:
	if is_active() and settles(_held_s, _travelled, _spacing):
		_emit(&"settle")
	_family = &""


## The stroke was cancelled: it ends without a sound.
func cancel() -> void:
	_family = &""


func _emit(moment: StringName) -> void:
	if is_active():
		player.call(StringName("%s_%s" % [_family, moment]))


func _play_on_manager(sound: StringName) -> void:
	AudioManager.play(sound)
