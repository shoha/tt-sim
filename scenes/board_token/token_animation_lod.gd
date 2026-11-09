class_name TokenAnimationLod
extends Node

## Advances pack tokens' animations at a level of detail (perf audit F-tokens-3, 2026-11-09).
##
## Every animated pack token runs an AnimationTree (BoardTokenAnimationTree) whose idle loop is
## decoration, yet each one blended and posed its skeleton every frame: 15-20 us of main-thread
## CPU per token per frame, 8.3 ms at 500 tokens, plus the renderer's skin update. One manager
## per viewport (for_viewport) now owns those mixers, switched to the manual callback mode, and
## advances each one by the time that has passed since its last step:
## - every frame while the token is highlighted (selected or hovered), being dragged, or within
##   FULL_HOLD_S of a state change (touch: damage, down, back up), so what a player handles or a
##   reaction they trigger moves at the full frame rate;
## - at IDLE_HZ otherwise, staggered (each mixer starts at its own phase, so a crowd does not all
##   step on one frame) while the token's sphere of CULL_RADIUS_M is inside the camera frustum;
## - not at all off screen: the pose holds, and resumes from there when the token comes back.
## Time is conserved: a step carries the whole interval since the last, so a 30 Hz idle runs at
## its real speed, only sampled less often. The rates are constants (the board left them to the
## recommendation: 30 Hz on screen, paused off screen). The model's own AnimationPlayer (the
## tree's animation source) and the scene's Dummy player play nothing, so they go manual too.
##
## `enabled` off hands every mixer back its own per-frame processing (the perf harness's A/B,
## perfaudit_tokens.gd `anim_full`, and a fallback).

const NODE_NAME := "TokenAnimationLod"
const META := &"token_animation_lod"
## Idle on-screen tokens step at this rate.
const IDLE_HZ := 30.0
## Full rate for this long after touch() (a reaction clip and its blend back to idle).
const FULL_HOLD_S := 2.0
## The sphere round a token's origin tested against the frustum (a large beast's half-size).
const CULL_RADIUS_M := 1.5

static var enabled := true

## Per entry, in parallel: the tree, its token (may be null), the time since its last step, and
## the time (msec) until which it runs at full rate.
var _mixers: Array[AnimationMixer] = []
var _sources: Array = []  # [AnimationMixer] the players the tree reads, made manual with it
var _tokens: Array[BoardToken] = []
var _since := PackedFloat32Array()
var _full_until := PackedInt64Array()
var _full := PackedByteArray()  # 1 while the entry runs at full rate
var _phase := 0.0


func _init() -> void:
	name = NODE_NAME
	process_priority = -10


## The manager of `viewport` (made and added on first use).
static func for_viewport(viewport: Viewport) -> TokenAnimationLod:
	var lod := _of(viewport)
	if lod == null:
		lod = TokenAnimationLod.new()
		viewport.set_meta(META, lod)
		viewport.add_child.call_deferred(lod)
	return lod


## Takes over `mixer` (the token's AnimationTree) and `sources` (the players it reads, which
## play nothing themselves); `token` decides its rate (null: idle rules only).
func register(mixer: AnimationMixer, token: BoardToken, sources: Array = []) -> void:
	if _mixers.has(mixer):
		return
	_mixers.append(mixer)
	_sources.append(sources)
	_tokens.append(token)
	# The golden-ratio sequence spreads the phases evenly whatever the count.
	_phase = fmod(_phase + 0.618034, 1.0)
	_since.append(_phase / IDLE_HZ)
	_full_until.append(0)
	_full.append(0)
	_set_manual(_mixers.size() - 1, enabled)


## Hands `mixer` back its own processing and forgets it.
func unregister(mixer: AnimationMixer) -> void:
	var i := _mixers.find(mixer)
	if i < 0:
		return
	_set_manual(i, false)
	_mixers.remove_at(i)
	_sources.remove_at(i)
	_tokens.remove_at(i)
	_since.remove_at(i)
	_full_until.remove_at(i)
	_full.remove_at(i)


