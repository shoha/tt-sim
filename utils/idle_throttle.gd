class_name IdleThrottle
extends Node

## Caps the frame rate while the game is in the background (perf audit sysidle, finding S4).
##
## An idle game ran at full rate, and a minimised one drew nothing yet still spent 0.18 to 0.23 of
## a core on its main loop (measured 2026-11, perfaudit). While the window has lost the focus the
## frame cap (Engine.max_fps) drops to UNFOCUSED_FPS, and while it is minimised to MINIMIZED_FPS;
## focus back restores the cap that stood before. Settings > Graphics > "Idle throttle" turns it
## off (a second monitor showing the table while another window has the focus).
##
## Three things never get slowed:
## - A load behind the loading sheet. LoadPacing owns the frame cap while it covers the screen
##   (it saves and restores Engine.max_fps itself): the cover calls release() before it saves and
##   reapply() after it restores, so a background load runs at full pace and the throttle takes
##   hold again when the sheet goes. The throttle never touches vsync.
## - A host with a peer. The network poll and the physics steps run once a frame (the engine
##   catches up at most 8 steps a frame, so 5 fps would run physics at two thirds speed), so a host
##   serving a client keeps at least HOSTING_FPS in either state.
## - Headless, scripted and bridge runs. A script-run main loop (render jobs, probes and the test
##   runner), a headless display and a --validation-bridge run are measured or driven by an agent
##   whose window is rarely focused; install() adds no node there.
##
## Root installs the node after the title is up. The cap policy is a pure function (cap_for) over
## the focus, the minimised state and whether a host has peers; the node feeds it from the
## application focus notifications, and polls the window mode (there is no notification for a
## minimise) and the peer list only while the window is in the background.

## The frame cap while the window is unfocused but visible.
const UNFOCUSED_FPS := 15
## The frame cap while the window is minimised: nothing is drawn, the loop only has to listen.
const MINIMIZED_FPS := 5
## The least a host with a connected peer runs at in the background.
const HOSTING_FPS := 30
## The settings file key, in the [graphics] section.
const KEY := "idle_throttle"
## On for a player with no saved choice.
const DEFAULT := true

## The player's setting (Settings > Graphics). False leaves the frame cap alone.
static var enabled := DEFAULT
## Whether the window has the focus. Starts true; the node reads the real state when it enters.
static var focused := true
## Whether the window is minimised (only tracked while unfocused).
static var minimized := false
## A probe that runs as a script and wants the real throttle sets this before install().
static var allow_scripted := false
## Engine.max_fps before the throttle lowered it; -1 while the throttle holds no cap.
static var _base_fps := -1


## Adds the throttle node under [param parent] unless this run is headless, scripted or driven by
## the validation bridge. Returns the node, or null when none was added.
static func install(parent: Node) -> IdleThrottle:
	if not runs_here():
		return null
	var node := IdleThrottle.new()
	node.name = "IdleThrottle"
	parent.add_child(node)
	return node


## Whether the throttle belongs to this run (a player's window).
static func runs_here() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if "--validation-bridge" in OS.get_cmdline_user_args():
		return false
	var loop := Engine.get_main_loop()
	return allow_scripted or (loop != null and loop.get_script() == null)


## The player's saved choice in a loaded settings file (DEFAULT when absent or not a bool).
static func stored(config: ConfigFile) -> bool:
	var value: Variant = config.get_value("graphics", KEY, DEFAULT)
	return bool(value) if value is bool else DEFAULT


## The cap for a window in the given state, 0 for none. A host with a peer keeps HOSTING_FPS.
static func cap_for(
	is_enabled: bool, has_focus: bool, is_minimized: bool, hosting_peers: bool
) -> int:
	if not is_enabled or has_focus:
		return 0
	var cap := MINIMIZED_FPS if is_minimized else UNFOCUSED_FPS
	return maxi(cap, HOSTING_FPS) if hosting_peers else cap


## Turns the throttle on or off at once (Settings).
static func set_enabled(value: bool) -> void:
	enabled = value
	reapply()


## Puts the frame cap that stood before the throttle back. LoadPacing calls it as a cover begins,
## so it saves the player's cap and not the throttled one.
static func release() -> void:
	_set_cap(0)


## Applies the cap for the current state, unless a load sheet is up (LoadPacing owns the cap then
## and calls this again as the sheet goes).
static func reapply() -> void:
	if LoadPacing.is_covered():
		return
	_set_cap(cap_for(enabled, focused, minimized, _hosting_peers()))


## The cap the throttle holds now, 0 when none.
static func held_cap() -> int:
	return Engine.max_fps if _base_fps >= 0 else 0


static func _set_cap(cap: int) -> void:
	if cap <= 0:
		if _base_fps >= 0:
			Engine.max_fps = _base_fps
			_base_fps = -1
		return
	if _base_fps < 0:
		_base_fps = Engine.max_fps
	Engine.max_fps = cap if _base_fps == 0 else mini(cap, _base_fps)


## Whether this process hosts a session with at least one peer connected.
static func _hosting_peers() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var net := tree.get_multiplayer()
	return net.has_multiplayer_peer() and net.is_server() and not net.get_peers().is_empty()


func _enter_tree() -> void:
	focused = DisplayServer.window_is_focused()
	minimized = false
	set_process(not focused)
	reapply()


func _exit_tree() -> void:
	focused = true
	minimized = false
	release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		set_process(true)
		_refresh()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
		minimized = false
		set_process(false)
		reapply()


func _process(_delta: float) -> void:
	_refresh()


## Reads the minimised state and re-applies the cap when it, or the host's peers, changed.
func _refresh() -> void:
	minimized = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	reapply()
