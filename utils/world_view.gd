class_name WorldView
extends RefCounted

## How the world SubViewport is sized: in output pixels, every coordinate still in canvas units.
##
## The project stretches canvas_items on a 1920x1080 base canvas (aspect expand), so the window
## holds a canvas of V = window / (window_scale x Interface size factor) units, 1920x1080 on any
## 16:9 window at factor 1. The viewport used to be sized in those canvas units (a stretched
## SubViewportContainer), so the board rendered at 1920x1080 on a 1440p or 4K screen and the canvas
## enlarged it. Now the viewport is P = V x density pixels, where density is the render pixels per
## canvas unit: the window's own pixels per unit (window_scale x factor), but never less than the
## 1080p-class render (a window under 1080p keeps supersampling, as before) and never more than
## MAX_OUTPUT_SCALE x factor (a 5K or 8K window renders at 4K and is upscaled by the canvas).
##
## Everything that reads positions keeps working in canvas units. The viewport's 2D size override
## (size_2d_override, with the stretch flag) is V, so Viewport.get_visible_rect(), the mouse
## position, Camera3D.unproject_position and project_ray_*, physics picking and the events the
## container forwards all stay in canvas units whatever P is (checked by a probe on a 2560x1440
## window, rendersize 2026-11-09). The one thing that is no longer canvas units is Viewport.size
## itself: code that wants the screen extent in the units of mouse and unprojected positions must
## read [method canvas_size], not viewport.size.
##
## The container is not stretched: it is P units wide and scaled by V / P so that it covers the
## canvas exactly and draws the viewport texture at the window's own pixels.
##
## Effects authored in render pixels (Bayer dither cells, grid line widths, pixel floors) multiply
## by [method px_scale], P.y / 1080: unchanged at 1080p, twice as wide at 4K.

## The most render pixels per canvas unit per axis, times the Interface size factor: 2 is 4K.
const MAX_OUTPUT_SCALE := 2.0
## The height the pixel-authored effects were tuned at.
const REFERENCE_HEIGHT := 1080.0
## The global shader parameter pixel-authored effects read (project.godot [shader_globals]).
const PX_SCALE_PARAM := "world_px_scale"


## The share of the output (window pixels per base-canvas unit) the render uses: the window's
## own scale, kept in [1, MAX_OUTPUT_SCALE].
static func output_scale(window_size: Vector2, base: Vector2 = InterfaceSize.BASE_SIZE) -> float:
	return clampf(InterfaceSize.window_scale(window_size, base), 1.0, MAX_OUTPUT_SCALE)


## The canvas the window shows, in units (V).
static func canvas_units(
	window_size: Vector2, factor: float = 1.0, base: Vector2 = InterfaceSize.BASE_SIZE
) -> Vector2:
	var scale := InterfaceSize.window_scale(window_size, base)
	if scale <= 0.0 or factor <= 0.0:
		return base
	return window_size / (scale * factor)


## Render pixels per canvas unit at Interface size factor [param factor].
static func density(
	window_size: Vector2, factor: float = 1.0, base: Vector2 = InterfaceSize.BASE_SIZE
) -> float:
	return maxf(factor, 0.01) * output_scale(window_size, base)


## The world viewport's pixel size (P) for a window of [param window_size].
static func pixel_size(
	window_size: Vector2, factor: float = 1.0, base: Vector2 = InterfaceSize.BASE_SIZE
) -> Vector2i:
	var size := canvas_units(window_size, factor, base) * density(window_size, factor, base)
	return Vector2i(maxi(roundi(size.x), 1), maxi(roundi(size.y), 1))


## The multiplier for effects authored in 1080p render pixels at a viewport of height
## [param pixel_height].
static func px_scale_for(pixel_height: float) -> float:
	return maxf(pixel_height, 1.0) / REFERENCE_HEIGHT


## The screen extent of [param viewport] in the units of mouse and unprojected positions (canvas
## units): its visible rect, which the 2D size override sets. Use this where code once read
## viewport.size.
static func canvas_size(viewport: Viewport) -> Vector2:
	return viewport.get_visible_rect().size


## The pixel-authored effects' multiplier for [param viewport] (px_scale_for its pixel height).
static func px_scale(viewport: Viewport) -> float:
	return px_scale_for(float(viewport.size.y))


## Sizes [param viewport] and its [param container] for [param window]: the viewport in output
## pixels, the 2D override in canvas units, the container scaled to cover the canvas. Publishes the
## pixel scale for the shaders. Cheap to call again; leaves a viewport already right alone.
static func apply_layout(container: Control, viewport: SubViewport, window: Window) -> void:
	var window_size := Vector2(window.size)
	var base := Vector2(window.content_scale_size)
	if base.x <= 0.0 or base.y <= 0.0:
		base = InterfaceSize.BASE_SIZE
	var factor := InterfaceSize.world_render_scale(window)
	var units := canvas_units(window_size, factor, base)
	var pixels := pixel_size(window_size, factor, base)
	var override := Vector2i(units.round())
	if override == pixels:
		override = Vector2i.ZERO
	if viewport.size != pixels:
		viewport.size = pixels
	if viewport.size_2d_override != override:
		viewport.size_2d_override = override
	viewport.size_2d_override_stretch = override != Vector2i.ZERO
	container.stretch = false
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.position = Vector2.ZERO
	container.size = Vector2(pixels)
	container.scale = units / Vector2(pixels)
	RenderingServer.global_shader_parameter_set(PX_SCALE_PARAM, px_scale_for(float(pixels.y)))