## Full rate for `mixer` for FULL_HOLD_S from now (a state change), from the next frame.
func touch(mixer: AnimationMixer) -> void:
	var i := _mixers.find(mixer)
	if i >= 0:
		_full_until[i] = Time.get_ticks_msec() + int(FULL_HOLD_S * 1000.0)
		_full[i] = 1


## The number of mixers managed (tests, probes).
func count() -> int:
	return _mixers.size()


## Turns the level of detail on or off for every manager under `tree` (and new ones).
static func set_enabled(on: bool, tree: SceneTree) -> void:
	enabled = on
	if tree == null:
		return
	for viewport in _viewports(tree.root):
		var lod := _of(viewport)
		if lod != null:
			for i in lod._mixers.size():
				lod._set_manual(i, on)


## The viewport's live manager, or null (a null meta default still errors, so has_meta first).
static func _of(viewport: Viewport) -> TokenAnimationLod:
	if not viewport.has_meta(META):
		return null
	var lod: Variant = viewport.get_meta(META)
	return lod as TokenAnimationLod if is_instance_valid(lod) else null


static func _viewports(node: Node) -> Array[Viewport]:
	var out: Array[Viewport] = []
	if node is Viewport:
		out.append(node as Viewport)
	for child in node.get_children():
		out.append_array(_viewports(child))
	return out


func _process(delta: float) -> void:
	if enabled:
		step(delta, get_viewport().get_camera_3d() if is_inside_tree() else null)


## Advances the managed mixers for a frame of `delta` seen through `camera` (null: every token
## counts as on screen). Returns how many stepped (tests, probes).
func step(delta: float, camera: Camera3D) -> int:
	var period := 1.0 / IDLE_HZ
	var now := Time.get_ticks_msec()
	var planes: Array[Plane] = []
	var stepped := 0
	for i in _mixers.size():
		var since := _since[i] + delta
		# An idle token is looked at only when due: step when the next frame would overshoot
		# the period by more than half a frame, so 60 fps steps every second frame rather than
		# every third. Whether it should run at full rate is asked then (a hover or a drag
		# starts at most one period late), and every frame while it does.
		if _full[i] == 0 and since + delta * 0.5 < period:
			_since[i] = since
			continue
		var mixer := _mixers[i]
		if not is_instance_valid(mixer):
			continue
		var full := _full_until[i] > now or _wants_full(_tokens[i])
		_full[i] = 1 if full else 0
		if not full and camera != null:
			if planes.is_empty():
				planes = camera.get_frustum()
			if not _on_screen(mixer, _tokens[i], planes):
				_since[i] = 0.0
				continue
		mixer.advance(since)
		_since[i] = 0.0
		stepped += 1
	return stepped


static func _wants_full(token: BoardToken) -> bool:
	if token == null or not is_instance_valid(token):
		return false
	if token.is_highlighted:
		return true
	var drag := token.get_dragging_object()
	return drag != null and drag.is_being_dragged()


static func _on_screen(mixer: AnimationMixer, token: BoardToken, planes: Array[Plane]) -> bool:
	var at: Vector3
	if token != null and is_instance_valid(token) and token.rigid_body != null:
		at = token.rigid_body.global_position
	else:
		var parent := mixer.get_parent() as Node3D
		if parent == null or not parent.is_inside_tree():
			return true
		at = parent.global_position
	for plane in planes:
		if plane.distance_to(at) > CULL_RADIUS_M:
			return false
	return true


func _set_manual(i: int, manual: bool) -> void:
	var mode := (
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if manual
		else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	)
	if is_instance_valid(_mixers[i]):
		_mixers[i].callback_mode_process = mode
	for source in _sources[i]:
		if is_instance_valid(source):
			(source as AnimationMixer).callback_mode_process = mode
