class_name FireNoiseBake
extends Node

## The ground fire's bake (cards F4b-3, F4b-4 and ground-cost; docs/PERFORMANCE.md "Fire
## (F4)"). The ground's fire term (fire_glow.gdshaderinc) once evaluated about 45 value noises,
## nine mask taps and two B-spline reads a burning pixel. Everything of it that does not change
## with time is a function of map-frame XZ, the fire mask and the flames' rasters, so it is
## worked out on the GPU into one texture, the sim bake, that the ground reads with one fetch
## where nothing burns and two where it does, and no noise:
##   - one 2D SubViewport (fire_ground_bake.gdshader) over the map and MARGIN_M round it, two
##     RGBA8 tiles side by side at SIM_PER_M: the albedo terms (the char's weight, the dried
##     band's mix, the scorch, the char's tone) and the glow terms (the glow before its
##     breathing, stored as its square root, and the breathing's phase);
##   - each texel works out the static fields (the burn, the dried band, the char's colour
##     weights, the ash, the pools, the crowding, the cracks' strength) from the mask, the
##     rasters and the broad noise, and the fine noise (tufts, lobes, coal lumps, cracks) inline,
##     then the ground's terms from them (fire_sim_bake), so the cracks and coal lumps are
##     thresholded before the bake and need the fine noise's spacing, 16 texels a metre.
## Drawn whole once (UPDATE_ONCE) and then, as strokes land, only over the rectangle a refresh
## reaches (rebake; the viewport is never cleared). FireField makes one with the first fire
## mask, hands it the mask and the rasters (set_inputs) and binds the texture once it is drawn
## (`baked`).

## Emitted once the bake has been drawn whole (its texture holds the terms).
signal baked

const SHADER := preload("res://shaders/fire_ground_bake.gdshader")
const NODE_NAME := "FireNoiseBake"
## Texels a metre (card ground-cost: the cracks' and coal lumps' edges stay crisp, no texel
## steps at the pools' edges).
const SIM_PER_M := 16.0
const MARGIN_M := 1.0
## The tiles, side by side: the albedo terms, then the glow terms.
const TILES := 2
## Texels a side spans at most (a larger map gets a coarser bake) and at least.
const MAX_PX := 2048
const MIN_PX := 16

var _bake: SubViewport = null
var _rect := Vector4.ZERO
var _tile := Vector2i.ZERO
var _drawn := false
var _pending := false
## Whether the next draw must cover the bake whole.
var _whole := true
## The rectangle to redraw at the next draw (texels of one tile), if any.
var _dirty := Rect2i()


func _init() -> void:
	name = NODE_NAME


## One side's size in texels at `per_m` texels a metre for a map of extent `extent` (metres).
## Pure.
static func tile_size(extent: Vector2, per_m: float) -> Vector2i:
	var span := extent + Vector2.ONE * MARGIN_M * 2.0
	return Vector2i(
		clampi(ceili(span.x * per_m), MIN_PX, MAX_PX), clampi(ceili(span.y * per_m), MIN_PX, MAX_PX)
	)


## A bake's frame at `per_m` texels a metre for a map of extent `extent` centred on the origin:
## the map-frame XZ of its corner and its size in metres (whole texels of that spacing, or
## coarser past MAX_PX), centred on the map. Pure.
static func rect_for(extent: Vector2, per_m: float) -> Vector4:
	var size := tile_size(extent, per_m)
	var span := extent + Vector2.ONE * MARGIN_M * 2.0
	var metres := Vector2(size) / per_m
	metres.x = span.x if size.x == MAX_PX else metres.x
	metres.y = span.y if size.y == MAX_PX else metres.y
	return Vector4(-metres.x * 0.5, -metres.y * 0.5, metres.x, metres.y)


