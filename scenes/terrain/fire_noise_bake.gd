class_name FireNoiseBake
extends Node

## The ground fire's bakes (cards F4b-3 and F4b-4; docs/PERFORMANCE.md "Fire (F4)"). The
## ground's fire term (fire_glow.gdshaderinc) once evaluated about 45 value noises, nine mask
## taps and two B-spline reads a burning pixel. Everything of it that does not change with time
## is a function of map-frame XZ, the fire mask and the flames' rasters, so it is worked out on
## the GPU into two textures the ground reads with one fetch where nothing burns and four where
## it does:
##   - the fine noise (fire_glow_bake.gdshader: the dried band's tufts, the glow's lobes, the
##     coal lumps, the cracks), a pure function of XZ, drawn once per map at fine_per_m;
##   - the static bake (fire_ground_bake.gdshader: three tiles side by side, the burn, the
##     dried band, the char's colour weights, the ash, the pools, the crowding, the cracks'
##     strength and the breathing's phase), drawn whole once and then, as strokes land, only
##     over the rectangle a refresh reaches (rebake; the viewport is never cleared), at
##     static_per_m.
## Each is a 2D SubViewport rendered on demand (UPDATE_ONCE), over the map and MARGIN_M round
## it. FireField makes one with the first fire mask, hands it the mask and the rasters
## (set_inputs) and binds the textures once they are drawn (`baked`).

## Emitted once a whole bake has been drawn (its textures hold the fields).
signal baked

const FINE_SHADER := preload("res://shaders/fire_glow_bake.gdshader")
const STATIC_SHADER := preload("res://shaders/fire_ground_bake.gdshader")
const NODE_NAME := "FireNoiseBake"
## Texels a metre of the static bake (its fields are as smooth as the mask's B-spline and the
## broad noise) and of the fine noise (the cracks and coal lumps are 5 to 10 cm across). Chosen by
## pixel diff against per-pixel evaluation (card F4b-4; docs/PERFORMANCE.md).
const STATIC_PER_M := 8.0
const FINE_PER_M := 16.0
const MARGIN_M := 1.0
## The static bake's tiles, side by side.
const TILES := 3
## Texels a side spans at most (a larger map gets a coarser bake) and at least.
const MAX_PX := 2048
const MIN_PX := 16

## The spacings in use (probes may change them before bake()).
var static_per_m := STATIC_PER_M
var fine_per_m := FINE_PER_M

var _fine: SubViewport = null
var _static: SubViewport = null
var _fine_rect := Vector4.ZERO
var _static_rect := Vector4.ZERO
var _tile := Vector2i.ZERO
var _drawn := false
var _pending := false
## Whether the next draw of the static bake must cover it whole.
var _whole := true
## The static bake's rectangle to redraw at the next draw (texels of one tile), if any.
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


## Bakes both for a map of extent `extent` (metres); `baked` follows once they are drawn.
func bake(extent: Vector2) -> void:
	_fine_rect = rect_for(extent, fine_per_m)
	_static_rect = rect_for(extent, static_per_m)
	_tile = tile_size(extent, static_per_m)
	if _fine == null:
		_fine = _viewport("Fine", FINE_SHADER, 1)
		_static = _viewport("Static", STATIC_SHADER, TILES)
		_static.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_fine.size = tile_size(extent, fine_per_m)
	_fit(_fine, 0, Rect2i(Vector2i.ZERO, _fine.size), _fine.size)
	(_fine.get_node("Rect0").material as ShaderMaterial).set_shader_parameter("rect", _fine_rect)
	_static.size = Vector2i(_tile.x * TILES, _tile.y)
	var mat := _static_material()
	mat.set_shader_parameter("rect", _static_rect)
	mat.set_shader_parameter("tile_px", _tile)
	_drawn = false
	_whole = true
	_dirty = Rect2i(Vector2i.ZERO, _tile)
	_fine.render_target_update_mode = SubViewport.UPDATE_ONCE
	_redraw_static()


## The static bake's inputs: the fire mask `mask` on the document's sample grid (its first
## sample at `origin`, `step` metres apart) and the flames' rasters `heat` (FireField). A new
## texture redraws the bake whole.
func set_inputs(mask: Texture2D, heat: Texture2D, origin: Vector2, step: Vector2) -> void:
	var mat := _static_material()
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
		_redraw_static()


## Redraws the static bake over document region `region` (map-frame metres) at the next draw
## (after its inputs changed there).
func rebake(region: Rect2) -> void:
	if _static == null:
		return
	var box := texels_of(region, _static_rect, _tile)
	if not box.has_area():
		return
	_dirty = box if not _dirty.has_area() else _dirty.merge(box)
	_redraw_static()


## The static bake's texture and the fine noise's (null until drawn).
func static_texture() -> Texture2D:
	return _static.get_texture() if _drawn and _static != null else null


func fine_texture() -> Texture2D:
	return _fine.get_texture() if _drawn and _fine != null else null


## The static bake's frame (one tile's; see rect_for) and the fine noise's.
func static_rect() -> Vector4:
	return _static_rect


func fine_rect() -> Vector4:
	return _fine_rect


## Bytes of video memory the two bakes take (RGBA8).
func memory_bytes() -> int:
	if _fine == null:
		return 0
	return (_fine.size.x * _fine.size.y + _static.size.x * _static.size.y) * 4


func _viewport(label: String, shader: Shader, rects: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for k in rects:
		var fill := ColorRect.new()
		fill.name = "Rect%d" % k
		fill.material = mat
		viewport.add_child(fill)
	add_child(viewport)
	return viewport


func _static_material() -> ShaderMaterial:
	if _static == null:
		return null
	return (_static.get_node("Rect0") as ColorRect).material as ShaderMaterial


## Places rect `k` of `viewport` over texels `box` of tile `k` (tiles `tile` texels).
static func _fit(viewport: SubViewport, k: int, box: Rect2i, tile: Vector2i) -> void:
	var fill := viewport.get_node("Rect%d" % k) as ColorRect
	fill.position = Vector2(box.position + Vector2i(tile.x * k, 0))
	fill.size = Vector2(box.size)


func _redraw_static() -> void:
	var box := Rect2i(Vector2i.ZERO, _tile) if _whole else _dirty
	for k in TILES:
		_fit(_static, k, box, _tile)
	_static.render_target_update_mode = SubViewport.UPDATE_ONCE
	_await_draw()


func _enter_tree() -> void:
	if _pending:
		_pending = false
		if _fine != null:
			_fine.render_target_update_mode = SubViewport.UPDATE_ONCE
			_redraw_static()


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
