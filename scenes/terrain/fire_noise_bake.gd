class_name FireNoiseBake
extends Node

## The ground fire's broad noise fields, baked (card F4b-3; docs/PERFORMANCE.md "Fire (F4)").
## The ground's fire term (fire_glow.gdshaderinc) evaluated about 45 value noises a burning pixel
## and cost about 1.5 ms at the home zoom over a third of a 200 ft map. Its broad fields (the mask
## read's warp, the char's edge, the dried band's width, the char's drift and blotches, the ash,
## the breathing's phase) are a pure function of map-frame XZ, so FireField has them worked out
## once per map on the GPU: a 2D SubViewport running fire_glow_bake.gdshader, rendered once, two
## halves side by side (glow_fields_a and glow_fields_b of fire_glow_noise.gdshaderinc), one
## texel every 1 / TEXELS_PER_M metres over the map and MARGIN_M round it. The ground reads them
## with two filtered fetches (FireLook.bind_glow binds the texture and its frame once it is
## drawn, `baked`). The finer fields stay in the shader: at this spacing they would move.

## Emitted once the bake has been drawn (its texture holds the fields).
signal baked

const SHADER := preload("res://shaders/fire_glow_bake.gdshader")
const NODE_NAME := "FireNoiseBake"
const TEXELS_PER_M := 8.0
const MARGIN_M := 1.0
## Texels a half spans at most (a larger map gets a coarser bake) and at least.
const MAX_PX := 2048
const MIN_PX := 16

var _viewport: SubViewport = null
var _rect := Vector4.ZERO
var _drawn := false
var _pending := false


func _init() -> void:
	name = NODE_NAME


## One half's size in texels for a map of extent `extent` (metres). Pure.
static func half_size(extent: Vector2) -> Vector2i:
	var span := extent + Vector2.ONE * MARGIN_M * 2.0
	return Vector2i(
		clampi(ceili(span.x * TEXELS_PER_M), MIN_PX, MAX_PX),
		clampi(ceili(span.y * TEXELS_PER_M), MIN_PX, MAX_PX)
	)


## One half's frame for a map of extent `extent` centred on the origin: the map-frame XZ of its
## corner and its size in metres (whole texels of the map's own spacing, or coarser past
## MAX_PX), centred on the map. Pure.
static func rect_for(extent: Vector2) -> Vector4:
	var size := half_size(extent)
	var span := extent + Vector2.ONE * MARGIN_M * 2.0
	var metres := Vector2(size) / TEXELS_PER_M
	metres.x = span.x if size.x == MAX_PX else metres.x
	metres.y = span.y if size.y == MAX_PX else metres.y
	return Vector4(-metres.x * 0.5, -metres.y * 0.5, metres.x, metres.y)


## Bakes the fields for a map of extent `extent` (metres); `baked` follows once it is drawn.
func bake(extent: Vector2) -> void:
	_rect = rect_for(extent)
	var size := half_size(extent)
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "Bake"
		_viewport.disable_3d = true
		_viewport.transparent_bg = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var fill := ColorRect.new()
		fill.name = "Rect"
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		fill.material = mat
		_viewport.add_child(fill)
		add_child(_viewport)
	_viewport.size = Vector2i(size.x * 2, size.y)
	var rect := _viewport.get_node("Rect") as ColorRect
	rect.position = Vector2.ZERO
	rect.size = Vector2(_viewport.size)
	(rect.material as ShaderMaterial).set_shader_parameter("rect", _rect)
	_drawn = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_await_draw()


## The baked fields (null until drawn).
func texture() -> Texture2D:
	return _viewport.get_texture() if _drawn and _viewport != null else null


## One half's frame (see rect_for).
func rect() -> Vector4:
	return _rect


func _enter_tree() -> void:
	if _pending:
		_pending = false
		if _viewport != null:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_await_draw()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_drawn)


func _await_draw() -> void:
	if not is_inside_tree():
		_pending = true
		return
	if not RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)


func _on_drawn() -> void:
	_drawn = true
	baked.emit()
