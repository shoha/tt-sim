class_name InterfaceSize
extends RefCounted

## Interface size: how large the Control layer draws, set as the root window's
## content_scale_factor. Every screen is laid out on a 1920x1080 canvas (project.godot:
## stretch mode canvas_items, aspect expand), and a smaller window shrinks that whole canvas
## with it, so at 1280x720 a 14 px caption drew at 9 px. A factor f shrinks the virtual canvas
## instead: the window holds base / f of it (1371x771 at 1.40), and the UI draws f times
## larger.
##
## Auto, the default, picks the least factor in 0.05 steps that draws a 14 px caption at 13
## physical px or more (UI_TASTE T2), between 1.0 and 1.5: 1.40 at 720p, 1.15 at 900p, 1.0
## from 1080p up. The step rounds up, not to the nearest, because the nearest (1.10 at 900p)
## leaves captions at 12.8 px. A player may pick a fixed size instead, 90% to 150%, which
## replaces Auto rather than multiplying it: a percent then means the same factor on every
## window, and nothing can pass MAX_FACTOR. 1.5 keeps the virtual canvas at 1280x720 or more on
## any window, the canvas every screen must fit (test_interface_size_fit.gd).
##
## Only the canvas scales. The board renders at its 100% size (GameMap scales its world
## viewport's 3D render back up by the factor, world_render_scale), so the camera's framing,
## the render resolution and pixel-sized 3D details such as grid lines are unchanged. Overlays
## drawn on the canvas over the board (measure labels, gizmo handles) are UI and follow it.
##
## Per user and never networked: saved in the settings file's [ui] section (UiPreferences);
## UIManager applies it at startup, on every window resize and when Settings changes it.

## The stored choice for Auto; the fixed sizes are stored as their percent.
const AUTO := 0
## The Settings > Graphics choices, in menu order.
const CHOICES: Array[int] = [AUTO, 90, 100, 110, 120, 130, 140, 150]
const MIN_FACTOR := 1.0
const MAX_FACTOR := 1.5
const STEP := 0.05
## The caption role's size and the least it may draw at on screen (UI_TASTE T1, T2).
const CAPTION_PX := 14.0
const CAPTION_FLOOR_PX := 13.0
## Rounding slack, in steps: a factor that is a whole number of steps up to float error stays.
const SNAP_SLACK := 0.001
## The canvas every screen is laid out on, when no window says otherwise.
const BASE_SIZE := Vector2(1920.0, 1080.0)


## How much the stretch scales the base canvas onto a window of `window_size` at factor 1:
## the smaller of the two axis ratios (aspect expand keeps the whole base canvas visible).
static func window_scale(window_size: Vector2, base: Vector2 = BASE_SIZE) -> float:
	if base.x <= 0.0 or base.y <= 0.0:
		return 1.0
	return minf(window_size.x / base.x, window_size.y / base.y)


## The Auto factor for a window of `window_size`: the least 0.05 step from MIN_FACTOR to
## MAX_FACTOR at which a caption draws at CAPTION_FLOOR_PX or more.
static func auto_factor(window_size: Vector2, base: Vector2 = BASE_SIZE) -> float:
	var scale := window_scale(window_size, base)
	if scale <= 0.0:
		return MIN_FACTOR
	var wanted := CAPTION_FLOOR_PX / (CAPTION_PX * scale)
	var steps := ceilf(wanted / STEP - SNAP_SLACK)
	return clampf(steps * STEP, MIN_FACTOR, MAX_FACTOR)


## `choice` if it is one of CHOICES, else AUTO (a hand-edited or stale settings value).
static func sanitize(choice: int) -> int:
	return choice if CHOICES.has(choice) else AUTO


## The content_scale_factor for `choice` on a window of `window_size`.
static func factor_for(choice: int, window_size: Vector2, base: Vector2 = BASE_SIZE) -> float:
	var picked := sanitize(choice)
	if picked == AUTO:
		return auto_factor(window_size, base)
	return picked / 100.0


## The Settings label for `choice`; Auto names the size it gives on this window.
static func label_for(choice: int, window_size: Vector2, base: Vector2 = BASE_SIZE) -> String:
	if sanitize(choice) == AUTO:
		return "Auto (%d%%)" % roundi(auto_factor(window_size, base) * 100.0)
	return "%d%%" % choice


## Fill a Settings `option` with CHOICES (item ids are the stored values), Auto naming the
## size it gives on `window`, and select `choice`.
static func fill_option(option: OptionButton, window: Window, choice: int) -> void:
	option.clear()
	for each in CHOICES:
		option.add_item(
			label_for(each, Vector2(window.size), Vector2(window.content_scale_size)), each
		)
	option.select(option.get_item_index(sanitize(choice)))


## The physical pixel size a `px` font draws at with factor `factor` on that window.
static func physical_px(
	px: float, factor: float, window_size: Vector2, base: Vector2 = BASE_SIZE
) -> float:
	return px * window_scale(window_size, base) * factor


## Set `window`'s content_scale_factor for `choice` and its current size; returns the factor.
## Leaves it alone when it already holds that factor, so a resize handler does not loop.
static func apply(window: Window, choice: int) -> float:
	var factor := factor_for(choice, Vector2(window.size), Vector2(window.content_scale_size))
	if not is_equal_approx(window.content_scale_factor, factor):
		window.content_scale_factor = factor
	return factor


## The 3D render scale that keeps a world viewport filling `window`'s canvas at its 100%
## resolution: the canvas is 1 / factor of its 100% size, so the render scales back up by it.
static func world_render_scale(window: Window) -> float:
	return window.content_scale_factor if window else 1.0