## The texels of a tile `size` texels over frame `frame` (rect_for) that document region
## `region` (map-frame metres) touches, within the tile. Pure.
static func texels_of(region: Rect2, frame: Vector4, size: Vector2i) -> Rect2i:
	var per := Vector2(size) / Vector2(frame.z, frame.w)
	var lo := ((region.position - Vector2(frame.x, frame.y)) * per).floor()
	var hi := ((region.end - Vector2(frame.x, frame.y)) * per).ceil()
	var box := Rect2i(Vector2i(lo), Vector2i(hi - lo))
	return box.intersection(Rect2i(Vector2i.ZERO, size))


## Bakes for a map of extent `extent` (metres); `baked` follows once it is drawn whole.
func bake(extent: Vector2) -> void:
	_rect = rect_for(extent, SIM_PER_M)
	_tile = tile_size(extent, SIM_PER_M)
	if _bake == null:
		_bake = SubViewport.new()
		_bake.name = "Sim"
		_bake.disable_3d = true
		_bake.transparent_bg = true
		_bake.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_bake.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		for k in TILES:
			var fill := ColorRect.new()
			fill.name = "Rect%d" % k
			fill.material = mat
			_bake.add_child(fill)
		add_child(_bake)
	_bake.size = Vector2i(_tile.x * TILES, _tile.y)
	var mat := _material()
	mat.set_shader_parameter("rect", _rect)
	mat.set_shader_parameter("tile_px", _tile)
	_drawn = false
	_whole = true
	_dirty = Rect2i(Vector2i.ZERO, _tile)
	_redraw()


## The bake's inputs: the fire mask `mask` on the document's sample grid (its first sample at
## `origin`, `step` metres apart) and the flames' rasters `heat` (FireField). A new texture
## redraws the bake whole.
func set_inputs(mask: Texture2D, heat: Texture2D, origin: Vector2, step: Vector2) -> void:
	var mat := _material()
	if mat == null:
		return
	var changed: bool = (
		mat.get_shader_parameter("fire_mask_map") != mask
		or mat.get_shader_parameter("fire_heat_map") != heat
	)
	mat.set_shader_parameter("fire_mask_map", mask)
	mat.set_shader_parameter("fire_heat_map", heat)
	mat.set_shader_parameter("grid_origin", origin)
	mat.set_shader_parameter("grid_step", step)
	mat.set_shader_parameter("fire_heat_step", FireField.HEAT_STEP_M)
	if changed:
		_whole = true
		_dirty = Rect2i(Vector2i.ZERO, _tile)
		_redraw()


## Redraws the bake over document region `region` (map-frame metres) at the next draw (after
## its inputs changed there).
func rebake(region: Rect2) -> void:
	if _bake == null:
		return
	var box := texels_of(region, _rect, _tile)
	if not box.has_area():
		return
	_dirty = box if not _dirty.has_area() else _dirty.merge(box)
	_redraw()


## The bake's texture (null until drawn whole) and one tile's frame (see rect_for).
func sim_texture() -> Texture2D:
	return _bake.get_texture() if _drawn and _bake != null else null


func sim_rect() -> Vector4:
	return _rect


## Bytes of video memory the bake takes (RGBA8; 0 before the first bake).
func memory_bytes() -> int:
	if _bake == null:
		return 0
	return _bake.size.x * _bake.size.y * 4


func _material() -> ShaderMaterial:
	if _bake == null:
		return null
	return (_bake.get_node("Rect0") as ColorRect).material as ShaderMaterial


## Places rect `k` over texels `box` of tile `k`.
func _fit(k: int, box: Rect2i) -> void:
	var fill := _bake.get_node("Rect%d" % k) as ColorRect
	fill.position = Vector2(box.position + Vector2i(_tile.x * k, 0))
	fill.size = Vector2(box.size)


func _redraw() -> void:
	var box := Rect2i(Vector2i.ZERO, _tile) if _whole else _dirty
	for k in TILES:
		_fit(k, box)
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	_await_draw()


func _enter_tree() -> void:
	if _pending:
		_pending = false
		if _bake != null:
			_redraw()


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
	_dirty = Rect2i()
	var first := not _drawn
	_whole = false
	_drawn = true
	if first:
		baked.emit()
