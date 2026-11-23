extends GutTest

## TokenAnimationLod (perf audit F-tokens-3): managed mixers go manual, idle on-screen ones step
## at IDLE_HZ with the time conserved, off-screen ones hold, a touched one runs every frame, and
## turning the level of detail off hands the mixers back their own processing.

const FRAME := 1.0 / 60.0

var _root: Node3D
var _lod: TokenAnimationLod
var _camera: Camera3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_lod = TokenAnimationLod.new()
	_root.add_child(_lod)
	_camera = Camera3D.new()
	_root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 10, 10), Vector3.ZERO)


func after_each() -> void:
	TokenAnimationLod.enabled = true


## An AnimationPlayer playing a 4 s clip (Target's x from `x0` to 4) on a Node3D at `at` (under
## _root), registered.
func _mixer(at: Vector3, x0: float = 0.0) -> AnimationPlayer:
	var holder := Node3D.new()
	_root.add_child(holder)
	holder.position = at
	var target := Node3D.new()
	target.name = "Target"
	holder.add_child(target)
	var anim := Animation.new()
	anim.length = 4.0
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, "Target:position:x")
	anim.track_insert_key(track, 0.0, x0)
	anim.track_insert_key(track, 4.0, 4.0)
	var library := AnimationLibrary.new()
	library.add_animation(&"idle", anim)
	var player := AnimationPlayer.new()
	holder.add_child(player)
	player.add_animation_library(&"", library)
	player.play(&"idle")
	_lod.register(player, null, [])
	return player


func _run(frames: int) -> int:
	var stepped := 0
	for i in frames:
		stepped += _lod.step(FRAME, _camera)
	return stepped


func test_register_makes_the_mixer_manual_and_disabling_restores_it() -> void:
	var player := _mixer(Vector3.ZERO)
	assert_eq(player.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	TokenAnimationLod.set_enabled(false, get_tree())
	# set_enabled walks the viewports' managers; this one is not registered on a viewport.
	_lod._set_manual(0, false)
	assert_eq(player.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE)
	_lod.unregister(player)
	assert_eq(_lod.count(), 0)


func test_an_idle_token_on_screen_steps_at_idle_rate_in_real_time() -> void:
	var player := _mixer(Vector3.ZERO)
	var start := player.current_animation_position
	var stepped := _run(60)
	assert_between(stepped, 29, 31, "about 30 steps in a second at 60 fps")
	var advanced := player.current_animation_position - start
	assert_almost_eq(advanced, 1.0, 1.0 / TokenAnimationLod.IDLE_HZ + 0.001, "time is conserved")


func test_idle_tokens_are_staggered() -> void:
	for i in 8:
		_mixer(Vector3(i * 0.1, 0, 0))
	var first := _lod.step(FRAME, _camera)
	assert_between(first, 1, 7, "not all on one frame (%d)" % first)


func test_an_off_screen_token_takes_one_step_then_holds_its_pose() -> void:
	var player := _mixer(Vector3(500, 0, -500))
	assert_eq(_run(60), 1, "the first step is never culled")
	var held := player.current_animation_position
	assert_eq(_run(60), 0)
	assert_eq(player.current_animation_position, held)


## Until a skeleton is posed the renderer skins it with identity matrices (the raw bind pose:
## Venusaur's vines 3.9 m out of its mouth, token-feet-patch), so a mixer is posed the moment it
## is registered, before any step and wherever it stands.
func test_a_registered_mixer_is_posed_at_once() -> void:
	var player := _mixer(Vector3(500, 0, -500), 2.0)
	var target := player.get_parent().get_node("Target") as Node3D
	assert_almost_eq(target.position.x, 2.0, 1.0e-4, "the clip's first frame, with no step")


func test_a_touched_token_steps_every_frame() -> void:
	var player := _mixer(Vector3(500, 0, -500))
	_lod.touch(player)
	assert_eq(_run(30), 30, "full rate, on screen or not")
