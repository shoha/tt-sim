class_name BackdropLayout
extends RefCounted

## Where a screen's paper covers the painted backdrop (PaintedBackdrop), so the painting can
## put its sun, clouds and poplars in the sky and on the crest the screen leaves open
## (BackdropPaint.compose). The canvas is a grid of cells about a seventy-second of its height
## (15 px at 1080), each covered or open; a cell is covered when any paper (a sheet, a plaque,
## a card, a button) comes within MARGIN of it. Prefix sums answer "is this rect open" at once,
## and the largest open square is found in one pass.

## How close paper may come to a shape in the sky, in pixels.
const MARGIN := 12.0
## A cell's size as a share of the canvas height, and its least size in pixels.
const CELL_SHARE := 1.0 / 72.0
const CELL_MIN := 6.0
## No scroll view clips the walk yet.
const NO_CLIP := Rect2(-1e7, -1e7, 2e7, 2e7)

var size: Vector2
var _cell: float
var _cols: int
var _rows: int
## Covered cells summed over every rect from the top-left: (cols + 1) x (rows + 1).
var _sum := PackedInt32Array()


## A layout of `canvas` pixels with `paper` (rects in the same pixels) over it.
func _init(canvas: Vector2, paper: Array[Rect2]) -> void:
	size = canvas
	_cell = maxf(canvas.y * CELL_SHARE, CELL_MIN)
	_cols = maxi(ceili(canvas.x / _cell), 1)
	_rows = maxi(ceili(canvas.y / _cell), 1)
	var covered := PackedByteArray()
	covered.resize(_cols * _rows)
	covered.fill(0)
	for rect in paper:
		var grown := rect.grow(MARGIN)
		var c0 := clampi(floori(grown.position.x / _cell), 0, _cols)
		var c1 := clampi(ceili(grown.end.x / _cell), 0, _cols)
		var r0 := clampi(floori(grown.position.y / _cell), 0, _rows)
		var r1 := clampi(ceili(grown.end.y / _cell), 0, _rows)
		for r in range(r0, r1):
			for c in range(c0, c1):
				covered[r * _cols + c] = 1
	var stride := _cols + 1
	_sum.resize(stride * (_rows + 1))
	_sum.fill(0)
	for r in _rows:
		var run := 0
		for c in _cols:
			run += covered[r * _cols + c]
			_sum[(r + 1) * stride + c + 1] = _sum[r * stride + c + 1] + run


## A cell's size in pixels.
func cell() -> float:
	return _cell


## Whether no paper covers `rect` (pixels). Parts past the canvas count as open.
func is_open(rect: Rect2) -> bool:
	var c0 := clampi(floori(rect.position.x / _cell), 0, _cols)
	var c1 := clampi(ceili(rect.end.x / _cell), 0, _cols)
	var r0 := clampi(floori(rect.position.y / _cell), 0, _rows)
	var r1 := clampi(ceili(rect.end.y / _cell), 0, _rows)
	if c1 <= c0 or r1 <= r0:
		return true
	var stride := _cols + 1
	var count := _sum[r1 * stride + c1] - _sum[r0 * stride + c1] - _sum[r1 * stride + c0]
	return count + _sum[r0 * stride + c0] == 0


## The largest open square above `floor_y` (pixels from the top), in pixels; among squares
## nearly as large (within a cell or 15%), the one whose centre is nearest `toward`. Empty when
## the paper covers it all.
func largest_square(floor_y: float, toward: Vector2) -> Rect2:
	var rows := clampi(floori(floor_y / _cell), 0, _rows)
	var stride := _cols + 1
	var side := PackedInt32Array()
	side.resize(_cols * rows)
	var best := 0
	for r in rows:
		for c in _cols:
			var open := _sum[(r + 1) * stride + c + 1] - _sum[r * stride + c + 1]
			open -= _sum[(r + 1) * stride + c] - _sum[r * stride + c]
			var s := 0
			if open == 0:
				s = 1
				if r > 0 and c > 0:
					var up := side[(r - 1) * _cols + c]
					var left := side[r * _cols + c - 1]
					s += mini(mini(up, left), side[(r - 1) * _cols + c - 1])
			side[r * _cols + c] = s
			best = maxi(best, s)
	if best == 0:
		return Rect2()
	var enough := mini(best - 1, ceili(best * 0.85))
	enough = maxi(enough, 1)
	var chosen := Rect2()
	var nearest := INF
	for r in rows:
		for c in _cols:
			var s := side[r * _cols + c]
			if s < enough:
				continue
			var square := Rect2((c - s + 1) * _cell, (r - s + 1) * _cell, s * _cell, s * _cell)
			var distance := square.get_center().distance_squared_to(toward) - s * s * _cell * _cell
			if distance < nearest:
				nearest = distance
				chosen = square
	return chosen


## The rects of the paper under `root` (a screen's CanvasLayer or a control): every visible
## control that draws an opaque fill (a sheet, a plaque, a card, a filled button) or a picture,
## clipped by the scroll view it sits in. A paper's children stand on it, so they are not
## walked.
static func paper_of(root: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	_collect(root, NO_CLIP, rects)
	return rects


static func _collect(node: Node, clip: Rect2, rects: Array[Rect2]) -> void:
	for child in node.get_children():
		var control := child as Control
		if control == null or not control.visible or control is PaintedBackdrop:
			continue
		var rect := control.get_global_rect()
		if _is_paper(control):
			var shown := rect.intersection(clip)
			if shown.has_area():
				rects.append(shown)
			continue
		_collect(control, clip.intersection(rect) if control is ScrollContainer else clip, rects)


## Whether `control` draws paper (or a picture) over the painting.
static func _is_paper(control: Control) -> bool:
	if control is TextureRect:
		return (control as TextureRect).texture != null
	var style: StyleBox = null
	if control is Button:
		var button := control as Button
		if button.flat:
			return false
		style = button.get_theme_stylebox(&"normal")
	elif control is PanelContainer or control is Panel:
		style = control.get_theme_stylebox(&"panel")
	if style is StyleBoxFlat:
		var flat := style as StyleBoxFlat
		return flat.draw_center and flat.bg_color.a >= 0.5
	return style is StyleBoxTexture
