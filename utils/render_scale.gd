class_name RenderScale
extends RefCounted

## Render scale: how many pixels the 3D board renders, as a share (per axis) of its full
## resolution, upscaled with AMD FSR 1.0 (Settings > Graphics, per player, never networked).
##
## The model. GameMap draws the world in a SubViewport sized in output pixels (WorldView): the
## window's own pixels from 1080p up to 4K (1920x1080 at 1080p, 2560x1440 at 1440p, 3840x2160 at
## 4K), and the 1080p-class size below that, where the window shows fewer pixels than are
## rendered (a supersample of up to 2.25x at 720p). That is the full render. Before rendersize
## (2026-11-09) the viewport was sized in canvas units, so 1440p and 4K screens showed a
## 1920x1080 render enlarged by the canvas. The 2D layer (menus, text, overlays) always draws at
## the window's own resolution.
##
## A fixed choice renders that percent of the full render: viewport.scaling_3d_scale is
## percent / 100, and FSR 1.0 upscales a render under the viewport's size (its RCAS pass sharpens
## at FSR_SHARPNESS; the engine lowers the texture mip bias by log2(scale) on its own, so textures
## keep their detail). 100 % is the full render, the default: a player who cannot hold the
## frame rate on a 4K screen lowers it themselves (FSR 50 % at 4K draws 1920x1080 pixels, the
## cost the game had before rendersize).
##
## Auto renders no more pixels than the screen shows: the full render while the window is 1080p
## or larger, and the window's own size below it. When that lands within AUTO_SNAP of the
## viewport's own size Auto renders at the viewport's size instead, since an upscale pass over a
## nearly equal size costs more than the pixels it saves. GameMap re-applies it on every resize.

## The stored choice for Auto; the fixed choices are stored as their percent.
const AUTO := 0
## The full render: no scaling beyond the Interface size match.
const FULL := 100
## The Settings > Graphics choices, in menu order.
const CHOICES: Array[int] = [AUTO, 100, 85, 75, 67, 50]
## The choice for a player with no saved one.
const DEFAULT := FULL
## The settings file key, in the [graphics] section.
const KEY := "render_scale"
## Auto renders at the viewport's own size when its scale lands in [AUTO_SNAP, 1).
const AUTO_SNAP := 0.9
## The upscaler for a render under the viewport's size. FSR 1.0 costs about 0.07 ms more than
## bilinear at 0.75 on an RTX 3080 and keeps edges crisper (docs/PERFORMANCE.md "Render scale").
const UPSCALER := Viewport.SCALING_3D_MODE_FSR
## FSR 1.0's RCAS sharpening, in stops: 0 is the sharpest, 2 the softest (engine default 0.2).
const FSR_SHARPNESS := 0.2

## The applied choice. Root sets it from the settings file at startup, Settings sets it on
## Apply, and GameMap reads it whenever it sizes its world render.
static var current: int = DEFAULT


## [param choice] if it is one of CHOICES, else DEFAULT (a hand-edited or stale value).
static func sanitize(choice: int) -> int:
	return choice if CHOICES.has(choice) else DEFAULT


## The saved choice in a loaded settings file (DEFAULT when absent or not a known choice).
static func stored(config: ConfigFile) -> int:
	var value: Variant = config.get_value("graphics", KEY, DEFAULT)
	return sanitize(int(value)) if value is int or value is float else DEFAULT


## The share of the full render (per axis) [param choice] draws on a window of
## [param window_size] whose base canvas is [param base].
static func fraction_for(
	choice: int, window_size: Vector2, base: Vector2 = InterfaceSize.BASE_SIZE
) -> float:
	var picked := sanitize(choice)
	if picked == AUTO:
		return minf(1.0, InterfaceSize.window_scale(window_size, base))
	return picked / 100.0


## The world viewport's scaling_3d_scale for [param choice]: the share of the full render (the
## viewport itself is already sized in output pixels, WorldView).
static func scale_3d(
	choice: int, window_size: Vector2, base: Vector2 = InterfaceSize.BASE_SIZE
) -> float:
	var scale := fraction_for(choice, window_size, base)
	if sanitize(choice) == AUTO and scale >= AUTO_SNAP and scale < 1.0:
		return 1.0
	return scale


## The scaling_3d_mode for a viewport scale: UPSCALER under 1, bilinear at 1 (no scaling; FSR 1.0
## cannot downsample).
static func mode_for(scale: float) -> Viewport.Scaling3DMode:
	return UPSCALER if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR


## Sets [param viewport]'s 3D scale, mode and FSR sharpness for [param choice] on
## [param window] (the full render when [param window] is null); returns the scale.
static func apply_to(viewport: Viewport, window: Window, choice: int) -> float:
	var window_size := Vector2(window.size) if window else InterfaceSize.BASE_SIZE
	var base := Vector2(window.content_scale_size) if window else InterfaceSize.BASE_SIZE
	if base.x <= 0.0 or base.y <= 0.0:
		base = InterfaceSize.BASE_SIZE
	var scale := scale_3d(choice, window_size, base)
	viewport.scaling_3d_mode = mode_for(scale)
	viewport.scaling_3d_scale = scale
	viewport.fsr_sharpness = FSR_SHARPNESS
	return scale


## The Settings label for [param choice]: each choice with the render size it draws on a window
## of [param window_size] at Interface size factor [param content_factor].
static func label_for(
	choice: int,
	window_size: Vector2,
	content_factor: float = 1.0,
	base: Vector2 = InterfaceSize.BASE_SIZE
) -> String:
	var picked := sanitize(choice)
	var size := render_size(picked, window_size, content_factor, base)
	var dims := "%dx%d" % [roundi(size.x), roundi(size.y)]
	if picked == AUTO:
		return "Auto (%s here)" % dims
	return "%d%% (%s%s)" % [picked, dims, ", full" if picked == FULL else ""]


## The 3D render's size in pixels for [param choice] on a window of [param window_size]: the
## world viewport (WorldView.pixel_size) times its 3D scale.
static func render_size(
	choice: int,
	window_size: Vector2,
	content_factor: float = 1.0,
	base: Vector2 = InterfaceSize.BASE_SIZE
) -> Vector2:
	var viewport_size := Vector2(InterfaceSize.world_pixel_size(window_size, content_factor, base))
	return viewport_size * scale_3d(choice, window_size, base)


## Fills a Settings [param option] with CHOICES (item ids are the stored values), labelled for
## [param window], and selects [param choice]. Runs again when the window resizes.
static func fill_option(option: OptionButton, window: Window, choice: int) -> void:
	option.clear()
	var window_size := Vector2(window.size)
	var factor := InterfaceSize.world_render_scale(window)
	for each in CHOICES:
		option.add_item(
			label_for(each, window_size, factor, Vector2(window.content_scale_size)), each
		)
	option.select(option.get_item_index(sanitize(choice)))
